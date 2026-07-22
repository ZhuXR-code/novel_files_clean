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
    await ScanRunDao.store.update('scan_run', values, predicates);
  }

  public static async delete(runId: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('scan_run');
    predicates.equalTo('id', runId);
    await ScanRunDao.store.delete(predicates);
    // 级联删除其下文件
    await ScannedFileDao.deleteByScanRun(runId);
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
    const predicates = new relationalStore.RdbPredicates('scan_run');
    return await ScanRunDao.store.query(predicates).then((rs) => {
      const c = rs.rowCount;
      rs.close();
      return c;
    });
  }
}
