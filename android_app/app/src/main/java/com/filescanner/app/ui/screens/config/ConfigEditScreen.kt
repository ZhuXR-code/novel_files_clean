package com.filescanner.app.ui.screens.config

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.unit.sp

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
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
import androidx.compose.ui.unit.dp
import androidx.documentfile.provider.DocumentFile
import androidx.lifecycle.viewmodel.compose.viewModel
import com.filescanner.app.FileScannerApp
import com.filescanner.app.R
import com.filescanner.app.data.database.entity.ScanConfigEntity
import com.filescanner.app.ui.components.TopBar
import com.filescanner.app.ui.components.AppButton
import com.filescanner.app.util.FileUtil
import kotlinx.coroutines.flow.first

private val BUILTIN_TYPES = listOf("txt", "md", "pdf", "epub", "doc", "docx")

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ConfigEditScreen(
    configId: Long,
    onBack: () -> Unit,
    viewModel: ScanConfigViewModel = viewModel()
) {
    val context = LocalContext.current
    val app = FileScannerApp.instance
    val prefs = app?.preferencesUtil

    var name by remember { mutableStateOf("") }
    var folderUri by remember { mutableStateOf("") }
    var folderName by remember { mutableStateOf("") }
    var selectedTypes by remember { mutableStateOf(setOf("txt")) }
    var customType by remember { mutableStateOf("") }
    var excludedFolders by remember { mutableStateOf("") }
    var minSize by remember { mutableStateOf("0") }
    var recursive by remember { mutableStateOf(true) }

    // 编辑已有配置：按 id 载入并反显
    LaunchedEffect(configId) {
        if (configId > 0) {
            viewModel.getById(configId)?.let { cfg ->
                name = cfg.name
                folderUri = cfg.folderUri
                folderName = cfg.folderName
                selectedTypes = cfg.fileTypes.split(",").map { it.trim() }
                    .filter { it.isNotEmpty() }.toSet()
                excludedFolders = cfg.excludedFolders
                minSize = cfg.minSizeKb.toString()
                recursive = cfg.recursive
            }
        } else {
            // 新建：用全局默认设置预填（来自设置页）
            prefs?.let {
                selectedTypes = it.scanFileTypes.first().split(",").map { t -> t.trim() }
                    .filter { t -> t.isNotEmpty() }.toSet().ifEmpty { setOf("txt") }
                minSize = it.minFileSizeKb.first().toString()
                recursive = it.recursive.first()
            }
        }
    }

    // 选择文件夹：点按打开系统选择器，选完后返回本页并反显路径
    val treeLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        try {
            context.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: Exception) {
        }
        folderUri = uri.toString()
        // 反显为可阅读路径，例如 “内部存储/DCIM/Camera”
        folderName = FileUtil.getReadableTreePath(uri)
    }

    Scaffold(
        topBar = {
            TopBar(
                title = stringResource(if (configId > 0) R.string.edit_config else R.string.add_config),
                onBack = onBack
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // 配置名称
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.config_name)) },
                placeholder = { Text(stringResource(R.string.config_name_hint)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            // 扫描文件夹路径：点按调用系统选择文件夹
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.medium
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(
                        stringResource(R.string.scan_folder_path),
                        fontWeight = MaterialTheme.typography.titleSmall.fontWeight
                    )
                    Text(
                        if (folderName.isNotBlank()) folderName else stringResource(R.string.folder_not_selected),
                        color = if (folderName.isNotBlank()) MaterialTheme.colorScheme.onSurface
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 13.sp,
                        maxLines = 2,
                        modifier = Modifier.padding(top = 4.dp, bottom = 8.dp)
                    )
                    AppButton(onClick = { treeLauncher.launch(null) }) {
                        Icon(Icons.Filled.FolderOpen, contentDescription = null)
                        Text(
                            stringResource(if (folderUri.isBlank()) R.string.select_folder_btn else R.string.change_folder_btn),
                            modifier = Modifier.padding(start = 8.dp)
                        )
                    }
                }
            }

            // 文件类型（参考 PC 版 cfgModal 的 fileTypesGroup）
            Card(modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(
                        stringResource(R.string.file_types),
                        fontWeight = MaterialTheme.typography.titleSmall.fontWeight
                    )
                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        BUILTIN_TYPES.forEach { t ->
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.padding(end = 4.dp)
                            ) {
                                Checkbox(
                                    checked = t in selectedTypes,
                                    onCheckedChange = {
                                        selectedTypes = if (it) selectedTypes + t else selectedTypes - t
                                    }
                                )
                                Text(t, fontSize = 13.sp)
                            }
                        }
                    }
                    OutlinedTextField(
                        value = customType,
                        onValueChange = { customType = it },
                        label = { Text(stringResource(R.string.custom_file_type)) },
                        placeholder = { Text("如 csv") },
                        singleLine = true,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp)
                    )
                }
            }

            // 排除的文件夹
            OutlinedTextField(
                value = excludedFolders,
                onValueChange = { excludedFolders = it },
                label = { Text(stringResource(R.string.excluded_folders)) },
                placeholder = { Text(stringResource(R.string.excluded_folders_hint)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            // 最小体积
            OutlinedTextField(
                value = minSize,
                onValueChange = { minSize = it.filter { c -> c.isDigit() } },
                label = { Text(stringResource(R.string.min_size)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            // 递归
            Card(modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(stringResource(R.string.recursive))
                    Switch(checked = recursive, onCheckedChange = { recursive = it })
                }
            }

            AppButton(
                onClick = {
                    if (folderUri.isBlank()) return@AppButton
                    val allTypes = (selectedTypes + customType.split(",").map { it.trim() }
                        .filter { it.isNotEmpty() }).filter { it.isNotEmpty() }
                    val typesStr = if (allTypes.isEmpty()) "txt" else allTypes.joinToString(",")
                    val cfg = ScanConfigEntity(
                        id = if (configId > 0) configId else 0,
                        name = name.trim(),
                        folderUri = folderUri,
                        folderName = folderName,
                        fileTypes = typesStr,
                        minSizeKb = minSize.toIntOrNull() ?: 0,
                        recursive = recursive,
                        exactHash = false,
                        excludedFolders = excludedFolders.trim()
                    )
                    viewModel.upsert(cfg) { onBack() }
                },
                enabled = folderUri.isNotBlank(),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.save_config))
            }
        }
    }
}
