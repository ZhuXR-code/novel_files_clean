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
import ctypes

from backend.logger import logger

# 命名互斥体：用于安装/更新时让 Inno Setup 能可靠识别并关闭正在运行的旧实例。
# 必须与 build/FileScanner.iss 中的 AppMutex 完全一致（含 Global\ 前缀）。
_APP_MUTEX_NAME = 'Global\\FileScannerAppMutex'
_app_mutex = None


def _acquire_app_mutex():
    """Windows 上创建并持有命名互斥体，直到进程退出。

    安装程序（Inno Setup）据 AppMutex 检测到“有对应应用正在运行”，
    并向该进程发送关闭信号；本进程收到（窗口被关闭）后会立即退出，
    从而释放对 FileScanner.exe 的文件锁，避免安装/更新时卡顿或报错。
    """
    global _app_mutex
    if os.name != 'nt':
        return
    try:
        kernel32 = ctypes.windll.kernel32
        # 不继承、初始未被占用
        _app_mutex = kernel32.CreateMutexW(None, False, _APP_MUTEX_NAME)
        if not _app_mutex or _app_mutex == 0:
            _app_mutex = None
    except Exception:
        _app_mutex = None

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
    # 窗口尺寸自适应当前用户屏幕：按主屏分辨率乘系数，不再写死像素，
    # 这样在不同分辨率/缩放的电脑上，页面展示宽度都能铺满、自适应。
    try:
        _sm = ctypes.windll.user32
        _sw, _sh = _sm.GetSystemMetrics(0), _sm.GetSystemMetrics(1)
        _win_w = max(960, int(_sw * 0.92))
        _win_h = max(640, int(_sh * 0.9))
    except Exception:
        _win_w, _win_h = 1280, 860

    # 创建命名互斥体，供安装程序检测并关闭旧实例（见 _acquire_app_mutex 说明）
    _acquire_app_mutex()

    window = webview.create_window(
        '文件扫描管理系统（本地版）',
        url,
        width=_win_w,
        height=_win_h,
        min_size=(900, 600),
        text_select=True,
        confirm_close=False,
    )

    def on_window_closed():
        """窗口关闭时停掉后端服务（真正退出在 webview.start() 之后统一进行）"""
        logger.info('窗口已关闭，正在停止本地服务...')
        try:
            server.should_exit = True
        except Exception:
            pass

    window.events.closed += on_window_closed

    # webview.start() 阻塞直到所有窗口关闭——无论用户点击 X，还是
    # 安装程序/系统发送 WM_CLOSE。一旦返回即代表窗口已关闭，此处立即
    # 强制退出整个进程，确保 FileScanner.exe 的文件锁被尽快释放。
    # 这是修复“安装时旧实例关不掉/卡顿报错”的根本：进程必须真正退出，
    # 安装程序才能替换文件。
    webview.start()
    logger.info('本地软件版 launcher 已退出')
    os._exit(0)


if __name__ == '__main__':
    main()
