package com.filescanner.app.data.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.filescanner.app.data.database.dao.ScannedFileDao
import com.filescanner.app.data.database.dao.ScanConfigDao
import com.filescanner.app.data.database.dao.ScanRunDao
import com.filescanner.app.data.database.dao.KeywordReplaceDao
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.database.entity.ScanConfigEntity
import com.filescanner.app.data.database.entity.ScanRunEntity
import com.filescanner.app.data.database.entity.KeywordReplaceRuleEntity
import com.filescanner.app.util.LogUtil

@Database(
    entities = [
        ScannedFileEntity::class, ScanConfigEntity::class, ScanRunEntity::class,
        KeywordReplaceRuleEntity::class
    ],
    version = 7,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun scannedFileDao(): ScannedFileDao
    abstract fun scanConfigDao(): ScanConfigDao
    abstract fun scanRunDao(): ScanRunDao
    abstract fun keywordReplaceDao(): KeywordReplaceDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null
        private const val TAG = "AppDatabase"
        private const val DB_NAME = "file_scanner.db"

        /** v1 -> v2：新增 scan_config 表，不破坏已有的 scanned_file 数据。 */
        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS scan_config (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        name TEXT NOT NULL DEFAULT '',
                        folder_uri TEXT NOT NULL,
                        folder_name TEXT NOT NULL DEFAULT '',
                        file_types TEXT NOT NULL DEFAULT 'txt',
                        min_size_kb INTEGER NOT NULL DEFAULT 0,
                        recursive INTEGER NOT NULL DEFAULT 1,
                        exact_hash INTEGER NOT NULL DEFAULT 0,
                        excluded_folders TEXT NOT NULL DEFAULT ''
                    )
                    """.trimIndent()
                )
            }
        }

        /** v2 -> v3：为 title 建索引，加速合集模式按书名分组（GROUP BY title）。 */
        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE INDEX IF NOT EXISTS index_scanned_file_title ON scanned_file (title)")
            }
        }

        /**
         * v3 -> v4：引入“文库（每次扫描）”概念。
         * 1) 新建 scan_run 表；
         * 2) scanned_file 增加 scan_run_id 列；
         * 3) 兼容旧数据：把历史全量文件归入一个“历史文库”(id=1)，避免丢失；
         * 4) 唯一约束从 (path) 改为 (path, scan_run_id)，允许同一文件在不同扫描中出现。
         */
        private val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS scan_run (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        name TEXT NOT NULL DEFAULT '',
                        folder_uri TEXT NOT NULL DEFAULT '',
                        folder_name TEXT NOT NULL DEFAULT '',
                        file_types TEXT NOT NULL DEFAULT 'txt',
                        created_at INTEGER NOT NULL DEFAULT 0,
                        file_count INTEGER NOT NULL DEFAULT 0
                    )
                    """.trimIndent()
                )
                db.execSQL("ALTER TABLE scanned_file ADD COLUMN scan_run_id INTEGER NOT NULL DEFAULT 0")
                // 把历史文件归入“历史文库”，保持可查看
                db.execSQL(
                    "INSERT INTO scan_run (id, name, created_at, file_count) " +
                    "SELECT 1, '历史文库', ${System.currentTimeMillis()}, " +
                    "(SELECT COUNT(*) FROM scanned_file)"
                )
                db.execSQL("UPDATE scanned_file SET scan_run_id = 1 WHERE scan_run_id = 0")
                // 唯一约束升级为 (path, scan_run_id)
                db.execSQL("DROP INDEX IF EXISTS index_scanned_file_path")
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS index_scanned_file_path_run ON scanned_file(path, scan_run_id)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_scanned_file_scan_run_id ON scanned_file(scan_run_id)")
            }
        }

        /**
         * v4 -> v5：scanned_file 新增 progress（更新进度）与 source（来源站点）两列。
         * 仅 ADD COLUMN，SQLite 全版本支持，无 DROP COLUMN 兼容性风险。
         */
        private val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE scanned_file ADD COLUMN progress TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE scanned_file ADD COLUMN source TEXT NOT NULL DEFAULT ''")
            }
        }

        /**
         * v5 -> v6：新增 keyword_replace_rules 表（关键词替换规则，对齐 PC 端）。
         * 仅建表，无破坏性操作，旧数据安全保留。
         */
        private val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS keyword_replace_rules (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        scope TEXT NOT NULL DEFAULT 'scan',
                        pattern TEXT NOT NULL,
                        replacement TEXT NOT NULL DEFAULT '',
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        enabled INTEGER NOT NULL DEFAULT 1,
                        created_at INTEGER NOT NULL DEFAULT 0
                    )
                    """.trimIndent()
                )
            }
        }

        /**
         * v6 -> v7：清理历史版本残留的 content_hash 索引。
         * 旧版 APK 曾给 content_hash 建过索引，当前实体已移除；
         * 升级时不删除会导致 Room schema 校验失败而闪退。其余 schema 不变。
         */
        private val MIGRATION_6_7 = object : Migration(6, 7) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("DROP INDEX IF EXISTS index_scanned_file_content_hash")
            }
        }

        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    DB_NAME
                )
                    .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7)
                    .fallbackToDestructiveMigration()
                    .build()
                    .also {
                        INSTANCE = it
                        LogUtil.i(TAG, "Database initialized")
                    }
            }
        }
    }
}
