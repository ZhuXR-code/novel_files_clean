package com.filescanner.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import com.filescanner.app.data.database.AppDatabase
import com.filescanner.app.data.repository.FileRepository
import com.filescanner.app.util.LogUtil
import com.filescanner.app.util.PreferencesUtil

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
        } catch (e: Exception) {
            LogUtil.e("App", "Failed to init database: ${e.message}")
        }

        createNotificationChannels()
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
