import pymysql

# 数据库连接
conn = pymysql.connect(
    host='localhost',
    user='your_user',
    password='your_password',
    database='file_scanner'
)
cursor = conn.cursor()

# 需要替换的模式列表
patterns = [
    '@txtnovel.com',
    '[草 莓]',
    '[草2莓]',
    '【香蕉】',
    '【苹果】',
    '[西瓜]',
    '{橙子}',
    '@gmail.com',
    '@163.com',
    '【火龙果】',
    '(芒果)',
    '【葡萄】'
]

# 先查看需要处理的数据
placeholders = ','.join(['%s'] * len(patterns))
like_conditions = ' OR '.join(['file_name LIKE %s'] * len(patterns))
like_params = [f'%{p}%' for p in patterns]

cursor.execute(f"""
    SELECT COUNT(*) FROM file_scanner.scan_results 
    WHERE {like_conditions}
""", like_params)
print(f"需要处理的记录数: {cursor.fetchone()[0]}")

# 执行更新（循环替换每个模式）
for pattern in patterns:
    cursor.execute("""
        UPDATE file_scanner.scan_results 
        SET file_name = REPLACE(file_name, %s, '')
        WHERE file_name LIKE %s
    """, (pattern, f'%{pattern}%'))
    print(f"替换 '{pattern}' 完成，影响 {cursor.rowcount} 行")

conn.commit()

# 验证结果
cursor.execute(f"""
    SELECT COUNT(*) FROM file_scanner.scan_results 
    WHERE {like_conditions}
""", like_params)
print(f"剩余包含模式的数量: {cursor.fetchone()[0]}")

cursor.close()
conn.close()