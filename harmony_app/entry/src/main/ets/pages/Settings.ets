import { router } from '@kit.ArkUI';

@Entry
@Component
struct Settings {
  private go(url: string): void {
    router.pushUrl({ url: url }).catch((err: Error) => {
      console.error(err.message);
    });
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
        this.item('操作日志', 'pages/LogViewer')
        this.item('帮助', 'pages/Help')
      }
      .width('100%')
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(12)
      .margin({ left: 16, right: 16 })

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
