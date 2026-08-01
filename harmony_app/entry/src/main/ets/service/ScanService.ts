import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { ScannedFile } from '../model/ScannedFile';
import { ChineseConverter } from '../utils/ChineseConverter';
import { ScanConfig } from '../model/ScanConfig';
import { ScanRun } from '../model/ScanRun';
import { KeywordReplaceRule } from '../model/KeywordReplaceRule';
import { ScanRunDao } from '../database/ScanRunDao';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { KeywordReplaceDao } from '../database/KeywordReplaceDao';
import { Parser } from '../utils/Parser';
import { KeywordReplace } from '../utils/KeywordReplace';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';
import { FilePermissionUtil } from '../utils/FilePermissionUtil';

export interface ScanProgress {
  processed: number;
  found: number;
  currentFile: string;
}

/**
 * 扫描服务：用 DocumentViewPicker 选择用户目录（已授权），递归遍历 txt 等文件，
 * 解析文件名得到 书名/作者/进度/来源，并应用关键词替换规则，增量写入数据库。
 *
 * 对齐安卓端 FileUtil 优化：
 *  1) 支持外部调用 stop() 立即停止扫描，已收集结果会保留；
 *  2) 进度回调节流，避免 10w 级文件压垮 UI；
 *  3) 保持增量批量写入，即使扫描被中止也不丢已解析结果；
 *  4) 采用 BFS 层级遍历，对同层目录顺序枚举，避免深目录爆栈。
 *
 * 关于 Android SAF "批量 children 查询 + 线程池并行" 的对齐说明：
 * 鸿蒙端 fileIo.listFile(dir) 一次 IPC 即返回整个目录的子项列表，天然等效于
 * DocumentsContract.buildChildDocumentsUriUsingTree 的批量 children 查询，无需像
 * Android SAF 那样逐文件 IPC。HarmonyOS NEXT 的文件 API 当前以同步调用为主，
 * 若后续真机测试出现 10w+ 文件扫描过慢，可再引入 @concurrent + taskpool/worker
 * 将目录枚举放到工作线程；目前单线程 BFS 配合增量写入与回调节流已能满足常规需求。
 *
 * 注意：HarmonyOS 的文件访问 API 在真机/模拟器上请以开发者文档为准；
 * 此处采用 Picker 授权 URI + fileIo 遍历的通用写法，并在遍历时对目录/文件用 URI 拼接子项。
 */
export class ScanService {
  private static readonly BATCH_SIZE: number = 200;
  private static readonly PROGRESS_INTERVAL: number = 16;
  private static stopped: boolean = false;

  /** 请求停止当前正在进行的扫描。runScan 会在下一个检查点退出。 */
  public static stop(): void {
    ScanService.stopped = true;
    LogUtil.i('ScanService', '收到停止扫描请求');
  }

  /**
   * 选择目录，返回用户选中的目录 URI（已获访问授权）。用户取消时返回空字符串。
   *
   * 策略：优先使用 FOLDER 模式直接选择文件夹（对齐安卓端体验）。
   * FOLDER 选择能力仅 API 26.0.0+ 的 Phone 设备支持；低版本（如 API 24 模拟器）
   * 会出现「对话框可打开但无法完成选中且不抛异常」的问题，因此需通过 canIUse
   * 前置检测直接降级为「选择文件推导父目录」方案；若支持但实际调用仍抛异常，同样降级。
   *
   * @param context  Ability 上下文
   * @param defaultUri  可选，上次选择的 URI，用于预设 Picker 打开位置（更好的 UX）
   */
  public static async selectDirectory(context: common.Context, defaultUri?: string): Promise<string> {
    const documentPicker = new picker.DocumentViewPicker(context);

    // ===== 选择策略说明（重要，经真机验证）=====
    // canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection') 在
    // HarmonyOS 6.1.1（API 24）手机上会返回 true，但 FOLDER 模式实际调用时表现为
    // 「对话框可打开、目录内容为空、无法完成选中且不抛异常」——try/catch 降级因此
    // 永远不会触发，用户会被卡死在无效的 FOLDER 选择器中。
    // 同时，官方文档明确 FOLDER 模式仅在 API 26.0.0+ 的 Phone 设备上受支持。
    // 结论：放弃依赖 FOLDER 模式，统一使用「FILE 模式选文件 → 自动定位所在文件夹」方案，
    // 这是手机端官方推荐的可靠路径，兼容 API 24 及更高版本。
    LogUtil.i('ScanService', '使用文件推导方案选择目录（放弃 FOLDER 模式，兼容 API 24 手机）');

    // 首次选择（无历史目录）时给出操作指引，避免用户在 FILE 模式下困惑「如何选文件夹」
    if (!defaultUri || defaultUri.length === 0) {
      await promptAction.showDialog({
        title: '如何选择文件夹',
        message: '当前系统不支持直接点选文件夹。\n\n请先进入目标文件夹，然后选择其中的任意一个文件，应用会自动把「该文件所在的文件夹」作为扫描目录。',
        buttons: [
          { text: '我知道了', color: '#2D6A4F' }
        ]
      });
    }

    // 选择一个文件，自动定位其父目录作为扫描目录
    const fileOptions = new picker.DocumentSelectOptions();
    fileOptions.maxSelectNumber = 1;
    // defaultFilePathUri 必须是 file://docs/... 格式的 URI；若历史记录为裸路径则忽略，
    // 避免非法默认路径导致选择器打开后内容为空。
    if (defaultUri && defaultUri.startsWith('file://')) {
      fileOptions.defaultFilePathUri = defaultUri;
    }
    const fileUris: string[] = await documentPicker.select(fileOptions);
    if (fileUris.length === 0) {
      return '';
    }

    const fileUriStr: string = fileUris[0];
    try {
      const fileUriObj: fileUri.FileUri = new fileUri.FileUri(fileUriStr);
      const parentDirUri: string = fileUriObj.getFullDirectoryUri();

      // 尝试持久化父目录权限
      try {
        await FilePermissionUtil.persistFolderPermission(parentDirUri);
      } catch (e) {
        // 持久化失败不影响当前使用
      }

      // 校验可访问性：先试 URI，再试 path（裸路径）
      // Picker 只授权了文件本身，父目录的 URI 访问可能失败；
      // 但 path 方式可能因系统实现差异而可用（部分机型 Picker 会授予更广的文件系统访问）。
      let uriAccessible: boolean = false;
      try {
        await fileIo.listFile(parentDirUri);
        uriAccessible = true;
        LogUtil.i('ScanService', `URI 访问成功: ${parentDirUri}`);
      } catch (e1) {
        LogUtil.w('ScanService', `URI 访问失败，尝试 path: ${(e1 as Error).message}`);
      }

      if (uriAccessible) {
        return parentDirUri;
      }

      // URI 失败，尝试 path 方式
      try {
        const parentPath: string = fileUriObj.path ? new fileUri.FileUri(parentDirUri).path : parentDirUri;
        await fileIo.listFile(parentPath);
        LogUtil.i('ScanService', `path 访问成功: ${parentPath}`);
        return parentPath;
      } catch (e2) {
        LogUtil.e('ScanService', `path 访问也失败: ${(e2 as Error).message}`);
        // 两种方式都失败，仍返回 URI（后续 runScan 会再试一次并给出明确错误提示）
        return parentDirUri;
      }
    } catch (e) {
      LogUtil.e('ScanService', `父目录推导失败: ${(e as Error).message}`);
      throw new Error('无法访问所选文件的父目录，请确保选择了目标文件夹中的文件');
    }
  }

  /**
   * 尝试访问一个之前选过的目录 URI。
   * 如果权限仍有效，直接返回；如果失效，尝试用 authMode 重新授权。
   *
   * @returns 可访问的 URI（原 URI 或重新授权后的 URI），不可访问返回空字符串
   */
  public static async tryAccessOrReauthorize(context: common.Context, uri: string): Promise<string> {
    // 1. 权限仍有效，直接返回
    if (FilePermissionUtil.checkUriAccessible(uri)) {
      return uri;
    }

    LogUtil.w('ScanService', `URI 权限已失效，尝试重新授权: ${uri}`);

    // 2. 尝试用 authMode 重新授权
    const reauthorized: boolean = await FilePermissionUtil.reauthorizeUri(context, uri);
    if (reauthorized && FilePermissionUtil.checkUriAccessible(uri)) {
      return uri;
    }

    // 3. 重新授权也失败了
    LogUtil.e('ScanService', `重新授权失败，需要用户重新选择目录`);
    return '';
  }

  /** 执行一次扫描，返回新建的文库 id 与扫到的文件数。 */
  public static async runScan(
    config: ScanConfig,
    onProgress: (p: ScanProgress) => void
  ): Promise<{ runId: number; total: number; stopped: boolean }> {
    ScanService.stopped = false;
    const run: ScanRun = new ScanRun();
    run.name = config.name;
    run.folderUri = config.folderUri;
    run.folderName = config.folderName;
    run.fileTypes = config.fileTypes;
    run.createdAt = Date.now();
    run.fileCount = 0;
    const runId: number = await ScanRunDao.insert(run);

    // 关键词替换规则（已启用、按 scope）
    const scanRules: KeywordReplaceRule[] = await KeywordReplaceDao.getEnabledByScope(KeywordReplace.SCOPE_SCAN);
    const parseRules: KeywordReplaceRule[] = await KeywordReplaceDao.getEnabledByScope(KeywordReplace.SCOPE_PARSE);

    const batch: ScannedFile[] = [];
    let processed: number = 0;
    let found: number = 0;
    let lastReportProcessed: number = 0;
    let currentLevel: string[] = [config.folderUri];

    const flushBatch = async (): Promise<void> => {
      if (batch.length > 0) {
        await ScannedFileDao.insertBatch(batch);
        batch.length = 0;
      }
    };

    const reportProgress = (currentFile: string, force: boolean = false): void => {
      if (force || processed - lastReportProcessed >= ScanService.PROGRESS_INTERVAL) {
        onProgress({ processed: processed, found: found, currentFile: currentFile });
        lastReportProcessed = processed;
      }
    };

    while (currentLevel.length > 0 && !ScanService.stopped) {
      const nextLevel: string[] = [];
      for (const dir of currentLevel) {
        if (ScanService.stopped) {
          break;
        }
        let names: string[] = [];
        try {
          names = await fileIo.listFile(dir);
        } catch (e) {
          // URI 访问失败，尝试转换为 path 再试
          LogUtil.w('ScanService', `listFile(URI) 失败，尝试 path: ${dir} -> ${(e as Error).message}`);
          try {
            let pathStr: string = dir;
            if (dir.startsWith('file://')) {
              pathStr = new fileUri.FileUri(dir).path;
            }
            // 异步枚举，避免同步 listFileSync 在 10w+ 文件目录下阻塞 UI 线程。
            names = await fileIo.listFile(pathStr);
          } catch (e2) {
            LogUtil.e('ScanService', `遍历目录失败(URI+path 均失败): ${dir} -> ${(e2 as Error).message}`);
            // 如果是根目录就失败，向上抛出明确错误
            if (dir === config.folderUri) {
              throw new Error(`无法访问扫描目录，请重新选择目录。错误: ${(e2 as Error).message}`);
            }
            continue;
          }
        }
        for (const name of names) {
          if (ScanService.stopped) {
            break;
          }
          const childUri: string = dir.endsWith('/') ? `${dir}${name}` : `${dir}/${name}`;
          let stat: fileIo.Stat | null = null;
          try {
            stat = await fileIo.stat(childUri);
          } catch (e) {
            continue;
          }
          if (stat.isDirectory()) {
            if (config.recursive && !ScanService.isExcluded(name, config.excludedFolders)) {
              nextLevel.push(childUri);
            }
          } else {
            processed++;
            const ext: string = FormatUtil.getExtension(name);
            if (!ScanService.matchExt(ext, config.fileTypes)) {
              continue;
            }
            if (stat.size / 1024 < config.minSizeKb) {
              continue;
            }
            let fileName: string = name;
            if (scanRules.length > 0) {
              fileName = KeywordReplace.applyRules(fileName, scanRules) ?? fileName;
            }
            const parsed = Parser.parseFileName(fileName);
            if (parseRules.length > 0) {
              parsed.title = KeywordReplace.applyRules(parsed.title, parseRules) ?? parsed.title;
              parsed.author = KeywordReplace.applyRules(parsed.author, parseRules) ?? parsed.author;
              parsed.progress = KeywordReplace.applyRules(parsed.progress, parseRules) ?? parsed.progress;
              parsed.source = KeywordReplace.applyRules(parsed.source, parseRules) ?? parsed.source;
            }
            const rec: ScannedFile = new ScannedFile();
            rec.path = childUri;
            rec.fileName = fileName;
            rec.fileSize = stat.size;
            rec.title = parsed.title;
            rec.author = parsed.author;
            rec.progress = parsed.progress;
            rec.source = parsed.source;
            rec.encoding = await ScanService.detectEncoding(childUri);
            rec.titlePinyin = ChineseConverter.toPinyin(parsed.title);
            rec.authorPinyin = ChineseConverter.toPinyin(parsed.author);
            rec.contentHash = config.exactHash ? await ScanService.computeMd5(childUri) : '';
            rec.ext = ext;
            rec.scanRunId = runId;
            rec.createdAt = Date.now();
            // stat.mtime 为最后修改时间；不同 API 版本可能是秒或毫秒，统一归一化为毫秒
            const rawMtime: number = stat.mtime ? Number(stat.mtime) : 0;
            rec.fileDate = rawMtime > 0 ? (rawMtime < 1e12 ? rawMtime * 1000 : rawMtime) : 0;
            batch.push(rec);
            found++;
            if (batch.length >= ScanService.BATCH_SIZE) {
              await flushBatch();
            }
            reportProgress(name);
          }
        }
      }
      currentLevel = nextLevel;
    }

    await flushBatch();
    await ScanRunDao.updateFileCount(runId, found);
    const status: string = ScanService.stopped ? '已停止' : '完成';
    LogUtil.operation('扫描', `文库=${config.name} 目录=${config.folderName} 命中=${found} 状态=${status} 文库ID=${runId}`);
    return { runId: runId, total: found, stopped: ScanService.stopped };
  }

  private static isExcluded(name: string, excluded: string): boolean {
    if (!excluded || excluded.trim().length === 0) {
      return false;
    }
    const list: string[] = excluded
      .split(/[;；,，]/)
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
    return list.includes(name);
  }

  private static matchExt(ext: string, fileTypes: string): boolean {
    if (!fileTypes || fileTypes.trim().length === 0) {
      return ext === 'txt' || ext === '';
    }
    const list: string[] = fileTypes
      .split(/[;；,，\s]+/)
      .map((s) => s.trim().toLowerCase())
      .filter((s) => s.length > 0);
    if (list.length === 0) {
      return true;
    }
    return list.includes(ext);
  }

  /**
   * 计算文件内容 MD5（仅当开启精确哈希时调用）。
   * 全程使用异步文件 I/O（open/read/close），避免同步调用阻塞 UI 线程导致 ANR/黑屏。
   */
  private static async computeMd5(uri: string): Promise<string> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const md = cryptoFramework.createMd('MD5');
      const CHUNK: number = 1024 * 1024;
      let off: number = 0;
      while (true) {
        const buf: ArrayBuffer = new ArrayBuffer(CHUNK);
        const len: number = await fileIo.read(file.fd, buf, { offset: off, length: CHUNK });
        if (len <= 0) {
          break;
        }
        md.updateSync({ data: new Uint8Array(buf.slice(0, len)) });
        off += len;
        if (len < CHUNK) {
          break;
        }
      }
      const digest = md.digestSync();
      const bytes: Uint8Array = new Uint8Array(digest.data);
      let hex: string = '';
      for (let i = 0; i < bytes.length; i++) {
        hex += bytes[i].toString(16).padStart(2, '0');
      }
      return hex;
    } finally {
      await fileIo.close(file);
    }
  }

  /**
   * 轻量编码探测：仅读取文件头部 4KB，按 BOM → UTF-8 校验 → GBK 兜底 顺序判定。
   * 对齐安卓端 EncodingDetector，扫描时调用以填充 ScannedFile.encoding。
   * 使用异步文件 I/O（open/read/close），避免每个文件的同步 I/O 阻塞 UI 线程
   * （10w 文件 × 同步 open/read/close 必然导致 ANR/黑屏）。
   */
  private static async detectEncoding(uri: string): Promise<string> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const HEAD: number = 4096;
      const buf: ArrayBuffer = new ArrayBuffer(HEAD);
      const len: number = await fileIo.read(file.fd, buf);
      if (len <= 0) {
        return '';
      }
      const bytes: Uint8Array = new Uint8Array(buf.slice(0, len));
      // UTF-8 BOM
      if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
        return 'UTF-8';
      }
      // UTF-16 LE BOM
      if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
        return 'UTF-16LE';
      }
      // UTF-16 BE BOM
      if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
        return 'UTF-16BE';
      }
      // UTF-8 严格校验
      if (ScanService.isValidUtf8(bytes)) {
        return 'UTF-8';
      }
      // 兜底 GBK
      return 'GBK';
    } catch (e) {
      return '';
    } finally {
      await fileIo.close(file);
    }
  }

  private static isValidUtf8(bytes: Uint8Array): boolean {
    let i: number = 0;
    while (i < bytes.length) {
      const b: number = bytes[i];
      if (b <= 0x7F) {
        i++;
      } else if (b >= 0xC2 && b <= 0xDF) {
        if (i + 1 >= bytes.length || (bytes[i + 1] & 0xC0) !== 0x80) return false;
        i += 2;
      } else if (b === 0xE0) {
        if (i + 2 >= bytes.length || bytes[i + 1] < 0xA0 || bytes[i + 1] > 0xBF ||
          (bytes[i + 2] & 0xC0) !== 0x80) return false;
        i += 3;
      } else if (b >= 0xE1 && b <= 0xEF) {
        if (i + 2 >= bytes.length || (bytes[i + 1] & 0xC0) !== 0x80 ||
          (bytes[i + 2] & 0xC0) !== 0x80) return false;
        i += 3;
      } else if (b === 0xF0) {
        if (i + 3 >= bytes.length || bytes[i + 1] < 0x90 || bytes[i + 1] > 0xBF ||
          (bytes[i + 2] & 0xC0) !== 0x80 || (bytes[i + 3] & 0xC0) !== 0x80) return false;
        i += 4;
      } else if (b >= 0xF1 && b <= 0xF3) {
        if (i + 3 >= bytes.length || (bytes[i + 1] & 0xC0) !== 0x80 ||
          (bytes[i + 2] & 0xC0) !== 0x80 || (bytes[i + 3] & 0xC0) !== 0x80) return false;
        i += 4;
      } else if (b >= 0xF4 && b <= 0xF7) {
        if (i + 3 >= bytes.length || bytes[i + 1] < 0x80 || bytes[i + 1] > 0x8F ||
          (bytes[i + 2] & 0xC0) !== 0x80 || (bytes[i + 3] & 0xC0) !== 0x80) return false;
        i += 4;
      } else {
        return false;
      }
    }
    return true;
  }
}
