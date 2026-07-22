/**
 * 通用格式化工具。
 */
export class FormatUtil {
  /** 字节数格式化为可读大小（B/KB/MB/GB）。 */
  public static formatFileSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    const kb: number = bytes / 1024;
    if (kb < 1024) {
      return `${kb.toFixed(1)} KB`;
    }
    const mb: number = kb / 1024;
    if (mb < 1024) {
      return `${mb.toFixed(1)} MB`;
    }
    return `${(mb / 1024).toFixed(2)} GB`;
  }

  /** 取文件扩展名（不含点，小写）；无扩展名返回空串。 */
  public static getExtension(fileName: string): string {
    const idx: number = fileName.lastIndexOf('.');
    if (idx < 0 || idx === fileName.length - 1) {
      return '';
    }
    return fileName.substring(idx + 1).toLowerCase();
  }

  /** 时间戳（毫秒）格式化为 YYYY-MM-DD HH:mm:ss。 */
  public static formatTimestamp(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d: Date = new Date(ts);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
      `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }
}
