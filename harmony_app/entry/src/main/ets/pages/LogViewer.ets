import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppContext } from '../utils/AppContext';
import { LogUtil } from '../utils/LogUtil';
import { ToastUtil } from '../utils/ToastUtil';
import { TopBar } from '../components/TopBar';

/**
 * 操作日志查看页（G组 #23）：支持刷新、清空、复制、导出。
 * 文件 I/O 全部异步，避免大日志文件读写阻塞 UI 线程。
 */
@Entry
@Component
struct LogViewer {
  @State content: string = '';
  @State showClearConfirm: boolean = false;

  async aboutToAppear(): Promise<void> {
    await this.refresh();
  }

  // G组 #23 刷新日志（异步读取，避免大文件阻塞 UI）
  private async refresh(): Promise<void> {
    try {
      this.content = await LogUtil.readAll();
    } catch (e) {
      ToastUtil.show('读取日志失败');
    }
  }

  // G组 #23 清空日志
  private async clearLog(): Promise<void> {
    try {
      await LogUtil.clear();
      this.content = '';
      this.showClearConfirm = false;
      ToastUtil.show('日志已清空');
    } catch (e) {
      ToastUtil.show('清空日志失败');
    }
  }

  // G组 #23 复制到剪贴板
  private async copyLog(): Promise<void> {
    if (this.content.length === 0) {
      ToastUtil.show('暂无日志可复制');
      return;
    }
    try {
      const pasteData = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.content);
      await pasteData.setData(data);
      ToastUtil.show('已复制到剪贴板');
    } catch (e) {
      ToastUtil.show('复制失败');
    }
  }

  // 导出日志到文件（异步 I/O）
  private async exportLog(): Promise<void> {
    const ctx = AppContext.get();
    if (!ctx) {
      ToastUtil.show('上下文未初始化');
      return;
    }
    if (this.content.length === 0) {
      ToastUtil.show('暂无日志可导出');
      return;
    }
    const path: string = `${ctx.filesDir}/operation_log_export_${Date.now()}.txt`;
    let file: fileIo.File | null = null;
    try {
      file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, this.content);
      ToastUtil.show(`已导出: ${path}`);
    } catch (e) {
      ToastUtil.show(`导出失败: ${(e as Error).message}`);
    } finally {
      if (file) {
        try {
          await fileIo.close(file);
        } catch (e) {
          // 忽略关闭错误
        }
      }
    }
  }

  build() {
    Column() {
      TopBar({ title: '操作日志' })

      // G组 #23 操作按钮行：刷新/复制/清空/导出
      Row({ space: 6 }) {
        Button('刷新')
          .fontSize(12)
          .height(32)
          .backgroundColor($r('app.color.bg_card'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.refresh())
        Button('复制')
          .fontSize(12)
          .height(32)
          .backgroundColor($r('app.color.bg_card'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.copyLog())
        Blank()
        Button('清空')
          .fontSize(12)
          .height(32)
          .backgroundColor($r('app.color.btn_danger_bg'))
          .fontColor($r('app.color.text_on_primary'))
          .onClick(() => (this.showClearConfirm = true))
        Button('导出')
          .fontSize(12)
          .height(32)
          .backgroundColor($r('app.color.btn_primary_bg'))
          .fontColor($r('app.color.text_on_primary'))
          .onClick(() => this.exportLog())
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.bg_card'))

      if (this.content.length === 0) {
        Column() {
          Text('暂无日志')
            .fontSize(15)
            .fontColor($r('app.color.text_hint'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        Scroll() {
          Text(this.content)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .copyOption(CopyOptions.InApp)
            .width('100%')
            .padding(12)
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.bg_card'))
        .edgeEffect(EdgeEffect.Spring)
      }

      // G组 #23 清空确认弹窗
      if (this.showClearConfirm) {
        this.clearConfirmDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  clearConfirmDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => (this.showClearConfirm = false))

      Column({ space: 12 }) {
        Text('确认清空日志？')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('此操作不可恢复，所有操作日志将被永久删除。')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .backgroundColor($r('app.color.bg_page'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => (this.showClearConfirm = false))
          Button('确认清空')
            .layoutWeight(1)
            .height(40)
            .backgroundColor($r('app.color.btn_danger_bg'))
            .fontColor($r('app.color.text_on_primary'))
            .onClick(() => this.clearLog())
        }
        .width('100%')
      }
      .width('80%')
      .padding(20)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(12)
      // 弹窗卡片居中：position + markAnchor 实现真正的中心对齐
      .position({ x: '50%', y: '50%' })
      .markAnchor({ x: '50%', y: '50%' })
    }
    .width('100%')
    .height('100%')
  }
}
