import { router, promptAction } from '@kit.ArkUI';
import { ConfigurationConstant, bundleManager } from '@kit.AbilityKit';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { AppContext } from '../utils/AppContext';
import { LogUtil } from '../utils/LogUtil';
import { TopBar } from '../components/TopBar';
import { FontUtil } from '../utils/FontUtil';
import { ToastUtil } from '../utils/ToastUtil';

const THEME_MODE_KEY: string = 'settings_theme_mode';
const FONT_SCALE_KEY: string = 'settings_font_scale';
type ThemeMode = 'system' | 'light' | 'dark';
type FontScale = 'small' | 'standard' | 'large';

interface ThemeOption {
  label: string;
  value: ThemeMode;
}
interface FontOption {
  label: string;
  value: FontScale;
}

const THEME_OPTIONS: ThemeOption[] = [
  { label: '跟随系统', value: 'system' },
  { label: '浅色', value: 'light' },
  { label: '深色', value: 'dark' }
];
const FONT_OPTIONS: FontOption[] = [
  { label: '小', value: 'small' },
  { label: '标准', value: 'standard' },
  { label: '大', value: 'large' }
];

/**
 * 我的 Tab：外观 / 功能 / 数据 / 关于。
 * 对齐安卓端「我的」一级页。
 */
@Component
export struct MinePage {
  @State themeMode: ThemeMode = 'system';
  @State fontScale: FontScale = 'standard';
  @StorageProp('fontScale') fontScaleNum: number = 1.0;
  @State appVersion: string = '';

  aboutToAppear(): void {
    const themeSaved: string = PreferencesUtil.getString(THEME_MODE_KEY, 'system');
    this.themeMode = (themeSaved === 'light' || themeSaved === 'dark') ? themeSaved as ThemeMode : 'system';
    const fontSaved: string = PreferencesUtil.getString(FONT_SCALE_KEY, 'standard');
    this.fontScale = (fontSaved === 'small' || fontSaved === 'large') ? fontSaved as FontScale : 'standard';
    this.loadAppVersion();
  }

  private loadAppVersion(): void {
    try {
      const bundleInfo: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = bundleInfo.versionName ?? '';
    } catch (e) {
      LogUtil.e('MinePage', `读取版本号失败: ${e}`);
      this.appVersion = '';
    }
  }

  private go(url: string): void {
    router.pushUrl({ url: url }).catch((err: Error) => {
      LogUtil.e('MinePage', `跳转失败: ${err.message}`);
    });
  }

  /** 按全局字号缩放比换算基准字号 */
  private fs(base: number): number {
    return Math.round(base * this.fontScaleNum);
  }

  // ── 主题模式 ──
  private themeIndex(): string {
    return THEME_OPTIONS.find((o) => o.value === this.themeMode)?.label ?? '跟随系统';
  }

  private handleThemeChange(label: string): void {
    const opt = THEME_OPTIONS.find((o) => o.label === label);
    if (!opt) {
      return;
    }
    this.themeMode = opt.value;
    PreferencesUtil.putString(THEME_MODE_KEY, opt.value);
    try {
      const ctx = AppContext.get();
      if (ctx) {
        const appCtx = ctx.getApplicationContext();
        if (opt.value === 'dark') {
          appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        } else if (opt.value === 'light') {
          appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
        } else {
          appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        }
      }
    } catch (e) {
      LogUtil.e('MinePage', `切换主题失败: ${(e as Error).message}`);
    }
    ToastUtil.show(`主题已切换为「${opt.label}」`);
  }

  // ── 字号 ──
  private fontIndex(): string {
    return FONT_OPTIONS.find((o) => o.value === this.fontScale)?.label ?? '标准';
  }

  private handleFontChange(label: string): void {
    const opt = FONT_OPTIONS.find((o) => o.label === label);
    if (!opt) {
      return;
    }
    this.fontScale = opt.value;
    PreferencesUtil.putString(FONT_SCALE_KEY, opt.value);
    // 同步到 AppStorage，所有 @StorageProp('fontScale') 绑定的页面立即重渲染
    AppStorage.set(FontUtil.KEY, FontUtil.scaleFromString(opt.value));
    ToastUtil.show(`字号已切换为「${opt.label}」`);
  }

  // ── 预览滚动条 ──


  build() {
    Column() {
      TopBar({ title: '我的', showBack: false })

      Scroll() {
        Column() {
          // ── 外观 ──
          Text('外观')
            .fontSize(this.fs(13))
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 16, left: 16, bottom: 4 })
          Column({ space: 1 }) {
            // 主题模式（内联以响应 @State 变化）
            Row() {
              Text('主题模式').fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
              Blank()
              Select(THEME_OPTIONS.map((o): SelectOption => ({ value: o.label })))
                .value(this.themeIndex())
                .font({ size: 14 })
                .fontColor($r('app.color.text_secondary'))
                .margin({ right: 8 })
                .onSelect((_idx: number, label: string) => this.handleThemeChange(label))
            }
            .width('100%').height(52).padding({ left: 16, right: 16 })

            // 字号（内联以响应 @State 变化）
            Row() {
              Text('字号').fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
              Blank()
              Select(FONT_OPTIONS.map((o): SelectOption => ({ value: o.label })))
                .value(this.fontIndex())
                .font({ size: 14 })
                .fontColor($r('app.color.text_secondary'))
                .margin({ right: 8 })
                .onSelect((_idx: number, label: string) => this.handleFontChange(label))
            }
            .width('100%').height(52).padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          // ── 功能 ──
          Text('功能')
            .fontSize(this.fs(13))
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 20, left: 16, bottom: 4 })
          Column({ space: 1 }) {
            this.item('关键词替换规则', 'pages/KeywordReplace')
            this.item('勾选重复规则', 'pages/DupRuleSettings')
          }
          .width('100%')
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          // ── 关于 ──
          Text('关于')
            .fontSize(this.fs(13))
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 20, left: 16, bottom: 4 })
          Column({ space: 1 }) {
            this.item('操作日志', 'pages/LogViewer')
            this.item('帮助', 'pages/Help')
            this.item('隐私协议', 'pages/PrivacyPolicy')
            this.infoItem('应用名称', '文包整理清理助手')
            this.infoItem('版本', this.appVersion)
            this.infoItem('运行形态', '纯本地（不联网）')
          }
          .width('100%')
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(12)
          .margin({ left: 16, right: 16 })

          Text('数据保存在应用私有目录，不会上传任何服务器。')
            .fontSize(this.fs(12))
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 24, left: 16, right: 16, bottom: 24 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // ── Builder 复用 ──
  @Builder
  item(label: string, url: string) {
    Row() {
      Text(label).fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
      Blank()
      Text('>').fontSize(this.fs(16)).fontColor($r('app.color.text_hint'))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .onClick(() => this.go(url))
  }

  @Builder
  choiceItem(label: string, value: string, onClick: () => void) {
    Row() {
      Text(label).fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
      Blank()
      Text(value).fontSize(this.fs(15)).fontColor($r('app.color.text_hint'))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .onClick(onClick)
  }

  @Builder
  selectItem(label: string, value: string, options: string[], onChange: (label: string) => void) {
    Row() {
      Text(label).fontSize(this.fs(16)).fontColor($r('app.color.text_primary'))
      Blank()
      Select(options.map((o: string): SelectOption => ({ value: o })))
        .value(value)
        .font({ size: 14 })
        .fontColor($r('app.color.text_secondary'))
        .margin({ right: 8 })
        .onSelect((_idx: number, label: string) => onChange(label))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
  }

  @Builder
  infoItem(label: string, value: string) {
    Row() {
      Text(label).fontSize(this.fs(15)).fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value).fontSize(this.fs(15)).fontColor($r('app.color.text_primary'))
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
  }
}
