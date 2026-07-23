package com.filescanner.app.ui.screens.cleanup

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.BackHandler
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.Icon
import androidx.compose.material3.Checkbox
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.graphics.Color
import androidx.documentfile.provider.DocumentFile
import androidx.lifecycle.viewmodel.compose.viewModel
import com.filescanner.app.R
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.util.FormatUtil
import com.filescanner.app.data.model.DeleteState
import com.filescanner.app.data.model.ScanState
import com.filescanner.app.ui.components.AppButton
import com.filescanner.app.ui.components.AppOutlinedButton
import com.filescanner.app.ui.components.CardItem
import com.filescanner.app.ui.components.TopBar

@Composable
fun OneClickCleanupScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val vm: OneClickCleanupViewModel = viewModel()
    val phase by vm.phase.collectAsState()
    val scanState by vm.scanState.collectAsState()
    // 返回处理：清单页(review)的返回应回到确认页(confirm)，而非直接退出到首页
    val handleBack: () -> Unit = { if (phase == "review") vm.backToConfirm() else onBack() }
    BackHandler(enabled = phase == "review") { vm.backToConfirm() }
    val deleteState by vm.deleteState.collectAsState()
    val folderName by vm.folderName.collectAsState()
    val scanned by vm.scanned.collectAsState()
    val dupCount by vm.duplicateCount.collectAsState()
    val selectedIds by vm.selectedIds.collectAsState()
    val reviewItems by vm.reviewItems.collectAsState()
    val selectedCount = selectedIds.size
    val errorMsg by vm.error.collectAsState()

    var selectedUri by remember { mutableStateOf<Uri?>(null) }
    var selFolderName by remember { mutableStateOf("") }
    var types by remember { mutableStateOf("txt") }

    val treeLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        uri?.let {
            selectedUri = it
            selFolderName = try {
                DocumentFile.fromTreeUri(context, it)?.name
                    ?: it.lastPathSegment ?: ""
            } catch (_: Exception) {
                it.lastPathSegment ?: ""
            }
        }
    }

    // 扫描完成 -> 计算重复文件
    LaunchedEffect(scanState.finished, phase) {
        if (scanState.finished && phase == "scanning") {
            vm.onScanFinished()
        }
    }
    // 删除完成 -> 结束
    LaunchedEffect(deleteState.finished, phase) {
        if (deleteState.finished && phase == "deleting") {
            vm.onDeleteFinished()
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        TopBar(title = stringResource(R.string.one_click_title), onBack = handleBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            when (phase) {
                "idle" -> {
                    Text(
                        text = stringResource(R.string.one_click_subtitle),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 13.sp
                    )
                    CardItem {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            AppOutlinedButton(
                                onClick = { treeLauncher.launch(null) }
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    androidx.compose.material3.Icon(
                                        Icons.Filled.Folder,
                                        contentDescription = null
                                    )
                                    Text(
                                        text = if (selectedUri == null)
                                            stringResource(R.string.one_click_select_folder)
                                        else stringResource(
                                            R.string.one_click_folder_selected,
                                            selFolderName
                                        ),
                                        modifier = Modifier.padding(start = 6.dp)
                                    )
                                }
                            }
                            OutlinedTextField(
                                value = types,
                                onValueChange = { types = it },
                                label = {
                                    Text(stringResource(R.string.one_click_file_types))
                                },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                            AppButton(
                                onClick = {
                                    selectedUri?.let { uri ->
                                        vm.startCleanup(
                                            context,
                                            uri,
                                            selFolderName,
                                            types
                                        )
                                    }
                                },
                                enabled = selectedUri != null,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    androidx.compose.material3.Icon(
                                        Icons.Filled.Delete,
                                        contentDescription = null
                                    )
                                    Text(
                                        text = stringResource(R.string.one_click_start),
                                        modifier = Modifier.padding(start = 6.dp)
                                    )
                                }
                            }
                        }
                    }
                }

                "scanning" -> ScanningContent(scanState)
                "marking" -> StageText(stringResource(R.string.one_click_marking))
                "confirm" -> ConfirmContent(vm, selectedCount)
                "review" -> ReviewContent(vm, reviewItems)
                "deleting" -> DeletingContent(deleteState)
                "done" -> DoneContent(vm, scanned, dupCount, deleteState, onBack)
                "error" -> ErrorContent(errorMsg, onBack)
            }
        }
    }
}

@Composable
private fun ScanningContent(s: ScanState) {
    val progress = if (s.totalFiles > 0) s.progress else s.collectedFiles
    val total = if (s.totalFiles > s.collectedFiles) s.totalFiles else s.collectedFiles
    val ratio = if (total > 0) progress.toFloat() / total else 0f
    CardItem {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = if (s.phase == "collecting")
                    stringResource(R.string.one_click_collecting)
                else stringResource(R.string.one_click_scanning),
                fontWeight = FontWeight.Bold
            )
            LinearProgressIndicator(
                progress = { ratio },
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                text = "$progress / $total",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp
            )
            if (s.currentFile.isNotBlank()) {
                Text(
                    text = s.currentFile.substringAfterLast('/').substringAfterLast('\\'),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 12.sp
                )
            }
        }
    }
}

@Composable
private fun DeletingContent(d: DeleteState) {
    val total = if (d.total > d.done) d.total else d.done
    val ratio = if (total > 0) d.done.toFloat() / total else 0f
    CardItem {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.one_click_deleting),
                fontWeight = FontWeight.Bold
            )
            LinearProgressIndicator(
                progress = { ratio },
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                text = "${d.done} / ${d.total}",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp
            )
            Text(
                text = stringResource(R.string.one_click_success, d.success) +
                    "　" + stringResource(R.string.one_click_failed, d.failed),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp
            )
        }
    }
}

@Composable
private fun ConfirmContent(
    vm: OneClickCleanupViewModel,
    selectedCount: Int
) {
    CardItem {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(R.string.one_click_confirm_title),
                fontWeight = FontWeight.Bold
            )
            Text(
                text = stringResource(R.string.one_click_confirm_desc, selectedCount),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp
            )
            Text(
                text = stringResource(R.string.one_click_confirm_warn),
                color = MaterialTheme.colorScheme.error,
                fontSize = 13.sp
            )
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                AppOutlinedButton(
                    onClick = { vm.openReview() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.one_click_view_list))
                }
                AppButton(
                    onClick = { vm.confirmDelete() },
                    modifier = Modifier.fillMaxWidth(),
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError
                ) {
                    Text(stringResource(R.string.one_click_confirm_delete))
                }
            }
        }
    }
}

@Composable
private fun ReviewContent(
    vm: OneClickCleanupViewModel,
    items: List<ScannedFileEntity>
) {
    val draftIds by vm.draftIds.collectAsState()
    CardItem {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(R.string.one_click_review_title),
                fontWeight = FontWeight.Bold
            )
            Text(
                text = stringResource(R.string.one_click_review_hint),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                AppOutlinedButton(
                    onClick = { vm.updateDraft(items.map { it.id }.toSet()) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.one_click_select_all))
                }
                AppOutlinedButton(
                    onClick = { vm.updateDraft(emptySet()) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.one_click_select_none))
                }
            }
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 320.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(items, key = { it.id }) { f ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { vm.toggleDraft(f.id) }
                            .padding(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(
                            checked = f.id in draftIds,
                            onCheckedChange = { on ->
                                vm.updateDraft(if (on) draftIds + f.id else draftIds - f.id)
                            }
                        )
                        Column(modifier = Modifier.padding(start = 8.dp)) {
                            Text(
                                text = f.fileName,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium
                            )
                            Text(
                                text = "${f.title}　${f.author}　${FormatUtil.formatSize(f.fileSize)}",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 12.sp
                            )
                        }
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                AppOutlinedButton(
                    onClick = { vm.backToConfirm() },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.one_click_review_back))
                }
                AppButton(
                    onClick = { vm.saveReview() },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.one_click_review_save, draftIds.size))
                }
            }
        }
    }
}

@Composable
private fun DoneContent(
    vm: OneClickCleanupViewModel,
    scanned: Int,
    dupCount: Int,
    d: DeleteState,
    onBack: () -> Unit
) {
    CardItem {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.one_click_done_title),
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp
            )
            Text(
                text = stringResource(R.string.one_click_done_desc, scanned, dupCount),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp
            )
            if (dupCount > 0) {
                Text(
                    text = stringResource(R.string.one_click_success, d.success) +
                        "　" + stringResource(R.string.one_click_failed, d.failed),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 13.sp
                )
            } else {
                Text(
                    text = stringResource(R.string.one_click_no_dup),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 13.sp
                )
            }
            AppButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.one_click_back_home))
            }
        }
    }
}

@Composable
private fun ErrorContent(errorMsg: String, onBack: () -> Unit) {
    CardItem {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.error),
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.error
            )
            Text(
                text = errorMsg,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 13.sp
            )
            AppButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.one_click_back_home))
            }
        }
    }
}

@Composable
private fun StageText(text: String) {
    CardItem {
        Text(
            text = text,
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            fontWeight = FontWeight.Bold
        )
    }
}
