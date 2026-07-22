/**
 * 复刻“标记重复”逻辑所需的轻量投影，对齐安卓端 DuplicateRow。
 * id / fileName / title / author / progress / fileSize / createdAt。
 */
export class DuplicateRow {
  id: number = 0;
  fileName: string = '';
  title: string = '';
  author: string = '';
  progress: string = '';
  fileSize: number = 0;
  createdAt: number = 0;
}
