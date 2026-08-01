/**
 * 全局字号缩放工具。
 *
 * 通过 AppStorage 共享 fontScale 值，各页面用 @StorageProp('fontScale') 绑定后，
 * 用户在「我的」-「字号」切换时自动触发 UI 重渲染。
 *
 * 缩放档位：
 *  - small:    0.85x
 *  - standard: 1.0x
 *  - large:    1.2x
 */
export class FontUtil {
  /** AppStorage 键名 */
  public static readonly KEY: string = 'fontScale';

  public static readonly SCALE_SMALL: number = 0.85;
  public static readonly SCALE_STANDARD: number = 1.0;
  public static readonly SCALE_LARGE: number = 1.2;

  /** 将 'small'/'standard'/'large' 字符串转为数值缩放比。 */
  public static scaleFromString(value: string): number {
    if (value === 'small') {
      return FontUtil.SCALE_SMALL;
    }
    if (value === 'large') {
      return FontUtil.SCALE_LARGE;
    }
    return FontUtil.SCALE_STANDARD;
  }

  /** 读取当前 AppStorage 中的缩放比（默认 1.0）。 */
  public static scale(): number {
    return AppStorage.get<number>(FontUtil.KEY) ?? FontUtil.SCALE_STANDARD;
  }

  /** 将基准字号按当前缩放比放大/缩小。 */
  public static size(base: number): number {
    return Math.round(base * FontUtil.scale());
  }
}
