"""
一键启动脚本 - 文件扫描管理系统
直接运行 python start.py 即可启动前后端
"""
import os
import sys
import time
import subprocess
import urllib.request
import urllib.error

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))


def check_dependencies():
    """检查并安装依赖"""
    print('  [1/3] 检查依赖...')
    try:
        import pymysql
        import sqlalchemy
        import fastapi
        import uvicorn
        import requests
        import chardet
        print('      依赖已就绪')
    except ImportError as e:
        print(f'      安装依赖: pip install -r requirements.txt')
        subprocess.check_call(
            [sys.executable, '-m', 'pip', 'install', '-r',
             os.path.join(PROJECT_DIR, 'requirements.txt')],
            cwd=PROJECT_DIR
        )
        print('      依赖安装完成')


def wait_for_server(url, timeout=30, interval=1):
    """等待服务启动，最多等待 timeout 秒"""
    start = time.time()
    while time.time() - start < timeout:
        try:
            resp = urllib.request.urlopen(url, timeout=5)
            if resp.status == 200:
                return True
        except (urllib.error.URLError, ConnectionResetError, ConnectionRefusedError):
            pass
        time.sleep(interval)
    return False


def main():
    print('=' * 50)
    print('  文件扫描管理系统 - 启动中...')
    print('=' * 50)

    # 检查 Python 版本
    if sys.version_info < (3, 8):
        print('[错误] 需要 Python 3.8+')
        sys.exit(1)

    check_dependencies()

    # 启动后端
    print('  [2/3] 启动后端服务...')
    backend_cmd = [sys.executable, '-m', 'backend.app']

    proc = subprocess.Popen(
        backend_cmd,
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        stdin=subprocess.DEVNULL,
    )

    # 后台线程持续消费 stderr，防止管道缓冲区满导致子进程阻塞
    stderr_lines = []
    def _consume_stderr():
        for line in iter(proc.stderr.readline, b''):
            stderr_lines.append(line)
    import threading
    stderr_thread = threading.Thread(target=_consume_stderr, daemon=True)
    stderr_thread.start()

    try:
        # 等待服务启动（最多30秒）
        print('      等待服务启动...')
        server_url = 'http://localhost:8000/'
        if wait_for_server(server_url, timeout=30):
            print('      后端服务已启动: http://localhost:8000')
        else:
            # 读取错误输出
            stderr_output = b''.join(stderr_lines).decode('utf-8', errors='replace')

            for line in stderr_output.split('\n'):
                if 'ERROR' in line or 'Error' in line or 'error' in line:
                    print(f'      错误: {line.strip()}')
            print('      启动超时，请检查日志或手动启动')
            print(f'      手动启动: python -m backend.app')
            sys.exit(1)

        print('  [3/3] 服务启动完成')
        print('=' * 50)
        print('  访问地址: http://localhost:8000')
        print('  按 Ctrl+C 停止服务')
        print('=' * 50)

        try:
            # 实时输出后端日志
            while True:
                line = proc.stdout.readline()
                if line:
                    print(line.decode('utf-8', errors='replace').rstrip())
                if proc.poll() is not None:
                    break
        except KeyboardInterrupt:
            print('\n正在停止服务...')
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait()
            print('服务已停止')
    finally:
        # 确保进程被清理
        if proc.poll() is None:
            proc.terminate()
            proc.wait()


if __name__ == '__main__':
    main()
