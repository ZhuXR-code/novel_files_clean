/**
 * 合集（按书名分组）的聚合信息，用于合集模式分页展示。
 * 对齐安卓端 NovelGroup：仅含标题、文件数、总大小、已勾选数。
 * @Observed 使 checkedCount/fileCount 等属性变化能驱动使用了 @ObjectLink 的 UI 重渲染。
 */
@Observed
export class GroupInfo {
  title: string = '';
  fileCount: number = 0;
  totalSize: number = 0;
  checkedCount: number = 0;
}
