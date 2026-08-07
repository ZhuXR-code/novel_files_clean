import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { LogUtil } from './LogUtil';

/**
 * 运行时动态权限申请工具（user_grant 权限）。
 *
 * READ_WRITE_DOCUMENTS_DIRECTORY / READ_WRITE_DOWNLOAD_DIRECTORY 属于
 * user_grant（用户授权）权限：仅静态声明不够，必须在运行时通过
 * requestPermissionsFromUser 弹窗申请，用户允许后才真正生效。
 *
 * 扫描主流程走 Picker 授权的 URI，不依赖这些权限；但按绝对路径删除文件
 * （DeleteService 的 fileIo.unlink）以及路径回退校验（listFileSync）依赖它们。
 * 部分设备/模拟器可能不支持授权（返回拒绝），此处仅记日志，不阻断主流程。
 */
export class PermissionRequester {
  /** 应用实际依赖的 user_grant 权限列表 */
  public static readonly NEEDED_PERMISSIONS: Array<Permissions> = [
    'ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY',
    'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY'
  ];

  /** 检查指定权限当前是否已授予。 */
  public static isGranted(context: common.UIAbilityContext, permission: Permissions): boolean {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const tokenId: number = context.applicationInfo.accessTokenId;
      const status: abilityAccessCtrl.GrantStatus = atManager.checkAccessTokenSync(tokenId, permission);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (e) {
      LogUtil.w('Permission', `检查权限状态失败 ${permission}: ${(e as Error).message}`);
      return false;
    }
  }

  /**
   * 申请尚未授予的 user_grant 权限（幂等：已授予的自动跳过）。
   * 任一申请失败（用户拒绝 / 设备不支持）仅记日志，不抛出异常。
   */
  public static async requestIfNeeded(context: common.UIAbilityContext): Promise<void> {
    try {
      const needed: Array<Permissions> = [];
      for (const p of PermissionRequester.NEEDED_PERMISSIONS) {
        if (!PermissionRequester.isGranted(context, p)) {
          needed.push(p);
        }
      }
      if (needed.length === 0) {
        LogUtil.i('Permission', 'user_grant 权限均已授予，无需申请');
        return;
      }
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(context, needed);
      for (let i = 0; i < result.permissions.length; i++) {
        const granted: boolean = result.authResults[i] === 0;
        LogUtil.i('Permission', `动态权限申请 ${result.permissions[i]}: ${granted ? '已授予' : '未授予'}`);
      }
    } catch (e) {
      LogUtil.w('Permission', `动态申请权限失败: ${(e as Error).message}`);
    }
  }
}
