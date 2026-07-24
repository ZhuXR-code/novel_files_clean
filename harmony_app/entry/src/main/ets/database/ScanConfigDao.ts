import { relationalStore } from '@kit.ArkData';
import { RdbHelper } from './RdbHelper';
import { ScanConfig } from '../model/ScanConfig';

/**
 * 扫描配置访问层，镜像安卓端 ScanConfigDao。
 */
export class ScanConfigDao {
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

  private static toConfig(rs: relationalStore.ResultSet): ScanConfig {
    const c: ScanConfig = new ScanConfig();
    c.id = ScanConfigDao.colNum(rs, 'id');
    c.name = ScanConfigDao.colStr(rs, 'name');
    c.folderUri = ScanConfigDao.colStr(rs, 'folder_uri');
    c.folderName = ScanConfigDao.colStr(rs, 'folder_name');
    c.fileTypes = ScanConfigDao.colStr(rs, 'file_types');
    c.minSizeKb = ScanConfigDao.colNum(rs, 'min_size_kb');
    c.recursive = ScanConfigDao.colNum(rs, 'recursive') === 1;
    c.exactHash = ScanConfigDao.colNum(rs, 'exact_hash') === 1;
    c.excludedFolders = ScanConfigDao.colStr(rs, 'excluded_folders');
    return c;
  }

  public static toValues(c: ScanConfig): relationalStore.ValuesBucket {
    return {
      name: c.name,
      folder_uri: c.folderUri,
      folder_name: c.folderName,
      file_types: c.fileTypes,
      min_size_kb: c.minSizeKb,
      recursive: c.recursive ? 1 : 0,
      exact_hash: c.exactHash ? 1 : 0,
      excluded_folders: c.excludedFolders
    };
  }

  public static async insert(cfg: ScanConfig): Promise<number> {
    return await ScanConfigDao.store.insert('scan_config', ScanConfigDao.toValues(cfg));
  }

  public static async update(cfg: ScanConfig): Promise<void> {
    const values: relationalStore.ValuesBucket = ScanConfigDao.toValues(cfg);
    const predicates = new relationalStore.RdbPredicates('scan_config');
    predicates.equalTo('id', cfg.id);
    await ScanConfigDao.store.update(values, predicates);
  }

  public static async delete(id: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('scan_config');
    predicates.equalTo('id', id);
    await ScanConfigDao.store.delete(predicates);
  }

  public static async getById(id: number): Promise<ScanConfig | null> {
    const predicates = new relationalStore.RdbPredicates('scan_config');
    predicates.equalTo('id', id);
    const rs = await ScanConfigDao.store.query(predicates);
    let result: ScanConfig | null = null;
    if (rs.goToFirstRow()) {
      result = ScanConfigDao.toConfig(rs);
    }
    rs.close();
    return result;
  }

  public static async getAll(): Promise<ScanConfig[]> {
    const predicates = new relationalStore.RdbPredicates('scan_config');
    predicates.orderByDesc('id');
    const rs = await ScanConfigDao.store.query(predicates);
    const list: ScanConfig[] = [];
    while (rs.goToNextRow()) {
      list.push(ScanConfigDao.toConfig(rs));
    }
    rs.close();
    return list;
  }

  public static async count(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates('scan_config');
    return await ScanConfigDao.store.query(predicates).then((rs) => {
      const c = rs.rowCount;
      rs.close();
      return c;
    });
  }
}
