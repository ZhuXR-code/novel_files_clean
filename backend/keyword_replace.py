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
