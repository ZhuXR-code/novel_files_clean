import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScanRun } from '../model/ScanRun';
import { ScanRunDao } from '../database/ScanRunDao';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct LibraryList {
  @State runs: ScanRun[] = [];
  @State loading: boolean = true;

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    try {
      this.runs = await ScanRunDao.getAll();
    } catch (e) {
      LogUtil.e('LibraryList', `加载失败: ${(e as Error).message}`);
    }
    this.loading = false;
  }

  private openRun(runId: number): void {
    router.pushUrl({ url: 'pages/LibraryScreen', params: { runId: runId } }).catch((err: Error) => {
      LogUtil.e('LibraryList', `跳转失败: ${err.message}`);
    });
  }

  private async deleteRun(run: ScanRun): Promise<void> {
    promptAction.showDialog({
      title: '删除文库',
      message: `确认删除文库「${run.name}」及其全部文件记录？此操作不可恢复（不删除原文件）。`,
      buttons: [{ text: '取消', color: '#888888' }, { text: '删除', color: '#ff3b30' }]
    }).then((result) => {
      if (result.index === 1) {
        ScannedFileDao.deleteByScanRun(run.id);
        ScanRunDao.delete(run.id);
        LogUtil.operation('删除文库', `文库ID=${run.id} 名称=${run.name}`);
        this.load();
      }
    });
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back())
        Text('文库列表')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button('新建扫描')
          .backgroundColor($r('app.color.primary'))
          .onClick(() => {
            router.pushUrl({ url: 'pages/ScanProgress' }).catch((err: Error) => {
              LogUtil.e('LibraryList', `跳转失败: ${err.message}`);
            });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.runs.length === 0) {
        Column() {
          Text('暂无文库')
            .fontSize(16)
            .fontColor($r('app.color.text_hint'))
          Text('点击右上角「新建扫描」开始')
            .fontSize(13)
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(
            this.runs,
            (run: ScanRun) => {
              ListItem() {
                Row() {
                  Column({ space: 4 }) {
                    Text(run.name || '未命名文库')
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                    Text(`目录: ${run.folderName}   文件: ${run.fileCount}`)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                    Text(FormatUtil.formatTimestamp(run.createdAt))
                      .fontSize(11)
                      .fontColor($r('app.color.text_hint'))
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Button('删除')
                    .backgroundColor($r('app.color.danger'))
                    .height(36)
                    .onClick(() => this.deleteRun(run))
                }
                .width('100%')
                .padding(16)
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(10)
                .onClick(() => this.openRun(run.id))
              }
              .padding({ left: 12, right: 12, bottom: 10 })
            },
            (run: ScanRun) => run.id.toString()
          )
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.bg_page'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
