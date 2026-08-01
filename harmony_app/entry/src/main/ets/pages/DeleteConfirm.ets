import { router } from '@kit.ArkUI';
import { ScannedFile } from '../model/ScannedFile';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';
import { TopBar } from '../components/TopBar';
import { ToastUtil } from '../utils/ToastUtil';

/**
 * 删除确认页（跳转页，非弹窗）。对齐安卓端强确认流程：
 * - 顶部红色永久删除提示条；
 * - 待删明细默认全部勾选，可逐条取消；
 * - 每行小字显示完整路径便于核对；
 * - 底部按钮实时显示「将删 N 个」。
 *
 * 性能模型（支持 10w+ 文件，避免 OOM）：
 * - 内存仅保留 id 数组（数字，10w≈800KB）+ 当前页完整对象（pageSize 个）；
 * - 勾选状态用「全选标志 + 排除集 / 显式集」表达，避免持有 10w 个完整 ScannedFile；
 * - 翻页时按 id 子集查库，只加载当前页的完整对象。
 */
@Entry
@Component
struct DeleteConfirm {
  @State runId: number = 0;
  /** 全部待删文件 id（仅数字，内存开销小）。 */
  @State allFileIds: number[] = [];
  /** 当前页完整文件对象（仅 pageSize 个）。 */
  @State visibleFiles: ScannedFile[] = [];
  @State pageSize: number = 50;
  @State currentPage: number = 0;
  @State totalCount: number = 0;
  @State loading: boolean = true;
  @State deleteSource: boolean = true;
  /** true=默认全选，excludedIds 记录被取消的；false=默认不选，selectedIds 记录被勾选的。 */
  @State allSelected: boolean = true;
  @State excludedIds: Set<number> = new Set<number>();
  @State selectedIds: Set<number> = new Set<number>();

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['runId'] !== undefined && params['runId'] !== null) {
      this.runId = params['runId'] as number;
    }
    let fileIds: number[] = [];
    if (params && params['fileIds'] !== undefined && params['fileIds'] !== null) {
      fileIds = params['fileIds'] as number[];
    }
    if (params && params['deleteSource'] !== undefined && params['deleteSource'] !== null) {
      this.deleteSource = params['deleteSource'] as boolean;
    }
    try {
      if (fileIds.length > 0) {
        // 上游显式传入待删 id（如文库勾选的文件），直接用。
        this.allFileIds = fileIds;
      } else {
        // 兜底：取该文库全部已勾选文件 id（仅投影 id 列，避免加载完整对象）。
        this.allFileIds = await ScannedFileDao.getCheckedIds(this.runId);
      }
      this.totalCount = this.allFileIds.length;
      this.currentPage = 0;
      this.allSelected = true;
      this.excludedIds = new Set<number>();
      this.selectedIds = new Set<number>();
      await this.loadPage(0);
    } catch (e) {
      LogUtil.e('DeleteConfirm', `加载失败: ${(e as Error).message}`);
    }
    this.loading = false;
  }

  /** 计算当前选中数。 */
  private get selectedCount(): number {
    if (this.allSelected) {
      return this.totalCount - this.excludedIds.size;
    }
    return this.selectedIds.size;
  }

  /** 加载指定页的完整文件对象（仅该页 pageSize 个 id 查库）。 */
  private async loadPage(page: number): Promise<void> {
    const start: number = page * this.pageSize;
    if (start >= this.totalCount) {
      this.visibleFiles = [];
      return;
    }
    const end: number = Math.min(start + this.pageSize, this.totalCount);
    const pageIds: number[] = this.allFileIds.slice(start, end);
    try {
      // getByIds 内部已按 500 分块，这里最多 pageSize(50) 个，安全。
      this.visibleFiles = await ScannedFileDao.getByIds(pageIds);
    } catch (e) {
      LogUtil.e('DeleteConfirm', `加载第 ${page + 1} 页失败: ${(e as Error).message}`);
      this.visibleFiles = [];
    }
  }

  /** 滚动到底部加载下一页（追加显示，最多累计一定页数后改用分页导航）。 */
  private async loadMore(): Promise<void> {
    const nextStart: number = (this.currentPage + 1) * this.pageSize;
    if (nextStart >= this.totalCount) {
      return;
    }
    this.currentPage++;
    const nextEnd: number = Math.min((this.currentPage + 1) * this.pageSize, this.totalCount);
    const pageIds: number[] = this.allFileIds.slice(this.currentPage * this.pageSize, nextEnd);
    try {
      const more: ScannedFile[] = await ScannedFileDao.getByIds(pageIds);
      // 累计可见列表控制在合理上限（避免无限增长），超过则只保留最近若干页。
      const merged: ScannedFile[] = this.visibleFiles.concat(more);
      const MAX_VISIBLE: number = Math.max(this.pageSize * 10, 500);
      this.visibleFiles = merged.length > MAX_VISIBLE ? merged.slice(merged.length - MAX_VISIBLE) : merged;
    } catch (e) {
      LogUtil.e('DeleteConfirm', `加载更多失败: ${(e as Error).message}`);
    }
  }

  /** 全选/取消全选（作用于全部文件，非仅可见）。 */
  private selectAll(on: boolean): void {
    this.allSelected = on;
    this.excludedIds = new Set<number>();
    this.selectedIds = new Set<number>();
  }

  /** 切换单个文件勾选。 */
  private toggleSelect(id: number, on: boolean): void {
    if (this.allSelected) {
      const s = new Set<number>(this.excludedIds);
      if (on) {
        s.delete(id);
      } else {
        s.add(id);
      }
      this.excludedIds = s;
    } else {
      const s = new Set<number>(this.selectedIds);
      if (on) {
        s.add(id);
      } else {
        s.delete(id);
      }
      this.selectedIds = s;
    }
  }

  /** 判断某 id 是否处于选中态。 */
  private isSelected(id: number): boolean {
    if (this.allSelected) {
      return !this.excludedIds.has(id);
    }
    return this.selectedIds.has(id);
  }

  private confirm(): void {
    if (this.selectedCount === 0) {
      ToastUtil.show('请至少选择一个文件');
      return;
    }
    let ids: number[];
    if (this.allSelected) {
      // 全选模式下：全部 id 减去排除集。
      const excluded = this.excludedIds;
      ids = this.allFileIds.filter((id) => !excluded.has(id));
    } else {
      ids = Array.from(this.selectedIds);
    }
    router.pushUrl({ url: 'pages/DeleteProgress', params: { runId: this.runId, ids: ids, deleteSource: this.deleteSource } }).catch((err: Error) => {
      LogUtil.e('DeleteConfirm', `跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      TopBar({ title: '确认删除' })

      // 顶部红色永久删除提示条
      Row() {
        Text(`将永久删除 ${this.selectedCount} 个文件，此操作不可恢复`)
          .fontSize(13)
          .fontColor($r('app.color.text_on_primary'))
          .width('100%')
          .padding(12)
      }
      .width('100%')
      .backgroundColor($r('app.color.danger'))

      // 删除源文件开关
      Row() {
        Column({ space: 2 }) {
          Text('删除源文件')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Text(this.deleteSource ? '同时删除物理文件与数据库记录' : '仅删除数据库记录，保留物理文件')
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.deleteSource })
          .onChange((isOn: boolean) => {
            this.deleteSource = isOn;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.bg_card'))

      if (this.totalCount === 0) {
        Text('没有可删除的文件')
          .fontSize(15)
          .fontColor($r('app.color.text_hint'))
          .margin({ top: 40 })
      } else {
        // 顶部操作栏：全选/取消 + 加载进度
        Row({ space: 12 }) {
          Text(`共 ${this.totalCount} 个，已加载 ${this.visibleFiles.length} 个`)
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
            .layoutWeight(1)
          Button(this.selectedCount === this.totalCount ? '取消全选' : '全选')
            .fontSize(12)
            .height(30)
            .backgroundColor($r('app.color.bg_light'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => this.selectAll(this.selectedCount !== this.totalCount))
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })

        List({ space: 6 }) {
          ForEach(
            this.visibleFiles,
            (file: ScannedFile) => {
              ListItem() {
                Row({ space: 10 }) {
                  Toggle({ type: ToggleType.Checkbox, isOn: this.isSelected(file.id) })
                    .onChange((v: boolean) => this.toggleSelect(file.id, v))
                  Column({ space: 3 }) {
                    Text(file.title || file.fileName)
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(file.path)
                      .fontSize(10)
                      .fontColor($r('app.color.text_hint'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .copyOption(CopyOptions.InApp)
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
              .padding({ left: 12, right: 12 })
            },
            (file: ScannedFile) => file.id.toString()
          )
          // 滚动到底部加载更多提示
          if (this.visibleFiles.length < this.totalCount) {
            ListItem() {
              Row() {
                Text('上拉加载更多…')
                  .fontSize(12)
                  .fontColor($r('app.color.text_hint'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding(12)
            }
          }
        }
        .layoutWeight(1)
        .width('100%')
        .onReachEnd(() => this.loadMore())
      }

      // 底部按钮
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor($r('app.color.bg_light'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => router.back())
        Button(`将删 ${this.selectedCount} 个`)
          .layoutWeight(1)
          .backgroundColor($r('app.color.danger'))
          .fontColor($r('app.color.text_on_primary'))
          .enabled(this.selectedCount > 0)
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
