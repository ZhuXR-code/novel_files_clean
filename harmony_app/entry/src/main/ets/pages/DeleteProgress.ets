import { router } from '@kit.ArkUI';
import { DeleteService } from '../service/DeleteService';
import { LogUtil } from '../utils/LogUtil';
import { TopBar } from '../components/TopBar';
import { ToastUtil } from '../utils/ToastUtil';

interface DeleteLog {
  name: string;
  ok: boolean;
  error: string;
}

/**
 * 删除进度页：进度条 + 实时滚动删除日志（✓ 绿 / ✗ 红）+ 完成结果摘要。
 * 对齐安卓端「删除进度页」。
 */
@Entry
@Component
struct DeleteProgress {
  /** 日志环形缓冲上限：仅保留最近 N 条，避免 10w 次删除导致 O(n²) 拷贝与 ForEach 渲染 OOM。 */
  private static readonly LOG_MAX: number = 300;
  /** 滚动到底部的节流间隔（每 N 个文件才滚动一次），避免高频 UI 调用卡顿。 */
  private static readonly SCROLL_INTERVAL: number = 20;

  @State runId: number = 0;
  @State ids: number[] = [];
  @State deleting: boolean = false;
  @State done: boolean = false;
  @State deleted: number = 0;
  @State failed: number = 0;
  @State pDone: number = 0;
  @State pTotal: number = 0;
  @State currentFile: string = '';
  @State deleteSource: boolean = true;
  @State logs: DeleteLog[] = [];
  private logScroller: Scroller = new Scroller();
  private logCountSinceScroll: number = 0;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['runId'] !== undefined && params['runId'] !== null) {
      this.runId = params['runId'] as number;
    }
    if (params && params['ids'] !== undefined && params['ids'] !== null) {
      this.ids = params['ids'] as number[];
    }
    if (params && params['deleteSource'] !== undefined && params['deleteSource'] !== null) {
      this.deleteSource = params['deleteSource'] as boolean;
    }
    this.pTotal = this.ids.length;
    // E组 #16 自动开始删除：进入页面即开始，无需手动点击
    if (this.ids.length > 0) {
      await this.startDelete();
    }
  }

  // 系统返回键拦截：删除进行中时阻止
  onBackPress(): boolean {
    if (this.deleting) {
      ToastUtil.show('删除进行中，请等待完成');
      return true;
    }
    return false;
  }

  private async startDelete(): Promise<void> {
    if (this.deleting || this.done) {
      return;
    }
    this.deleting = true;
    this.logs = [];
    try {
      const res = await DeleteService.deleteByIds(this.ids, {
        deleteSource: this.deleteSource,
        onProgress: (d: number, total: number, success: number, failed: number, c: string) => {
          this.pDone = d;
          this.pTotal = total;
          this.deleted = success;
          this.failed = failed;
          this.currentFile = c;
        },
        onFileDone: (info) => {
          // 环形缓冲：超过上限丢弃最旧条目，保证数组长度 ≤ LOG_MAX，
          // 避免 10w 次删除时 [...this.logs] 每次 O(n) 拷贝累计成 O(n²) 卡死。
          const next: DeleteLog = { name: info.name, ok: info.ok, error: info.error ?? '' };
          if (this.logs.length >= DeleteProgress.LOG_MAX) {
            this.logs = [...this.logs.slice(1), next];
          } else {
            this.logs = [...this.logs, next];
          }
          // 滚动节流：每 SCROLL_INTERVAL 个文件才滚一次，降低高频 UI 调用。
          this.logCountSinceScroll++;
          if (this.logCountSinceScroll >= DeleteProgress.SCROLL_INTERVAL) {
            this.logCountSinceScroll = 0;
            this.logScroller.scrollEdge(Edge.Bottom);
          }
        }
      });
      this.deleted = res.deleted;
      this.failed = res.failed;
      this.done = true;
      // 删除结束后滚动到底部，展示最后一批日志。
      this.logScroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      LogUtil.e('DeleteProgress', `删除失败: ${(e as Error).message}`);
      ToastUtil.show('删除异常');
    }
    this.deleting = false;
  }

  private finish(): void {
    router.replaceUrl({ url: 'pages/LibraryScreen', params: { runId: this.runId } }).catch((err: Error) => {
      LogUtil.e('DeleteProgress', `跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      TopBar({ title: this.done ? '删除完成' : '删除中' })

      Column({ space: 12 }) {
        if (this.deleting) {
          Text('正在删除…')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
          Text(`进度: ${this.pDone} / ${this.pTotal}   成功 ${this.deleted}   失败 ${this.failed}`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Progress({ value: this.pDone, total: this.pTotal, type: ProgressType.Linear })
            .width('100%')
            .color($r('app.color.primary'))
          Text(`当前: ${this.currentFile}`)
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        } else if (this.done) {
          Text('删除完成')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.failed > 0 ? $r('app.color.warning') : $r('app.color.success'))
          Text(`成功 ${this.deleted}   失败 ${this.failed}`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          if (this.failed > 0) {
            Text('失败多为 Picker 授权失效，可在原目录重新授权后重试')
              .fontSize(12)
              .fontColor($r('app.color.text_hint'))
              .padding({ left: 16, right: 16 })
              .lineHeight(18)
          }
        } else {
          Text(`将删除 ${this.ids.length} 个文件`)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text(this.deleteSource ? '模式：删除数据库记录 + 物理源文件' : '模式：仅删除数据库记录，保留物理源文件')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .width('100%')
      .padding(16)

      // 实时滚动日志（删除中或完成时显示）
      if (this.deleting || this.done) {
        Text('删除日志')
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
          .padding({ left: 16, top: 4 })
        List({ scroller: this.logScroller, space: 2 }) {
          ForEach(
            this.logs,
            (log: DeleteLog, idx: number) => {
              ListItem() {
                Row({ space: 8 }) {
                  Text(log.ok ? '✓' : '✗')
                    .fontSize(14)
                    .fontColor(log.ok ? $r('app.color.success') : $r('app.color.danger'))
                  Text(log.name)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (!log.ok) {
                    Text('失败')
                      .fontSize(11)
                      .fontColor($r('app.color.danger'))
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 5, bottom: 5 })
              }
            },
            (log: DeleteLog, idx: number) => idx.toString()
          )
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        Blank().layoutWeight(1)
      }

      // 底部操作
      Row({ space: 12 }) {
        if (this.done) {
          Button('查看日志')
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_light'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => router.pushUrl({ url: 'pages/LogViewer' }).catch(() => {}))
          Button('返回文库')
            .layoutWeight(1)
            .backgroundColor($r('app.color.primary'))
            .fontColor($r('app.color.text_on_primary'))
            .onClick(() => this.finish())
        } else {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_light'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => router.back())
          Button('开始删除')
            .layoutWeight(1)
            .backgroundColor($r('app.color.danger'))
            .fontColor($r('app.color.text_on_primary'))
            .enabled(this.ids.length > 0 && !this.deleting)
            .onClick(() => this.startDelete())
        }
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
