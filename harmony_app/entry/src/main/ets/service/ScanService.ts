import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
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
import { PreferencesUtil } from '../utils/PreferencesUtil';

export interface ScanProgress {
  processed: number;
  found: number;
  currentFile: string;
  excluded?: number;
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
  private static readonly MAX_FILE_PICK: number = 99999;
  private static stopped: boolean = false;
  /**
   * 低版本系统（API < 26）不支持 FOLDER 模式时，selectDirectory 会改为 FILE 多选。
   * 选中的文件 URI 临时存于此，runScan 检测到非空时直接逐文件扫描，不再 listFile 父目录。
   */
  private static selectedFileUris: string[] = [];

  /** 请求停止当前正在进行的扫描。runScan 会在下一个检查点退出。 */
  public static stop(): void {
    ScanService.stopped = true;
    LogUtil.i('ScanService', '收到停止扫描请求');
  }

  /**
   * 当前是否处于「多选文件回退」模式。UI 可据此给出不同提示。
   */
  public static useFileFallback(): boolean {
    return ScanService.selectedFileUris.length > 0;
  }

  private static readonly PREF_FILE_URIS: string = 'scan_selected_file_uris';

  /**
   * 保存 FILE 回退模式选中的文件 URI 列表。
   * selectedFileUris 是内存静态变量，应用重启即丢失；同时写入 Preferences，
   * 重启后 runScan 可恢复，避免「重新进入扫描时报扫描失败」。
   */
  private static saveFileFallback(uris: string[]): void {
    ScanService.selectedFileUris = [...uris];
    PreferencesUtil.putString(ScanService.PREF_FILE_URIS, uris.join('\n'));
  }

  /**
   * 从持久化存储恢复上次 FILE 回退选中的文件列表（仅当内存列表为空时）。
   * @returns 是否存在可用的文件列表
   */
  public static restoreFileFallback(): boolean {
    if (ScanService.selectedFileUris.length > 0) {
      return true;
    }
    const raw: string = PreferencesUtil.getString(ScanService.PREF_FILE_URIS, '');
    if (raw.length === 0) {
      return false;
    }
    ScanService.selectedFileUris = raw.split('\n').filter((s: string) => s.length > 0);
    return ScanService.selectedFileUris.length > 0;
  }

  /** 清空 FILE 回退缓存（内存 + 持久化）。 */
  public static clearFileFallback(): void {
    ScanService.selectedFileUris = [];
    PreferencesUtil.putString(ScanService.PREF_FILE_URIS, '');
  }

  /**
   * 选择扫描目标，返回用户选中的「目录展示 URI」（已获访问授权）。用户取消时返回空字符串。
   *
   * 策略（三级降级）：
   *  1. FOLDER 目录选择（API 26+）：选中目录即授权整棵目录树，可持久化并 listFile 递归遍历，
   *     天然支撑 10w 级文件扫描，为主方案。
   *  2. 选文件定位目录（保留旧模式）：FOLDER 不可用/未选中时，用户选一个或多个文件，
   *     若其父目录可访问则扫描整个文件夹（见 pickFiles）。
   *  3. FILE 多选兜底：父目录不可遍历时，逐文件扫描选中的文件。
   *
   * @param context  Ability 上下文
   * @param defaultUri  可选，上次选择的 URI，用于预设 Picker 打开位置（更好的 UX）
   */
  public static async selectDirectory(context: common.Context, defaultUri?: string): Promise<string> {
    // 先清空上次的文件缓存（内存 + 持久化），避免旧列表影响新配置。
    ScanService.clearFileFallback();
    // FOLDER 模式优先：直接选目录，授权整棵树，可递归遍历扫描。
    if (ScanService.canPickFolder()) {
      const folderUri: string = await ScanService.tryPickFolder(context, defaultUri);
      if (folderUri.length > 0) {
        return folderUri;
      }
      LogUtil.w('ScanService', 'FOLDER 模式未选中目录，降级为 FILE 多选');
    } else {
      LogUtil.i('ScanService', '当前设备不支持 FOLDER 模式，使用 FILE 多选兜底');
    }
    return ScanService.pickFiles(context, defaultUri);
  }

  /**
   * 设备是否支持 FOLDER（目录选择）模式。
   * FOLDER 模式由 Picker 的 selectMode=DocumentSelectMode.FOLDER 提供，需 API 26+ 手机。
   */
  private static canPickFolder(): boolean {
    try {
      return deviceInfo.sdkApiVersion >= 26;
    } catch (e) {
      // 拿不到 SDK 版本时保守降级为 FILE 多选
      return false;
    }
  }

  /**
   * FOLDER 模式：让用户在 Picker 中直接选择一个文件夹。
   * 选中目录即获得整棵目录树的访问授权，持久化后 listFile 可递归遍历。
   *
   * @returns 选中的目录 URI；用户取消或失败返回空字符串
   */
  private static async tryPickFolder(context: common.Context, defaultUri?: string): Promise<string> {
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      // 必须声明 FOLDER 模式：否则 Picker 默认打开「文件」选择器，用户选到的是
      // 文件 URI，后续 listFile 遍历目录会失败，导致「点击扫描提示扫描失败」。
      // （从 API 26.0.0 开始支持 selectMode + FOLDER）
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      if (defaultUri && defaultUri.startsWith('file://')) {
        options.defaultFilePathUri = defaultUri;
      }
      const uris: string[] = await documentPicker.select(options);
      if (!uris || uris.length === 0) {
        return '';
      }
      const folderUri: string = uris[0];
      // 持久化目录授权（读写模式），重启后自动激活
      try {
        await FilePermissionUtil.persistFolderPermission(folderUri);
        LogUtil.i('ScanService', `已持久化目录授权: ${folderUri}`);
      } catch (e) {
        LogUtil.w('ScanService', `持久化目录授权失败: ${(e as Error).message}`);
      }
      LogUtil.i('ScanService', `FOLDER 模式选择成功: ${folderUri}`);
      return folderUri;
    } catch (e) {
      LogUtil.w('ScanService', `FOLDER 模式选择失败，降级 FILE 多选: ${(e as Error).message}`);
      return '';
    }
  }

  /**
   * 文件定位模式（FOLDER 不可用时的降级方案，保留旧行为）：
   * 让用户在 Picker 中选中一个或多个文件，应用先尝试推导其父目录：
   *  - 父目录可访问（listFile 成功）→ 返回父目录 URI，runScan 扫描整个文件夹；
   *  - 父目录不可访问（如文档卷未授权父目录）→ 回退逐文件扫描 selectedFileUris。
   */
  private static async pickFiles(context: common.Context, defaultUri?: string): Promise<string> {
    // 首次使用时给出明确指引
    await promptAction.showDialog({
      title: '选择文件以定位文件夹',
      message: '当前设备不支持直接选择文件夹。\n\n请在文件选择器中进入目标文件夹，选中其中的一个或多个文件：\n· 若文件所在文件夹可访问，将扫描整个文件夹；\n· 否则仅扫描您选中的文件。',
      buttons: [{ text: '我知道了', color: '#2D6A4F' }]
    });

    const documentPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = ScanService.MAX_FILE_PICK;
    if (defaultUri && defaultUri.startsWith('file://')) {
      options.defaultFilePathUri = defaultUri;
    }
    const uris: string[] = await documentPicker.select(options);
    if (!uris || uris.length === 0) {
      return '';
    }

    // 持久化每个选中文件的授权（每个文件都有独立的 picker 临时授权，可持久化）
    try {
      await FilePermissionUtil.persistUris(uris);
      LogUtil.i('ScanService', `已持久化 ${uris.length} 个选中文件的授权`);
    } catch (e) {
      LogUtil.w('ScanService', `持久化文件授权失败: ${(e as Error).message}`);
    }

    // 取共同父目录
    let parentDirUri: string = '';
    try {
      const fileUriObj = new fileUri.FileUri(uris[0]);
      parentDirUri = fileUriObj.getFullDirectoryUri();
    } catch (e) {
      LogUtil.w('ScanService', `推导父目录失败: ${(e as Error).message}`);
      parentDirUri = uris[0];
    }

    // 优先整目录扫描：父目录可访问（listFile 成功）时，选中文件仅用于定位文件夹，
    // runScan 对父目录做 BFS 遍历，扫描其下全部文件——保留「选文件→推导父目录→扫文件夹」模式。
    if (parentDirUri.length > 0 && (await FilePermissionUtil.checkUriAccessible(parentDirUri))) {
      ScanService.selectedFileUris = [];
      // 关键：仅持久化选中文件们，重启后父目录授权不会自动恢复（picker 授权的是
      // 文件而非父目录），再次扫描 listFile 父目录必然失败。这里同时持久化父目录
      // 授权，保证应用重启后仍可遍历整个文件夹。
      try {
        await FilePermissionUtil.persistFolderPermission(parentDirUri);
        LogUtil.i('ScanService', `已持久化父目录授权: ${parentDirUri}`);
      } catch (e) {
        LogUtil.w('ScanService', `持久化父目录授权失败: ${(e as Error).message}`);
      }
      LogUtil.i('ScanService', `已定位目录（选中 ${uris.length} 个文件），将扫描整个文件夹: ${parentDirUri}`);
      return parentDirUri;
    }

    // 父目录不可访问（如文档卷未授权父目录）：回退为逐文件扫描选中列表。
    // 列表需持久化：selectedFileUris 是内存变量，重启丢失后 runScan 会错误地走
    // BFS 遍历不可访问的父目录导致「扫描失败」。
    ScanService.saveFileFallback(uris);
    LogUtil.i('ScanService', `FILE 多选：共选 ${uris.length} 个文件，父目录不可遍历，逐文件扫描`);
    return parentDirUri;
  }

  /**
   * 尝试访问一个之前选过的目录 URI。
   * 如果权限仍有效，直接返回；如果失效，尝试用 authMode 重新授权。
   *
   * @returns 可访问的 URI（原 URI 或重新授权后的 URI），不可访问返回空字符串
   */
  public static async tryAccessOrReauthorize(context: common.Context, uri: string): Promise<string> {
    // 1. 权限仍有效，直接返回
    if (await FilePermissionUtil.checkUriAccessible(uri)) {
      return uri;
    }

    LogUtil.w('ScanService', `URI 权限已失效，尝试重新授权: ${uri}`);

    // 2. 尝试用 authMode 重新授权
    const reauthorized: boolean = await FilePermissionUtil.reauthorizeUri(context, uri);
    if (reauthorized && (await FilePermissionUtil.checkUriAccessible(uri))) {
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
  ): Promise<{ runId: number; total: number; processed: number; stopped: boolean }> {
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

    // FILE 多选回退模式（低版本手机不支持 FOLDER 模式）：
    // selectDirectory 已把用户选中的文件 URI 保存到 selectedFileUris（并持久化），
    // 每个文件都已单独授权。直接逐文件处理，不再尝试 listFile 父目录，
    // 避免 Operation not permitted；重启后内存列表为空时从持久化恢复。
    if (ScanService.selectedFileUris.length > 0 || ScanService.restoreFileFallback()) {
      return ScanService.runScanFromFiles(config, onProgress, run, runId, scanRules, parseRules);
    }

    const batch: ScannedFile[] = [];
    let processed: number = 0;
    let found: number = 0;
    let excluded: number = 0;
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

    // 解析"排除原始书名 / 排除书名词汇"：命中任一项的书名在解析后剔除（等同该文件被跳过，不入库）
    const titleExcludes = ScanService.parseTitleExcludes(config);

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
          // fileIo.listFile 对文档树/文件 URI 的返回值有两种形态：
          //   1) 子项「完整 URI」（含 scheme，如 file:///.../Books/sub）——官方文档主形态；
          //   2) 子项「纯文件名」（如 "sub"）——对真实文件系统路径文件 URI 的返回。
          // 之前一律按纯文件名做 `${dir}/${name}` 字符串拼接，当 name 已是完整 URI 时
          // 会拼出 `${docTreeUri}/file:///.../sub` 这种非法 URI，fileIo.stat 抛异常被
          // catch 跳过，子目录永远进不了 nextLevel，递归只跑第一层就结束——即「递归
          // 扫描没有生效」。这里先归一化为正确的子项 URI。
          let childUri: string;
          if (name.includes('://')) {
            childUri = name; // listFile 已返回完整子项 URI，直接用
          } else if (name.startsWith('/')) {
            childUri = `file://${name}`; // 真实绝对路径，补 scheme
          } else {
            // 纯文件名：优先用 FileUri 基于父 URI 正确构造层级 URI（文档树 URI 不能简单拼接）
            try {
              const parentObj = new fileUri.FileUri(dir);
              const basePath: string = parentObj.path ?? '';
              if (basePath.length > 0) {
                const subPath: string = basePath.endsWith('/') ? `${basePath}${name}` : `${basePath}/${name}`;
                childUri = new fileUri.FileUri(subPath).toString();
              } else {
                childUri = dir.endsWith('/') ? `${dir}${name}` : `${dir}/${name}`;
              }
            } catch (e) {
              childUri = dir.endsWith('/') ? `${dir}${name}` : `${dir}/${name}`;
            }
          }

          let stat: fileIo.Stat | null = null;
          try {
            stat = await fileIo.stat(childUri);
          } catch (e) {
            continue;
          }
          // 判定目录：以 stat.isDirectory() 为主；文档树 URI 子项 stat 不可靠时，
          // 用「listFile 能成功返回数组」作为目录的兜底判据，确保递归能下钻。
          let isDir: boolean = stat.isDirectory();
          if (!isDir) {
            try {
              const probe: string[] = await fileIo.listFile(childUri);
              if (Array.isArray(probe) && probe.length >= 0) {
                isDir = true;
              }
            } catch (e) {
              // listFile 失败说明不是可遍历目录，维持 isDir=false
            }
          }
          if (isDir) {
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
            // 命中"排除原始书名 / 排除书名词汇"的文件：解析后剔除，不入库（等同扫描跳过）
            if (ScanService.titleExcluded(rec.title, titleExcludes.exact, titleExcludes.keywords)) {
              processed++;
              excluded++;
              reportProgress(name);
              continue;
            }
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
    LogUtil.operation('扫描', `文库=${config.name} 目录=${config.folderName} 命中=${found} 排除=${excluded} 状态=${status} 文库ID=${runId}`);
    return { runId: runId, total: found, processed: processed, excluded: excluded, stopped: ScanService.stopped };
  }

  /**
   * FILE 多选回退模式下的扫描：直接处理 selectDirectory 缓存的已授权文件 URI 列表。
   * 不递归、不遍历父目录，只处理用户明确选中的文件。扫描结束后清空缓存。
   */
  private static async runScanFromFiles(
    config: ScanConfig,
    onProgress: (p: ScanProgress) => void,
    run: ScanRun,
    runId: number,
    scanRules: KeywordReplaceRule[],
    parseRules: KeywordReplaceRule[]
  ): Promise<{ runId: number; total: number; processed: number; stopped: boolean }> {
    const fileUris: string[] = [...ScanService.selectedFileUris];
    ScanService.clearFileFallback(); // 立即清空（内存+持久化），避免重复扫描或旧数据残留

    const batch: ScannedFile[] = [];
    let processed: number = 0;
    let found: number = 0;
    let lastReportProcessed: number = 0;

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

    for (const childUri of fileUris) {
      if (ScanService.stopped) {
        break;
      }
      let stat: fileIo.Stat | null = null;
      try {
        stat = await fileIo.stat(childUri);
      } catch (e) {
        LogUtil.w('ScanService', `无法 stat 已选文件: ${childUri} -> ${(e as Error).message}`);
        continue;
      }
      if (stat.isDirectory()) {
        continue;
      }
      processed++;
      let name: string = '';
      try {
        name = new fileUri.FileUri(childUri).name ?? '';
      } catch (e) {
        name = childUri.substring(childUri.lastIndexOf('/') + 1);
      }
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
      const rawMtime: number = stat.mtime ? Number(stat.mtime) : 0;
      rec.fileDate = rawMtime > 0 ? (rawMtime < 1e12 ? rawMtime * 1000 : rawMtime) : 0;
      batch.push(rec);
      found++;
      if (batch.length >= ScanService.BATCH_SIZE) {
        await flushBatch();
      }
      reportProgress(name);
    }

    await flushBatch();
    await ScanRunDao.updateFileCount(runId, found);
    const status: string = ScanService.stopped ? '已停止' : '完成';
    LogUtil.operation('扫描', `文库=${config.name} 目录=${config.folderName} 命中=${found} 状态=${status} 文库ID=${runId} [FILE多选回退]`);
    return { runId: runId, total: found, processed: processed, stopped: ScanService.stopped };
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

  /**
   * 判断某书名是否命中「排除原始书名 / 排除书名词汇」。
   * - exactList：精确书名列表，完全相同才剔除；
   * - keywordList：书名词汇列表，书名包含任一词汇即剔除。
   * 两者为「或」关系（命中任一即排除）。title 为空时不算命中。
   */
  private static titleExcluded(title: string, exactList: string[], keywordList: string[]): boolean {
    if (!title || title.length === 0) {
      return false;
    }
    if (exactList.includes(title)) {
      return true;
    }
    for (const kw of keywordList) {
      if (kw.length > 0 && title.includes(kw)) {
        return true;
      }
    }
    return false;
  }

  /** 把排除书名配置（逗号/换行分隔）解析为精确书名集合与书名词汇列表。 */
  private static parseTitleExcludes(config: ScanConfig): { exact: string[]; keywords: string[] } {
    const splitExcludes = (raw: string): string[] =>
      (raw ?? '')
        .split(/[,\n，\r]/)
        .map((s) => s.trim())
        .filter((s) => s.length > 0);
    return {
      exact: splitExcludes(config.excludedTitles),
      keywords: splitExcludes(config.excludedTitleKeywords)
    };
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
