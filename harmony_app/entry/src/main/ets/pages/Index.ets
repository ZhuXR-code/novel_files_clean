import { router } from '@kit.ArkUI';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { ScanRunDao } from '../database/ScanRunDao';
import { ScanRun } from '../model/ScanRun';
import { LogUtil } from '../utils/LogUtil';

interface NavParams {
  runId?: number;
}

/**
 * 首页 Tab：扫描入口 + 概览统计 + 最近文库。
 * 对齐安卓端「首页」：大主按钮 + 统计卡片 + 最近文库；下拉刷新统计。
 */
@Component
export struct HomePage {
  @State recentRuns: ScanRun[] = [];
  @State refreshing: boolean = false;
  @StorageProp('fontScale') fontScaleNum: number = 1.0;

  async aboutToAppear(): Promise<void> {
    await this.loadStats();
  }

  // 每次从其它 Tab（文库/我的）切回首页时重新拉取统计，避免 Tab 不重挂导致数据停留在旧值
  onPageShow(): void {
    this.loadStats();
  }

  private fs(base: number): number {
    return Math.round(base * this.fontScaleNum);
  }

  async loadStats(): Promise<void> {
    try {
      this.recentRuns = await ScanRunDao.getRecent(5);
    } catch (e) {
      LogUtil.e('HomePage', `recentRuns 统计失败: ${(e as Error)?.message ?? e}`);
    }
  }

  private go(url: string, params?: NavParams): void {
    router.pushUrl({ url: url, params: params }).catch((err: Error) => {
      LogUtil.e('HomePage', `导航失败 ${url}: ${err.message}`);
    });
  }

  private openLibrary(runId: number): void {
    this.go('pages/LibraryScreen', { runId: runId } as NavParams);
  }

  build() {
    Column() {
      Text('文包整理清理助手')
        .fontSize(this.fs(22))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 20, bottom: 10 })

      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            // 操作指引说明卡片（对齐安卓端 HomeScreen 指引卡片）
            Column({ space: 6 }) {
              Row({ space: 6 }) {
                Text('方法一')
                  .fontSize(this.fs(12))
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary'))
                Text('开始扫描/查看文库：配置扫描路径→扫描+解析→合集模式→勾选重复→批量删除选中')
                  .fontSize(this.fs(12))
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
              }
              .width('100%')
              Row({ space: 6 }) {
                Text('方法二')
                  .fontSize(this.fs(12))
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary'))
                Text('一键清理：选择文件夹 → 一键清理（自动扫描标记，删除前可查看清单确认）')
                  .fontSize(this.fs(12))
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
              }
              .width('100%')
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.bg_card'))
            .borderRadius(10)
            .margin({ left: 16, right: 16, bottom: 12 })

            // 无数据提示（对齐安卓端：无文库时显示提示卡片）
            if (this.recentRuns.length === 0) {
              Column({ space: 8 }) {
                Text('暂无数据')
                  .fontSize(this.fs(16))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_hint'))
                Text('点击上方「开始扫描」或「一键清理」开始使用')
                  .fontSize(this.fs(12))
                  .fontColor($r('app.color.text_hint'))
              }
              .width('100%')
              .padding(40)
              .alignItems(HorizontalAlign.Center)
            }

            // 快速开始
            Row({ space: 10 }) {
              Button() {
                Column({ space: 4 }) {
                  Text('开始扫描')
                    .fontSize(this.fs(15))
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_on_primary'))
                  Text('选择目录创建文库')
                    .fontSize(this.fs(11))
                    .fontColor($r('app.color.text_on_primary'))
                    .opacity(0.7)
                }
              }
              .layoutWeight(1)
              .height(72)
              .backgroundColor($r('app.color.primary'))
              .borderRadius(12)
              .onClick(() => this.go('pages/ScanConfigList'))

              Button() {
                Column({ space: 4 }) {
                  Text('一键清理')
                    .fontSize(this.fs(15))
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_on_primary'))
                  Text('快速勾选重复文件')
                    .fontSize(this.fs(11))
                    .fontColor($r('app.color.text_on_primary'))
                    .opacity(0.7)
                }
              }
              .layoutWeight(1)
              .height(72)
              .backgroundColor($r('app.color.primary_dark'))
              .borderRadius(12)
              .onClick(() => this.go('pages/OneClickCleanup'))
            }
            .padding({ left: 16, right: 16 })
            .margin({ bottom: 16 })

            // G组 #28 更多功能入口（帮助/日志/规则/设置）
            Column({ space: 8 }) {
              Text('更多功能')
                .fontSize(this.fs(13))
                .fontColor($r('app.color.text_hint'))
                .padding({ left: 16, bottom: 4 })

              Row({ space: 8 }) {
                this.funcEntry('帮助文档', () => this.go('pages/Help'))
                this.funcEntry('操作日志', () => this.go('pages/LogViewer'))
                this.funcEntry('关键词替换', () => this.go('pages/KeywordReplace'))
                this.funcEntry('去重规则', () => this.go('pages/DupRuleSettings'))
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
            }
            .margin({ bottom: 16 })

            // 最近文库
            if (this.recentRuns.length > 0) {
              Column() {
                Row() {
                  Text('最近文库')
                    .fontSize(this.fs(13))
                    .fontColor($r('app.color.text_hint'))
                    .layoutWeight(1)
                  Text('切到「文库」查看全部 >')
                    .fontSize(this.fs(12))
                    .fontColor($r('app.color.primary'))
                    .onClick(() => this.go('pages/LibraryList'))
                }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 8 })

                List() {
                  ForEach(
                    this.recentRuns,
                    (run: ScanRun) => {
                      ListItem() {
                        Row({ space: 10 }) {
                          Column({ space: 3 }) {
                            Text(run.name || '未命名文库')
                              .fontSize(this.fs(14))
                              .fontColor($r('app.color.text_primary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                            Text(`目录: ${run.folderName}   文件: ${run.fileCount}`)
                              .fontSize(this.fs(11))
                              .fontColor($r('app.color.text_secondary'))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                          }
                          .layoutWeight(1)
                          .alignItems(HorizontalAlign.Start)
                          Text(' >')
                            .fontSize(this.fs(16))
                            .fontColor($r('app.color.text_hint'))
                        }
                        .width('100%')
                        .padding(14)
                        .backgroundColor($r('app.color.bg_card'))
                        .borderRadius(10)
                        .onClick(() => this.openLibrary(run.id))
                      }
                      .padding({ left: 16, right: 16, bottom: 8 })
                    },
                    (run: ScanRun) => run.id.toString()
                  )
                }
                .constraintSize({ maxHeight: 240 })
                .width('100%')
              }
              .margin({ bottom: 12 })
            }

            // 本地处理声明（对齐安卓端底部声明）
            Text('🔒 本地扫描，文件不会上传')
              .fontSize(this.fs(11))
              .fontColor($r('app.color.text_hint'))
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ top: 8, bottom: 20 })
          }
          .width('100%')
        }
        .align(Alignment.Top)
        .layoutWeight(1)
      }
      .layoutWeight(1)
      .onRefreshing(() => {
        this.loadStats().then(() => {
          this.refreshing = false;
        });
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  // G组 #28 更多功能入口按钮
  @Builder
  funcEntry(label: string, onClick: () => void) {
    Button(label)
      .fontSize(this.fs(12))
      .height(40)
      .layoutWeight(1)
      .backgroundColor($r('app.color.bg_card'))
      .fontColor($r('app.color.text_primary'))
      .borderRadius(10)
      .onClick(onClick)
  }
}
