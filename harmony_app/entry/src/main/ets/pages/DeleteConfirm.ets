import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScannedFile } from '../model/ScannedFile';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct DeleteConfirm {
  @State runId: number = 0;
  @State fileIds: number[] = [];
  @State files: ScannedFile[] = [];
  @State loading: boolean = true;
  @State deleteSource: boolean = true;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['runId'] !== undefined && params['runId'] !== null) {
      this.runId = params['runId'] as number;
    }
    if (params && params['fileIds'] !== undefined && params['fileIds'] !== null) {
      this.fileIds = params['fileIds'] as number[];
    }
    try {
      if (this.fileIds.length > 0) {
        this.files = await ScannedFileDao.getByIds(this.fileIds);
      } else {
        const all: ScannedFile[] = await ScannedFileDao.getByScanRun(this.runId, 1000000, 0);
        this.files = all.filter((f) => f.checked === 1);
      }
    } catch (e) {
      LogUtil.e('DeleteConfirm', `加载失败: ${(e as Error).message}`);
    }
    this.loading = false;
  }

  private confirm(): void {
    if (this.files.length === 0) {
      promptAction.showToast({ message: '没有待删文件' });
      return;
    }
    const ids: number[] = this.files.map((f) => f.id);
    router.pushUrl({ url: 'pages/DeleteProgress', params: { runId: this.runId, ids: ids, deleteSource: this.deleteSource } }).catch((err: Error) => {
      LogUtil.e('DeleteConfirm', `跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back())
        Text('删除确认')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_primary'))
        Button('').width(0).height(0).visibility(Visibility.Hidden)
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      Column({ space: 8 }) {
        Text(`待删除 ${this.files.length} 个文件`)
          .fontSize(13)
          .fontColor($r('app.color.danger'))
        Text(this.deleteSource ? '将同时删除物理文件与数据库记录' : '仅删除数据库记录，不删除物理文件')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Row({ space: 8 }) {
          Text('删除源文件')
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
          Toggle({ type: ToggleType.Switch, isOn: this.deleteSource })
            .onChange((isOn: boolean) => {
              this.deleteSource = isOn;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .padding(16)

      if (this.files.length === 0) {
        Text('没有可删除的文件')
          .fontSize(15)
          .fontColor($r('app.color.text_hint'))
          .margin({ top: 40 })
      } else {
        List() {
          ForEach(
            this.files,
            (file: ScannedFile) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(file.title || file.fileName)
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${file.fileName}   ${FormatUtil.formatFileSize(file.fileSize)}`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_hint'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(8)
              }
              .padding({ left: 12, right: 12, bottom: 6 })
            },
            (file: ScannedFile) => file.id.toString()
          )
        }
        .layoutWeight(1)
        .width('100%')
      }

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .onClick(() => router.back())
        Button('确认删除')
          .layoutWeight(1)
          .backgroundColor($r('app.color.danger'))
          .enabled(this.files.length > 0)
          .onClick(() => this.confirm())
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
