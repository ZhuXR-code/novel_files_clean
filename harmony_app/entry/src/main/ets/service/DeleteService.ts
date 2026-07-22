import { fileIo } from '@kit.CoreFileKit';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { ScanRunDao } from '../database/ScanRunDao';
import { LogUtil } from '../utils/LogUtil';

export interface DeleteOptions {
  /** true=删除数据库记录 + 物理源文件（旧默认）；false=仅删除数据库记录，保留源文件。 */
  deleteSource?: boolean;
  /** 进度回调：done 已处理数, total 总数, success 成功数, failed 失败数, current 当前文件名。 */
  onProgress?: (done: number, total: number, success: number, failed: number, current: string) => void;
}

/**
 * 删除服务：支持"删除记录+源文件"或"仅删除记录"。
 * 对齐安卓端 DeleteService 优化：
 *  1) deleteSource 开关；
 *  2) 分批加载实体并删除，避免一次性把上万行读进内存；
 *  3) 删除完成后重算所有受影响文库的 file_count。
 */
export class DeleteService {
  /**
   * 删除指定 id 的文件。
   * @returns { deleted, failed } 成功/失败数。
   */
  public static async deleteByIds(
    ids: number[],
    options: DeleteOptions = {}
  ): Promise<{ deleted: number; failed: number }> {
    if (ids.length === 0) {
      return { deleted: 0, failed: 0 };
    }
    const deleteSource: boolean = options.deleteSource !== false;
    const BATCH: number = 200;
    let deleted: number = 0;
    let failed: number = 0;
    let done: number = 0;
    const total: number = ids.length;
    const affectedRuns: Set<number> = new Set<number>();

    LogUtil.i('DeleteService', `[操作] 开始删除：共 ${total} 个文件（${deleteSource ? '删除记录+源文件' : '仅删除记录'}）`);

    for (let start: number = 0; start < ids.length; start += BATCH) {
      const batch: number[] = ids.slice(start, Math.min(start + BATCH, ids.length));
      const files = await ScannedFileDao.getByIds(batch);
      for (const f of files) {
        done++;
        let ok: boolean = false;
        if (deleteSource) {
          try {
            if (f.path && f.path.length > 0) {
              fileIo.unlink(f.path);
              ok = true;
            }
          } catch (e) {
            ok = false;
          }
        } else {
          // 仅删记录，直接视为成功
          ok = true;
        }
        if (ok) {
          await ScannedFileDao.deleteByIds([f.id]);
          deleted++;
          affectedRuns.add(f.scanRunId);
        } else {
          failed++;
          LogUtil.w('DeleteService', `物理删除失败，保留记录: ${f.fileName} (${f.path})`);
        }
        if (options.onProgress) {
          options.onProgress(done, total, deleted, failed, f.fileName);
        }
      }
    }

    // 删除完成后，重算所有受影响文库的文件数（回写 scan_run.file_count）
    if (affectedRuns.size > 0) {
      for (const runId of affectedRuns) {
        const n: number = await ScannedFileDao.countByScanRun(runId);
        await ScanRunDao.updateFileCount(runId, n);
      }
      LogUtil.i('DeleteService', `重算 ${affectedRuns.size} 个文库文件数完成`);
    }

    LogUtil.operation('删除', `共=${total} 成功=${deleted} 失败=${failed} deleteSource=${deleteSource}`);
    return { deleted: deleted, failed: failed };
  }

  /** 删除某文库下全部文件。 */
  public static async deleteAllInRun(
    runId: number,
    options: DeleteOptions = {}
  ): Promise<{ deleted: number; failed: number }> {
    const files = await ScannedFileDao.getByScanRun(runId, 1000000, 0);
    const ids: number[] = files.map((f) => f.id);
    return await DeleteService.deleteByIds(ids, options);
  }
}
