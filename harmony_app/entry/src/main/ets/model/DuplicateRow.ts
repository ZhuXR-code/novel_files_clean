/**
 * 复刻“勾选重复”逻辑所需的轻量投影，对齐安卓端 DuplicateRow。
 * id / fileName / title / author / progress / fileSize / createdAt / fileDate / contentHash。
 * contentHash 用于「rule_hash 内容哈希去重」规则：哈希相同且非最新的文件额外勾选。
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
  /** 内容哈希（扫描时计算，可能为空）。rule_hash 内容哈希去重规则使用。 */
  contentHash: string = '';
}
