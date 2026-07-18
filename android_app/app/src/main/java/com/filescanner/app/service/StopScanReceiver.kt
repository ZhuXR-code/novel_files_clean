package com.filescanner.app.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.filescanner.app.data.model.ScanStateManager

/**
 * 通知栏“停止扫描”按钮的广播接收器。
 * 点击通知栏按钮不再用 startService(STOP)（Android 8+ 后台限制常使其失效），
 * 改为发送广播直接置位进程内停止标志，由扫描协程检测后退出，保证停止可靠。
 */
class StopScanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        ScanStateManager.requestStop()
    }
}
