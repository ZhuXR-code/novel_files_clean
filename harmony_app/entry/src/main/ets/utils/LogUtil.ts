import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';

/**
 * 操作日志工具，对齐安卓端 util/LogUtil。
 * 日志写入应用沙箱 filesDir/operation_log.log（追加），同时打印到控制台。
 * 关键业务（创建/更新/删除配置、扫描、删除、勾选重复、一键清理、导出）均调用 logOperation 记录。
 *
 * 性能：采用「句柄常开 + 缓冲批量刷盘」，避免每条日志都 open/write/close 三次同步系统调用
 * （扫描/删除 10w 文件时热路径频繁记日志，原实现会严重阻塞 UI）。
 */
export class LogUtil {
  private static readonly LOG_FILE: string = 'operation_log.log';
  private static readonly DOMAIN: number = 0x0001;
  private static readonly HILOG_TAG: string = 'HarmonyCleaner';
  /** 缓冲达到该条数时强制刷盘。 */
  private static readonly FLUSH_THRESHOLD: number = 50;
  /** 缓冲达到该字节数时强制刷盘。 */
  private static readonly FLUSH_BYTES: number = 32 * 1024;

  /** 常开文件描述符（APPEND 模式），-1 表示未打开/已失效。 */
  private static fd: number = -1;
  /** 待刷盘的日志行缓冲。 */
  private static buffer: string[] = [];
  private static bufferedBytes: number = 0;

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
    const hilogTag: string = `${LogUtil.HILOG_TAG}/${level}/${tag}`;
    switch (level) {
      case 'W':
        hilog.warn(LogUtil.DOMAIN, hilogTag, '%{public}s', msg);
        break;
      case 'E':
        hilog.error(LogUtil.DOMAIN, hilogTag, '%{public}s', msg);
        break;
      default:
        hilog.info(LogUtil.DOMAIN, hilogTag, '%{public}s', msg);
        break;
    }
    const path: string = LogUtil.logPath();
    if (path.length === 0) {
      return;
    }
    // 入缓冲，达到阈值再批量刷盘，避免每条日志 open/write/close 三次同步系统调用。
    LogUtil.buffer.push(line);
    LogUtil.bufferedBytes += line.length;
    if (LogUtil.buffer.length >= LogUtil.FLUSH_THRESHOLD || LogUtil.bufferedBytes >= LogUtil.FLUSH_BYTES) {
      LogUtil.flush();
    }
  }

  /** 将缓冲区批量写入文件（保持句柄常开，失败时重置句柄以便下次重开）。 */
  private static flush(): void {
    if (LogUtil.buffer.length === 0) {
      return;
    }
    const path: string = LogUtil.logPath();
    if (path.length === 0) {
      return;
    }
    try {
      if (LogUtil.fd < 0) {
        const file = fileIo.openSync(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND | fileIo.OpenMode.CREATE);
        LogUtil.fd = file.fd;
      }
      fileIo.writeSync(LogUtil.fd, LogUtil.buffer.join(''));
      LogUtil.buffer = [];
      LogUtil.bufferedBytes = 0;
    } catch (e) {
      // 句柄可能失效（文件被删/权限变化），重置以便下次写入重新打开。
      hilog.error(LogUtil.DOMAIN, `${LogUtil.HILOG_TAG}/E/LogUtil`, '日志文件写入失败: %{public}s', (e as Error).message);
      if (LogUtil.fd >= 0) {
        try {
          fileIo.closeSync(LogUtil.fd);
        } catch (ce) {
          // 关闭失败忽略
        }
      }
      LogUtil.fd = -1;
      LogUtil.buffer = [];
      LogUtil.bufferedBytes = 0;
    }
  }

  private static now(): string {
    const d: Date = new Date();
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
      `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  /** 读取全部日志（供日志页展示、导出）。异步读取避免大日志文件阻塞 UI 线程。 */
  public static async readAll(): Promise<string> {
    // 先把缓冲写入文件，保证读取到最新日志（flush 保持同步，写入量小且已缓冲）。
    LogUtil.flush();
    const path: string = LogUtil.logPath();
    if (path.length === 0) {
      return '';
    }
    try {
      const stat = await fileIo.stat(path);
      if (!stat.isFile) {
        return '';
      }
      // 限制单次读取上限，避免日志文件增长到数十 MB 时一次性占满内存。
      const MAX_READ: number = 8 * 1024 * 1024;
      const size: number = Math.min(stat.size, MAX_READ);
      const offset: number = stat.size > MAX_READ ? stat.size - MAX_READ : 0;
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      try {
        const buf: ArrayBuffer = new ArrayBuffer(size);
        await fileIo.read(file.fd, buf, { offset: offset, length: size });
        const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
        return decoder.decodeToString(new Uint8Array(buf));
      } finally {
        await fileIo.close(file);
      }
    } catch (e) {
      return '';
    }
  }

  /** 清空全部日志。 */
  public static async clear(): Promise<void> {
    const path: string = LogUtil.logPath();
    if (path.length === 0) {
      return;
    }
    // 关闭常开句柄并清空缓冲，再以 TRUNC 模式重建空文件。
    LogUtil.buffer = [];
    LogUtil.bufferedBytes = 0;
    if (LogUtil.fd >= 0) {
      // 常开句柄仅持有 fd（number），异步 close 只接受 File 对象，故保留 closeSync 关闭 fd；
      // 关闭单个 fd 为极轻量操作，不会阻塞 UI。
      try {
        fileIo.closeSync(LogUtil.fd);
      } catch (e) {
        // 关闭失败忽略
      }
      LogUtil.fd = -1;
    }
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.close(file);
    } catch (e) {
      // 清空失败忽略
    }
  }
}
