"""
验证 Android APP 真实的重复标记 SQL（ScannedFileDao.markDuplicatesByNameSql）。
逐字取自 android_app/.../data/database/dao/ScannedFileDao.kt:81-95。
按 lower(trim(title))||'|'||lower(trim(COALESCE(author,''))) 同组、count>1 视为重复，
保留每组 MIN(id)，其余标记 marked=1。用内存 SQLite 跑真实 SQL 验证语义。
"""
import sqlite3

SQL = """
    UPDATE scanned_file SET marked = 1
    WHERE scan_run_id = ?
      AND title != ''
      AND (lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))) IN (
          SELECT lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
          FROM scanned_file WHERE scan_run_id = ? AND title != ''
          GROUP BY lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
          HAVING COUNT(*) > 1
      )
      AND id NOT IN (
          SELECT MIN(id) FROM scanned_file WHERE scan_run_id = ? AND title != ''
          GROUP BY lower(trim(title)) || '|' || lower(trim(COALESCE(author, '')))
      )
"""

# (id, runId, title, author, 期望是否被标记)
ROWS = [
    (1, 10, '都市奇缘', '张三', False),
    (2, 10, '都市奇缘', '张三', True),       # 同组重复 -> 标记
    (3, 10, '深海',     '李四', False),
    (4, 10, '深海',     '李四', True),       # 同组重复 -> 标记
    (5, 10, '深海',     '王五', False),      # 作者不同 -> 不重复
    (6, 10, '都市奇缘', '张三 ', True),      # 末尾空格 trim 后并入「都市奇缘|张三」组 -> 应标记
    (7, 10, '天官赐福', '墨香铜臭', False),  # 唯一 -> 不标记
    (8, 10, '都市奇缘', '张三', True),       # 同组 -> 标记
    (9, 20, '都市奇缘', '张三', False),      # 不同 runId 不参与本次标记
    (10, 10, '',         '无书名', False),   # title 空 -> 不标记
]

def run():
    con = sqlite3.connect(':memory:')
    cur = con.cursor()
    cur.execute("""CREATE TABLE scanned_file (
        id INTEGER PRIMARY KEY, scan_run_id INTEGER, title TEXT, author TEXT, marked INTEGER DEFAULT 0)""")
    cur.executemany("INSERT INTO scanned_file (id, scan_run_id, title, author) VALUES (?,?,?,?)",
                    [(r[0], r[1], r[2], r[3]) for r in ROWS])
    cur.execute(SQL, (10, 10, 10))   # 仅对 runId=10 执行
    con.commit()
    cur.execute("SELECT id, marked FROM scanned_file ORDER BY id")
    marked = {i: bool(m) for i, m in cur.fetchall()}
    con.close()

    passed = 0
    failed = 0
    print("==== 重复标记真实 SQL 验证 ====")
    for rid, runid, title, author, exp in ROWS:
        got = marked.get(rid, False)
        ok = (got == exp)
        passed += ok
        failed += (not ok)
        print(f"  [{'PASS' if ok else 'FAIL'}] id={rid} run={runid} '{title}'/'{author}' expected={exp} got={got}")
    print(f"\n结果: {passed} pass / {failed} fail")
    return failed

if __name__ == '__main__':
    import sys
    sys.exit(1 if run() > 0 else 0)
