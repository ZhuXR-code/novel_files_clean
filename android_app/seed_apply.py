import sqlite3, os

base = r"d:\user\project\批量文件清理和文件内容识别\txt文件清理-单工程清理\android_app"
db = os.path.join(base, "seed_pull.db")
sql = os.path.join(base, "seed_test.sql")

con = sqlite3.connect(db)
con.execute("PRAGMA journal_mode=DELETE")
con.execute("PRAGMA foreign_keys=OFF")
with open(sql, encoding="utf-8") as f:
    con.executescript(f.read())
con.commit()

cur = con.cursor()
cur.execute("SELECT COUNT(*) FROM scanned_file")
print("scanned_file:", cur.fetchone()[0])
cur.execute("SELECT COUNT(*) FROM scan_run")
print("scan_run:", cur.fetchone()[0])
cur.execute("SELECT COUNT(*) FROM scanned_file WHERE marked=1")
print("marked:", cur.fetchone()[0])
con.close()
print("seeded ok")
