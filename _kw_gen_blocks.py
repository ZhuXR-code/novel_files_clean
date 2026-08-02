# -*- coding: utf-8 -*-
import io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

lines = [l.strip() for l in open(r"d:/user/project/批量文件清理和文件内容识别/txt文件清理-单工程清理/_kw_new_unique.txt", encoding='utf-8').read().splitlines() if l.strip()]
assert len(lines) == 471, len(lines)

base = 522
# PC: backend/keyword_replace.py
pc = ",\n".join(
    f"    {{'scope': 'scan', 'pattern': '{w}', 'replacement': '', 'sort_order': {base+i}}}"
    for i, w in enumerate(lines)
)
# Android: KeywordReplace.kt
android = ",\n".join(
    f"        KeywordReplaceRuleEntity(scope = SCOPE_SCAN, pattern = \"{w}\", replacement = \"\", sortOrder = {base+i})"
    for i, w in enumerate(lines)
)
# Harmony: KeywordReplace.ts
harmony = ",\n".join(
    f"    KeywordReplace.rule('scan', '{w}', '', {base+i})"
    for i, w in enumerate(lines)
)
# iOS: KeywordReplace.swift
ios = ",\n".join(
    f"        KeywordReplaceRule(scope: SCOPE_SCAN, pattern: \"{w}\", replacement: \"\", sortOrder: {base+i})"
    for i, w in enumerate(lines)
)

open(r"d:/user/project/批量文件清理和文件内容识别/txt文件清理-单工程清理/_blk_pc.txt", "w", encoding="utf-8").write(pc)
open(r"d:/user/project/批量文件清理和文件内容识别/txt文件清理-单工程清理/_blk_android.txt", "w", encoding="utf-8").write(android)
open(r"d:/user/project/批量文件清理和文件内容识别/txt文件清理-单工程清理/_blk_harmony.txt", "w", encoding="utf-8").write(harmony)
open(r"d:/user/project/批量文件清理和文件内容识别/txt文件清理-单工程清理/_blk_ios.txt", "w", encoding="utf-8").write(ios)
print("生成完成, 各块行数:", pc.count(chr(10))+1)
