import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DupRuleConfigDao } from './DupRuleConfigDao';

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

  private constructor() {}

  /** 初始化（或复用）单例。必须在 EntryAbility 拿到 context 后调用一次。 */
  public static async getInstance(context: common.Context): Promise<RdbHelper> {
    if (!RdbHelper.instance) {
      RdbHelper.instance = new RdbHelper();
      await RdbHelper.instance.init(context);
    }
    return RdbHelper.instance;
  }

  /** 取得已初始化的单例；未初始化时返回 null。 */
  public static getExisting(): RdbHelper | null {
    return RdbHelper.instance;
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
    await store.executeSql(`
      CREATE TABLE IF NOT EXISTS scanned_file (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL DEFAULT '',
        file_name TEXT NOT NULL DEFAULT '',
        file_size INTEGER NOT NULL DEFAULT 0,
        title TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        progress TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '',
        content_hash TEXT NOT NULL DEFAULT '',
        ext TEXT NOT NULL DEFAULT '',
        marked INTEGER NOT NULL DEFAULT 0,
        checked INTEGER NOT NULL DEFAULT 0,
        scan_run_id INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        title_pinyin TEXT NOT NULL DEFAULT '',
        author_pinyin TEXT NOT NULL DEFAULT ''
      )`);
    await store.executeSql('CREATE UNIQUE INDEX IF NOT EXISTS idx_sf_path_run ON scanned_file(path, scan_run_id)');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_sf_marked ON scanned_file(marked)');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_sf_checked ON scanned_file(checked)');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_sf_title ON scanned_file(title)');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_sf_run ON scanned_file(scan_run_id)');

    await store.executeSql(`
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
      )`);

    await store.executeSql(`
      CREATE TABLE IF NOT EXISTS scan_run (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL DEFAULT '',
        folder_uri TEXT NOT NULL DEFAULT '',
        folder_name TEXT NOT NULL DEFAULT '',
        file_types TEXT NOT NULL DEFAULT 'txt',
        created_at INTEGER NOT NULL DEFAULT 0,
        file_count INTEGER NOT NULL DEFAULT 0
      )`);

    await store.executeSql(`
      CREATE TABLE IF NOT EXISTS keyword_replace_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT NOT NULL DEFAULT 'scan',
        pattern TEXT NOT NULL DEFAULT '',
        replacement TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT 0
      )`);

    await DupRuleConfigDao.createTable();

    // 旧库迁移：补充拼音列（列已存在时 ALTER 抛错，忽略即可，保持幂等）
    await RdbHelper.addColumnIfNotExists(store, 'scanned_file', 'title_pinyin', "TEXT NOT NULL DEFAULT ''");
    await RdbHelper.addColumnIfNotExists(store, 'scanned_file', 'author_pinyin', "TEXT NOT NULL DEFAULT ''");
  }

  private static async addColumnIfNotExists(store: relationalStore.RdbStore, table: string, column: string, def: string): Promise<void> {
    try {
      await store.executeSql(`ALTER TABLE ${table} ADD COLUMN ${column} ${def}`);
    } catch (e) {
      // 列已存在时 ALTER 会报错，忽略
    }
  }
}
