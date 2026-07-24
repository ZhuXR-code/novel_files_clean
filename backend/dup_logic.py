"""合集模式"勾选重复"的核心判定算法（PC 网页版 / PC 桌面版 共用，可单测）。

算法在【同一合集】内、按 (作者 + 小说名) 子分组进行五则规则判定：

规则 1（完全相等去重）：
    (小说名 + 作者 + 进度 + 文件大小) 四要素完全一致（不含文件名），且同 (作者+小说名) 子组 >= 2 本时，
    最新(创建时间最晚，并列取 id 最大)的不勾选，其余全部勾选(待删)。

规则 2（纯数字进度对比）：
    同 (作者+小说名) 内，对【有纯数字进度】的文件做比较（空白进度文件不参与），
    进度数字最大的不勾选，其余数字进度文件全部勾选。

规则 3（含中文进度 / 完结特例）：
    - 进度含中文(如"完结/连载/断更")的，不勾选（保护状态文件）；
    - 若同组存在文件名带『完结』等关键词、且"进度数字最大文件"的大小
      小于同组所有含中文进度文件的大小时，该"进度数字最大文件"也要勾选
      （说明存在更完整的完结版，部分进度版冗余应删）。

规则 4（最大文件不勾选原则）：
    已勾选的文件若为本 (作者+小说名) 组内文件大小最大者，则不勾选。

最终待删集合 = (勾选集 - 永不勾选集) ∪ 强制勾选集。
"""
import re
from collections import defaultdict

# 文件名中代表"已完结/完整版"的关键词：用于规则 3 的特例判定。
_DUP_COMPLETION_KW = ['完结', '完本', '全本', '全集', '完整', '全套', '全集版']

# 进度【严格】匹配「完结+数字番外」或「完结+番外数字」的正则（用于规则 5 的完结+N番外/完结+番外N 组合排序）。
_DUP_FANWAI_RE = re.compile(r'^完结\+(?:(\d+(?:\.\d+)?)番外|番外(\d+(?:\.\d+)?))$')


def _dup_has_cjk(s: str) -> bool:
    """判断字符串是否含有中文（CJK）字符。"""
    if not s:
        return False
    for c in s:
        o = ord(c)
        if 0x4E00 <= o <= 0x9FFF or 0x3400 <= o <= 0x4DBF:
            return True
    return False


def _dup_progress_value(s: str):
    """若进度为纯数字（可选小数、可选尾随 %），返回 float 数值，否则返回 None。"""
    s = (s or '').strip()
    if not s or _dup_has_cjk(s):
        return None
    m = re.fullmatch(r'(\d+(?:\.\d+)?)\s*%?', s)
    return float(m.group(1)) if m else None


def _dup_fanwai_value(s: str):
    """若进度匹配「完结+N番外」或「完结+番外N」（如「完结+3番外」「完结+番外5」），返回数字 N，否则 None。"""
    s = (s or '').strip()
    if not s:
        return None
    m = _DUP_FANWAI_RE.match(s)
    return float(m.group(1) or m.group(2)) if m else None


def _dup_subgroup_key(author: str, novel: str):
    """(作者 + 小说名) 归一化子分组键（统一小写、去空格）。"""
    return ((author or '').strip().lower(), (novel or '').strip().lower())


def compute_duplicate_ids(rows, enabled_rules=None, user_rules=None):
    """计算应勾选（待删）的文件 id 集合。

    [rows] 为 dict 列表，每项含 id / file_name / file_size / novel_name / author /
    progress / created_date。按 (作者 + 小说名) 分组后应用五则规则，
    返回 (ids_to_check, subgroups_with_duplicates, detail_lines)。

    [enabled_rules] 为可选 set，控制哪些规则生效：
        None = 全部规则启用（默认）。
        可包含: rule1/rule2/rule3a/rule3b/rule4/rule5
    """
    subgroups = defaultdict(list)
    for r in rows:
        subgroups[_dup_subgroup_key(r.get('author'), r.get('novel_name'))].append(r)

    all_result = set()
    subgroups_with_dups = 0
    detail_lines = []

    for _key, S in subgroups.items():
        if len(S) < 2:
            continue

        c = set()   # 应勾选
        nc = set()  # 永不勾选（保护）
        fc = set()  # 强制勾选（覆盖保护）

        # ── 规则 1：完全相等去重 ──
        if enabled_rules is None or 'rule1' in enabled_rules:
            # (小说名+作者+进度+文件大小) 完全相等的精确重复组（不含文件名）。
            #   子分组已保证 小说名+作者 相同，这里只比 (文件大小, 进度)。
            exact = defaultdict(list)
            for f in S:
                ek = (f['file_size'] or 0, (f['progress'] or '').strip())
                exact[ek].append(f)
            for _ek, g in exact.items():
                if len(g) < 2:
                    continue
                newest = max(g, key=lambda x: ((x.get('created_date') or ''), x['id']))
                nc.add(newest['id'])
                for f in g:
                    if f['id'] != newest['id']:
                        # 精确重复的非最新本：强制勾选（覆盖规则2"最大进度不勾选"的保护，
                        # 因为精确重复=同尺寸，不可能同时是"唯一最大文件"，故不会与规则4冲突）。
                        c.add(f['id'])
                        fc.add(f['id'])

        # 进度分类
        numeric_files = [f for f in S if _dup_progress_value(f['progress']) is not None]
        chinese_files = [f for f in S if _dup_has_cjk(f['progress'] or '')]

        # 本组文件大小列表（规则4/5需要）
        sizes = [f['file_size'] for f in S]
        max_size = max(sizes) if sizes else 0

        # ── 规则 2：纯数字进度对比 ──
        # 仅当【组内无中文进度文件时】应用：纯数字组内，非最大进度本全部勾选。
        # 混合组（同时有中文进度）中，规则2不应勾选非最大本（由规则3B单独处理最大本）。
        if enabled_rules is None or 'rule2' in enabled_rules:
            if len(numeric_files) >= 2 and not chinese_files:
                max_val = max(_dup_progress_value(f['progress']) for f in numeric_files)
                max_files = [f for f in numeric_files
                             if _dup_progress_value(f['progress']) == max_val]
                for f in max_files:
                    nc.add(f['id'])
                for f in numeric_files:
                    if _dup_progress_value(f['progress']) != max_val:
                        c.add(f['id'])
                        fc.add(f['id'])

        # ── 规则 3A：含中文进度者不勾选 ──
        if enabled_rules is None or 'rule3a' in enabled_rules:
            for f in chinese_files:
                nc.add(f['id'])

        # ── 规则 3B：完结特例 ──
        if enabled_rules is None or 'rule3b' in enabled_rules:
            # 进度数字最大文件更小则强制勾选
            if chinese_files and numeric_files:
                max_num_val = max(_dup_progress_value(f['progress']) for f in numeric_files)
                max_num_files = [f for f in numeric_files
                                 if _dup_progress_value(f['progress']) == max_num_val]
                has_completion = any(
                    any(kw in (f['file_name'] or '') for kw in _DUP_COMPLETION_KW)
                    for f in S
                )
                min_chinese_size = min(f['file_size'] for f in chinese_files)
                if has_completion and all(mn['file_size'] < min_chinese_size for mn in max_num_files):
                    for mn in max_num_files:
                        fc.add(mn['id'])

        # ── 规则 4：最大文件不勾选 ──
        if enabled_rules is None or 'rule4' in enabled_rules:
            # 本组内【唯一】文件大小最大者，不勾选。
            #   若多本并列最大，则按大小无法区分，不据此保护，以免同大小重复组被整体保留。
            #   同时从 fc 移除（覆盖规则2的强制勾选），确保最大文件不被误勾选。
            sizes = [f['file_size'] for f in S]
            max_size = max(sizes)
            if sizes.count(max_size) == 1:
                for f in S:
                    if f['file_size'] == max_size:
                        nc.add(f['id'])
                        fc.discard(f['id'])

        # ── 规则 5：完结+N番外/完结+番外N 组合排序去重 ──
        if enabled_rules is None or 'rule5' in enabled_rules:
            # 进度匹配「完结+N番外」或「完结+番外N」的文件，在同组内按数字 N 排序；
            # 数字最大者不勾选，其余打勾（强制勾选，覆盖规则③A 对中文进度的保护）；
            # 但被勾选的文件若恰为本组 (作者+小说名) 内【唯一文件大小最大者】，则也不勾选。
            fanwai = [f for f in S if _dup_fanwai_value(f['progress']) is not None]
            if fanwai:
                max_n = max(_dup_fanwai_value(f['progress']) for f in fanwai)
                max_n_ids = {f['id'] for f in fanwai
                                 if _dup_fanwai_value(f['progress']) == max_n}
                for f in fanwai:
                    if f['id'] in max_n_ids:
                        nc.add(f['id'])
                        fc.discard(f['id'])
                    elif f['file_size'] == max_size and sizes.count(max_size) == 1:
                        nc.add(f['id'])
                        fc.discard(f['id'])
                    else:
                        c.add(f['id'])
                        fc.add(f['id'])

        sub_result = (c - nc) | fc
        if sub_result:
            subgroups_with_dups += 1
            nv = S[0].get('novel_name') or '?'
            au = S[0].get('author') or '?'
            detail_lines.append(
                f"重复子组 书名={nv} 作者={au} 共{len(S)}本 "
                f"-> 勾选{len(sub_result)}个: {sorted(sub_result)}"
            )
            all_result |= sub_result

    # ── 用户自定义规则（条件-动作引擎） ──
    if user_rules:
        check_ids, protect_ids = _apply_user_rules(rows, user_rules)
        # 先追加勾选，再应用保护
        all_result |= check_ids
        all_result -= protect_ids
        if check_ids:
            detail_lines.append(f"自定义规则追加勾选 {len(check_ids)} 个: {sorted(check_ids)}")
        if protect_ids:
            detail_lines.append(f"自定义规则保护 {len(protect_ids)} 个: {sorted(protect_ids)}")

    return all_result, subgroups_with_dups, detail_lines


# ===================== 用户自定义规则引擎 =====================

# 可用字段映射：用户选择的字段名 → row dict 中的键名
_USER_FIELD_MAP = {
    'novel_name': 'novel_name',
    'author': 'author',
    'progress': 'progress',
    'source': 'source',
    'file_name': 'file_name',
    'file_size': 'file_size',
    'file_path': 'file_path',
    'created_date': 'created_date',
}


def _eval_user_condition(row: dict, condition: dict) -> bool:
    """评估单条条件。condition = {"field":"...","op":"...","value":"..."}"""
    field_name = condition.get('field', '')
    op = condition.get('op', 'eq')
    raw_value = condition.get('value', '')

    # 解析行中的实际值
    row_key = _USER_FIELD_MAP.get(field_name)
    if row_key is None:
        return True  # 未知字段不参与判断
    actual = row.get(row_key)

    # 数值字段特殊处理（file_size 和 progress 支持数值比较）
    if field_name in ('file_size', 'progress'):
        # 提取实际值（允许丢失非数字内容，如 "50%"→50）
        actual_val = None
        if actual is not None:
            try:
                # 提取数字前缀（允许含 % 或纯数字）
                m = re.match(r'(\d+(?:\.\d+)?)', str(actual).strip())
                if m:
                    actual_val = float(m.group(1))
            except (ValueError, TypeError):
                pass
        if actual_val is None:
            actual_val = 0

        # between 运算符特殊处理（逗号分隔的两个值）
        if op == 'between':
            parts = str(raw_value).split(',')
            if len(parts) == 2:
                try:
                    lo = float(parts[0].strip())
                    hi = float(parts[1].strip())
                    return lo <= actual_val <= hi
                except ValueError:
                    pass
            return False

        # 其他运算符：先尝试数值比较，失败回退字符串比较
        try:
            target_val = float(raw_value)
        except (ValueError, TypeError):
            # 非数值字符串（如 "完结"），回退文本比较
            actual_str = str(actual or '')
            target_str = str(raw_value or '')
            if op == 'eq': return actual_str == target_str
            if op == 'neq': return actual_str != target_str
            if op == 'gt': return actual_str > target_str
            if op == 'gte': return actual_str >= target_str
            if op == 'lt': return actual_str < target_str
            if op == 'lte': return actual_str <= target_str
            if op == 'contains': return target_str.lower() in actual_str.lower()
            if op == 'not_contains': return target_str.lower() not in actual_str.lower()
            if op == 'starts_with': return actual_str.lower().startswith(target_str.lower())
            if op == 'ends_with': return actual_str.lower().endswith(target_str.lower())
            if op == 'regex':
                try:
                    return bool(re.search(target_str, actual_str))
                except re.error:
                    return False
            return False

        if op == 'eq': return actual_val == target_val
        if op == 'neq': return actual_val != target_val
        if op == 'gt': return actual_val > target_val
        if op == 'gte': return actual_val >= target_val
        if op == 'lt': return actual_val < target_val
        if op == 'lte': return actual_val <= target_val
        return False

    # 文本字段
    actual_str = str(actual or '')
    target_str = str(raw_value or '')
    if op == 'eq': return actual_str == target_str
    if op == 'neq': return actual_str != target_str
    if op == 'contains': return target_str.lower() in actual_str.lower()
    if op == 'not_contains': return target_str.lower() not in actual_str.lower()
    if op == 'starts_with': return actual_str.lower().startswith(target_str.lower())
    if op == 'ends_with': return actual_str.lower().endswith(target_str.lower())
    if op == 'regex':
        try:
            return bool(re.search(target_str, actual_str))
        except re.error:
            return False

    # 日期字段
    if field_name in ('created_date',):
        try:
            from datetime import datetime
            actual_dt = datetime.fromisoformat(str(actual)) if actual else None
            if op == 'before' or op == 'after':
                target_dt = datetime.fromisoformat(str(raw_value))
                if actual_dt:
                    return actual_dt < target_dt if op == 'before' else actual_dt > target_dt
            if op == 'within_days':
                if actual_dt:
                    delta = (datetime.now() - actual_dt).days
                    return abs(delta) <= int(raw_value)
        except (ValueError, TypeError):
            pass
        return False

    return True  # 未知运算符默认通过


def _eval_user_rule(row: dict, rule_dict: dict) -> bool:
    """评估一条用户自定义规则是否命中该行。
    rule_dict = {"conditions":[...], "action":"check"/"protect"}
    conditions 内各条件用 AND 逻辑。
    """
    conditions = rule_dict.get('conditions', [])
    if not conditions:
        return False
    # 并列条件全部满足才算命中（AND）
    for cond in conditions:
        if not _eval_user_condition(row, cond):
            return False
    return True


def _apply_user_rules(rows: list, user_rules: list) -> tuple:
    """应用用户自定义规则到所有行。
    返回 (check_ids: set, protect_ids: set)
    user_rules: [{"action":"check"/"protect", "conditions":[...], ...}, ...]
    按 user_rules 列表顺序执行，后执行的规则可覆盖前面结果。
    """
    check_ids = set()
    protect_ids = set()
    for rule in user_rules:
        action = rule.get('action', 'check')
        for row in rows:
            if _eval_user_rule(row, rule):
                rid = row.get('id')
                if rid is not None:
                    if action == 'check':
                        check_ids.add(rid)
                        protect_ids.discard(rid)
                    elif action == 'protect':
                        protect_ids.add(rid)
                        check_ids.discard(rid)
    return check_ids, protect_ids
