/**
 * 去重规则配置，对齐安卓端 DupRuleConfigEntity。
 * 既有 6 条内置规则（isBuiltin=1，ruleKey=rule1..rule5），也支持用户自定义规则（isBuiltin=0，ruleKey 为空）。
 * conditions 为 JSON 数组：[{"field":"file_name","op":"contains","value":""}, ...]
 * action：check=命中则勾选；protect=命中则保护（不勾选）。
 */
export class DupRuleConfig {
  id: number = 0;
  ruleKey: string = '';
  ruleName: string = '';
  description: string = '';
  conditions: string = '[]';
  action: string = 'check';
  isBuiltin: number = 0;
  enabled: number = 1;
  sortOrder: number = 0;
}
