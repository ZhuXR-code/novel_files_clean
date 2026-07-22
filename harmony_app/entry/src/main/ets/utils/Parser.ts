import { ParsedName } from '../model/ParsedName';

/**
 * 文件名解析工具，完整对齐安卓端 util/Parser.kt 当前优化版本：
 * 仅基于文件名解析 书名 / 作者 / 进度 / 来源，不读取文件内容。
 * 正则与命中顺序与安卓端逐一对应，请勿擅自调整顺序。
 *
 * 相对旧版鸿蒙实现的改进（来自安卓端本次优化）：
 *  1) 书名/作者正则兼容"作家"与"作者"两种前缀；
 *  2) 标签识别同时支持中文方括号【】、英文方括号[]、全角/半角圆括号（）()；
 *  3) 作者尾部清洗新增"更新至N / 补番 / 修" 三类残留剥离；
 *  4) extractSourceProgress 新增"番外"与"更新至N"兜底进度识别；
 *  5) 新增 cleanTitle 清洗书名开头残留标签。
 */
export class Parser {
  private static readonly SOURCE_SITES: string[] = [
    '废文', '海棠', 'fw', 'ht', '米国度', '米国', '晋江', '长佩', '刺猬猫', '豆腐',
    '老福特', '息壤', '粉笔', '鲜网', '绿茶', '寒武纪', '不可能的世界', '豆瓣阅读',
    '掌阅', '番茄', '起点', '飞卢', '纵横', '17K', '黑岩', '云起', '红袖', '潇湘书院',
    '阅文', 'LOFTER', 'lofter', 'Po18', 'po18', 'FW', 'HT'
  ];

  private static readonly CN_REGEX: RegExp = /[一-龥]/;

  // ============ 书名/作者 正则（命中即返回，顺序与安卓端一致） ============
  private static readonly RE_BOOK_AUTHOR: RegExp = /《([^》]+)》.*?(?:作家|作者)[：:]\s*(.+)/;
  private static readonly RE_BOOK_BY: RegExp = /《([^》]+)》.*?[bB][yY]\s*(.+)/;
  private static readonly RE_BOOK_AUTHOR2: RegExp = /《(.+?)》\s*(?:作家|作者)[：:]\s*(.+)/;
  private static readonly RE_TAG_BOOK_AUTHOR: RegExp = /【[^】]+】\s*《(.+?)》\s*(?:作家|作者)[：:]\s*(.+)/;
  private static readonly RE_BOOK_BY2: RegExp = /《(.+?)》\s*[bB][yY]\s*(.+)/;
  private static readonly RE_NAME_BY: RegExp = /^(.+?)\s+[bB][yY]\s+(.+)/;
  private static readonly RE_NAME_AUTHOR: RegExp = /^(.+?)[_\-—]\s*(?:作家|作者)[：:]?\s*(.+)/;
  // 同时支持【】、[]、（）、() 做前缀标签
  private static readonly RE_TAG_NAME_BY: RegExp = /^[【\[（(][^】\]）)\n]+[】\]）)]\s*(.+?)\s*[bB][yY]\s*(.+)/;
  private static readonly RE_TAG_NAME_AUTHOR: RegExp = /^[【\[（(][^】\]）)\n]+[】\]）)]\s*(.+?)\s*(?:作家|作者)[：:]\s*(.+)/;
  private static readonly RE_TAG_NAME_ONLY: RegExp = /^[【\[（(][^】\]）)\n]+[】\]）)]\s*(.+)/;
  private static readonly RE_NAME_BY2: RegExp = /^(.+?)\s*[bB][yY]\s*(.+)/;
  private static readonly RE_BRACKET_NAME_AUTHOR: RegExp = /\[[^\]]+\]\s*(.+?)\s*(?:作家|作者)[：:]\s*(.+)/;
  private static readonly RE_NAME_AUTHOR2: RegExp = /^(.+?)\s*(?:作家|作者)[：:]\s*(.+)/;
  private static readonly RE_OPT_TAG_BOOK_AUTHOR: RegExp = /^(?:\[.*?\])?\s*《(.+?)》\s*(?:作家|作者)\s*(.+?)/;
  private static readonly RE_BOOK_ONLY: RegExp = /《(.+?)》/;
  private static readonly RE_TITLE_PAREN_VER: RegExp = /^(.+?)\s*[（(]\s*[\w\-]+(?:\.[\w\-]+)+\s*[）)]\s*$/;
  private static readonly RE_CATEGORY: RegExp = /^(?:BG|BL|GL|GB|DM|言情|耽美|百合|同人|原创|武侠|玄幻|古言|现言|仙侠|科幻|悬疑|惊悚|轻小说|海棠|popo|废文|po18|SF)\s*(.+?)[_\-—](.+)/;
  private static readonly RE_DASH_UNDER: RegExp = /^(.+?)[_\-—](.+?)/;
  private static readonly RE_TITLE_BRACKET_END: RegExp = /^(.+?)\s*\[([^\]]+)\]\s*$/;

  // 作者后缀清洗（支持【】、[]、（）、()）
  private static readonly AUTHOR_TRAIL_BRACKET: RegExp = /\s*[\[（(【][^\]）)】]*?(?:\d+|[更完结番外npv1V]+)[^\]）)】]*?[\]）)】]\s*$/;
  private static readonly AUTHOR_TRAIL_DASH_NUM: RegExp = /\s*-\d+\s*$/;
  // 作者尾部"更新至N / --更新至N / -更新至N"清洗，进度交由 extractSourceProgress 提取
  private static readonly AUTHOR_TRAIL_UPDATE: RegExp = /\s*[-—~]*更新至?\s*\d+\s*$/;
  // 作者尾部"补番 / ~补番"等补缺番标记清洗
  private static readonly AUTHOR_TRAIL_BUFAN: RegExp = /\s*[-—~]?补番\s*$/;
  // 作者尾部"【修】/（修）"修订标记清洗
  private static readonly AUTHOR_TRAIL_REVISE: RegExp = /\s*[【\[（(]修[】\]）)]\s*$/;
  // 仅用于“书名 作者：xxx”场景的后缀（完结/番外/连载…），以及作者尾部残留的“精校/校对”等清洗
  private static readonly AUTHOR_SUFFIX_STATUS: RegExp = /\s*(?:完结|番外|全本|完本|连载|出版|实体书|定制书|定制|校对|精校).*$/;
  private static readonly AUTHOR_TRAIL_PAREN_NUM: RegExp = /\s*[（(]\d+[）)]\s*$/;
  private static readonly AUTHOR_TRAIL_PAREN_ANY: RegExp = /[\s（(]*[）)]\s*$/;
  private static readonly AUTHOR_TRAIL_PAREN_LEFT: RegExp = /[\s（(]*$/;

  private static readonly LATIN4: RegExp = /[a-zA-Z]{4,}/;
  private static readonly KEYWORD_BLOCK: RegExp = /(?:试阅|请勿|版权|删[除文]|二传|商业|仅供|公告|下载|通知|说明|使用|帮助|README|changelog|免责|侵权|联系|QQ|微信|公众号|微博)/i;

  // 热路径内联正则
  private static readonly RE_ONLY_NUM_SYM: RegExp = /^[0-9\s.\-_#@!*&]+$/;
  private static readonly RE_HAS_LATIN: RegExp = /[a-zA-Z]/;
  private static readonly RE_BRACKET_SQ: RegExp = /\[([^\]]*)\]/g;
  private static readonly RE_BRACKET_CN: RegExp = /【([^】]*)】/g;
  private static readonly RE_BRACKET_PAREN_CN: RegExp = /（([^）]*)）/g;
  private static readonly RE_BRACKET_PAREN: RegExp = /\(([^)]*)\)/g;
  private static readonly RE_TAIL_NUM: RegExp = /-(\d+)\s*$/;
  private static readonly RE_PROGRESS_GENG: RegExp = /更\s*(\d+)/;
  private static readonly RE_PROGRESS_WAN: RegExp = /完结[^\]\s]*/;
  private static readonly RE_PROGRESS_STATUS: RegExp = /(?:连载|断更|暂停|烂尾|坑|锁文|锁)/;
  // 番外标记（如【番外合集】、（番外）），用于从方括号标签提取进度
  private static readonly RE_PROGRESS_FANWAI: RegExp = /番外[^\]\s]*/;
  // “更新至N”形式的进度兜底（常出现在作者名后缀）
  private static readonly RE_PROGRESS_UPDATE: RegExp = /更新至?\s*(\d+)/;

  private static readonly LEAD_TAG: RegExp = /^[【\[（(][^】\]）)]*[】\]）)]\s*/;

  /** 从文件名（不含扩展名）解析出 书名 / 作者 / 进度 / 来源。 */
  public static parseFileName(rawName: string): ParsedName {
    let name: string = rawName;
    const dot: number = name.lastIndexOf('.');
    if (dot > 0) {
      name = name.substring(0, dot);
    }
    name = name.trim();
    const result: ParsedName = new ParsedName();
    if (name.length === 0) {
      result.title = rawName;
      return result;
    }
    const ta: { title: string; author: string } = Parser.parseTitleAuthor(name);
    const sp: { source: string; progress: string } = Parser.extractSourceProgress(name);
    result.title = Parser.cleanTitle(ta.title);
    result.author = ta.author;
    result.progress = sp.progress;
    result.source = sp.source;
    return result;
  }

  private static cleanTitle(raw: string): string {
    let t: string = raw.trim();
    while (true) {
      const m: RegExpExecArray | null = Parser.LEAD_TAG.exec(t);
      if (!m) {
        break;
      }
      t = t.substring(m[0].length);
    }
    return t.trim();
  }

  private static parseTitleAuthor(name: string): { title: string; author: string } {
    let m: RegExpExecArray | null;

    m = Parser.RE_BOOK_AUTHOR.exec(name);
    if (m) {
      return { title: m[1].trim(), author: Parser.cleanAuthor(m[2]) };
    }
    m = Parser.RE_BOOK_BY.exec(name);
    if (m) {
      return { title: m[1].trim(), author: Parser.cleanAuthor(m[2]) };
    }
    m = Parser.RE_BOOK_AUTHOR2.exec(name);
    if (m) {
      return { title: m[1].trim(), author: Parser.cleanAuthor(m[2]) };
    }
    m = Parser.RE_TAG_BOOK_AUTHOR.exec(name);
    if (m) {
      return { title: m[1].trim(), author: Parser.cleanAuthor(m[2]) };
    }
    m = Parser.RE_BOOK_BY2.exec(name);
    if (m) {
      return { title: m[1].trim(), author: Parser.cleanAuthor(m[2]) };
    }
    m = Parser.RE_NAME_BY.exec(name);
    if (m) {
      return { title: m[1].trim(), author: Parser.cleanAuthor(m[2]) };
    }
    m = Parser.RE_NAME_AUTHOR.exec(name);
    if (m) {
      return { title: m[1].trim(), author: Parser.cleanAuthor(m[2]) };
    }
    m = Parser.RE_TAG_NAME_BY.exec(name);
    if (m) {
      return { title: m[1].trim(), author: Parser.cleanAuthor(m[2]) };
    }
    m = Parser.RE_TAG_NAME_AUTHOR.exec(name);
    if (m) {
      return { title: m[1].trim(), author: Parser.cleanAuthor(m[2]) };
    }
    m = Parser.RE_TAG_NAME_ONLY.exec(name);
    if (m) {
      const t: string = m[1].trim();
      if (t.length >= 2 && !Parser.RE_ONLY_NUM_SYM.test(t) && !t.includes('作者') && !t.includes('《')) {
        return { title: t, author: '' };
      }
    }
    m = Parser.RE_NAME_BY2.exec(name);
    if (m) {
      const t: string = m[1].trim();
      const a: string = m[2].trim();
      if (!t.startsWith('【') && !t.startsWith('(') && !t.startsWith('[')) {
        return { title: t, author: Parser.stripAuthor(a) };
      }
    }
    m = Parser.RE_BRACKET_NAME_AUTHOR.exec(name);
    if (m) {
      return { title: m[1].trim(), author: Parser.cleanAuthor(m[2]) };
    }
    m = Parser.RE_NAME_AUTHOR2.exec(name);
    if (m) {
      const t: string = m[1].trim();
      let a: string = m[2].trim();
      a = a.replace(Parser.AUTHOR_SUFFIX_STATUS, '').trim();
      return { title: t, author: Parser.stripAuthor(a) };
    }
    m = Parser.RE_OPT_TAG_BOOK_AUTHOR.exec(name);
    if (m) {
      const t: string = m[1].trim();
      const a: string = m[2].trim();
      if (t.length >= 2 && a.length >= 2) {
        return { title: t, author: Parser.stripAuthor(a) };
      }
    }
    m = Parser.RE_BOOK_ONLY.exec(name);
    if (m) {
      return { title: m[1].trim(), author: '' };
    }
    m = Parser.RE_TITLE_PAREN_VER.exec(name);
    if (m) {
      return { title: m[1].trim(), author: '' };
    }
    m = Parser.RE_CATEGORY.exec(name);
    if (m) {
      const t: string = m[1].trim();
      let a: string = m[2].trim();
      a = a.replace(Parser.AUTHOR_TRAIL_PAREN_NUM, '').trim();
      if (t.length >= 2) {
        return { title: t, author: Parser.stripAuthor(a) };
      }
    }
    m = Parser.RE_DASH_UNDER.exec(name);
    if (m) {
      const t: string = m[1].trim();
      let a: string = m[2].trim();
      a = a.replace(Parser.AUTHOR_TRAIL_PAREN_ANY, '');
      a = a.replace(Parser.AUTHOR_TRAIL_PAREN_NUM, '');
      a = a.replace(Parser.AUTHOR_TRAIL_PAREN_LEFT, '');
      const hasCnT: boolean = Parser.CN_REGEX.test(t);
      const hasCnA: boolean = Parser.CN_REGEX.test(a);
      const hasLatinA: boolean = Parser.RE_HAS_LATIN.test(a);
      if (hasCnT && t.length >= 2 && a.length >= 2 && (hasCnA || hasLatinA)) {
        return { title: t, author: Parser.stripAuthor(a) };
      }
    }
    m = Parser.RE_TITLE_BRACKET_END.exec(name);
    if (m) {
      const t: string = m[1].trim();
      if (t.length >= 2) {
        return { title: t, author: '' };
      }
    }
    // 兜底：整段基本是中文且无英文长词、非说明类文件，则整段视为书名
    if (!Parser.LATIN4.test(name)) {
      const cnMatches: RegExpMatchArray | null = name.match(/[一-龥]/g);
      const cnCount: number = cnMatches ? cnMatches.length : 0;
      if (cnCount >= 2 && name.length <= 60 && !Parser.KEYWORD_BLOCK.test(name)) {
        return { title: name.trim(), author: '' };
      }
    }
    return { title: '', author: '' };
  }

  /** 作者清洗：去掉“著/作者/作家：/:”前缀，并清掉尾部残留。 */
  private static cleanAuthor(raw: string): string {
    let a: string = raw.trim();
    if (a.startsWith('著')) {
      a = a.substring(1);
    }
    if (a.startsWith('作者')) {
      a = a.substring(2);
    }
    if (a.startsWith('作家')) {
      a = a.substring(2);
    }
    a = a.trim();
    if (a.startsWith('：')) {
      a = a.substring(1);
    }
    if (a.startsWith(':')) {
      a = a.substring(1);
    }
    a = a.trim();
    return Parser.stripAuthor(a);
  }

  /** 作者尾部清洗：循环剥离末尾括号（含数字/进度词）与状态后缀，直到不再变化。 */
  private static stripAuthor(raw: string): string {
    let a: string = raw.trim();
    for (let i = 0; i < 6; i++) {
      const before: string = a;
      a = a.replace(Parser.AUTHOR_TRAIL_BRACKET, '').trim();
      a = a.replace(Parser.AUTHOR_SUFFIX_STATUS, '').trim();
      a = a.replace(Parser.AUTHOR_TRAIL_DASH_NUM, '').trim();
      a = a.replace(Parser.AUTHOR_TRAIL_UPDATE, '').trim();
      a = a.replace(Parser.AUTHOR_TRAIL_BUFAN, '').trim();
      a = a.replace(Parser.AUTHOR_TRAIL_REVISE, '').trim();
      if (a === before) {
        break;
      }
    }
    return a;
  }

  /** 取最后一个点之前的部分（无点则返回原串）。 */
  private static beforeLastDot(s: string): string {
    const idx: number = s.lastIndexOf('.');
    return idx > 0 ? s.substring(0, idx) : s;
  }

  /** 从文件名方括号/圆括号标签提取 来源站点 与 更新进度。 */
  private static extractSourceProgress(name: string): { source: string; progress: string } {
    const base: string = Parser.beforeLastDot(name);
    const brackets: string[] = [];
    let mm: RegExpExecArray | null;
    Parser.RE_BRACKET_SQ.lastIndex = 0;
    while ((mm = Parser.RE_BRACKET_SQ.exec(base)) !== null) {
      brackets.push(mm[1]);
    }
    Parser.RE_BRACKET_CN.lastIndex = 0;
    while ((mm = Parser.RE_BRACKET_CN.exec(base)) !== null) {
      brackets.push(mm[1]);
    }
    Parser.RE_BRACKET_PAREN_CN.lastIndex = 0;
    while ((mm = Parser.RE_BRACKET_PAREN_CN.exec(base)) !== null) {
      brackets.push(mm[1]);
    }
    Parser.RE_BRACKET_PAREN.lastIndex = 0;
    while ((mm = Parser.RE_BRACKET_PAREN.exec(base)) !== null) {
      brackets.push(mm[1]);
    }

    let source: string = '';
    let progress: string = '';
    if (brackets.length === 0) {
      const tail: RegExpExecArray | null = Parser.RE_TAIL_NUM.exec(base);
      progress = tail ? tail[1] : '';
      return { source: source, progress: progress };
    }

    for (const content of brackets) {
      if (source.length === 0) {
        for (const site of Parser.SOURCE_SITES) {
          if (site.length > 0 && content.includes(site)) {
            source = site;
            break;
          }
        }
      }
      if (progress.length === 0) {
        const gm: RegExpExecArray | null = Parser.RE_PROGRESS_GENG.exec(content);
        if (gm) {
          progress = gm[1];
        }
      }
      if (progress.length === 0) {
        const wm: RegExpExecArray | null = Parser.RE_PROGRESS_WAN.exec(content);
        if (wm) {
          progress = wm[0];
        }
      }
      if (progress.length === 0) {
        const fw: RegExpExecArray | null = Parser.RE_PROGRESS_FANWAI.exec(content);
        if (fw) {
          progress = fw[0];
        }
      }
      if (progress.length === 0) {
        const om: RegExpExecArray | null = Parser.RE_PROGRESS_STATUS.exec(content);
        if (om) {
          progress = om[0];
        }
      }
      if (progress.length === 0) {
        const tail: RegExpExecArray | null = Parser.RE_TAIL_NUM.exec(base);
        if (tail) {
          progress = tail[1];
        }
      }
    }
    if (progress.length === 0) {
      const tail: RegExpExecArray | null = Parser.RE_TAIL_NUM.exec(base);
      if (tail) {
        progress = tail[1];
      }
    }
    if (progress.length === 0) {
      const um: RegExpExecArray | null = Parser.RE_PROGRESS_UPDATE.exec(base);
      if (um) {
        progress = um[1];
      }
    }
    return { source: source, progress: progress };
  }
}
