import pymysql

conn = pymysql.connect(host='localhost', user='root', password='msps',
                      port=3308, database='file_scanner_noai', charset='utf8mb4')
cur = conn.cursor()

print("=== scan_configs columns ===")
cur.execute("SHOW COLUMNS FROM scan_configs")
for r in cur.fetchall():
    print(" ", r)

print("=== scan_configs rows ===")
cur.execute("SELECT * FROM scan_configs")
cols = [d[0] for d in cur.description]
for row in cur.fetchall():
    d = dict(zip(cols, row))
    print(" ", {k: (str(v)[:60] if v is not None else None) for k, v in d.items()})

print("=== scan_results columns ===")
cur.execute("SHOW COLUMNS FROM scan_results")
for r in cur.fetchall():
    print(" ", r[0], r[1])

print("=== file_groups columns ===")
cur.execute("SHOW COLUMNS FROM file_groups")
for r in cur.fetchall():
    print(" ", r[0], r[1])

print("=== scan_results per config ===")
cur.execute("SELECT scan_config_id, COUNT(*) FROM scan_results GROUP BY scan_config_id")
for r in cur.fetchall():
    print(" ", r)
conn.close()
