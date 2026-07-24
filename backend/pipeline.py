"""一键清理流程（Pipeline）后台任务管理器

设计要点：
  - 单实例：同一时刻仅允许一个一键清理流程运行（并发=1）。
  - 流程节点（串行）：
      1. scan  扫描
      2. parse 工程文件名解析（全部，正则，多进程）
      3. group 生成合集（rebuild_file_groups）
      4. mark  勾选重复，计算待删除 id 集合
      5. clean 清理删除 —— 需用户「二次确认」后才真正执行
  - 打断语义：取消后「已完成节点保留、不回滚」，后续节点跳过。
  - 二次确认：节点 5 在真正删除前进入 awaiting_confirm 状态，前端展示
        将被删除的清单供用户确认；确认后才删除，取消则放弃删除。
  - 日志：复用 add_parse_log（写入内存 + ParseLog 表），可跨重启回溯。
"""
import os
import time
import uuid
import threading
from collections import defaultdict
from datetime import datetime
from typing import Optional

from sqlalchemy import func
from backend.logger import logger
from backend.models import ScanResult, FileMetadata, FileGroup, ScanConfig, ParseLog
from backend.scanner import scan_files
from backend.regex_parser import parse_file_names_regex_only
from backend.operation_log import log_operation


# ---------- 全局单例状态 ----------
_pipeline_lock = threading.Lock()
_pipeline_state = None          # 当前流程状态（最多一个）


# 由 app.py 在启动时注入，避免循环 import
_session_factory = None
_pymysql_factory = None
_log_func = None
_rebuild_func = None


NODE_DEFS = [
    ('scan',  '扫描'),
    ('parse', '工程文件名解析'),
    ('group', '生成合集'),
    ('mark',  '勾选重复'),
    ('clean', '清理删除'),
]

COMPLETION_KEYWORDS = ['完结', '番外', '完本', '全本']


class _Cancel(Exception):
    """内部信号：流程被用户取消"""
    pass


def init_pipeline(session_factory, pymysql_factory, log_func, rebuild_file_groups_func):
    """由 app.py 在启动时调用，注入数据库与会话依赖（避免循环 import）"""
    global _session_factory, _pymysql_factory, _log_func, _rebuild_func
    _session_factory = session_factory
    _pymysql_factory = pymysql_factory
    _log_func = log_func
    _rebuild_func = rebuild_file_groups_func


def _now():
    return datetime.now()


def _log(msg, level=''):
    if _log_func and _pipeline_state:
        _log_func(_pipeline_state['task_id'], msg, level,
                  db_session_factory=_session_factory)


def _is_under_root(root, path):
    """判断 path 是否位于 root 目录（含子目录）内，防止路径穿越"""
    try:
        root_abs = os.path.abspath(root)
        path_abs = os.path.abspath(path)
        return os.path.commonpath([root_abs]) == os.path.commonpath([root_abs, path_abs])
    except Exception:
        return False


# ===================== 核心计算：勾选重复 =====================
def compute_duplicate_ids(db, config_id):
    """计算某配置下「应删除」的 ScanResult id 集合。

    直接复用 dup_logic.compute_duplicate_ids 的五则规则，与
    /api/groups/select-duplicates 端点完全一致，避免一键清理与手动勾选重复结果不一致。
    """
    # 取出该 config 下全部条目（含 novel_name 为空者，由 dup_logic 按 (作者+小说名) 分组处理）
    items = db.query(
        ScanResult.id,
        ScanResult.file_name,
        ScanResult.file_size,
        func.coalesce(FileMetadata.novel_name, '').label('novel_name'),
        FileMetadata.author,
        FileMetadata.progress,
        func.coalesce(FileMetadata.source, '').label('source'),
        ScanResult.created_date,
    ).outerjoin(
        FileMetadata, ScanResult.id == FileMetadata.scan_result_id
    ).filter(
        ScanResult.scan_config_id == config_id,
    ).all()

    rows = [{
        'id': it.id,
        'file_name': it.file_name or '',
        'file_size': it.file_size or 0,
        'novel_name': it.novel_name or '',
        'author': it.author or '',
        'progress': it.progress or '',
        'source': it.source or '',
        'created_date': it.created_date,
    } for it in items]

    if not rows:
        return []

    from backend.dup_logic import compute_duplicate_ids as _dup_compute
    from backend.models import DupRuleConfig
    import json
    # 读取用户配置的勾选重复规则开关
    dup_rule_configs = db.query(DupRuleConfig).filter(DupRuleConfig.enabled == True).all()
    enabled_rules = {r.rule_key for r in dup_rule_configs if r.is_builtin}
    user_rules = [
        {
            'id': r.id,
            'action': r.action or 'check',
            'conditions': json.loads(r.conditions) if r.conditions else [],
        }
        for r in dup_rule_configs if not r.is_builtin and r.conditions
    ]
    all_ids, _subgroups, _detail = _dup_compute(rows, enabled_rules=enabled_rules, user_rules=user_rules or None)
    _log(f'勾选重复规则已启用: {",".join(r.rule_name for r in dup_rule_configs)}')
    return list(all_ids)


# ===================== 删除执行 =====================
def _delete_records(db, ids, delete_mode, config_folder, progress_cb):
    """批量删除记录（及源文件）。返回 (deleted, failed_paths)"""
    total = len(ids)
    batch = 20 if delete_mode == 'file' else 100
    done = 0
    deleted = 0
    failed = []
    scan_root = os.path.abspath(config_folder) if config_folder else ''

    for i in range(0, total, batch):
        if _pipeline_state and _pipeline_state['cancel_event'].is_set():
            break
        chunk = ids[i:i + batch]
        if delete_mode == 'file':
            for rid in chunk:
                rec = db.query(ScanResult).filter(ScanResult.id == rid).first()
                if not rec:
                    continue
                fp = rec.file_path
                if scan_root and not _is_under_root(scan_root, fp):
                    failed.append(fp)
                    continue
                if os.path.exists(fp):
                    for _ in range(3):
                        try:
                            os.remove(fp)
                        except Exception:
                            pass
                        time.sleep(0.1)
                        if not os.path.exists(fp):
                            break
                if os.path.exists(fp):
                    failed.append(fp)
                    continue
                db.query(ScanResult).filter(ScanResult.id == rid).delete(synchronize_session=False)
                deleted += 1
            db.commit()
        else:
            db.query(ScanResult).filter(ScanResult.id.in_(chunk)).delete(synchronize_session=False)
            db.commit()
            deleted += len(chunk)
        done += len(chunk)
        if progress_cb:
            progress_cb(done, total)
    return deleted, failed


# ===================== 流程控制 =====================
def start_pipeline(config_id, delete_mode):
    """启动一键清理。已在运行时抛 RuntimeError（单实例约束）。"""
    try:
        log_operation('一键清理-启动', detail=f'delete_mode={delete_mode}',
                      config_id=config_id, delete_mode=delete_mode)
    except Exception as _ole:
        logger.warning(f'操作日志写入失败: {_ole}')
    global _pipeline_state
    with _pipeline_lock:
        if _pipeline_state and _pipeline_state['status'] in ('running', 'awaiting_confirm'):
            raise RuntimeError('已有进行中的一键清理任务，请先取消或等待其完成')
        task_id = str(uuid.uuid4())[:8]
        nodes = [{
            'key': k, 'name': n, 'status': 'pending',
            'processed': 0, 'total': 0, 'started_at': None,
            'ended_at': None, 'message': '',
        } for k, n in NODE_DEFS]
        _pipeline_state = {
            'task_id': task_id,
            'status': 'running',
            'config_id': config_id,
            'delete_mode': delete_mode,
            'started_at': _now(),
            'nodes': nodes,
            'cancel_event': threading.Event(),
            'confirm_event': threading.Event(),
            'deletion_ids': [],
            'deletion_preview': [],
            '_scan_prog': {},
        }
    t = threading.Thread(target=_run, args=(config_id, delete_mode), daemon=True)
    t.start()
    return task_id


def _set_node(key, **kw):
    if not _pipeline_state:
        return
    for n in _pipeline_state['nodes']:
        if n['key'] == key:
            n.update(kw)
            break


def _run(config_id, delete_mode):
    db = _session_factory()
    state = _pipeline_state
    current = None
    try:
        cancel = lambda: state['cancel_event'].is_set()

        # ---------- 节点1：扫描 ----------
        current = 'scan'
        _set_node('scan', status='running', started_at=_now())
        _log('开始扫描目标路径...')
        config = db.query(ScanConfig).filter(ScanConfig.id == config_id).first()
        if not config:
            raise ValueError('扫描配置不存在')
        file_types = [ft.strip() for ft in (config.file_types or 'txt').split(',') if ft.strip()]
        excluded = [f.strip() for f in (config.excluded_folders or '').split(',') if f.strip()]
        scan_prog = {config_id: {'count': 0, 'start_time': _now()}}
        new_count, total = scan_files(
            db=db, config_id=config.id, folder_path=config.folder_path,
            file_types=file_types, excluded_folders=excluded, progress_dict=scan_prog,
        )
        state['_scan_prog'] = scan_prog
        _rebuild_func(config_id, db)
        _set_node('scan', status='done', processed=total, total=total, ended_at=_now(),
                   message=f'新增 {new_count}，共 {total} 个文件')
        _log(f'扫描完成：新增 {new_count}，总计 {total}')
        if cancel():
            raise _Cancel()

        # ---------- 节点2：工程文件名解析（全部） ----------
        current = 'parse'
        _set_node('parse', status='running', started_at=_now())
        _log('开始工程文件名解析（全部，正则）...')
        total_count = db.query(func.count(ScanResult.id)).filter(
            ScanResult.scan_config_id == config_id).scalar() or 0
        if total_count == 0:
            _log('没有可解析的文件，跳过', 'warn')
        else:
            def _pcb(processed, total, success, failed):
                _set_node('parse', processed=processed, total=total,
                           message=f'成功 {success}，失败 {failed}')
            parse_file_names_regex_only(
                db, config_id=config_id, progress_callback=_pcb,
                cancel_check=cancel, log_callback=_log,
                db_session_factory=_session_factory,
                pymysql_factory=_pymysql_factory, concurrency=8,
            )
        _set_node('parse', status='done', ended_at=_now(), message='解析完成')
        _log('工程文件名解析完成')
        if cancel():
            raise _Cancel()

        # ---------- 节点3：生成合集 ----------
        current = 'group'
        _set_node('group', status='running', started_at=_now())
        _log('开始生成合集...')
        _rebuild_func(config_id, db)
        _set_node('group', status='done', ended_at=_now(), message='合集已生成')
        _log('合集生成完成')
        if cancel():
            raise _Cancel()

        # ---------- 节点4：勾选重复 ----------
        current = 'mark'
        _set_node('mark', status='running', started_at=_now())
        _log('开始勾选重复，计算待删除项...')
        del_ids = compute_duplicate_ids(db, config_id)
        state['deletion_ids'] = del_ids
        _set_node('mark', status='done', processed=len(del_ids), total=len(del_ids),
                   ended_at=_now(), message=f'待删除 {len(del_ids)} 项')
        _log(f'勾选重复完成：待删除 {len(del_ids)} 项')
        if cancel():
            raise _Cancel()

        # ---------- 节点5：清理删除（二次确认） ----------
        current = 'clean'
        _set_node('clean', status='awaiting_confirm', started_at=_now())
        state['status'] = 'awaiting_confirm'
        preview = _build_preview(db, del_ids)
        state['deletion_preview'] = preview
        _log(f'已计算出待删除 {len(del_ids)} 项，等待用户二次确认...', 'warn')

        while (not state['confirm_event'].is_set()
               and not state['cancel_event'].is_set()):
            time.sleep(0.5)

        if state['cancel_event'].is_set():
            _set_node('clean', status='cancelled', ended_at=_now(), message='用户取消，未删除')
            _log('用户在二次确认阶段取消，跳过删除', 'warn')
            raise _Cancel()

        _log('用户已确认，开始删除...')
        _set_node('clean', status='running', message='删除中...')

        def _ccb(done, total):
            _set_node('clean', processed=done, total=total)

        deleted, failed = _delete_records(
            db, del_ids, delete_mode, config.folder_path, _ccb)
        _rebuild_func(config_id, db)
        _set_node('clean', status='done', processed=deleted, total=len(del_ids),
                   ended_at=_now(),
                   message=f'已删除 {deleted} 项' + (f'，失败 {len(failed)}' if failed else ''))
        _log(f'清理完成：已删除 {deleted} 项' + (f'，失败 {len(failed)}' if failed else ''),
             'info' if not failed else 'warn')
        try:
            log_operation('一键清理-删除', detail=f"已删除 {deleted} 项" + (f'，失败 {len(failed)}' if failed else ''),
                          config_id=config_id, delete_mode=delete_mode, deleted=deleted, failed=len(failed))
        except Exception as _ole:
            logger.warning(f'操作日志写入失败: {_ole}')
        state['status'] = 'done'
        _log('一键清理全流程完成 ✅', 'info')

    except _Cancel:
        state['status'] = 'cancelled'
        _log('流程已取消（已完成节点保留，不回滚）', 'warn')
        for n in state['nodes']:
            if n['status'] in ('pending', 'running', 'awaiting_confirm'):
                n['status'] = 'cancelled'
                n['ended_at'] = _now()
    except Exception as e:
        logger.exception('一键清理流程出错')
        state['status'] = 'error'
        _log(f'流程出错：{e}', 'error')
        if current:
            for n in state['nodes']:
                if n['key'] == current and n['status'] in ('running', 'awaiting_confirm'):
                    n['status'] = 'error'
                    n['ended_at'] = _now()
                elif n['status'] in ('pending', 'running'):
                    n['status'] = 'cancelled'
                    n['ended_at'] = _now()
    finally:
        try:
            db.close()
        except Exception:
            pass


def _build_preview(db, ids):
    if not ids:
        return []
    records = db.query(
        ScanResult.id, ScanResult.file_name, ScanResult.file_path
    ).filter(ScanResult.id.in_(ids)).all()
    return [{'id': r.id, 'file_name': r.file_name, 'file_path': r.file_path}
            for r in records]


# ===================== 对外查询 =====================
def get_status():
    with _pipeline_lock:
        if not _pipeline_state:
            return {'status': 'idle'}
        s = _pipeline_state
        nodes = []
        for n in s['nodes']:
            nodes.append({
                'key': n['key'], 'name': n['name'], 'status': n['status'],
                'processed': n['processed'], 'total': n['total'],
                'message': n['message'],
            })
        scan_count = 0
        sp = s.get('_scan_prog', {}).get(s['config_id'])
        if sp:
            scan_count = sp.get('count', 0)
        preview = s.get('deletion_preview', [])
        preview_total = len(preview)
        preview_sample = preview[:500]
        return {
            'task_id': s['task_id'],
            'status': s['status'],
            'config_id': s['config_id'],
            'delete_mode': s['delete_mode'],
            'started_at': s['started_at'].isoformat() if s['started_at'] else None,
            'nodes': nodes,
            'scan_count': scan_count,
            'deletion_count': preview_total,
            'preview_sample': preview_sample,
            'preview_truncated': preview_total > len(preview_sample),
        }


def get_logs():
    if not _pipeline_state:
        return []
    tid = _pipeline_state['task_id']
    db = _session_factory()
    try:
        rows = db.query(ParseLog).filter(
            ParseLog.task_id == tid
        ).order_by(ParseLog.id.asc()).limit(2000).all()
        return [{
            'time': r.created_at.strftime('%H:%M:%S') if r.created_at else '',
            'msg': r.message, 'level': r.level,
        } for r in rows]
    finally:
        db.close()


def cancel_pipeline():
    if _pipeline_state:
        _pipeline_state['cancel_event'].set()
        return True
    return False


def confirm_pipeline():
    if _pipeline_state and _pipeline_state['status'] == 'awaiting_confirm':
        _pipeline_state['confirm_event'].set()
        return True
    return False
