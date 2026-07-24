import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { AppContext } from '../utils/AppContext';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct LogViewer {
  @State content: string = '';

  async aboutToAppear(): Promise<void> {
    this.content = LogUtil.readAll();
  }

  private async exportLog(): Promise<void> {
    const ctx = AppContext.get();
    if (!ctx) {
      promptAction.showToast({ message: '上下文未初始化' });
      return;
    }
    const path: string = `${ctx.filesDir}/operation_log_export_${Date.now()}.txt`;
    const file = fileIo.openSync(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, this.content);
    } finally {
      fileIo.closeSync(file);
    }
    promptAction.showToast({ message: `已导出: ${path}` });
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back())
        Text('操作日志')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_primary'))
        Button('导出')
          .backgroundColor($r('app.color.primary'))
          .onClick(() => this.exportLog())
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.content.length === 0) {
        Text('暂无日志')
          .fontSize(15)
          .fontColor($r('app.color.text_hint'))
          .margin({ top: 40 })
      } else {
        TextArea({ text: this.content }).enabled(false)
          .layoutWeight(1)
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.bg_card'))
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
