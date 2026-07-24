package com.filescanner.app.data.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.filescanner.app.data.database.dao.DupRuleConfigDao
import com.filescanner.app.data.database.dao.ScannedFileDao
import com.filescanner.app.data.database.dao.ScanConfigDao
import com.filescanner.app.data.database.dao.ScanRunDao
import com.filescanner.app.data.database.dao.KeywordReplaceDao
import com.filescanner.app.data.database.entity.DupRuleConfigEntity
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.data.database.entity.ScanConfigEntity
import com.filescanner.app.data.database.entity.ScanRunEntity
import com.filescanner.app.data.database.entity.KeywordReplaceRuleEntity
import com.filescanner.app.util.LogUtil

@Database(
    entities = [
        ScannedFileEntity::class, ScanConfigEntity::class, ScanRunEntity::class,
        KeywordReplaceRuleEntity::class, DupRuleConfigEntity::class
    ],
    version = 12,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun scannedFileDao(): ScannedFileDao
    abstract fun scanConfigDao(): ScanConfigDao
    abstract fun scanRunDao(): ScanRunDao
    abstract fun keywordReplaceDao(): KeywordReplaceDao
    abstract fun dupRuleConfigDao(): DupRuleConfigDao

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

        /**
         * v7 -> v8：scanned_file 新增 checked（是否勾选）列。
         * 仅 ADD COLUMN（NOT NULL DEFAULT 0），SQLite 全版本支持，旧数据安全保留。
         * 勾选状态由“勾选重复”计算或手动勾选写入，供批量删除选中与“已勾选”筛选使用。
         */
        private val MIGRATION_7_8 = object : Migration(7, 8) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE scanned_file ADD COLUMN checked INTEGER NOT NULL DEFAULT 0")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_scanned_file_checked ON scanned_file(checked)")
            }
        }

        /**
         * v8 -> v9：scanned_file 新增 title_pinyin / author_pinyin 列。
         * 拼音格式："全拼|首字母"（如 "dou po cang qiong|dpcq"），
         * 供拼音搜索使用——输入 dpcq 可搜到「斗破苍穹」。
         * 仅 ADD COLUMN（NOT NULL DEFAULT ''），SQLite 全版本支持，旧数据安全保留。
         */
        private val MIGRATION_8_9 = object : Migration(8, 9) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE scanned_file ADD COLUMN title_pinyin TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE scanned_file ADD COLUMN author_pinyin TEXT NOT NULL DEFAULT ''")
            }
        }

        /**
         * v10 -> v11：dup_rule_configs 表增加 is_builtin/conditions/action/sort_order 列。
         * 标记已有内置规则为 is_builtin=1；自定义规则列留空 NULL。
         */
        private val MIGRATION_10_11 = object : Migration(10, 11) {
            override fun migrate(db: SupportSQLiteDatabase) {
                // SQLite ALTER TABLE ADD COLUMN 不支持一次加多列，逐条执行
                try { db.execSQL("ALTER TABLE dup_rule_configs ADD COLUMN is_builtin INTEGER NOT NULL DEFAULT 0") } catch (_: Exception) {}
                try { db.execSQL("ALTER TABLE dup_rule_configs ADD COLUMN conditions TEXT") } catch (_: Exception) {}
                try { db.execSQL("ALTER TABLE dup_rule_configs ADD COLUMN action TEXT") } catch (_: Exception) {}
                try { db.execSQL("ALTER TABLE dup_rule_configs ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0") } catch (_: Exception) {}
                // 标记内置规则
                db.execSQL("UPDATE dup_rule_configs SET is_builtin = 1, sort_order = 0 WHERE rule_key IN ('rule1','rule2','rule3a','rule3b','rule4','rule5')")
            }
        }

        /**
         * v11 -> v12：scanned_file 新增 encoding 字段，保存文件编码。
         */
        private val MIGRATION_11_12 = object : Migration(11, 12) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE scanned_file ADD COLUMN encoding TEXT NOT NULL DEFAULT ''")
            }
        }

        /**
         * v9 -> v10：新增 dup_rule_configs 表（勾选重复规则配置）。
         * 建表 + 写入 6 条默认规则（全部启用），幂等。
         */
        private val MIGRATION_9_10 = object : Migration(9, 10) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS dup_rule_configs (
                        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        rule_key TEXT NOT NULL UNIQUE,
                        rule_name TEXT NOT NULL,
                        enabled INTEGER NOT NULL DEFAULT 1,
                        description TEXT NOT NULL DEFAULT '',
                        created_at INTEGER NOT NULL DEFAULT 0,
                        updated_at INTEGER NOT NULL DEFAULT 0
                    )
                    """.trimIndent()
                )
                val now = System.currentTimeMillis()
                val defaultRules = arrayOf(
                    arrayOf("rule1", "精确重复去重", "1", "小说名+作者+进度+文件大小完全相等的文件，保留最新一个", "$now", "$now"),
                    arrayOf("rule2", "纯数字进度对比", "1", "有纯数字进度的文件中，进度最高的不勾选，其余勾选", "$now", "$now"),
                    arrayOf("rule3a", "含中文进度保护", "1", "含有中文进度（如\"更新至50\"）的文件不勾选", "$now", "$now"),
                    arrayOf("rule3b", "完结特例", "1", "中文进度保护的特例：数字进度文件更小且文件名含\"完结\"时，仍勾选最大进度文件", "$now", "$now"),
                    arrayOf("rule4", "最大文件不勾选", "1", "同一组内文件大小唯一最大的文件不勾选", "$now", "$now"),
                    arrayOf("rule5", "完结+N番外去重", "1", "进度匹配\"完结+数字番外\"的组内，按番外数 N 排序，最大 N 不勾选，其余勾选", "$now", "$now"),
                )
                for (r in defaultRules) {
                    db.execSQL(
                        "INSERT OR IGNORE INTO dup_rule_configs (rule_key, rule_name, enabled, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                        r
                    )
                }
            }
        }

        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    DB_NAME
                )
                    .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9, MIGRATION_9_10, MIGRATION_10_11, MIGRATION_11_12)
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
