"""文件扫描模块"""
import os
from datetime import datetime
from typing import List, Tuple, Optional, Dict
from sqlalchemy.orm import Session

from backend.logger import logger
from backend.models import ScanConfig, ScanResult
from backend.keyword_replace import load_rules, apply_rules


def scan_files(
    db: Session,
    config_id: int,
    folder_path: str,
    file_types: List[str],
    excluded_folders: List[str],
    progress_dict: Optional[Dict[int, int]] = None,
) -> Tuple[int, int]:
    """
    扫描指定文件夹下的所有符合类型的文件
    
    Args:
        db: 数据库会话
        config_id: 扫描配置ID
        folder_path: 要扫描的文件夹路径
        file_types: 文件类型列表，如 ['txt', 'md']
        excluded_folders: 排除的文件夹名称列表
        progress_dict: 进度字典，用于实时更新进度
    
    Returns:
        (新增数量, 总数量) 元组
    """
    if not os.path.isdir(folder_path):
        logger.error(f'文件夹不存在: {folder_path}')
        raise FileNotFoundError(f'文件夹不存在: {folder_path}')

    # 加载「扫描阶段」关键词替换规则（一次性加载，循环内复用）
    scan_rules = load_rules(db, 'scan')

    # 加载该配置下已有的文件路径，用于去重跳过
    existing_records = db.query(ScanResult.file_path).filter(
        ScanResult.scan_config_id == config_id
    ).all()
    # Windows 路径不区分大小写，统一转为小写
    if os.name == 'nt':
        existing_paths = {r[0].lower() for r in existing_records}
    else:
        existing_paths = {r[0] for r in existing_records}

    file_types_set = {ft.strip().lower().lstrip('.') for ft in file_types if ft.strip()}

    # 构建排除集：纯文件夹名 + 相对路径（从扫描根目录算起）
    excluded_set = set()
    excluded_rel_paths = set()
    folder_path_norm = folder_path.lower().rstrip('\\/')
    for folder in excluded_folders:
        f = folder.strip()
        if not f:
            continue
        f_lower = f.lower().rstrip('\\/')
        # 如果排除项是完整路径且以扫描根目录开头，提取相对路径
        if f_lower.startswith(folder_path_norm):
            rel = f_lower[len(folder_path_norm):].lstrip('\\/')
            if rel:
                excluded_rel_paths.add(rel)
            else:
                excluded_set.add(f_lower)  # 排除根目录本身
        else:
            excluded_set.add(f_lower)  # 纯文件夹名匹配

    new_count = 0
    skip_count = 0
    batch = []
    batch_size = 50
    processed = 0
    total_found = 0

    for root, dirs, files in os.walk(folder_path):
        # 排除配置的文件夹（修改dirs使得os.walk不再进入排除的目录）
        relative_root = os.path.relpath(root, folder_path)
        dirs[:] = [d for d in dirs if d.lower() not in excluded_set]

        # 检查当前路径是否在排除列表中（处理中间路径被排除的情况）
        if relative_root != '.':
            path_parts = relative_root.replace('\\', '/').split('/')
            if any(part.lower() in excluded_set for part in path_parts):
                continue
            # 检查相对路径匹配（排除完整路径的情况）
            rel_norm = relative_root.replace('\\', '/').lower()
            if any(rel_path.replace('\\', '/') in rel_norm for rel_path in excluded_rel_paths):
                dirs[:] = []
                continue

        for file in files:
            ext = os.path.splitext(file)[1].lower().lstrip('.')
            if ext in file_types_set:
                full_path = os.path.join(root, file)
                total_found += 1
                processed += 1

                # 检查文件是否已在库中
                check_path = full_path.lower() if os.name == 'nt' else full_path
                if check_path in existing_paths:
                    skip_count += 1
                    # 更新进度（含跳过文件）
                    if progress_dict is not None and config_id in progress_dict:
                        progress_dict[config_id]['count'] = processed
                    continue

                try:
                    stat = os.stat(full_path)
                    file_size = stat.st_size
                    # 获取创建时间
                    created_ts = getattr(stat, 'st_birthtime', stat.st_ctime)
                    created_date = datetime.fromtimestamp(created_ts)
                except (OSError, AttributeError) as e:
                    logger.warning(f'无法获取文件信息: {full_path}, {e}')
                    file_size = 0
                    created_date = None

                batch.append(ScanResult(
                    file_name=apply_rules(file, scan_rules),
                    file_size=file_size,
                    file_path=full_path,
                    created_date=created_date,
                    scan_config_id=config_id,
                ))
                new_count += 1
                existing_paths.add(check_path)  # 防止同路径在本次扫描中重复添加

                # 每批达到 batch_size 条即入库
                if len(batch) >= batch_size:
                    db.bulk_save_objects(batch)
                    db.commit()
                    batch = []

                # 更新进度
                if progress_dict is not None and config_id in progress_dict:
                    progress_dict[config_id]['count'] = processed

    # 入库剩余批次
    if batch:
        db.bulk_save_objects(batch)
        db.commit()

    logger.info(f'扫描完成: 文件夹={folder_path}, 类型={file_types}, '
                f'排除={excluded_folders}, 新增={new_count}, 跳过={skip_count}条')

    return new_count, total_found
