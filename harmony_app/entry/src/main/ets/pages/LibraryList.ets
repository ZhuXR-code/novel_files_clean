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
 * 支持多选模式批量删除（仅删除数据库记录，不删除源文件）。
 */
@Component
export struct LibraryTab {
  @State runs: ScanRun[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State selectMode: boolean = false;
  @State selectedIds: number[] = [];
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

  // ===== 多选相关 =====
  private enterSelectMode(): void {
    this.selectMode = true;
    this.selectedIds = [];
  }

  private exitSelectMode(): void {
    this.selectMode = false;
    this.selectedIds = [];
  }

  private toggleSelect(runId: number): void {
    const idx = this.selectedIds.indexOf(runId);
    if (idx >= 0) {
      this.selectedIds.splice(idx, 1);
    } else {
      this.selectedIds.push(runId);
    }
  }

  private isSelected(runId: number): boolean {
    return this.selectedIds.indexOf(runId) >= 0;
  }

  private toggleSelectAll(): void {
    if (this.selectedIds.length === this.runs.length) {
      this.selectedIds = [];
    } else {
      this.selectedIds = this.runs.map((r) => r.id);
    }
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

  private async deleteSelected(): Promise<void> {
    if (this.selectedIds.length === 0) {
      return;
    }
    const ids = [...this.selectedIds];
    promptAction.showDialog({
      title: '删除文库',
      message: `确认删除选中的 ${ids.length} 个文库及其全部文件记录？仅删除数据库中的数据，不会删除源文件。`,
      buttons: [
        { text: '取消', color: $r('app.color.text_hint') },
        { text: '删除', color: $r('app.color.danger') }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        try {
          for (const id of ids) {
            await ScannedFileDao.deleteByScanRun(id);
            await ScanRunDao.delete(id);
          }
          LogUtil.operation('批量删除文库', `文库ID=[${ids.join(',')}]`);
          this.exitSelectMode();
          await this.load();
          ToastUtil.show(`已删除 ${ids.length} 个文库`);
        } catch (e) {
          LogUtil.e('LibraryTab', `批量删除文库失败: ${(e as Error).message}`);
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

  @Builder
  checkBox(run: ScanRun) {
    Stack({ alignContent: Alignment.Center }) {
      Circle({ width: this.fs(22), height: this.fs(22) })
        .fill(this.isSelected(run.id) ? $r('app.color.primary') : Color.Transparent)
        .stroke(this.isSelected(run.id) ? $r('app.color.primary') : $r('app.color.text_hint'))
        .strokeWidth(2)
      if (this.isSelected(run.id)) {
        Path()
          .width(this.fs(12))
          .height(this.fs(12))
          .commands('M4 7 L9 12 L16 4')
          .stroke($r('app.color.text_on_primary'))
          .strokeWidth(2)
          .fill(Color.Transparent)
          .antiAlias(true)
      }
    }
    .width(this.fs(24))
    .height(this.fs(24))
    .margin({ right: 12 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 主体用 Column：顶栏在顶、列表自然铺满剩余区域。
      // 注意：Stack 子组件的 .layoutWeight(1) 无效（原方案 List 不会撑满且会被 TopBar 覆盖），
      // 因此把顶栏 + 内容放进一个 Column，让 layoutWeight(1) 在 List 上正确生效。
      Column() {
        .width('100%')
        .height('100%')
        if (this.selectMode) {
          // 多选模式顶部栏
          Row() {
            Text('取消')
              .fontSize(this.fs(15))
              .fontColor($r('app.color.primary'))
              .padding({ left: 12, top: 14, bottom: 14 })
              .onClick(() => this.exitSelectMode())
            Text('已选 ' + this.selectedIds.length + ' 个')
              .fontSize(this.fs(15))
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Text(this.selectedIds.length === this.runs.length ? '取消全选' : '全选')
              .fontSize(this.fs(15))
              .fontColor($r('app.color.primary'))
              .padding({ right: 12, top: 14, bottom: 14 })
              .onClick(() => this.toggleSelectAll())
          }
          .width('100%')
          .backgroundColor($r('app.color.bg_card'))
          .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
        } else {
          TopBar({
            title: '文库',
            showBack: false,
            rightText: '选择',
            onRight: () => this.enterSelectMode()
          })
        }

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
                      if (this.selectMode) {
                        this.checkBox(run)
                      }
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

                      if (!this.selectMode) {
                        Text(' >')
                          .fontSize(this.fs(16))
                          .fontColor($r('app.color.text_hint'))
                      }
                    }
                    .width('100%')
                    .padding(16)
                    .backgroundColor($r('app.color.bg_card'))
                    .borderRadius(10)
                    .onClick(() => {
                      if (this.selectMode) {
                        this.toggleSelect(run.id);
                      } else {
                        this.openRun(run.id);
                      }
                    })
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
          .onRefreshing(() => {
            this.load().then(() => {
              this.refreshing = false;
            });
          })
        } // 闭合 else(runs.length===0)
      } // 闭合 Column(主体)

      // 多选模式删除栏：固定在距页面顶部 20% 处（不再贴底）
      if (this.selectMode && this.selectedIds.length > 0) {
        Row() {
          Button('删除选中 (' + this.selectedIds.length + ')')
            .width('100%')
            .height(44)
            .backgroundColor($r('app.color.danger'))
            .fontColor($r('app.color.text_on_primary'))
            .enabled(this.selectedIds.length > 0)
            .onClick(() => this.deleteSelected())
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.bg_card'))
        .position({ x: 0, y: '20%' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
