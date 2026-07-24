import { KeywordReplaceRule } from '../model/KeywordReplaceRule';

/**
 * 关键词替换工具，完整对齐安卓端 util/KeywordReplace.kt 与 PC 端 backend/keyword_replace.py。
 *
 * applyRules：按规则顺序对文本依次执行【字面量】精确字符串替换
 * （pattern 命中即整段替换为 replacement，空串=删除）。
 * 使用 split/join 实现字面量替换（对齐 Kotlin String.replace 的语义），
 * 避免把规则里的正则元字符误当正则、也避免 replacement 中的 $ 被特殊解释。
 */
export class KeywordReplace {
  public static readonly SCOPE_SCAN: string = 'scan'; // 扫描阶段：作用于文件名
  public static readonly SCOPE_PARSE: string = 'parse'; // 解析阶段：作用于 书名/作者/进度/来源

  public static applyRules(text: string | null, rules: KeywordReplaceRule[]): string | null {
    if (text === null || text.length === 0 || rules.length === 0) {
      return text;
    }
    let result: string = text;
    for (const r of rules) {
      const p: string = r.pattern;
      if (p && p.length > 0) {
        result = result.split(p).join(r.replacement);
      }
    }
    return result;
  }

  /**
   * 预置默认关键词替换规则（作用域=扫描阶段，作用于文件名）。
   * 用于去除网文 txt 文件名上常见的平台水印/标记（如 [草2莓]、【lili】 等），
   * 减少用户手动配置工作量。首次启动时由 EntryAbility 按 pattern 幂等补齐；
   * 后续新增预置项也会自动补进已安装实例，无需清数据。
   */
  public static readonly DEFAULT_KEYWORD_RULES: KeywordReplaceRule[] = [
    KeywordReplace.rule('scan', '[草2莓]', '', 1),
    KeywordReplace.rule('scan', '【草2莓', '', 2),
    KeywordReplace.rule('scan', '【草2莓】', '', 3),
    KeywordReplace.rule('scan', '[草 莓]', '', 4),
    KeywordReplace.rule('scan', '[草 莓', '', 5),
    KeywordReplace.rule('scan', '【lili】', '', 6),
    KeywordReplace.rule('scan', '（l.i.）', '', 7),
    KeywordReplace.rule('scan', '(l.i.）', '', 8),
    KeywordReplace.rule('scan', '（l.i.)', '', 9),
    KeywordReplace.rule('scan', '(l.i.)', '', 10),
    // —— 以下为 caomei / 3167 937770 水印系列及扩展名修正（与 PC/安卓端同步）——
    // 顺序约定：① 含「の企鹅3167 937770」的完整变体须先于裸「の企鹅3167 937770」；
    // ② 成对括号变体须先于只去开头括号的变体，避免残留孤立前缀/括号。
    KeywordReplace.rule('scan', '..txt', '.txt', 11),
    KeywordReplace.rule('scan', '【草莓】', '', 12),
    KeywordReplace.rule('scan', '【草 莓', '', 13),
    KeywordReplace.rule('scan', '【＋V信kxee6699】', '', 14),
    KeywordReplace.rule('scan', '.3167 937770', '', 15),
    KeywordReplace.rule('scan', '【颜3167 937770', '', 16),
    KeywordReplace.rule('scan', '【Q主caomeiの企鹅3167 937770】', '', 17),
    KeywordReplace.rule('scan', '【Q主caomei】', '', 18),
    KeywordReplace.rule('scan', '_caomeiの企鹅3167 937770_', '', 19),
    KeywordReplace.rule('scan', '（caomeiの企鹅3167 937770', '', 20),
    KeywordReplace.rule('scan', '(caomeiの企鹅3167 937770', '', 21),
    KeywordReplace.rule('scan', '【qzcaomeiの企鹅3167 937770', '', 22),
    KeywordReplace.rule('scan', '.QZcaomeiの企鹅3167 937770', '', 23),
    KeywordReplace.rule('scan', '_caomeiの企鹅3167 937770', '', 24),
    KeywordReplace.rule('scan', '.caomeiの企鹅3167 937770', '', 25),
    KeywordReplace.rule('scan', 'の企鹅3167 937770', '', 26),
    KeywordReplace.rule('scan', '[3167 937770]', '', 27),
    KeywordReplace.rule('scan', '[3167 937770', '', 28),
    KeywordReplace.rule('scan', '3167937770', '', 29),
    KeywordReplace.rule('scan', '_3167 937770', '', 30),
    KeywordReplace.rule('scan', '（颜3167 937770', '', 31),
    KeywordReplace.rule('scan', '【3167 937770]', '', 32),
    KeywordReplace.rule('scan', '_.txt', '.txt', 33),
    // —— 与 Android 端同步的默认替换规则 ——
    KeywordReplace.rule('scan', '【YLW】', '', 34),
    KeywordReplace.rule('scan', '『推』', '', 35),
    KeywordReplace.rule('scan', '【昭昭明月BG】', '', 36),
    KeywordReplace.rule('scan', '【昭昭明月BL】', '', 37),
    KeywordReplace.rule('scan', '【推荐】', '', 38),
    KeywordReplace.rule('scan', '【全本校对】', '', 39),
    KeywordReplace.rule('scan', '【全本精校】', '', 40),
    KeywordReplace.rule('scan', '【BL】', '', 41),
    KeywordReplace.rule('scan', '【BG】', '', 42),
    KeywordReplace.rule('scan', '【YLW连载】', '', 43),
    KeywordReplace.rule('scan', '【棠】', '', 44),
    KeywordReplace.rule('scan', '【公众号：推文日记】', '', 45),
    KeywordReplace.rule('scan', '【书香门第★九落】', '', 46)
  ];

  private static rule(scope: string, pattern: string, replacement: string, sortOrder: number): KeywordReplaceRule {
    const r: KeywordReplaceRule = new KeywordReplaceRule();
    r.scope = scope;
    r.pattern = pattern;
    r.replacement = replacement;
    r.sortOrder = sortOrder;
    r.enabled = true;
    r.createdAt = Date.now();
    return r;
  }
}
