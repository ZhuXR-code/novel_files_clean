/**
 * 关键词替换规则，对齐安卓端 KeywordReplaceRuleEntity。
 * scope: "scan" 扫描阶段作用于文件名；"parse" 解析阶段作用于 书名/作者/进度/来源。
 */
export class KeywordReplaceRule {
  id: number = 0;
  scope: string = 'scan';
  pattern: string = '';
  replacement: string = '';
  sortOrder: number = 0;
  enabled: boolean = true;
  createdAt: number = 0;
}
