import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppContext } from './AppContext';

/**
 * 操作日志工具，对齐安卓端 util/LogUtil。
 * 日志写入应用沙箱 filesDir/operation_log.log（追加），同时打印到控制台。
 * 关键业务（创建/更新/删除配置、扫描、删除、标记重复、一键清理、导出）均调用 logOperation 记录。
 */
export class LogUtil {
  private static readonly LOG_FILE: string = 'operation_log.log';

  private static logPath(): string {
    const ctx = AppContext.get();
    if (!ctx) {
      return '';
    }
    return `${ctx.filesDir}/${LogUtil.LOG_FILE}`;
  }

  public static i(tag: string, msg: string): void {
    LogUtil.write('I', tag, msg);
  }

  public static w(tag: string, msg: string): void {
    LogUtil.write('W', tag, msg);
  }

  public static e(tag: string, msg: string): void {
    LogUtil.write('E', tag, msg);
  }

  /** 记录一次关键业务操作（统一 OP 级别，供日志页/导出使用）。 */
  public static operation(action: string, detail: string): void {
    LogUtil.write('OP', action, detail);
  }

  private static write(level: string, tag: string, msg: string): void {
    const line: string = `[${LogUtil.now()}] [${level}] ${tag}: ${msg}\n`;
    console.info(line);
    const path: string = LogUtil.logPath();
    if (path.length === 0) {
      return;
    }
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.APPEND | fileIo.OpenMode.CREATE);
      fileIo.writeSync(file.fd, line);
      fileIo.closeSync(file);
    } catch (e) {
      // 日志写入失败不影响主流程
    }
  }

  private static now(): string {
    const d: Date = new Date();
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
      `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  /** 读取全部日志（供日志页展示、导出）。 */
  public static readAll(): string {
    const path: string = LogUtil.logPath();
    if (path.length === 0) {
      return '';
    }
    try {
      const stat = fileIo.statSync(path);
      if (!stat.isFile) {
        return '';
      }
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (e) {
      return '';
    }
  }
}
