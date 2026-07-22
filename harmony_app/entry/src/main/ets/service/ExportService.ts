import { fileIo } from '@kit.CoreFileKit';
import { AppContext } from '../utils/AppContext';
import { ScannedFile } from '../model/ScannedFile';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';

export type ExportMode = 'checked' | 'marked' | 'all';

/**
 * 导出服务：将文库下「已勾选 / 已标记 / 全部」文件清单导出为 CSV，
 * 写入应用沙箱 filesDir（CSV 含书名/作者/进度/来源/文件名/大小/路径）。
 * 对齐安卓端 ExportService。
 */
export class ExportService {
  public static async exportList(runId: number, mode: ExportMode, fileNamePrefix: string): Promise<string> {
    const all: ScannedFile[] = await ScannedFileDao.getByScanRun(runId, 1000000, 0);
    const filtered: ScannedFile[] = all.filter((f) => {
      if (mode === 'all') {
        return true;
      }
      if (mode === 'checked') {
        return f.checked === 1;
      }
      return f.marked === 1;
    });
    const ctx = AppContext.get();
    if (!ctx) {
      throw new Error('AppContext 未初始化');
    }
    const outPath: string = `${ctx.filesDir}/${fileNamePrefix}_${Date.now()}.csv`;
    const header: string = '书名,作者,进度,来源,文件名,大小,路径\n';
    let body: string = '';
    for (const f of filtered) {
      body += `${ExportService.csvCell(f.title)},${ExportService.csvCell(f.author)},` +
        `${ExportService.csvCell(f.progress)},${ExportService.csvCell(f.source)},` +
        `${ExportService.csvCell(f.fileName)},${FormatUtil.formatFileSize(f.fileSize)},` +
        `${ExportService.csvCell(f.path)}\n`;
    }
    const file = fileIo.openSync(outPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, `${header}${body}`);
    } finally {
      fileIo.closeSync(file);
    }
    LogUtil.operation('导出', `文库ID=${runId} 模式=${mode} 条数=${filtered.length} 文件=${outPath}`);
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
