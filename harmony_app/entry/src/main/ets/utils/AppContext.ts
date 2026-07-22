import { common } from '@kit.AbilityKit';

/**
 * 全局持有应用 Context 单例，供工具类（日志、偏好、导出、文件扫描）获取上下文。
 * 在 EntryAbility.onCreate 中调用 AppContext.set(context) 初始化。
 */
export class AppContext {
  private static ctx: common.Context | null = null;

  public static set(context: common.Context): void {
    AppContext.ctx = context;
  }

  public static get(): common.Context | null {
    return AppContext.ctx;
  }
}
