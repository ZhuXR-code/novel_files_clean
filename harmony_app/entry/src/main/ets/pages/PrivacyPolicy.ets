import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { TopBar } from '../components/TopBar';
import { AppContext } from '../utils/AppContext';

const PRIVACY_KEY: string = 'privacy_agreed';

/**
 * 隐私协议页。
 * - mode = 'agree'：首次启动拦截，必须主动选择"同意并继续"或"不同意并退出"，无返回。
 * - mode = 'view'：设置页内查看，可返回。
 */
@Entry
@Component
struct PrivacyPolicy {
  @State content: string = '';
  @State mode: string = 'view'; // 'agree' | 'view'
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string> | undefined;
    if (params && params['mode']) {
      this.mode = params['mode'];
    }
    this.loadText();
  }

  private async loadText(): Promise<void> {
    try {
      const ctx = AppContext.get();
      if (!ctx) {
        this.content = '隐私协议加载失败。';
        return;
      }
      const data: Uint8Array = await ctx.resourceManager.getRawFileContent('privacy_policy.txt');
      const decoder = new util.TextDecoder('utf-8');
      this.content = decoder.decodeToString(data);
    } catch (e) {
      this.content = '隐私协议加载失败，请重试或联系我们。';
    }
  }

  private agree(): void {
    PreferencesUtil.putBoolean(PRIVACY_KEY, true);
    if (this.mode === 'agree') {
      router.replaceUrl({ url: 'pages/MainTabs' });
    } else {
      router.back();
    }
  }

  private disagree(): void {
    const ctx = AppContext.get() as common.UIAbilityContext;
    if (ctx) {
      ctx.terminateSelf();
    }
  }

  build() {
    Column() {
      TopBar({ title: '隐私协议', showBack: this.mode === 'view' })

      Scroll(this.scroller) {
        Text(this.content)
          .fontSize(14)
          .lineHeight(22)
          .padding(16)
      }
      .layoutWeight(1)
      .align(Alignment.Top)

      if (this.mode === 'agree') {
        Row() {
          Button('不同意并退出', { type: ButtonType.Normal })
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_card'))
            .fontColor($r('app.color.text_hint'))
            .onClick(() => this.disagree())
          Button('同意并继续', { type: ButtonType.Normal })
            .layoutWeight(1)
            .backgroundColor($r('app.color.primary'))
            .fontColor($r('app.color.text_on_primary'))
            .onClick(() => this.agree())
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.bg_card'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
