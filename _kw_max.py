# -*- coding: utf-8 -*-
import re, io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
base = r"d:/user/project/批量文件清理和文件内容识别/txt文件清理-单工程清理/"
files = {
    "PC": ("backend/keyword_replace.py", r"'sort_order':\s*(\d+)"),
    "Android": ("android_app/app/src/main/java/com/booksclean/app/util/KeywordReplace.kt", r"sortOrder\s*=\s*(\d+)"),
    "Harmony": ("harmony_app/entry/src/main/ets/utils/KeywordReplace.ts", r"\.rule\('scan',\s*'[^']*',\s*'[^']*',\s*(\d+)\)"),
    "iOS": ("ios_app/booksclean/Core/KeywordReplace.swift", r"sortOrder:\s*(\d+)"),
}
for name,(path,pat) in files.items():
    t = open(base+path, encoding='utf-8').read()
    nums = [int(x) for x in re.findall(pat, t)]
    print(name, "max sortOrder:", max(nums), "count:", len(nums))
