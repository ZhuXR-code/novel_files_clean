import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScanRun } from '../model/ScanRun';
import { ScanRunDao } from '../database/ScanRunDao';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';
import { TopBar } from '../components/TopBar';
import { ToastUtil } from '../utils/ToastUtil';

/**
 * 文库 Tab：列出全部文库，点击进入 LibraryScreen；左滑快速删除；下拉刷新。
 * 对齐安卓端「文库」一级页。
 */
@Component
export struct LibraryTab {
  @State runs: ScanRun[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @StorageProp('fontScale') fontScaleNum: number = 1.0;

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  private fs(base: number): number {
    return Math.round(base * this.fontScaleNum);
  }

  async onPageShow(): Promise<void> {
    await this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    try {
      this.runs = await ScanRunDao.getAll();
    } catch (e) {
      LogUtil.e('LibraryTab', `加载失败: ${(e as Error).message}`);
    }
    this.loading = false;
  }

  private openRun(runId: number): void {
    router.pushUrl({ url: 'pages/LibraryScreen', params: { runId: runId } }).catch((err: Error) => {
      LogUtil.e('LibraryTab', `跳转失败: ${err.message}`);
    });
  }

  private newScan(): void {
    router.pushUrl({ url: 'pages/ScanProgress' }).catch((err: Error) => {
      LogUtil.e('LibraryTab', `跳转失败: ${err.message}`);
    });
  }

  private async deleteRun(run: ScanRun): Promise<void> {
    promptAction.showDialog({
      title: '删除文库',
      message: `确认删除文库「${run.name}」及其全部文件记录？此操作不可恢复（不删除原文件）。`,
      buttons: [
        { text: '取消', color: $r('app.color.text_hint') },
        { text: '删除', color: $r('app.color.danger') }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        try {
          await ScannedFileDao.deleteByScanRun(run.id);
          await ScanRunDao.delete(run.id);
          LogUtil.operation('删除文库', `文库ID=${run.id} 名称=${run.name}`);
          await this.load();
        } catch (e) {
          LogUtil.e('LibraryTab', `删除文库失败: ${(e as Error).message}`);
          ToastUtil.show('删除失败');
        }
      }
    });
  }

  @Builder
  swipeDeleteAction(run: ScanRun) {
    Button('删除')
      .backgroundColor($r('app.color.danger'))
      .fontColor($r('app.color.text_on_primary'))
      .height('100%')
      .borderRadius(0)
      .onClick(() => this.deleteRun(run))
  }

  build() {
    Column() {
      TopBar({
        title: '文库',
        showBack: false,
        rightText: '新建扫描',
        onRight: () => this.newScan()
      })

      if (this.runs.length === 0) {
        Column() {
          Text('暂无文库')
            .fontSize(this.fs(16))
            .fontColor($r('app.color.text_hint'))
          Text('点击右上角「新建扫描」开始')
            .fontSize(this.fs(13))
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          List({ space: 10 }) {
            ForEach(
              this.runs,
              (run: ScanRun) => {
                ListItem() {
                  Row() {
                    Column({ space: 4 }) {
                      Text(run.name || '未命名文库')
                        .fontSize(this.fs(16))
                        .fontColor($r('app.color.text_primary'))
                      Text(`目录: ${run.folderName}   文件: ${run.fileCount}`)
                        .fontSize(this.fs(12))
                        .fontColor($r('app.color.text_secondary'))
                      Text(FormatUtil.formatTimestamp(run.createdAt))
                        .fontSize(this.fs(11))
                        .fontColor($r('app.color.text_hint'))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Text(' >')
                      .fontSize(this.fs(16))
                      .fontColor($r('app.color.text_hint'))
                  }
                  .width('100%')
                  .padding(16)
                  .backgroundColor($r('app.color.bg_card'))
                  .borderRadius(10)
                  .onClick(() => this.openRun(run.id))
                }
                .swipeAction({
                  end: {
                    builder: () => {
                      this.swipeDeleteAction(run);
                    }
                  }
                })
                .padding({ left: 12, right: 12 })
              },
              (run: ScanRun) => run.id.toString()
            )
          }
          .width('100%')
          .layoutWeight(1)
        }
        .layoutWeight(1)
        .onRefreshing(() => {
          this.load().then(() => {
            this.refreshing = false;
          });
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
