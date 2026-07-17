"""数据库后端配置（网页版 MySQL / 本地 EXE SQLite 共存）。

通过环境变量 DB_BACKEND 切换：
  - mysql  （默认）：沿用原有 MySQL 逻辑，完全不变。
  - sqlite ：本地 EXE 模式，使用内置 SQLite 文件数据库，无需安装 MySQL。

本地 EXE 的 launcher 会在导入本模块前设置 os.environ['DB_BACKEND'] = 'sqlite'。
"""
import os


DB_BACKEND = os.environ.get('DB_BACKEND', 'mysql').lower()
IS_SQLITE = DB_BACKEND == 'sqlite'


def sqlite_db_path() -> str:
    """返回 SQLite 数据库文件路径。

    优先级：
      1. 环境变量 SQLITE_DB_PATH（可由 launcher / 便携模式设置）
      2. 用户应用数据目录：%APPDATA%/FileScanner/file_scanner.db
    该路径对当前用户可写，安装到 Program Files 也能正常使用。
    """
    env_path = os.environ.get('SQLITE_DB_PATH')
    if env_path:
        return env_path
    app_dir = os.environ.get('APPDATA') or os.path.expanduser('~')
    folder = os.path.join(app_dir, 'FileScanner')
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, 'file_scanner.db')
