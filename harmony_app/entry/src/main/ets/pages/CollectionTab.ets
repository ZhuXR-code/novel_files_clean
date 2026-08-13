import { router } from '@kit.ArkUI';
import { ScanRun } from '../model/ScanRun';
import { ScanRunDao } from '../database/ScanRunDao';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';
import { TopBar } from '../components/TopBar';

/**
 * 合集 Tab：按文库列出，每行展示「待清理」勾选计数徽标。
 * 点击进入对应文库的 LibraryScreen（内含合集分组视图与去重操作）。
 * 对齐安卓端「合集」一级页：默认折叠 + 待清理计数。
 */
@Component
export struct CollectionTab {
  @State runs: ScanRun[] = [];
  @State checkedMap: Map<number, number> = new Map<number, number>();
  @State totalMap: Map<number, number> = new Map<number, number>();
  @State refreshing: boolean = false;
  @StorageProp('fontScale') fontScaleNum: number = 1.0;

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  private fs(base: number): number {
    return Math.round(base * this.fontScaleNum);
  }

  onPageShow(): void {
    this.load();
  }

  async load(): Promise<void> {
    try {
      const runs = await ScanRunDao.getAll();
      this.runs = runs;
      const cMap = new Map<number, number>();
      const tMap = new Map<number, number>();
      for (const r of runs) {
        cMap.set(r.id, await ScannedFileDao.countChecked(r.id));
        tMap.set(r.id, await ScannedFileDao.countByScanRun(r.id));
      }
      this.checkedMap = cMap;
      this.totalMap = tMap;
    } catch (e) {
      LogUtil.e('CollectionTab', `加载失败: ${(e as Error).message}`);
    }
  }

  private openCollection(runId: number): void {
    router.pushUrl({ url: 'pages/LibraryScreen', params: { runId: runId } }).catch((err: Error) => {
      LogUtil.e('CollectionTab', `跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      TopBar({ title: '合集', showBack: false })

      if (this.runs.length === 0) {
        Column() {
          Text('暂无合集')
            .fontSize(this.fs(16))
            .fontColor($r('app.color.text_hint'))
          Text('请先在「文库」中扫描生成文库')
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
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row({ space: 8 }) {
                        Text(`文件 ${this.totalMap.get(run.id) ?? run.fileCount}`)
                          .fontSize(this.fs(12))
                          .fontColor($r('app.color.text_secondary'))
                        Text(`待清理 ${this.checkedMap.get(run.id) ?? 0}`)
                          .fontSize(this.fs(12))
                          .fontColor((this.checkedMap.get(run.id) ?? 0) > 0 ? $r('app.color.danger') : $r('app.color.text_hint'))
                      }
                      Text(FormatUtil.formatTimestamp(run.createdAt))
                        .fontSize(this.fs(11))
                        .fontColor($r('app.color.text_hint'))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Text('查看 >')
                      .fontSize(this.fs(13))
                      .fontColor($r('app.color.primary'))
                  }
                  .width('100%')
                  .padding(16)
                  .backgroundColor($r('app.color.bg_card'))
                  .borderRadius(10)
                  .onClick(() => this.openCollection(run.id))
                }
              },
              (run: ScanRun) => run.id.toString()
            )
          }
          .width('100%')
          .layoutWeight(1)
          .edgeEffect(EdgeEffect.Spring)
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
