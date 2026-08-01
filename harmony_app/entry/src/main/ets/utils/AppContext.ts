import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/**
 * 全局持有应用 Context 单例，供工具类（日志、偏好、导出、文件扫描）获取上下文。
 * 在 EntryAbility.onCreate 中调用 AppContext.set(context) 初始化。
 * 主题色模式切换已改用 ApplicationContext.setColorMode()，通过 AppContext.get() 获取上下文。
 * mainWindow 引用保留备用。
 */
export class AppContext {
  private static ctx: common.Context | null = null;
  private static mainWindow: window.Window | null = null;

  public static set(context: common.Context): void {
    AppContext.ctx = context;
  }

  public static get(): common.Context | null {
    return AppContext.ctx;
  }

  /** 由 EntryAbility.onWindowStageCreate 在 loadContent 成功后调用。 */
  public static setMainWindow(win: window.Window): void {
    AppContext.mainWindow = win;
  }

  /** 获取主窗口引用，用于运行时切换主题色模式。 */
  public static getMainWindow(): window.Window | null {
    return AppContext.mainWindow;
  }
}
