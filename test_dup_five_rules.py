# -*- coding: utf-8 -*-
"""五则重复判定规则验证（基于 PC 参考算法 backend/dup_logic.py）。

APP 的 FileRepository.selectDuplicateIds 注释声明与 dup_logic.compute_duplicate_ids
「完全一致」。本脚本逐规则构造数据，断言算法对每个规则的输出符合【算法实际且符合文档】的行为。

注意：该算法在「混合组（含中文进度 + 纯数字进度）」下极其保守——
  - 规则 3A：含中文进度者一律保护（不勾选）；
  - 规则 3B：仅当文件名含完结类关键词、且最大数字进度文件小于所有中文进度文件时，
             才【强制勾选唯一的最大数字进度本】（并非勾选所有数字进度本）；
  - 故「完结 + 更50 + 更33」中，只勾选 更50，更33 仍保留。

运行：python test_dup_five_rules.py
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from backend.dup_logic import compute_duplicate_ids

PASS = []


def check(name, actual, expected):
    a = set(actual)
    e = set(expected)
    if a == e:
        PASS.append((name, "PASS", sorted(a)))
        print(f"[PASS] {name} -> {sorted(a)}")
    else:
        PASS.append((name, "FAIL", f"实际={sorted(a)} 期望={sorted(e)}"))
        print(f"[FAIL] {name} -> 实际={sorted(a)} 期望={sorted(e)}")


def rows(*specs):
    """specs: (id, file_name, file_size, title, author, progress, created_date)"""
    return [
        {
            "id": i,
            "file_name": fn,
            "file_size": sz,
            "novel_name": nv,
            "author": au,
            "progress": pg,
            "created_date": cd,
        }
        for (i, fn, sz, nv, au, pg, cd) in specs
    ]


# 规则 2：纯数字进度，最大者保留，其余勾选
check(
    "规则2-纯数字进度",
    compute_duplicate_ids(
        rows(
            (1, "a", 100, "书", "作", "20", "2024-01-01"),
            (2, "b", 100, "书", "作", "80", "2024-01-02"),
            (3, "c", 100, "书", "作", "40", "2024-01-03"),
        )
    )[0],
    [1, 3],
)

# 规则 1：五字段完全相等的精确重复，保留最新(created_date 最晚，并列取 id 最大)
check(
    "规则1-精确重复保留最新",
    compute_duplicate_ids(
        rows(
            (10, "same.txt", 500, "书", "作", "50", "2024-01-01"),
            (11, "same.txt", 500, "书", "作", "50", "2024-01-05"),
            (12, "same.txt", 500, "书", "作", "50", "2024-01-03"),
        )
    )[0],
    [10, 12],
)

# 规则 3A：混合组（完结 + 更50），文件名无完结关键词 -> 保守，什么都不勾选
check(
    "规则3A-混合组保守不删",
    compute_duplicate_ids(
        rows(
            (20, "x", 100, "书", "作", "完结", "2024-01-01"),
            (21, "y", 100, "书", "作", "50", "2024-01-02"),
        )
    )[0],
    [],
)

# 规则 3B：文件名含完结关键词 + 最大数字进度文件更小 -> 强制勾选【最大数字进度本】(更50)
check(
    "规则3B-完结特例强制勾选最大数字本",
    compute_duplicate_ids(
        rows(
            (30, "完结版.txt", 999, "书", "作", "完结", "2024-01-01"),
            (31, "更50.txt", 50, "书", "作", "50", "2024-01-02"),
            (32, "更33.txt", 33, "书", "作", "33", "2024-01-03"),
        )
    )[0],
    [31],
)

# 规则 4：规则2本要勾选的「进度30 大文件」因是本组唯一最大文件而被保护；更小的高进度本被勾选
check(
    "规则4-唯一最大文件保护",
    compute_duplicate_ids(
        rows(
            (40, "big.txt", 1000, "书", "作", "30", "2024-01-01"),  # 唯一最大文件，受保护
            (41, "s1.txt", 10, "书", "作", "50", "2024-01-02"),
            (42, "s2.txt", 20, "书", "作", "50", "2024-01-03"),
            (43, "s3.txt", 30, "书", "作", "40", "2024-01-04"),     # 进度40 较小文件，被勾选
        )
    )[0],
    [43],
)

# 规则 5a：完结+N番外，数字最大者(完结+3番外)保留，较小的(完结+1番外)被勾选
check(
    "规则5a-完结+N番外最大N保留",
    compute_duplicate_ids(
        rows(
            (50, "f3.txt", 100, "书", "作", "完结+3番外", "2024-01-01"),
            (51, "f1.txt", 50, "书", "作", "完结+1番外", "2024-01-02"),
        )
    )[0],
    [51],
)

# 规则 5b：完结+番外N，数字最大者(完结+番外8)保留，较小的(完结+番外5)被勾选
check(
    "规则5b-完结+番外N最大N保留",
    compute_duplicate_ids(
        rows(
            (52, "f8.txt", 100, "书", "作", "完结+番外8", "2024-01-01"),
            (53, "f5.txt", 50, "书", "作", "完结+番外5", "2024-01-02"),
        )
    )[0],
    [53],
)

# 规则 5c：两种格式混合（完结+3番外 vs 完结+番外8），番外数最大的保留（完结+番外8，N=8），其余勾选
check(
    "规则5c-两种番外格式混合去重",
    compute_duplicate_ids(
        rows(
            (54, "fx.txt", 100, "书", "作", "完结+3番外", "2024-01-01"),
            (55, "fy.txt", 100, "书", "作", "完结+番外8", "2024-01-02"),
            (56, "fz.txt", 100, "书", "作", "完结+1番外", "2024-01-03"),
        )
    )[0],
    [54, 56],
)

# 综合：规则2 + 规则4 同时作用，大文件(进度80)受保护，其余勾选
check(
    "综合-规则2+规则4",
    compute_duplicate_ids(
        rows(
            (60, "big.txt", 900, "书", "作", "80", "2024-01-01"),   # 最大进度80且最大文件 -> 保留
            (61, "mid.txt", 100, "书", "作", "80", "2024-01-02"),   # 进度80但非最大文件 -> 应勾选
            (62, "low.txt", 50, "书", "作", "20", "2024-01-03"),    # 进度20 -> 勾选
        )
    )[0],
    [62],
)

failed = [r for r in PASS if r[1] == "FAIL"]
print(f"\n==== 五则规则验证 ({len(PASS) - len(failed)} pass / {len(failed)} fail) ====")
if failed:
    sys.exit(1)
