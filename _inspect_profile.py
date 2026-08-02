# -*- coding: utf-8 -*-
"""临时工具：解析 mobileprovision 查看已注册设备（前缀 _ 已被 .gitignore 忽略）"""
import os
import plistlib
import subprocess
import tempfile

PROFILE = r"D:\user\key\ios\bookscleanadhoc2.mobileprovision"
OPENSSL = r"D:\Install\strawberry-perl\Strawberry\c\bin\openssl.exe"

plist_path = os.path.join(tempfile.gettempdir(), "profile.plist")
r = subprocess.run(
    [OPENSSL, "smime", "-inform", "DER", "-verify", "-noverify",
     "-in", PROFILE, "-out", plist_path],
    capture_output=True, text=True,
)
if r.returncode != 0:
    print("openssl 提取失败:", r.stderr)
    raise SystemExit(1)

with open(plist_path, "rb") as f:
    p = plistlib.load(f)

print("Name     :", p.get("Name"))
print("UUID     :", p.get("UUID"))
print("AppID    :", p.get("Entitlements", {}).get("application-identifier"))
print("Expires  :", p.get("ExpirationDate"))
print("Team     :", p.get("TeamIdentifier"))
devs = p.get("ProvisionedDevices") or []
print("DeviceCount:", len(devs))
for x in devs:
    print("   UDID:", x)
