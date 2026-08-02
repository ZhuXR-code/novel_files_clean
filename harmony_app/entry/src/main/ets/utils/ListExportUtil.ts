import { ScannedFile } from '../model/ScannedFile';
import { GroupInfo } from '../model/GroupInfo';
import { FormatUtil } from './FormatUtil';

/**
 * 导出列定义：key 用于勾选状态，label 用于弹框显示与表头。
 * 对齐安卓端 ListExportUtil.FileColumn / GroupColumn。
 */
export class ExportColumn {
  key: string = '';
  label: string = '';

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

/**
 * 书库列表 / 合集列表「导出为 TXT」的列定义与内容生成。
 *
 * 导出格式：一行一本（或一个合集），各列之间用制表符 \t 分隔，首行为表头。
 * 单元格内的制表符/换行会被替换为空格，避免破坏列对齐。
 */
export class ListExportUtil {
  /** 列表模式可导出的列（顺序即导出列顺序）。 */
  static readonly FILE_COLUMNS: ExportColumn[] = [
    new ExportColumn('title', '小说名'),
    new ExportColumn('author', '作者'),
    new ExportColumn('progress', '进度'),
    new ExportColumn('source', '来源'),
    new ExportColumn('file_name', '文件名'),
    new ExportColumn('file_size', '文件大小'),
    new ExportColumn('file_path', '文件路径'),
    new ExportColumn('encoding', '编码'),
    new ExportColumn('ext', '扩展名'),
    new ExportColumn('file_date', '文件修改时间'),
    new ExportColumn('created_at', '入库时间'),
    new ExportColumn('marked', '标记状态'),
    new ExportColumn('checked', '勾选状态')
  ];

  /** 合集模式可导出的列。 */
  static readonly GROUP_COLUMNS: ExportColumn[] = [
    new ExportColumn('title', '小说名'),
    new ExportColumn('file_count', '文件数'),
    new ExportColumn('total_size', '总大小'),
    new ExportColumn('checked_count', '已勾选数')
  ];

  /** 默认勾选：仅「小说名」。 */
  static readonly DEFAULT_KEYS: string[] = ['title'];

  private static readonly SEP: string = '\t';

  /** 清洗单元格：制表符/换行替换为空格。 */
  private static cell(value: string): string {
    if (!value) {
      return '';
    }
    return value.replace(/[\t\r\n]/g, ' ');
  }

  /** 毫秒时间戳 → yyyy-MM-dd HH:mm:ss */
  private static formatTime(ts: number): string {
    if (!ts || ts <= 0) {
      return '';
    }
    const d: Date = new Date(ts);
    const p = (n: number): string => n < 10 ? '0' + n : '' + n;
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ` +
      `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  }

  private static fileCellValue(f: ScannedFile, key: string): string {
    switch (key) {
      case 'title': return f.title;
      case 'author': return f.author;
      case 'progress': return f.progress;
      case 'source': return f.source;
      case 'file_name': return f.fileName;
      case 'file_size': return FormatUtil.formatFileSize(f.fileSize);
      case 'file_path': return f.path;
      case 'encoding': return f.encoding;
      case 'ext': return f.ext;
      case 'file_date': return ListExportUtil.formatTime(f.fileDate);
      case 'created_at': return ListExportUtil.formatTime(f.createdAt);
      case 'marked': return f.marked === 1 ? '已标记' : '未标记';
      case 'checked': return f.checked === 1 ? '已勾选' : '未勾选';
      default: return '';
    }
  }

  private static groupCellValue(g: GroupInfo, key: string): string {
    switch (key) {
      case 'title': return g.title ? g.title : '未解析';
      case 'file_count': return `${g.fileCount}`;
      case 'total_size': return FormatUtil.formatFileSize(g.totalSize);
      case 'checked_count': return `${g.checkedCount}`;
      default: return '';
    }
  }

  /** 生成列表模式的 TXT 内容（含表头行）。 */
  static buildFilesText(files: ScannedFile[], selectedKeys: string[]): string {
    const cols: ExportColumn[] = ListExportUtil.FILE_COLUMNS.filter((c) => selectedKeys.includes(c.key));
    if (cols.length === 0) {
      return '';
    }
    const lines: string[] = [];
    lines.push(cols.map((c) => c.label).join(ListExportUtil.SEP));
    files.forEach((f) => {
      lines.push(cols.map((c) => ListExportUtil.cell(ListExportUtil.fileCellValue(f, c.key)))
        .join(ListExportUtil.SEP));
    });
    return lines.join('\n') + '\n';
  }

  /** 生成合集模式的 TXT 内容（含表头行）。 */
  static buildGroupsText(groups: GroupInfo[], selectedKeys: string[]): string {
    const cols: ExportColumn[] = ListExportUtil.GROUP_COLUMNS.filter((c) => selectedKeys.includes(c.key));
    if (cols.length === 0) {
      return '';
    }
    const lines: string[] = [];
    lines.push(cols.map((c) => c.label).join(ListExportUtil.SEP));
    groups.forEach((g) => {
      lines.push(cols.map((c) => ListExportUtil.cell(ListExportUtil.groupCellValue(g, c.key)))
        .join(ListExportUtil.SEP));
    });
    return lines.join('\n') + '\n';
  }

  /** 生成默认文件名，如 书库列表_20260802_143012.txt */
  static buildFileName(isGroupMode: boolean): string {
    const d: Date = new Date();
    const p = (n: number): string => n < 10 ? '0' + n : '' + n;
    const stamp: string = `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_` +
      `${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
    return (isGroupMode ? '合集列表_' : '书库列表_') + stamp + '.txt';
  }
}
