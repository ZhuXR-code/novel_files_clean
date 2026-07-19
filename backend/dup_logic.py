"""合集模式“标记重复”的核心判定算法（PC 网页版 / PC 桌面版 共用，可单测）。

算法在【同一合集】内、按 (作者 + 小说名) 子分组进行五则规则判定：

规则 1（完全相等去重）：
    (文件名 + 大小 + 小说名 + 作者 + 进度) 五字段完全一致，且同组 >= 2 本时，
    最新(创建时间最晚，并列取 id 最大)的不勾选，其余全部勾选(待删)。

规则 2（纯数字进度对比）：
    同 (作者+小说名) 内，若【所有】进度均为纯数字，则进度数字最大的不勾选，
    其余纯数字文件全部勾选。

规则 3（含中文进度 / 完结特例）：
    - 进度含中文(如“完结/连载/断更”)的，不勾选（保护状态文件）；
    - 若同组存在文件名带『完结』等关键词、且“进度数字最大文件”的大小
      小于同组所有含中文进度文件的大小时，该“进度数字最大文件”也要勾选
      （说明存在更完整的完结版，部分进度版冗余应删）。

规则 4（最大文件不勾选原则）：
    已勾选的文件若为本 (作者+小说名) 组内文件大小最大者，则不勾选。

最终待删集合 = (勾选集 - 永不勾选集) ∪ 强制勾选集。
"""
import re
from collections import defaultdict

# 文件名中代表“已完结/完整版”的关键词：用于规则 3 的特例判定。
_DUP_COMPLETION_KW = ['完结', '完本', '全本', '全集', '完整', '全套', '全集版']

# 进度【严格】匹配「完结+数字番外」的正则（用于规则 5 的完结+N番外 组合排序）。
_DUP_FANWAI_RE = re.compile(r'^完结\+(\d+(?:\.\d+)?)番外$')


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
    """若进度严格匹配 `完结+数字番外`（如「完结+3番外」），返回数字 N，否则 None。"""
    s = (s or '').strip()
    if not s:
        return None
    m = _DUP_FANWAI_RE.match(s)
    return float(m.group(1)) if m else None


def _dup_subgroup_key(author: str, novel: str):
    """(作者 + 小说名) 归一化子分组键（统一小写、去空格）。"""
    return ((author or '').strip().lower(), (novel or '').strip().lower())


def compute_duplicate_ids(rows):
    """计算应勾选（待删）的文件 id 集合。

    [rows] 为 dict 列表，每项含 id / file_name / file_size / novel_name / author /
    progress / created_date。按 (作者 + 小说名) 分组后应用五则规则，
    返回 (ids_to_check, subgroups_with_duplicates, detail_lines)。
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

        # 规则 1：五字段完全相等的精确重复组
        exact = defaultdict(list)
        for f in S:
            ek = (f['file_name'] or '', f['file_size'] or 0, (f['progress'] or '').strip())
            exact[ek].append(f)
            for _ek, g in exact.items():
                if len(g) < 2:
                    continue
                newest = max(g, key=lambda x: ((x.get('created_date') or ''), x['id']))
                nc.add(newest['id'])
                for f in g:
                    if f['id'] != newest['id']:
                        # 精确重复的非最新本：强制勾选（覆盖规则2“最大进度不勾选”的保护，
                        # 因为精确重复=同尺寸，不可能同时是“唯一最大文件”，故不会与规则4冲突）。
                        c.add(f['id'])
                        fc.add(f['id'])

        # 进度分类
        numeric_files = [f for f in S if _dup_progress_value(f['progress']) is not None]
        chinese_files = [f for f in S if _dup_has_cjk(f['progress'] or '')]
        all_numeric = (len(numeric_files) == len(S))

        if all_numeric:
            # 规则 2：纯数字进度，最大者不勾选，其余纯数字全部勾选
            max_val = max(_dup_progress_value(f['progress']) for f in S)
            max_files = [f for f in S if _dup_progress_value(f['progress']) == max_val]
            max_ids = {m['id'] for m in max_files}
            for f in max_files:
                nc.add(f['id'])
            for f in S:
                if f['id'] not in max_ids:
                    c.add(f['id'])
        else:
            # 规则 3A：含中文进度者不勾选
            for f in chinese_files:
                nc.add(f['id'])
            # 规则 3B：完结特例——进度数字最大文件更小则强制勾选
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

        # 规则 4：本组内【唯一】文件大小最大者，不勾选（最大文件不勾选原则）。
        #   若多本并列最大，则按大小无法区分，不据此保护，以免同大小重复组被整体保留。
        sizes = [f['file_size'] for f in S]
        max_size = max(sizes)
        if sizes.count(max_size) == 1:
            for f in S:
                if f['file_size'] == max_size:
                    nc.add(f['id'])

        # 规则 5（新增）：完结+N番外 组合排序去重。
        #   进度【严格】匹配 `完结+数字番外`（如「完结+3番外」）的文件，在同 (作者+小说名)
        #   组内按数字 N 排序；数字最大者不勾选，其余打勾（强制勾选，覆盖规则③A 对中文进度的保护）；
        #   但被勾选的文件若恰为本组 (作者+小说名) 内【文件大小最大者】，则也不勾选。
        fanwai = [f for f in S if _dup_fanwai_value(f['progress']) is not None]
        if fanwai:
            max_n = max(_dup_fanwai_value(f['progress']) for f in fanwai)
            max_n_ids = {f['id'] for f in fanwai
                             if _dup_fanwai_value(f['progress']) == max_n}
            for f in fanwai:
                if f['id'] in max_n_ids:
                    nc.add(f['id'])            # 数字最大：不勾选（保护）
                    fc.discard(f['id'])        # 即便被规则①精确重复强制勾选，也以本规则为准
                elif f['file_size'] == max_size:
                    nc.add(f['id'])            # 本组文件大小最大：不勾选
                    fc.discard(f['id'])
                else:
                    c.add(f['id'])
                    fc.add(f['id'])            # 强制勾选，覆盖规则③A

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

    return all_result, subgroups_with_dups, detail_lines
