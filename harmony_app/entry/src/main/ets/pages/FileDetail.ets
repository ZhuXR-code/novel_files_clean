import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScannedFile } from '../model/ScannedFile';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct FileDetail {
  @State fileId: number = 0;
  @State file: ScannedFile | null = null;
  @State loading: boolean = true;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['fileId'] !== undefined && params['fileId'] !== null) {
      this.fileId = params['fileId'] as number;
    }
    this.file = await ScannedFileDao.getById(this.fileId);
    this.loading = false;
  }

  private async onMarkChanged(marked: boolean): Promise<void> {
    if (!this.file) {
      return;
    }
    this.file.marked = marked ? 1 : 0;
    await ScannedFileDao.updateMarked(this.file.id, this.file.marked);
  }

  private async onCheckChanged(checked: boolean): Promise<void> {
    if (!this.file) {
      return;
    }
    this.file.checked = checked ? 1 : 0;
    await ScannedFileDao.updateChecked(this.file.id, this.file.checked);
  }

  private deleteThis(): void {
    if (!this.file) {
      return;
    }
    router.pushUrl({ url: 'pages/DeleteConfirm', params: { runId: this.file.scanRunId, fileIds: [this.file.id] } }).catch(
      (err: Error) => {
        LogUtil.e('FileDetail', `跳转失败: ${err.message}`);
      }
    );
  }

  private previewContent(): void {
    if (!this.file) {
      return;
    }
    router.pushUrl({
      url: 'pages/FilePreview',
      params: {
        fileName: this.file.fileName,
        filePath: this.file.path
      }
    }).catch((err: Error) => {
      LogUtil.e('FileDetail', `跳转预览失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back())
        Text('文件详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_primary'))
        Button('预览')
          .backgroundColor($r('app.color.primary'))
          .onClick(() => this.previewContent())
        Button('删除')
          .backgroundColor($r('app.color.danger'))
          .onClick(() => this.deleteThis())
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.file) {
        Scroll() {
          Column({ space: 12 }) {
            this.infoRow('文件名', this.file!.fileName)
            this.infoRow('路径', this.file!.path)
            this.infoRow('书名', this.file!.title || '(未解析)')
            this.infoRow('作者', this.file!.author || '(未解析)')
            this.infoRow('进度', this.file!.progress || '(未解析)')
            this.infoRow('来源', this.file!.source || '(未解析)')
            this.infoRow('扩展名', this.file!.ext || '(无)')
            this.infoRow('大小', FormatUtil.formatFileSize(this.file!.fileSize))
            this.infoRow('创建时间', FormatUtil.formatTimestamp(this.file!.createdAt))

            Row({ space: 20 }) {
              Row({ space: 8 }) {
                Text('星标')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Toggle({ type: ToggleType.Switch, isOn: this.file!.marked === 1 }).onChange((v: boolean) => this.onMarkChanged(v))
              }
              Row({ space: 8 }) {
                Text('勾选删除')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Toggle({ type: ToggleType.Switch, isOn: this.file!.checked === 1 }).onChange((v: boolean) => this.onCheckChanged(v))
              }
            }
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(16)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  infoRow(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .copyOption(CopyOptions.InApp)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(8)
    .padding(12)
  }
}
