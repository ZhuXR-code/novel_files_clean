# -*- coding: utf-8 -*-
"""用户自定义规则引擎调试"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from backend.dup_logic import compute_duplicate_ids, _eval_user_condition, _eval_user_rule, _apply_user_rules

rows = [
    {"id": 1, "file_name": "a.txt", "file_size": 100, "novel_name": "书", "author": "某作", "progress": "50", "created_date": "2024-01-01"},
    {"id": 2, "file_name": "b.txt", "file_size": 80, "novel_name": "书", "author": "某作", "progress": "完结", "created_date": "2024-01-02"},
    {"id": 3, "file_name": "c.txt", "file_size": 60, "novel_name": "书", "author": "其他", "progress": "30", "created_date": "2024-01-03"},
]

# --- debug between ---
r3 = rows[2]
print(f"between debug: file_size=60, between 50,100 = {_eval_user_condition(r3, {'field':'file_size','op':'between','value':'50,100'})}")

# --- debug protect ---
rule_protect = {"action":"protect", "conditions":[{"field":"author","op":"eq","value":"某作"}]}
check_ids, protect_ids = _apply_user_rules(rows, [rule_protect])
print(f"protect: check_ids={sorted(check_ids)}, protect_ids={sorted(protect_ids)}")
builtin = compute_duplicate_ids(rows, enabled_rules=None, user_rules=[])
print(f"builtin only: {sorted(builtin[0])}")
builtin_with_protect = compute_duplicate_ids(rows, user_rules=[rule_protect])
print(f"builtin+protect: {sorted(builtin_with_protect[0])}")

# --- debug 多规则 ---
rule_check = {"action":"check", "conditions":[{"field":"progress","op":"gt","value":"40"}]}
rule_prot = {"action":"protect", "conditions":[{"field":"progress","op":"eq","value":"完结"}]}
print(f"单个条件 gt(40) 评估 row1(50): {_eval_user_condition(rows[0], {'field':'progress','op':'gt','value':'40'})}")
print(f"单个条件 gt(40) 评估 row3(30): {_eval_user_condition(rows[2], {'field':'progress','op':'gt','value':'40'})}")
check_ids2, protect_ids2 = _apply_user_rules(rows, [rule_check, rule_prot])
print(f"多规则: check={sorted(check_ids2)}, protect={sorted(protect_ids2)}")
r = compute_duplicate_ids(rows, user_rules=[rule_check, rule_prot])
print(f"多规则最终: {sorted(r[0])}")

# Debug: show what builtins produce
r_builtin, count, detail = compute_duplicate_ids(rows)
print(f"\nBuiltin details:")
for d in detail:
    print(f"  {d}")
print(f"Subgroups: {count}, result: {sorted(r_builtin)}")

import io
with io.open(os.path.join(os.path.dirname(__file__), "test_user_rules_debug.txt"), "w", encoding="utf-8") as f:
    f.write("debug complete")
