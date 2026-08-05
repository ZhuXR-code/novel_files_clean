import { router } from '@kit.ArkUI';
import { ScannedFile } from '../model/ScannedFile';
import { ScanRun } from '../model/ScanRun';
import { GroupInfo } from '../model/GroupInfo';
import { ScanRunDao } from '../database/ScanRunDao';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { DupLogic } from '../utils/DupLogic';
import { ExportService } from '../service/ExportService';
import { ListExportService } from '../service/ListExportService';
import { ListExportUtil, ExportColumn } from '../utils/ListExportUtil';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';
import { ToastUtil } from '../utils/ToastUtil';
import { AppTextInput } from '../components/AppTextInput';

type FilterKind = 'ALL' | 'MARKED' | 'UNMARKED' | 'CHECKED' | 'UNCHECKED' | 'HAS_CHECKED';
type SortKind = 'TIME' | 'NAME' | 'SIZE';
type GroupSortMode =
  | 'COUNT_DESC' | 'COUNT_ASC'
  | 'SIZE_DESC' | 'SIZE_ASC'
  | 'NAME_ASC' | 'NAME_DESC'
  | 'DATE_NEWEST' | 'DATE_OLDEST';

/**
 * 合集三态勾选框（对齐安卓 Material TriStateCheckbox）。
 * 已改为 @Builder 直接绘制在父组件 build 中，实时读取 group.checkedCount，
 * 彻底避免子组件在 ForEach key 复用场景下状态不刷新的问题。
 */

@Entry
@Component
struct LibraryScreen {
  @State runId: number = 0;
  @State run: ScanRun | null = null;
  // 列表模式当前页数据（数据库分页，仅查一页，支持 10w+ 级数据）
  @State viewItems: ScannedFile[] = [];
  // 合集模式当前页数据（数据库分页聚合）
  @State groupItems: GroupInfo[] = [];
  // 已展开合集的文件缓存（书名 -> 文件列表，懒加载）
  @State expandedGroupFiles: Map<string, ScannedFile[]> = new Map<string, ScannedFile[]>();
  // 当前页（0 基）：同步驱动跳转输入框默认显示「第 N 页」（对齐安卓 jumpText = page + 1）
  @State @Watch('onPageChanged') page: number = 0;
  @State pageCount: number = 1;
  // 当前筛选条件下的总数（分页指示器「共 N 条」用，对齐安卓 listPageState.total / groupPageState.total）
  // 与 totalCount（运行全集数，用于统计栏）区分：筛选/搜索后只显示匹配条数
  @State pageTotal: number = 0;
  @State filter: FilterKind = 'ALL';
  @State sort: SortKind = 'TIME';
  @State query: string = '';
  @State queryInput: string = '';
  @State mode: 'list' | 'collection' = 'list';
  @State checkedCount: number = 0;
  @State markedCount: number = 0;
  @State unCheckedCount: number = 0;
  @State unMarkedCount: number = 0;
  @State totalCount: number = 0;
  @State marking: boolean = false;
  @State loadingPage: boolean = false;
  @State expandedTitle: string = '';
  @State colMinCount: number = 0;
  @State colMaxCount: number = 0;
  @State colExcludeInput: string = '';
  @State colExcludeNames: string[] = [];
  @State showCollectionFilter: boolean = false;
  @State currentStep: number = 1; // 1=扫描 2=合集 3=勾选重复 4=确认 5=删除
  @State refreshing: boolean = false;
  @State multiSelectMode: boolean = false;
  // 多选选中 id 集合：刻意不放入 @State。ArkUI 对 @State 引用类型（Set/数组）整体赋值
  // 会触发依赖它的全部 UI 重求值——全选数百上千个 id 时 UI 线程同步重渲染大量行，
  // 数据量大（如 pageSize 调至 2000）直接导致应用卡死/无响应。
  // 改为普通成员 + 轻量 @State 版本号（multiSelectTick）驱动刷新，开销降至 O(可见行)。
  private multiSelectIds: Set<number> = new Set<number>();
  @State multiSelectTick: number = 0;
  // 每页条数可调（10~2000，默认100）、勾选排前、合集排序
  @State pageSize: number = 100;
  @State pageSizeInput: string = '100';
  @State checkedSortToFront: boolean = false;
  @State groupSort: GroupSortMode = 'COUNT_DESC';
  @State showGroupSort: boolean = false;
  @State showSortMenu: boolean = false;
  @State savedScrollIndex: number = 0;
  @State firstVisibleIndex: number = 0;
  // 从详情页返回时置 true：本次 reload 不清空合集展开状态、不把列表/合集回顶
  @State keepExpandedOnReload: boolean = false;
  // FAB 可见性追踪（局部可见索引，用于判断列表是否可滚动，对齐安卓 FAB 仅在可滚动时显示）
  @State listFirstVisible: number = 0;
  @State listLastVisible: number = 0;
  @State colFirstVisible: number = 0;
  @State colLastVisible: number = 0;
  // 对齐安卓端：搜索框切换、工具栏收起、删除选择弹窗
  @State searchVisible: boolean = false;
  @State toolbarExpanded: boolean = true;
  @State showDeleteChoice: boolean = false;
  @State deleteSource: boolean = false;
  @State jumpPage: string = '';
  // 导出列表为 TXT：弹框显隐、已勾选的导出列、导出范围（true=仅当前页）
  @State showExportDialog: boolean = false;
  @State exportKeys: string[] = ListExportUtil.DEFAULT_KEYS.slice();
  @State exportCurrentPageOnly: boolean = true;
  // 全局字号缩放（与「我的」-字号联动）：AppStorage('fontScale') 变化时自动重渲染。
  @StorageProp('fontScale') fontScaleNum: number = 1.0;
  private readonly MIN_PAGE_SIZE: number = 10;
  private readonly MAX_PAGE_SIZE: number = 2000;
  private searchTimer: number | null = null;
  private listScroller: Scroller = new Scroller();
  private collectionScroller: Scroller = new Scroller();

  /** 按全局字号缩放比换算基准字号（对齐 LibraryTab/MinePage 的 fs 实现）。 */
  private fs(base: number): number {
    return Math.round(base * this.fontScaleNum);
  }

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['runId'] !== undefined) {
      this.runId = params['runId'] as number;
    }
    await this.load();
  }

  /** 初始加载：统计 + 当前页数据。不再一次性加载全部文件到内存。 */
  async load(): Promise<void> {
    try {
      this.run = await ScanRunDao.getById(this.runId);
      await this.loadStats();
      await this.reload();
    } catch (e) {
      LogUtil.e('LibraryScreen', `加载文库失败: ${(e as Error).message}`);
      ToastUtil.show(`加载失败: ${(e as Error).message}`);
    }
  }

  /** 加载底部统计：总数/已勾选/已标记（均由数据库 COUNT 查询，不加载文件到内存）。 */
  private async loadStats(): Promise<void> {
    try {
      this.totalCount = await ScannedFileDao.countByScanRun(this.runId);
      this.checkedCount = await ScannedFileDao.countChecked(this.runId);
      this.markedCount = await ScannedFileDao.countMarkedByScanRun(this.runId);
      this.unCheckedCount = this.totalCount - this.checkedCount;
      this.unMarkedCount = this.totalCount - this.markedCount;
    } catch (e) {
      LogUtil.e('LibraryScreen', `加载统计失败: ${(e as Error).message}`);
    }
  }

  /** 根据当前模式加载当前页数据。 */
  private async reload(): Promise<void> {
    if (this.mode === 'list') {
      await this.loadPage();
    } else {
      await this.loadGroups();
    }
  }

  /** 列表模式：从数据库查询当前页文件（LIMIT/OFFSET，支持 10w+ 级数据）。 */
  private async loadPage(): Promise<void> {
    this.loadingPage = true;
    try {
      // 列表模式下 HAS_CHECKED 退化为 CHECKED
      const listFilter: string = this.filter === 'HAS_CHECKED' ? 'CHECKED' : this.filter;
      const total: number = await ScannedFileDao.countFiltered(this.runId, listFilter, this.query);
      this.pageTotal = total;
      this.pageCount = Math.max(1, Math.ceil(total / this.pageSize));
      if (this.page >= this.pageCount) {
        this.page = this.pageCount - 1;
      }
      const offset: number = this.page * this.pageSize;
      this.viewItems = await ScannedFileDao.getPageFiltered(
        this.runId, listFilter, this.sort, this.query, this.pageSize, offset, this.checkedSortToFront
      );
    } catch (e) {
      LogUtil.e('LibraryScreen', `加载列表页失败: ${(e as Error).message}`);
    }
    this.loadingPage = false;
  }

  /** 合集模式：从数据库查询当前页合集（GROUP BY title + 聚合统计 + LIMIT/OFFSET）。 */
  private async loadGroups(): Promise<void> {
    this.loadingPage = true;
    try {
      const total: number = await ScannedFileDao.countGroupsFiltered(
        this.runId, this.filter, this.query, this.colMinCount, this.colMaxCount, this.colExcludeNames
      );
      this.pageTotal = total;
      this.pageCount = Math.max(1, Math.ceil(total / this.pageSize));
      if (this.page >= this.pageCount) {
        this.page = this.pageCount - 1;
      }
      const offset: number = this.page * this.pageSize;
      this.groupItems = await ScannedFileDao.getGroupsPage(
        this.runId, this.filter, this.query, this.colMinCount, this.colMaxCount, this.colExcludeNames,
        this.groupSort, this.checkedSortToFront, this.pageSize, offset
      );
      // 翻页/筛选后清空已展开合集（旧页的展开不再有效）。
      // 但从详情页返回（keepExpandedOnReload=true）时需保留展开状态，仅刷新当前页，不折叠。
      if (!this.keepExpandedOnReload) {
        this.expandedTitle = '';
        this.expandedGroupFiles = new Map<string, ScannedFile[]>();
      }
    } catch (e) {
      LogUtil.e('LibraryScreen', `加载合集页失败: ${(e as Error).message}`);
    }
    this.loadingPage = false;
  }

  /** 展开/折叠某合集；展开时懒加载其文件列表（按当前筛选条件）。 */
  private async toggleExpand(title: string): Promise<void> {
    if (this.expandedTitle === title) {
      this.expandedTitle = '';
      return;
    }
    this.expandedTitle = title;
    // 未加载过则从数据库懒加载
    if (!this.expandedGroupFiles.has(title)) {
      try {
        const args: [number | null, number | null] = this.filterToArgs(this.filter);
        const files: ScannedFile[] = await ScannedFileDao.getFilesByTitle(this.runId, title, args[0], args[1]);
        const newMap: Map<string, ScannedFile[]> = new Map(this.expandedGroupFiles);
        newMap.set(title, files);
        this.expandedGroupFiles = newMap;
      } catch (e) {
        LogUtil.e('LibraryScreen', `加载合集文件失败: ${(e as Error).message}`);
      }
    }
  }

  /** 将筛选模式转换为 getFilesByTitle 的 marked/checked 参数。 */
  private filterToArgs(f: FilterKind): [number | null, number | null] {
    if (f === 'MARKED') return [1, null];
    if (f === 'UNMARKED') return [0, null];
    if (f === 'CHECKED') return [null, 1];
    if (f === 'UNCHECKED') return [null, 0];
    return [null, null]; // ALL / HAS_CHECKED → 不过滤
  }

  // ===== 长按多选 =====
  private enterMultiSelect(id: number): void {
    if (this.multiSelectMode) {
      return;
    }
    this.multiSelectMode = true;
    const s = new Set<number>();
    s.add(id);
    this.multiSelectIds = s;
    this.multiSelectTick++;
    ToastUtil.show('已进入多选模式');
  }

  private toggleMultiSelect(id: number): void {
    const s = new Set<number>(this.multiSelectIds);
    if (s.has(id)) {
      s.delete(id);
    } else {
      s.add(id);
    }
    this.multiSelectIds = s;
    this.multiSelectTick++;
    if (s.size === 0) {
      this.multiSelectMode = false;
    }
  }

  private selectAllVisible(): void {
    const s = new Set<number>(this.multiSelectIds);
    for (const f of this.viewItems) {
      s.add(f.id);
    }
    // 合集模式：展开的合集同样参与全选（viewItems 在合集模式下为空数组）
    for (const files of this.expandedGroupFiles.values()) {
      for (const f of files) {
        s.add(f.id);
      }
    }
    this.multiSelectIds = s;
    this.multiSelectTick++;
  }

  private invertVisible(): void {
    const s = new Set<number>(this.multiSelectIds);
    const allVisible = (): Array<ScannedFile> => {
      const list: ScannedFile[] = [...this.viewItems];
      for (const files of this.expandedGroupFiles.values()) {
        list.push(...files);
      }
      return list;
    };
    for (const f of allVisible()) {
      if (s.has(f.id)) {
        s.delete(f.id);
      } else {
        s.add(f.id);
      }
    }
    this.multiSelectIds = s;
    this.multiSelectTick++;
  }

  private exitMultiSelect(): void {
    this.multiSelectMode = false;
    this.multiSelectIds = new Set<number>();
    this.multiSelectTick++;
  }

  /** 多选已选数量（内部读取 @State 版本号，驱动操作栏计数随 tick 刷新）。 */
  private multiSelectCount(): number {
    return this.multiSelectTick >= 0 ? this.multiSelectIds.size : 0;
  }

  // 多选模式下：将选中文件批量勾选为待删除
  private async multiSelectCheck(): Promise<void> {
    if (this.multiSelectIds.size === 0) {
      ToastUtil.show('未选择任何文件');
      return;
    }
    const ids: number[] = Array.from(this.multiSelectIds);
    try {
      await ScannedFileDao.setCheckedForIds(ids, 1);
      ToastUtil.show(`已勾选 ${ids.length} 个`);
      this.exitMultiSelect();
      await this.loadStats();
      await this.reload();
    } catch (e) {
      LogUtil.e('LibraryScreen', `批量勾选失败: ${(e as Error).message}`);
      ToastUtil.show('批量勾选失败');
    }
  }

  private onQueryInputChanged(v: string): void {
    this.queryInput = v;
    if (this.searchTimer !== null) {
      clearTimeout(this.searchTimer);
      this.searchTimer = null;
    }
    this.searchTimer = setTimeout(() => {
      this.query = this.queryInput;
      this.page = 0;
      this.reload();
      this.searchTimer = null;
    }, 300);
  }

  private submitQuery(): void {
    if (this.searchTimer !== null) {
      clearTimeout(this.searchTimer);
      this.searchTimer = null;
    }
    this.query = this.queryInput;
    this.page = 0;
    this.reload();
  }

  private clearQuery(): void {
    this.queryInput = '';
    this.query = '';
    this.page = 0;
    this.reload();
  }

  private async onCheckChanged(file: ScannedFile, checked: boolean): Promise<void> {
    try {
      file.checked = checked ? 1 : 0;
      await ScannedFileDao.updateChecked(file.id, file.checked);
      this.checkedCount += checked ? 1 : -1;
      this.unCheckedCount -= checked ? 1 : -1;
      // 筛选为 CHECKED/UNCHECKED 时，勾选变化会影响列表内容，需重载
      if (this.filter === 'CHECKED' || this.filter === 'UNCHECKED') {
        await this.reload();
      } else if (this.mode === 'collection') {
        // 合集模式：更新本合集的 checkedCount（三态符号刷新）
        this.updateGroupCheckedCount(file, checked ? 1 : -1);
        // 同步展开缓存中的文件
        this.syncExpandedFile(file);
      } else {
        // 列表模式 ALL 等：仅刷新当前页（触发 Toggle 状态更新）
        this.viewItems = this.viewItems.slice();
      }
    } catch (e) {
      LogUtil.e('LibraryScreen', `勾选失败: ${(e as Error).message}`);
      ToastUtil.show('操作失败');
      file.checked = checked ? 0 : 1;
    }
  }

  private async onMarkChanged(file: ScannedFile, marked: boolean): Promise<void> {
    try {
      file.marked = marked ? 1 : 0;
      await ScannedFileDao.updateMarked(file.id, file.marked);
      this.markedCount += marked ? 1 : -1;
      this.unMarkedCount -= marked ? 1 : -1;
      if (this.filter === 'MARKED' || this.filter === 'UNMARKED') {
        await this.reload();
      } else if (this.mode === 'collection') {
        this.syncExpandedFile(file);
      } else {
        this.viewItems = this.viewItems.slice();
      }
    } catch (e) {
      LogUtil.e('LibraryScreen', `标记失败: ${(e as Error).message}`);
      ToastUtil.show('操作失败');
      file.marked = marked ? 0 : 1;
    }
  }

  /** 合集模式下同步更新展开缓存中的文件（勾选/标记变化后立即刷新 UI）。 */
  private syncExpandedFile(file: ScannedFile): void {
    const files: ScannedFile[] | undefined = this.expandedGroupFiles.get(this.expandedTitle);
    if (!files) return;
    const idx: number = files.findIndex((f) => f.id === file.id);
    if (idx >= 0) {
      // 必须创建新数组（而非原地修改 files[idx]=file），否则数组引用不变，
      // ForEach 检测不到变化，Toggle 的 isOn 不会重新渲染。
      const newFiles: ScannedFile[] = files.slice();
      newFiles[idx] = file;
      const newMap: Map<string, ScannedFile[]> = new Map(this.expandedGroupFiles);
      newMap.set(this.expandedTitle, newFiles);
      this.expandedGroupFiles = newMap;
    }
  }

  /** 合集模式下更新某合集的 checkedCount（三态符号刷新）。 */
  private updateGroupCheckedCount(file: ScannedFile, delta: number): void {
    const title: string = file.title || '';
    const idx: number = this.groupItems.findIndex((g) => g.title === title);
    if (idx >= 0) {
      const g: GroupInfo = this.groupItems[idx];
      g.checkedCount += delta;
      if (g.checkedCount < 0) g.checkedCount = 0;
      if (g.checkedCount > g.fileCount) g.checkedCount = g.fileCount;
      this.groupItems = this.groupItems.slice();
    }
  }

  private async markDuplicates(): Promise<void> {
    // 重入守卫：步骤条快速连点或扫描未完成时避免重复执行导致状态错乱。
    if (this.marking) {
      return;
    }
    this.marking = true;
    try {
      // selectDuplicateIds 内部已调用 setCheckedForIds 持久化勾选，此处无需重复调用
      // （重复调用会导致 10w+ id 时双倍 DB 写入，且曾因 IN 占位符超限崩溃）。
      const ids: number[] = await DupLogic.selectDuplicateIds(this.runId);
      this.checkedCount = await ScannedFileDao.countChecked(this.runId);
      this.unCheckedCount = this.totalCount - this.checkedCount;
      // 步骤条联动：标记重复后推进到第3步
      this.currentStep = Math.max(this.currentStep, 3);
      // 合集模式下保留展开状态，reload 后恢复（让用户能看到文件级勾选变化）。
      // 不再自动展开任意合集：尊重用户当前视图，勾选变化通过「勾选排前」排序后即可看到。
      const savedExpandedTitle: string = this.expandedTitle;
      await this.reload();
      if (this.mode === 'collection' && savedExpandedTitle.length > 0) {
        await this.toggleExpand(savedExpandedTitle);
      }
      // 对齐安卓 selectDuplicates 文案：这里写的是 checked（勾选）字段，不是 marked（星标），
      // 因此用"勾选"而非"标记"；ids 为空说明没有重复文件，给单独提示避免"已勾选 0 个"误导。
      if (ids.length > 0) {
        ToastUtil.show(`已勾选 ${ids.length} 个重复文件`);
      } else {
        ToastUtil.show('未找到重复文件，无需勾选');
      }
    } catch (e) {
      LogUtil.e('LibraryScreen', `勾选重复失败: ${(e as Error).message}`);
      ToastUtil.show('勾选重复失败');
    }
    this.marking = false;
  }

  private async clearChecked(): Promise<void> {
    try {
      await ScannedFileDao.clearChecked(this.runId);
      this.checkedCount = 0;
      this.unCheckedCount = this.totalCount;
      await this.reload();
      // 防御性兜底：reload 已按 DB 重新聚合（checked_count=0），但若 UI 因 ForEach
      // 复用未刷新，这里显式把合集 checkedCount 归零并强制刷新数组引用（触发 @Prop 重算）。
      const rebuilt: GroupInfo[] = this.groupItems.map((g) => {
        const ng: GroupInfo = new GroupInfo();
        ng.title = g.title;
        ng.fileCount = g.fileCount;
        ng.totalSize = g.totalSize;
        ng.checkedCount = 0;
        return ng;
      });
      this.groupItems = rebuilt;
      // 强制刷新 viewItems 中每个文件的 checked 状态，确保 Toggle 重新渲染
      for (const f of this.viewItems) {
        f.checked = 0;
      }
      this.viewItems = this.viewItems.slice();
      // 重置已展开合集文件缓存的 checked（reload 已清空 map，这里仅防御）
      const newMap: Map<string, ScannedFile[]> = new Map<string, ScannedFile[]>();
      this.expandedGroupFiles.forEach((files: ScannedFile[], title: string) => {
        const newFiles: ScannedFile[] = files.map((f) => {
          const nf: ScannedFile = f;
          nf.checked = 0;
          return nf;
        });
        newMap.set(title, newFiles);
      });
      this.expandedGroupFiles = newMap;
      ToastUtil.show('已清空勾选');
    } catch (e) {
      LogUtil.e('LibraryScreen', `清空勾选失败: ${(e as Error).message}`);
      ToastUtil.show('清空勾选失败');
    }
  }

  private async clearMarked(): Promise<void> {
    try {
      await ScannedFileDao.clearMarked(this.runId);
      this.markedCount = 0;
      this.unMarkedCount = this.totalCount;
      await this.reload();
      ToastUtil.show('已清空标记');
    } catch (e) {
      LogUtil.e('LibraryScreen', `清空标记失败: ${(e as Error).message}`);
      ToastUtil.show('清空标记失败');
    }
  }

  private async markDuplicatesByName(): Promise<void> {
    this.marking = true;
    try {
      const n: number = await DupLogic.markDuplicatesByName(this.runId);
      this.currentStep = Math.max(this.currentStep, 3);
      await this.loadStats();
      await this.reload();
      ToastUtil.show(`按书名作者标记了 ${n} 个重复文件`);
    } catch (e) {
      LogUtil.e('LibraryScreen', `按书名标重失败: ${(e as Error).message}`);
      ToastUtil.show('按书名标重失败');
    }
    this.marking = false;
  }

  private applyCollectionFilter(): void {
    this.colExcludeNames = this.colExcludeInput
      .split(/[,，]/)
      .map((s) => s.trim().toLowerCase())
      .filter((s) => s.length > 0);
    this.page = 0;
    this.reload();
  }

  private clearCollectionFilter(): void {
    this.colMinCount = 0;
    this.colMaxCount = 0;
    this.colExcludeInput = '';
    this.colExcludeNames = [];
    this.page = 0;
    this.reload();
  }

  private async exportList(mode: 'checked' | 'marked'): Promise<void> {
    try {
      const path: string = await ExportService.exportList(this.runId, mode, '导出清单');
      ToastUtil.show(`已导出: ${path}`);
    } catch (e) {
      LogUtil.e('LibraryScreen', `导出失败: ${(e as Error).message}`);
      ToastUtil.show('导出失败');
    }
  }

  private openDetail(fileId: number): void {
    router.pushUrl({ url: 'pages/FileDetail', params: { fileId: fileId } }).catch((err: Error) => {
      LogUtil.e('LibraryScreen', `跳转失败: ${err.message}`);
    });
  }

  // 对齐安卓端：删除前先弹窗选择模式（仅记录 / 记录+源文件）
  private goDelete(): void {
    this.currentStep = Math.max(this.currentStep, 4);
    this.showDeleteChoice = true;
  }

  private confirmDeleteChoice(): void {
    this.showDeleteChoice = false;
    router.pushUrl({
      url: 'pages/DeleteConfirm',
      params: { runId: this.runId, deleteSource: this.deleteSource }
    }).catch((err: Error) => {
      LogUtil.e('LibraryScreen', `跳转失败: ${err.message}`);
    });
  }

  // 模式切换：列表 ↔ 合集（对齐安卓 SegmentedButton 列表/合集切换）
  private async toggleMode(target: 'list' | 'collection'): Promise<void> {
    if (this.mode === target) return;
    this.mode = target;
    // 步骤条联动：切换到合集模式时推进到第2步
    if (target === 'collection') {
      this.currentStep = Math.max(this.currentStep, 2);
    }
    // 「含已勾选」是合集级筛选，切回列表模式时回落到全部
    if (target === 'list' && this.filter === 'HAS_CHECKED') {
      this.filter = 'ALL';
    }
    this.page = 0;
    this.expandedTitle = '';
    this.expandedGroupFiles = new Map<string, ScannedFile[]>();
    await this.reload();
  }

  // 更多菜单（对齐安卓 moreMenu：合集筛选/合集排序/按书名标重/清空标记/清空勾选/删除已勾选）
  private buildMoreMenu(): Array<MenuElement> {
    const items: Array<MenuElement> = [];
    // 勾选重复置顶（列表模式无独立 ✓ 按钮，故在更多菜单提供入口；合集模式亦有此入口，与 ✓ 按钮等价）
    // 复用 onStepClick(3)：自动切到合集模式再标记，与步骤条「勾选重复」节点行为一致
    items.push({ value: '勾选重复', action: () => this.onStepClick(3) });
    if (this.mode === 'collection') {
      items.push({ value: '合集筛选', action: () => { this.showCollectionFilter = !this.showCollectionFilter; } });
      items.push({ value: '合集排序', action: () => { this.showGroupSort = true; } });
    }
    items.push({ value: '按书名标重', action: () => this.markDuplicatesByName() });
    items.push({ value: '清空标记', action: () => this.clearMarked() });
    items.push({ value: '清空勾选', action: () => this.clearChecked() });
    items.push({ value: '导出列表', action: () => this.openExportDialog() });
    items.push({ value: '删除已勾选', action: () => this.goDelete() });
    return items;
  }

  // ===================== 导出列表为 TXT =====================

  /** 打开导出弹框：按当前模式重置可选列与默认勾选（仅「小说名」）。 */
  private openExportDialog(): void {
    this.exportKeys = ListExportUtil.DEFAULT_KEYS.slice();
    this.exportCurrentPageOnly = true;
    this.showExportDialog = true;
  }

  /** 勾选/取消某一导出列。 */
  private toggleExportKey(key: string): void {
    const idx: number = this.exportKeys.indexOf(key);
    const next: string[] = this.exportKeys.slice();
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(key);
    }
    this.exportKeys = next;
  }

  /**
   * 执行导出：按当前模式与筛选条件取数 → 生成 TXT → 用系统「另存为」让用户选保存位置。
   * 「仅当前页」取 this.page 那一页；「全部」不分页取全量（复用同一套 WHERE/ORDER BY）。
   */
  private async doExport(): Promise<void> {
    if (this.exportKeys.length === 0) {
      ToastUtil.show('请至少选择一项导出内容');
      return;
    }
    this.showExportDialog = false;
    const isGroup: boolean = this.mode === 'collection';
    try {
      // 全量导出用一个足够大的 limit（与安卓 page<0 不加 LIMIT 等效）
      const BIG_LIMIT: number = 100000000;
      const limit: number = this.exportCurrentPageOnly ? this.pageSize : BIG_LIMIT;
      const offset: number = this.exportCurrentPageOnly ? this.page * this.pageSize : 0;

      let content: string = '';
      let rows: number = 0;
      if (isGroup) {
        const groups: GroupInfo[] = await ScannedFileDao.getGroupsPage(
          this.runId, this.filter, this.query,
          this.colMinCount, this.colMaxCount, this.colExcludeNames,
          this.groupSort, this.checkedSortToFront, limit, offset
        );
        rows = groups.length;
        content = ListExportUtil.buildGroupsText(groups, this.exportKeys);
      } else {
        const files: ScannedFile[] = await ScannedFileDao.getPageFiltered(
          this.runId, this.filter, this.sort, this.query,
          limit, offset, this.checkedSortToFront
        );
        rows = files.length;
        content = ListExportUtil.buildFilesText(files, this.exportKeys);
      }

      if (rows === 0 || !content) {
        ToastUtil.show('没有可导出的数据');
        return;
      }
      const savedName: string = await ListExportService.saveAsTxt(
        content, ListExportUtil.buildFileName(isGroup)
      );
      if (savedName) {
        ToastUtil.show(`已导出 ${rows} 条到 ${savedName}`);
        LogUtil.operation('导出列表', `文库ID=${this.runId} 模式=${isGroup ? '合集' : '列表'} 条数=${rows}`);
      }
    } catch (e) {
      LogUtil.e('LibraryScreen', `导出失败: ${(e as Error).message}`);
      ToastUtil.show(`导出失败: ${(e as Error).message}`);
    }
  }

  /** 导出弹框：勾选导出内容 + 选择导出范围。 */
  @Builder
  exportDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => { this.showExportDialog = false; })

      Column({ space: 10 }) {
        Text('导出列表')
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        // 顶部操作按钮：防止底部按钮被小屏/模拟器截断时无法操作
        Row({ space: 12 }) {
          Button('取消')
            .fontSize(this.fs(14))
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .onClick(() => { this.showExportDialog = false; })
          Button('导出')
            .fontSize(this.fs(14))
            .enabled(this.exportKeys.length > 0)
            .layoutWeight(1)
            .onClick(() => { this.doExport(); })
        }
        .width('100%')

        // 中间内容可滚动：避免列数多或屏幕小时底部按钮被截断
        Scroll() {
          Column({ space: 10 }) {
            Text('导出内容')
              .fontSize(this.fs(13))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            // 可选列：列表模式与合集模式各一套，双列排布以节省高度
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(
                this.mode === 'collection' ? ListExportUtil.GROUP_COLUMNS : ListExportUtil.FILE_COLUMNS,
                (col: ExportColumn) => {
                  Row() {
                    Checkbox()
                      .select(this.exportKeys.includes(col.key))
                      .onChange(() => { this.toggleExportKey(col.key); })
                    Text(col.label)
                      .fontSize(this.fs(13))
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('50%')
                  .padding({ top: 4, bottom: 4 })
                  .onClick(() => { this.toggleExportKey(col.key); })
                },
                (col: ExportColumn) => col.key
              )
            }
            .width('100%')

            Divider().color($r('app.color.divider'))

            Text('导出范围')
              .fontSize(this.fs(13))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            Row() {
              Radio({ value: 'page', group: 'exportRange' })
                .checked(this.exportCurrentPageOnly)
                .onChange((isOn: boolean) => { if (isOn) this.exportCurrentPageOnly = true; })
              Text('仅当前页')
                .fontSize(this.fs(14))
                .fontColor($r('app.color.text_primary'))
                .margin({ left: 4 })
                .layoutWeight(1)
            }
            .width('100%')
            .onClick(() => { this.exportCurrentPageOnly = true; })

            Row() {
              Radio({ value: 'all', group: 'exportRange' })
                .checked(!this.exportCurrentPageOnly)
                .onChange((isOn: boolean) => { if (isOn) this.exportCurrentPageOnly = false; })
              Text('全部（当前筛选条件下的所有数据）')
                .fontSize(this.fs(14))
                .fontColor($r('app.color.text_primary'))
                .margin({ left: 4 })
                .layoutWeight(1)
            }
            .width('100%')
            .onClick(() => { this.exportCurrentPageOnly = false; })

            Text('导出为 TXT，一行一条，各项之间用制表符分隔，首行为表头。')
              .fontSize(this.fs(12))
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(this.fs(14))
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .onClick(() => { this.showExportDialog = false; })
          Button('导出')
            .fontSize(this.fs(14))
            .enabled(this.exportKeys.length > 0)
            .layoutWeight(1)
            .onClick(() => { this.doExport(); })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('86%')
      .constraintSize({ maxHeight: '70%' })
      .padding(16)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(12)
      .offset({ y: -60 })
    }
    .width('100%')
    .height('100%')
  }

  // 删除选择弹窗（对齐安卓 showDeleteChoice：仅记录 / 记录+源文件）
  @Builder
  deleteChoiceDialog() {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩：覆盖整个屏幕，吸收点击关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => { this.showDeleteChoice = false; })

      Column({ space: 12 }) {
        Text('删除选择')
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        // 仅删除记录
        Row() {
          Radio({ value: 'record', group: 'deleteChoice' })
            .checked(!this.deleteSource)
            .onChange((isOn: boolean) => { if (isOn) this.deleteSource = false; })
          Column({ space: 2 }) {
            Text('仅删除记录')
              .fontSize(this.fs(14))
              .fontColor($r('app.color.text_primary'))
            Text('只删除数据库中的扫描记录，保留源文件')
              .fontSize(this.fs(12))
              .fontColor($r('app.color.text_secondary'))
          }
          .margin({ left: 8 })
          .layoutWeight(1)
        }
        .width('100%')
        .onClick(() => { this.deleteSource = false; })

        // 删除记录和源文件
        Row() {
          Radio({ value: 'source', group: 'deleteChoice' })
            .checked(this.deleteSource)
            .onChange((isOn: boolean) => { if (isOn) this.deleteSource = true; })
          Column({ space: 2 }) {
            Text('删除记录和源文件')
              .fontSize(this.fs(14))
              .fontColor($r('app.color.text_primary'))
            Text('同时删除数据库记录和磁盘上的源文件')
              .fontSize(this.fs(12))
              .fontColor($r('app.color.text_secondary'))
          }
          .margin({ left: 8 })
          .layoutWeight(1)
        }
        .width('100%')
        .onClick(() => { this.deleteSource = true; })

        Row({ space: 8 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_page'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => { this.showDeleteChoice = false; })
          Button('确认删除')
            .layoutWeight(1)
            .backgroundColor($r('app.color.danger'))
            .fontColor($r('app.color.text_on_primary'))
            .onClick(() => this.confirmDeleteChoice())
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('85%')
      .padding(16)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(12)
      // 在居中基础上继续上移，使弹框视觉中心偏上，避免被底部手势条/安全区压低
      .offset({ y: -120 })
    }
    .width('100%')
    .height('100%')
  }

  // 多选模式下按返回键退出多选，而非退出页面
  onBackPress(): boolean {
    if (this.multiSelectMode) {
      this.exitMultiSelect();
      return true;
    }
    return false;
  }

  build() {
    Column() {
      // 顶部栏：对齐安卓 TopBar actions（搜索/排序/勾选重复/删除/更多菜单）
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => router.back())
        Text(this.run?.name ?? '文库')
          .fontSize(this.fs(17))
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 8 })

        // 搜索切换
        Button(this.searchVisible ? '✕' : '🔍')
          .fontSize(this.fs(16))
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .fontColor(this.searchVisible ? $r('app.color.primary') : $r('app.color.text_secondary'))
          .onClick(() => this.searchVisible = !this.searchVisible)
        // 工具栏收起/展开（对齐安卓 ExpandMore/ExpandLess：单图标 + 旋转动画）
        Button('▼')
          .fontSize(this.fs(14))
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_secondary'))
          .rotate({ angle: this.toolbarExpanded ? 180 : 0 })
          .animation({ duration: 300, curve: Curve.EaseInOut })
          .onClick(() => { this.toolbarExpanded = !this.toolbarExpanded; })
        // 排序下拉菜单
        Button('⇅')
          .fontSize(this.fs(16))
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_secondary'))
          .bindMenu([
            { value: '按时间', action: () => this.changeSort('TIME') },
            { value: '按名称', action: () => this.changeSort('NAME') },
            { value: '按大小', action: () => this.changeSort('SIZE') }
          ])
        // 勾选重复（合集模式才显示）
        if (this.mode === 'collection') {
          Button('✓')
            .fontSize(this.fs(16))
            .width(32)
            .height(32)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .fontColor(this.marking ? $r('app.color.text_hint') : $r('app.color.primary'))
            .enabled(!this.marking)
            .onClick(() => this.markDuplicates())
        }
        // 删除（有勾选时才显示）
        if (this.checkedCount > 0) {
          Button('🗑')
            .fontSize(this.fs(16))
            .width(32)
            .height(32)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.danger'))
            .onClick(() => this.goDelete())
        }
        // 更多菜单
        Button('⋮')
          .fontSize(this.fs(20))
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_primary'))
          .bindMenu(this.buildMoreMenu())
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 4 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.bg_card'))
      .border({ width: { bottom: 0.5 }, color: $r('app.color.divider') })

      // 多选模式操作栏
      if (this.multiSelectMode) {
        Row({ space: 8 }) {
          Text(`已选 ${this.multiSelectCount()} 个`)
            .fontSize(this.fs(13))
            .fontColor($r('app.color.text_on_primary'))
          Blank()
          Button('全选').fontSize(this.fs(12)).height(30).backgroundColor($r('app.color.primary_dark')).fontColor($r('app.color.text_on_primary')).onClick(() => this.selectAllVisible())
          Button('反选').fontSize(this.fs(12)).height(30).backgroundColor($r('app.color.primary_dark')).fontColor($r('app.color.text_on_primary')).onClick(() => this.invertVisible())
          Button('勾选').fontSize(this.fs(12)).height(30).backgroundColor($r('app.color.danger')).fontColor($r('app.color.text_on_primary')).onClick(() => this.multiSelectCheck())
          Button('退出').fontSize(this.fs(12)).height(30).backgroundColor($r('app.color.bg_card')).fontColor($r('app.color.text_primary')).onClick(() => this.exitMultiSelect())
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.primary'))
      }

      // 步骤条（对齐安卓：扫描→合集→勾选重复→确认→删除）
      Row({ space: 0 }) {
        ForEach(
          ['扫描', '合集', '勾选重复', '确认', '删除'],
          (label: string, index: number) => {
            Row() {
              this.stepDot(index)
              Text(label)
                .fontSize(this.fs(11))
                .fontColor(this.isStepActive(index) ? $r('app.color.primary') : $r('app.color.text_hint'))
                .margin({ left: 4 })
              // 节点间短横线连接（最后一个不显示），对齐安卓版本
              if (index < 4) {
                Text('—')
                  .fontSize(this.fs(11))
                  .fontColor($r('app.color.text_hint'))
                  .margin({ left: 6, right: 6 })
              }
            }
            .onClick(() => this.onStepClick(index + 1))
          },
          (_label: string, index: number) => index.toString()
        )
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.bg_card'))

      // 工具栏（对齐安卓：模式切换 + 勾选排前 + 筛选Chip横向滚动；可整体收起）
      if (this.toolbarExpanded) {
        Column({ space: 6 }) {
          // 列表/合集 模式切换（对齐安卓 SegmentedButton）
          Row({ space: 0 }) {
            Button('列表')
              .layoutWeight(1)
              .height(30)
              .fontSize(this.fs(13))
              .backgroundColor(this.mode === 'list' ? $r('app.color.primary') : $r('app.color.bg_card'))
              .fontColor(this.mode === 'list' ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
              .borderRadius({ topLeft: 8, bottomLeft: 8 })
              .onClick(() => this.toggleMode('list'))
            Button('合集')
              .layoutWeight(1)
              .height(30)
              .fontSize(this.fs(13))
              .backgroundColor(this.mode === 'collection' ? $r('app.color.primary') : $r('app.color.bg_card'))
              .fontColor(this.mode === 'collection' ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
              .borderRadius({ topRight: 8, bottomRight: 8 })
              .onClick(() => this.toggleMode('collection'))
          }
          .width('100%')

          // 勾选排前开关（对齐安卓 Switch + 文案）
          Row() {
            Text('勾选排前')
              .fontSize(this.fs(13))
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.checkedSortToFront })
              .onChange(() => this.toggleCheckedSortToFront())
              .height(24)
          }
          .width('100%')

          // 筛选 Chip 横向滚动（对齐安卓 horizontalScroll + FilterChip）
          Scroll() {
            Row({ space: 8 }) {
              this.chip('全部', this.filter === 'ALL', () => this.changeFilter('ALL'))
              this.chip('已勾选', this.filter === 'CHECKED', () => this.changeFilter('CHECKED'))
              this.chip('未勾选', this.filter === 'UNCHECKED', () => this.changeFilter('UNCHECKED'))
              this.chip('已标记', this.filter === 'MARKED', () => this.changeFilter('MARKED'))
              this.chip('未标记', this.filter === 'UNMARKED', () => this.changeFilter('UNMARKED'))
              if (this.mode === 'collection') {
                this.chip('含已勾选', this.filter === 'HAS_CHECKED', () => this.changeFilter('HAS_CHECKED'))
              }
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      }

      // 搜索框（对齐安卓：仅点击搜索图标后显示）
      if (this.searchVisible) {
        Row({ space: 8 }) {
          AppTextInput({ text: this.queryInput, placeholder: '搜索文件名/书名/作者', inputHeight: 40, expand: true, onChangeCallback: (v: string) => this.onQueryInputChanged(v) })
          if (this.queryInput.length > 0 || this.query.length > 0) {
            Button('清空')
              .fontSize(this.fs(12))
              .height(32)
              .backgroundColor($r('app.color.bg_card'))
              .onClick(() => this.clearQuery())
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }

      // 合集筛选面板（仅合集模式 + 展开时显示）
      if (this.mode === 'collection' && this.showCollectionFilter) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('数量:')
              .fontSize(this.fs(13))
              .fontColor($r('app.color.text_secondary'))
            AppTextInput({ text: this.colMinCount > 0 ? this.colMinCount.toString() : '', placeholder: '最小', inputHeight: 36, widthValue: 70, inputType: InputType.Number, onChangeCallback: (v: string) => {
              const n: number = Number.parseInt(v, 10);
              this.colMinCount = isNaN(n) || n < 0 ? 0 : n;
            } })
            Text('-')
              .fontColor($r('app.color.text_secondary'))
            AppTextInput({ text: this.colMaxCount > 0 ? this.colMaxCount.toString() : '', placeholder: '最大', inputHeight: 36, widthValue: 70, inputType: InputType.Number, onChangeCallback: (v: string) => {
              const n: number = Number.parseInt(v, 10);
              this.colMaxCount = isNaN(n) || n < 0 ? 0 : n;
            } })
            AppTextInput({ text: this.colExcludeInput, placeholder: '排除书名关键词（多个用逗号分隔）', inputHeight: 36, expand: true, onChangeCallback: (v: string) => (this.colExcludeInput = v) })
          }
          .width('100%')

          Row({ space: 12 }) {
            Button('重置')
              .layoutWeight(1)
              .backgroundColor($r('app.color.bg_card'))
              .fontColor($r('app.color.text_primary'))
              .onClick(() => this.clearCollectionFilter())
            Button('应用')
              .layoutWeight(1)
              .backgroundColor($r('app.color.primary'))
              .onClick(() => this.applyCollectionFilter())
          }
          .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(10)
        .margin({ left: 12, right: 12 })
      }

      Text(`共 ${this.totalCount} 个文件  |  已勾选 ${this.checkedCount} / 未勾选 ${this.unCheckedCount}  |  已标记 ${this.markedCount} / 未标记 ${this.unMarkedCount}`)
        .fontSize(this.fs(12))
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 12 })

      // 内容（下拉刷新）
      Refresh({ refreshing: $$this.refreshing }) {
        if (this.loadingPage) {
          Column() {
            LoadingProgress().width(32).height(32)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.mode === 'list') {
          this.listView()
        } else {
          this.collectionView()
        }
      }
      .onRefreshing(() => {
        this.load().finally(() => { this.refreshing = false; });
      })
      .layoutWeight(1)

      // 底部分页导航条（对齐安卓 PageNavBar：有数据即显示，两行布局适配窄屏）
      // 第1行：« ‹ 第X/Y页(共N条) › »
      // 第2行：每页[input]✓  跳转[input]✓      已勾选N个
      // 注意：不再用 pageCount>1 隐藏——单页时也要露出「每页条数」与「共N条」，否则用户以为缺分页
      if (this.pageTotal > 0) {
        Column({ space: 6 }) {
          // 第1行：翻页导航（首页 / 上一页 / 页码 / 下一页 / 末页）
          // 注意：与顶栏图标按钮一致加 .padding(0)，避免鸿蒙 Button 默认内边距把 32vp 宽度的内容压扁/消失
          Row({ space: 4 }) {
            Button('«')
              .fontSize(this.fs(14))
              .height(28)
              .width(32)
              .padding(0)
              .enabled(this.page > 0)
              .backgroundColor($r('app.color.bg_card'))
              .fontColor(this.page > 0 ? $r('app.color.text_primary') : $r('app.color.text_hint'))
              .onClick(() => this.jumpToPage(0))
            Button('‹')
              .fontSize(this.fs(14))
              .height(28)
              .width(32)
              .padding(0)
              .enabled(this.page > 0)
              .backgroundColor($r('app.color.bg_card'))
              .fontColor(this.page > 0 ? $r('app.color.text_primary') : $r('app.color.text_hint'))
              .onClick(() => this.jumpToPage(this.page - 1))
            Text(`第 ${this.page + 1} / ${this.pageCount} 页（共 ${this.pageTotal} 条）`)
              .fontSize(this.fs(11))
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 4, right: 4 })
            Button('›')
              .fontSize(this.fs(14))
              .height(28)
              .width(32)
              .padding(0)
              .enabled(this.page < this.pageCount - 1)
              .backgroundColor($r('app.color.bg_card'))
              .fontColor(this.page < this.pageCount - 1 ? $r('app.color.text_primary') : $r('app.color.text_hint'))
              .onClick(() => this.jumpToPage(this.page + 1))
            Button('»')
              .fontSize(this.fs(14))
              .height(28)
              .width(32)
              .padding(0)
              .enabled(this.page < this.pageCount - 1)
              .backgroundColor($r('app.color.bg_card'))
              .fontColor(this.page < this.pageCount - 1 ? $r('app.color.text_primary') : $r('app.color.text_hint'))
              .onClick(() => this.jumpToPage(this.pageCount - 1))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)

          // 第2行：每页条数 + 跳到指定页（左） / 已勾选数（右）
          Row() {
            Row({ space: 6 }) {
              Text('每页')
                .fontSize(this.fs(12))
                .fontColor($r('app.color.text_secondary'))
              AppTextInput({ text: this.pageSizeInput, inputHeight: 30, widthValue: 60, inputType: InputType.Number, fontSizeVal: this.fs(12), onChangeCallback: (v: string) => (this.pageSizeInput = v) })
              Button('✓')
                .fontSize(this.fs(13))
                .height(30)
                .width(40)
                .borderRadius(4)
                .backgroundColor($r('app.color.primary'))
                .fontColor($r('app.color.text_on_primary'))
                .onClick(() => this.applyPageSize())
              Text('跳转')
                .fontSize(this.fs(12))
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 6 })
              // 跳转输入框：不加 placeholder（前面的"跳转"标签已说明用途），避免被误认为默认填入文字
              AppTextInput({ text: this.jumpPage, inputHeight: 30, widthValue: 48, inputType: InputType.Number, fontSizeVal: this.fs(12), onChangeCallback: (v: string) => (this.jumpPage = v) })
              Button('✓')
                .fontSize(this.fs(13))
                .height(30)
                .width(40)
                .borderRadius(4)
                .backgroundColor($r('app.color.primary_dark'))
                .fontColor($r('app.color.text_on_primary'))
                .onClick(() => {
                  const n: number = Number.parseInt(this.jumpPage, 10);
                  if (!isNaN(n) && n >= 1 && n <= this.pageCount) {
                    this.jumpToPage(n - 1);
                  }
                })
            }
            Blank()
            if (this.checkedCount > 0) {
              Text(`已勾选 ${this.checkedCount} 个`)
                .fontSize(this.fs(11))
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .width('100%')
          .padding({ left: 6, right: 6 })
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
        .backgroundColor($r('app.color.bg_card'))
        .border({ width: { top: 0.5 }, color: $r('app.color.divider') })
      }

      // C组 #6 合集排序弹窗
      if (this.showGroupSort) {
        this.groupSortDialog()
      }

      // 删除选择弹窗（对齐安卓 showDeleteChoice）
      if (this.showDeleteChoice) {
        this.deleteChoiceDialog()
      }

      // 导出列表弹窗（对齐安卓 ExportListDialog）
      if (this.showExportDialog) {
        this.exportDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    // 回到顶部 FAB
    .overlay(() => {
      this.fabButton()
    })
  }

  // C组 #6 合集排序选择弹窗
  @Builder
  groupSortDialog() {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => (this.showGroupSort = false))

      // 弹窗内容
      Column({ space: 8 }) {
        Text('合集排序')
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 8 })

        this.groupSortOption('数量 多→少', 'COUNT_DESC')
        this.groupSortOption('数量 少→多', 'COUNT_ASC')
        this.groupSortOption('大小 大→小', 'SIZE_DESC')
        this.groupSortOption('大小 小→大', 'SIZE_ASC')
        this.groupSortOption('书名 A→Z', 'NAME_ASC')
        this.groupSortOption('书名 Z→A', 'NAME_DESC')
        this.groupSortOption('日期 新→旧', 'DATE_NEWEST')
        this.groupSortOption('日期 旧→新', 'DATE_OLDEST')

        Button('取消')
          .fontSize(this.fs(13))
          .height(36)
          .width('100%')
          .backgroundColor($r('app.color.bg_card'))
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
          .onClick(() => (this.showGroupSort = false))
      }
      .width('80%')
      .padding(16)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(12)
      // 弹窗卡片居中：依赖外层 Stack 的 alignContent(Alignment.Center)，
      // 比 position + markAnchor 组合在 HarmonyOS 上更可靠
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  groupSortOption(label: string, mode: GroupSortMode) {
    Row() {
      Text(label)
        .fontSize(this.fs(14))
        .fontColor(this.groupSort === mode ? $r('app.color.primary') : $r('app.color.text_primary'))
        .layoutWeight(1)
      if (this.groupSort === mode) {
        Text('✓')
          .fontSize(this.fs(14))
          .fontColor($r('app.color.primary'))
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 12 })
    .borderRadius(8)
    .backgroundColor(this.groupSort === mode ? $r('app.color.primary_light') : $r('app.color.bg_page'))
    .onClick(() => this.setGroupSort(mode))
  }

  // 步骤小圆点 builder（内部直接读 @State，避免 @Builder 参数值不刷新）
  @Builder
  stepDot(index: number) {
    Circle({ width: this.isStepActive(index) ? 16 : 14, height: this.isStepActive(index) ? 16 : 14 })
      .fill(this.isStepActive(index) ? $r('app.color.primary') : $r('app.color.divider'))
  }

  // FAB 可见性：仅在内容可滚动时显示（对齐安卓 FAB up/down 仅在可滚动时出现，避免小列表遮挡）
  get scrollTopVisible(): boolean {
    if (this.mode === 'list') {
      return this.listFirstVisible > 0 && this.listFirstVisible < this.viewItems.length;
    }
    return this.colFirstVisible > 0 && this.colFirstVisible < this.groupItems.length;
  }

  get scrollBottomVisible(): boolean {
    if (this.mode === 'list') {
      return this.viewItems.length > 1 && this.listLastVisible < this.viewItems.length - 1;
    }
    return this.groupItems.length > 1 && this.colLastVisible < this.groupItems.length - 1;
  }

  // 悬浮按钮：回到顶部 + 回到底部（对齐安卓 FAB up/down）
  @Builder
  fabButton() {
    Column({ space: 8 }) {
      // 回到顶部（仅在非顶部时显示）
      if (this.scrollTopVisible) {
        Button({ type: ButtonType.Circle }) {
          Text('▲')
            .fontSize(this.fs(18))
            .fontColor($r('app.color.primary'))
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.bg_card'))
        .shadow({ radius: 4, color: $r('app.color.shadow') })
        .onClick(() => {
          if (this.mode === 'list') {
            this.listScroller.scrollToIndex(0);
          } else {
            this.collectionScroller.scrollToIndex(0);
          }
        })
      }

      // 回到底部（仅在非底部时显示）
      if (this.scrollBottomVisible) {
        Button({ type: ButtonType.Circle }) {
          Text('▼')
            .fontSize(this.fs(18))
            .fontColor($r('app.color.primary'))
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.bg_card'))
        .shadow({ radius: 4, color: $r('app.color.shadow') })
        .onClick(() => {
          const total: number = this.mode === 'list' ? this.viewItems.length : this.groupItems.length;
          if (total > 0) {
            if (this.mode === 'list') {
              this.listScroller.scrollToIndex(total - 1);
            } else {
              this.collectionScroller.scrollToIndex(total - 1);
            }
          }
        })
      }
    }
    .position({ x: '82%', y: '60%' })
    .visibility(this.scrollTopVisible || this.scrollBottomVisible ? Visibility.Visible : Visibility.None)
  }

  // 页面跳转
  private jumpToPage(p: number): void {
    if (p >= 0 && p < this.pageCount) {
      // 改 this.page 会触发 @Watch('onPageChanged') 同步更新 jumpPage
      this.page = p;
      this.reload();
    }
  }

  // @Watch 回调：page 变化时同步跳转输入框默认显示（用户可覆盖输入后通过 ✓ 提交）
  // 对齐安卓 jumpText = remember(page) { mutableStateOf((page + 1).toString()) }
  private onPageChanged(): void {
    this.jumpPage = (this.page + 1).toString();
  }

  // 筛选 Chip（对齐安卓 CompactChip：圆角小标签，选中高亮）
  @Builder
  chip(label: string, active: boolean, onClick: () => void) {
    Text(label)
      .fontSize(this.fs(12))
      .height(28)
      .padding({ left: 12, right: 12 })
      .borderRadius(14)
      .backgroundColor(active ? $r('app.color.primary') : $r('app.color.bg_card'))
      .fontColor(active ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      .onClick(onClick)
  }

  @Builder
  listView() {
    List({ scroller: this.listScroller }) {
      ForEach(
        this.viewItems,
        (file: ScannedFile) => {
          ListItem() {
            this.fileRow(file)
          }
          .padding({ left: 12, right: 12, bottom: 8 })
        },
        (file: ScannedFile) => file.id.toString()
      )
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor($r('app.color.bg_page'))
    .onScrollIndex((first: number, end: number) => {
      this.listFirstVisible = first;
      this.listLastVisible = end;
      this.firstVisibleIndex = first + this.page * this.pageSize;
    })
  }

  @Builder
  fileRow(file: ScannedFile) {
    Row({ space: 8 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: file.checked === 1 }).onChange((v: boolean) => this.onCheckChanged(file, v))
        .width(20)
        .height(20)
      Column({ space: 2 }) {
        // 主标题：解析书名优先，缺则显示原文件名（对齐安卓 FileRow）
        Text(file.title.length > 0 ? file.title : file.fileName)
          .fontSize(this.fs(15))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 原文件名（与书名不同时才显示，避免冗余）
        if (file.fileName.length > 0 && file.title.length > 0 && file.fileName !== file.title) {
          Text(`原名:${file.fileName}`)
            .fontSize(this.fs(11))
            .fontColor($r('app.color.text_hint'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        // 元信息行：作者·大小·进度·来源·编码·日期（对齐安卓 FileRow）
        Text(this.buildMetaInfo(file))
          .fontSize(this.fs(12))
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 星标按钮（对齐安卓 IconButton：仅星标，无 > 按钮）
      Text(file.marked === 1 ? '★' : '☆')
        .fontSize(this.fs(20))
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .fontColor(file.marked === 1 ? $r('app.color.primary') : $r('app.color.text_hint'))
        .onClick(() => this.onMarkChanged(file, file.marked !== 1))
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.multiSelectMode && (this.multiSelectTick >= 0) && this.multiSelectIds.has(file.id) ? $r('app.color.primary_light') : $r('app.color.bg_card'))
    .borderRadius(10)
    .onClick(() => {
      if (this.multiSelectMode) {
        this.toggleMultiSelect(file.id);
      } else {
        this.openDetail(file.id);
      }
    })
    .gesture(LongPressGesture().onAction(() => this.enterMultiSelect(file.id)))
  }

  // 合集头三态勾选框（@Builder 直接绘制，避免子组件复用导致状态不刷新）
  @Builder
  collectionCheckBox(group: GroupInfo, onToggle: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(24)
        .height(24)
        .borderRadius(2)
        .border({
          width: (group.fileCount === 0 || group.checkedCount === 0) ? 2 : 0,
          color: $r('app.color.text_secondary')
        })
        .backgroundColor((group.fileCount === 0 || group.checkedCount === 0) ? Color.Transparent : $r('app.color.primary'))
      if (group.fileCount > 0 && group.checkedCount >= group.fileCount) {
        Text('✓')
          .fontSize(16)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
      } else if (group.fileCount > 0 && group.checkedCount > 0) {
        Text('−')
          .fontSize(16)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
      }
    }
    .width(24)
    .height(24)
    .responseRegion({ x: -8, y: -8, width: 40, height: 40 })
    .onClick(onToggle)
  }

  // 构建文件元信息：作者·大小·进度·来源·编码·日期（对齐安卓 FileRow）
  private buildMetaInfo(file: ScannedFile): string {
    const parts: string[] = [];
    if (file.author.length > 0) parts.push(file.author);
    parts.push(FormatUtil.formatFileSize(file.fileSize));
    if (file.progress.length > 0) parts.push(file.progress);
    if (file.source.length > 0) parts.push(`来源:${file.source}`);
    if (file.encoding.length > 0) parts.push(file.encoding);
    const dateStr: string = FormatUtil.formatFileDate(file.fileDate);
    if (dateStr.length > 0) parts.push(dateStr);
    return parts.join(' · ');
  }

  @Builder
  collectionView() {
    List({ scroller: this.collectionScroller }) {
      ForEach(
        this.groupItems,
        (group: GroupInfo) => {
          ListItem() {
            Column({ space: 4 }) {
              // 合集头行（对齐安卓 GroupList header：三态勾选 + 标题 + 汇总 + 展开图标）
              Row() {
                // 直接传 group（@Observed）而不是拷贝 group.checkedCount：ForEach 重建 ListItem 时
                // 父 Column 重新调用此 @Builder 时会读 group.checkedCount 最新值。
                // 关键：外层 ForEach 的 keyGenerator 必须包含 checkedCount，否则 ListItem 复用 + @Builder
                // 缓存会让"勾选重复"等批量更新后合集前复选框不刷新。
                this.collectionCheckBox(group, () => { this.toggleCollectionCheck(group.title); })
                Column({ space: 1 }) {
                  Text(group.title.length > 0 ? group.title : '未解析')
                    .fontSize(this.fs(15))
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  // 汇总：X 本 · 总大小（对齐安卓 group_summary）
                  Text(`${group.fileCount} 本 · ${FormatUtil.formatFileSize(group.totalSize)}`)
                    .fontSize(this.fs(12))
                    .fontColor($r('app.color.text_secondary'))
                  if (group.checkedCount > 0) {
                    Text(`已勾选 ${group.checkedCount} 个`)
                      .fontSize(this.fs(12))
                      .fontColor($r('app.color.primary'))
                  }
                }
                .layoutWeight(1)
                .margin({ left: 4 })
                .alignItems(HorizontalAlign.Start)
                .onClick(() => this.toggleExpand(group.title))

                // 展开/收起图标（对齐安卓 ExpandMore/ExpandLess：单图标 + 旋转动画）
                Text('▼')
                  .fontSize(this.fs(14))
                  .width(36)
                  .height(36)
                  .textAlign(TextAlign.Center)
                  .fontColor($r('app.color.text_hint'))
                  .rotate({ angle: this.expandedTitle === group.title ? 180 : 0 })
                  .animation({ duration: 250, curve: Curve.EaseInOut })
                  .onClick(() => this.toggleExpand(group.title))
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              if (this.expandedTitle === group.title) {
                Column({ space: 6 }) {
                  if (this.expandedGroupFiles.has(group.title)) {
                    ForEach(
                      this.expandedGroupFiles.get(group.title)!,
                      (file: ScannedFile) => {
                        this.fileRow(file)
                      },
                      (file: ScannedFile) => `${file.id}_${file.checked}_${file.marked}`
                    )
                  } else {
                    LoadingProgress().width(24).height(24)
                  }
                }
                .width('100%')
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.bg_card'))
            .borderRadius(10)
          }
          .padding({ left: 12, right: 12, bottom: 8 })
        },
        // 关键：keyGenerator 必须包含 checkedCount/fileCount（影响三态勾选框 + 标题下的"X 本 / 已勾选 N 个"）
        // 否则 markDuplicates 批量更新后 reload 出的新 groupItems 会被 ForEach 判为"同一合集"复用 ListItem，
        // 内部 @Builder 缓存导致合集前复选框不刷新（仅顶部"已勾选 N"统计正常，因为它是顶层 @State 重新赋值）。
        (group: GroupInfo) => `${group.title}_${group.fileCount}_${group.checkedCount}`
      )
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor($r('app.color.bg_page'))
    .onScrollIndex((first: number, end: number) => {
      this.colFirstVisible = first;
      this.colLastVisible = end;
    })
  }

  private async changeFilter(f: FilterKind): Promise<void> {
    this.filter = f;
    this.page = 0;
    this.expandedTitle = '';
    this.expandedGroupFiles = new Map<string, ScannedFile[]>();
    await this.reload();
  }

  private async changeSort(s: SortKind): Promise<void> {
    this.sort = s;
    this.page = 0;
    await this.reload();
  }

  // 步骤条节点是否高亮（联动判定：合集视图模式下自动高亮节点 2，避免模式与步骤条脱钩）
  private isStepActive(index: number): boolean {
    return this.currentStep >= index + 1 || (index === 1 && this.mode === 'collection');
  }

  // 步骤条点击联动（对齐安卓 StepIndicator 可点击+节点联动）
  // 支持回退：点击较早步骤时 currentStep 同步回退，节点高亮随之变化
  private async onStepClick(step: number): Promise<void> {
    // 回退：仅更新 currentStep 并协调界面模式，不重跑标记/删除等耗时操作
    if (step < this.currentStep) {
      this.currentStep = step;
      if (step <= 1) {
        // 回退到扫描：若当前是合集模式则切回列表
        if (this.mode !== 'list') {
          this.mode = 'list';
          await this.reload();
        }
      } else if (step === 2) {
        // 回退到合集：确保处于合集模式
        if (this.mode !== 'collection') {
          this.mode = 'collection';
          await this.reload();
        }
      }
      return;
    }
    // 前进
    if (step === 1) {
      this.currentStep = 1;
    } else if (step === 2) {
      // 合集：切换到合集模式
      this.toggleMode('collection');
      this.currentStep = Math.max(this.currentStep, 2);
    } else if (step === 3) {
      // 勾选重复：先确保切到合集模式（await 避免与 markDuplicates 的 reload 并发），再执行标记
      this.currentStep = 3;
      if (this.mode !== 'collection') {
        await this.toggleMode('collection');
      }
      await this.markDuplicates();
    } else if (step === 4) {
      // 确认：跳转删除确认页
      this.currentStep = Math.max(this.currentStep, 4);
      this.goDelete();
    } else if (step === 5) {
      // 删除：跳转删除确认页
      this.currentStep = 5;
      this.goDelete();
    }
  }

  private async toggleCollectionCheck(title: string): Promise<void> {
    try {
      const ids: number[] = await ScannedFileDao.getIdsByTitle(this.runId, title);
      if (ids.length === 0) return;
      // 查找当前合集信息判断状态（0=未选 1=部分 2=全选）
      const group: GroupInfo | undefined = this.groupItems.find((g) => g.title === title);
      let status: number = 0;
      if (group && group.fileCount > 0) {
        if (group.checkedCount >= group.fileCount) {
          status = 2;
        } else if (group.checkedCount > 0) {
          status = 1;
        }
      }
      // 全选/部分 → 取消；未选 → 全选
      const targetChecked: number = status === 2 ? 0 : 1;
      await ScannedFileDao.setCheckedForIds(ids, targetChecked);
      // 更新统计
      this.checkedCount = await ScannedFileDao.countChecked(this.runId);
      this.unCheckedCount = this.totalCount - this.checkedCount;
      // 更新合集的 checkedCount
      if (group) {
        group.checkedCount = targetChecked === 1 ? group.fileCount : 0;
        this.groupItems = this.groupItems.slice();
      }
      // 同步展开缓存中的文件勾选状态
      const files: ScannedFile[] | undefined = this.expandedGroupFiles.get(title);
      if (files) {
        for (const f of files) {
          f.checked = targetChecked;
        }
        // 创建新数组（而非仅浅拷贝 Map），否则 ForEach 检测不到数组引用变化
        const newFiles: ScannedFile[] = files.slice();
        const newMap: Map<string, ScannedFile[]> = new Map(this.expandedGroupFiles);
        newMap.set(title, newFiles);
        this.expandedGroupFiles = newMap;
      }
    } catch (e) {
      LogUtil.e('LibraryScreen', `合集勾选失败: ${(e as Error).message}`);
      ToastUtil.show('合集勾选失败');
    }
  }

  // ===== 每页条数可调 =====
  private applyPageSize(): void {
    let n: number = Number.parseInt(this.pageSizeInput, 10);
    if (isNaN(n)) n = 100;
    n = Math.max(this.MIN_PAGE_SIZE, Math.min(this.MAX_PAGE_SIZE, n));
    this.pageSize = n;
    this.pageSizeInput = n.toString();
    this.page = 0;
    this.reload();
  }

  // ===== 勾选排前切换 =====
  private toggleCheckedSortToFront(): void {
    this.checkedSortToFront = !this.checkedSortToFront;
    this.page = 0;
    this.reload();
  }

  // ===== 合集排序选择 =====
  private setGroupSort(mode: GroupSortMode): void {
    this.groupSort = mode;
    this.showGroupSort = false;
    this.page = 0;
    this.reload();
  }

  // ===== 滚动位置保存/恢复 =====
  async onPageShow(): Promise<void> {
    // 从详情页返回：保留合集展开状态与滚动位置，仅静默刷新数据（文件可能已被详情页修改/删除）。
    // keepExpandedOnReload=true 让 loadGroups 不折叠已展开合集；reload 后按保存的页内相对索引恢复滚动。
    this.keepExpandedOnReload = true;
    await this.loadStats();
    await this.reload();
    this.keepExpandedOnReload = false;
    // 若详情页修改了某合集内的文件状态，重新懒加载该合集内容（不折叠），保证行内 Toggle 与 DB 一致
    if (this.mode === 'collection' && this.expandedTitle.length > 0) {
      this.expandedGroupFiles.delete(this.expandedTitle);
      await this.toggleExpand(this.expandedTitle);
    }
    if (this.savedScrollIndex > 0) {
      setTimeout(() => {
        if (this.mode === 'list') {
          this.listScroller.scrollToIndex(this.savedScrollIndex, false, ScrollAlign.START);
        } else {
          this.collectionScroller.scrollToIndex(this.savedScrollIndex, false, ScrollAlign.START);
        }
      }, 100);
    }
  }

  onPageHide(): void {
    // 记录当前滚动位置（转成「页内相对索引」，因为 scrollToIndex 的 index 是 List 内数组的 0-based 局部下标）
    this.savedScrollIndex = Math.max(0, this.firstVisibleIndex - this.page * this.pageSize);
  }
}
