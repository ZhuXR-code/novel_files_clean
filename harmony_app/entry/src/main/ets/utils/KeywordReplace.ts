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
    KeywordReplace.rule('scan', '(l.i.)', '', 10)
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
