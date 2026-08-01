/**
 * 复刻“勾选重复”逻辑所需的轻量投影，对齐安卓端 DuplicateRow。
 * id / fileName / title / author / progress / fileSize / createdAt / fileDate。
 */
export class DuplicateRow {
  id: number = 0;
  fileName: string = '';
  title: string = '';
  author: string = '';
  progress: string = '';
  source: string = '';
  fileSize: number = 0;
  createdAt: number = 0;
  /** 文件在文件系统中的最后修改时间（毫秒时间戳）。判断“新旧”时优先使用，避免扫描入库顺序干扰。 */
  fileDate: number = 0;
}
