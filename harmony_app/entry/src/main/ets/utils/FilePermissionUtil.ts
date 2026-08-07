import { fileShare, fileIo, picker } from '@kit.CoreFileKit';
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
  public static async checkUriAccessible(uri: string): Promise<boolean> {
    if (!uri || uri.length === 0) {
      return false;
    }
    // Picker 返回的 URI（content:// / file://）走异步 listFile
    if (uri.startsWith('content://') || uri.startsWith('file://')) {
      try {
        await fileIo.listFile(uri);
        return true;
      } catch (e) {
        return false;
      }
    }
    // 真实文件系统路径：listFileSync 同步校验
    try {
      fileIo.listFileSync(uri);
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
   * @returns 授权成功返回 true，用户取消或失败返回 false
   */
  public static async reauthorizeUri(context: common.Context, uri: string): Promise<boolean> {
    if (!uri || uri.length === 0) {
      return false;
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
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return false; // 用户取消
      }
      // 重新持久化
      await FilePermissionUtil.persistFolderPermission(uris[0]);
      LogUtil.i('FilePermission', `重新授权成功: ${uris[0]}`);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      LogUtil.e('FilePermission', `重新授权失败: code=${err.code} msg=${err.message}`);
      return false;
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
