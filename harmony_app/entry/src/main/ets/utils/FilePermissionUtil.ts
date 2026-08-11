import { fileShare, fileIo, picker } from '@kit.CoreFileKit';
import { uri } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferencesUtil } from './PreferencesUtil';
import { LogUtil } from './LogUtil';
import { AppContext } from './AppContext';

/**
 * 文件 URI 权限持久化工具，对齐鸿蒙官方「授权持久化」方案。
 *
 * 背景：通过 Picker 选择文件/文件夹后返回的 URI 只具有临时读写权限，
 * 应用退出或设备重启后授权会清除。若需要重启后仍能访问/删除文件，
 * 必须调用 fileShare.persistPermission 持久化授权，并在每次应用启动时
 * 调用 fileShare.activatePermission 激活已持久化的权限。
 *
 * 需要 module.json5 声明 ohos.permission.FILE_ACCESS_PERSIST 权限。
 *
 * 参考：https://device.harmonyos.com/cn/docs/apiref/harmonyos-guides/file-persistpermission
 */
const PREF_KEY_PERSISTED_URIS: string = 'persisted_folder_uris';

export class FilePermissionUtil {
  /** 检查当前设备是否支持文件 URI 持久化授权（API 12+ 真机/Beta3+ 模拟器支持）。 */
  public static isPersistSupported(): boolean {
    try {
      return canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization');
    } catch (e) {
      return false;
    }
  }

  /** 将选中文件夹的 URI 持久化授权（读写模式），并记录到本地。 */
  public static async persistFolderPermission(uri: string): Promise<boolean> {
    return FilePermissionUtil.persistUris([uri]);
  }

  /**
   * 批量持久化多个 URI 的访问权限（读写模式），并记录到本地。
   * 用于 FILE 多选回退模式：每个选中文件都需要单独持久化授权。
   */
  public static async persistUris(uris: string[]): Promise<boolean> {
    if (!uris || uris.length === 0) {
      return false;
    }
    // 设备不支持持久化时优雅降级：当前会话仍可使用临时权限
    if (!FilePermissionUtil.isPersistSupported()) {
      LogUtil.w('FilePermission', '当前设备不支持持久化授权，仅本次会话可访问');
      return false;
    }
    try {
      const policies: fileShare.PolicyInfo[] = uris.map((uri: string) => ({
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      }));
      await fileShare.persistPermission(policies);
      // 持久化成功后，将每个 URI 保存到本地列表（供下次启动激活）
      for (const uri of uris) {
        FilePermissionUtil.addPersistedUri(uri);
      }
      LogUtil.i('FilePermission', `批量持久化授权成功: ${uris.length} 个 URI`);
      return true;
    } catch (e) {
      const err = e as BusinessError<Array<fileShare.PolicyErrorResult>>;
      LogUtil.e('FilePermission', `批量持久化授权失败: code=${err.code} msg=${err.message}`);
      // 模拟器/低版本系统缺少 FolderAuthorization 能力时返回 801（能力不支持）。
      // 此时持久化不可用，仅本次会话可访问，重启后需重新选择目录。
      if (err.code === 801) {
        LogUtil.e('FilePermission', '设备缺少 FolderAuthorization 能力(801)，持久化授权不可用，重启后需重新授权');
      }
      // 持久化失败不阻断主流程，当前会话仍可使用临时权限
      return false;
    }
  }

  /**
   * 应用启动时调用：激活所有已持久化的 URI 权限。
   * 持久化授权信息存储在系统数据库中，重启后不会自动加载到内存，需手动激活。
   */
  public static async activatePersistedPermissions(): Promise<void> {
    // 设备不支持持久化时跳过激活
    if (!FilePermissionUtil.isPersistSupported()) {
      return;
    }
    const uris: string[] = FilePermissionUtil.getPersistedUris();
    if (uris.length === 0) {
      return;
    }
    let activated: number = 0;
    for (const uri of uris) {
      try {
        const policyInfo: fileShare.PolicyInfo = {
          uri: uri,
          operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
        };
        await fileShare.activatePermission([policyInfo]);
        activated++;
      } catch (e) {
        const err = e as BusinessError<Array<fileShare.PolicyErrorResult>>;
        LogUtil.w('FilePermission', `激活权限失败 uri=${uri}: code=${err.code} msg=${err.message}`);
        // 文件可能已被删除或移动，从列表中移除失效 URI
        if (err.code === 13900001 || err.code === 13900002) {
          FilePermissionUtil.removePersistedUri(uri);
        }
      }
    }
    if (activated > 0) {
      LogUtil.i('FilePermission', `已激活 ${activated}/${uris.length} 个持久化权限`);
    }
  }

  /**
   * 激活单个 URI 的持久化权限。
   * 用于扫描前权限预检失败时重试激活（覆盖「已持久化但启动时未成功激活」的场景，
   * 避免每次重启后都强制用户重新选择目录）。
   * @returns 激活成功返回 true
   */
  public static async activateUri(uri: string): Promise<boolean> {
    if (!uri || uri.length === 0 || !FilePermissionUtil.isPersistSupported()) {
      return false;
    }
    try {
      const policyInfo: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      };
      await fileShare.activatePermission([policyInfo]);
      LogUtil.i('FilePermission', `激活单个权限成功: ${uri}`);
      return true;
    } catch (e) {
      const err = e as BusinessError<Array<fileShare.PolicyErrorResult>>;
      LogUtil.w('FilePermission', `激活单个权限失败 uri=${uri}: code=${err.code} msg=${err.message}`);
      return false;
    }
  }

  /**
   * 检查 URI 是否仍可访问（权限是否有效）。
   * 通过尝试 listFile 来验证读写权限。
   *
   * 注意：fileIo.listFile 是异步方法，不 await 时返回的是 Promise<Array<string>>
   * 而非抛出异常——若直接调用且不 await，try/catch 捕获不到 rejected Promise，
   * 会错误地判定为「权限失效」，进而触发重新授权。因此必须 await。
   *
   * 同时：传入的可能是 Picker 返回的 content:// URI，也可能是真实文件系统
   * 路径（file:// 或绝对路径）。对 URI 应使用 fileIo.listFile（异步），对纯
   * 路径应使用 fileIo.listFileSync；二者不要混用，否则对 URI 调用 listFileSync
   * 会抛「不支持的操作」而误判失效。
   */
  public static async checkUriAccessible(targetUri: string): Promise<boolean> {
    if (!targetUri || targetUri.length === 0) {
      return false;
    }
    // Picker 返回的 URI（content:// / file://）走异步 listFile。
    // 关键：fileIo.listFile 不能直接传文档树 URI（file://docs/...），否则会报
    // No such file or directory 或返回空。必须先提取 path 再 listFile：
    //   new uri.URI(targetUri).path
    if (targetUri.startsWith('content://') || targetUri.startsWith('file://')) {
      try {
        const pathStr: string = new uri.URI(targetUri).path;
        await fileIo.listFile(pathStr);
        return true;
      } catch (e) {
        // path 方式失败，再尝试直接传 URI（部分场景下 URI 直接可用）
        try {
          await fileIo.listFile(targetUri);
          return true;
        } catch (e2) {
          return false;
        }
      }
    }
    // 真实文件系统路径：listFileSync 同步校验
    try {
      fileIo.listFileSync(targetUri);
      return true;
    } catch (e) {
      return false;
    }
  }

  /**
   * 使用 authMode 重新授权一个之前选过的 URI。
   *
   * Picker 会以 defaultFilePathUri 为默认路径打开，用户确认后即重新获得授权。
   * 比「从头浏览选择」体验更好——用户只需确认，不用重新找目录。
   *
   * 关键修正：删除时重新授权的目标是「目录 URI」（扫描时用 FOLDER 模式授权），
   * 因此默认用 FOLDER 模式重新授权，Picker 会打开到目录树并定位到已授权目录，
   * 用户确认即重新授权整目录。若错误地用默认的文件选择模式（select()）去重新授权
   * 目录 URI，Picker 会打开到「最近」文件列表（通常为空），且用户选到的 URI 是文件
   * 而非目录，导致后续重建路径错乱、删除继续失败（表现为「弹出文件管理器但显示失败」）。
   *
   * @param selectFolder true=目标为目录（FOLDER 模式，删除重授权用）；false=目标为文件。
   * @returns 返回重新授权后的新 URI（已持久化）；用户取消或失败返回空字符串
   */
  public static async reauthorizeUri(
    context: common.Context,
    uri: string,
    selectFolder: boolean = false
  ): Promise<string> {
    if (!uri || uri.length === 0) {
      return '';
    }
    // DocumentViewPicker 需要真正的 UIAbilityContext 才能正确拉起授权弹窗。
    // 调用方可能误传 @Component 的 UIContext（如 getContext(this)）。UIAbilityContext 独有
    // startAbility 方法，用它判定；若传入的不是 UIAbilityContext，则回退到 AppContext
    // 中由 EntryAbility 保存的 UIAbilityContext（最可靠）。
    let abilityContext: common.Context = context;
    const hasAbilityApi: boolean = typeof (abilityContext as common.UIAbilityContext)?.startAbility === 'function';
    if (!hasAbilityApi) {
      const appCtx: common.Context | null = AppContext.get();
      if (appCtx && typeof (appCtx as common.UIAbilityContext)?.startAbility === 'function') {
        abilityContext = appCtx;
      }
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(abilityContext);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.authMode = true;
      options.defaultFilePathUri = uri;
      if (selectFolder) {
        // 目录重新授权：对齐扫描时 FOLDER 模式，Picker 打开到目录树并定位到目标目录，
        // 用户确认即重新授权整目录，避免"最近"空列表 + 选到文件 URI 的错配。
        options.selectMode = picker.DocumentSelectMode.FOLDER;
      }
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return ''; // 用户取消
      }
      // 重新持久化，并返回新 URI 供调用方更新配置（模拟器上重新授权可能返回不同的 URI）
      const newUri: string = uris[0];
      if (selectFolder) {
        await FilePermissionUtil.persistFolderPermission(newUri);
      } else {
        await FilePermissionUtil.persistUris([newUri]);
      }
      LogUtil.i('FilePermission', `重新授权成功(${selectFolder ? '目录' : '文件'}): ${newUri}`);
      return newUri;
    } catch (e) {
      const err = e as BusinessError;
      LogUtil.e('FilePermission', `重新授权失败: code=${err.code} msg=${err.message}`);
      return '';
    }
  }

  /** 从本地获取已持久化的 URI 列表。 */
  public static getPersistedUris(): string[] {
    const raw: string = PreferencesUtil.getString(PREF_KEY_PERSISTED_URIS, '');
    if (raw.length === 0) {
      return [];
    }
    try {
      return raw.split('\n').filter((s) => s.length > 0);
    } catch (e) {
      return [];
    }
  }

  /** 将 URI 添加到持久化列表（去重）。 */
  private static addPersistedUri(uri: string): void {
    const list: string[] = FilePermissionUtil.getPersistedUris();
    if (!list.includes(uri)) {
      list.push(uri);
      PreferencesUtil.putString(PREF_KEY_PERSISTED_URIS, list.join('\n'));
    }
  }

  /** 从持久化列表中移除指定 URI。 */
  private static removePersistedUri(uri: string): void {
    const list: string[] = FilePermissionUtil.getPersistedUris();
    const idx: number = list.indexOf(uri);
    if (idx >= 0) {
      list.splice(idx, 1);
      PreferencesUtil.putString(PREF_KEY_PERSISTED_URIS, list.join('\n'));
    }
  }
}
