"""工程解析模块 - 仅使用正则/规则提取 TXT 文件名与简介，不调用任何 LLM/AI 接口。

提供：
  - 文件名解析（正则提取 书名 / 作者 / 来源 / 进度）
  - 摘要提取（读取正文首章前简介）
两个解析函数均以「多进程计算 + 主进程批量 upsert」的方式写入数据库。
"""
import os
import re
import sys
import time
import threading
import traceback
from datetime import datetime
from typing import List, Optional, Callable

from sqlalchemy import func
from sqlalchemy.orm import Session

from backend.logger import logger
from backend.models import ScanResult, FileMetadata
from backend.keyword_replace import load_rules, apply_rules
from backend.db_config import IS_SQLITE

# 数据库写锁：文件名解析的 save_one 仍在主进程调用，保留以防并发安全。
# 注：CPU 密集解析已下沉到 ProcessPoolExecutor 子进程，子进程不共享此锁与 DB 会话。
_db_lock = threading.Lock()


def _upsert_metadata_sqlalchemy(session_factory, rows, columns):
    """SQLite / 通用回退：使用 SQLAlchemy Core 的 INSERT ... ON CONFLICT 做 upsert。

    - rows: list[dict]，每项含 'scan_result_id' 以及 columns 中的字段。
    - columns: 冲突时要更新的字段名列表（不含 scan_result_id）。
    以 scan_result_id 唯一约束作为冲突判定键；MySQL 模式不会走到这里
    （MySQL 使用 pymysql 原生 ON DUPLICATE KEY UPDATE）。
    """
    if not rows:
        return
    from sqlalchemy.dialects.sqlite import insert as sqlite_insert
    session = session_factory()
    try:
        stmt = sqlite_insert(FileMetadata)
        values = [{'scan_result_id': r['scan_result_id'],
                   **{c: r.get(c) for c in columns}} for r in rows]
        stmt = stmt.values(values)
        set_cols = {c: getattr(FileMetadata, c) for c in columns}
        stmt = stmt.on_conflict_do_update(index_elements=['scan_result_id'], set_=set_cols)
        session.execute(stmt)
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()

# 默认读取行数（用于摘要提取时的头部读取）
HEAD_LINES = 40
TAIL_LINES = 25

# 首章标题正则模式（用于定位简介/正文分界，按优先级降序排列）
CHAPTER_TITLE_PATTERNS = [
    # 格式: 第X章、第X节、第X卷
    r'第[　\s]*[一二三四五六七八九十百千\d]+[　\s]*章',
    r'第[　\s]*[一二三四五六七八九十百千\d]+[　\s]*节',
    r'第[　\s]*[一二三四五六七八九十百千\d]+[　\s]*卷',
    r'第[　\s]*[一二三四五六七八九十百千\d]+[　\s]*部分',
    r'第[　\s]*[一二三四五六七八九十百千\d]+[　\s]*篇',
    # 英文章节
    r'chapter\s*[\d]+',
    r'ch[\.\s]*[\d]+',
    r'vol[\.\s]*[\d]+',
    r'volume[\s]*[\d]+',
    # 卷标（卷一、卷1等）
    r'卷[一二三四五六七八九十百千\d]',
    # 特殊标题
    r'^(?:引子|楔子|序章|序言|前言|序)',  # 行首匹配
    r'^(?:正文)',  # 行首匹配
]
# 编译后的首章正则
_compiled_chapter_re = re.compile(
    '|'.join(f'(?:{p})' for p in CHAPTER_TITLE_PATTERNS),
    re.IGNORECASE | re.MULTILINE,
)

# 简介/摘要标记模式
SUMMARY_MARKER_PATTERNS = [
    r'(?:本书|内容|作品|故事|小说|文章|文案)?\s*简介[：:\s]',
    r'【.*?简介.*?】',
    r'\[.*?简介.*?\]',
    r'(?:文案|故事梗概|内容摘要)[：:\s]',
]
_compiled_summary_re = re.compile(
    '|'.join(f'(?:{p})' for p in SUMMARY_MARKER_PATTERNS),
    re.IGNORECASE | re.MULTILINE,
)

# ===================== 工程摘要提取 =====================


def _read_full_file_content(file_path: str) -> str:
    """读取文件的完整内容"""
    try:
        encoding = _detect_encoding(file_path)
        with open(file_path, 'r', encoding=encoding, errors='replace') as f:
            return f.read()
    except Exception as e:
        logger.warning(f'读取完整文件内容失败 [{file_path}]: {e}')
        return ''


def _read_head_content(file_path: str, max_bytes: int = 200 * 1024, max_lines: int = 5000) -> str:
    """安全读取文件头部（限制大小，避免 OOM）。"""
    try:
        encoding = _detect_encoding(file_path)
        with open(file_path, 'r', encoding=encoding, errors='replace') as f:
            lines = []
            total_bytes = 0
            for line in f:
                lines.append(line)
                total_bytes += len(line.encode(encoding, errors='replace'))
                if total_bytes >= max_bytes or len(lines) >= max_lines:
                    break
            return ''.join(lines)
    except Exception as e:
        logger.warning(f'读取文件头部失败 [{file_path}]: {e}')
        return ''


def _extract_pre_chapter_content(full_content: str) -> str:
    """提取首章之前的内容（简介/楔子部分）"""
    if not full_content:
        return ''

    matches = list(_compiled_chapter_re.finditer(full_content))
    if matches:
        first_chapter_pos = matches[0].start()
        pre_chapter = full_content[:first_chapter_pos].strip()
        if pre_chapter:
            return pre_chapter

    lines = full_content.split('\n')
    first_100 = '\n'.join(lines[:100]).strip()
    return first_100


def _extract_summary_from_intro(intro_text: str) -> str:
    """从首章前的内容中提取简介/摘要文本"""
    if not intro_text:
        return ''

    match = _compiled_summary_re.search(intro_text)
    if match:
        summary_start = match.end()
        summary_text = intro_text[summary_start:].strip()
    else:
        summary_text = intro_text

    lines = summary_text.split('\n')
    cleaned_lines = []
    for line in lines:
        stripped = line.strip()
        if re.match(r'^[\s\-—*_=～~#@\.]+$', stripped):
            continue
        if not stripped:
            continue
        if re.match(r'^(书名|作者|标签|字数|状态|小说|作品).*[：:]', stripped):
            continue
        cleaned_lines.append(stripped)

    if not cleaned_lines:
        return ''

    result = '\n'.join(cleaned_lines).strip()
    if len(result) > 5000:
        result = result[:5000]
    return result


def _ensure_db_session(db: Session, db_session_factory=None) -> Session:
    """检查 db session 是否可用，如果不可用则尝试重建"""
    if db_session_factory is None:
        return db
    try:
        db.connection()
        return db
    except Exception:
        logger.warning('DB连接已断开，重建新session')
        try:
            db.close()
        except Exception:
            pass
        return db_session_factory()


def _dump_thread_stacks(context: str = ''):
    """遍历所有线程并转储其当前执行栈到日志（用于诊断死锁/卡住）"""
    try:
        frames = sys._current_frames()
        lines = [f'=== 线程栈转储 ({context}) ===']
        for tid, frame in frames.items():
            stack = ''.join(traceback.format_stack(frame))
            lines.append(f'--- 线程ID={tid} ---\n{stack}')
        lines.append('=== 转储结束 ===')
        msg = '\n'.join(lines)
        logger.warning(msg)
    except Exception as e:
        logger.warning(f'线程栈转储失败: {e}')


def _read_file_content(file_path: str, head_lines: int = HEAD_LINES, tail_lines: int = TAIL_LINES) -> tuple:
    """读取文件的前 head_lines 行和后 tail_lines 行（流式读取，避免大文件全量加载）"""
    head_content = ''
    tail_content = ''

    try:
        encoding = _detect_encoding(file_path)
        head_lines_list = []
        with open(file_path, 'r', encoding=encoding, errors='replace') as f:
            for i, line in enumerate(f):
                if i >= head_lines:
                    break
                head_lines_list.append(line)
        head_content = ''.join(head_lines_list)

        if tail_lines > 0:
            tail_content = _read_tail_lines_fast(file_path, encoding, tail_lines)

    except Exception as e:
        logger.warning(f'读取文件内容失败 [{file_path}]: {e}')

    return head_content, tail_content


def _read_tail_lines_fast(file_path: str, encoding: str, num_lines: int) -> str:
    """快速读取文件末尾 N 行（使用 seek 从文件末尾反向读取）"""
    try:
        with open(file_path, 'rb') as f:
            f.seek(0, os.SEEK_END)
            file_size = f.tell()

            if file_size == 0:
                return ''

            read_size = min(num_lines * 400 + 4096, file_size)
            f.seek(-read_size, os.SEEK_END)
            chunk = f.read(read_size)

            try:
                text = chunk.decode(encoding)
            except (UnicodeDecodeError, LookupError):
                text = chunk.decode('utf-8', errors='replace')

            lines = text.splitlines()
            if not lines:
                return ''

            tail = lines[-num_lines:] if len(lines) >= num_lines else lines[1:] if len(lines) > 1 else lines
            return '\n'.join(tail) + ('\n' if text.endswith('\n') else '')
    except Exception as e:
        logger.debug(f'快速读取尾行失败（回退常规方式）: {e}')
        try:
            from collections import deque
            with open(file_path, 'r', encoding=encoding, errors='replace') as f:
                tail_deque = deque(maxlen=num_lines)
                for line in f:
                    tail_deque.append(line)
                return ''.join(tail_deque)
        except Exception as e2:
            logger.warning(f'读取尾行失败 [{file_path}]: {e2}')
            return ''


def _pymysql_execute_with_retry(conn, sql, values, retries: int = 3):
    """执行 pymysql 批量写入语句并带重试，规避偶发锁等待 / 超时导致的整批失败。"""
    last_err = None
    for attempt in range(retries):
        try:
            with conn.cursor() as cur:
                affected = cur.execute(sql, values)
                conn.commit()
            return affected
        except Exception as e:
            last_err = e
            try:
                conn.rollback()
            except Exception:
                pass
            if attempt < retries - 1:
                logger.warning(f'[数据库] 批量写入第{attempt + 1}次失败，{1 + attempt}s 后重试: {e}')
                time.sleep(1 + attempt)
    logger.error(f'[数据库] 批量写入重试{retries}次仍失败: {last_err}', exc_info=True)
    raise last_err


def _detect_encoding(file_path: str) -> str:
    """检测文件编码"""
    import chardet
    try:
        with open(file_path, 'rb') as f:
            raw = f.read(min(8192, os.path.getsize(file_path) if os.path.getsize(file_path) > 0 else 8192))
            result = chardet.detect(raw)
            encoding = result.get('encoding', 'utf-8')
            if encoding and encoding.lower() in ('gb2312', 'gbk'):
                encoding = 'gb18030'
            return encoding or 'utf-8'
    except Exception:
        return 'utf-8'


# 常见小说来源站点（用于从文件名标签提取"来源"列）
SOURCE_SITES = [
    '废文', '海棠', '晋江', '长佩', '刺猬猫', '豆腐', '老福特', '息壤',
    '粉笔', '鲜网', '绿茶', '寒武纪', '不可能的世界', '豆瓣阅读', '掌阅',
    '番茄', '起点', '飞卢', '纵横', '17K', '黑岩', '云起', '红袖', '潇湘书院',
    '阅文', 'LOFTER', 'lofter', 'Po18', 'po18', 'FW', 'HT',
]


def _extract_source_progress(file_name: str):
    """从文件名方括号标签中提取 来源站点 与 更新进度。"""
    name = os.path.splitext(file_name)[0]
    source = ''
    progress = ''

    brackets = re.findall(r'\[([^\]]*)\]', name)
    brackets += re.findall(r'【([^】]*)】', name)

    if not brackets:
        tail = re.search(r'-(\d+)\s*$', name)
        if tail:
            progress = tail.group(1)
        return source, progress

    for content in brackets:
        if not source:
            for site in SOURCE_SITES:
                if site and site in content:
                    source = site
                    break
        if not progress:
            gm = re.search(r'更\s*(\d+)', content)
            if gm:
                progress = gm.group(1)
        if not progress:
            wm = re.search(r'完结[^\]\s]*', content)
            if wm:
                progress = wm.group(0)
        if not progress:
            tail = re.search(r'-(\d+)\s*$', name)
            if tail:
                progress = tail.group(1)
        if not progress:
            om = re.search(r'(?:连载|断更|暂停|烂尾|坑|锁文|锁)', content)
            if om:
                progress = om.group(0)

    if not progress:
        tail = re.search(r'-(\d+)\s*$', name)
        if tail:
            progress = tail.group(1)

    return source, progress


def _parse_filename_by_regex(file_name: str) -> Optional[dict]:
    """使用正则表达式解析常见文件名格式，返回 {title, author} 或 None"""
    name = os.path.splitext(file_name)[0]

    m = re.search(r'《([^》]+)》.*?作者[：:]\s*(.+)$', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author:
            return {'title': title, 'author': author}
    m = re.search(r'《([^》]+)》.*?[bB][yY]\s*(.+)$', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author:
            return {'title': title, 'author': author}

    m = re.search(r'《(.+?)》\s*作者[：:]\s*(.+)', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author:
            return {'title': title, 'author': author}

    m = re.search(r'【[^】]+】\s*《(.+?)》\s*作者[：:]\s*(.+)', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author:
            return {'title': title, 'author': author}

    m = re.search(r'《(.+?)》\s*[bB][yY]\s*(.+)', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author:
            return {'title': title, 'author': author}

    m = re.search(r'^(.+?)\s+[bB][yY]\s+(.+)$', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author:
            return {'title': title, 'author': author}

    m = re.search(r'^(.+?)[_\-—]\s*作者[：:]?\s*(.+)$', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author:
            return {'title': title, 'author': author}

    m = re.search(r'^[【\[(][^】\])\n]+[】\])]\s*(.+?)\s*[bB][yY]\s*(.+)$', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author:
            return {'title': title, 'author': author}

    m = re.search(r'^[【\[(][^】\])\n]+[】\])]\s*(.+?)\s*作者[：:]\s*(.+)$', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author:
            return {'title': title, 'author': author}

    m = re.search(r'^[【\[(][^】\])\n]+[】\])]\s*(.+)$', name)
    if m:
        title = m.group(1).strip()
        if title and len(title) >= 2 and not re.match(r'^[\d\s\.\-_#@!*&]+$', title) and '作者' not in title and '《' not in title:
            return {'title': title, 'author': ''}

    m = re.search(r'^(.+?)\s*[bB][yY]\s*(.+)$', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author and not re.match(r'^[【\[(]', title):
            return {'title': title, 'author': author}

    m = re.search(r'\[[^\]]+\]\s*(.+?)\s*作者[：:]\s*(.+)', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author:
            return {'title': title, 'author': author}

    m = re.search(r'^(.+?)\s*作者[：:]\s*(.+)', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        author = re.sub(r'\s+(?:完结|番外|全本|完本|连载|出版|实体书|定制书|定制|校对).*$', '', author, flags=re.IGNORECASE).strip()
        if title and author:
            return {'title': title, 'author': author}

    m = re.search(r'^(?:\[.*?\])?\s*《(.+?)》\s*作者\s*(.+?)$', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        if title and author and len(title) >= 2 and len(author) >= 2:
            return {'title': title, 'author': author}

    m = re.search(r'《(.+?)》', name)
    if m:
        title = m.group(1).strip()
        return {'title': title, 'author': ''}

    m = re.search(r'^(.+?)\s*[（(]\s*[\w\-]+(?:\.[\w\-]+)+\s*[）)]\s*$', name)
    if m:
        title = m.group(1).strip()
        if title:
            return {'title': title, 'author': ''}

    m = re.search(r'^(?:BG|BL|GL|GB|DM|言情|耽美|百合|同人|原创|武侠|玄幻|古言|现言|仙侠|科幻|悬疑|惊悚|轻小说|海棠|popo|废文|po18|SF)\s*(.+?)[_\-—](.+?)$', name, re.IGNORECASE)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        author = re.sub(r'\s*[（(]\d+[）)]\s*$', '', author).strip()
        if title and author and len(title) >= 2:
            return {'title': title, 'author': author}

    m = re.search(r'^(.+?)[_\-—](.+?)$', name)
    if m:
        title = m.group(1).strip()
        author = m.group(2).strip()
        author = re.sub(r'[\s（(]*[）)]\s*$', '', author)
        author = re.sub(r'\s*[（(]\d+[）)]\s*$', '', author)
        author = re.sub(r'[\s（(]*$', '', author)
        has_cn_t = bool(re.search(r'[\u4e00-\u9fff]', title))
        has_cn_a = bool(re.search(r'[\u4e00-\u9fff]', author))
        if has_cn_t and len(title) >= 2 and len(author) >= 2 and (has_cn_a or re.search(r'[a-zA-Z]', author)):
            return {'title': title, 'author': author}

    m = re.search(r'^(.+?)\s*\[([^\]]+)\]\s*$', name)
    if m:
        title = m.group(1).strip()
        if title and len(title) >= 2:
            return {'title': title, 'author': ''}

    if not re.search(r'[a-zA-Z]{4,}', name):
        cn_chars = re.findall(r'[\u4e00-\u9fff]', name)
        if len(cn_chars) >= 2 and len(name) <= 60:
            if not re.search(r'(?:试阅|请勿|版权|删[除文]|二传|商业|仅供|公告|下载|通知|说明|使用|帮助|README|changelog|免责|侵权|联系|QQ|微信|公众号|微博)', name, re.IGNORECASE):
                title = name.strip()
                return {'title': title, 'author': ''}

    return None


def _parse_file_content_for_metadata(file_path: str, file_name: str) -> Optional[dict]:
    """当文件名无法解析时，读取文件前 N 行内容尝试提取作者和书名"""
    ext = os.path.splitext(file_name)[1].lower()
    if ext not in ('.txt', '.text', '.md', ''):
        return None

    try:
        import chardet
        with open(file_path, 'rb') as f:
            raw = f.read(8192)
        enc = chardet.detect(raw)['encoding'] or 'utf-8'
        enc = enc.replace('gb2312', 'gbk').replace('GB2312', 'GBK')

        lines = []
        try:
            with open(file_path, 'r', encoding=enc, errors='replace') as f:
                for _ in range(30):
                    line = f.readline()
                    if not line:
                        break
                    lines.append(line)
        except (UnicodeDecodeError, LookupError):
            with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                for _ in range(30):
                    line = f.readline()
                    if not line:
                        break
                    lines.append(line)
    except Exception:
        return None

    content = '\n'.join(lines)
    title = ''
    author = ''

    author_patterns = [
        r'作者[：:]\s*(.+)',
        r'著者[：:]\s*(.+)',
        r'作\s*者[：:]\s*(.+)',
        r'By\s*(.+)$',
        r'by\s*(.+)$',
    ]
    for pat in author_patterns:
        m = re.search(pat, content)
        if m:
            candidate = m.group(1).strip().rstrip('，,。.')
            if candidate and len(candidate) < 30:
                author = candidate
                break

    title_patterns = [
        r'书名[：:]\s*(.+)',
        r'小说名[：:]\s*(.+)',
        r'作品名[：:]\s*(.+)',
        r'作品[：:]\s*(.+)',
        r'名称[：:]\s*(.+)',
        r'题名[：:]\s*(.+)',
    ]
    for pat in title_patterns:
        m = re.search(pat, content)
        if m:
            candidate = m.group(1).strip().rstrip('，,。.')
            if candidate and len(candidate) < 100:
                title = candidate
                break

    m = re.search(r'《(.+?)》', content)
    if m:
        title = m.group(1).strip()

    if not title:
        for line in lines:
            line = line.strip()
            if not line:
                continue
            if re.match(r'^(作者|著者|作\s*者|书名|小说名|作品名|标签|文案|简介|文案|第\d+章|楔子|引子)', line):
                continue
            if len(line) >= 2 and len(line) <= 80:
                title = line
                break

    if title or author:
        logger.info(f'文件内容解析成功[{file_name}]: title="{title}", author="{author}"')
        return {'title': title, 'author': author}

    return None


# ===================== 线程级 Worker =====================


def _name_worker(args: tuple) -> dict:
    """进程 worker：解析文件名提取 小说名/作者/进度/来源。"""
    rec_id, file_name, existing_data = args

    src_progress = _extract_source_progress(file_name)
    regex_res = _parse_filename_by_regex(file_name)
    parsed_title = regex_res['title'] if regex_res else ''
    parsed_author = regex_res['author'] if regex_res else ''
    if parsed_author:
        parsed_author = re.sub(r'\s*[\[（][^\]）]*?(?:\d+|[更完结npv1V]+)[^\]）]*?[\]）]\s*$', '', parsed_author).strip()
        parsed_author = re.sub(r'\s*-\d+\s*$', '', parsed_author).strip()
    parsed_progress = src_progress[1]
    parsed_source = src_progress[0]

    if existing_data:
        cur_title = existing_data.get('novel_name', '') or ''
        cur_author = existing_data.get('author', '') or ''
        cur_progress = existing_data.get('progress', '') or ''
        cur_source = existing_data.get('source', '') or ''
    else:
        cur_title = cur_author = cur_progress = cur_source = ''

    new_title = cur_title or parsed_title
    new_author = cur_author or parsed_author
    new_progress = cur_progress or parsed_progress
    new_source = cur_source or parsed_source

    filled = (0 if cur_title else 1 if new_title else 0) + \
             (0 if cur_author else 1 if new_author else 0) + \
             (0 if cur_progress else 1 if new_progress else 0) + \
             (0 if cur_source else 1 if new_source else 0)

    if filled == 0:
        if not (cur_title or cur_author or cur_progress or cur_source):
            return {'rec_id': rec_id, 'failed': True, 'file_name': file_name}
        else:
            return {'rec_id': rec_id, 'skipped': True}

    return {
        'rec_id': rec_id,
        'novel_name': new_title,
        'author': new_author,
        'progress': new_progress,
        'source': new_source,
        'success': True,
    }


def _summary_worker(args: tuple) -> dict:
    """进程 worker：读取文件全文，提取摘要。"""
    rec_id, file_path, file_name = args

    full_content = _read_head_content(file_path)
    if not full_content:
        return {'rec_id': rec_id, 'failed': True, 'file_name': file_name, 'reason': '文件为空或无法读取'}

    pre_chapter = _extract_pre_chapter_content(full_content)
    if not pre_chapter:
        return {'rec_id': rec_id, 'failed': True, 'file_name': file_name, 'reason': '首章前内容为空'}

    summary = _extract_summary_from_intro(pre_chapter)
    return {
        'rec_id': rec_id,
        'summary': summary or '',
        'success': True,
    }


def parse_file_names_regex_only(
    db: Session,
    file_ids: Optional[List[int]] = None,
    config_id: Optional[int] = None,
    progress_callback=None,
    cancel_check=None,
    log_callback=None,
    db_session_factory=None,
    pymysql_factory=None,
    concurrency: int = 8,
    force: bool = False,
) -> dict:
    """仅使用工程方法（正则）解析文件名，不调用 AI。

    单线程顺序解析文件名（纯 CPU 计算），
    主进程收集结果后拼接批量 upsert 语句一次性写入数据库。
    「解析全部」按 config_id 分页流式处理，避免一次性加载全部记录与超大 IN 子句。

    Args:
        file_ids: 指定文件ID列表（已选模式）；为 None 时按 config_id 处理全部。
        config_id: 扫描配置ID（解析全部时使用）。
        concurrency: 用于文件名解析的进程数。
        force: 是否强制重新解析。True=不管是否已有数据都覆盖重写；False=跳过已有元数据记录的文件。
    """
    max_workers = max(1, min(int(concurrency) if concurrency else 8, (os.cpu_count() or 4) * 2))
    PAGE_SIZE = 5000

    if file_ids:
        total = len(file_ids)
    elif config_id is not None:
        total = db.query(func.count(ScanResult.id)).filter(
            ScanResult.scan_config_id == config_id
        ).scalar() or 0
    else:
        total = 0

    logger.info(f'[工程文件名解析][入口] 入参: file_ids={"{}个".format(len(file_ids)) if file_ids else "None"}, '
                f'config_id={config_id}, 进程数={max_workers}, '
                f'pymysql_factory={"已提供" if pymysql_factory else "未提供(回退SQLAlchemy)"}')
    parse_rules = load_rules(db, 'parse')
    if log_callback:
        log_callback('正在准备解析任务...')

    if total == 0:
        logger.info('[工程文件名解析][入口] 没有需要解析的文件，直接返回')
        if progress_callback:
            progress_callback(0, 0, 0, 0)
        return {'total': 0, 'success': 0, 'failed': 0}

    if progress_callback:
        progress_callback(0, total, 0, 0)

    BULK_BATCH = 500
    success_count = 0
    skipped_count = 0
    failed_count = 0
    processed = 0
    insert_batch = []

    REPORT_INTERVAL = 1.0
    MAX_FAIL_SAMPLE = 30
    _last_report_ts = [0.0]

    def _report(force=False):
        now = time.time()
        if not force and (now - _last_report_ts[0]) < REPORT_INTERVAL:
            return
        _last_report_ts[0] = now
        if progress_callback:
            progress_callback(processed, total, success_count, failed_count)
        msg = f'进度 {processed}/{total}（成功 {success_count}，跳过 {skipped_count}，失败 {failed_count}）'
        logger.info(msg)
        if log_callback:
            log_callback(msg)

    def _iter_record_pages():
        if file_ids:
            for start in range(0, len(file_ids), PAGE_SIZE):
                chunk = file_ids[start:start + PAGE_SIZE]
                recs = db.query(ScanResult).filter(ScanResult.id.in_(chunk)).all()
                if recs:
                    yield recs
        elif config_id is not None:
            offset = 0
            while True:
                recs = db.query(ScanResult).filter(
                    ScanResult.scan_config_id == config_id
                ).offset(offset).limit(PAGE_SIZE).all()
                if not recs:
                    break
                yield recs
                offset += PAGE_SIZE

    _report(force=True)

    for page_recs in _iter_record_pages():
        if cancel_check and cancel_check():
            logger.warning(f'[工程文件名解析] 任务在 {processed}/{total} 处被取消')
            if log_callback:
                log_callback(f'任务在 {processed}/{total} 处被取消')
            break

        record_ids = [r.id for r in page_recs]
        existing_metas = db.query(FileMetadata).filter(
            FileMetadata.scan_result_id.in_(record_ids)
        ).all()
        meta_by_id = {m.scan_result_id: m for m in existing_metas}

        page_skipped = 0
        need_parse = []
        for rec in page_recs:
            m = meta_by_id.get(rec.id)
            if not force and m:
                page_skipped += 1
                logger.info(f'  ~ {rec.file_name[:60]} → 跳过（已有元数据）')
                continue
            need_parse.append((rec.id, rec.file_name, None))

        skipped_count += page_skipped
        processed += len(page_recs)
        _report(force=True)

        if not need_parse:
            continue

        cancelled = False
        for (rid, fname, _) in need_parse:
            if cancel_check and cancel_check():
                cancelled = True
                break
            result = _name_worker((rid, fname, None))
            if result.get('success'):
                insert_batch.append({
                    'scan_result_id': result['rec_id'],
                    'novel_name': apply_rules(result['novel_name'] or '', parse_rules),
                    'author': apply_rules(result['author'] or '', parse_rules),
                    'progress': apply_rules(result['progress'] or '', parse_rules),
                    'source': apply_rules(result['source'] or '', parse_rules),
                })
                success_count += 1
                n = result.get('novel_name', '') or ''
                a = result.get('author', '') or ''
                logger.info(f'  [+] {fname[:60]} → 书名={n[:30]}, 作者={a[:20]}')
            elif result.get('skipped'):
                skipped_count += 1
            elif result.get('failed'):
                failed_count += 1
                logger.info(f'  [-] {fname[:60]} → 解析失败')
                if failed_count <= MAX_FAIL_SAMPLE:
                    msg = f'正则未能解析: {result.get("file_name", "?")}'
                    logger.warning(msg)
                    if log_callback:
                        log_callback(msg)
        if cancelled:
            logger.warning('[工程文件名解析] 已取消，停止后续解析')
            break
        _report(force=True)

    _report(force=True)

    if insert_batch:
        total_rows = len(insert_batch)
        n_batches = (total_rows + BULK_BATCH - 1) // BULK_BATCH
        logger.info(f'[工程文件名解析] 全部 worker 结束，开始批量写入: 待写入={total_rows}条, '
                    f'共{n_batches}批, 每批={BULK_BATCH}, 使用={"pymysql" if pymysql_factory else "SQLAlchemy回退"}')
        if log_callback:
            log_callback(f'开始批量写入数据库: 共{total_rows}条, 分{n_batches}批, 每批{BULK_BATCH}条')
        written = 0
        failed_batches = 0
        write_start = time.time()
        if pymysql_factory:
            conn = pymysql_factory()
            try:
                with conn.cursor() as cur:
                    for bi in range(n_batches):
                        i = bi * BULK_BATCH
                        chunk = insert_batch[i:i + BULK_BATCH]
                        batch_no = bi + 1
                        placeholders = []
                        values = []
                        for row in chunk:
                            placeholders.append('(%s, %s, %s, %s, %s)')
                            values.extend([
                                row['scan_result_id'], row['novel_name'],
                                row['author'], row['progress'], row['source'],
                            ])
                        sql = (
                            "INSERT INTO file_metadata "
                            "(scan_result_id, novel_name, author, progress, source) VALUES "
                            + ", ".join(placeholders) +
                            " ON DUPLICATE KEY UPDATE "
                            "novel_name = VALUES(novel_name), "
                            "author = VALUES(author), "
                            "progress = VALUES(progress), "
                            "source = VALUES(source)"
                        )
                        b_t0 = time.time()
                        try:
                            affected = _pymysql_execute_with_retry(conn, sql, values)
                        except Exception as be:
                            try:
                                conn.rollback()
                            except Exception:
                                pass
                            failed_batches += 1
                            err_msg = f'批量写入第{batch_no}/{n_batches}批失败（已回滚本批）: {be}'
                            logger.error(f'[工程文件名解析] {err_msg}', exc_info=True)
                            if log_callback:
                                log_callback(err_msg)
                            continue
                        written += len(chunk)
                        b_elapsed = time.time() - b_t0
                        if b_elapsed > 5:
                            logger.warning(f'[工程文件名解析] 批量写入第{batch_no}/{n_batches}批耗时过长: '
                                           f'本批{len(chunk)}条, 影响行数={affected}, 耗时={b_elapsed:.2f}s')

                        if bi % 10 == 0 or bi == n_batches - 1:
                            _report(force=True)

                        logger.info(f'[工程文件名解析] 批量写入第{batch_no}/{n_batches}批成功: '
                                    f'本批{len(chunk)}条, 影响行数={affected}, 累计写入={written}, 耗时={b_elapsed:.2f}s')
                logger.info(f'[工程文件名解析] 批量写入全部完成: 成功写入={written}/{total_rows}条, '
                            f'失败批数={failed_batches}, 总耗时={time.time() - write_start:.2f}s')
                if log_callback:
                    log_callback(f'批量写入完成: 成功{written}/{total_rows}条, 失败批数={failed_batches}')
            except Exception as e:
                try:
                    conn.rollback()
                except Exception:
                    pass
                logger.error(f'[工程文件名解析] 批量写入连接级失败（已中断剩余批次）: {e}', exc_info=True)
                if log_callback:
                    log_callback(f'批量写入数据库连接失败: {e}')
            finally:
                conn.close()
        else:
            logger.warning('[工程文件名解析] 未提供 pymysql_factory，使用 SQLAlchemy upsert（兼容 SQLite）')
            for bi in range(n_batches):
                i = bi * BULK_BATCH
                chunk = insert_batch[i:i + BULK_BATCH]
                batch_no = bi + 1
                b_t0 = time.time()
                try:
                    _upsert_metadata_sqlalchemy(
                        db_session_factory, chunk,
                        ['novel_name', 'author', 'progress', 'source'],
                    )
                    written += len(chunk)
                    if bi % 10 == 0 or bi == n_batches - 1:
                        _report(force=True)
                    logger.info(f'[工程文件名解析] upsert 第{batch_no}/{n_batches}批成功: '
                                f'{len(chunk)}条, 累计写入={written}, 耗时={time.time() - b_t0:.2f}s')
                except Exception as e:
                    failed_batches += 1
                    err_msg = f'upsert 第{batch_no}/{n_batches}批失败: {e}'
                    logger.error(f'[工程文件名解析] {err_msg}', exc_info=True)
                    if log_callback:
                        log_callback(err_msg)
    else:
        logger.info('[工程文件名解析] 没有需要写入的数据（全部跳过或失败）')

    _report(force=True)

    total_skipped = skipped_count
    logger.info(f'工程文件名解析完成: 总计={total}, 成功={success_count}, 跳过={total_skipped}, 失败={failed_count}')
    return {
        'total': total,
        'success': success_count,
        'failed': failed_count,
        'skipped': total_skipped,
    }


def parse_file_summary_regex_only(
    db: Session,
    file_ids: Optional[List[int]] = None,
    config_id: Optional[int] = None,
    progress_callback=None,
    cancel_check=None,
    log_callback=None,
    db_session_factory=None,
    pymysql_factory=None,
    concurrency: int = 8,
    force: bool = False,
) -> dict:
    """仅使用工程方法（正则）提取文件摘要，不调用 AI。

    单线程顺序读取文件并提取摘要，主进程收集结果后拼接批量 upsert 语句一次性写入数据库。
    「解析全部」按 config_id 分页流式处理，避免一次性加载全部记录与超大 IN 子句。
    """
    PAGE_SIZE = 5000

    if file_ids:
        total = len(file_ids)
    elif config_id is not None:
        total = db.query(func.count(ScanResult.id)).filter(
            ScanResult.scan_config_id == config_id
        ).scalar() or 0
    else:
        total = 0

    logger.info(f'[工程摘要解析][入口] 入参: file_ids={"{}个".format(len(file_ids)) if file_ids else "None"}, '
                f'config_id={config_id}, '
                f'pymysql_factory={"已提供" if pymysql_factory else "未提供(回退SQLAlchemy)"}')
    if log_callback:
        log_callback('正在准备解析任务...')

    if total == 0:
        logger.info('[工程摘要解析][入口] 没有需要解析的文件，直接返回')
        if progress_callback:
            progress_callback(0, 0, 0, 0)
        return {'total': 0, 'success': 0, 'failed': 0}

    if progress_callback:
        progress_callback(0, total, 0, 0)

    BULK_BATCH = 500
    success_count = 0
    skipped_count = 0
    failed_count = 0
    processed = 0
    insert_batch = []

    REPORT_INTERVAL = 1.0
    MAX_FAIL_SAMPLE = 30
    _last_report_ts = [0.0]

    def _report(force=False):
        now = time.time()
        if not force and (now - _last_report_ts[0]) < REPORT_INTERVAL:
            return
        _last_report_ts[0] = now
        if progress_callback:
            progress_callback(processed, total, success_count, failed_count)
        msg = f'进度 {processed}/{total}（成功 {success_count}，跳过 {skipped_count}，失败 {failed_count}）'
        logger.info(msg)
        if log_callback:
            log_callback(msg)

    def _iter_record_pages():
        if file_ids:
            for start in range(0, len(file_ids), PAGE_SIZE):
                chunk = file_ids[start:start + PAGE_SIZE]
                recs = db.query(ScanResult).filter(ScanResult.id.in_(chunk)).all()
                if recs:
                    yield recs
        elif config_id is not None:
            offset = 0
            while True:
                recs = db.query(ScanResult).filter(
                    ScanResult.scan_config_id == config_id
                ).offset(offset).limit(PAGE_SIZE).all()
                if not recs:
                    break
                yield recs
                offset += PAGE_SIZE

    _report(force=True)
    t_start = time.time()

    for page_recs in _iter_record_pages():
        if cancel_check and cancel_check():
            logger.warning(f'[工程摘要解析] 任务在 {processed}/{total} 处被取消')
            if log_callback:
                log_callback(f'任务在 {processed}/{total} 处被取消')
            break

        record_ids = [r.id for r in page_recs]
        existing_metas = db.query(FileMetadata).filter(
            FileMetadata.scan_result_id.in_(record_ids)
        ).all()
        existing_ids = {m.scan_result_id for m in existing_metas if m.summary}

        page_skipped = 0
        need_parse = []
        for rec in page_recs:
            if not force and rec.id in existing_ids:
                page_skipped += 1
                logger.info(f'  ~ {rec.file_name[:60]} → 跳过（已有摘要）')
                continue
            need_parse.append((rec.id, rec.file_path, rec.file_name))

        skipped_count += page_skipped
        processed += page_skipped
        _report()

        if not need_parse:
            continue

        cancelled = False
        for (rid, fpath, fname) in need_parse:
            if cancel_check and cancel_check():
                cancelled = True
                break
            result = _summary_worker((rid, fpath, fname))
            processed += 1
            if result.get('success'):
                insert_batch.append({
                    'scan_result_id': result['rec_id'],
                    'summary': result.get('summary', ''),
                    'parsed_at': datetime.now(),
                })
                if result.get('summary'):
                    success_count += 1
                    logger.info(f'  [+] {fname[:60]} → 摘要提取成功 ({len(result.get("summary",""))}字)')
            elif result.get('failed'):
                failed_count += 1
                logger.info(f'  [-] {fname[:60]} → 摘要提取失败')
                if failed_count <= MAX_FAIL_SAMPLE:
                    msg = f'摘要解析失败: {result.get("file_name", "?")}（{result.get("reason", "")}）'
                    logger.warning(msg)
                    if log_callback:
                        log_callback(msg)
        if cancelled:
            logger.warning('[工程摘要解析] 已取消，停止后续解析')
            break
        _report(force=True)

    _report(force=True)

    logger.info(f'工程摘要解析(解析阶段)完成: 总计={total}, 成功={success_count}, 跳过={skipped_count}, '
                f'失败={failed_count}, 耗时={time.time() - t_start:.1f}s')

    if insert_batch:
        total_rows = len(insert_batch)
        n_batches = (total_rows + BULK_BATCH - 1) // BULK_BATCH
        logger.info(f'[工程摘要解析] 全部 worker 结束，开始批量写入: 待写入={total_rows}条, '
                    f'共{n_batches}批, 每批={BULK_BATCH}, 使用={"pymysql" if pymysql_factory else "SQLAlchemy回退"}')
        if log_callback:
            log_callback(f'开始批量写入数据库: 共{total_rows}条, 分{n_batches}批, 每批{BULK_BATCH}条')
        written = 0
        failed_batches = 0
        write_start = time.time()
        if pymysql_factory:
            conn = pymysql_factory()
            try:
                with conn.cursor() as cur:
                    for bi in range(n_batches):
                        i = bi * BULK_BATCH
                        chunk = insert_batch[i:i + BULK_BATCH]
                        batch_no = bi + 1
                        placeholders = []
                        values = []
                        for row in chunk:
                            placeholders.append('(%s, %s, %s)')
                            values.extend([
                                row['scan_result_id'], row['summary'],
                                row['parsed_at'],
                            ])
                        sql = (
                            "INSERT INTO file_metadata "
                            "(scan_result_id, summary, parsed_at) VALUES "
                            + ", ".join(placeholders) +
                            " ON DUPLICATE KEY UPDATE "
                            "summary = VALUES(summary), "
                            "parsed_at = VALUES(parsed_at)"
                        )
                        logger.debug(f'[工程摘要解析] 批量写入第{batch_no}/{n_batches}批开始: 本批{len(chunk)}条')
                        b_t0 = time.time()
                        try:
                            affected = _pymysql_execute_with_retry(conn, sql, values)
                        except Exception as be:
                            try:
                                conn.rollback()
                            except Exception:
                                pass
                            failed_batches += 1
                            err_msg = f'批量写入第{batch_no}/{n_batches}批失败（已回滚本批）: {be}'
                            logger.error(f'[工程摘要解析] {err_msg}', exc_info=True)
                            if log_callback:
                                log_callback(err_msg)
                            continue
                        written += len(chunk)
                        b_elapsed = time.time() - b_t0
                        if b_elapsed > 5:
                            logger.warning(f'[工程摘要解析] 批量写入第{batch_no}/{n_batches}批耗时过长: '
                                           f'本批{len(chunk)}条, 影响行数={affected}, 耗时={b_elapsed:.2f}s')
                        if bi % 10 == 0 or bi == n_batches - 1:
                            _report(force=True)
                        logger.info(f'[工程摘要解析] 批量写入第{batch_no}/{n_batches}批成功: '
                                    f'本批{len(chunk)}条, 影响行数={affected}, 累计写入={written}, 耗时={b_elapsed:.2f}s')
                logger.info(f'[工程摘要解析] 批量写入全部完成: 成功写入={written}/{total_rows}条, '
                            f'失败批数={failed_batches}, 总耗时={time.time() - write_start:.2f}s')
                if log_callback:
                    log_callback(f'批量写入完成: 成功{written}/{total_rows}条, 失败批数={failed_batches}')
            except Exception as e:
                try:
                    conn.rollback()
                except Exception:
                    pass
                logger.error(f'[工程摘要解析] 批量写入连接级失败（已中断剩余批次）: {e}', exc_info=True)
                if log_callback:
                    log_callback(f'批量写入数据库连接失败: {e}')
            finally:
                conn.close()
        else:
            logger.warning('[工程摘要解析] 未提供 pymysql_factory，使用 SQLAlchemy upsert（兼容 SQLite）')
            for bi in range(n_batches):
                i = bi * BULK_BATCH
                chunk = insert_batch[i:i + BULK_BATCH]
                batch_no = bi + 1
                b_t0 = time.time()
                try:
                    _upsert_metadata_sqlalchemy(
                        db_session_factory, chunk,
                        ['summary', 'parsed_at'],
                    )
                    written += len(chunk)
                    if bi % 10 == 0 or bi == n_batches - 1:
                        _report(force=True)
                    logger.info(f'[工程摘要解析] upsert 第{batch_no}/{n_batches}批成功: '
                                f'{len(chunk)}条, 累计写入={written}, 耗时={time.time() - b_t0:.2f}s')
                except Exception as e:
                    failed_batches += 1
                    err_msg = f'upsert 第{batch_no}/{n_batches}批失败: {e}'
                    logger.error(f'[工程摘要解析] {err_msg}', exc_info=True)
                    if log_callback:
                        log_callback(err_msg)
    else:
        logger.info('[工程摘要解析] 没有需要写入的数据（全部跳过或失败）')

    _report(force=True)

    total_skipped = skipped_count
    logger.info(f'工程摘要解析完成: 总计={total}, 成功={success_count}, 跳过={total_skipped}, 失败={failed_count}')
    return {
        'total': total,
        'success': success_count,
        'failed': failed_count,
        'skipped': total_skipped,
    }
