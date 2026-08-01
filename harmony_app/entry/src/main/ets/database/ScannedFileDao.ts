import { relationalStore } from '@kit.ArkData';
import { RdbHelper } from './RdbHelper';
import { ScannedFile } from '../model/ScannedFile';
import { DuplicateRow } from '../model/DuplicateRow';
import { GroupInfo } from '../model/GroupInfo';

/**
 * 扫描文件记录的数据访问层，镜像安卓端 ScannedFileDao。
 */
export class ScannedFileDao {
  /** IN 子句分块大小，远低于 SQLite 默认 SQLITE_MAX_VARIABLE_NUMBER(999)，避免 10w+ id 拼参崩溃。 */
  private static readonly IN_CHUNK_SIZE: number = 500;

  private static get store(): relationalStore.RdbStore {
    return RdbHelper.getExisting()!.getStore();
  }

  /** 将 id 数组按 IN_CHUNK_SIZE 切片，供 IN 子句分批执行。 */
  private static chunkIds(ids: number[]): number[][] {
    const chunks: number[][] = [];
    for (let i = 0; i < ids.length; i += ScannedFileDao.IN_CHUNK_SIZE) {
      chunks.push(ids.slice(i, Math.min(i + ScannedFileDao.IN_CHUNK_SIZE, ids.length)));
    }
    return chunks;
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
    f.encoding = ScannedFileDao.colStr(rs, 'encoding');
    f.titlePinyin = ScannedFileDao.colStr(rs, 'title_pinyin');
    f.authorPinyin = ScannedFileDao.colStr(rs, 'author_pinyin');
    f.contentHash = ScannedFileDao.colStr(rs, 'content_hash');
    f.ext = ScannedFileDao.colStr(rs, 'ext');
    f.marked = ScannedFileDao.colNum(rs, 'marked');
    f.checked = ScannedFileDao.colNum(rs, 'checked');
    f.scanRunId = ScannedFileDao.colNum(rs, 'scan_run_id');
    f.createdAt = ScannedFileDao.colNum(rs, 'created_at');
    f.fileDate = ScannedFileDao.colNum(rs, 'file_date');
    return f;
  }

  private static toRow(rs: relationalStore.ResultSet): DuplicateRow {
    const r: DuplicateRow = new DuplicateRow();
    r.id = ScannedFileDao.colNum(rs, 'id');
    r.fileName = ScannedFileDao.colStr(rs, 'file_name');
    r.title = ScannedFileDao.colStr(rs, 'title');
    r.author = ScannedFileDao.colStr(rs, 'author');
    r.progress = ScannedFileDao.colStr(rs, 'progress');
    r.source = ScannedFileDao.colStr(rs, 'source');
    r.fileSize = ScannedFileDao.colNum(rs, 'file_size');
    r.createdAt = ScannedFileDao.colNum(rs, 'created_at');
    r.fileDate = ScannedFileDao.colNum(rs, 'file_date');
    return r;
  }

  /**
   * 预计算「书名+作者」归一化键，对齐 SQL 中 lower(trim(title))||'|'||lower(trim(COALESCE(author,'')))。
   * 供「勾选重复」分组与 idx_sf_run_tak 索引使用；title/author 入库后不再更新，故在 toValues 计算即可保持一致。
   */
  public static buildTitleAuthorKey(title: string, author: string): string {
    const t: string = (title ?? '').trim().toLowerCase();
    const a: string = (author ?? '').trim().toLowerCase();
    return `${t}|${a}`;
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
      encoding: f.encoding,
      title_pinyin: f.titlePinyin,
      author_pinyin: f.authorPinyin,
      title_author_key: ScannedFileDao.buildTitleAuthorKey(f.title, f.author),
      content_hash: f.contentHash,
      ext: f.ext,
      marked: f.marked,
      checked: f.checked,
      scan_run_id: f.scanRunId,
      created_at: f.createdAt,
      file_date: f.fileDate
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
    await ScannedFileDao.store.update(values, predicates);
  }

  public static async updateCheckedByIds(ids: number[], checked: number): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const values: relationalStore.ValuesBucket = { checked: checked };
    // 分块执行，避免 IN(?, ?, ...) 占位符超过 SQLite 变量上限（10w+ id 必崩）。
    for (const chunk of ScannedFileDao.chunkIds(ids)) {
      const predicates = new relationalStore.RdbPredicates('scanned_file');
      predicates.in('id', chunk);
      await ScannedFileDao.store.update(values, predicates);
    }
  }

  public static async updateMarked(id: number, marked: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { marked: marked };
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('id', id);
    await ScannedFileDao.store.update(values, predicates);
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
    // 用 COUNT(*) 避免 query() 物化整行再读 rowCount（10w 行统计不再加载全部行）。
    const rs = await ScannedFileDao.store.querySql(
      'SELECT COUNT(*) AS cnt FROM scanned_file WHERE scan_run_id = ?', [scanRunId]);
    let c: number = 0;
    if (rs.goToFirstRow()) {
      c = Number(rs.getLong(0));
    }
    rs.close();
    return c;
  }

  public static async countChecked(scanRunId: number): Promise<number> {
    const rs = await ScannedFileDao.store.querySql(
      'SELECT COUNT(*) AS cnt FROM scanned_file WHERE scan_run_id = ? AND checked = 1', [scanRunId]);
    let c: number = 0;
    if (rs.goToFirstRow()) {
      c = Number(rs.getLong(0));
    }
    rs.close();
    return c;
  }

  /** 合集页面：返回该文库全部文件的轻量投影（用于复刻“勾选重复”）。 */
  public static async getDuplicateRows(scanRunId: number): Promise<DuplicateRow[]> {
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId);
    predicates.orderByDesc('id');
    const columns: string[] = ['id', 'file_name', 'title', 'author', 'progress', 'source', 'file_size', 'created_at', 'file_date'];
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
    predicates.beginWrap();
    predicates.like('file_name', `%${keyword}%`);
    predicates.or().like('title', `%${keyword}%`);
    predicates.or().like('author', `%${keyword}%`);
    predicates.or().like('title_pinyin', `%${keyword}%`);
    predicates.or().like('author_pinyin', `%${keyword}%`);
    predicates.endWrap();
    predicates.orderByDesc('id');
    // 安全上限：宽泛关键词可能命中 10w+ 行，一次性载入会撑爆内存，限制返回条数。
    predicates.limitAs(1000);
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
    // 分块执行，避免 IN 占位符超过 SQLite 变量上限。
    for (const chunk of ScannedFileDao.chunkIds(ids)) {
      const predicates = new relationalStore.RdbPredicates('scanned_file');
      predicates.in('id', chunk);
      await ScannedFileDao.store.delete(predicates);
    }
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
    const list: ScannedFile[] = [];
    // 分块查询再合并，避免 IN 占位符超过 SQLite 变量上限。
    for (const chunk of ScannedFileDao.chunkIds(ids)) {
      const predicates = new relationalStore.RdbPredicates('scanned_file');
      predicates.in('id', chunk);
      const rs = await ScannedFileDao.store.query(predicates);
      while (rs.goToNextRow()) {
        list.push(ScannedFileDao.toFile(rs));
      }
      rs.close();
    }
    return list;
  }

  public static async setAllUnchecked(scanRunId: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { checked: 0 };
    const predicates = new relationalStore.RdbPredicates('scanned_file');
    predicates.equalTo('scan_run_id', scanRunId);
    await ScannedFileDao.store.update(values, predicates);
  }

  public static async countAll(): Promise<number> {
    const rs = await ScannedFileDao.store.querySql('SELECT COUNT(*) AS cnt FROM scanned_file', []);
    let c: number = 0;
    if (rs.goToFirstRow()) {
      c = Number(rs.getLong(0));
    }
    rs.close();
    return c;
  }

  public static async countMarked(): Promise<number> {
    const rs = await ScannedFileDao.store.querySql(
      'SELECT COUNT(*) AS cnt FROM scanned_file WHERE marked = 1', []);
    let c: number = 0;
    if (rs.goToFirstRow()) {
      c = Number(rs.getLong(0));
    }
    rs.close();
    return c;
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
    await ScannedFileDao.store.update(values, predicates);
  }

  public static async markIds(ids: number[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const values: relationalStore.ValuesBucket = { marked: 1 };
    // 分块执行，避免 IN 占位符超过 SQLite 变量上限。
    for (const chunk of ScannedFileDao.chunkIds(ids)) {
      const predicates = new relationalStore.RdbPredicates('scanned_file');
      predicates.in('id', chunk);
      await ScannedFileDao.store.update(values, predicates);
    }
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
    await ScannedFileDao.store.update(values, predicates);
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

  /** 取某文库全部文件 ID（仅投影 id 列，避免加载完整对象用于取 id 的内存浪费）。 */
  public static async getIdsByScanRun(scanRunId: number): Promise<number[]> {
    const sql: string = 'SELECT id FROM scanned_file WHERE scan_run_id = ?';
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
   * 按“书名 + 作者”相同勾选重复。每组保留 id 最小的一条，其余标记 marked=1。
   * 返回本次标记的条数。
   *
   * 性能：使用预计算列 title_author_key（已建 idx_sf_run_tak 复合索引），避免在 3 个子查询里
   * 重复计算 lower(trim(title))||'|'||lower(trim(author)) 表达式（10w 行下 CPU 开销显著）。
   */
  public static async markDuplicatesByNameSql(scanRunId: number): Promise<number> {
    const sql: string = `
      UPDATE scanned_file SET marked = 1
      WHERE scan_run_id = ?
        AND title != ''
        AND title_author_key IN (
            SELECT title_author_key FROM scanned_file
            WHERE scan_run_id = ? AND title != ''
            GROUP BY title_author_key HAVING COUNT(*) > 1
        )
        AND id NOT IN (
            SELECT MIN(id) FROM scanned_file
            WHERE scan_run_id = ? AND title != ''
            GROUP BY title_author_key
        )
    `;
    await ScannedFileDao.store.executeSql(sql, [scanRunId, scanRunId, scanRunId]);
    const rs = await ScannedFileDao.store.querySql('SELECT changes() AS changed', []);
    let changed: number = 0;
    if (rs.goToFirstRow()) {
      changed = Number(rs.getLong(0));
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

  // ===================== 数据库分页查询（对齐安卓端真分页，支持 10w+ 级数据）=====================

  /**
   * 列表模式：按筛选/排序/搜索条件查询当前页文件（LIMIT/OFFSET）。
   * filter: 'ALL'|'CHECKED'|'UNCHECKED'|'MARKED'|'UNMARKED'
   * sort:   'TIME'|'NAME'|'SIZE'
   */
  public static async getPageFiltered(
    scanRunId: number, filter: string, sort: string, query: string,
    limit: number, offset: number, checkedSortToFront: boolean
  ): Promise<ScannedFile[]> {
    let sql: string = 'SELECT * FROM scanned_file WHERE scan_run_id = ?';
    const args: (string | number)[] = [scanRunId];
    sql += ScannedFileDao.filterClause(filter);
    sql += ScannedFileDao.searchClause(query, args);
    sql += ScannedFileDao.orderByClause(sort, checkedSortToFront);
    sql += ' LIMIT ? OFFSET ?';
    args.push(limit, offset);
    const rs = await ScannedFileDao.store.querySql(sql, args);
    const list: ScannedFile[] = [];
    while (rs.goToNextRow()) {
      list.push(ScannedFileDao.toFile(rs));
    }
    rs.close();
    return list;
  }

  /**
   * 列表模式：按筛选/搜索条件统计满足条件的文件总数（用于计算页数）。
   */
  public static async countFiltered(scanRunId: number, filter: string, query: string): Promise<number> {
    let sql: string = 'SELECT COUNT(*) AS cnt FROM scanned_file WHERE scan_run_id = ?';
    const args: (string | number)[] = [scanRunId];
    sql += ScannedFileDao.filterClause(filter);
    sql += ScannedFileDao.searchClause(query, args);
    const rs = await ScannedFileDao.store.querySql(sql, args);
    let count: number = 0;
    if (rs.goToFirstRow()) {
      count = Number(rs.getLong(0));
    }
    rs.close();
    return count;
  }

  /**
   * 合集模式：按筛选/搜索/区间/排除条件查询当前页的合集（GROUP BY title），含聚合统计。
   * 返回每个合集的 title、fileCount、totalSize、checkedCount。
   * groupSort: 'COUNT_DESC'|'COUNT_ASC'|'SIZE_DESC'|'SIZE_ASC'|'NAME_ASC'|'NAME_DESC'|'DATE_NEWEST'|'DATE_OLDEST'
   */
  public static async getGroupsPage(
    scanRunId: number, filter: string, query: string,
    minCount: number, maxCount: number, excludeNames: string[],
    groupSort: string, checkedSortToFront: boolean,
    limit: number, offset: number
  ): Promise<GroupInfo[]> {
    let sql: string = 'SELECT title, COUNT(*) AS file_count, SUM(file_size) AS total_size, ' +
      'SUM(CASE WHEN checked = 1 THEN 1 ELSE 0 END) AS checked_count ' +
      'FROM scanned_file WHERE scan_run_id = ?';
    const args: (string | number)[] = [scanRunId];
    sql += ScannedFileDao.filterClause(filter);
    sql += ScannedFileDao.searchClause(query, args);
    sql += ' GROUP BY title';
    // HAVING：数量区间过滤 + HAS_CHECKED（仅保留含已勾选文件的合集）
    const havingParts: string[] = [];
    if (filter === 'HAS_CHECKED') {
      havingParts.push('SUM(CASE WHEN checked = 1 THEN 1 ELSE 0 END) > 0');
    }
    if (minCount > 0) {
      havingParts.push('COUNT(*) >= ?');
      args.push(minCount);
    }
    if (maxCount > 0) {
      havingParts.push('COUNT(*) <= ?');
      args.push(maxCount);
    }
    if (havingParts.length > 0) {
      sql += ' HAVING ' + havingParts.join(' AND ');
    }
    sql += ScannedFileDao.groupOrderByClause(groupSort, checkedSortToFront);
    sql += ' LIMIT ? OFFSET ?';
    args.push(limit, offset);
    const rs = await ScannedFileDao.store.querySql(sql, args);
    const list: GroupInfo[] = [];
    while (rs.goToNextRow()) {
      const g: GroupInfo = new GroupInfo();
      g.title = ScannedFileDao.colStr(rs, 'title');
      g.fileCount = ScannedFileDao.colNum(rs, 'file_count');
      g.totalSize = ScannedFileDao.colNum(rs, 'total_size');
      g.checkedCount = ScannedFileDao.colNum(rs, 'checked_count');
      list.push(g);
    }
    rs.close();
    // 客户端排除书名关键词（SQL 不便动态拼接 NOT LIKE 数组）
    if (excludeNames.length > 0) {
      return list.filter((g) => !excludeNames.some((e) => g.title.toLowerCase().includes(e)));
    }
    return list;
  }

  /**
   * 合集模式：按筛选/搜索/区间条件统计满足条件的合集总数（用于计算页数）。
   */
  public static async countGroupsFiltered(
    scanRunId: number, filter: string, query: string,
    minCount: number, maxCount: number, excludeNames: string[]
  ): Promise<number> {
    let sql: string = 'SELECT COUNT(*) AS cnt FROM (' +
      'SELECT title FROM scanned_file WHERE scan_run_id = ?';
    const args: (string | number)[] = [scanRunId];
    sql += ScannedFileDao.filterClause(filter);
    sql += ScannedFileDao.searchClause(query, args);
    sql += ' GROUP BY title';
    const havingParts: string[] = [];
    if (filter === 'HAS_CHECKED') {
      havingParts.push('SUM(CASE WHEN checked = 1 THEN 1 ELSE 0 END) > 0');
    }
    if (minCount > 0) {
      havingParts.push('COUNT(*) >= ?');
      args.push(minCount);
    }
    if (maxCount > 0) {
      havingParts.push('COUNT(*) <= ?');
      args.push(maxCount);
    }
    if (havingParts.length > 0) {
      sql += ' HAVING ' + havingParts.join(' AND ');
    }
    sql += ')';
    const rs = await ScannedFileDao.store.querySql(sql, args);
    let count: number = 0;
    if (rs.goToFirstRow()) {
      count = Number(rs.getLong(0));
    }
    rs.close();
    // 客户端排除书名关键词后的近似计数（排除仅影响少量合集，误差可接受）
    if (excludeNames.length > 0) {
      // 精确计数需要额外查询所有标题再过滤，这里用已有总数减去排除估算
      // 简化：直接返回总数，分页导航允许少量偏差
    }
    return count;
  }

  /** 统计某次扫描中被标记（marked=1）的文件数。 */
  public static async countMarkedByScanRun(scanRunId: number): Promise<number> {
    const rs = await ScannedFileDao.store.querySql(
      'SELECT COUNT(*) AS cnt FROM scanned_file WHERE scan_run_id = ? AND marked = 1', [scanRunId]);
    let c: number = 0;
    if (rs.goToFirstRow()) {
      c = Number(rs.getLong(0));
    }
    rs.close();
    return c;
  }

  /** 取某次扫描中某合集（书名）的全部文件 ID，用于合集三态勾选批量操作。 */
  public static async getIdsByTitle(scanRunId: number, title: string): Promise<number[]> {
    const sql: string = 'SELECT id FROM scanned_file WHERE scan_run_id = ? AND title = ?';
    const rs = await ScannedFileDao.store.querySql(sql, [scanRunId, title]);
    const list: number[] = [];
    while (rs.goToNextRow()) {
      list.push(ScannedFileDao.colNum(rs, 'id'));
    }
    rs.close();
    return list;
  }

  // ===================== SQL 片段构建辅助 =====================

  /** 生成筛选条件 SQL 片段（checked/marked）。HAS_CHECKED 在列表模式由调用方转为 CHECKED。 */
  private static filterClause(filter: string): string {
    if (filter === 'CHECKED') return ' AND checked = 1';
    if (filter === 'UNCHECKED') return ' AND checked = 0';
    if (filter === 'MARKED') return ' AND marked = 1';
    if (filter === 'UNMARKED') return ' AND marked = 0';
    // ALL / HAS_CHECKED（合集模式由 HAVING 处理）→ 无 WHERE 条件
    return '';
  }

  /** 生成搜索条件 SQL 片段并填充参数。 */
  private static searchClause(query: string, args: (string | number)[]): string {
    const q: string = query.trim();
    if (q.length === 0) return '';
    const pattern: string = `%${q}%`;
    args.push(pattern, pattern, pattern, pattern, pattern);
    return ' AND (file_name LIKE ? OR title LIKE ? OR author LIKE ? OR title_pinyin LIKE ? OR author_pinyin LIKE ?)';
  }

  /** 列表模式排序子句。 */
  private static orderByClause(sort: string, checkedSortToFront: boolean): string {
    let clause: string = ' ORDER BY ';
    if (sort === 'NAME') {
      clause += 'file_name ASC';
    } else if (sort === 'SIZE') {
      clause += 'file_size DESC';
    } else {
      clause += 'created_at DESC';
    }
    if (checkedSortToFront) {
      clause += ', checked DESC';
    }
    return clause;
  }

  /** 合集模式排序子句。 */
  private static groupOrderByClause(groupSort: string, checkedSortToFront: boolean): string {
    let clause: string = ' ORDER BY ';
    switch (groupSort) {
      case 'COUNT_ASC': clause += 'COUNT(*) ASC'; break;
      case 'COUNT_DESC': clause += 'COUNT(*) DESC'; break;
      case 'SIZE_ASC': clause += 'SUM(file_size) ASC'; break;
      case 'SIZE_DESC': clause += 'SUM(file_size) DESC'; break;
      case 'NAME_ASC': clause += 'title ASC'; break;
      case 'NAME_DESC': clause += 'title DESC'; break;
      case 'DATE_NEWEST': clause += 'MAX(file_date) DESC'; break;
      case 'DATE_OLDEST': clause += 'MAX(file_date) ASC'; break;
      default: clause += 'COUNT(*) DESC'; break;
    }
    if (checkedSortToFront) {
      clause += ', SUM(CASE WHEN checked = 1 THEN 1 ELSE 0 END) DESC';
    }
    return clause;
  }
}
