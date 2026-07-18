"""本地 EXE 启动器（pywebview 本地软件版）。

职责：
  1. 设置 DB_BACKEND=sqlite（必须在导入 backend.app 之前），
     使网页版 MySQL 代码路径完全不被触碰，本地使用内置 SQLite。
  2. 在后台线程启动 FastAPI/uvicorn 服务（仅监听 127.0.0.1，不外网）。
  3. 服务就绪后，用 pywebview 打开一个本地窗口，把前端 index.html
     直接嵌进窗口；全程在软件窗口内操作，不再打开浏览器、不联网。
  4. 关闭窗口即退出整个应用（含后端服务）。

打包说明：用 PyInstaller 以本文件为入口（windowed 模式），并把 frontend/
目录作为数据文件打入，即可生成可安装的本地软件（单文件 EXE）。
"""
import os
import sys
import time
import socket
import threading

from backend.logger import logger

# ---- 关键：必须在导入 backend.app 之前设置 SQLite 模式 ----
os.environ['DB_BACKEND'] = 'sqlite'
logger.info('启动本地软件版 launcher（DB_BACKEND=sqlite）')

# 便携模式：用 `launcher.exe --portable` 启动，或设置环境变量 SQLITE_DB_PATH，
# 则数据库文件放在程序旁边（FileScannerData/file_scanner.db），便于整体拷贝。
_args = sys.argv[1:]
if '--portable' in _args and 'SQLITE_DB_PATH' not in os.environ:
    _exe_dir = os.path.dirname(os.path.abspath(sys.executable))
    os.environ['SQLITE_DB_PATH'] = os.path.join(_exe_dir, 'FileScannerData', 'file_scanner.db')


def find_free_port(preferred=8000, limit=20):
    """从 preferred 开始找一个可用端口"""
    for p in range(preferred, preferred + limit):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('127.0.0.1', p))
                return p
        except OSError:
            continue
    return preferred


def wait_for_server(url, timeout=30):
    import urllib.request
    import urllib.error
    start = time.time()
    while time.time() - start < timeout:
        try:
            with urllib.request.urlopen(url, timeout=3) as resp:
                if resp.status == 200:
                    return True
        except (urllib.error.URLError, ConnectionError, OSError):
            time.sleep(0.5)
    return False


def main():
    import uvicorn
    import webview
    import backend.app as backend_app
    from backend.db_config import sqlite_db_path

    port = find_free_port(8000)
    url = f'http://127.0.0.1:{port}'
    logger.info(f'选定本地端口: {port}')

    # 启动 uvicorn（后台线程）
    # 固定使用纯 Python 实现（h11 / asyncio），避免 PyInstaller 打包时
    # 对 httptools / uvloop / watchfiles 等 C 扩展依赖收集不全导致启动崩溃。
    config = uvicorn.Config(backend_app.app, host='127.0.0.1', port=port,
                            log_level='info', access_log=False,
                            http='h11', ws='none', loop='asyncio')
    server = uvicorn.Server(config)
    threading.Thread(target=server.run, daemon=True).start()

    # 等待服务就绪
    ready = wait_for_server(url + '/', timeout=30)
    if not ready:
        logger.error('本地服务未能在 30 秒内就绪，启动失败')
        # 服务没起来，弹个系统错误框提示（不依赖浏览器）
        try:
            import tkinter as tk
            from tkinter import messagebox
            _r = tk.Tk()
            _r.withdraw()
            messagebox.showerror('启动失败', '本地服务未能在 30 秒内启动，请重试或联系开发者。')
        except Exception:
            pass
        os._exit(1)
    logger.info(f'本地服务已就绪: {url}')

    db_path = sqlite_db_path()

    # ---------- 本地软件窗口：把前端页面直接嵌进窗口 ----------
    window = webview.create_window(
        '文件扫描管理系统（本地版）',
        url,
        width=1280,
        height=860,
        min_size=(900, 600),
        text_select=True,
        confirm_close=False,
    )

    def on_window_closed():
        """窗口关闭时停掉后端服务并退出整个进程"""
        logger.info('窗口已关闭，正在退出本地服务...')
        try:
            server.should_exit = True
        except Exception:
            pass
        # 给服务一点时间退出
        time.sleep(0.3)
        logger.info('本地软件版 launcher 已退出')
        os._exit(0)

    window.events.closed += on_window_closed

    # webview.start() 阻塞直到所有窗口关闭；Windows 上须在主线程调用。
    # pywebview 在 Windows 下默认使用 WebView2 (Edge 内核) 后端，
    # 通过 .NET/pythonnet 桥接，无需打包浏览器，体积小。
    webview.start()


if __name__ == '__main__':
    main()
