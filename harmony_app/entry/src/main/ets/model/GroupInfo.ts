/**
 * 合集（按书名分组）的聚合信息，用于合集模式分页展示。
 * 对齐安卓端 NovelGroup：仅含标题、文件数、总大小、已勾选数。
 */
export class GroupInfo {
  title: string = '';
  fileCount: number = 0;
  totalSize: number = 0;
  checkedCount: number = 0;
}
