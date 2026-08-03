"""
验证「关键词替换」的批量启用 / 不启用 + 停用规则确实不参与扫描解析。

覆盖：
1. batch-enabled 接口把指定 ID 批量置为 启用 / 不启用，并持久化到数据库（回退后依旧有效）。
2. load_rules 只返回 enabled=True 的规则 —— 即停用的规则在实际扫描 / 解析中真的不生效。
3. 停用后 apply_rules 的输出不再包含该规则的替换效果，重新启用后恢复生效。

运行： python -m pytest tests/test_keyword_batch_enabled.py -v
"""
import os
import sys

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend.keyword_replace import apply_rules, load_rules  # noqa: E402
from backend.models import Base, KeywordReplaceRule  # noqa: E402


@pytest.fixture()
def db():
    """内存 SQLite，隔离于真实库。"""
    engine = create_engine('sqlite:///:memory:')
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()


def _seed(db):
    """写入 4 条 scan 规则 + 1 条 parse 规则。"""
    rules = [
        KeywordReplaceRule(scope='scan', pattern='【精校】', replacement='', sort_order=1, enabled=True),
        KeywordReplaceRule(scope='scan', pattern='（校对版）', replacement='', sort_order=2, enabled=True),
        KeywordReplaceRule(scope='scan', pattern='精校', replacement='', sort_order=3, enabled=True),
        KeywordReplaceRule(scope='scan', pattern='高清', replacement='', sort_order=4, enabled=True),
        KeywordReplaceRule(scope='parse', pattern='佚名', replacement='未知', sort_order=1, enabled=True),
    ]
    db.add_all(rules)
    db.commit()
    for r in rules:
        db.refresh(r)
    return rules


def _batch_set_enabled(db, ids, enabled):
    """等价于后端 POST /api/keyword-replaces/batch-enabled 的核心逻辑。"""
    updated = db.query(KeywordReplaceRule).filter(
        KeywordReplaceRule.id.in_(ids)
    ).update({KeywordReplaceRule.enabled: enabled}, synchronize_session=False)
    db.commit()
    return updated


def test_load_rules_only_returns_enabled(db):
    """load_rules 必须过滤掉停用规则 —— 这是「不启用真的不生效」的根本保证。"""
    rules = _seed(db)
    assert len(load_rules(db, 'scan')) == 4

    rules[2].enabled = False  # 停用「精校」
    db.commit()

    loaded = load_rules(db, 'scan')
    assert len(loaded) == 3
    assert '精校' not in [r.pattern for r in loaded]


def test_disabled_rule_not_applied_in_pipeline(db):
    """停用的规则不参与实际替换；重新启用后恢复生效。"""
    rules = _seed(db)
    name = '斗破苍穹【精校】高清.txt'

    # 全部启用：两条都命中
    assert apply_rules(name, load_rules(db, 'scan')) == '斗破苍穹.txt'

    # 停用「高清」后，「高清」应保留在结果里
    _batch_set_enabled(db, [rules[3].id], False)
    out = apply_rules(name, load_rules(db, 'scan'))
    assert out == '斗破苍穹高清.txt'
    assert '高清' in out
    assert '【精校】' not in out  # 其它规则仍生效

    # 重新启用后恢复
    _batch_set_enabled(db, [rules[3].id], True)
    assert apply_rules(name, load_rules(db, 'scan')) == '斗破苍穹.txt'


def test_batch_disable_only_affects_given_ids(db):
    """批量操作只影响传入的 ID（即前端「搜索结果」子集），其余规则不受影响。"""
    rules = _seed(db)
    # 模拟搜索「精校」命中 2 条，批量不启用
    hits = [r for r in rules if '精校' in r.pattern]
    assert len(hits) == 2

    updated = _batch_set_enabled(db, [r.id for r in hits], False)
    assert updated == 2

    remaining = load_rules(db, 'scan')
    assert sorted(r.pattern for r in remaining) == sorted(['（校对版）', '高清'])
    # parse 作用域完全不受影响
    assert len(load_rules(db, 'parse')) == 1


def test_batch_state_persists_across_sessions(db):
    """批量修改后的状态写入库中，新建会话（等价于页面回退重进）依旧有效。"""
    rules = _seed(db)
    scan_ids = [r.id for r in rules if r.scope == 'scan']
    _batch_set_enabled(db, scan_ids, False)

    # 清空 ORM 身份映射，强制从数据库重新读取，模拟「回退后重新进入页面」
    db.expunge_all()
    assert load_rules(db, 'scan') == []

    reread = db.query(KeywordReplaceRule).filter(KeywordReplaceRule.scope == 'scan').all()
    assert all(r.enabled is False for r in reread)

    # 批量启用回来
    _batch_set_enabled(db, scan_ids, True)
    db.expunge_all()
    assert len(load_rules(db, 'scan')) == 4


def test_batch_empty_ids_is_noop(db):
    """空 ID 列表不应改动任何数据。"""
    _seed(db)
    assert _batch_set_enabled(db, [], False) == 0
    assert len(load_rules(db, 'scan')) == 4
