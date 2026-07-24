# -*- coding: utf-8 -*-
"""用户自定义规则引擎单元测试"""
import sys, os, io
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from backend.dup_logic import compute_duplicate_ids, _eval_user_condition, _eval_user_rule, _apply_user_rules

PASS = 0
FAIL = 0
LOG_LINES = []
def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        msg = f"  [PASS] {name}" + (f" {detail}" if detail else "")
    else:
        FAIL += 1
        msg = f"  [FAIL] {name}: {detail}"
    print(msg)
    LOG_LINES.append(msg)

def log(msg):
    print(msg)
    LOG_LINES.append(msg)

log("=== 条件评估基础测试 ===")
r_a = {"id": 1, "file_name": "a.txt", "file_size": 100, "novel_name": "书", "author": "某作", "progress": "50", "created_date": "2024-01-01"}
r_b = {"id": 2, "file_name": "b.txt", "file_size": 80, "novel_name": "书", "author": "某作", "progress": "完结", "created_date": "2024-01-02"}

check("文本 eq 匹配", _eval_user_condition(r_a, {"field":"author","op":"eq","value":"某作"}))
check("文本 eq 不匹配", not _eval_user_condition(r_a, {"field":"author","op":"eq","value":"其他"}))
check("text contains", _eval_user_condition(r_a, {"field":"novel_name","op":"contains","value":"书"}))
check("text not_contains", not _eval_user_condition(r_a, {"field":"novel_name","op":"not_contains","value":"书"}))
check("text starts_with", _eval_user_condition(r_a, {"field":"file_name","op":"starts_with","value":"a"}))
check("text ends_with", _eval_user_condition(r_a, {"field":"file_name","op":"ends_with","value":".txt"}))
check("text regex", _eval_user_condition(r_a, {"field":"file_name","op":"regex","value":"^a\\."}))
check("数值 file_size gt", _eval_user_condition(r_a, {"field":"file_size","op":"gt","value":"50"}))
check("数值 file_size lte", _eval_user_condition(r_a, {"field":"file_size","op":"lte","value":"100"}))
check("数值 file_size between", _eval_user_condition(r_a, {"field":"file_size","op":"between","value":"50,200"}))
check("数值 progress gt", _eval_user_condition(r_a, {"field":"progress","op":"gt","value":"40"}), "(50>40)")
check("数值 progress gt 不匹配", not _eval_user_condition(r_a, {"field":"progress","op":"gt","value":"60"}), "(50 not >60)")
check("文本 progress eq(完结)", _eval_user_condition(r_b, {"field":"progress","op":"eq","value":"完结"}))

log("\n=== 自定义规则 check action（跨子分组）===")
# check 应作用于 ALL 行，不受子分组限制
rows_check = [
    {"id": 1, "file_name": "a.txt", "file_size": 100, "novel_name": "书1", "author": "某作", "progress": "50", "created_date": "2024-01-01"},
    {"id": 2, "file_name": "b.txt", "file_size": 80, "novel_name": "书2", "author": "其他", "progress": "30", "created_date": "2024-01-02"},
]
check_ids, _ = _apply_user_rules(rows_check, [{"action":"check", "conditions":[{"field":"file_size","op":"gt","value":"0"}]}])
check("check 全部行", sorted(check_ids) == [1, 2], f"got {sorted(check_ids)}")
# filtered
check_ids2, _ = _apply_user_rules(rows_check, [{"action":"check", "conditions":[{"field":"author","op":"eq","value":"某作"}]}])
check("check 特定行", sorted(check_ids2) == [1], f"got {sorted(check_ids2)}")

log("\n=== 自定义规则 protect action（覆盖内置规则）===")
# 2 个精确重复：built-in → 保留最新(2), 检查(1)
rows_protect = [
    {"id": 1, "file_name": "a.txt", "file_size": 100, "novel_name": "书", "author": "某作", "progress": "50", "created_date": "2024-01-01"},
    {"id": 2, "file_name": "b.txt", "file_size": 100, "novel_name": "书", "author": "某作", "progress": "50", "created_date": "2024-01-02"},
]
builtin = compute_duplicate_ids(rows_protect)[0]
check("内置规则: 保留最新,勾选文件1", sorted(builtin) == [1], f"got {sorted(builtin)}")

# protect 文件名包含"a"→保护文件1, 结果应为空
rule_prot_a = {"action":"protect", "conditions":[{"field":"file_name","op":"contains","value":"a"}]}
r_prot = compute_duplicate_ids(rows_protect, user_rules=[rule_prot_a])[0]
check("protect 覆盖内置勾选→空", len(r_prot) == 0, f"got {sorted(r_prot)}")

# protect 不相关的文件→保持内置结果
rule_prot_b = {"action":"protect", "conditions":[{"field":"file_name","op":"contains","value":"noexists"}]}
r_prot2 = compute_duplicate_ids(rows_protect, user_rules=[rule_prot_b])[0]
check("protect 不相关→保持内置", sorted(r_prot2) == [1], f"got {sorted(r_prot2)}")

log("\n=== 复合条件 (AND) ===")
rule_and = {"action":"check", "conditions":[{"field":"author","op":"eq","value":"某作"}, {"field":"progress","op":"gt","value":"40"}]}
check_ids_and, _ = _apply_user_rules([r_a, r_b], [rule_and])
check("某作 AND progress>40→只命中文件1", sorted(check_ids_and) == [1], f"got {sorted(check_ids_and)}")

rule_and2 = {"action":"check", "conditions":[{"field":"author","op":"eq","value":"某作"}, {"field":"progress","op":"eq","value":"完结"}]}
check_ids_and2, _ = _apply_user_rules([r_a, r_b], [rule_and2])
check("某作 AND progress=完结→只命中文件2", sorted(check_ids_and2) == [2], f"got {sorted(check_ids_and2)}")

log("\n=== 多规则组合：check + protect 顺序 ===")
# 3 个精确重复: 保留最新(3), 勾选 [1,2]
rows_multi = [
    {"id": 1, "file_name": "a.txt", "file_size": 100, "novel_name": "书", "author": "某", "progress": "50", "created_date": "2024-01-01"},
    {"id": 2, "file_name": "b.txt", "file_size": 100, "novel_name": "书", "author": "某", "progress": "50", "created_date": "2024-01-02"},
    {"id": 3, "file_name": "c.txt", "file_size": 100, "novel_name": "书", "author": "某", "progress": "50", "created_date": "2024-01-03"},
]
builtin_multi = compute_duplicate_ids(rows_multi)[0]
check("内置规则1: 勾选[1,2]", sorted(builtin_multi) == [1, 2], f"got {sorted(builtin_multi)}")

# check progress=50(全部) + protect file_name=b.txt(保护文件2)
# 最终: [1,2] ∪ [1,2,3] - [2] = [1,3]
rule_chk = {"action":"check", "conditions":[{"field":"progress","op":"eq","value":"50"}]}
rule_prt = {"action":"protect", "conditions":[{"field":"file_name","op":"eq","value":"b.txt"}]}
r_m = compute_duplicate_ids(rows_multi, user_rules=[rule_chk, rule_prt])[0]
check("多规则: check+protect→[1,3]", sorted(r_m) == [1, 3], f"got {sorted(r_m)}")

# protect后执行: all protected → empty
r_m2 = compute_duplicate_ids(rows_multi, user_rules=[rule_chk, {"action":"protect", "conditions":[{"field":"file_size","op":"gt","value":"0"}]}])[0]
check("protect在最后→空", len(r_m2) == 0, f"got {sorted(r_m2)}")
# check后执行: check重新勾选
r_m3 = compute_duplicate_ids(rows_multi, user_rules=[{"action":"protect", "conditions":[{"field":"file_size","op":"gt","value":"0"}]}, rule_chk])[0]
check("check在最后→全部勾选", sorted(r_m3) == [1, 2, 3], f"got {sorted(r_m3)}")

log("\n=== 禁用内置规则 + 仅自定义规则 ===")
rows_only_user = [
    {"id": 1, "file_name": "a.txt", "file_size": 100, "novel_name": "书", "author": "某", "progress": "50", "created_date": "2024-01-01"},
    {"id": 2, "file_name": "b.txt", "file_size": 100, "novel_name": "书", "author": "某", "progress": "50", "created_date": "2024-01-02"},
]
r_d = compute_duplicate_ids(rows_only_user, enabled_rules=set(), user_rules=[{"action":"check", "conditions":[{"field":"file_size","op":"gt","value":"0"}]}])[0]
check("禁内置+仅自定义", sorted(r_d) == [1, 2], f"got {sorted(r_d)}")

# 无匹配用户规则时不应该勾选
r_e = compute_duplicate_ids(rows_only_user, enabled_rules=set(), user_rules=[{"action":"check", "conditions":[{"field":"author","op":"eq","value":"不存在"}]}])[0]
check("禁内置+无匹配→空", len(r_e) == 0, f"got {sorted(r_e)}")

log("")
summary = f"==== 自定义规则引擎测试: {PASS} pass / {FAIL} fail ===="
print(summary)
LOG_LINES.append(summary)
with io.open(os.path.join(os.path.dirname(__file__), "test_user_rules_result.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(LOG_LINES))
    f.write(f"\n\nPASS={PASS}\nFAIL={FAIL}\n")
sys.exit(1 if FAIL else 0)
