import { promptAction } from '@kit.ArkUI';
import { AppContext } from './AppContext';

/**
 * Toast 统一封装（G组 #23 之后统一替换散落各页的 promptAction.showToast）。
 *
 * 背景：模块级 promptAction.showToast 已被官方标记 deprecated，推荐改用
 *   this.getUIContext().getPromptAction().showToast()。
 * 但工具类/服务类无组件 this，故通过 AppContext 持有的主窗口取得 UIContext，
 * 再调用其 PromptAction；窗口未就绪等极端情况下回退到模块级 API（废弃但仍可用），
 * 确保 Toast 至少能展示，不因 API 切换而丢提示。
 */
export class ToastUtil {
  /**
   * 展示一条 Toast。
   * @param message 文案
   * @param duration 时长（毫秒），默认 1500
   */
  public static show(message: string, duration: number = 1500): void {
    try {
      const win = AppContext.getMainWindow();
      if (win) {
        const uiCtx = win.getUIContext();
        uiCtx.getPromptAction().showToast({ message: message, duration: duration });
        return;
      }
    } catch (e) {
      // 窗口或 UIContext 未就绪，回退到模块级 API
    }
    try {
      promptAction.showToast({ message: message, duration: duration });
    } catch (e) {
      // 忽略：Toast 失败不应影响业务流程
    }
  }
}
