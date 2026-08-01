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

  /** 文件日期（毫秒时间戳）格式化为 YYYY-MM-DD，对齐安卓 FormatUtil.formatFileDate。 */
  public static formatFileDate(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d: Date = new Date(ts);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  /**
   * 将目录 URI 转为友好的展示名。
   * 处理 file:// 前缀与末尾斜杠，提取最后一个非空路径段作为展示名。
   * 自动解码 URL 编码（如 %E6%B5%8B → 测），给用户可读的中文目录名。
   * 例：file://docs/.../Download/  =>  Download
   * 例：file://docs/.../%E6%B5%8B%E8%AF%95/  =>  测试
   * 空或无效 URI 返回空串。
   */
  public static formatFolderDisplay(uri: string): string {
    if (!uri || uri.trim().length === 0) {
      return '';
    }
    // 去掉 file:// 前缀
    let path: string = uri.replace(/^file:\/\//i, '');
    // 去掉末尾的 / 或 \
    path = path.replace(/[\/\\]+$/, '');
    if (path.length === 0) {
      return '';
    }
    // 按 / 或 \ 分割，取最后一个非空段
    const segments: string[] = path.split(/[\/\\]/).filter((s: string) => s.length > 0);
    if (segments.length === 0) {
      return '';
    }
    let name: string = segments[segments.length - 1];
    // 解码 URL 编码（如 %E6%B5%8B → 测），使中文目录名可读
    try {
      name = decodeURIComponent(name);
    } catch (e) {
      // 解码失败（非标准编码），返回原始字符串
    }
    return name;
  }
}
