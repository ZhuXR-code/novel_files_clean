import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ScannedFile } from '../model/ScannedFile';
import { ScanRun } from '../model/ScanRun';
import { ScanRunDao } from '../database/ScanRunDao';
import { ScannedFileDao } from '../database/ScannedFileDao';
import { DupLogic } from '../utils/DupLogic';
import { ExportService } from '../service/ExportService';
import { FormatUtil } from '../utils/FormatUtil';
import { LogUtil } from '../utils/LogUtil';

type FilterKind = 'ALL' | 'MARKED' | 'UNMARKED' | 'CHECKED' | 'UNCHECKED';
type SortKind = 'TIME' | 'NAME' | 'SIZE';

@Entry
@Component
struct LibraryScreen {
  @State runId: number = 0;
  @State run: ScanRun | null = null;
  @State allFiles: ScannedFile[] = [];
  @State viewItems: ScannedFile[] = [];
  @State page: number = 0;
  @State pageCount: number = 1;
  @State filter: FilterKind = 'ALL';
  @State sort: SortKind = 'TIME';
  @State query: string = '';
  @State queryInput: string = '';
  @State mode: 'list' | 'collection' = 'list';
  @State checkedCount: number = 0;
  @State markedCount: number = 0;
  @State unCheckedCount: number = 0;
  @State unMarkedCount: number = 0;
  @State marking: boolean = false;
  @State expandedTitle: string = '';
  @State colMinCount: number = 0;
  @State colMaxCount: number = 0;
  @State colExcludeInput: string = '';
  @State colExcludeNames: string[] = [];
  @State showCollectionFilter: boolean = false;
  private readonly pageSize: number = 50;
  private searchTimer: number | null = null;
  private groupCache: Map<string, ScannedFile[]> = new Map<string, ScannedFile[]>();

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params && params['runId'] !== undefined) {
      this.runId = params['runId'] as number;
    }
    await this.load();
  }

  async load(): Promise<void> {
    this.run = await ScanRunDao.getById(this.runId);
    this.allFiles = await ScannedFileDao.getByScanRun(this.runId, 1000000, 0);
    this.checkedCount = await ScannedFileDao.countChecked(this.runId);
    this.markedCount = this.allFiles.filter((f) => f.marked === 1).length;
    this.unCheckedCount = this.allFiles.length - this.checkedCount;
    this.unMarkedCount = this.allFiles.length - this.markedCount;
    this.page = 0;
    this.refreshView();
  }

  private refreshView(): void {
    this.groupCache.clear();
    const list: ScannedFile[] = this.filteredAllFiles();
    this.pageCount = Math.max(1, Math.ceil(list.length / this.pageSize));
    if (this.page >= this.pageCount) {
      this.page = this.pageCount - 1;
    }
    const start: number = this.page * this.pageSize;
    this.viewItems = list.slice(start, start + this.pageSize);
  }

  private filteredAllFiles(): ScannedFile[] {
    let list: ScannedFile[] = this.allFiles;
    if (this.filter === 'MARKED') {
      list = list.filter((f) => f.marked === 1);
    } else if (this.filter === 'UNMARKED') {
      list = list.filter((f) => f.marked === 0);
    } else if (this.filter === 'CHECKED') {
      list = list.filter((f) => f.checked === 1);
    } else if (this.filter === 'UNCHECKED') {
      list = list.filter((f) => f.checked === 0);
    }
    const q: string = this.query.trim().toLowerCase();
    if (q.length > 0) {
      list = list.filter(
        (f) =>
          f.fileName.toLowerCase().includes(q) ||
          f.title.toLowerCase().includes(q) ||
          f.author.toLowerCase().includes(q) ||
          (f.titlePinyin.length > 0 && f.titlePinyin.toLowerCase().includes(q)) ||
          (f.authorPinyin.length > 0 && f.authorPinyin.toLowerCase().includes(q))
      );
    }
    if (this.sort === 'NAME') {
      list = list.slice().sort((a, b) => a.fileName.localeCompare(b.fileName));
    } else if (this.sort === 'SIZE') {
      list = list.slice().sort((a, b) => b.fileSize - a.fileSize);
    } else {
      list = list.slice().sort((a, b) => b.createdAt - a.createdAt);
    }
    return list;
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
      this.expandedTitle = '';
      this.refreshView();
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
    this.expandedTitle = '';
    this.refreshView();
  }

  private clearQuery(): void {
    this.queryInput = '';
    this.query = '';
    this.page = 0;
    this.expandedTitle = '';
    this.refreshView();
  }

  private async onCheckChanged(file: ScannedFile, checked: boolean): Promise<void> {
    file.checked = checked ? 1 : 0;
    await ScannedFileDao.updateChecked(file.id, file.checked);
    this.checkedCount += checked ? 1 : -1;
    this.unCheckedCount -= checked ? 1 : -1;
    this.refreshView();
  }

  private async onMarkChanged(file: ScannedFile, marked: boolean): Promise<void> {
    file.marked = marked ? 1 : 0;
    await ScannedFileDao.updateMarked(file.id, file.marked);
    this.markedCount += marked ? 1 : -1;
    this.unMarkedCount -= marked ? 1 : -1;
    this.refreshView();
  }

  private async markDuplicates(): Promise<void> {
    this.marking = true;
    try {
      const ids: number[] = await DupLogic.selectDuplicateIds(this.runId);
      for (const f of this.allFiles) {
        if (ids.includes(f.id)) {
          f.checked = 1;
        }
      }
      this.checkedCount = await ScannedFileDao.countChecked(this.runId);
      this.unCheckedCount = this.allFiles.length - this.checkedCount;
      this.refreshView();
      promptAction.showToast({ message: `已标记 ${ids.length} 个重复文件` });
    } catch (e) {
      LogUtil.e('LibraryScreen', `勾选重复失败: ${(e as Error).message}`);
      promptAction.showToast({ message: '勾选重复失败' });
    }
    this.marking = false;
  }

  private async clearChecked(): Promise<void> {
    await ScannedFileDao.clearChecked(this.runId);
    for (const f of this.allFiles) {
      f.checked = 0;
    }
    this.checkedCount = 0;
    this.unCheckedCount = this.allFiles.length;
    this.refreshView();
    promptAction.showToast({ message: '已清空勾选' });
  }

  private async clearMarked(): Promise<void> {
    await ScannedFileDao.clearMarked(this.runId);
    for (const f of this.allFiles) {
      f.marked = 0;
    }
    this.markedCount = 0;
    this.unMarkedCount = this.allFiles.length;
    this.refreshView();
    promptAction.showToast({ message: '已清空标记' });
  }

  private async markDuplicatesByName(): Promise<void> {
    this.marking = true;
    try {
      const n: number = await DupLogic.markDuplicatesByName(this.runId);
      await this.load();
      promptAction.showToast({ message: `按书名作者标记了 ${n} 个重复文件` });
    } catch (e) {
      LogUtil.e('LibraryScreen', `按书名标重失败: ${(e as Error).message}`);
      promptAction.showToast({ message: '按书名标重失败' });
    }
    this.marking = false;
  }

  private applyCollectionFilter(): void {
    this.colExcludeNames = this.colExcludeInput
      .split(/[,，]/)
      .map((s) => s.trim().toLowerCase())
      .filter((s) => s.length > 0);
    this.page = 0;
    this.expandedTitle = '';
    this.refreshView();
  }

  private clearCollectionFilter(): void {
    this.colMinCount = 0;
    this.colMaxCount = 0;
    this.colExcludeInput = '';
    this.colExcludeNames = [];
    this.page = 0;
    this.expandedTitle = '';
    this.refreshView();
  }

  private async exportList(mode: 'checked' | 'marked'): Promise<void> {
    try {
      const path: string = await ExportService.exportList(this.runId, mode, '导出清单');
      promptAction.showToast({ message: `已导出: ${path}` });
    } catch (e) {
      LogUtil.e('LibraryScreen', `导出失败: ${(e as Error).message}`);
      promptAction.showToast({ message: '导出失败' });
    }
  }

  private openDetail(fileId: number): void {
    router.pushUrl({ url: 'pages/FileDetail', params: { fileId: fileId } }).catch((err: Error) => {
      LogUtil.e('LibraryScreen', `跳转失败: ${err.message}`);
    });
  }

  private goDelete(): void {
    router.pushUrl({ url: 'pages/DeleteConfirm', params: { runId: this.runId } }).catch((err: Error) => {
      LogUtil.e('LibraryScreen', `跳转失败: ${err.message}`);
    });
  }

  build() {
    Column() {
      // 顶部栏
      Row() {
        Button('返回').onClick(() => router.back())
        Text(this.run?.name ?? '文库')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_primary'))
        Button(this.mode === 'list' ? '合集' : '列表')
          .backgroundColor($r('app.color.primary'))
          .onClick(() => {
            this.mode = this.mode === 'list' ? 'collection' : 'list';
            this.expandedTitle = '';
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      // 工具栏
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          this.tab('全部', this.filter === 'ALL', () => this.changeFilter('ALL'))
          this.tab('已标记', this.filter === 'MARKED', () => this.changeFilter('MARKED'))
          this.tab('未标记', this.filter === 'UNMARKED', () => this.changeFilter('UNMARKED'))
          this.tab('已勾选', this.filter === 'CHECKED', () => this.changeFilter('CHECKED'))
          this.tab('未勾选', this.filter === 'UNCHECKED', () => this.changeFilter('UNCHECKED'))
        }
        .width('100%')

        Row({ space: 6 }) {
          this.sortBtn('时间', this.sort === 'TIME', () => this.changeSort('TIME'))
          this.sortBtn('名称', this.sort === 'NAME', () => this.changeSort('NAME'))
          this.sortBtn('大小', this.sort === 'SIZE', () => this.changeSort('SIZE'))
          Blank()
          if (this.mode === 'collection') {
            Button(this.showCollectionFilter ? '隐藏筛选' : '合集筛选')
              .fontSize(12)
              .height(30)
              .backgroundColor(this.showCollectionFilter ? $r('app.color.primary_dark') : $r('app.color.bg_card'))
              .fontColor(this.showCollectionFilter ? '#ffffff' : $r('app.color.text_secondary'))
              .onClick(() => (this.showCollectionFilter = !this.showCollectionFilter))
          }
        }
        .width('100%')

        Row({ space: 8 }) {
          TextInput({ text: this.queryInput, placeholder: '搜索文件名/书名/作者' })
            .height(40)
            .layoutWeight(1)
            .onChange((v: string) => this.onQueryInputChanged(v))
          if (this.queryInput.length > 0 || this.query.length > 0) {
            Button('清空')
              .fontSize(12)
              .height(32)
              .backgroundColor($r('app.color.bg_card'))
              .onClick(() => this.clearQuery())
          }
        }
        .width('100%')

        if (this.mode === 'collection' && this.showCollectionFilter) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('数量:')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.colMinCount > 0 ? this.colMinCount.toString() : '', placeholder: '最小' })
                .height(36)
                .width(70)
                .type(InputType.Number)
                .onChange((v: string) => {
                  const n: number = Number.parseInt(v, 10);
                  this.colMinCount = isNaN(n) || n < 0 ? 0 : n;
                })
              Text('-')
                .fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.colMaxCount > 0 ? this.colMaxCount.toString() : '', placeholder: '最大' })
                .height(36)
                .width(70)
                .type(InputType.Number)
                .onChange((v: string) => {
                  const n: number = Number.parseInt(v, 10);
                  this.colMaxCount = isNaN(n) || n < 0 ? 0 : n;
                })
              TextInput({ text: this.colExcludeInput, placeholder: '排除书名关键词（多个用逗号分隔）' })
                .height(36)
                .layoutWeight(1)
                .onChange((v: string) => (this.colExcludeInput = v))
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
        }
      }
      .padding({ left: 12, right: 12 })

      // 操作行
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Button('规则标重').backgroundColor($r('app.color.primary')).enabled(!this.marking).onClick(() => this.markDuplicates())
          Button('书名标重').backgroundColor($r('app.color.primary')).enabled(!this.marking).onClick(() => this.markDuplicatesByName())
          Button('清空勾选').onClick(() => this.clearChecked())
          Button('清空标记').onClick(() => this.clearMarked())
        }
        .width('100%')
        .padding({ top: 4 })

        Row({ space: 6 }) {
          Button('导出勾选').onClick(() => this.exportList('checked'))
          Button('导出标记').onClick(() => this.exportList('marked'))
          Button('删除').backgroundColor($r('app.color.danger')).onClick(() => this.goDelete())
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4 })

      Text(`已勾选 ${this.checkedCount} / 未勾选 ${this.unCheckedCount}  |  已标记 ${this.markedCount} / 未标记 ${this.unMarkedCount}`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 12 })

      // 内容
      if (this.mode === 'list') {
        this.listView()
      } else {
        this.collectionView()
      }

      // 底部分页
      if (this.mode === 'list' && this.pageCount > 1) {
        Row() {
          Button('上一页').enabled(this.page > 0).onClick(() => {
            if (this.page > 0) {
              this.page--;
              this.refreshView();
            }
          })
          Text(`${this.page + 1} / ${this.pageCount}`)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 16, right: 16 })
          Button('下一页').enabled(this.page < this.pageCount - 1).onClick(() => {
            if (this.page < this.pageCount - 1) {
              this.page++;
              this.refreshView();
            }
          })
        }
        .width('100%')
        .height(48)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  tab(label: string, active: boolean, onClick: () => void) {
    Button(label)
      .fontSize(12)
      .height(32)
      .backgroundColor(active ? $r('app.color.primary') : $r('app.color.bg_card'))
      .fontColor(active ? '#ffffff' : $r('app.color.text_primary'))
      .onClick(onClick)
  }

  @Builder
  sortBtn(label: string, active: boolean, onClick: () => void) {
    Button(label)
      .fontSize(12)
      .height(30)
      .backgroundColor(active ? $r('app.color.primary_dark') : $r('app.color.bg_card'))
      .fontColor(active ? '#ffffff' : $r('app.color.text_secondary'))
      .onClick(onClick)
  }

  @Builder
  listView() {
    List() {
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
  }

  @Builder
  fileRow(file: ScannedFile) {
    Row({ space: 10 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: file.checked === 1 }).onChange((v: boolean) => this.onCheckChanged(file, v))
        .width(36)
      Column({ space: 3 }) {
        Text(file.title || file.fileName)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${file.author || '未知作者'}  ${file.progress || ''}  ${file.source || ''}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${file.fileName}  ${FormatUtil.formatFileSize(file.fileSize)}`)
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.openDetail(file.id))

      Row({ space: 4 }) {
        Button(file.marked === 1 ? '★' : '☆')
          .fontSize(18)
          .width(36)
          .height(36)
          .backgroundColor($r('app.color.bg_card'))
          .fontColor($r('app.color.primary'))
          .onClick(() => this.onMarkChanged(file, file.marked !== 1))
        Button('>')
          .width(36)
          .height(36)
          .backgroundColor($r('app.color.bg_card'))
          .onClick(() => this.openDetail(file.id))
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(10)
  }

  @Builder
  collectionView() {
    List() {
      ForEach(
        this.groupTitles(),
        (title: string) => {
          ListItem() {
            Column({ space: 4 }) {
              Row() {
                Text(title || '未解析')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Text(`${this.groupOf(title).length} 本`)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                Button(this.expandedTitle === title ? '收起' : '展开')
                  .fontSize(12)
                  .height(30)
                  .backgroundColor($r('app.color.bg_card'))
                  .onClick(() => {
                    this.expandedTitle = this.expandedTitle === title ? '' : title;
                  })
              }
              .width('100%')
              if (this.expandedTitle === title) {
                Column({ space: 6 }) {
                  ForEach(
                    this.groupOf(title),
                    (file: ScannedFile) => {
                      this.fileRow(file)
                    },
                    (file: ScannedFile) => file.id.toString()
                  )
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
        (title: string) => title
      )
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  private groupCacheKey(title: string): string {
    return `${this.filter}|${this.query}|${this.colMinCount}|${this.colMaxCount}|${this.colExcludeNames.join(',')}|${this.sort}|${title}`;
  }

  private groupTitles(): string[] {
    const map = new Map<string, ScannedFile[]>();
    for (const f of this.filteredAllFiles()) {
      const key: string = f.title || '';
      if (!map.has(key)) {
        map.set(key, []);
      }
      map.get(key)!.push(f);
    }
    const excludes: string[] = this.colExcludeNames;
    const titles: string[] = [];
    const allKeys: string[] = Array.from(map.keys());
    for (const key of allKeys) {
      const fileList: ScannedFile[] = map.get(key)!;
      if (this.colMinCount > 0 && fileList.length < this.colMinCount) {
        continue;
      }
      if (this.colMaxCount > 0 && fileList.length > this.colMaxCount) {
        continue;
      }
      if (excludes.length > 0 && excludes.some((e) => key.toLowerCase().includes(e))) {
        continue;
      }
      titles.push(key);
    }
    titles.sort((a, b) => {
      if (a === '' && b !== '') return 1;
      if (b === '' && a !== '') return -1;
      return map.get(b)!.length - map.get(a)!.length;
    });
    return titles;
  }

  private groupOf(title: string): ScannedFile[] {
    const key: string = this.groupCacheKey(title);
    if (this.groupCache.has(key)) {
      return this.groupCache.get(key)!;
    }
    let list: ScannedFile[] = this.allFiles.filter((f) => (f.title || '') === title);
    if (this.filter === 'MARKED') {
      list = list.filter((f) => f.marked === 1);
    } else if (this.filter === 'UNMARKED') {
      list = list.filter((f) => f.marked === 0);
    } else if (this.filter === 'CHECKED') {
      list = list.filter((f) => f.checked === 1);
    } else if (this.filter === 'UNCHECKED') {
      list = list.filter((f) => f.checked === 0);
    }
    const q: string = this.query.trim().toLowerCase();
    if (q.length > 0) {
      list = list.filter(
        (f) =>
          f.fileName.toLowerCase().includes(q) ||
          f.title.toLowerCase().includes(q) ||
          f.author.toLowerCase().includes(q) ||
          (f.titlePinyin.length > 0 && f.titlePinyin.toLowerCase().includes(q)) ||
          (f.authorPinyin.length > 0 && f.authorPinyin.toLowerCase().includes(q))
      );
    }
    if (this.sort === 'NAME') {
      list = list.slice().sort((a, b) => a.fileName.localeCompare(b.fileName));
    } else if (this.sort === 'SIZE') {
      list = list.slice().sort((a, b) => b.fileSize - a.fileSize);
    } else {
      list = list.slice().sort((a, b) => b.createdAt - a.createdAt);
    }
    this.groupCache.set(key, list);
    return list;
  }

  private changeFilter(f: FilterKind): void {
    this.filter = f;
    this.page = 0;
    this.expandedTitle = '';
    this.refreshView();
  }

  private changeSort(s: SortKind): void {
    this.sort = s;
    this.page = 0;
    this.refreshView();
  }
}
