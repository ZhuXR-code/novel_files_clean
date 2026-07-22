/**
 * 一次扫描对应一个“文库”，对齐安卓端 ScanRunEntity。
 * 每次启动扫描新建一条记录，本次扫到的全部文件以 scanRunId 关联回它。
 */
export class ScanRun {
  id: number = 0;
  name: string = '';
  folderUri: string = '';
  folderName: string = '';
  fileTypes: string = 'txt';
  createdAt: number = 0;
  fileCount: number = 0;
}
