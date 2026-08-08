import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DupRuleConfigDao } from './DupRuleConfigDao';
import { LogUtil } from '../utils/LogUtil';
import { ChineseConverter } from '../utils/ChineseConverter';

/**
 * 关系型数据库单例封装，对齐安卓端 AppDatabase（v8 schema）。
 * 鸿蒙端从 v1 起即包含全部表，无需 migration：
 *   - scanned_file（含 progress/source/checked 列）
 *   - scan_config
 *   - scan_run
 *   - keyword_replace_rules
 */
export class RdbHelper {
  private static instance: RdbHelper | null = null;
  private rdbStore: relationalStore.RdbStore | null = null;
  private static readonly DB_NAME: string = 'file_scanner.db';
  /** 进行中的初始化 Promise，避免 onCreate 与 onWindowStageCreate 并发调用导致重复 init。 */
  private static pending: Promise<RdbHelper> | null = null;

  private constructor() {}

  /**
   * 初始化（或复用）单例。必须在拿到 context 后调用（EntryAbility.onCreate / onWindowStageCreate）。
   * 幂等：已就绪直接返回；并发调用复用同一个 pending Promise，避免重复 init；
   * 失败时清除单例，下次调用自动重试。
   */
  public static async getInstance(context: common.Context): Promise<RdbHelper> {
    if (RdbHelper.instance && RdbHelper.instance.isReady()) {
      return RdbHelper.instance;
    }
    // 复用进行中的初始化，避免并发重复 init
    if (RdbHelper.pending) {
      return RdbHelper.pending;
    }
    // 先设实例，供 createTables 内部 DupRuleConfigDao 经 getExisting() 访问 store
    const helper: RdbHelper = new RdbHelper();
    RdbHelper.instance = helper;
    RdbHelper.pending = (async () => {
      try {
        await helper.init(context);
        return helper;
      } catch (e) {
        // 初始化失败时清除单例，使下次调用可重试，避免卡在 "rdbStore 未初始化" 状态
        RdbHelper.instance = null;
        throw e;
      } finally {
        RdbHelper.pending = null;
      }
    })();
    return RdbHelper.pending;
  }

  /** 取得已初始化的单例；未初始化时返回 null。 */
  public static getExisting(): RdbHelper | null {
    return RdbHelper.instance;
  }

  /** rdbStore 是否已就绪（用于 getInstance 判断是否需要重新初始化）。 */
  public isReady(): boolean {
    return this.rdbStore !== null;
  }

  private async init(context: common.Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: RdbHelper.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.rdbStore = await relationalStore.getRdbStore(context, config);
    await this.createTables();
  }

  public getStore(): relationalStore.RdbStore {
    if (!this.rdbStore) {
      throw new Error('RdbStore 尚未初始化，请先调用 RdbHelper.getInstance(context)');
    }
    return this.rdbStore;
  }

  private async createTables(): Promise<void> {
    const store = this.getStore();
    // 单条 DDL/迁移失败不中断整体初始化：记录错误后继续，保证库可用。
    // 避免「某条索引/迁移语句失败 → init 抛错 → instance 置 null → 所有 DAO 崩溃」的连锁反应；
    // 失败原因写入日志，便于排查真实根因。
    const safe = async (sql: string, label: string): Promise<void> => {
      try {
        await store.executeSql(sql);
      } catch (e) {
        LogUtil.e('RdbHelper', `执行SQL失败[${label}]: ${(e as Error)?.message ?? '未知错误'}`);
      }
    };

    await safe(`
      CREATE TABLE IF NOT EXISTS scanned_file (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL DEFAULT '',
        file_name TEXT NOT NULL DEFAULT '',
        file_size INTEGER NOT NULL DEFAULT 0,
        title TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        progress TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '',
        encoding TEXT NOT NULL DEFAULT '',
        content_hash TEXT NOT NULL DEFAULT '',
        ext TEXT NOT NULL DEFAULT '',
        marked INTEGER NOT NULL DEFAULT 0,
        checked INTEGER NOT NULL DEFAULT 0,
        scan_run_id INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        file_date INTEGER NOT NULL DEFAULT 0,
        title_pinyin TEXT NOT NULL DEFAULT '',
        author_pinyin TEXT NOT NULL DEFAULT '',
        title_author_key TEXT NOT NULL DEFAULT ''
      )`, 'scanned_file');
    await safe('CREATE UNIQUE INDEX IF NOT EXISTS idx_sf_path_run ON scanned_file(path, scan_run_id)', 'idx_sf_path_run');
    await safe('CREATE INDEX IF NOT EXISTS idx_sf_marked ON scanned_file(marked)', 'idx_sf_marked');
    await safe('CREATE INDEX IF NOT EXISTS idx_sf_checked ON scanned_file(checked)', 'idx_sf_checked');
    await safe('CREATE INDEX IF NOT EXISTS idx_sf_title ON scanned_file(title)', 'idx_sf_title');
    await safe('CREATE INDEX IF NOT EXISTS idx_sf_run ON scanned_file(scan_run_id)', 'idx_sf_run');

    await safe(`
      CREATE TABLE IF NOT EXISTS scan_config (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL DEFAULT '',
        folder_uri TEXT NOT NULL DEFAULT '',
        folder_name TEXT NOT NULL DEFAULT '',
        file_types TEXT NOT NULL DEFAULT 'txt',
        min_size_kb INTEGER NOT NULL DEFAULT 0,
        recursive INTEGER NOT NULL DEFAULT 1,
        exact_hash INTEGER NOT NULL DEFAULT 0,
        excluded_folders TEXT NOT NULL DEFAULT ''
      )`, 'scan_config');
    // 旧库升级：补齐排除书名两列（新库 CREATE 未含，需经迁移添加）。
    // 用 addColumnIfNotExists 先探测列是否存在再 ALTER，避免重复启动对已含列的表
    // 重复 ALTER 触发 "Insert failed or the updated data does not exist" 通用报错污染日志。
    await RdbHelper.addColumnIfNotExists(store, 'scan_config', 'excluded_titles', "TEXT NOT NULL DEFAULT ''");
    await RdbHelper.addColumnIfNotExists(store, 'scan_config', 'excluded_title_keywords', "TEXT NOT NULL DEFAULT ''");

    await safe(`
      CREATE TABLE IF NOT EXISTS scan_run (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL DEFAULT '',
        folder_uri TEXT NOT NULL DEFAULT '',
        folder_name TEXT NOT NULL DEFAULT '',
        file_types TEXT NOT NULL DEFAULT 'txt',
        created_at INTEGER NOT NULL DEFAULT 0,
        file_count INTEGER NOT NULL DEFAULT 0
      )`, 'scan_run');

    await safe(`
      CREATE TABLE IF NOT EXISTS keyword_replace_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT NOT NULL DEFAULT 'scan',
        pattern TEXT NOT NULL DEFAULT '',
        replacement TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0
      )`, 'keyword_replace_rules');

    // DupRuleConfigDao.createTable 内部经 getExisting() 取 store；init 进行中实例已设，可安全调用。
    try {
      await DupRuleConfigDao.createTable();
    } catch (e) {
      LogUtil.e('RdbHelper', `创建 dup_rule_config 表失败: ${(e as Error)?.message ?? '未知错误'}`);
    }

    // 旧库迁移：补充拼音列（列已存在时 ALTER 抛错，忽略即可，保持幂等）
    await RdbHelper.addColumnIfNotExists(store, 'scanned_file', 'title_pinyin', "TEXT NOT NULL DEFAULT ''");
    await RdbHelper.addColumnIfNotExists(store, 'scanned_file', 'author_pinyin', "TEXT NOT NULL DEFAULT ''");
    // 旧库迁移：关键词替换规则补充 is_builtin 列（区分内置/自定义）
    await RdbHelper.addColumnIfNotExists(store, 'keyword_replace_rules', 'is_builtin', 'INTEGER NOT NULL DEFAULT 0');
    // 旧库迁移：scanned_file 补充 encoding/file_date 列（对齐安卓 ScannedFileEntity）
    await RdbHelper.addColumnIfNotExists(store, 'scanned_file', 'encoding', "TEXT NOT NULL DEFAULT ''");
    await RdbHelper.addColumnIfNotExists(store, 'scanned_file', 'file_date', 'INTEGER NOT NULL DEFAULT 0');
    // 旧库迁移：补充 title_author_key 列（预计算 lower(trim(title))||'|'||lower(trim(author))，
    // 供「勾选重复」分组使用，避免在子查询中重复计算表达式；新插入行由 ScannedFileDao.toValues 写入）。
    await RdbHelper.addColumnIfNotExists(store, 'scanned_file', 'title_author_key', "TEXT NOT NULL DEFAULT ''");
    // 回填历史空 key（title 非空时 key 至少含 '|'，不会与空串冲突，仅一次性迁移）。
    await safe(
      `UPDATE scanned_file SET title_author_key = lower(trim(title)) || '|' || lower(trim(COALESCE(author, ''))) WHERE title_author_key = ''`,
      'backfill title_author_key'
    );
    // 复合索引：加速「勾选重复」按 (scan_run_id, title_author_key) 的分组聚合与过滤。
    await safe('CREATE INDEX IF NOT EXISTS idx_sf_run_tak ON scanned_file(scan_run_id, title_author_key)', 'idx_sf_run_tak');
    // 拼音回填：历史数据在拼音列加入前已入库时，title_pinyin/author_pinyin 为空串，
    // 导致按拼音搜索无法命中。仅在拼音列为空、原字段非空时回填，已有正确拼音的不覆盖。
    await this.backfillPinyin(store);
  }

  private static async addColumnIfNotExists(store: relationalStore.RdbStore, table: string, column: string, def: string): Promise<void> {
    // 先查询表结构，列已存在则直接跳过，避免对已有列执行 ALTER 抛 "duplicate column name"。
    // 注意：鸿蒙 ArkData 在列已存在时报 "SQLite: Generic error..." 而非明确的
    // "duplicate column name"，故不能仅靠捕获异常文案判断；用 table_info 显式探测最稳妥。
    try {
      const info = await store.querySql(`PRAGMA table_info(${table})`);
      let exists = false;
      while (info.goToNextRow()) {
        const name = info.getString(info.getColumnIndex('name'));
        if (name === column) {
          exists = true;
          break;
        }
      }
      info.close();
      if (exists) {
        return;
      }
    } catch (e) {
      // 探测失败（如表不存在）时，仍尝试 ALTER，让底层报错暴露真实问题。
      LogUtil.w('RdbHelper', `探测列 ${table}.${column} 失败，尝试直接 ALTER: ${(e as Error)?.message ?? '未知错误'}`);
    }
    try {
      await store.executeSql(`ALTER TABLE ${table} ADD COLUMN ${column} ${def}`);
    } catch (e) {
      const msg: string = (e as Error)?.message ?? '';
      if (msg.includes('duplicate column name')) {
        return; // 列已存在，ALTER 重复执行时的正常情况（兜底，理论上不会再走到）
      }
      // 非预期错误：记录但不中断初始化，避免一条迁移失败导致整个数据库不可用。
      // 真实原因写入日志便于排查（如磁盘满/语法错误等仍需关注）。
      LogUtil.e('RdbHelper', `添加列失败 ${table}.${column}: ${msg}`);
    }
  }

  /**
   * 回填历史数据的拼音列。仅处理 title_pinyin/author_pinyin 为空串、但对应原字段非空的行，
   * 已有正确拼音的不覆盖。逐行读取后用 ChineseConverter.toPinyin 重算并 UPDATE。
   * 与安卓端对齐：避免「早期扫描的数据搜不了拼音」的问题。
   */
  private async backfillPinyin(store: relationalStore.RdbStore): Promise<void> {
    try {
      // 仅取需要回填的行（减少内存与计算量）
      const result = await store.querySql(
        `SELECT id, title, author FROM scanned_file WHERE (title_pinyin = '' AND title <> '') OR (author_pinyin = '' AND author IS NOT NULL AND author <> '')`
      );
      const updates: Array<Promise<void>> = [];
      while (result.goToNextRow()) {
        const id = result.getLong(result.getColumnIndex('id'));
        const title = result.getString(result.getColumnIndex('title')) ?? '';
        const author = result.getString(result.getColumnIndex('author')) ?? '';
        const tp = title ? ChineseConverter.toPinyin(title) : '';
        const ap = author ? ChineseConverter.toPinyin(author) : '';
        updates.push(
          store.executeSql(
            `UPDATE scanned_file SET title_pinyin = ?, author_pinyin = ? WHERE id = ?`,
            [tp, ap, id]
          ).catch((e: Error) => {
            LogUtil.e('RdbHelper', `回填拼音失败 id=${id}: ${e?.message ?? '未知错误'}`);
          })
        );
      }
      result.close();
      await Promise.all(updates);
      if (updates.length > 0) {
        LogUtil.i('RdbHelper', `拼音回填完成，处理 ${updates.length} 行`);
      }
    } catch (e) {
      LogUtil.e('RdbHelper', `拼音回填异常: ${(e as Error)?.message ?? '未知错误'}`);
    }
  }
}
