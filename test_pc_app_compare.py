# -*- coding: utf-8 -*-
"""
权威对比：Android APP Parser（真实编译产物） vs PC 端 regex_parser._extract_source_progress（真实函数）
关于【书名/作者/进度/来源】的提取行为。

做法：
  - PC 侧：直接 import backend.regex_parser._extract_source_progress（真实函数）。
  - APP 侧：取自真实编译后的 Parser.kt 产物（由 Java 驱动 ParserDriver 实测，见 .app_out.log）。
  - 比对 (progress, source) 是否一致。

运行：python test_pc_app_compare.py
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from backend.regex_parser import _extract_source_progress as pc_extract_source_progress

# APP 侧取值来自真实编译产物 Parser.kt（ParserDriver 实测，见 .app_out.log）。
# 每一项 = (progress, source)
APP = {
    "《都市奇缘》作者：张三（更50）.txt":          ('50', ''),
    "《都市奇缘》作者：张三（更50）精校.txt":      ('50', ''),
    "《深海》123.txt":                            ('', ''),
    "【晋江】《名》作者：王五.txt":                ('', '晋江'),
    "仙侠世界 李四 更100.txt":                    ('', ''),
    "《诛仙》作者：萧鼎 [起点] (更200).txt":       ('200', '起点'),
    "《庆余年》作者：猫腻【纵横】（更300）.txt":   ('300', '纵横'),
    "[废文]《默读》作者：priest（完结）.txt":      ('完结', '废文'),
    "《书》作者：张三（起点）.txt":                ('', '起点'),
    "《诛仙》作者：萧鼎（起点）（更200）.txt":     ('200', '起点'),
}

print("文件名 | APP(progress,source) | PC(progress,source) | 是否分歧")
print("-" * 100)
diverged = 0
for fn, appv in APP.items():
    raw = pc_extract_source_progress(fn)        # PC 返回 (source, progress)
    pcv = (raw[1], raw[0])                       # 统一为 (progress, source)
    div = (appv != pcv)
    diverged += div
    print(f"{fn}\n   APP={appv}  PC={pcv}  {'<-- 分歧' if div else '一致'}")

print(f"\n分歧数: {diverged}/{len(APP)}")
if diverged:
    sys.exit(1)
