package com.filescanner.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import com.filescanner.app.data.database.AppDatabase
import com.filescanner.app.data.repository.FileRepository
import com.filescanner.app.util.LogUtil
import com.filescanner.app.util.PreferencesUtil
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class FileScannerApp : Application() {
    lateinit var database: AppDatabase
        private set
    lateinit var repository: FileRepository
        private set
    lateinit var preferencesUtil: PreferencesUtil
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        LogUtil.init(this)
        LogUtil.i("App", "FileScannerApp onCreate")

        preferencesUtil = PreferencesUtil(this)
        try {
            database = AppDatabase.getInstance(this)
            repository = FileRepository(
                database.scannedFileDao(),
                database.scanRunDao(),
                database.keywordReplaceDao()
            )
            LogUtil.i("App", "Database and repository initialized")
            seedDefaultKeywordRules()
        } catch (e: Exception) {
            LogUtil.e("App", "Failed to init database: ${e.message}")
        }

        createNotificationChannels()
    }

    /**
     * 预埋一批默认规则（去文件名水印），减少用户配置工作量。
     * 逻辑：按 pattern 补齐缺失的预置规则（幂等）——首次为空时整批写入；
     * 后续新增预置项也会自动补进已安装实例，无需清数据。
     * 只动数据库记录，不触碰手机上的源文件。若用户不想要某条，建议在界面“禁用”而非“删除”，
     * 否则下次启动会被重新补齐。
     */
    private fun seedDefaultKeywordRules() {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val added = repository.seedDefaultKeywordRules()
                if (added > 0) {
                    LogUtil.i("App", "Seeded $added missing default keyword-replace rules")
                }
                preferencesUtil.setKeywordSeeded()
            } catch (e: Exception) {
                LogUtil.e("App", "seed default keyword rules failed: ${e.message}")
            }
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                SCAN_CHANNEL_ID,
                getString(R.string.scan_channel_name),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = getString(R.string.scan_channel_desc)
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    companion object {
        const val SCAN_CHANNEL_ID = "scan_service"

        @Volatile
        var instance: FileScannerApp? = null
            private set
    }
}
