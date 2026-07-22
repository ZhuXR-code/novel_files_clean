"""测试「删除源文件」功能（前端删除弹框选 deleteMode=file -> DELETE /api/results/with-files）。

覆盖：
  A. 仅删数据库记录（DELETE /api/results）          -> 源文件保留、记录消失
  B. 物理删除源文件   （DELETE /api/results/with-files） -> 源文件被删、记录消失、其他文件不受影响
  C. 路径越界安全校验  （file_path 不在扫描目录内）   -> 进入 failed_files、文件不删、记录不删

使用 SQLite 临时库 + 临时沙箱，绝不触碰真实数据。
运行：python test_delete_source_files.py
"""
import os, sys, time, shutil, json, logging, tempfile, datetime

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
TEMP_DIR = tempfile.mkdtemp(prefix='.del_src_')
DB_PATH = os.path.join(TEMP_DIR, 'del_test.db')
RESULT_PATH = os.path.join(TEMP_DIR, 'result.json')

os.environ['DB_BACKEND'] = 'sqlite'
os.environ['SQLITE_DB_PATH'] = DB_PATH

from fastapi.testclient import TestClient
from backend.app import app


def write_result(results):
    passed = sum(1 for status, _ in results if status.startswith('PASS'))
    payload = {'passed': passed, 'total': len(results), 'results': results}
    with open(RESULT_PATH, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    print(f'\n==== 删除源文件 测试结果 ({passed}/{len(results)}) ====')
    for status, msg in results:
        print(f'  [{status}] {msg}')


def main():
    results = []
    sandbox = os.path.join(TEMP_DIR, 'sandbox')
    os.makedirs(sandbox)
    files = {
        '都市奇缘_张三_更60.txt': '第一章 开始\n这是测试小说A的内容。',
        '都市奇缘_张三_更33.txt': '第一章 开始\n这是测试小说A的另一进度。',
        '仙侠世界_李四.txt': '第一章 开始\n这是测试小说B的内容。',
    }
    for name, content in files.items():
        with open(os.path.join(sandbox, name), 'w', encoding='utf-8') as f:
            f.write(content)

    with TestClient(app) as client:
        # 1) 创建配置
        r = client.post('/api/configs', json={
            'name': 'deltest', 'folder_path': sandbox,
            'file_types': '.txt', 'parse_on_scan': False})
        assert r.status_code in (200, 201), f'创建配置失败: {r.status_code} {r.text}'
        config_id = r.json()['id']

        # 2) 扫描
        r = client.post(f'/api/scan/{config_id}')
        assert r.status_code in (200, 202), f'扫描失败: {r.status_code} {r.text}'
        for _ in range(180):
            st = client.get(f'/api/scan-progress/{config_id}').json()
            if st.get('done'):
                break
            time.sleep(0.3)
        else:
            results.append(('FAIL', '扫描未完成（超时）'))
            write_result(results)
            return

        # 3) 取记录
        r = client.get('/api/results', params={'config_id': config_id})
        assert r.status_code == 200, r.text
        items = r.json()['items']
        by_name = {it['file_name']: it for it in items}
        r1 = by_name['都市奇缘_张三_更60.txt']   # 用于物理删除
        r2 = by_name['仙侠世界_李四.txt']         # 用于仅删库
        r3 = by_name['都市奇缘_张三_更33.txt']     # 见证：其他文件不受影响

        # ---------- 测试 A：物理删除源文件 ----------
        r = client.delete('/api/results/with-files', params={'ids': [r1['id']]})
        data = r.json()
        ok = (r.status_code in (200, 202) and data.get('deleted', 0) >= 1
              and data.get('failed_files', []) == []
              and not os.path.exists(r1['file_path']))
        results.append(('PASS' if ok else 'FAIL',
                         f"物理删除源文件: HTTP={r.status_code} deleted={data.get('deleted')} "
                         f"failed={data.get('failed_files')} 文件已删={not os.path.exists(r1['file_path'])}"))
        # 其他文件不受影响
        intact = os.path.exists(r2['file_path']) and os.path.exists(r3['file_path'])
        results.append(('PASS' if intact else 'FAIL',
                         f"物理删除不影响其他文件: 更33存在={os.path.exists(r3['file_path'])} 仙侠存在={os.path.exists(r2['file_path'])}"))
        # r1 记录应已消失
        r = client.get('/api/results', params={'config_id': config_id})
        ids_left = [it['id'] for it in r.json()['items']]
        results.append(('PASS' if r1['id'] not in ids_left else 'FAIL',
                         f"物理删除后记录消失: id={r1['id']} 剩余={ids_left}"))

        # ---------- 测试 B：仅删数据库记录 ----------
        r = client.delete('/api/results', params={'ids': [r2['id']]})
        data = r.json()
        ok = (r.status_code in (200, 202) and data.get('deleted', 0) >= 1
              and os.path.exists(r2['file_path']))
        results.append(('PASS' if ok else 'FAIL',
                         f"仅删数据库记录: HTTP={r.status_code} deleted={data.get('deleted')} "
                         f"源文件保留={os.path.exists(r2['file_path'])}"))
        r = client.get('/api/results', params={'config_id': config_id})
        ids_left = [it['id'] for it in r.json()['items']]
        results.append(('PASS' if r2['id'] not in ids_left else 'FAIL',
                         f"仅删库后记录消失: id={r2['id']} 剩余={ids_left}"))

        # ---------- 测试 C：路径越界安全校验 ----------
        from backend.app import SessionLocal
        from backend.models import ScanResult
        outside_path = os.path.join(TEMP_DIR, 'outside.txt')  # 在 sandbox 之外
        with open(outside_path, 'w', encoding='utf-8') as f:
            f.write('越界文件')
        db = SessionLocal()
        rec = ScanResult(file_name='outside.txt', file_size=10, file_path=outside_path,
                         scan_config_id=config_id, scanned_at=datetime.datetime.now())
        db.add(rec)
        db.commit()
        db.refresh(rec)
        out_id = rec.id
        db.close()

        r = client.delete('/api/results/with-files', params={'ids': [out_id]})
        data = r.json()
        # 越界文件应被拒绝（进入 failed_files），且文件本身不应被删
        ok = (r.status_code in (200, 202)
              and outside_path in data.get('failed_files', [])
              and os.path.exists(outside_path))
        # 记录不应被删（因为物理删除失败，with-files 不删该记录）
        r = client.get('/api/results', params={'config_id': config_id})
        ids_left = [it['id'] for it in r.json()['items']]
        rec_kept = out_id in ids_left
        ok = ok and rec_kept
        results.append(('PASS' if ok else 'FAIL',
                         f"路径越界安全校验: failed={data.get('failed_files')} "
                         f"越界文件未被删={os.path.exists(outside_path)} 记录保留={rec_kept}"))

    write_result(results)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        write_result([('ERROR', f'{type(e).__name__}: {e}')])
    finally:
        logging.shutdown()
        shutil.rmtree(TEMP_DIR, ignore_errors=True)
