import { fileIo } from '@kit.CoreFileKit';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { ScanRunDao } from '../database/ScanRunDao';
import { LogUtil } from '../utils/LogUtil';

export interface DeleteOptions {
  /** true=删除数据库记录 + 物理源文件（旧默认）；false=仅删除数据库记录，保留源文件。 */
  deleteSource?: boolean;
  /** 进度回调：done 已处理数, total 总数, success 成功数, failed 失败数, current 当前文件名。 */
  onProgress?: (done: number, total: number, success: number, failed: number, current: string) => void;
  /** 单文件完成回调，便于 UI 追加实时日志（成功/失败 + 文件名 + 路径）。 */
  onFileDone?: (info: { id: number; name: string; path: string; ok: boolean; error?: string }) => void;
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
    // 进度回调节流：与扫描侧 ScanService.PROGRESS_INTERVAL=16 对齐。
    // 10w 文件若每删一个就回调一次 onProgress，UI 线程需 10w 次 @State 刷新必然卡顿。
    const PROGRESS_INTERVAL: number = 16;
    let deleted: number = 0;
    let failed: number = 0;
    let done: number = 0;
    let lastReportDone: number = 0;
    const total: number = ids.length;
    const affectedRuns: Set<number> = new Set<number>();

    LogUtil.i('DeleteService', `[操作] 开始删除：共 ${total} 个文件（${deleteSource ? '删除记录+源文件' : '仅删除记录'}）`);

    for (let start: number = 0; start < ids.length; start += BATCH) {
      const batch: number[] = ids.slice(start, Math.min(start + BATCH, ids.length));
      const files = await ScannedFileDao.getByIds(batch);
      // 本批物理删除成功的 id，待本批结束统一入库删除（deleteByIds 内部再按 500 分块），
      // 避免逐条 deleteByIds([f.id]) 造成 10w 文件 = 10w 次 DB 往返。
      const successIds: number[] = [];
      for (const f of files) {
        done++;
        let ok: boolean = false;
        let errMsg: string | undefined = undefined;
        if (deleteSource) {
          try {
            if (f.path && f.path.length > 0) {
              // fileIo.unlink 返回 Promise，必须 await 才能捕获异常并确认删除结果；
              // 原实现未 await 会导致「删除失败也被记为成功」，且异常无法进入 catch。
              await fileIo.unlink(f.path);
              ok = true;
            }
          } catch (e) {
            ok = false;
            errMsg = (e as Error).message ?? String(e);
            LogUtil.w('DeleteService', `文件 ${f.fileName}（${f.path}）删除失败: ${errMsg}`);
          }
        } else {
          // 仅删记录，直接视为成功
          ok = true;
        }
        if (ok) {
          successIds.push(f.id);
          deleted++;
          affectedRuns.add(f.scanRunId);
        } else {
          failed++;
          LogUtil.w('DeleteService', `物理删除失败，保留记录: ${f.fileName} (${f.path})`);
        }
        if (options.onFileDone) {
          options.onFileDone({ id: f.id, name: f.fileName, path: f.path, ok: ok, error: ok ? undefined : errMsg });
        }
        // 节流：仅当累计增量 ≥ PROGRESS_INTERVAL 才回调进度，避免每文件一次 UI 刷新。
        if (options.onProgress && done - lastReportDone >= PROGRESS_INTERVAL) {
          options.onProgress(done, total, deleted, failed, f.fileName);
          lastReportDone = done;
        }
      }
      // 批量删除本批成功文件的数据库记录（一次 DELETE 替代逐条删除）。
      if (successIds.length > 0) {
        await ScannedFileDao.deleteByIds(successIds);
      }
    }
    // 强制补报最终进度：小批量（< PROGRESS_INTERVAL）时上述节流可能一次都没触发，
    // UI 若停留在 0/0 将无法显示完成状态。
    if (options.onProgress && total > 0 && done - lastReportDone > 0) {
      options.onProgress(done, total, deleted, failed, '');
      lastReportDone = done;
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
    // 仅投影 id 列，避免加载 10w+ 完整对象仅为取 id 的内存浪费。
    const ids: number[] = await ScannedFileDao.getIdsByScanRun(runId);
    return await DeleteService.deleteByIds(ids, options);
  }
}
