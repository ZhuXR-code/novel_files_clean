import { relationalStore } from '@kit.ArkData';
import { RdbHelper } from './RdbHelper';
import { ScannedFile } from '../model/ScannedFile';
import { DuplicateRow } from '../model/DuplicateRow';

/**
 * 扫描文件记录的数据访问层，镜像安卓端 ScannedFileDao。
 */
export class ScannedFileDao {
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

  private static toFile(rs: relationalStore.ResultSet): ScannedFile {
    const f: ScannedFile = new ScannedFile();
    f.id = ScannedFileDao.colNum(rs, 'id');
    f.path = ScannedFileDao.colStr(rs, 'path');
    f.fileName = ScannedFileDao.colStr(rs, 'file_name');
    f.fileSize = ScannedFileDao.colNum(rs, 'file_size');
    f.title = ScannedFileDao.colStr(rs, 'title');
    f.author = ScannedFileDao.colStr(rs, 'author');
    f.progress = ScannedFileDao.colStr(rs, 'progress');
    f.source = ScannedFileDao.colStr(rs, 'source');
    f.contentHash = ScannedFileDao.colStr(rs, 'content_hash');
    f.ext = ScannedFileDao.colStr(rs, 'ext');
    f.marked = ScannedFileDao.colNum(rs, 'marked');
    f.checked = ScannedFileDao.colNum(rs, 'checked');
    f.scanRunId = ScannedFileDao.colNum(rs, 'scan_run_id');
    f.createdAt = ScannedFileDao.colNum(rs, 'created_at');
    return f;
  }

  private static toRow(rs: relationalStore.ResultSet): DuplicateRow {
    const r: DuplicateRow = new DuplicateRow();
    r.id = ScannedFileDao.colNum(rs, 'id');
    r.fileName = ScannedFileDao.colStr(rs, 'file_name');
    r.title = ScannedFileDao.colStr(rs, 'title');
    r.author = ScannedFileDao.colStr(rs, 'author');
    r.progress = ScannedFileDao.colStr(rs, 'progress');
    r.fileSize = ScannedFileDao.colNum(rs, 'file_size');
    r.createdAt = ScannedFileDao.colNum(rs, 'created_at');
    return r;
  }

  public static toValues(f: ScannedFile): relationalStore.ValuesBucket {
    return {
      path: f.path,
      file_name: f.fileName,
      file_size: f.fileSize,
      title: f.title,
      author: f.author,
      progress: f.progress,
      source: f.source,
      content_hash: f.contentHash,
      ext: f.ext,
      marked: f.marked,
      checked: f.checked,
      scan_run_id: f.scanRunId,
      created_at: f.createdAt
    };
  }

  public static async insert(file: ScannedFile): Promise<number> {
    return await ScannedFileDao.store.insert('scanned_file', ScannedFileDao.toValues(file));
  }

  public static async insertBatch(files: ScannedFile[]): Promise<void> {
    if (files.length === 0) {
      return;
    }
    const buckets: relationalStore.ValuesBucket[] = files.map((f) => ScannedFileDao.toValues(f));
    await ScannedFileDao.store.batchInsert('scanned_file', buckets);
  }

  public static async updateChecked(id: number, checked: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { checked: checked };
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('id', id);
    await ScannedFileDao.store.update('scanned_file', values, predicates);
  }

  public static async updateCheckedByIds(ids: number[], checked: number): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const values: relationalStore.ValuesBucket = { checked: checked };
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.in('id', ids);
    await ScannedFileDao.store.update('scanned_file', values, predicates);
  }

  public static async updateMarked(id: number, marked: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { marked: marked };
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('id', id);
    await ScannedFileDao.store.update('scanned_file', values, predicates);
  }

  public static async getById(id: number): Promise<ScannedFile | null> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('id', id);
    const rs = await ScannedFileDao.store.query(predicates);
    let result: ScannedFile | null = null;
    if (rs.goToFirstRow()) {
      result = ScannedFileDao.toFile(rs);
    }
    rs.close();
    return result;
  }

  public static async getByScanRun(scanRunId: number, limit: number, offset: number): Promise<ScannedFile[]> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId);
    predicates.orderByDesc('id');
    predicates.limitAs(limit).offsetAs(offset);
    const rs = await ScannedFileDao.store.query(predicates);
    const list: ScannedFile[] = [];
    while (rs.goToNextRow()) {
      list.push(ScannedFileDao.toFile(rs));
    }
    rs.close();
    return list;
  }

  public static async countByScanRun(scanRunId: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId);
    return await ScannedFileDao.store.query(predicates).then((rs) => {
      const c = rs.rowCount;
      rs.close();
      return c;
    });
  }

  public static async countChecked(scanRunId: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId).and().equalTo('checked', 1);
    return await ScannedFileDao.store.query(predicates).then((rs) => {
      const c = rs.rowCount;
      rs.close();
      return c;
    });
  }

  /** 合集页面：返回该文库全部文件的轻量投影（用于复刻“标记重复”）。 */
  public static async getDuplicateRows(scanRunId: number): Promise<DuplicateRow[]> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId);
    predicates.orderByDesc('id');
    const columns: string[] = ['id', 'file_name', 'title', 'author', 'progress', 'file_size', 'created_at'];
    const rs = await ScannedFileDao.store.query(predicates, columns);
    const list: DuplicateRow[] = [];
    while (rs.goToNextRow()) {
      list.push(ScannedFileDao.toRow(rs));
    }
    rs.close();
    return list;
  }

  public static async searchByScanRun(scanRunId: number, keyword: string): Promise<ScannedFile[]> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId);
    predicates.and().like('file_name', `%${keyword}%`);
    predicates.orderByDesc('id');
    const rs = await ScannedFileDao.store.query(predicates);
    const list: ScannedFile[] = [];
    while (rs.goToNextRow()) {
      list.push(ScannedFileDao.toFile(rs));
    }
    rs.close();
    return list;
  }

  public static async deleteByIds(ids: number[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.in('id', ids);
    await ScannedFileDao.store.delete(predicates);
  }

  public static async deleteByScanRun(scanRunId: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId);
    await ScannedFileDao.store.delete(predicates);
  }

  public static async getByIds(ids: number[]): Promise<ScannedFile[]> {
    if (ids.length === 0) {
      return [];
    }
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.in('id', ids);
    const rs = await ScannedFileDao.store.query(predicates);
    const list: ScannedFile[] = [];
    while (rs.goToNextRow()) {
      list.push(ScannedFileDao.toFile(rs));
    }
    rs.close();
    return list;
  }

  public static async setAllUnchecked(scanRunId: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { checked: 0 };
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId);
    await ScannedFileDao.store.update('scanned_file', values, predicates);
  }

  public static async countAll(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    return await ScannedFileDao.store.query(predicates).then((rs) => {
      const c: number = rs.rowCount;
      rs.close();
      return c;
    });
  }

  public static async countMarked(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('marked', 1);
    return await ScannedFileDao.store.query(predicates).then((rs) => {
      const c: number = rs.rowCount;
      rs.close();
      return c;
    });
  }

  // ===================== 安卓端优化同步：标记/勾选/批量操作 =====================

  public static async getByPath(path: string): Promise<ScannedFile | null> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('path', path);
    const rs = await ScannedFileDao.store.query(predicates);
    let result: ScannedFile | null = null;
    if (rs.goToFirstRow()) {
      result = ScannedFileDao.toFile(rs);
    }
    rs.close();
    return result;
  }

  public static async getMarked(): Promise<ScannedFile[]> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('marked', 1);
    predicates.orderByDesc('id');
    const rs = await ScannedFileDao.store.query(predicates);
    const list: ScannedFile[] = [];
    while (rs.goToNextRow()) {
      list.push(ScannedFileDao.toFile(rs));
    }
    rs.close();
    return list;
  }

  public static async clearMarked(scanRunId: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { marked: 0 };
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId);
    await ScannedFileDao.store.update('scanned_file', values, predicates);
  }

  public static async markIds(ids: number[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const values: relationalStore.ValuesBucket = { marked: 1 };
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.in('id', ids);
    await ScannedFileDao.store.update('scanned_file', values, predicates);
  }

  /** 单条勾选/取消勾选（与安卓 setChecked 对齐）。 */
  public static async setChecked(id: number, checked: number): Promise<void> {
    await ScannedFileDao.updateChecked(id, checked);
  }

  /** 批量勾选/取消勾选（与安卓 setCheckedForIds 对齐）。 */
  public static async setCheckedForIds(ids: number[], checked: number): Promise<void> {
    await ScannedFileDao.updateCheckedByIds(ids, checked);
  }

  public static async clearChecked(scanRunId: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { checked: 0 };
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId);
    await ScannedFileDao.store.update('scanned_file', values, predicates);
  }

  public static async getCheckedIds(scanRunId: number): Promise<number[]> {
    const sql: string = 'SELECT id FROM scanned_file WHERE scan_run_id = ? AND checked = 1';
    const rs = await ScannedFileDao.store.querySql(sql, [scanRunId]);
    const list: number[] = [];
    while (rs.goToNextRow()) {
      list.push(ScannedFileDao.colNum(rs, 'id'));
    }
    rs.close();
    return list;
  }

  public static async deleteAll(): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    await ScannedFileDao.store.delete(predicates);
  }

  /**
   * 按“书名 + 作者”相同标记重复。每组保留 id 最小的一条，其余标记 marked=1。
   * 返回本次标记的条数。
   */
  public static async markDuplicatesByNameSql(scanRunId: number): Promise<number> {
    const sql: string = `
      UPDATE scanned_file SET marked = 1
      WHERE scan_run_id = ?
        AND title != ''
        AND (lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))) IN (
            SELECT lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
            FROM scanned_file WHERE scan_run_id = ? AND title != ''
            GROUP BY lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
            HAVING COUNT(*) > 1
        )
        AND id NOT IN (
            SELECT MIN(id) FROM scanned_file WHERE scan_run_id = ? AND title != ''
            GROUP BY lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
        )
    `;
    await ScannedFileDao.store.executeSql(sql, [scanRunId, scanRunId, scanRunId]);
    const rs = await ScannedFileDao.store.querySql('SELECT changes() AS changed', []);
    let changed: number = 0;
    if (rs.goToNextRow()) {
      changed = ScannedFileDao.colNum(rs, 'changed');
    }
    rs.close();
    return changed;
  }

  /**
   * 取某个合集（书名）内的全部文件，供合集展开时懒加载。
   * marked / checked 为 null 时不作过滤。
   */
  public static async getFilesByTitle(scanRunId: number, title: string, marked: number | null = null, checked: number | null = null): Promise<ScannedFile[]> {
    let sql: string = 'SELECT * FROM scanned_file WHERE scan_run_id = ? AND title = ?';
    const args: (string | number)[] = [scanRunId, title];
    if (marked !== null) {
      sql += ' AND marked = ?';
      args.push(marked);
    }
    if (checked !== null) {
      sql += ' AND checked = ?';
      args.push(checked);
    }
    sql += ' ORDER BY file_name ASC';
    const rs = await ScannedFileDao.store.querySql(sql, args);
    const list: ScannedFile[] = [];
    while (rs.goToNextRow()) {
      list.push(ScannedFileDao.toFile(rs));
    }
    rs.close();
    return list;
  }
}
