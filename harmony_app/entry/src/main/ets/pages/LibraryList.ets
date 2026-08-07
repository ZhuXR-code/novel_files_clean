import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { CustomDialogController } from '@kit.ArkUI';
import { ScanRun } from '../model/ScanRun';
import { ScanRunDao } from '../database/ScanRunDao';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';
import { TopBar } from '../components/TopBar';
import { AppTextInput } from '../components/AppTextInput';
import { ToastUtil } from '../utils/ToastUtil';


/**
 * 合并文库命名弹窗：悬浮在页面最上层，输入合并后文库名称。
 * 使用 CustomDialog 避免原先 if(showMerge) 内嵌 Column 在部分机型/场景下
 * 被列表或 Tab 栏遮挡、点击穿透关闭的问题。
 */
@CustomDialog
struct MergeNameDialog {
  @State mergeInput: string = '合并文库';
  controller: CustomDialogController;
  onConfirm?: (name: string) => void;
  onCancel?: () => void;
  private fs(base: number): number {
    return Math.round(base * (AppStorage.get<number>('fontScale') ?? 1.0));
  }

  build() {
    Column({ space: 12 }) {
      Text('合并文库')
        .fontSize(this.fs(16))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(`将把选中的多个文库合并为一个新文库`)
        .fontSize(this.fs(12))
        .fontColor($r('app.color.text_secondary'))
      AppTextInput({
        placeholder: '请输入合并后的文库名称',
        text: '',
        onChangeCallback: (v: string) => {
          this.mergeInput = v;
        }
      })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor($r('app.color.bg_card'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            if (this.onCancel) {
              this.onCancel();
            }
            this.controller.close();
          })
        Button('合并')
          .layoutWeight(1)
          .backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.text_on_primary'))
          .onClick(() => {
            const name: string = this.mergeInput.trim();
            if (name.length === 0) {
              ToastUtil.show('请输入文库名称');
              return;
            }
            this.controller.close();
            if (this.onConfirm) {
              this.onConfirm(name);
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(12)
    .margin({ left: 24, right: 24 })
  }
}

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
  @State renamingRun: ScanRun | null = null;
  @State showRename: boolean = false;
  @State renameInput: string = '';
  // 合并弹窗改用 CustomDialogController，确保悬浮在最前且不被列表/Tab 遮挡
  private mergeDialogController: CustomDialogController | null = null;
  @StorageProp('fontScale') fontScaleNum: number = 1.0;
  // 全局刷新信号：扫描/导入完成或切到本 Tab 时由 MainTabs/ScanProgress 推送，触发重载
  @StorageLink('libraryRefreshTick') @Watch('onRefreshTick') refreshTick: number = 0;

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  private fs(base: number): number {
    return Math.round(base * this.fontScaleNum);
  }

  // 全局刷新信号变化（切 Tab / 扫描完成）时重新加载文库列表
  private onRefreshTick(): void {
    this.load();
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

  /** 从 folderUri 拆出可读路径片段（取末尾两段，URL 解码），用于区分同名文库。 */
  private pathHint(run: ScanRun): string {
    const uri: string = run.folderUri ?? '';
    if (!uri || uri.trim().length === 0) {
      return '';
    }
    let path: string = uri.replace(/^file:\/\//i, '').replace(/^content:\/\//i, '');
    path = path.replace(/[\/\\]+$/, '');
    const segments: string[] = path.split(/[\/\\]/).filter((s: string) => s.length > 0);
    if (segments.length === 0) {
      return '';
    }
    return segments
      .slice(-2)
      .map((s: string) => {
        try {
          return decodeURIComponent(s);
        } catch (e) {
          return s;
        }
      })
      .join('/');
  }

  private openRename(run: ScanRun): void {
    this.renamingRun = run;
    this.renameInput = run.name || '';
    this.showRename = true;
  }

  private async doRename(): Promise<void> {
    const run = this.renamingRun;
    const name = this.renameInput.trim();
    this.showRename = false;
    if (!run || name.length === 0) {
      return;
    }
    try {
      await ScanRunDao.rename(run.id, name);
      await this.load();
      ToastUtil.show('已重命名');
    } catch (e) {
      LogUtil.e('LibraryTab', `重命名失败: ${(e as Error).message}`);
      ToastUtil.show('重命名失败');
    }
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

  private async mergeSelected(): Promise<void> {
    if (this.selectedIds.length < 2) {
      ToastUtil.show('请至少选择 2 个文库');
      return;
    }
    // 使用 CustomDialog 弹出命名浮层，比 if(showMerge) 内嵌 overlay 更稳定，
    // 不会被列表、删除栏或 TabBar 遮挡。
    this.mergeDialogController = new CustomDialogController({
      builder: MergeNameDialog({
        onConfirm: (name: string) => {
          this.doMerge(name);
        },
        onCancel: () => {
          this.mergeDialogController = null;
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true,
      offset: { dx: 0, dy: -24 }
    });
    this.mergeDialogController.open();
  }

  private async doMerge(name: string): Promise<void> {
    const ids = [...this.selectedIds];
    const trimmedName = name.trim();
    this.mergeDialogController = null;
    if (ids.length < 2 || trimmedName.length === 0) {
      return;
    }
    try {
      const newId: number = await ScanRunDao.mergeRuns(ids, trimmedName);
      if (newId > 0) {
        LogUtil.operation('合并文库', `源文库ID=[${ids.join(',')}] 新文库ID=${newId}`);
        this.exitSelectMode();
        await this.load();
        ToastUtil.show(`已合并为「${trimmedName}」`);
        this.openRun(newId);
      } else {
        ToastUtil.show('合并失败');
      }
    } catch (e) {
      LogUtil.e('LibraryTab', `合并文库失败: ${(e as Error).message}`);
      ToastUtil.show('合并失败');
    }
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
    Checkbox({ name: 'lib_' + run.id.toString() })
      .select(this.isSelected(run.id))
      .width(this.fs(20))
      .height(this.fs(20))
      .selectedColor($r('app.color.primary'))
      .unselectedColor($r('app.color.text_hint'))
      .mark({
        strokeColor: $r('app.color.text_on_primary'),
        size: this.fs(12),
        strokeWidth: 2
      })
      .margin({ right: 12 })
      .onChange((checked: boolean) => {
        // 受控：仅当实际勾选状态与本地 selectedIds 不一致时才同步，
        // 避免外部（如全选）批量赋值 selectedIds 触发 onChange 时再次反转状态。
        const selected: boolean = this.isSelected(run.id);
        if (checked !== selected) {
          this.toggleSelect(run.id);
        }
      })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 主体用 Column：顶栏在顶、列表自然铺满剩余区域。
      // 注意：Stack 子组件的 .layoutWeight(1) 无效（原方案 List 不会撑满且会被 TopBar 覆盖），
      // 因此把顶栏 + 内容放进一个 Column，让 layoutWeight(1) 在 List 上正确生效。
      Column() {
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
            if (this.selectedIds.length >= 2) {
              Text('合并')
                .fontSize(this.fs(15))
                .fontColor($r('app.color.primary'))
                .padding({ right: 16, top: 14, bottom: 14 })
                .onClick(() => this.mergeSelected())
            }
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
          .width('100%')
          .padding({ top: 80 })
          .alignItems(HorizontalAlign.Center)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            List({ space: 8 }) {
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
                        // 小字路径差异：同名目录/同名文库时辅助区分来源
                        Text(`路径: ${this.pathHint(run)}`)
                          .fontSize(this.fs(10))
                          .fontColor($r('app.color.text_hint'))
                          .opacity(0.8)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      if (!this.selectMode) {
                        Column({ space: 2 }) {
                          Text(`#${run.id}`)
                            .fontSize(this.fs(11))
                            .fontColor($r('app.color.text_hint'))
                          Text(' >')
                            .fontSize(this.fs(16))
                            .fontColor($r('app.color.text_hint'))
                        }
                        .alignItems(HorizontalAlign.End)
                      }
                    }
                    .width('100%')
                    .padding(14)
                    .backgroundColor($r('app.color.bg_card'))
                    .borderRadius(10)
                    .onClick(() => {
                      // 多选模式下由 Checkbox 自身响应切换，避免与 Row 点击重复触发
                      if (!this.selectMode) {
                        this.openRun(run.id);
                      }
                    })
                    .gesture(
                      LongPressGesture({ repeat: false })
                        .onAction(() => {
                          if (!this.selectMode) {
                            this.openRename(run);
                          }
                        })
                    )
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
          .padding({ top: 4 })
        }
        .onRefreshing(() => {
          this.load().then(() => {
            this.refreshing = false;
          });
        })
      } // 闭合 else(runs.length===0)

      // 多选模式删除栏：紧跟列表下方，自然排在 Tab 栏上方
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
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.bg_card'))
        .border({ width: { top: 1 }, color: $r('app.color.divider') })
      }

      // 重命名弹窗（长按文库条目触发）
      if (this.showRename) {
        Column() {
          Column({ space: 12 }) {
            Text('重命名文库')
              .fontSize(this.fs(15))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            AppTextInput({ placeholder: '请输入文库名称', text: this.renameInput, onChangeCallback: (v: string) => {
              this.renameInput = v;
            } })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor($r('app.color.bg_card'))
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.showRename = false;
                })
              Button('保存')
                .layoutWeight(1)
                .backgroundColor($r('app.color.primary'))
                .fontColor($r('app.color.text_on_primary'))
                .onClick(() => this.doRename())
            }
          }
          .padding(20)
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(12)
          .margin({ left: 24, right: 24 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showRename = false;
        })
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
  } // 闭合 build()
}
