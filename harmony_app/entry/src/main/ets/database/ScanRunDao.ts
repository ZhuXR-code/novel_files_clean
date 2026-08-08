import { relationalStore } from '@kit.ArkData';
import { RdbHelper } from './RdbHelper';
import { ScanRun } from '../model/ScanRun';
import { ScannedFileDao } from './ScannedFileDao';

/**
 * 文库（一次扫描）访问层，镜像安卓端 ScanRunDao。
 * 删除文库会级联删除其下全部文件记录。
 */
export class ScanRunDao {
  private static get store(): relationalStore.RdbStore {
    return RdbHelper.getExisting()!.getStore();
  }

  private static colStr(rs: relationalStore.ResultSet, col: string): string {
    const idx: number = rs.getColumnIndex(col);
    if (idx < 0) {
      return '';
    }
    try {
      return rs.getString(idx);
    } catch (e) {
      return '';
    }
  }

  private static colNum(rs: relationalStore.ResultSet, col: string): number {
    const idx: number = rs.getColumnIndex(col);
    if (idx < 0) {
      return 0;
    }
    try {
      return rs.getLong(idx);
    } catch (e) {
      return 0;
    }
  }

  private static toRun(rs: relationalStore.ResultSet): ScanRun {
    const r: ScanRun = new ScanRun();
    r.id = ScanRunDao.colNum(rs, 'id');
    r.name = ScanRunDao.colStr(rs, 'name');
    r.folderUri = ScanRunDao.colStr(rs, 'folder_uri');
    r.folderName = ScanRunDao.colStr(rs, 'folder_name');
    r.fileTypes = ScanRunDao.colStr(rs, 'file_types');
    r.createdAt = ScanRunDao.colNum(rs, 'created_at');
    r.fileCount = ScanRunDao.colNum(rs, 'file_count');
    return r;
  }

  public static toValues(r: ScanRun): relationalStore.ValuesBucket {
    return {
      name: r.name,
      folder_uri: r.folderUri,
      folder_name: r.folderName,
      file_types: r.fileTypes,
      created_at: r.createdAt,
      file_count: r.fileCount
    };
  }

  public static async insert(run: ScanRun): Promise<number> {
    return await ScanRunDao.store.insert('scan_run', ScanRunDao.toValues(run));
  }

  public static async updateFileCount(runId: number, fileCount: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { file_count: fileCount };
    const predicates = new relationalStore.RdbPredicates('scan_run');
    predicates.equalTo('id', runId);
    await ScanRunDao.store.update(values, predicates);
  }

  public static async delete(runId: number): Promise<void> {
    const store = ScanRunDao.store;
    // 事务包裹，保证「删文库 + 级联删文件」原子性，避免中途失败留下孤儿文件记录。
    await store.beginTransaction();
    try {
      // 先删文件再删文库，保持引用方向一致（即使无外键约束也便于排查）。
      await ScannedFileDao.deleteByScanRun(runId);
      const predicates = new relationalStore.RdbPredicates('scan_run');
      predicates.equalTo('id', runId);
      await store.delete(predicates);
      await store.commit();
    } catch (e) {
      await store.rollBack();
      throw e;
    }
  }

  public static async deleteAll(): Promise<void> {
    const store = ScanRunDao.store;
    const predicates = new relationalStore.RdbPredicates('scan_run');
    await store.delete(predicates);
  }

  /** 重命名文库（仅更新 name 字段）。 */
  public static async rename(runId: number, newName: string): Promise<void> {
    const store = ScanRunDao.store;
    const predicates = new relationalStore.RdbPredicates('scan_run');
    predicates.equalTo('id', runId);
    await store.update({ name: newName }, predicates);
  }

  public static async getById(runId: number): Promise<ScanRun | null> {
    const predicates = new relationalStore.RdbPredicates('scan_run');
    predicates.equalTo('id', runId);
    const rs = await ScanRunDao.store.query(predicates);
    let result: ScanRun | null = null;
    if (rs.goToFirstRow()) {
      result = ScanRunDao.toRun(rs);
    }
    rs.close();
    return result;
  }

  public static async getAll(): Promise<ScanRun[]> {
    const predicates = new relationalStore.RdbPredicates('scan_run');
    predicates.orderByDesc('id');
    const rs = await ScanRunDao.store.query(predicates);
    const list: ScanRun[] = [];
    while (rs.goToNextRow()) {
      list.push(ScanRunDao.toRun(rs));
    }
    rs.close();
    return list;
  }

  public static async count(): Promise<number> {
    const rs = await ScanRunDao.store.querySql('SELECT COUNT(*) AS cnt FROM scan_run', []);
    let c: number = 0;
    if (rs.goToFirstRow()) {
      c = Number(rs.getLong(0));
    }
    rs.close();
    return c;
  }

  /** 获取最近 N 个文库（按 id 倒序） */
  public static async getRecent(limit: number): Promise<ScanRun[]> {
    const predicates = new relationalStore.RdbPredicates('scan_run');
    predicates.orderByDesc('id');
    predicates.limitAs(limit);
    const rs = await ScanRunDao.store.query(predicates);
    const list: ScanRun[] = [];
    while (rs.goToNextRow()) {
      list.push(ScanRunDao.toRun(rs));
    }
    rs.close();
    return list;
  }

  /**
   * 合并多个文库为一个新文库。
   * 流程：① 新建文库（记录合并来源）② 用 INSERT...SELECT 把源文库文件复制进新文库（保留
   * marked/checked/content_hash 等全部状态，相同 path 通过唯一约束去重）③ 统计新文库文件数。
   * 原文库保留，仅新增一个合并文库（不删除源文库）。对齐安卓 ScanRunDao.mergeRuns。
   * 要求 sourceIds.length >= 2，否则返回 -1。
   */
  public static async mergeRuns(sourceIds: number[], newName: string): Promise<number> {
    if (sourceIds.length < 2) {
      return -1;
    }
    const store = ScanRunDao.store;
    const placeholders: string = sourceIds.map(() => '?').join(',');
    try {
      await store.executeSql('BEGIN TRANSACTION', []);
      // ① 新建文库
      const name: string = newName && newName.trim().length > 0 ? newName.trim() : '合并文库';
      const newId: number = await store.insert('scan_run', {
        name: name,
        created_at: Date.now(),
        status: 'done',
        file_count: 0
      } as relationalStore.ValuesBucket);
      // ② 复制文件（保留全部列；path 唯一冲突的行忽略）
      await store.executeSql(
        `INSERT INTO scanned_file (scan_run_id, path, file_name, file_size, title, author, progress, source, encoding, title_pinyin, author_pinyin, content_hash, ext, marked, checked, created_at, file_date, title_author_key)
         SELECT ?, path, file_name, file_size, title, author, progress, source, encoding, title_pinyin, author_pinyin, content_hash, ext, marked, checked, created_at, file_date, title_author_key
         FROM scanned_file WHERE scan_run_id IN (${placeholders})`,
        [newId, ...sourceIds]
      );
      // ③ 统计新文库文件数
      const cntRs = await store.querySql('SELECT COUNT(*) AS cnt FROM scanned_file WHERE scan_run_id = ?', [newId]);
      let fileCount: number = 0;
      if (cntRs.goToFirstRow()) {
        fileCount = Number(cntRs.getLong(0));
      }
      cntRs.close();
      await store.executeSql('UPDATE scan_run SET file_count = ? WHERE id = ?', [fileCount, newId]);
      // ④ 原文库保留：仅新增一个合并文库，不再删除源文库及其文件
      await store.executeSql('COMMIT', []);
      return newId;
    } catch (e) {
      try {
        await store.executeSql('ROLLBACK', []);
      } catch (_) {
        // ignore
      }
      console.error('mergeRuns failed:', e);
      return -1;
    }
  }
}
