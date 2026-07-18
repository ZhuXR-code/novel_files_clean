package com.filescanner.app.ui.screens.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.sp
import android.content.Intent
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.ui.platform.LocalContext
import com.filescanner.app.service.ScanService


import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.filescanner.app.R
import com.filescanner.app.data.model.ScanStateManager
import com.filescanner.app.ui.components.TopBar
import com.filescanner.app.ui.components.AppButton
import com.filescanner.app.ui.components.AppOutlinedButton

@Composable
fun ScanProgressScreen(onBack: () -> Unit, onFinished: () -> Unit) {
    val state by ScanStateManager.state.collectAsStateWithLifecycle()
    val isCollecting = state.isScanning && state.phase == "collecting"
    val context = LocalContext.current
    val lastConfig by ScanStateManager.lastConfig.collectAsStateWithLifecycle()

    Scaffold(
        topBar = { TopBar(title = stringResource(R.string.scanning), onBack = onBack) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (state.finished) {
                // 完成 / 停止 / 未找到文件：展示结果入口
                val summary = when (state.status) {
                    "empty" -> stringResource(R.string.scan_no_files)
                    "stopped" -> stringResource(R.string.scan_stopped, state.scannedFiles)
                    "error" -> "${stringResource(R.string.scan_error)}: ${state.error}"
                    else -> stringResource(R.string.scan_completed, state.totalFiles)
                }
                Text(
                    summary,
                    fontWeight = MaterialTheme.typography.titleMedium.fontWeight,
                    fontSize = MaterialTheme.typography.titleMedium.fontSize
                )
            } else if (isCollecting) {
                // 收集阶段：文件总数未知，用环形进度 + 已收集数量反馈，避免“卡在 0”
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    CircularProgressIndicator()
                    Column {
                        Text(
                            stringResource(R.string.collecting),
                            fontWeight = MaterialTheme.typography.titleMedium.fontWeight,
                            fontSize = MaterialTheme.typography.titleMedium.fontSize
                        )
                        Text(
                            stringResource(R.string.collected_count, state.collectedFiles),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 13.sp
                        )
                    }
                }
            } else {
                LinearProgressIndicator(
                    progress = { (state.progress.coerceIn(0, 100)) / 100f },
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    stringResource(R.string.scanning_progress, state.scannedFiles, state.totalFiles),
                    fontWeight = MaterialTheme.typography.titleMedium.fontWeight,
                    fontSize = MaterialTheme.typography.titleMedium.fontSize
                )
            }

            if (!state.finished) {
                Text(
                    state.currentFile,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Spacer(Modifier.weight(1f))

            // 停止扫描：扫描/收集中均可停止，已扫描结果会保留
            if (state.isScanning) {
                AppOutlinedButton(
                    onClick = { ScanStateManager.requestStop() },
                    modifier = Modifier.fillMaxWidth(),
                    contentColor = MaterialTheme.colorScheme.error
                ) {
                    Text(stringResource(R.string.stop_scan))
                }
                Text(
                    stringResource(R.string.stop_scan_hint),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 12.sp,
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                )
            }

            if (state.finished) {
                // 扫描完成 / 已停止：可“重新扫描”（沿用本次配置）或查看文库结果
                if (lastConfig != null) {
                    AppButton(
                        onClick = {
                            val c = lastConfig!!
                            val intent = Intent(context, ScanService::class.java).apply {
                                action = ScanService.ACTION_START_SCAN
                                putExtra("tree_uri", c.treeUri)
                                putExtra("file_types", c.fileTypes)
                                putExtra("min_size_kb", c.minSizeKb)
                                putExtra("recursive", c.recursive)
                                putExtra("excluded_folders", c.excludedFolders)
                                putExtra("config_name", c.configName)
                                putExtra("folder_name", c.folderName)
                            }
                            context.startForegroundService(intent)
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null)
                        Spacer(Modifier.padding(start = 8.dp))
                        Text(stringResource(R.string.rescan))
                    }
                    Spacer(Modifier.height(8.dp))
                }
                AppButton(
                    onClick = onFinished,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.scan_finished_view))
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center
            ) {
                Text(
                    stringResource(R.string.scan_notification_title),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 12.sp
                )
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}
