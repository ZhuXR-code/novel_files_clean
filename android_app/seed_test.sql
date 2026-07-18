-- 分页压力测试种子数据：清空后插入 1 个文库 + 30000 条文件
DELETE FROM scanned_file;
DELETE FROM scan_run;
INSERT INTO scan_run (id,name,folder_uri,folder_name,file_types,created_at,file_count)
VALUES (1,'测试3万条','test://uri','测试文件夹','txt',1000000000000,30000);
WITH RECURSIVE seq(n) AS (
  SELECT 1
  UNION ALL
  SELECT n+1 FROM seq WHERE n < 30000
)
INSERT INTO scanned_file
  (path,file_name,file_size,title,author,progress,source,content_hash,ext,marked,scan_run_id,created_at)
SELECT
  '/test/book_'||n||'.txt',
  '书名'||(n%500)||'_'||n||'.txt',
  (n*13%900000)+1000,
  '书名'||(n%500),
  '作者'||(n%97),
  CAST((n%300) AS TEXT),
  '测试来源',
  '',
  'txt',
  CASE WHEN n%10=0 THEN 1 ELSE 0 END,
  1,
  1000000000000+n
FROM seq;
SELECT '总条数=' || COUNT(*) FROM scanned_file;
SELECT '已标记=' || COUNT(*) FROM scanned_file WHERE marked=1;
SELECT '书名数=' || COUNT(DISTINCT title) FROM scanned_file;
