import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { uri } from '@kit.ArkTS';
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
import { EncodingUtil } from '../utils/EncodingUtil';
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
/**
 * 目录选择结果。
 * isFileFallback=true 表示当前设备/系统不支持 FOLDER 目录选择器，已降级为 FILE 多选；
 * 此时 uri 是第一个被选中的文件 URI，供 UI 展示与保存配置，真正的扫描仍走 selectedFileUris 逐文件模式。
 */
export interface DirectoryPickResult {
  uri: string;
  isFileFallback: boolean;
  /**
   * 仅 isFileFallback=true 时使用：供 UI 展示的文件夹/文件名称（例如父文件夹名）。
   * 此时 uri 可能是被选中的文件 URI，实际扫描不依赖它。
   */
  displayName?: string;
}

export class ScanService {
  private static readonly BATCH_SIZE: number = 200;
  private static readonly PROGRESS_INTERVAL: number = 16;
  private static readonly MAX_FILE_PICK: number = 99999;
  private static stopped: boolean = false;

  /**
   * 把任意 URI 转成父目录 URI（带末尾斜杠）。
   * 兼容 file:// URI 与纯字符串兜底，避免 FileUri 在特殊 URI 上抛异常。
   */
  private static deriveParentUri(uri: string): string | null {
    try {
      let parent = new fileUri.FileUri(uri).getFullDirectoryUri();
      if (!parent.endsWith('/')) {
        parent += '/';
      }
      return parent;
    } catch (e) {
      LogUtil.w('ScanService', `FileUri parent fail for ${uri}: ${(e as Error).message}`);
      let s = uri.replace(/[\/\\]+$/, '');
      const idx = s.lastIndexOf('/');
      if (idx <= 0) {
        return null;
      }
      return s.substring(0, idx + 1);
    }
  }

  /**
   * 判断 URI 是否真的是目录。
   * 优先用 stat.isDirectory()；失败时回退到 listFile 校验。
   */
  private static async isDirectoryUri(uri: string): Promise<boolean> {
    try {
      const stat = await fileIo.stat(uri);
      if (stat && typeof (stat as fileIo.Stat).isDirectory === 'function') {
        return (stat as fileIo.Stat).isDirectory();
      }
    } catch (e) {
      // ignore, fallback below
    }
    return FilePermissionUtil.checkUriAccessible(uri);
  }
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
    ScanService.restoreFileFallback();
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
  public static async selectDirectory(context: common.Context, defaultUri?: string): Promise<DirectoryPickResult> {
    // 先清空上次的文件缓存（内存 + 持久化），避免旧列表影响新配置。
    ScanService.clearFileFallback();
    // FOLDER 模式优先：直接选目录，授权整棵树，可递归遍历扫描。
    // 官方口径：DocumentSelectMode.FOLDER 仅对 PC/2in1/TV 设备生效；手机/平板上强行调用
    // 会让系统选择器提示「不支持选择文件夹」（Pura 系列真机 HarmonyOS 6.x 实测如此），
    // 因此按设备类型判定，手机/平板直接走「选择文件定位文件夹」方案，不再吊起文件夹选择器。
    if (ScanService.canPickFolder()) {
      const folderResult: DirectoryPickResult = await ScanService.tryPickFolder(context, defaultUri);
      if (folderResult.uri.length > 0) {
        return folderResult;
      }
      // 用户在 FOLDER 选择器中未选中目录（取消等）：提示后降级为「选择文件以定位文件夹」
      LogUtil.w('ScanService', 'FOLDER 模式未选中目录，降级为 FILE 多选');
      await ScanService.notifyFolderFallback(false);
    } else {
      // 手机/平板等设备不支持 FOLDER：直接用友好文案引导「选择文件定位文件夹」，
      // 避免出现「不支持选择文件夹」这类让用户误以为功能损坏的提示。
      LogUtil.i('ScanService', `当前设备(${ScanService.safeDeviceType()})不支持 FOLDER 模式，使用「选择文件定位文件夹」方案`);
      await ScanService.notifyFolderFallback(true);
    }
    return ScanService.pickFiles(context, defaultUri);
  }

  /** 读取设备类型（异常时返回 unknown），仅用于日志与 FOLDER 能力判定。 */
  private static safeDeviceType(): string {
    try {
      return deviceInfo.deviceType;
    } catch (e) {
      return 'unknown';
    }
  }

  /**
   * 提示用户改用「选择文件以定位文件夹」方案（FOLDER 模式不可用或未选中时调用）。
   * @param deviceUnsupported true=设备形态不支持（手机/平板），文案说明系统限制；
   *                          false=FOLDER 选择器中用户未选中，仅引导继续选文件。
   */
  private static async notifyFolderFallback(deviceUnsupported: boolean): Promise<void> {
    try {
      const prefix: string = deviceUnsupported
        ? '鸿蒙手机/平板暂不支持直接选择文件夹，'
        : '';
      await promptAction.showDialog({
        title: '请选择文件以定位文件夹',
        message: `${prefix}请在接下来的文件选择器中，进入目标文件夹并选中其中的任意一个（或多个）文件：\n· 应用会自动定位并扫描整个文件夹（含子文件夹）；\n· 若文件夹不可访问，则仅扫描您选中的文件。`,
        buttons: [{ text: '我知道了', color: '#2D6A4F' }]
      });
    } catch (e) {
      // 弹窗失败不阻断主流程
    }
  }

  /**
   * 设备是否支持 FOLDER（目录选择）模式。
   * 官方口径（华为 Core File Kit FAQ）：DocumentSelectMode.FOLDER 仅对 PC/2in1/TV 设备生效，
   * 手机/平板等非 PC 形态当前只能通过批量选择文件来获取目录。
   * 此前仅以 sdkApiVersion>=12 作门槛，导致手机（如 Pura 80 Ultra / HarmonyOS 6.x）上
   * 吊起 FOLDER 选择器后被系统提示「不支持选择文件夹」，用户误以为功能损坏。
   */
  private static canPickFolder(): boolean {
    try {
      if (deviceInfo.sdkApiVersion < 12) {
        return false;
      }
      const type: string = deviceInfo.deviceType;
      return type === '2in1' || type === 'tv';
    } catch (e) {
      return false;
    }
  }

  /**
   * FOLDER 模式：让用户在 Picker 中直接选择一个文件夹。
   * 选中目录即获得整棵目录树的访问授权，持久化后 listFile 可递归遍历。
   *
   * @returns 选中的目录 URI；用户取消或失败返回空字符串
   */
  private static async tryPickFolder(context: common.Context, defaultUri?: string): Promise<DirectoryPickResult> {
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
        return { uri: '', isFileFallback: false };
      }
      const pickedUri: string = uris[0];

      // 部分设备/系统虽然声明了 FOLDER 模式，但 Picker 实际仍返回文件 URI。
      // 这里做一层兜底：若选中的不是目录，则尝试取它的父目录；父目录可访问就
      // 按整目录扫描，避免界面上把文件名当成文件夹名，也避免扫描时出错。
      if (!(await ScanService.isDirectoryUri(pickedUri))) {
        LogUtil.w('ScanService', `FOLDER 模式返回了非目录，尝试推导父目录: ${pickedUri}`);
        const parentUri = ScanService.deriveParentUri(pickedUri);
        if (parentUri && (await FilePermissionUtil.checkUriAccessible(parentUri))) {
          try {
            await FilePermissionUtil.persistFolderPermission(parentUri);
          } catch (e) {
            LogUtil.w('ScanService', `持久化父目录授权失败: ${(e as Error).message}`);
          }
          LogUtil.i('ScanService', `已降级为父目录扫描: ${parentUri}`);
          return { uri: parentUri, isFileFallback: false };
        }
        // 父目录也不可访问：降级为逐文件扫描（至少能扫选中的这个文件）
        ScanService.saveFileFallback([pickedUri]);
        const displayName = FormatUtil.getParentFolderDisplay(pickedUri);
        LogUtil.i('ScanService', `父目录不可访问，逐文件扫描: ${pickedUri}`);
        return { uri: pickedUri, isFileFallback: true, displayName };
      }

      // 持久化目录授权（读写模式），重启后自动激活
      try {
        await FilePermissionUtil.persistFolderPermission(pickedUri);
        LogUtil.i('ScanService', `已持久化目录授权: ${pickedUri}`);
      } catch (e) {
        LogUtil.w('ScanService', `持久化目录授权失败: ${(e as Error).message}`);
      }
      LogUtil.i('ScanService', `FOLDER 模式选择成功: ${pickedUri}`);
      return { uri: pickedUri, isFileFallback: false };
    } catch (e) {
      LogUtil.w('ScanService', `FOLDER 模式选择失败，降级 FILE 多选: ${(e as Error).message}`);
      return { uri: '', isFileFallback: false };
    }
  }

  /**
   * 文件定位模式（FOLDER 不可用时的降级方案，保留旧行为）：
   * 让用户在 Picker 中选中一个或多个文件，应用先尝试推导其父目录：
   *  - 父目录可访问（listFile 成功）→ 返回父目录 URI，runScan 扫描整个文件夹；
   *  - 父目录不可访问（如文档卷未授权父目录）→ 回退逐文件扫描 selectedFileUris。
   */
  private static async pickFiles(context: common.Context, defaultUri?: string): Promise<DirectoryPickResult> {
    // 说明：引导弹窗已在 selectDirectory 中统一弹出（notifyFolderFallback），此处不再重复弹窗，
    // 避免「提示一 → 提示二 → 才打开选择器」的连弹体验。
    const documentPicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = ScanService.MAX_FILE_PICK;
    if (defaultUri && defaultUri.startsWith('file://')) {
      options.defaultFilePathUri = defaultUri;
    }
    const uris: string[] = await documentPicker.select(options);
    if (!uris || uris.length === 0) {
      return { uri: '', isFileFallback: false };
    }

    // 持久化每个选中文件的授权（每个文件都有独立的 picker 临时授权，可持久化）
    try {
      await FilePermissionUtil.persistUris(uris);
      LogUtil.i('ScanService', `已持久化 ${uris.length} 个选中文件的授权`);
    } catch (e) {
      LogUtil.w('ScanService', `持久化文件授权失败: ${(e as Error).message}`);
    }

    // 取共同父目录（优先使用 FileUri，失败时字符串兜底）
    let parentDirUri: string | null = ScanService.deriveParentUri(uris[0]);
    if (!parentDirUri) {
      LogUtil.w('ScanService', `推导父目录失败，回退逐文件: ${uris[0]}`);
      ScanService.saveFileFallback(uris);
      return { uri: uris[0] || '', isFileFallback: true, displayName: FormatUtil.getParentFolderDisplay(uris[0] || '') };
    }

    // 优先整目录扫描：父目录可访问（listFile 成功）时，选中文件仅用于定位文件夹，
    // runScan 对父目录做 BFS 遍历，扫描其下全部文件——保留「选文件→推导父目录→扫文件夹」模式。
    if (await FilePermissionUtil.checkUriAccessible(parentDirUri)) {
      ScanService.selectedFileUris = [];
      // 关键：仅持久化选中文件们，重启后父目录授权不会自动恢复（picker 授权的是
      // 文件而非父目录），再次扫描 listFile 父目录必然失败。这里同时持久化父目录
      // 授权，保证应用重启后仍可遍历整个文件夹。
      if (!parentDirUri.endsWith('/')) {
        parentDirUri += '/';
      }
      try {
        await FilePermissionUtil.persistFolderPermission(parentDirUri);
        LogUtil.i('ScanService', `已持久化父目录授权: ${parentDirUri}`);
      } catch (e) {
        LogUtil.w('ScanService', `持久化父目录授权失败: ${(e as Error).message}`);
      }
      LogUtil.i('ScanService', `已定位目录（选中 ${uris.length} 个文件），将扫描整个文件夹: ${parentDirUri}`);
      return { uri: parentDirUri, isFileFallback: false };
    }

    // 父目录不可访问（如文档卷未授权父目录）：回退为逐文件扫描选中列表。
    // 列表需持久化：selectedFileUris 是内存变量，重启丢失后 runScan 会错误地走
    // BFS 遍历不可访问的父目录导致「扫描失败」。
    // 返回第一个选中的文件 URI 给 UI 展示/保存配置；runScan 优先使用 selectedFileUris 走逐文件分支。
    ScanService.saveFileFallback(uris);
    LogUtil.i('ScanService', `FILE 多选：共选 ${uris.length} 个文件，父目录不可遍历，逐文件扫描`);
    return { uri: uris[0] || '', isFileFallback: true, displayName: FormatUtil.getParentFolderDisplay(uris[0] || '') };
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

    // 1.5 权限可能已持久化但重启后未成功激活（启动时批量激活失败仅记日志，不重试）。
    // 先尝试单独激活该 URI，避免每次重启后都强制用户重新选择目录。
    if (await FilePermissionUtil.activateUri(uri)) {
      if (await FilePermissionUtil.checkUriAccessible(uri)) {
        return uri;
      }
    }

    // 2. 尝试用 authMode 重新授权。
    // 注意：必须使用返回的「新 URI」校验并返回——模拟器/部分系统重新授权返回的
    // URI 可能与旧 URI 不同，若仍校验旧 URI 会误判为失效，导致重新授权永远不生效。
    const newUri: string = await FilePermissionUtil.reauthorizeUri(context, uri);
    if (newUri.length > 0 && (await FilePermissionUtil.checkUriAccessible(newUri))) {
      return newUri;
    }

    // 3. 重新授权也失败了。鸿蒙系统限制：目录授权过期后应用无法自行恢复，
    // 必须由用户通过系统 Picker 重新确认，UI 层据此引导用户重新选择目录。
    LogUtil.e('ScanService', `重新授权失败（鸿蒙系统限制，需用户重新选择目录）`);
    return '';
  }

  /** 执行一次扫描，返回新建的文库 id 与扫到的文件数。 */
  public static async runScan(
    config: ScanConfig,
    onProgress: (p: ScanProgress) => void
  ): Promise<{ runId: number; total: number; processed: number; excluded: number; stopped: boolean }> {
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

    // 模式判定（以「本次传入的 config.folderUri 是否可访问且为目录」为准，避免旧
    // 文件 URI 残留误触发）：
    //  - folderUri 非空且可访问为目录（FOLDER 模式选中目录，或 pickFiles 推导出可访问的父目录）
    //    → 走目录递归遍历（BFS 逐层 listFile，子目录入队下一层）。
    //  - folderUri 为空或不可访问，但存在已选文件列表（FILE 多选回退，父目录不可访问）
    //    → 逐文件扫描 selectedFileUris（含内存列表，或从 Preferences 恢复）。
    // 旧实现用 restoreFileFallback() 读 Preferences 的旧文件 URI 来决定模式，
    // 会导致「这次明明选了目录、却因为历史残留文件 URI 而只扫那一个文件」的问题。
    const hasDirMode: boolean = config.folderUri.length > 0 && (await FilePermissionUtil.checkUriAccessible(config.folderUri));
    if (!hasDirMode) {
      if (ScanService.restoreFileFallback() || ScanService.selectedFileUris.length > 0) {
        return ScanService.runScanFromFiles(config, onProgress, run, runId, scanRules, parseRules);
      }
      // 既无目录也无文件，报错提示
      throw new Error('未选择任何扫描目标，请先选择目录或文件');
    }

    // 目录模式：统一交给 traverseDirs 做 BFS 递归遍历（同时供文件回退递归模式复用）。
    // failOnFirstRootUnavailable=true：单一根目录不可访问时抛错，引导 UI 重新选择授权。
    const stats = await ScanService.traverseDirs(
      [config.folderUri], config, onProgress, runId, scanRules, parseRules, true
    );
    return { runId: runId, total: stats.found, processed: stats.processed, excluded: stats.excluded, stopped: ScanService.stopped };
  }

  /**
   * 枚举目录的子项，返回可直接用于 stat/open 的子项 URI 数组。
   *
   * 鸿蒙 NEXT 关键限制：fileIo.listFile 不能直接传文档树 URI（file://docs/...），
   * 否则会报 No such file or directory 或返回空。必须先提取 path 再 listFile：
   *   const path = new uri.URI(dir).path; fileIo.listFile(path)。
   * 这里优先用「提取 path 后 listFile」的方式，失败时再尝试直接用 URI。
   *
   * @param dir 目录 URI（文档树 URI 或沙箱路径）
   * @returns 子项 URI 数组（含 scheme 的完整 URI，文档树形态）
   */
  private static async listChildEntries(dir: string): Promise<string[]> {
    let raw: string[] = [];
    try {
      // 关键修复：文档树 URI 必须先提取 path 再 listFile（直接传 URI 会失败/返回空）
      const pathStr: string = new uri.URI(dir).path;
      raw = await fileIo.listFile(pathStr);
    } catch (e) {
      LogUtil.w('ScanService', `listFile(path) 失败，尝试直接 listFile(uri): ${dir} -> ${(e as Error).message}`);
      try {
        raw = await fileIo.listFile(dir);
      } catch (e2) {
        LogUtil.e('ScanService', `listFile 失败: ${dir} -> ${(e2 as Error).message}`);
        return [];
      }
    }
    // fileIo.listFile 返回文件名数组（或完整 URI），统一拼成文档树 URI 形态
    const result: string[] = [];
    for (const entry of raw) {
      if (entry.includes('://')) {
        result.push(entry); // 已是完整 URI
      } else if (entry.startsWith('/')) {
        // 关键：必须拼成「文档类 URI」file://docs/storage/...（授权体系认可的形态）。
        // 若拼成 file:///storage/...（本机 URI，三个斜杠），读操作可工作，但删除/写
        // 操作时系统按「应用沙箱外未授权 URI」拒绝（Permission denied），删除必失败。
        result.push(ScanService.toDocUri(entry));
      } else {
        const sep: string = dir.endsWith('/') ? '' : '/';
        result.push(`${dir}${sep}${entry}`); // 纯文件名：父 URI + '/' + 文件名
      }
    }
    return result;
  }

  /**
   * 将绝对路径/URI 归一化为鸿蒙「文档类 URI」（file://docs/storage/Users/...）。
   * 通过 Picker 获得的是文档树授权 URI（file://docs/...），只有这种形态的 URI 才被
   * 授权体系认可；file:///storage/...（本机 URI）或裸路径（/storage/...）不在授权链上，
   * 扫描可读（读走挂载路径）但删除/写操作会被拒绝。
   * @param p 绝对路径（如 /storage/Users/currentUser/Documents/xxx）或已是 URI 的字符串
   */
  private static toDocUri(p: string): string {
    if (p.startsWith('file://docs')) {
      return p;
    }
    if (p.startsWith('file:///')) {
      p = p.substring('file://'.length);
    }
    if (p.startsWith('/storage/')) {
      return 'file://docs' + p;
    }
    return 'file://' + p;
  }

  /**
   * 目录递归遍历核心（BFS 逐层 listFile）。
   * 供两种入口复用：
   *  - 目录模式（FOLDER 选中目录，或 FILE 推导出可访问父目录）；
   *  - 文件回退递归模式（FILE 多选 + 勾选递归：对每个选中文件取父目录，遍历父目录下所有符合后缀的文件与子文件夹）。
   *
   * @param roots  待遍历的根目录 URI 列表（可多个）
   */
  private static async traverseDirs(
    roots: string[],
    config: ScanConfig,
    onProgress: (p: ScanProgress) => void,
    runId: number,
    scanRules: KeywordReplaceRule[],
    parseRules: KeywordReplaceRule[],
    failOnFirstRootUnavailable: boolean = false
  ): Promise<{ processed: number; found: number; excluded: number }> {
    const batch: ScannedFile[] = [];
    let processed: number = 0;
    let found: number = 0;
    let excluded: number = 0;
    let lastReportProcessed: number = 0;
    let currentLevel: string[] = [...roots];

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
        // 目录访问自愈（修复「扫描目录无法访问」核心场景）：
        // 鸿蒙 NEXT 安全模型下 Picker 返回的目录 URI 是临时授权，应用重启/重装后失效，
        // 持久化授权（fileShare.persistPermission）在模拟器/多数手机上不支持（801）。
        // 这里先探测目录可达性，失败则尝试激活持久化权限后重试一次；仍失败则跳过该目录。
        let names: string[] = [];
        try {
          // 优先用 fileAccess.listFile 枚举文档树 URI 的子项（返回「子项完整 URI」数组，
          // 可直接用于 stat/open，是官方推荐的遍历用户文档方式）；
          // 失败或不支持时回退到 fileIo.listFile（返回文件名数组，需自行拼接）。
          names = await ScanService.listChildEntries(dir);
        } catch (rootErr) {
          LogUtil.w('ScanService', `目录首次访问失败，尝试激活持久化权限: ${dir} -> ${(rootErr as Error).message}`);
          try {
            await FilePermissionUtil.activateUri(dir);
          } catch (actErr) {
            LogUtil.w('ScanService', `激活目录权限失败（模拟器上常返回 801，属预期）: ${(actErr as Error).message}`);
          }
          try {
            names = await ScanService.listChildEntries(dir);
          } catch (e3) {
            // 目录模式（单一根目录）不可访问时，抛出明确错误引导 UI 重新选择授权；
            // 文件回退递归模式（多个父目录根）则跳过该不可访问的父目录，继续其余。
            if (failOnFirstRootUnavailable && dir === roots[0]) {
              throw new Error(`无法访问扫描目录，请重新选择目录授权。错误: ${(e3 as Error).message}`);
            }
            LogUtil.e('ScanService', `目录不可访问，跳过: ${dir} -> ${(e3 as Error).message}`);
            continue;
          }
        }
        if (names.length === 0) {
          LogUtil.w('ScanService', `目录列举为空: ${dir}`);
        }
        for (const name of names) {
          if (ScanService.stopped) {
            break;
          }
          // listChildEntries 返回的 childUri 可能是两种形态：
          //   a) 完整子项 URI（fileAccess.listFile 返回，如 file://docs/.../sub）；
          //   b) 纯文件名（fileIo.listFile 回退时返回，如 "sub"），需自行拼接为文档树 URI 形态。
          // 关键：文档树 URI（FOLDER 模式选中的 file://docs/...）不能转换为沙箱外真实
          // 路径访问（应用无权限），始终用「文档树 URI 形态」。早期版本用 new FileUri(dir).path
          // 拿真实路径拼接，导致 stat/open 全部失败、子目录进不了 nextLevel、文件被跳过。
          let childUri: string;
          if (name.includes('://')) {
            childUri = name; // fileAccess.listFile 返回完整子项 URI，直接用
          } else if (name.startsWith('/')) {
            childUri = ScanService.toDocUri(name); // 真实绝对路径，归一化为文档类 URI
          } else {
            // 纯文件名：父 URI + '/' + 文件名（文档树 URI 与 file:/// 真实路径 URI 均适用）
            const sep: string = dir.endsWith('/') ? '' : '/';
            childUri = `${dir}${sep}${name}`;
          }
          // 子项显示名：fileAccess 返回的是 URI 时取末尾段；fileIo 返回的是文件名，直接用
          const childName: string = name.includes('://')
            ? ScanService.getFileNameFromUri(name)
            : name;

          let stat: fileIo.Stat | null = null;
          try {
            stat = await fileIo.stat(childUri);
          } catch (e) {
            // stat 失败：文档树 URI 子项的 stat 有时不可靠。用 fileAccess.listFile(childUri)
            // 兜底判定是否为目录（返回数组即目录）。对文件则尝试 fileAccess 的递归列举判定。
            const isDirFallback: boolean = await ScanService.isDirectoryUri(childUri);
            if (isDirFallback && config.recursive && !ScanService.isExcluded(childName, config.excludedFolders)) {
              LogUtil.i('ScanService', `子项判定为目录(兜底): ${childName}`);
              nextLevel.push(childUri);
              continue;
            }
            // 非目录且 stat 失败：视为无法访问的文件，跳过（不计入 processed，与原行为一致）
            LogUtil.w('ScanService', `子项 stat 失败且非目录，跳过: ${childUri} -> ${(e as Error).message}`);
            continue;
          }
          // 判定目录：以 stat.isDirectory() 为主；stat 已成功，绝大多数场景下直接可信，
          // 避免对每个文件再发一次无意义的 listFile 探测（10w 文件场景会多出 10w 次 IPC）。
          const isDir: boolean = stat.isDirectory();
          if (isDir) {
            if (config.recursive && !ScanService.isExcluded(childName, config.excludedFolders)) {
              nextLevel.push(childUri);
            }
          } else {
            processed++;
            const ext: string = FormatUtil.getExtension(childName);
            if (!ScanService.matchExt(ext, config.fileTypes)) {
              continue;
            }
            if (stat.size / 1024 < config.minSizeKb) {
              continue;
            }
            let fileName: string = childName;
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
              reportProgress(childName);
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
    return { processed, found, excluded };
  }

  /**
   * FILE 多选回退模式下的扫描：处理 selectDirectory 缓存的已授权文件 URI 列表。
   *
   * 递归处理：
   *  - 勾选「递归扫描」(config.recursive=true) 时，对每个选中文件推导其父目录，
   *    若父目录可访问则交给 traverseDirs 递归扫描父目录下所有符合后缀要求的文件与
   *    子文件夹（即扫描父目录下的全部文件，含子目录递归）；父目录不可访问的文件则
   *    降级为只扫描该文件本身。
   *  - 未勾选递归时，仅扫描用户明确选中的文件。
   *
   * 扫描结束后清空缓存。
   */
  private static async runScanFromFiles(
    config: ScanConfig,
    onProgress: (p: ScanProgress) => void,
    run: ScanRun,
    runId: number,
    scanRules: KeywordReplaceRule[],
    parseRules: KeywordReplaceRule[]
  ): Promise<{ runId: number; total: number; processed: number; excluded: number; stopped: boolean }> {
    const fileUris: string[] = [...ScanService.selectedFileUris];
    ScanService.clearFileFallback(); // 立即清空（内存+持久化），避免重复扫描或旧数据残留

    let processed: number = 0;
    let found: number = 0;
    let excluded: number = 0;

    if (config.recursive === true) {
      // 递归模式：收集可访问的父目录作为遍历根；父目录不可访问的选中文件单独扫描。
      const dirRoots: string[] = [];
      const singleFiles: string[] = [];
      for (const f of fileUris) {
        if (ScanService.stopped) { break; }
        if (!(await FilePermissionUtil.checkUriAccessible(f))) {
          LogUtil.w('ScanService', `选中文件不可访问，跳过: ${f}`);
          continue;
        }
        const parentDir: string | null = ScanService.deriveParentUri(f);
        if (parentDir && (await FilePermissionUtil.checkUriAccessible(parentDir))) {
          if (!parentDir.endsWith('/')) {
            dirRoots.push(parentDir + '/');
          } else {
            dirRoots.push(parentDir);
          }
        } else {
          singleFiles.push(f);
        }
      }
      if (dirRoots.length > 0) {
        // 文件回退递归模式：多个父目录根，任一不可访问则跳过（不抛错中断整个扫描）
        const stats = await ScanService.traverseDirs(dirRoots, config, onProgress, runId, scanRules, parseRules, false);
        processed += stats.processed;
        found += stats.found;
        excluded += stats.excluded;
        LogUtil.i('ScanService', `文件回退递归模式：遍历 ${dirRoots.length} 个父目录，命中=${stats.found}`);
      }
      // 父目录不可访问的选中文件：逐文件扫描（不递归）
      for (const f of singleFiles) {
        if (ScanService.stopped) { break; }
        const r = await ScanService.scanSingleSelectedFile(f, config, runId, scanRules, parseRules);
        processed += r.processed; found += r.found; excluded += r.excluded;
        onProgress({ processed: processed, found: found, currentFile: ScanService.getFileNameFromUri(f) });
      }
    } else {
      // 非递归模式：仅扫描选中的文件
      for (const f of fileUris) {
        if (ScanService.stopped) { break; }
        if (!(await FilePermissionUtil.checkUriAccessible(f))) {
          LogUtil.w('ScanService', `选中文件不可访问，跳过: ${f}`);
          continue;
        }
        const r = await ScanService.scanSingleSelectedFile(f, config, runId, scanRules, parseRules);
        processed += r.processed; found += r.found; excluded += r.excluded;
        onProgress({ processed: processed, found: found, currentFile: ScanService.getFileNameFromUri(f) });
      }
    }

    await ScanRunDao.updateFileCount(runId, found);
    const status: string = ScanService.stopped ? '已停止' : '完成';
    LogUtil.operation('扫描', `文库=${config.name} 目录=${config.folderName} 命中=${found} 排除=${excluded} 状态=${status} 文库ID=${runId} [FILE多选回退]`);
    return { runId: runId, total: found, processed: processed, excluded: excluded, stopped: ScanService.stopped };
  }

  /** 从文件 URI 中提取文件名（末尾段），供进度展示。 */
  private static getFileNameFromUri(uri: string): string {
    try {
      const n: string | undefined = new fileUri.FileUri(uri).name;
      if (n && n.length > 0) { return n; }
    } catch (e) {
      // 忽略，走字符串兜底
    }
    const idx: number = uri.lastIndexOf('/');
    return idx >= 0 ? uri.substring(idx + 1) : uri;
  }

  /**
   * 扫描单个「已选文件」（FILE 回退模式逐文件分支）。
   * 用于递归模式下父目录不可访问的降级，以及非递归模式逐文件扫描。
   * 返回扫描统计（processed 至少为 1，命中算 found，排除算 excluded）。
   */
  private static async scanSingleSelectedFile(
    childUri: string,
    config: ScanConfig,
    runId: number,
    scanRules: KeywordReplaceRule[],
    parseRules: KeywordReplaceRule[]
  ): Promise<{ processed: number; found: number; excluded: number }> {
    const batch: ScannedFile[] = [];
    let processed: number = 0;
    let found: number = 0;
    let excluded: number = 0;

    const flushBatch = async (): Promise<void> => {
      if (batch.length > 0) {
        await ScannedFileDao.insertBatch(batch);
        batch.length = 0;
      }
    };

    const titleExcludes = ScanService.parseTitleExcludes(config);

    let stat: fileIo.Stat | null = null;
    try {
      stat = await fileIo.stat(childUri);
    } catch (e) {
      LogUtil.w('ScanService', `无法 stat 已选文件: ${childUri} -> ${(e as Error).message}`);
      return { processed, found, excluded };
    }
    if (stat.isDirectory()) {
      return { processed, found, excluded };
    }
    processed++;
    const name: string = ScanService.getFileNameFromUri(childUri);
    const ext: string = FormatUtil.getExtension(name);
    if (!ScanService.matchExt(ext, config.fileTypes)) {
      return { processed, found, excluded };
    }
    if (stat.size / 1024 < config.minSizeKb) {
      return { processed, found, excluded };
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
    if (ScanService.titleExcluded(rec.title, titleExcludes.exact, titleExcludes.keywords)) {
      excluded++;
      await flushBatch();
      return { processed, found, excluded };
    }
    batch.push(rec);
    found++;
    await flushBatch();
    return { processed, found, excluded };
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
      // 关键修复：用 EncodingUtil.decodeStrict 做严格解码 + CJK 占比评分，
      // 对齐 iOS decodeStrict + 安卓 Charset 严格解码语义。
      // 直接返回带 BOM 时已在上文命中；无 BOM 时统一交由 decodeStrict 评分择优，
      // 避免「GBK 文件被误判为合法 UTF-8 → 用 UTF-8 解码成乱码（损坏文件）」。
      return EncodingUtil.decodeStrict(bytes);
    } catch (e) {
      return '';
    } finally {
      await fileIo.close(file);
    }
  }
}
