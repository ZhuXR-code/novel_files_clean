# -*- coding: utf-8 -*-
"""一键清理（one-click cleanup）端到端测试。

使用 SQLite 临时库 + FastAPI TestClient（with 上下文触发 lifespan 初始化数据库），
构造沙箱目录触发重复标记，覆盖三种 pipeline 确认路径：
  1) action='cancel'  -> 不删除任何记录，源文件保留
  2) delete_mode='db' -> 仅删数据库记录，源文件保留
  3) delete_mode='file'-> 删数据库记录 + 物理删除源文件
"""
import os, sys, time, shutil, json, logging, tempfile, atexit

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
TEMP_DIR = tempfile.mkdtemp(prefix='clean_test_', dir=PROJECT_ROOT)
DB_PATH = os.path.join(TEMP_DIR, 'clean_test.db')
RESULT_PATH = os.path.join(TEMP_DIR, 'result.json')

os.environ['DB_BACKEND'] = 'sqlite'
os.environ['SQLITE_DB_PATH'] = DB_PATH

from fastapi.testclient import TestClient
from backend.app import app


def make_sandbox(name, files):
    d = os.path.join(TEMP_DIR, name)
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(d)
    for fname, content in files:
        with open(os.path.join(d, fname), 'w', encoding='utf-8') as f:
            f.write(content)
    return d


def get_total(client, config_id):
    r = client.get(f'/api/results?config_id={config_id}&limit=1')
    assert r.status_code == 200, f'get results 失败: {r.status_code}'
    return r.json().get('total', 0)


def wait_await_confirm(client):
    for _ in range(180):
        st = client.get('/api/pipeline/status').json()
        nodes = st.get('nodes') or []
        clean = next((n.get('status') for n in nodes if n.get('name') == 'clean'), None)
        if clean == 'awaiting_confirm' or st.get('status') == 'awaiting_confirm':
            return st
        if st.get('status') in ('error', 'done'):
            return st
        time.sleep(0.5)
    raise TimeoutError('等待 awaiting_confirm 超时')


def wait_finished(client):
    for _ in range(120):
        st = client.get('/api/pipeline/status').json().get('status')
        if st in ('done', 'cancelled', 'error'):
            return st
        time.sleep(0.5)


def start_and_confirm(client, config_id, delete_mode, action):
    # action='confirm' -> 二次确认删除；action='cancel' -> 取消（跳过删除）
    r = client.post('/api/pipeline/start', json={'config_id': config_id, 'delete_mode': delete_mode})
    assert r.status_code in (200, 202), f'start 失败: {r.status_code} {r.text}'
    st = wait_await_confirm(client)
    deletion_count = st.get('deletion_count')
    to_delete = [it['file_path'] for it in (st.get('preview_sample') or [])]
    if action == 'cancel':
        r = client.post('/api/pipeline/cancel')
        assert r.status_code in (200, 202), f'cancel 失败: {r.status_code}'
    else:
        r = client.post('/api/pipeline/confirm', json={'action': action})
        assert r.status_code in (200, 202), f'confirm 失败: {r.status_code}'
    wait_finished(client)
    return deletion_count, to_delete


def run_all():
    results = []
    with TestClient(app) as client:  # with 触发 lifespan -> init_database
        files_a = [
            ('《都市奇缘》作者：张三（更50）.txt', '这是进度50的版本。' * 5),
            ('《都市奇缘》作者：张三（更40）.txt', '这是进度40的版本。' * 4),
        ]
        files_b = [
            ('《江湖路远》作者：李四（更80）.txt', '进度80的版本。' * 8),
            ('《江湖路远》作者：李四（更20）.txt', '进度20的版本。' * 2),
        ]
        files_c = [
            ('《雪中悍刀》作者：王五（更60）.txt', '进度60版本。' * 6),
            ('《雪中悍刀》作者：王五（更33）.txt', '进度33版本。' * 3),
        ]

        # 测试1：cancel 路径（db 模式，确认取消 -> 不删除）
        d1 = make_sandbox('cancel', files_a)
        cid1 = client.post('/api/configs', json={
            'name': 'clean_test_cancel', 'folder_path': d1,
            'file_types': '.txt', 'parse_on_scan': True}).json()['id']
        dc1, _ = start_and_confirm(client, cid1, 'db', 'cancel')
        assert dc1 == 1, f'[cancel] 应标记1个待删除，实际 {dc1}'
        assert get_total(client, cid1) == 2, f'[cancel] 取消后记录数应为2，实际 {get_total(client, cid1)}'
        assert os.path.exists(os.path.join(d1, files_a[1][0])), '[cancel] 源文件不应被删'
        results.append(('cancel路径: 取消不删除任何记录/源文件保留', 'PASS'))

        # 测试2：db 删除路径（仅删库记录，源文件保留）
        d2 = make_sandbox('db_del', files_b)
        cid2 = client.post('/api/configs', json={
            'name': 'clean_test_db', 'folder_path': d2,
            'file_types': '.txt', 'parse_on_scan': True}).json()['id']
        dc2, _ = start_and_confirm(client, cid2, 'db', 'confirm')
        assert dc2 == 1, f'[db] 应标记1个待删除，实际 {dc2}'
        assert get_total(client, cid2) == 1, f'[db] 确认后记录数应为1，实际 {get_total(client, cid2)}'
        assert os.path.exists(os.path.join(d2, files_b[0][0])), '[db] 更80源文件应保留'
        assert os.path.exists(os.path.join(d2, files_b[1][0])), '[db] 更20源文件应保留(仅删库记录)'
        results.append(('db删除路径: 仅删库记录/源文件保留', 'PASS'))

        # 测试3：file 删除路径（删库记录 + 物理删除源文件）
        d3 = make_sandbox('file_del', files_c)
        cid3 = client.post('/api/configs', json={
            'name': 'clean_test_file', 'folder_path': d3,
            'file_types': '.txt', 'parse_on_scan': True}).json()['id']
        dc3, to_delete = start_and_confirm(client, cid3, 'file', 'confirm')
        assert dc3 == 1, f'[file] 应标记1个待删除，实际 {dc3}'
        assert get_total(client, cid3) == 1, f'[file] 确认后记录数应为1，实际 {get_total(client, cid3)}'
        assert os.path.exists(os.path.join(d3, files_c[0][0])), '[file] 更60源文件应保留'
        assert not os.path.exists(os.path.join(d3, files_c[1][0])), '[file] 更33源文件应被物理删除'
        assert to_delete, '[file] 应返回待删文件路径'
        assert not os.path.exists(to_delete[0]), '[file] preview_sample 中的源文件应已删除'
        results.append(('file删除路径: 物理删除源文件', 'PASS'))

    return results


if __name__ == '__main__':
    atexit.register(lambda: (logging.shutdown(), shutil.rmtree(TEMP_DIR, ignore_errors=True)))
    out = {'passed': 0, 'results': [], 'error': None}
    try:
        results = run_all()
        out['passed'] = len(results)
        out['results'] = results
        print('\n==== 一键清理 测试结果 ====')
        for name, res in results:
            print(f'  [{res}] {name}')
        print(f'\n全部 {len(results)} 项通过')
    except Exception as e:
        import traceback as _tb
        out['error'] = f'{type(e).__name__}: {e}\n{_tb.format_exc()}'
        print('测试失败:', out['error'])
    finally:
        with open(RESULT_PATH, 'w', encoding='utf-8') as f:
            json.dump(out, f, ensure_ascii=False, indent=2)
