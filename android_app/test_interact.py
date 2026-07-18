import re, subprocess, time

ADB = r"D:\adb_tools\adb.exe"
DEV = "127.0.0.1:7555"


def adb(a):
    return subprocess.run([ADB, "-s", DEV] + a, capture_output=True, text=True).stdout


def dump(n):
    adb(["shell", "uiautomator", "dump", "/sdcard/%s.xml" % n])
    adb(["pull", "/sdcard/%s.xml" % n, n])
    return open(n, encoding="utf-8").read()


def texts_of(xml):
    return sorted(set(re.findall(r'text="([^"]+)"', xml)))


def tap(cx, cy):
    adb(["shell", "input", "tap", str(cx), str(cy)])


def tap_text(xml, text):
    m = re.search(r'text="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' % re.escape(text), xml)
    if not m:
        print("NOT FOUND:", text)
        return False
    x1, y1, x2, y2 = map(int, m.groups())
    tap((x1 + x2) // 2, (y1 + y2) // 2)
    return True


def edittexts(xml):
    return re.findall(r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)


def clear_field(n=6):
    for _ in range(n):
        adb(["shell", "input", "keyevent", "67"])


def itext(s):
    adb(["shell", "input", "text", s])


def page_texts(xml):
    return [t for t in texts_of(xml) if "页" in t or "共" in t]


lib = dump("lib.xml")
ets = edittexts(lib)
print("EDITTEXTS:", ets)
# 每页 input = first EditText
e0 = ets[0]
cx, cy = (int(e0[0]) + int(e0[2])) // 2, (int(e0[1]) + int(e0[3])) // 2
tap(cx, cy)
time.sleep(0.6)
clear_field(5)
itext("500")
time.sleep(0.6)
tap_text(lib, "应用")
time.sleep(2)
lib2 = dump("lib2.xml")
print("AFTER 应用(500) page texts:", page_texts(lib2))

# 跳到 input = second EditText
ets2 = edittexts(lib2)
print("EDITTEXTS2:", ets2)
e1 = ets2[1]
cx2, cy2 = (int(e1[0]) + int(e1[2])) // 2, (int(e1[1]) + int(e1[3])) // 2
tap(cx2, cy2)
time.sleep(0.6)
itext("30")
time.sleep(0.6)
tap_text(lib2, "跳转")
time.sleep(2)
lib3 = dump("lib3.xml")
print("AFTER 跳转(30) page texts:", page_texts(lib3))
