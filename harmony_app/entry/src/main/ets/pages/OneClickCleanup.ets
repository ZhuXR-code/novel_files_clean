import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScanRun } from '../model/ScanRun';
import { ScanRunDao } from '../database/ScanRunDao';
import { DupLogic } from '../utils/DupLogic';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct OneClickCleanup {
  @State runs: ScanRun[] = [];
  @State selectedRunId: number = 0;
  @State marking: boolean = false;
  @State checkedCount: number = -1;

  async aboutToAppear(): Promise<void> {
    try {
      this.runs = await ScanRunDao.getAll();
    } catch (e) {
      LogUtil.e('OneClickCleanup', `加载失败: ${(e as Error).message}`);
    }
  }

  private async mark(): Promise<void> {
    if (this.selectedRunId <= 0) {
      promptAction.showToast({ message: '请先选择文库' });
      return;
    }
    this.marking = true;
    try {
      const ids: number[] = await DupLogic.selectDuplicateIds(this.selectedRunId);
      this.checkedCount = ids.length;
      promptAction.showToast({ message: `已标记 ${ids.length} 个重复文件` });
    } catch (e) {
      LogUtil.e('OneClickCleanup', `标记重复失败: ${(e as Error).message}`);
      promptAction.showToast({ message: '标记失败' });
    }
    this.marking = false;
  }

  private goDelete(): void {
    if (this.selectedRunId <= 0) {
      return;
    }
    router.pushUrl({ url: 'pages/DeleteConfirm', params: { runId: this.selectedRunId } }).catch((err: Error) => {
      LogUtil.e('OneClickCleanup', `跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      Row() {
        Button('返回').onClick(() => router.back())
        Text('一键清理')
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

      Text('选择文库后点击「标记重复」，系统将按五则规则自动勾选应删除的重复文件。')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .padding(16)
        .lineHeight(18)

      if (this.runs.length === 0) {
        Text('暂无文库，请先扫描')
          .fontSize(15)
          .fontColor($r('app.color.text_hint'))
          .margin({ top: 40 })
      } else {
        List() {
          ForEach(
            this.runs,
            (run: ScanRun) => {
              ListItem() {
                Row({ space: 12 }) {
                  Radio({ value: run.id.toString(), group: 'runGroup' })
                    .checked(this.selectedRunId === run.id)
                    .onChange((isOn: boolean) => {
                      if (isOn) {
                        this.selectedRunId = run.id;
                        this.checkedCount = -1;
                      }
                    })
                  Column({ space: 3 }) {
                    Text(run.name || '未命名文库')
                      .fontSize(15)
                      .fontColor($r('app.color.text_primary'))
                    Text(`目录: ${run.folderName}   文件: ${run.fileCount}`)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(14)
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(10)
              }
              .padding({ left: 12, right: 12, bottom: 10 })
            },
            (run: ScanRun) => run.id.toString()
          )
        }
        .layoutWeight(1)
        .width('100%')
      }

      Column({ space: 10 }) {
        Button('标记重复')
          .width('80%')
          .backgroundColor($r('app.color.primary'))
          .enabled(!this.marking && this.selectedRunId > 0)
          .onClick(() => this.mark())
        if (this.checkedCount >= 0) {
          Text(`已勾选 ${this.checkedCount} 个待删文件`)
            .fontSize(14)
            .fontColor($r('app.color.danger'))
          Button('去删除')
            .width('80%')
            .backgroundColor($r('app.color.danger'))
            .onClick(() => this.goDelete())
        }
      }
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
