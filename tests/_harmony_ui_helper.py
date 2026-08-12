# -*- coding: utf-8 -*-
"""鸿蒙模拟器 UI 测试辅助脚本：截图 / 解析控件树 / 输出可交互元素坐标"""
import json, subprocess, sys, os, re

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

HDC = r"D:\Install\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_test_screenshots")

def run(*args):
    r = subprocess.run([HDC, *args], capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.stdout + r.stderr

def snap(name):
    run("shell", "snapshot_display", "-f", "/data/local/tmp/screen.jpeg")
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, name)
    run("file", "recv", "/data/local/tmp/screen.jpeg", dst)
    return os.path.abspath(dst)

def layout():
    run("shell", "uitest", "dumpLayout", "-p", "/data/local/tmp/layout.json")
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, "layout.json")
    run("file", "recv", "/data/local/tmp/layout.json", dst)
    return json.load(open(dst, encoding='utf-8'))

def walk(node, out):
    a = node.get("attributes", {})
    text = a.get("text", "")
    desc = a.get("description", "")
    label = (text or desc or "").strip()
    b = a.get("bounds", "")
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b or "")
    if label and m:
        x1, y1, x2, y2 = map(int, m.groups())
        if x2 - x1 > 0 and y2 - y1 > 0:
            out.append({
                "label": label.replace("\n", " ")[:60],
                "cx": (x1 + x2) // 2, "cy": (y1 + y2) // 2,
                "bounds": b,
                "click": a.get("clickable") == "true",
                "scroll": a.get("scrollable") == "true",
                "long": a.get("longClickable") == "true",
                "type": a.get("type", "").split(".")[-1],
            })
    for c in node.get("children", []):
        walk(c, out)

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "dump"
    if cmd == "snap":
        print(snap(sys.argv[2] if len(sys.argv) > 2 else "s.jpeg"))
    elif cmd == "dump":
        kw = sys.argv[2] if len(sys.argv) > 2 else None
        d = layout()
        out = []
        walk(d, out)
        seen, res = set(), []
        for e in out:
            k = (e["label"], e["cx"], e["cy"])
            if k in seen:
                continue
            seen.add(k)
            res.append(e)
        res.sort(key=lambda e: (e["cy"], e["cx"]))
        for e in res:
            if kw and kw not in e["label"]:
                continue
            flags = ("C" if e["click"] else "-") + ("L" if e["long"] else "-") + ("S" if e["scroll"] else "-")
            print(f"{flags} ({e['cx']},{e['cy']}) [{e['type']}] {e['label']}")
