/**
 * 扫描配置，对齐安卓端 ScanConfigEntity。
 * folderUri 保存通过 DocumentViewPicker 选中的目录 URI（已授权），
 * folderName 仅用于界面反显，不参与扫描。
 */
export class ScanConfig {
  id: number = 0;
  name: string = '';
  folderUri: string = '';
  folderName: string = '';
  fileTypes: string = 'txt';
  minSizeKb: number = 0;
  recursive: boolean = true;
  exactHash: boolean = false;
  excludedFolders: string = '';
}
