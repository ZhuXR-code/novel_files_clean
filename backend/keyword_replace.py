"""关键词替换工具：在扫描/解析阶段应用用户在设置页配置的规则"""
from typing import List, Optional

from backend.models import KeywordReplaceRule
from sqlalchemy.orm import Session


def load_rules(db: Session, scope: str) -> List[KeywordReplaceRule]:
    """加载某作用域下已启用的规则，按 sort_order、id 升序。"""
    return db.query(KeywordReplaceRule).filter(
        KeywordReplaceRule.scope == scope,
        KeywordReplaceRule.enabled == True,
    ).order_by(KeywordReplaceRule.sort_order, KeywordReplaceRule.id).all()


def apply_rules(text: Optional[str], rules: List[KeywordReplaceRule]) -> Optional[str]:
    """按顺序对文本应用规则；空文本或空规则原样返回。"""
    if not text or not rules:
        return text
    for r in rules:
        p = (r.pattern or '')
        if p:
            text = text.replace(p, r.replacement or '')
    return text


# 预置关键词替换规则（去文件名水印），随启动补齐进数据库，用户可见、可增删改查。
# 与 Android 端 DEFAULT_KEYWORD_RULES 保持同步：作用域均为 scan（扫描阶段作用于文件名），
# replacement 为空串表示删除。若用户不想要某条，建议在界面"禁用"而非"删除"，否则下次启动会被重新补齐。
DEFAULT_KEYWORD_RULES = [
    {'scope': 'scan', 'pattern': '[草2莓]', 'replacement': '', 'sort_order': 1},
    {'scope': 'scan', 'pattern': '【草2莓', 'replacement': '', 'sort_order': 2},
    {'scope': 'scan', 'pattern': '【草2莓】', 'replacement': '', 'sort_order': 3},
    {'scope': 'scan', 'pattern': '[草 莓]', 'replacement': '', 'sort_order': 4},
    {'scope': 'scan', 'pattern': '[草 莓', 'replacement': '', 'sort_order': 5},
    {'scope': 'scan', 'pattern': '【lili】', 'replacement': '', 'sort_order': 6},
    {'scope': 'scan', 'pattern': '（l.i.）', 'replacement': '', 'sort_order': 7},
    {'scope': 'scan', 'pattern': '(l.i.）', 'replacement': '', 'sort_order': 8},
    {'scope': 'scan', 'pattern': '（l.i.)', 'replacement': '', 'sort_order': 9},
    {'scope': 'scan', 'pattern': '(l.i.)', 'replacement': '', 'sort_order': 10},
    # —— 以下为 caomei / 3167 937770 水印系列及扩展名修正（与 APP/鸿蒙端同步）——
    # 顺序约定：① 含「の企鹅3167 937770」的完整变体须先于裸「の企鹅3167 937770」，
    # 否则裸规则先吃掉尾部、残留孤立前缀；② 成对括号变体须先于只去开头括号的变体，
    # 否则残留孤立括号。
    {'scope': 'scan', 'pattern': '..txt', 'replacement': '.txt', 'sort_order': 11},
    {'scope': 'scan', 'pattern': '【草莓】', 'replacement': '', 'sort_order': 12},
    {'scope': 'scan', 'pattern': '【草 莓', 'replacement': '', 'sort_order': 13},
    {'scope': 'scan', 'pattern': '【＋V信kxee6699】', 'replacement': '', 'sort_order': 14},
    {'scope': 'scan', 'pattern': '.3167 937770', 'replacement': '', 'sort_order': 15},
    {'scope': 'scan', 'pattern': '【颜3167 937770', 'replacement': '', 'sort_order': 16},
    {'scope': 'scan', 'pattern': '【Q主caomeiの企鹅3167 937770】', 'replacement': '', 'sort_order': 17},
    {'scope': 'scan', 'pattern': '【Q主caomei】', 'replacement': '', 'sort_order': 18},
    {'scope': 'scan', 'pattern': '_caomeiの企鹅3167 937770_', 'replacement': '', 'sort_order': 19},
    {'scope': 'scan', 'pattern': '（caomeiの企鹅3167 937770', 'replacement': '', 'sort_order': 20},
    {'scope': 'scan', 'pattern': '(caomeiの企鹅3167 937770', 'replacement': '', 'sort_order': 21},
    {'scope': 'scan', 'pattern': '【qzcaomeiの企鹅3167 937770', 'replacement': '', 'sort_order': 22},
    {'scope': 'scan', 'pattern': '.QZcaomeiの企鹅3167 937770', 'replacement': '', 'sort_order': 23},
    {'scope': 'scan', 'pattern': '_caomeiの企鹅3167 937770', 'replacement': '', 'sort_order': 24},
    {'scope': 'scan', 'pattern': '.caomeiの企鹅3167 937770', 'replacement': '', 'sort_order': 25},
    {'scope': 'scan', 'pattern': 'の企鹅3167 937770', 'replacement': '', 'sort_order': 26},
    {'scope': 'scan', 'pattern': '[3167 937770]', 'replacement': '', 'sort_order': 27},
    {'scope': 'scan', 'pattern': '[3167 937770', 'replacement': '', 'sort_order': 28},
    {'scope': 'scan', 'pattern': '3167937770', 'replacement': '', 'sort_order': 29},
    {'scope': 'scan', 'pattern': '_3167 937770', 'replacement': '', 'sort_order': 30},
    {'scope': 'scan', 'pattern': '（颜3167 937770', 'replacement': '', 'sort_order': 31},
    {'scope': 'scan', 'pattern': '【3167 937770]', 'replacement': '', 'sort_order': 32},
    {'scope': 'scan', 'pattern': '_.txt', 'replacement': '.txt', 'sort_order': 33},
    # —— 与 Android 端同步的默认替换规则 ——
    {'scope': 'scan', 'pattern': '【YLW】', 'replacement': '', 'sort_order': 34},
    {'scope': 'scan', 'pattern': '『推』', 'replacement': '', 'sort_order': 35},
    {'scope': 'scan', 'pattern': '【昭昭明月BG】', 'replacement': '', 'sort_order': 36},
    {'scope': 'scan', 'pattern': '【昭昭明月BL】', 'replacement': '', 'sort_order': 37},
    {'scope': 'scan', 'pattern': '【推荐】', 'replacement': '', 'sort_order': 38},
    {'scope': 'scan', 'pattern': '【全本校对】', 'replacement': '', 'sort_order': 39},
    {'scope': 'scan', 'pattern': '【全本精校】', 'replacement': '', 'sort_order': 40},
    {'scope': 'scan', 'pattern': '【BL】', 'replacement': '', 'sort_order': 41},
    {'scope': 'scan', 'pattern': '【BG】', 'replacement': '', 'sort_order': 42},
    {'scope': 'scan', 'pattern': '【YLW连载】', 'replacement': '', 'sort_order': 43},
    {'scope': 'scan', 'pattern': '【棠】', 'replacement': '', 'sort_order': 44},
    {'scope': 'scan', 'pattern': '【公众号：推文日记】', 'replacement': '', 'sort_order': 45},
    {'scope': 'scan', 'pattern': '【书香门第★九落】', 'replacement': '', 'sort_order': 46},
]


def seed_default_rules(db: Session) -> int:
    """补齐缺失的预置关键词替换规则（幂等）：按 (scope, pattern) 判断，仅插入库中没有的项。

    - 首次为空时整批写入；
    - 后续新增预置项也会自动补进已安装实例，无需清数据；
    - 只动数据库记录，不触碰磁盘上的源文件。
    返回本次新增的条数。
    """
    added = 0
    for rule in DEFAULT_KEYWORD_RULES:
        exists = db.query(KeywordReplaceRule).filter(
            KeywordReplaceRule.scope == rule['scope'],
            KeywordReplaceRule.pattern == rule['pattern'],
        ).first()
        if not exists:
            db.add(KeywordReplaceRule(
                scope=rule['scope'],
                pattern=rule['pattern'],
                replacement=rule['replacement'],
                sort_order=rule['sort_order'],
                enabled=True,
            ))
            added += 1
    if added:
        db.commit()
    return added
