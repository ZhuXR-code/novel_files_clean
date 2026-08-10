import { relationalStore } from '@kit.ArkData';
import { RdbHelper } from './RdbHelper';
import { FileNoteDao } from './FileNoteDao';
import { ScanRun } from '../model/ScanRun';
import { ScannedFileDao } from './ScannedFileDao';
import { LogUtil } from '../utils/LogUtil';

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
    console.info(`[ScanRunDao] mergeRuns entered sourceIds=[${sourceIds.join(',')}] name="${newName}"`);
    const store = ScanRunDao.store;
    const placeholders: string = sourceIds.map(() => '?').join(',');
    const name: string = newName && newName.trim().length > 0 ? newName.trim() : '合并文库';
    // 合并前记录总源文件数，便于展示去重效果。
    let sourceTotal: number = 0;
    try {
      const totalRs = await store.querySql(
        `SELECT COUNT(*) AS cnt FROM scanned_file WHERE scan_run_id IN (${placeholders})`,
        sourceIds
      );
      if (totalRs.goToFirstRow()) {
        sourceTotal = Number(totalRs.getLong(0));
      }
      totalRs.close();
      LogUtil.i('ScanRunDao', `合并文库准备 sourceIds=[${sourceIds.join(',')}] 源文件总数=${sourceTotal} 新名称="${name}"`);
    } catch (e) {
      LogUtil.w('ScanRunDao', `合并文库 统计源文件总数失败(忽略): ${(e as Error)?.message ?? '未知错误'}`);
    }
    try {
      // 使用 ArkData 原生事务 API（与 ScanRunDao.delete 一致）。
      // 注意：executeSql('BEGIN TRANSACTION'/'COMMIT'/'ROLLBACK') 在 ArkData 下不被支持，
      // 会直接抛错导致整个合并回滚、返回 -1（即“合并失败”且无明确日志）。
      store.beginTransaction();
      // ① 新建文库
      // 注意：scan_run 表 schema 没有 status 列（对照 RdbHelper.createTables 与 ScanRun model），
      // 插入 status 会令 ArkData 抛错导致整个事务回滚、mergeRuns 返回 -1（即“合并失败”）。
      // 仅写入表中实际存在的列。
      const newId: number = await store.insert('scan_run', {
        name: name,
        created_at: Date.now(),
        file_count: 0
      } as relationalStore.ValuesBucket);
      // ② 复制文件（保留全部列；多个源文库存在相同 path 时只保留一条）
      await store.executeSql(
        `INSERT OR IGNORE INTO scanned_file (scan_run_id, path, file_name, file_size, title, author, progress, source, encoding, title_pinyin, author_pinyin, content_hash, ext, marked, checked, created_at, file_date, title_author_key)
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
      // ④ 原文库保留：仅新增一个合并文库，不再删除源文库及其文件
      store.commit();
      // 在事务外重新统计并更新 file_count（ArkData 事务内 UPDATE 可能不生效）
      const cntRs2 = await store.querySql('SELECT COUNT(*) AS cnt FROM scanned_file WHERE scan_run_id = ?', [newId]);
      let fileCount2: number = 0;
      if (cntRs2.goToFirstRow()) {
        fileCount2 = Number(cntRs2.getLong(cntRs2.getColumnIndex('cnt')));
      }
      cntRs2.close();
      const updatePred = new relationalStore.RdbPredicates('scan_run');
      updatePred.equalTo('id', newId);
      await store.update({ file_count: fileCount2 } as relationalStore.ValuesBucket, updatePred);
      console.info(`[ScanRunDao] mergeRuns success newId=${newId} fileCount=${fileCount} fileCount2=${fileCount2}`);
      LogUtil.i('ScanRunDao', `合并文库成功 sourceIds=[${sourceIds.join(',')}] newId=${newId} name="${name}" 源文件总数=${sourceTotal} 去重后文件数=${fileCount}`);
      // ⑤ 合并备注：按 path 把源文库文件备注复制到新文库文件下。
      // 合并后相同 path 只保留一条（新 file_id），多个源对同一 path 的备注经
      // file_notes 唯一索引 (file_id, content) 自动去重（区分大小写）。
      try {
        ScanRunDao.mergeNotesInto(store, sourceIds, newId);
      } catch (en) {
        LogUtil.w('ScanRunDao', `合并备注失败(忽略): ${(en as Error)?.message ?? '未知错误'}`);
      }
      LogUtil.flushNow();
      return newId;
    } catch (e) {
      try {
        store.rollBack();
      } catch (_) {
        // ignore
      }
      const err = e as Error;
      console.error(`[ScanRunDao] mergeRuns error: ${err?.message ?? JSON.stringify(e)}`);
      LogUtil.e('ScanRunDao', `合并文库失败 sourceIds=[${sourceIds.join(',')}] name=${name}: ${err?.message ?? JSON.stringify(e)}${err?.stack ? ' | stack: ' + err.stack : ''}`);
      LogUtil.flushNow();
      return -1;
    }
  }

  /**
   * 把多个源文库的文件备注按 path 映射到新文库文件下（合并书库专用）。
   * 通过查询新文库文件 path→newId、源文库文件 id→path，再把源备注写入新文件，
   * 重复内容由 file_notes 唯一索引 (file_id, content) 自动去重（区分大小写）。
   */
  private static mergeNotesInto(store: relationalStore.RdbStore, sourceIds: number[], newRunId: number): void {
    const srcPlaceholders: string = sourceIds.map(() => '?').join(',');
    // 1) 新文库 path -> newFileId
    const newRs = store.querySql!(
      'SELECT id, path FROM scanned_file WHERE scan_run_id = ?',
      [newRunId]
    );
    const newPathToId: Map<string, number> = new Map();
    while (newRs.goToNextRow()) {
      const idIdx = newRs.getColumnIndex('id');
      const pathIdx = newRs.getColumnIndex('path');
      const id = idIdx >= 0 ? newRs.getLong(idIdx) : 0;
      const path = pathIdx >= 0 ? newRs.getString(pathIdx) : '';
      if (path) {
        newPathToId.set(path, id);
      }
    }
    newRs.close();
    // 2) 源文库文件 id -> path
    const srcRs = store.querySql!(
      `SELECT id, path FROM scanned_file WHERE scan_run_id IN (${srcPlaceholders})`,
      sourceIds
    );
    const srcIdToPath: Map<number, string> = new Map();
    while (srcRs.goToNextRow()) {
      const idIdx = srcRs.getColumnIndex('id');
      const pathIdx = srcRs.getColumnIndex('path');
      const id = idIdx >= 0 ? srcRs.getLong(idIdx) : 0;
      const path = pathIdx >= 0 ? srcRs.getString(pathIdx) : '';
      if (path) {
        srcIdToPath.set(id, path);
      }
    }
    srcRs.close();
    // 3) 取源备注并按 path 写入新文件
    const srcFileIds: number[] = Array.from(srcIdToPath.keys());
    if (!srcFileIds.length) {
      return;
    }
    const notes = FileNoteDao.getNotesByFiles(srcFileIds);
    for (const note of notes) {
      const path = srcIdToPath.get(note.fileId);
      if (!path) {
        continue;
      }
      const newFileId = newPathToId.get(path);
      if (newFileId && newFileId > 0) {
        FileNoteDao.insert(newFileId, note.content, note.createdAt > 0 ? note.createdAt : Date.now());
      }
    }
  }
}
