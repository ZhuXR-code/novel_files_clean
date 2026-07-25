# -*- coding: utf-8 -*-
"""API 端点端到端测试"""
import requests, sys, os, io
sys.stdout.reconfigure(encoding='utf-8')
LOG = []
def log(m): print(m); LOG.append(m)

base = "http://localhost:8000"
PASS = 0; FAIL = 0

def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        log(f"  [PASS] {name}" + (f" {detail}" if detail else ""))
    else:
        FAIL += 1
        log(f"  [FAIL] {name}: {detail}")

def get_list(url):
    """从响应包装中提取列表"""
    r = requests.get(url, timeout=10)
    j = r.json()
    if 'result' in j:
        return j['result']
    return j

log("=== 1. 获取勾选重复规则列表 ===")
try:
    data = get_list(f"{base}/api/dup-rule-configs")
    check("返回列表", isinstance(data, list), f"type={type(data)}")
    builtin_count = sum(1 for item in data if item.get('is_builtin'))
    check("6条内置规则", builtin_count == 6, f"got {builtin_count}")
except Exception as e:
    check("获取列表", False, str(e))

log("\n=== 2. 创建自定义规则 ===")
rule_id_1 = rule_id_2 = None
try:
    body = {"rule_name":"测试-勾选大文件","description":"勾选大于10MB","conditions":[{"field":"file_size","op":"gt","value":"10485760"}],"action":"check","enabled":True}
    r2 = requests.post(f"{base}/api/dup-rule-configs", json=body, timeout=10)
    check("创建规则1", r2.status_code in (200, 201), f"status={r2.status_code}")
    j2 = r2.json()
    rule_id_1 = j2.get('id') or (j2.get('result') or {}).get('id')
    body2 = {"rule_name":"测试-保护完结","description":"保护完结文件","conditions":[{"field":"progress","op":"eq","value":"完结"}],"action":"protect","enabled":True}
    r2b = requests.post(f"{base}/api/dup-rule-configs", json=body2, timeout=10)
    check("创建规则2", r2b.status_code in (200, 201))
    j2b = r2b.json()
    rule_id_2 = j2b.get('id') or (j2b.get('result') or {}).get('id')
except Exception as e:
    check("创建规则", False, str(e))

log("\n=== 3. 删除内置规则(应禁止) ===")
try:
    r3 = requests.delete(f"{base}/api/dup-rule-configs/1", timeout=10)
    check("禁止删除内置", r3.status_code == 403, f"status={r3.status_code}")
except Exception as e:
    check("删除内置", False, str(e))

log("\n=== 4. 删除自定义规则 ===")
if rule_id_1:
    try:
        r4 = requests.delete(f"{base}/api/dup-rule-configs/{rule_id_1}", timeout=10)
        check("删除自定义成功", r4.status_code in (200, 204), f"status={r4.status_code}")
    except Exception as e:
        check("删除自定义", False, str(e))
else:
    log("  [SKIP] 无规则ID")

log("\n=== 5. 更新自定义规则 ===")
if rule_id_2:
    try:
        body_upd = {"rule_name":"测试-保护完结-已更新","description":"更新后的描述","enabled":False}
        r6 = requests.put(f"{base}/api/dup-rule-configs/{rule_id_2}", json=body_upd, timeout=10)
        check("更新成功", r6.status_code in (200, 204), f"status={r6.status_code}")
        r6v_data = get_list(f"{base}/api/dup-rule-configs")
        updated = next((item for item in r6v_data if item['id'] == rule_id_2), None)
        check("rule_name已更新", updated and updated.get('rule_name') == "测试-保护完结-已更新")
        check("enabled已改False", updated and updated.get('enabled') == False)
    except Exception as e:
        check("更新规则", False, str(e))

log("\n=== 6. 验证最终列表 ===")
try:
    data5 = get_list(f"{base}/api/dup-rule-configs")
    check("总条数=7(6内置+1自定义)", len(data5) == 7, f"got {len(data5)}")
    for item in data5:
        log(f"    id={item['id']} name={item.get('rule_name','')[:25]} is_builtin={item.get('is_builtin')} enabled={item.get('enabled')}")
    if rule_id_1:
        check("规则1已删除", all(item['id'] != rule_id_1 for item in data5))
except Exception as e:
    check("验证列表", False, str(e))

log("\n=== 7. 配置与前端 ===")
try:
    r7 = requests.get(f"{base}/api/configs", timeout=10)
    check("获取配置", r7.status_code == 200, f"status={r7.status_code}")
except Exception as e:
    check("获取配置", False, str(e))
try:
    r8 = requests.get(f"{base}/", timeout=10)
    check("前端可访问", r8.status_code == 200, f"status={r8.status_code}")
    check("含app.js", "app.js" in r8.text)
except Exception as e:
    check("前端", False, str(e))

log("")
summary = f"==== API 端点测试: {PASS} pass / {FAIL} fail ===="
log(summary)

outpath = os.path.join(os.path.dirname(__file__), "test_api_result.txt")
with io.open(outpath, "w", encoding="utf-8") as f:
    f.write("\n".join(LOG))
sys.exit(1 if FAIL else 0)
