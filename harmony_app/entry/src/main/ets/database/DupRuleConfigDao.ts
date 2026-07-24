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
}
