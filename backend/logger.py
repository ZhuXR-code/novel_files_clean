"""日志系统配置"""
import os
import logging
import multiprocessing
from logging.handlers import RotatingFileHandler

LOG_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'logs')
LOG_FILE = os.path.join(LOG_DIR, 'app.log')

# 保留的轮转日志文件数量（与实际行为保持一致，避免文档与代码不符）
LOG_BACKUP_COUNT = 30
LOG_MAX_BYTES = 10 * 1024 * 1024


def setup_logger(name='file_scanner', level=logging.DEBUG):
    """设置并返回日志记录器。

    多进程安全：解析任务使用 ProcessPoolExecutor（spawn）会在子进程重新导入本模块，
    若子进程也挂载 RotatingFileHandler，多个进程同时持有并轮转同一 app.log 文件，
    在 Windows 上会导致 rollover 时 PermissionError（无法重命名被占用文件）。
    因此：仅主进程挂载文件轮转 Handler；子进程只保留控制台输出。
    """
    os.makedirs(LOG_DIR, exist_ok=True)

    logger = logging.getLogger(name)
    logger.setLevel(level)

    # 避免重复添加handler
    if logger.handlers:
        return logger

    is_child_process = multiprocessing.current_process().name != 'MainProcess'

    # 控制台输出（主/子进程都有）
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_fmt = logging.Formatter(
        '%(asctime)s | %(levelname)-8s | %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    console_handler.setFormatter(console_fmt)
    logger.addHandler(console_handler)

    # 文件输出（按大小轮转，保留 LOG_BACKUP_COUNT 个文件，每个 10MB）——仅主进程
    if not is_child_process:
        file_handler = RotatingFileHandler(
            LOG_FILE, maxBytes=LOG_MAX_BYTES, backupCount=LOG_BACKUP_COUNT, encoding='utf-8'
        )
        file_handler.setLevel(level)
        file_fmt = logging.Formatter(
            '%(asctime)s | %(levelname)-8s | %(name)s | %(filename)s:%(lineno)d | %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        file_handler.setFormatter(file_fmt)
        logger.addHandler(file_handler)

    return logger


# 全局日志实例
logger = setup_logger()
