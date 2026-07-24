#!/usr/bin/env python3
"""检查 MySQL 中 dup_rule_configs 表结构"""
from sqlalchemy import create_engine, text

engine = create_engine('mysql+pymysql://root:msps@127.0.0.1:3308/file_scanner_noai')
with engine.connect() as conn:
    rows = conn.execute(text('DESCRIBE dup_rule_configs')).fetchall()
    print("dup_rule_configs 表结构:")
    for row in rows:
        print(f"  {row[0]:20} {row[1]:20} Null={row[2]:5} Default={str(row[4]):15} Extra={row[5]}")
