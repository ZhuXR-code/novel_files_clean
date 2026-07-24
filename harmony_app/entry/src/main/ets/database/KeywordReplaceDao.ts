import { relationalStore } from '@kit.ArkData';
import { RdbHelper } from './RdbHelper';
import { KeywordReplaceRule } from '../model/KeywordReplaceRule';

/**
 * 关键词替换规则访问层，镜像安卓端 KeywordReplaceDao。
 */
export class KeywordReplaceDao {
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

  private static toRule(rs: relationalStore.ResultSet): KeywordReplaceRule {
    const r: KeywordReplaceRule = new KeywordReplaceRule();
    r.id = KeywordReplaceDao.colNum(rs, 'id');
    r.scope = KeywordReplaceDao.colStr(rs, 'scope');
    r.pattern = KeywordReplaceDao.colStr(rs, 'pattern');
    r.replacement = KeywordReplaceDao.colStr(rs, 'replacement');
    r.sortOrder = KeywordReplaceDao.colNum(rs, 'sort_order');
    r.enabled = KeywordReplaceDao.colNum(rs, 'enabled') === 1;
    r.createdAt = KeywordReplaceDao.colNum(rs, 'created_at');
    return r;
  }

  public static toValues(r: KeywordReplaceRule): relationalStore.ValuesBucket {
    return {
      scope: r.scope,
      pattern: r.pattern,
      replacement: r.replacement,
      sort_order: r.sortOrder,
      enabled: r.enabled ? 1 : 0,
      created_at: r.createdAt
    };
  }

  public static async insert(rule: KeywordReplaceRule): Promise<number> {
    return await KeywordReplaceDao.store.insert('keyword_replace_rules', KeywordReplaceDao.toValues(rule));
  }

  public static async update(rule: KeywordReplaceRule): Promise<void> {
    const values: relationalStore.ValuesBucket = KeywordReplaceDao.toValues(rule);
    const predicates = new relationalStore.RdbPredicates('keyword_replace_rules');
    predicates.equalTo('id', rule.id);
    await KeywordReplaceDao.store.update(values, predicates);
  }

  public static async delete(id: number): Promise<void> {
    const predicates = new relationalStore.RdbPredicates('keyword_replace_rules');
    predicates.equalTo('id', id);
    await KeywordReplaceDao.store.delete(predicates);
  }

  public static async getById(id: number): Promise<KeywordReplaceRule | null> {
    const predicates = new relationalStore.RdbPredicates('keyword_replace_rules');
    predicates.equalTo('id', id);
    const rs = await KeywordReplaceDao.store.query(predicates);
    let result: KeywordReplaceRule | null = null;
    if (rs.goToFirstRow()) {
      result = KeywordReplaceDao.toRule(rs);
    }
    rs.close();
    return result;
  }

  public static async getAll(): Promise<KeywordReplaceRule[]> {
    const predicates = new relationalStore.RdbPredicates('keyword_replace_rules');
    predicates.orderByAsc('sort_order');
    const rs = await KeywordReplaceDao.store.query(predicates);
    const list: KeywordReplaceRule[] = [];
    while (rs.goToNextRow()) {
      list.push(KeywordReplaceDao.toRule(rs));
    }
    rs.close();
    return list;
  }

  /** 解析阶段使用的已启用规则，按 scope 过滤。 */
  public static async getEnabledByScope(scope: string): Promise<KeywordReplaceRule[]> {
    const predicates = new relationalStore.RdbPredicates('keyword_replace_rules');
    predicates.equalTo('scope', scope).and().equalTo('enabled', 1);
    predicates.orderByAsc('sort_order');
    const rs = await KeywordReplaceDao.store.query(predicates);
    const list: KeywordReplaceRule[] = [];
    while (rs.goToNextRow()) {
      list.push(KeywordReplaceDao.toRule(rs));
    }
    rs.close();
    return list;
  }

  public static async count(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates('keyword_replace_rules');
    return await KeywordReplaceDao.store.query(predicates).then((rs) => {
      const c = rs.rowCount;
      rs.close();
      return c;
    });
  }

  /**
   * 按 scope + pattern 统计是否存在，用于默认规则幂等补齐。
   */
  public static async countByScopeAndPattern(scope: string, pattern: string): Promise<number> {
    const predicates = new relationalStore.RdbPredicates('keyword_replace_rules');
    predicates.equalTo('scope', scope).and().equalTo('pattern', pattern);
    return await KeywordReplaceDao.store.query(predicates).then((rs) => {
      const c = rs.rowCount;
      rs.close();
      return c;
    });
  }

  /**
   * 统计全部规则条数，供管理后台/统计页使用。
   */
  public static async countAll(): Promise<number> {
    const sql: string = 'SELECT COUNT(*) AS c FROM keyword_replace_rules';
    const rs = await KeywordReplaceDao.store.querySql(sql, []);
    let n: number = 0;
    if (rs.goToFirstRow()) {
      n = KeywordReplaceDao.colNum(rs, 'c');
    }
    rs.close();
    return n;
  }

  /**
   * 某作用域当前最大 sort_order，新规则默认追加到末尾。
   */
  public static async maxSortOrder(scope: string): Promise<number> {
    const sql: string = 'SELECT COALESCE(MAX(sort_order), 0) AS max_so FROM keyword_replace_rules WHERE scope = ?';
    const rs = await KeywordReplaceDao.store.querySql(sql, [scope]);
    let result: number = 0;
    if (rs.goToNextRow()) {
      result = KeywordReplaceDao.colNum(rs, 'max_so');
    }
    rs.close();
    return result;
  }

  /**
   * 新建（id=0）插入，编辑（带原 id）更新。
   */
  public static async upsert(rule: KeywordReplaceRule): Promise<number> {
    if (rule.id > 0) {
      await KeywordReplaceDao.update(rule);
      return rule.id;
    } else {
      return await KeywordReplaceDao.insert(rule);
    }
  }

  public static async setEnabled(id: number, enabled: boolean): Promise<void> {
    const values: relationalStore.ValuesBucket = { enabled: enabled ? 1 : 0 };
    const predicates = new relationalStore.RdbPredicates('keyword_replace_rules');
    predicates.equalTo('id', id);
    await KeywordReplaceDao.store.update(values, predicates);
  }
}
