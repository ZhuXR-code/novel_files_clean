import { relationalStore } from '@kit.ArkData';
import { RdbHelper } from './RdbHelper';
import { DupRuleConfig } from '../model/DupRuleConfig';
import { LogUtil } from '../utils/LogUtil';

/**
 * 去重规则配置的数据访问层，镜像安卓端 DupRuleConfigDao。
 */
export class DupRuleConfigDao {
  private static get store(): relationalStore.RdbStore {
    return RdbHelper.getExisting()!.getStore();
  }

  private static colStr(rs: relationalStore.ResultSet, col: string): string {
    const idx: number = rs.getColumnIndex(col);
    if (idx < 0) {
      return '';
    }
    try {
      return rs.getString(idx);
    } catch (e) {
      return '';
    }
  }

  private static colNum(rs: relationalStore.ResultSet, col: string): number {
    const idx: number = rs.getColumnIndex(col);
    if (idx < 0) {
      return 0;
    }
    try {
      return rs.getLong(idx);
    } catch (e) {
      return 0;
    }
  }

  private static toRule(rs: relationalStore.ResultSet): DupRuleConfig {
    const r: DupRuleConfig = new DupRuleConfig();
    r.id = DupRuleConfigDao.colNum(rs, 'id');
    r.ruleKey = DupRuleConfigDao.colStr(rs, 'rule_key');
    r.ruleName = DupRuleConfigDao.colStr(rs, 'rule_name');
    r.description = DupRuleConfigDao.colStr(rs, 'description');
    r.conditions = DupRuleConfigDao.colStr(rs, 'conditions');
    r.action = DupRuleConfigDao.colStr(rs, 'action');
    r.isBuiltin = DupRuleConfigDao.colNum(rs, 'is_builtin');
    r.enabled = DupRuleConfigDao.colNum(rs, 'enabled');
    r.sortOrder = DupRuleConfigDao.colNum(rs, 'sort_order');
    return r;
  }

  public static async createTable(): Promise<void> {
    await DupRuleConfigDao.store.executeSql(`
      CREATE TABLE IF NOT EXISTS dup_rule_config (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_key TEXT NOT NULL DEFAULT '',
        rule_name TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        conditions TEXT NOT NULL DEFAULT '[]',
        action TEXT NOT NULL DEFAULT 'check',
        is_builtin INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0
      )`);
  }

  public static async insertIfNotExists(rule: DupRuleConfig): Promise<void> {
    if (rule.ruleKey && rule.ruleKey.length > 0) {
      const existing: DupRuleConfig | null = await DupRuleConfigDao.getByRuleKey(rule.ruleKey);
      if (existing) {
        return;
      }
    }
    await DupRuleConfigDao.insert(rule);
  }

  public static async insert(rule: DupRuleConfig): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      rule_key: rule.ruleKey,
      rule_name: rule.ruleName,
      description: rule.description,
      conditions: rule.conditions,
      action: rule.action,
      is_builtin: rule.isBuiltin,
      enabled: rule.enabled,
      sort_order: rule.sortOrder
    };
    return await DupRuleConfigDao.store.insert('dup_rule_config', values);
  }

  public static async update(rule: DupRuleConfig): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      rule_name: rule.ruleName,
      description: rule.description,
      conditions: rule.conditions,
      action: rule.action,
      enabled: rule.enabled,
      sort_order: rule.sortOrder
    };
    const predicates = new relationalStore.RdbPredicates('dup_rule_config');
    predicates.equalTo('id', rule.id);
    await DupRuleConfigDao.store.update(values, predicates);
  }

  public static async delete(id: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('dup_rule_config');
    predicates.equalTo('id', id);
    await DupRuleConfigDao.store.delete(predicates);
  }

  public static async deleteAll(): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('dup_rule_config');
    await DupRuleConfigDao.store.delete(predicates);
  }

  public static async getAll(): Promise<DupRuleConfig[]> {
    const predicates = new relationalStore.RdbPredicates('dup_rule_config');
    predicates.orderByAsc('sort_order');
    predicates.orderByAsc('id');
    const rs = await DupRuleConfigDao.store.query(predicates);
    const list: DupRuleConfig[] = [];
    while (rs.goToNextRow()) {
      list.push(DupRuleConfigDao.toRule(rs));
    }
    rs.close();
    return list;
  }

  public static async getByRuleKey(ruleKey: string): Promise<DupRuleConfig | null> {
    const predicates = new relationalStore.RdbPredicates('dup_rule_config');
    predicates.equalTo('rule_key', ruleKey);
    const rs = await DupRuleConfigDao.store.query(predicates);
    let result: DupRuleConfig | null = null;
    if (rs.goToFirstRow()) {
      result = DupRuleConfigDao.toRule(rs);
    }
    rs.close();
    return result;
  }

  /**
   * 清理 rule_key 重复的行：每个 rule_key 只保留 id 最小的一条。
   * 用于修复早期因缺少 UNIQUE 约束、每次启动 seed 都重复插入内置规则的问题。
   * 自定义规则的 rule_key 为唯一随机串，不受影响。
   * 对齐安卓端 DupRuleConfigDao.dedupByKey()。
   */
  public static async dedupByKey(): Promise<void> {
    await DupRuleConfigDao.store.executeSql(
      `DELETE FROM dup_rule_config WHERE id NOT IN (SELECT MIN(id) FROM dup_rule_config GROUP BY rule_key)`
    );
  }

  public static async getEnabledBuiltinRuleKeys(): Promise<string[]> {
    const predicates = new relationalStore.RdbPredicates('dup_rule_config');
    predicates.equalTo('is_builtin', 1).and().equalTo('enabled', 1);
    predicates.orderByAsc('sort_order');
    const rs = await DupRuleConfigDao.store.query(predicates);
    const keys: string[] = [];
    while (rs.goToNextRow()) {
      keys.push(DupRuleConfigDao.colStr(rs, 'rule_key'));
    }
    rs.close();
    return keys;
  }

  public static async getEnabledUserRules(): Promise<DupRuleConfig[]> {
    const predicates = new relationalStore.RdbPredicates('dup_rule_config');
    predicates.equalTo('is_builtin', 0).and().equalTo('enabled', 1);
    predicates.orderByAsc('sort_order');
    const rs = await DupRuleConfigDao.store.query(predicates);
    const list: DupRuleConfig[] = [];
    while (rs.goToNextRow()) {
      list.push(DupRuleConfigDao.toRule(rs));
    }
    rs.close();
    return list;
  }

  public static async updateEnabled(id: number, enabled: number): Promise<void> {
    const values: relationalStore.ValuesBucket = { enabled: enabled };
    const predicates = new relationalStore.RdbPredicates('dup_rule_config');
    predicates.equalTo('id', id);
    await DupRuleConfigDao.store.update(values, predicates);
  }

  /**
   * 确保内置去重规则已写入数据库（幂等）。
   * 在 EntryAbility.onCreate 和页面 load() 时双重保障调用，防止因初始化时序问题导致页面为空。
   */
  public static async ensureBuiltinSeeded(): Promise<number> {
    let added: number = 0;
    const builtins: DupRuleConfig[] = [
      DupRuleConfigDao.makeBuiltin('rule1', '完全相等去重', '小说名+作者+进度+文件大小 完全一致视为重复', 1),
      DupRuleConfigDao.makeBuiltin('rule2', '数字进度对比', '有纯数字进度时，数字大者保留', 2),
      DupRuleConfigDao.makeBuiltin('rule3a', '中文进度/完结优先', '含中文进度或完结关键词者优先保留', 3),
      DupRuleConfigDao.makeBuiltin('rule3b', '番外特例', '完结+数字番外 按 N 最大保留', 4),
      DupRuleConfigDao.makeBuiltin('rule4', '大文件保护', '同组内文件最大者不勾选(保护)', 5),
      DupRuleConfigDao.makeBuiltin('rule5', '完结+番外覆盖', '完结+N番外 按 N 最大保留(覆盖规则3A)', 6)
    ];
    for (const r of builtins) {
      try {
        const existing: DupRuleConfig | null = await DupRuleConfigDao.getByRuleKey(r.ruleKey);
        if (!existing) {
          await DupRuleConfigDao.insert(r);
          added++;
        }
      } catch (e) {
        // 单条失败不阻断后续规则
      }
    }
    return added;
  }

  private static makeBuiltin(ruleKey: string, ruleName: string, description: string, sortOrder: number): DupRuleConfig {
    const r: DupRuleConfig = new DupRuleConfig();
    r.ruleKey = ruleKey;
    r.ruleName = ruleName;
    r.description = description;
    r.isBuiltin = 1;
    r.enabled = 1;
    r.sortOrder = sortOrder;
    r.action = 'check';
    r.conditions = '[]';
    return r;
  }
}
