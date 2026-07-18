import re, subprocess, time

ADB = r"D:\adb_tools\adb.exe"
DEV = "127.0.0.1:7555"


def adb(args):
    return subprocess.run([ADB, "-s", DEV] + args,
                         capture_output=True, text=True).stdout


def dump(name):
    adb(["shell", "uiautomator", "dump", "/sdcard/%s.xml" % name])
    adb(["pull", "/sdcard/%s.xml" % name, name])
    return open(name, encoding="utf-8").read()


def texts_of(xml):
    return sorted(set(re.findall(r'text="([^"]+)"', xml)))


def tap_text(xml, text):
    pat = r'text="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' % re.escape(text)
    m = re.search(pat, xml)
    if not m:
        print("NOT FOUND:", text)
        return False
    x1, y1, x2, y2 = map(int, m.groups())
    cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
    adb(["shell", "input", "tap", str(cx), str(cy)])
    print("TAP", text, "->", (cx, cy))
    return True


home = dump("h.xml")
print("HOME:", [t for t in texts_of(home) if t in ("查看文库", "开始扫描")])

tap_text(home, "查看文库")
time.sleep(3)
runlist = dump("r.xml")
print("RUNLIST:", texts_of(runlist)[:30])

tap_text(runlist, "测试3万条")
time.sleep(4)
lib = dump("lib.xml")
print("LIB TEXTS:")
for t in texts_of(lib):
    print("  -", t)
