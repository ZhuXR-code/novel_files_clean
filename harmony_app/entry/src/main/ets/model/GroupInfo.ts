/**
 * 合集（按书名分组）的聚合信息，用于合集模式分页展示。
 * 对齐安卓端 NovelGroup：仅含标题、文件数、总大小、已勾选数。
 * 注：本工程 UI 通过重建 @State 数组（groupItems）引用触发刷新，未使用 @ObjectLink 绑定实例，
 * 故此处保持普通 class（避免依赖特定 SDK 版本的状态管理装饰器导出）。
 */
export class GroupInfo {
  title: string = '';
  fileCount: number = 0;
  totalSize: number = 0;
  checkedCount: number = 0;
}
