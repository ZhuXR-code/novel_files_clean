import { relationalStore } from '@kit.ArkData';
import { RdbHelper } from './RdbHelper';

/** 文件备注实体，对应 file_notes 表。 */
export class FileNote {
  id: number = 0;
  fileId: number = 0;
  content: string = '';
  createdAt: number = 0;
}

/**
 * 文件备注数据访问层。
 * 去重（区分大小写）由 file_notes 的唯一索引 (file_id, content) 保证（SQLite 默认 BINARY）。
 * 新增/编辑时若触发唯一冲突，upsert 会静默忽略重复行（INSERT OR IGNORE）。
 */
export class FileNoteDao {
  private static get store(): relationalStore.RdbStore {
    return RdbHelper.getExisting()!.getStore();
  }

  private static toNote(rs: relationalStore.ResultSet): FileNote {
    const n: FileNote = new FileNote();
    const idxId: number = rs.getColumnIndex('id');
    const idxFile: number = rs.getColumnIndex('file_id');
    const idxContent: number = rs.getColumnIndex('content');
    const idxCreated: number = rs.getColumnIndex('created_at');
    n.id = idxId >= 0 ? rs.getLong(idxId) : 0;
    n.fileId = idxFile >= 0 ? rs.getLong(idxFile) : 0;
    n.content = idxContent >= 0 ? rs.getString(idxContent) : '';
    n.createdAt = idxCreated >= 0 ? rs.getLong(idxCreated) : 0;
    return n;
  }

  /** 取某文件全部备注（按创建时间升序）。 */
  static getNotesByFile(fileId: number): FileNote[] {
    const out: FileNote[] = [];
    const rs = FileNoteDao.store.querySql(
      'SELECT * FROM file_notes WHERE file_id = ? ORDER BY created_at ASC, id ASC',
      [fileId]
    );
    try {
      while (rs.goToNextRow()) {
        out.push(FileNoteDao.toNote(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 批量取多个文件的备注（合并书库复制用）。 */
  static getNotesByFiles(fileIds: number[]): FileNote[] {
    const out: FileNote[] = [];
    if (!fileIds.length) {
      return out;
    }
    const placeholders: string = fileIds.map(() => '?').join(',');
    const rs = FileNoteDao.store.querySql(
      `SELECT * FROM file_notes WHERE file_id IN (${placeholders}) ORDER BY created_at ASC, id ASC`,
      fileIds
    );
    try {
      while (rs.goToNextRow()) {
        out.push(FileNoteDao.toNote(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /**
   * 新增备注，重复内容（区分大小写）忽略（INSERT OR IGNORE）。
   * @returns 是否插入成功（false 表示内容已存在，被忽略）。
   */
  static insert(fileId: number, content: string, createdAt: number): boolean {
    const c: string = content.trim();
    if (!c || c.length > 50) {
      return false;
    }
    try {
      FileNoteDao.store.executeSql(
        'INSERT OR IGNORE INTO file_notes (file_id, content, created_at) VALUES (?, ?, ?)',
        [fileId, c, createdAt]
      );
      // 通过 last_insert_rowid() 判断是否真正插入（重复内容被 IGNORE 时 id 不变/为0）
      const rs = FileNoteDao.store.querySql('SELECT last_insert_rowid() AS lid');
      let id: number = 0;
      try {
        if (rs.goToFirstRow()) {
          const idx = rs.getColumnIndex('lid');
          id = idx >= 0 ? rs.getLong(idx) : 0;
        }
      } finally {
        rs.close();
      }
      return id > 0;
    } catch (e) {
      return false;
    }
  }

  /** 编辑备注内容；若与同文件其它备注内容（区分大小写）冲突则忽略更新并返回 false。 */
  static update(noteId: number, fileId: number, content: string): boolean {
    const c: string = content.trim();
    if (!c || c.length > 50) {
      return false;
    }
    try {
      FileNoteDao.store.executeSql(
        'UPDATE OR IGNORE file_notes SET content = ?, created_at = ? WHERE id = ?',
        [c, Date.now(), noteId]
      );
      // 校验是否真的更新成功（避免被唯一约束忽略却仍返回 OK）
      const rs = FileNoteDao.store.querySql(
        'SELECT id FROM file_notes WHERE file_id = ? AND content = ? AND id = ?',
        [fileId, c, noteId]
      );
      let exists: boolean = false;
      try {
        exists = rs.goToFirstRow();
      } finally {
        rs.close();
      }
      return exists;
    } catch (e) {
      return false;
    }
  }

  static delete(noteId: number): void {
    FileNoteDao.store.executeSql('DELETE FROM file_notes WHERE id = ?', [noteId]);
  }

  static deleteByFile(fileId: number): void {
    FileNoteDao.store.executeSql('DELETE FROM file_notes WHERE file_id = ?', [fileId]);
  }
}
