import { fileIo } from '@kit.CoreFileKit';
import { AppContext } from '../utils/AppContext';
import { ScannedFile } from '../model/ScannedFile';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';

export type ExportMode = 'checked' | 'marked' | 'all';

/**
 * 导出服务：将文库下「已勾选 / 已标记 / 全部」文件清单导出为 CSV，
 * 写入应用沙箱 filesDir（CSV 含书名/作者/进度/来源/编码/文件名/大小/修改日期/路径）。
 * 对齐安卓端 ExportService。
 */
export class ExportService {
  public static async exportList(runId: number, mode: ExportMode, fileNamePrefix: string): Promise<string> {
    const ctx = AppContext.get();
    if (!ctx) {
      throw new Error('AppContext 未初始化');
    }
    const outPath: string = `${ctx.filesDir}/${fileNamePrefix}_${Date.now()}.csv`;
    // 异步打开 + 流式分页写入，避免：
    //  1) getByScanRun(1000000) 一次性加载 10w+ 完整对象到内存；
    //  2) body += ... 循环字符串拼接的 O(n²) 开销；
    //  3) writeSync 整串同步写入阻塞 UI。
    const file = await fileIo.open(outPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    let total: number = 0;
    try {
      await fileIo.write(file.fd, '书名,作者,进度,来源,编码,文件名,大小,修改日期,路径\n');
      const PAGE: number = 1000;
      let offset: number = 0;
      while (true) {
        const page: ScannedFile[] = await ScannedFileDao.getByScanRun(runId, PAGE, offset);
        if (page.length === 0) {
          break;
        }
        // 用数组收集行再 join，避免 body += 的 O(n²) 字符串拼接。
        const lines: string[] = [];
        for (const f of page) {
          if (mode === 'all' || (mode === 'checked' && f.checked === 1) || (mode === 'marked' && f.marked === 1)) {
            lines.push(`${ExportService.csvCell(f.title)},${ExportService.csvCell(f.author)},` +
              `${ExportService.csvCell(f.progress)},${ExportService.csvCell(f.source)},` +
              `${ExportService.csvCell(f.encoding)},${ExportService.csvCell(f.fileName)},` +
              `${FormatUtil.formatFileSize(f.fileSize)},${FormatUtil.formatFileDate(f.fileDate)},` +
              `${ExportService.csvCell(f.path)}\n`);
            total++;
          }
        }
        if (lines.length > 0) {
          await fileIo.write(file.fd, lines.join(''));
        }
        offset += PAGE;
        if (page.length < PAGE) {
          break;
        }
      }
    } finally {
      await fileIo.close(file);
    }
    LogUtil.operation('导出', `文库ID=${runId} 模式=${mode} 条数=${total} 文件=${outPath}`);
    return outPath;
  }

  private static csvCell(s: string): string {
    const t: string = s ?? '';
    if (t.includes(',') || t.includes('"') || t.includes('\n')) {
      return `"${t.replace(/"/g, '""')}"`;
    }
    return t;
  }
}
