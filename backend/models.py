"""数据库模型定义"""
import os

from sqlalchemy import Column, Integer, BigInteger, String, Text, DateTime, ForeignKey, Boolean, func, Index
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()

# SQLite 分支（本地 EXE）不使用 MySQL 专属的 mysql_length 索引选项，
# 否则建表时会因方言不兼容而报错。网页版（mysql）保持原逻辑不变。
_IS_SQLITE = os.environ.get('DB_BACKEND', 'mysql').lower() == 'sqlite'


class ScanConfig(Base):
    """扫描配置表"""
    __tablename__ = 'scan_configs'

    __table_args__ = (
        Index('idx_config_folder_path', 'folder_path'),
        Index('idx_config_created_at', 'created_at'),
    )

    id = Column(Integer, primary_key=True, autoincrement=True, comment='扫描配置ID')
    name = Column(String(200), nullable=True, default='', comment='扫描配置自定义名称（可空，为空时回退显示文件夹路径）')
    folder_path = Column(String(500), nullable=False, comment='扫描文件夹路径')
    file_types = Column(String(200), nullable=False, default='txt', comment='文件类型，多个用逗号分隔')
    excluded_folders = Column(Text, nullable=True, comment='排除的文件夹，多个用逗号分隔')
    created_at = Column(DateTime, server_default=func.now(), comment='创建时间')
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now(), comment='更新时间')

    results = relationship('ScanResult', back_populates='config', cascade='all, delete-orphan')


class FileGroup(Base):
    """文件分组表（合集模式预计算结果）"""
    __tablename__ = 'file_groups'

    __table_args__ = (
        Index('idx_group_config_novel', 'config_id', 'novel_name'),
        Index('idx_group_config_count', 'config_id', 'file_count'),
    )

    id = Column(Integer, primary_key=True, autoincrement=True, comment='分组ID')
    config_id = Column(Integer, ForeignKey('scan_configs.id', ondelete='CASCADE'), nullable=False, comment='关联扫描配置ID')
    novel_name = Column(String(500), nullable=False, default='', comment='小说名（合集名）')
    file_count = Column(Integer, nullable=False, default=0, comment='文件数量')
    total_size = Column(BigInteger, nullable=False, default=0, comment='文件总大小')
    created_at = Column(DateTime, server_default=func.now(), comment='创建时间')
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now(), comment='更新时间')


class ScanResult(Base):
    """扫描结果表"""
    __tablename__ = 'scan_results'

    # 仅在 MySQL 下使用 mysql_length（索引前缀），SQLite 下省略该参数
    _file_path_index = (
        Index('idx_file_path', 'file_path', mysql_length=255)
        if not _IS_SQLITE else
        Index('idx_file_path', 'file_path')
    )

    __table_args__ = (
        Index('idx_scan_config_id', 'scan_config_id'),
        Index('idx_file_name', 'file_name'),
        _file_path_index,
        Index('idx_config_id_file_size', 'scan_config_id', 'file_size'),
        Index('idx_created_date', 'created_date'),
        Index('idx_scanned_at', 'scanned_at'),
    )

    id = Column(Integer, primary_key=True, autoincrement=True, comment='扫描结果ID')
    file_name = Column(String(500), nullable=False, comment='完整文件名（含后缀）')
    file_size = Column(BigInteger, nullable=False, default=0, comment='文件大小（字节）')
    file_path = Column(String(1000), nullable=False, comment='文件完整路径')
    created_date = Column(DateTime, nullable=True, comment='文件创建日期')
    scan_config_id = Column(Integer, ForeignKey('scan_configs.id', ondelete='CASCADE'), nullable=False, comment='关联扫描配置ID')
    scanned_at = Column(DateTime, server_default=func.now(), comment='扫描时间')

    config = relationship('ScanConfig', back_populates='results')
    metadata_record = relationship('FileMetadata', back_populates='scan_result', uselist=False, cascade='all, delete-orphan')


class FileMetadata(Base):
    """文件元数据（工程解析结果）"""
    __tablename__ = 'file_metadata'

    __table_args__ = (
        Index('idx_novel_name', 'novel_name'),
        Index('idx_author', 'author'),
    )

    id = Column(Integer, primary_key=True, autoincrement=True, comment='元数据ID')
    scan_result_id = Column(Integer, ForeignKey('scan_results.id', ondelete='CASCADE'), nullable=False, unique=True, comment='关联扫描结果ID')
    novel_name = Column(String(500), nullable=True, comment='小说名')
    author = Column(String(200), nullable=True, comment='作者')
    progress = Column(String(200), nullable=True, comment='更新进度情况，如 完结/更78/完结613+番外')
    source = Column(String(100), nullable=True, comment='来源站点，如 废文/海棠')
    summary = Column(Text, nullable=True, comment='内容简介/摘要（工程正则提取首章前简介）')
    parsed_at = Column(DateTime, nullable=True, comment='解析时间')

    scan_result = relationship('ScanResult', back_populates='metadata_record')


class ColumnConfig(Base):
    """列显示配置表"""
    __tablename__ = 'column_configs'

    __table_args__ = (
        Index('idx_column_sort_order', 'sort_order'),
    )

    id = Column(Integer, primary_key=True, autoincrement=True, comment='列配置ID')
    column_key = Column(String(50), nullable=False, unique=True, comment='列标识')
    display_name = Column(String(100), nullable=False, comment='列显示名称')
    visible = Column(Boolean, nullable=False, default=True, comment='是否显示')
    sort_order = Column(Integer, nullable=False, default=0, comment='排序顺序')


class ParseLog(Base):
    """解析任务日志表（持久化解析步骤日志）"""
    __tablename__ = 'parse_logs'

    __table_args__ = (
        Index('idx_parse_log_task', 'task_id'),
        Index('idx_parse_log_created', 'created_at'),
    )

    id = Column(Integer, primary_key=True, autoincrement=True, comment='日志ID')
    task_id = Column(String(50), nullable=False, comment='任务ID')
    message = Column(Text, nullable=False, comment='日志消息')
    level = Column(String(10), nullable=False, default='info', comment='日志级别: info/warn/error')
    created_at = Column(DateTime, server_default=func.now(), comment='创建时间')


class KeywordReplaceRule(Base):
    """关键词替换规则表（设置页配置）"""
    __tablename__ = 'keyword_replace_rules'

    id = Column(Integer, primary_key=True, autoincrement=True, comment='规则ID')
    scope = Column(String(20), nullable=False, default='scan',
                  comment='作用域: scan=扫描阶段(文件名), parse=解析阶段(书名/作者/进度/来源)')
    pattern = Column(String(500), nullable=False, comment='被替换的关键词/字符串')
    replacement = Column(String(500), nullable=False, default='', comment='替换后的内容，空串表示删除')
    sort_order = Column(Integer, nullable=False, default=0, comment='同作用域内的执行顺序')
    enabled = Column(Boolean, nullable=False, default=True, comment='是否启用')
    created_at = Column(DateTime, server_default=func.now(), comment='创建时间')


class HelpDoc(Base):
    """帮助手册 / 功能说明文档（Markdown 内容存于数据库）"""
    __tablename__ = 'help_docs'

    __table_args__ = (
        Index('idx_help_doc_key', 'doc_key'),
        Index('idx_help_sort_order', 'sort_order'),
    )

    id = Column(Integer, primary_key=True, autoincrement=True, comment='文档ID')
    doc_key = Column(String(100), nullable=False, unique=True, comment='文档唯一标识（如 quickstart）')
    title = Column(String(200), nullable=False, comment='文档标题')
    content = Column(Text, nullable=False, default='', comment='Markdown 正文')
    sort_order = Column(Integer, nullable=False, default=0, comment='显示顺序（从小到大）')
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now(), comment='更新时间')
