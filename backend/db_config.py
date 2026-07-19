"""数据库后端配置（网页版 MySQL / 本地 EXE SQLite 共存）。

通过环境变量 DB_BACKEND 切换：
  - mysql  （默认）：沿用原有 MySQL 逻辑，完全不变。
  - sqlite ：本地 EXE 模式，使用内置 SQLite 文件数据库，无需安装 MySQL。

本地 EXE 的 launcher 会在导入本模块前设置 os.environ['DB_BACKEND'] = 'sqlite'。
"""
import os
import sys
import logging


DB_BACKEND = os.environ.get('DB_BACKEND', 'mysql').lower()
IS_SQLITE = DB_BACKEND == 'sqlite'


def _is_writable(path: str) -> bool:
    """判断该路径所在目录是否可写：可写则顺便创建好目录。"""
    try:
        parent = os.path.dirname(path)
        os.makedirs(parent, exist_ok=True)
        # 用追加模式试探一下能否创建/写入文件
        with open(path, 'a'):
            pass
        return True
    except OSError:
        return False


def sqlite_db_path() -> str:
    """返回 SQLite 数据库文件路径。

    默认放在“程序所在安装目录”下的 FileScannerData\\ 子目录，即：
        <EXE 所在目录>\\FileScannerData\\file_scanner.db

    这样数据库随安装目录走，用户在安装时指定的路径即为数据根目录，
    卸载/移动整个安装目录即可整体带走或重置，数据不再散落到 %APPDATA%。

    覆盖优先级：
      1. 环境变量 SQLITE_DB_PATH（可显式指定，便于调试 / 自定义）
      2. 程序所在目录\\FileScannerData\\file_scanner.db   ← 默认（位于安装目录内）
      3. 若安装目录不可写（例如装到了受保护的 C:\\Program Files 且未提权），
         则回退到 %LOCALAPPDATA%\\FileScanner\\，避免程序崩溃。
         （正常安装到可写目录时不会触发此回退。）
    """
    env_path = os.environ.get('SQLITE_DB_PATH')
    if env_path:
        return env_path

    # 单文件 EXE 的 sys.executable 即真实安装路径（不是 PyInstaller 的临时解压目录）
    exe_dir = os.path.dirname(os.path.abspath(sys.executable))
    prefer = os.path.join(exe_dir, 'FileScannerData', 'file_scanner.db')
    if _is_writable(prefer):
        return prefer

    # 回退：安装目录不可写时，放到当前用户 Local AppData（仅兜底，正常不触发）
    logging.getLogger(__name__).warning(
        '安装目录不可写，数据库回退到 LocalAppData：%s', prefer)
    local = os.environ.get('LOCALAPPDATA') or os.path.expanduser('~')
    folder = os.path.join(local, 'FileScanner')
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, 'file_scanner.db')


def app_data_root() -> str:
    """应用数据根目录：与 SQLite 数据库共用安装目录下的 `FileScannerData`，
    日志、导出等数据统一存放于此，使整个应用的数据都随安装目录走、可整体带走。
    即 `sqlite_db_path()` 所在的目录。
    """
    return os.path.dirname(sqlite_db_path())
