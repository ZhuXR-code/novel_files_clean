"""数据库迁移脚本：从旧库拷贝表与基础数据到新的独立数据库。

特点：
- 新建一个独立的新库（默认 file_scanner_noai），不再使用旧的数据库表。
- 用当前 models.py 的表结构在新库建表（已剔除全部 AI / Token 相关表与字段）。
- 仅「读取」旧库，把除 ai_configs / token_usage 之外的表数据拷贝过来；
  对 file_metadata 等表只拷贝新旧结构的交集字段（自动排除 AI 专属列）。
- 旧库保持只读、不做任何修改。

用法：
    python migrate_to_new_db.py
可选环境变量：
    DB_OLD_NAME  旧库名（默认 file_scanner）
    DB_NEW_NAME  新库名（默认 file_scanner_noai）
    DB_USER / DB_PASS / DB_HOST / DB_PORT  连接参数
"""
import os

from dotenv import load_dotenv

from sqlalchemy import create_engine, text, inspect
from sqlalchemy.exc import SQLAlchemyError

from backend.models import Base

load_dotenv()

OLD_DB = os.environ.get('DB_OLD_NAME', 'file_scanner')
NEW_DB = os.environ.get('DB_NEW_NAME', 'file_scanner_noai')
DB_USER = os.environ.get('DB_USER', 'root')
DB_PASS = os.environ.get('DB_PASS')
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_PORT = os.environ.get('DB_PORT', '3308')

# 这些表属于 AI / Token 统计，整表不迁移
SKIP_TABLES = {'ai_configs', 'token_usage'}

# 依赖顺序（父表优先）；其余自动跳过或按序处理
TABLE_ORDER = [
    'scan_configs',
    'column_configs',
    'keyword_replace_rules',
    'scan_results',
    'file_groups',
    'file_metadata',
    'parse_logs',
    'help_docs',
]


def build_url(dbname):
    if DB_PASS:
        return f'mysql+pymysql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{dbname}?charset=utf8mb4'
    return f'mysql+pymysql://{DB_USER}@{DB_HOST}:{DB_PORT}/{dbname}?charset=utf8mb4'


def main():
    admin_engine = create_engine(build_url(''), pool_pre_ping=True)
    with admin_engine.connect() as conn:
        conn.execute(text(
            f"CREATE DATABASE IF NOT EXISTS `{NEW_DB}` "
            f"CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
        ))
        conn.commit()
    print(f'[1/4] 新库 `{NEW_DB}` 已就绪（若不存在则已创建）')

    old_engine = create_engine(build_url(OLD_DB), pool_pre_ping=True)
    new_engine = create_engine(build_url(NEW_DB), pool_pre_ping=True)

    # 用当前模型在新库建表（不含 AI / Token 相关结构）
    Base.metadata.create_all(bind=new_engine)
    print(f'[2/4] 已按当前模型在新库 `{NEW_DB}` 建表')

    try:
        old_insp = inspect(old_engine)
        new_insp = inspect(new_engine)
    except SQLAlchemyError as e:
        print(f'无法连接旧库 `{OLD_DB}`，跳过数据拷贝：{e}')
        print('[完成] 新库已创建并建表，无旧数据可拷贝。')
        return

    old_tables = set(old_insp.get_table_names())
    new_tables = set(new_insp.get_table_names())

    if not old_tables:
        # 旧库可能根本不存在或为空
        print(f'[提示] 旧库 `{OLD_DB}` 中未检测到任何表，可能尚未创建过。')
        print('[完成] 新库已就绪，应用启动后将自动初始化默认数据。')
        return

    print('[3/4] 开始拷贝数据（旧库保持只读）...')
    # 临时关闭外键检查，避免父子表插入顺序问题
    with new_engine.begin() as w:
        w.execute(text('SET FOREIGN_KEY_CHECKS=0'))
    try:
        for table in TABLE_ORDER:
            if table in SKIP_TABLES:
                print(f'  - 跳过 `{table}`（AI / Token 相关，不迁移）')
                continue
            if table not in new_tables:
                print(f'  - 跳过 `{table}`（新库不存在该表）')
                continue
            if table not in old_tables:
                print(f'  - 跳过 `{table}`（旧库不存在该表）')
                continue

            old_cols = {c['name'] for c in old_insp.get_columns(table)}
            new_cols = {c['name'] for c in new_insp.get_columns(table)}
            common = [c for c in new_cols if c in old_cols]
            if not common:
                print(f'  - 跳过 `{table}`（新旧字段无交集）')
                continue

            with old_engine.connect() as ro:
                rows = ro.execute(
                    text(f"SELECT {', '.join('`' + c + '`' for c in common)} FROM `{table}`")
                ).fetchall()
            if not rows:
                print(f'  - `{table}`: 旧库无数据，跳过')
                continue

            col_list = ', '.join('`' + c + '`' for c in common)
            placeholders = ', '.join(':' + c for c in common)
            stmt = text(f"INSERT IGNORE INTO `{table}` ({col_list}) VALUES ({placeholders})")
            batch = [dict(zip(common, r)) for r in rows]
            with new_engine.begin() as w:
                w.execute(stmt, batch)
            print(f'  - `{table}`: 已迁移 {len(rows)} 行')
    finally:
        with new_engine.begin() as w:
            w.execute(text('SET FOREIGN_KEY_CHECKS=1'))

    print('[4/4] 迁移完成。旧库未被修改，新库已包含拷贝过来的基础数据。')


if __name__ == '__main__':
    main()
