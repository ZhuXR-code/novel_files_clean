import { router } from '@kit.ArkUI';
import { ScanConfig } from '../model/ScanConfig';
import { ScannedFile } from '../model/ScannedFile';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { DupLogic } from '../utils/DupLogic';
import { DeleteService } from '../service/DeleteService';
import { ScanService, ScanProgress as ScanProgressData } from '../service/ScanService';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';
import { AppContext } from '../utils/AppContext';
import { TopBar } from '../components/TopBar';
import { ToastUtil } from '../utils/ToastUtil';

/** 流水线节点状态（对齐 PC 端 pipeline.py 的节点状态） */
type NodeStatus = 'pending' | 'running' | 'done' | 'error';

/** 流水线节点（对齐 PC 端 NODE_DEFS） */
interface PipelineNode {
  key: string;
  name: string;
  status: NodeStatus;
}

/** 页面阶段 */
type Phase = 'idle' | 'scanning' | 'marking' | 'confirm' | 'review' | 'deleting' | 'done' | 'error';

/**
 * 一键清理页（对齐 PC 端 pipeline.py 和安卓端 OneClickCleanupViewModel）。
 *
 * 完整自动化流程（用户只需配置目录，后续全自动）：
 *   1. scan   扫描目录（含解析 parse + 合集 group，在扫描中自动完成）
 *   2. mark   勾选重复（五则规则）
 *   3. clean  清理删除（需用户二次确认）
 *
 * 对齐要点：
 *  - PC端：scan→parse→group→mark→clean 五节点串行，clean 需二次确认
 *  - 安卓端：idle→scanning→marking→confirm→review→deleting→done
 *  - 鸿蒙端：用户选目录后自动扫描→自动标记重复→二次确认→删除
 */
@Entry
@Component
struct OneClickCleanup {
  // === 配置 ===
  @State folderUri: string = '';
  @State folderName: string = '';
  @State fileTypes: string = 'txt';

  // === 流程状态 ===
  @State phase: Phase = 'idle';
  @State errorMsg: string = '';

  // === 流水线节点（对齐 PC 端 5 节点） ===
  @State nodes: PipelineNode[] = [
    { key: 'scan', name: '扫描', status: 'pending' },
    { key: 'parse', name: '工程文件名解析', status: 'pending' },
    { key: 'group', name: '生成合集', status: 'pending' },
    { key: 'mark', name: '勾选重复', status: 'pending' },
    { key: 'clean', name: '清理删除', status: 'pending' }
  ];

  // === 扫描进度 ===
  @State scanProcessed: number = 0;
  @State scanFound: number = 0;
  @State scanCurrent: string = '';

  // === 重复标记 ===
  @State runId: number = 0;
  @State dupCount: number = 0;
  /** 全部重复文件 id（仅数字，10w≈800KB，避免持有 10w 完整对象）。 */
  @State reviewIds: number[] = [];
  /** 复核清单当前页完整对象（仅 pageSize 个）。 */
  @State reviewVisible: ScannedFile[] = [];
  @State reviewPageSize: number = 50;
  @State reviewPage: number = 0;
  /** true=默认全删，excludedIds 记录要保留的；false=默认不删，draftIds 记录要删的。 */
  @State reviewAllSelected: boolean = true;
  @State excludedIds: Set<number> = new Set<number>();
  @State draftIds: Set<number> = new Set<number>();

  // === 删除进度 ===
  @State delDone: number = 0;
  @State delTotal: number = 0;
  @State delSuccess: number = 0;
  @State delFailed: number = 0;
  @State currentFile: string = '';

  /** 更新流水线节点状态（创建新数组以触发 UI 更新） */
  private setNodeStatus(idx: number, status: NodeStatus): void {
    const arr: PipelineNode[] = this.nodes.map((n: PipelineNode): PipelineNode => {
      const p: PipelineNode = { key: n.key, name: n.name, status: n.status };
      return p;
    });
    arr[idx].status = status;
    this.nodes = arr;
  }

  /** 重置流水线 */
  private resetNodes(): void {
    this.nodes = [
      { key: 'scan', name: '扫描', status: 'pending' },
      { key: 'parse', name: '工程文件名解析', status: 'pending' },
      { key: 'group', name: '生成合集', status: 'pending' },
      { key: 'mark', name: '勾选重复', status: 'pending' },
      { key: 'clean', name: '清理删除', status: 'pending' }
    ];
  }

  // 选择扫描目录（复用 ScanService，支持 FOLDER 模式 + 自动降级）
  private async selectDir(): Promise<void> {
    const ctx = AppContext.get();
    if (!ctx) {
      return;
    }
    try {
      const uri = await ScanService.selectDirectory(ctx, this.folderUri);
      if (uri.length === 0) {
        return; // 用户取消
      }
      this.folderUri = uri;
      this.folderName = FormatUtil.formatFolderDisplay(uri);
    } catch (e) {
      LogUtil.e('OneClickCleanup', `选择目录失败: ${(e as Error).message}`);
      ToastUtil.show(`选择失败: ${(e as Error).message}`);
    }
  }

  /**
   * 开始一键清理：自动 扫描 → 解析 → 合集 → 标记重复 → 确认
   * 对齐 PC 端 pipeline._run() 的节点1-4。
   */
  private async startCleanup(): Promise<void> {
    if (this.folderUri.length === 0) {
      ToastUtil.show('请先选择扫描目录');
      return;
    }

    // 重置状态
    this.errorMsg = '';
    this.scanProcessed = 0;
    this.scanFound = 0;
    this.scanCurrent = '';
    this.dupCount = 0;
    this.resetNodes();
    LogUtil.operation('一键清理-启动', `目录=${this.folderName}`);

    // === 节点1：扫描（含解析 parse + 合集 group，在扫描中自动完成） ===
    this.phase = 'scanning';
    this.setNodeStatus(0, 'running');

    const cfg: ScanConfig = new ScanConfig();
    cfg.folderUri = this.folderUri;
    cfg.folderName = this.folderName;
    cfg.name = `${this.folderName}·一键清理`;
    cfg.fileTypes = this.fileTypes.trim().length === 0 ? 'txt' : this.fileTypes.trim();
    cfg.minSizeKb = 0;
    cfg.recursive = true;
    cfg.exactHash = false;
    cfg.excludedFolders = '';

    try {
      const res = await ScanService.runScan(cfg, (p: ScanProgressData) => {
        this.scanProcessed = p.processed;
        this.scanFound = p.found;
        this.scanCurrent = p.currentFile;
      });
      this.runId = res.runId;
      this.setNodeStatus(0, 'done');
      // 解析和合集在扫描中自动完成（Parser.parseFileName + titlePinyin 已在 runScan 中处理）
      this.setNodeStatus(1, 'done');
      this.setNodeStatus(2, 'done');
      LogUtil.operation('一键清理-扫描完成', `命中=${res.total}`);
    } catch (e) {
      LogUtil.e('OneClickCleanup', `扫描失败: ${(e as Error).message}`);
      this.errorMsg = `扫描失败: ${(e as Error).message}`;
      this.setNodeStatus(0, 'error');
      this.phase = 'error';
      return;
    }

    // === 节点4：勾选重复（五则规则） ===
    this.phase = 'marking';
    this.setNodeStatus(3, 'running');
    try {
      const ids: number[] = await DupLogic.selectDuplicateIds(this.runId);
      this.dupCount = ids.length;
      // 仅存 id（数字数组），不加载完整对象，避免 10w+ ScannedFile 占满内存。
      this.reviewIds = ids;
      this.reviewPage = 0;
      this.reviewVisible = [];
      this.reviewAllSelected = true;
      this.excludedIds = new Set<number>();
      this.draftIds = new Set<number>();
      this.setNodeStatus(3, 'done');
      LogUtil.operation('一键清理-标记完成', `待删除=${ids.length}`);
    } catch (e) {
      LogUtil.e('OneClickCleanup', `标记失败: ${(e as Error).message}`);
      this.errorMsg = `标记失败: ${(e as Error).message}`;
      this.setNodeStatus(3, 'error');
      this.phase = 'error';
      return;
    }

    // === 进入二次确认阶段（对齐 PC 端 awaiting_confirm） ===
    if (this.dupCount === 0) {
      this.phase = 'done';
    } else {
      this.phase = 'confirm';
    }
  }

  // 打开复核清单：进入时加载第一页完整对象
  private async openReview(): Promise<void> {
    this.phase = 'review';
    this.reviewPage = 0;
    this.reviewVisible = [];
    await this.loadReviewPage(0);
  }

  /** 加载复核清单指定页的完整对象（仅该页 pageSize 个 id 查库）。 */
  private async loadReviewPage(page: number): Promise<void> {
    const start: number = page * this.reviewPageSize;
    if (start >= this.reviewIds.length) {
      this.reviewVisible = [];
      return;
    }
    const end: number = Math.min(start + this.reviewPageSize, this.reviewIds.length);
    const pageIds: number[] = this.reviewIds.slice(start, end);
    try {
      this.reviewVisible = await ScannedFileDao.getByIds(pageIds);
    } catch (e) {
      LogUtil.e('OneClickCleanup', `加载复核页失败: ${(e as Error).message}`);
      this.reviewVisible = [];
    }
  }

  /** 复核清单滚动加载更多（累计显示，超过上限则只保留最近若干页）。 */
  private async loadReviewMore(): Promise<void> {
    const nextStart: number = (this.reviewPage + 1) * this.reviewPageSize;
    if (nextStart >= this.reviewIds.length) {
      return;
    }
    this.reviewPage++;
    const nextEnd: number = Math.min((this.reviewPage + 1) * this.reviewPageSize, this.reviewIds.length);
    const pageIds: number[] = this.reviewIds.slice(this.reviewPage * this.reviewPageSize, nextEnd);
    try {
      const more: ScannedFile[] = await ScannedFileDao.getByIds(pageIds);
      const merged: ScannedFile[] = this.reviewVisible.concat(more);
      const MAX_VISIBLE: number = Math.max(this.reviewPageSize * 10, 500);
      this.reviewVisible = merged.length > MAX_VISIBLE ? merged.slice(merged.length - MAX_VISIBLE) : merged;
    } catch (e) {
      LogUtil.e('OneClickCleanup', `加载更多失败: ${(e as Error).message}`);
    }
  }

  /** 当前选中（待删除）数量。 */
  private get reviewSelectedCount(): number {
    if (this.reviewAllSelected) {
      return this.reviewIds.length - this.excludedIds.size;
    }
    return this.draftIds.size;
  }

  /** 判断某 id 是否处于选中（待删除）态。 */
  private isReviewSelected(id: number): boolean {
    if (this.reviewAllSelected) {
      return !this.excludedIds.has(id);
    }
    return this.draftIds.has(id);
  }

  // 切换草稿勾选
  private toggleDraft(id: number): void {
    if (this.reviewAllSelected) {
      const s = new Set<number>(this.excludedIds);
      if (s.has(id)) {
        s.delete(id);
      } else {
        s.add(id);
      }
      this.excludedIds = s;
    } else {
      const s = new Set<number>(this.draftIds);
      if (s.has(id)) {
        s.delete(id);
      } else {
        s.add(id);
      }
      this.draftIds = s;
    }
  }

  // 全选（全删）
  private draftAll(): void {
    this.reviewAllSelected = true;
    this.excludedIds = new Set<number>();
    this.draftIds = new Set<number>();
  }

  // 全不选（都不删）
  private draftNone(): void {
    this.reviewAllSelected = false;
    this.excludedIds = new Set<number>();
    this.draftIds = new Set<number>();
  }

  // 保存复核结果，回到确认
  private saveReview(): void {
    this.dupCount = this.reviewSelectedCount;
    this.phase = 'confirm';
  }

  /**
   * 确认删除：执行节点5 - 清理删除
   * 对齐 PC 端 pipeline 的 clean 节点（用户二次确认后执行）。
   */
  private async confirmDelete(): Promise<void> {
    let ids: number[];
    if (this.reviewAllSelected) {
      const excluded = this.excludedIds;
      ids = this.reviewIds.filter((id) => !excluded.has(id));
    } else {
      ids = Array.from(this.draftIds);
    }
    if (ids.length === 0) {
      ToastUtil.show('没有可删除的文件');
      return;
    }

    this.delTotal = ids.length;
    this.delDone = 0;
    this.delSuccess = 0;
    this.delFailed = 0;
    this.currentFile = '';
    this.phase = 'deleting';
    this.setNodeStatus(4, 'running');

    try {
      const res = await DeleteService.deleteByIds(ids, {
        deleteSource: true,
        onProgress: (done: number, total: number, success: number, failed: number, current: string) => {
          this.delDone = done;
          this.delTotal = total;
          this.delSuccess = success;
          this.delFailed = failed;
          this.currentFile = current;
        }
      });
      this.delSuccess = res.deleted;
      this.delFailed = res.failed;
      this.setNodeStatus(4, 'done');
      this.phase = 'done';
      LogUtil.operation('一键清理-删除完成', `成功=${res.deleted} 失败=${res.failed}`);
    } catch (e) {
      LogUtil.e('OneClickCleanup', `删除失败: ${(e as Error).message}`);
      this.errorMsg = `删除失败: ${(e as Error).message}`;
      this.setNodeStatus(4, 'error');
      this.phase = 'error';
    }
  }

  onBackPress(): boolean {
    if (this.phase === 'review') {
      this.phase = 'confirm';
      return true;
    }
    if (this.phase === 'deleting' || this.phase === 'scanning' || this.phase === 'marking') {
      ToastUtil.show('处理中，请稍候');
      return true;
    }
    return false;
  }

  build() {
    Column() {
      TopBar({ title: '一键清理', showBack: true })

      Scroll() {
        Column({ space: 12 }) {
          // 流水线节点进度（非 idle 阶段显示，对齐 PC 端节点展示）
          if (this.phase !== 'idle') {
            this.pipelineCard()
          }

          if (this.phase === 'idle') {
            this.idleContent()
          } else if (this.phase === 'scanning') {
            this.scanningContent()
          } else if (this.phase === 'marking') {
            this.markingContent()
          } else if (this.phase === 'confirm') {
            this.confirmContent()
          } else if (this.phase === 'review') {
            this.reviewContent()
          } else if (this.phase === 'deleting') {
            this.deletingContent()
          } else if (this.phase === 'done') {
            this.doneContent()
          } else if (this.phase === 'error') {
            this.errorContent()
          }
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  // 流水线节点进度卡片（对齐 PC 端 pipeline 的 5 节点展示）
  @Builder
  pipelineCard() {
    Column({ space: 4 }) {
      ForEach(
        this.nodes,
        (node: PipelineNode, idx: number) => {
          Row({ space: 10 }) {
            // 节点状态图标
            if (node.status === 'done') {
              Text('✓')
                .fontSize(16)
                .fontColor($r('app.color.success'))
                .width(20)
                .textAlign(TextAlign.Center)
            } else if (node.status === 'running') {
              LoadingProgress()
                .width(16)
                .height(16)
            } else if (node.status === 'error') {
              Text('✗')
                .fontSize(16)
                .fontColor($r('app.color.danger'))
                .width(20)
                .textAlign(TextAlign.Center)
            } else {
              Text(`${idx + 1}`)
                .fontSize(13)
                .fontColor($r('app.color.text_hint'))
                .width(20)
                .textAlign(TextAlign.Center)
            }
            // 节点名称
            Text(node.name)
              .fontSize(14)
              .fontColor(node.status === 'done' ? $r('app.color.text_primary') :
                node.status === 'running' ? $r('app.color.primary') :
                node.status === 'error' ? $r('app.color.danger') : $r('app.color.text_secondary'))
              .layoutWeight(1)
            // 节点状态文字
            Text(node.status === 'done' ? '完成' :
              node.status === 'running' ? '进行中' :
              node.status === 'error' ? '失败' : '待执行')
              .fontSize(12)
              .fontColor(node.status === 'done' ? $r('app.color.success') :
                node.status === 'running' ? $r('app.color.primary') :
                node.status === 'error' ? $r('app.color.danger') : $r('app.color.text_hint'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        },
        (node: PipelineNode, idx: number) => `${idx}-${node.status}`
      )
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
  }

  // 配置阶段：用户选目录 + 文件类型
  @Builder
  idleContent() {
    Column({ space: 14 }) {
      Text('一键清理')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
      Text('选择目标文件夹后点击「开始」，系统将自动完成扫描 → 解析 → 合集 → 标记重复，然后等待您确认删除。')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(18)

      // 目录选择
      Column({ space: 6 }) {
        Text('扫描目录').fontSize(14).fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
        Row() {
          Text(this.folderName || '(未选择)')
            .fontSize(14)
            .fontColor(this.folderName ? $r('app.color.text_primary') : $r('app.color.text_hint'))
            .layoutWeight(1)
          Button('选择目录')
            .backgroundColor($r('app.color.primary'))
            .fontColor($r('app.color.text_on_primary'))
            .height(36)
            .onClick(() => this.selectDir())
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(10)

      // 文件类型
      Column({ space: 6 }) {
        Text('文件类型(逗号分隔)').fontSize(14).fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
        TextInput({ text: this.fileTypes, placeholder: 'txt' })
          .onChange((v: string) => (this.fileTypes = v))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(10)

      Button('开始一键清理')
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.primary'))
        .fontColor($r('app.color.text_on_primary'))
        .enabled(this.folderUri.length > 0)
        .onClick(() => this.startCleanup())
    }
    .width('100%')
  }

  // 扫描中（节点1）
  @Builder
  scanningContent() {
    Column({ space: 8 }) {
      Text('正在扫描目录…')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(`已处理: ${this.scanProcessed}  命中: ${this.scanFound}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      if (this.scanCurrent.length > 0) {
        Text(this.scanCurrent)
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
  }

  // 标记重复中（节点4）
  @Builder
  markingContent() {
    Column({ space: 8 }) {
      Text('正在按五则规则标记重复文件…')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      LoadingProgress()
        .width(28)
        .height(28)
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 二次确认（对齐 PC 端 awaiting_confirm）
  @Builder
  confirmContent() {
    Column({ space: 10 }) {
      Text('确认删除')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
      Text(`已标记 ${this.dupCount} 个重复文件待删除。`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Text('将永久删除这些文件，此操作不可恢复。')
        .fontSize(13)
        .fontColor($r('app.color.danger'))
      Button('查看清单')
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.bg_card'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => this.openReview())
      Button('确认删除')
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.danger'))
        .fontColor($r('app.color.text_on_primary'))
        .enabled(this.dupCount > 0)
        .onClick(() => this.confirmDelete())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
  }

  // 复核清单
  @Builder
  reviewContent() {
    Column({ space: 10 }) {
      Text('复核清单')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start)
      Text(`共 ${this.reviewIds.length} 个，已加载 ${this.reviewVisible.length} 个。勾选要删除的文件，取消勾选的将保留。`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Row({ space: 10 }) {
        Button('全选')
          .layoutWeight(1)
          .height(36)
          .backgroundColor($r('app.color.bg_card'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.draftAll())
        Button('全不选')
          .layoutWeight(1)
          .height(36)
          .backgroundColor($r('app.color.bg_card'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.draftNone())
      }
      .width('100%')

      // 清单列表（可滚动，仅渲染当前已加载页，避免 10w ListItem OOM）
      List({ space: 4 }) {
        ForEach(
          this.reviewVisible,
          (f: ScannedFile) => {
            ListItem() {
              Row({ space: 8 }) {
                Toggle({ type: ToggleType.Checkbox, isOn: this.isReviewSelected(f.id) })
                  .onChange((v: boolean) => this.toggleDraft(f.id))
                Column({ space: 2 }) {
                  Text(f.fileName)
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${f.title || ''}　${f.author || ''}　${FormatUtil.formatFileSize(f.fileSize)}`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(8)
              .onClick(() => this.toggleDraft(f.id))
            }
          },
          (f: ScannedFile) => f.id.toString()
        )
        // 滚动到底部加载更多提示
        if (this.reviewVisible.length < this.reviewIds.length) {
          ListItem() {
            Row() {
              Text('上拉加载更多…')
                .fontSize(12)
                .fontColor($r('app.color.text_hint'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding(10)
          }
        }
      }
      .width('100%')
      .height(280)
      .backgroundColor($r('app.color.bg_page'))
      .borderRadius(8)
      .onReachEnd(() => this.loadReviewMore())

      Row({ space: 10 }) {
        Button('返回')
          .layoutWeight(1)
          .height(42)
          .backgroundColor($r('app.color.bg_card'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.phase = 'confirm';
          })
        Button(`保存 ${this.reviewSelectedCount} 个`)
          .layoutWeight(1)
          .height(42)
          .backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.text_on_primary'))
          .onClick(() => this.saveReview())
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
  }

  // 删除中（节点5）
  @Builder
  deletingContent() {
    Column({ space: 8 }) {
      Text('删除中…')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Progress({ value: this.delDone, total: Math.max(this.delTotal, 1), type: ProgressType.Linear })
      Text(`${this.delDone} / ${this.delTotal}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Text(`成功 ${this.delSuccess}   失败 ${this.delFailed}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      if (this.currentFile.length > 0) {
        Text(this.currentFile)
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
  }

  // 完成
  @Builder
  doneContent() {
    Column({ space: 8 }) {
      Text('清理完成')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.success'))
        .alignSelf(ItemAlign.Start)
      if (this.dupCount > 0) {
        Text(`标记重复 ${this.dupCount} 个`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Text(`成功 ${this.delSuccess}   失败 ${this.delFailed}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        if (this.delFailed > 0) {
          Text('失败多为授权失效，可在文库中手动重试')
            .fontSize(11)
            .fontColor($r('app.color.warning'))
        }
      } else {
        Text('未发现重复文件')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      Button('返回首页')
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.primary'))
        .fontColor($r('app.color.text_on_primary'))
        .onClick(() => router.back())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
  }

  // 出错
  @Builder
  errorContent() {
    Column({ space: 8 }) {
      Text('出错')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.danger'))
        .alignSelf(ItemAlign.Start)
      Text(this.errorMsg)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Button('返回首页')
        .width('100%')
        .height(42)
        .backgroundColor($r('app.color.primary'))
        .fontColor($r('app.color.text_on_primary'))
        .onClick(() => router.back())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
  }
}
