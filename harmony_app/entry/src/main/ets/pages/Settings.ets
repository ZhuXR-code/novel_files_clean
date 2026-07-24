import { router } from '@kit.ArkUI';
import { PreferencesUtil } from '../utils/PreferencesUtil';

const PREVIEW_SCROLLBAR_MODE_KEY: string = 'preview_scrollbar_mode';
type ScrollbarMode = 'vertical' | 'horizontal';

@Entry
@Component
struct Settings {
  @State scrollbarMode: ScrollbarMode = 'vertical';

  aboutToAppear(): void {
    const saved: string = PreferencesUtil.getString(PREVIEW_SCROLLBAR_MODE_KEY, 'vertical');
    this.scrollbarMode = saved === 'horizontal' ? 'horizontal' : 'vertical';
  }

  private go(url: string): void {
    router.pushUrl({ url: url }).catch((err: Error) => {
      console.error(err.message);
    });
  }

  private toggleScrollbarMode(): void {
    this.scrollbarMode = this.scrollbarMode === 'vertical' ? 'horizontal' : 'vertical';
    PreferencesUtil.putString(PREVIEW_SCROLLBAR_MODE_KEY, this.scrollbarMode);
  }

  build() {
    Column() {
      Text('设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 24, bottom: 16 })
        .fontColor($r('app.color.text_primary'))

      Column({ space: 1 }) {
        this.item('关键词替换规则', 'pages/KeywordReplace')
        this.item('勾选重复规则', 'pages/DupRuleSettings')
        this.item('操作日志', 'pages/LogViewer')
        this.item('帮助', 'pages/Help')
      }
      .width('100%')
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(12)
      .margin({ left: 16, right: 16 })

      Text('阅读设置')
        .fontSize(13)
        .fontColor($r('app.color.text_hint'))
        .margin({ top: 24, left: 16 })
      Column({ space: 1 }) {
        this.choiceItem('预览滚动条方向', this.scrollbarMode === 'vertical' ? '竖向' : '横向', () => this.toggleScrollbarMode())
      }
      .width('100%')
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(12)
      .margin({ left: 16, right: 16, top: 8 })

      Text('关于')
        .fontSize(13)
        .fontColor($r('app.color.text_hint'))
        .margin({ top: 24, left: 16 })
      Column({ space: 1 }) {
        this.infoItem('应用名称', '文件清理与内容识别')
        this.infoItem('版本', '1.0.0')
        this.infoItem('运行形态', '纯本地（不联网）')
      }
      .width('100%')
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(12)
      .margin({ left: 16, right: 16, top: 8 })

      Text('数据保存在应用私有目录，不会上传任何服务器。')
        .fontSize(12)
        .fontColor($r('app.color.text_hint'))
        .margin({ top: 24, left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  item(label: string, url: string) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text('>')
        .fontSize(16)
        .fontColor($r('app.color.text_hint'))
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(() => this.go(url))
  }

  @Builder
  choiceItem(label: string, value: string, onClick: () => void) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.text_hint'))
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(onClick)
  }

  @Builder
  infoItem(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
  }
}
