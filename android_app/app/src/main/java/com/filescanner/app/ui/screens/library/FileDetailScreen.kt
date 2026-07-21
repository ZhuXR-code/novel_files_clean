package com.filescanner.app.ui.screens.library

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.core.content.FileProvider
import com.filescanner.app.util.FileUtil
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.filescanner.app.R
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.ui.components.TopBar
import com.filescanner.app.ui.components.AppButton
import com.filescanner.app.ui.components.AppOutlinedButton
import com.filescanner.app.service.DeleteService
import com.filescanner.app.util.FormatUtil
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 单文件明细页：展示该书/文件解析出的全部字段，并提供“打开文件”按钮，
 * 用系统查看器打开（SAF 的 content Uri 直接 ACTION_VIEW）。
 */
@Composable
fun FileDetailScreen(
    fileId: Long,
    onBack: () -> Unit,
    viewModel: LibraryViewModel = viewModel()
) {
    val context = LocalContext.current
    var file by remember { mutableStateOf<ScannedFileEntity?>(null) }
    val toast by viewModel.toast.collectAsStateWithLifecycle()
    // 详情页删除：对话框可见性 + 删除方式（false=仅删记录，true=记录+源文件）
    var showDeleteDialog by remember { mutableStateOf(false) }
    var deleteSourceChoice by remember { mutableStateOf(false) }
    // 二次确认对话框：防止误删
    var showConfirmDialog by remember { mutableStateOf(false) }

    LaunchedEffect(fileId) {
        file = withContext(Dispatchers.IO) { viewModel.getById(fileId) }
    }

    Scaffold(
        topBar = {
            TopBar(
                title = stringResource(R.string.file_detail_title),
                onBack = onBack,
                actions = {
                    file?.let { f ->
                        IconButton(onClick = { viewModel.toggleMark(f.id, f.marked) }) {
                            Icon(
                                if (f.marked == 1) Icons.Filled.Star else Icons.Filled.StarBorder,
                                contentDescription = stringResource(
                                    if (f.marked == 1) R.string.unmark else R.string.mark
                                ),
                                tint = if (f.marked == 1) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        // 详情页删除入口
                        IconButton(onClick = { showDeleteDialog = true }) {
                            Icon(
                                Icons.Filled.Delete,
                                contentDescription = stringResource(R.string.delete_text),
                                tint = MaterialTheme.colorScheme.error
                            )
                        }
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            file?.let { f ->
                DetailRow(stringResource(R.string.detail_title), f.title.ifBlank { "—" })
                DetailRow(stringResource(R.string.detail_author), f.author.ifBlank { "—" })
                DetailRow(stringResource(R.string.detail_progress), f.progress.ifBlank { "—" })
                DetailRow(stringResource(R.string.detail_source), f.source.ifBlank { "—" })
                DetailRow(stringResource(R.string.detail_original_name), f.fileName.ifBlank { "—" })
                DetailRow(stringResource(R.string.detail_ext), f.ext.ifBlank { "—" })
                DetailRow(stringResource(R.string.detail_size), FormatUtil.formatSize(f.fileSize))
                DetailRow(stringResource(R.string.detail_marked), if (f.marked == 1) stringResource(R.string.mark) else stringResource(R.string.unmark))
                DetailRow(stringResource(R.string.detail_checked), if (f.checked == 1) stringResource(R.string.state_checked) else stringResource(R.string.state_unchecked))
                DetailRow(stringResource(R.string.detail_content_hash), f.contentHash.ifBlank { "—" })
                DetailRow(stringResource(R.string.detail_path), FormatUtil.toHumanReadablePath(f.path), isPath = true)

                Spacer(Modifier.height(20.dp))
                AppButton(
                    onClick = { openFileWithViewer(context, f.path) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(Icons.Filled.OpenInNew, contentDescription = null)
                    Spacer(Modifier.size(8.dp))
                    Text(stringResource(R.string.open_file))
                }
                Spacer(Modifier.height(12.dp))
                // 删除该文件（提供“仅删除记录 / 删除记录和源文件”两种选择）
                AppButton(
                    onClick = { showDeleteDialog = true },
                    modifier = Modifier.fillMaxWidth(),
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError
                ) {
                    Icon(Icons.Filled.Delete, contentDescription = null)
                    Spacer(Modifier.size(8.dp))
                    Text(stringResource(R.string.delete_text))
                }
            } ?: run {
                Text(
                    stringResource(R.string.file_not_found),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }

    // 删除确认对话框：复用 DeleteService，支持“仅删除记录”与“删除记录和源文件”两种选择
    if (showDeleteDialog && file != null) {
        val target = file!!
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text(stringResource(R.string.delete_confirm_title)) },
            text = {
                Column {
                    Text(
                        stringResource(R.string.detail_delete_hint),
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(8.dp))
                    // 选项一：仅删除记录
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { deleteSourceChoice = false }
                            .padding(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(selected = !deleteSourceChoice, onClick = { deleteSourceChoice = false })
                        Column(modifier = Modifier.padding(start = 8.dp)) {
                            Text(stringResource(R.string.delete_record_only))
                            Text(
                                stringResource(R.string.delete_record_only_hint),
                                fontSize = 11.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    // 选项二：删除记录和源文件
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { deleteSourceChoice = true }
                            .padding(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(selected = deleteSourceChoice, onClick = { deleteSourceChoice = true })
                        Column(modifier = Modifier.padding(start = 8.dp)) {
                            Text(stringResource(R.string.delete_record_file))
                            Text(
                                stringResource(R.string.delete_record_file_hint),
                                fontSize = 11.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            },
            confirmButton = {
                AppButton(
                    onClick = {
                        showDeleteDialog = false
                        showConfirmDialog = true
                    },
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError
                ) { Text(stringResource(R.string.delete_next_step)) }
            },
            dismissButton = {
                AppOutlinedButton(onClick = { showDeleteDialog = false }) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }

    // 二次确认：防止误删（尤其“删除记录和源文件”不可恢复）
    if (showConfirmDialog && file != null) {
        val target = file!!
        val willDeleteSource = deleteSourceChoice
        AlertDialog(
            onDismissRequest = { showConfirmDialog = false },
            title = { Text(stringResource(R.string.delete_confirm_title)) },
            text = {
                Text(
                    if (willDeleteSource) stringResource(R.string.detail_delete_confirm_source)
                    else stringResource(R.string.detail_delete_confirm_record),
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            },
            confirmButton = {
                AppButton(
                    onClick = {
                        showConfirmDialog = false
                        val intent = Intent(context, DeleteService::class.java).apply {
                            action = DeleteService.ACTION_START_DELETE
                            putExtra("ids", longArrayOf(target.id))
                            putExtra("deleteSource", willDeleteSource)
                        }
                        context.startForegroundService(intent)
                        onBack()
                    },
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError
                ) { Text(stringResource(R.string.delete_text)) }
            },
            dismissButton = {
                AppOutlinedButton(onClick = { showConfirmDialog = false }) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }
}

@Composable
private fun DetailRow(label: String, value: String, isPath: Boolean = false) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp)
    ) {
        Text(
            label,
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(2.dp))
        Text(
            value,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            maxLines = if (isPath) 3 else 1,
            overflow = if (isPath) TextOverflow.Clip else TextOverflow.Ellipsis
        )
        Spacer(Modifier.height(4.dp))
        androidx.compose.material3.HorizontalDivider(
            color = MaterialTheme.colorScheme.outlineVariant
        )
    }
}

/**
 * 用系统查看器打开指定文件。
 * - 路径为 SAF content:// URI 时直接用作 ACTION_VIEW 的 data；
 * - 路径为本地文件路径（file:// 或绝对路径）时通过 FileProvider 暴露为 content URI，
 *   避免 Android 7+ 的 FileUriExposedException。
 * 关键：必须按扩展名给出正确 MIME（如 txt -> text/plain），否则系统会把
 * 请求派发给文件管理器并打开“所在文件夹”而非文件本身。
 */
private fun openFileWithViewer(context: android.content.Context, path: String) {
    try {
        val uri = Uri.parse(path)
        val isContentUri = uri.scheme == "content"
        val name = FileUtil.getFileName(context, uri)
        val ext = FileUtil.getFileExtension(name)
        val mimeType = when (ext) {
            "txt" -> "text/plain"
            "epub" -> "application/epub+zip"
            "pdf" -> "application/pdf"
            "mobi" -> "application/x-mobipocket-ebook"
            "json" -> "application/json"
            "csv" -> "text/csv"
            else -> context.contentResolver.getType(uri) ?: "*/*"
        }
        val viewUri = if (isContentUri) {
            uri
        } else {
            FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                java.io.File(path)
            )
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(viewUri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val chooser = Intent.createChooser(intent, context.getString(R.string.choose_viewer))
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent.resolveActivity(context.packageManager) != null) {
            context.startActivity(chooser)
        } else {
            Toast.makeText(context, context.getString(R.string.no_viewer_found), Toast.LENGTH_SHORT).show()
        }
    } catch (e: Exception) {
        Toast.makeText(
            context,
            context.getString(R.string.open_file_failed, e.message ?: ""),
            Toast.LENGTH_LONG
        ).show()
    }
}
