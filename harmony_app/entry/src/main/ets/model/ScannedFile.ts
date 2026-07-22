/**
 * 扫描得到的单个文件记录，对齐安卓端 ScannedFileEntity。
 * 数据库表 scanned_file。
 */
export class ScannedFile {
  id: number = 0;
  path: string = '';
  fileName: string = '';
  fileSize: number = 0;
  title: string = '';
  author: string = '';
  progress: string = '';
  source: string = '';
  contentHash: string = '';
  ext: string = '';
  /** 是否已被用户手工标记（1/0） */
  marked: number = 0;
  /** 是否处于“待删除勾选”状态（1/0） */
  checked: number = 0;
  /** 所属文库（一次扫描）id */
  scanRunId: number = 0;
  createdAt: number = 0;
}
