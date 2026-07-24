"""操作日志模块（用户关键操作留痕）

与 pipeline 调试日志（ParseLog / logger）不同，操作日志聚焦“用户做了什么”：
勾选重复、删除记录、清空配置、一键清理删除等。落盘到项目根 logs/operation.log，
带滚动切分与实时 flush，供前端「操作日志」面板查看与一键复制。

设计要点：
  - 单文件 + RotatingFileHandler（5MB × 10 备份），进程内加锁，写完立即 flush。
  - 每条日志以 "[YYYY-MM-DD HH:MM:SS] [操作] ..." 开头，便于 get_operation_logs
    按时间戳拆分为独立块。
  - get_operation_logs 返回「字符串列表」，每条为一个完整日志块；前端以
    logs.join('\\n\\n') 渲染，因此此处不返回 dict。
"""
import logging
import os
import re
import threading
from datetime import datetime
from logging.handlers import RotatingFileHandler

from backend.db_config import app_data_root

# 操作日志统一落在安装目录的 FileScannerData/logs（与数据库同根），不再散落到项目/Python 目录
_LOG_DIR = os.path.join(app_data_root(), 'logs')
_LOG_FILE = os.path.join(_LOG_DIR, 'operation.log')

_lock = threading.Lock()
_op_logger = None

_TS_RE = re.compile(r'(?=^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] )', re.MULTILINE)


def _get_logger():
    global _op_logger
    if _op_logger is None:
        os.makedirs(_LOG_DIR, exist_ok=True)
        lg = logging.getLogger('file_scanner.operation')
        lg.setLevel(logging.INFO)
        lg.propagate = False
        if not lg.handlers:
            handler = RotatingFileHandler(
                _LOG_FILE, maxBytes=5 * 1024 * 1024, backupCount=10, encoding='utf-8'
            )
            handler.setFormatter(logging.Formatter('%(message)s'))
            lg.addHandler(handler)
        _op_logger = lg
    return _op_logger


def _stamp():
    return datetime.now().strftime('%Y-%m-%d %H:%M:%S')


def log_operation(action, detail='', **meta):
    """记录一条操作日志。

    action: 操作名，如 '勾选重复' / '删除记录' / '清空扫描配置' / '一键清理-删除'
    detail: 单行摘要
    meta:   额外字段（以 key=value 追加），如 config_id=1, deleted=10
    """
    lines = [f"[{_stamp()}] [操作] {action}"]
    if detail:
        lines.append(f"  摘要: {detail}")
    for k, v in meta.items():
        lines.append(f"  {k}={v}")
    text = "\n".join(lines)
    with _lock:
        try:
            lg = _get_logger()
            lg.info(text)
            for h in lg.handlers:
                h.flush()
        except Exception:
            pass


def log_block(title, lines):
    """记录一个带标题的多行明细块（如重复组逐项信息）。"""
    if not lines:
        return
    body = "\n".join(str(x) for x in lines)
    text = f"[{_stamp()}] [明细] {title}\n{body}"
    with _lock:
        try:
            lg = _get_logger()
            lg.info(text)
            for h in lg.handlers:
                h.flush()
        except Exception:
            pass


def get_operation_logs(limit=2000):
    """读取 operation.log，按日志块拆分后返回最近 limit 个块（字符串列表）。

    前端「操作日志」面板以 logs.join('\\n\\n') 渲染，故此处返回字符串列表。
    """
    if not os.path.exists(_LOG_FILE):
        return []
    try:
        with _lock:
            with open(_LOG_FILE, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
    except Exception:
        return []
    blocks = [b.strip() for b in _TS_RE.split(content) if b.strip()]
    if limit and len(blocks) > limit:
        blocks = blocks[-limit:]
    return blocks
