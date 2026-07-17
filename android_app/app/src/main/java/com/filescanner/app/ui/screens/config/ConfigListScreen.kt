package com.filescanner.app.ui.screens.config

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import com.filescanner.app.data.database.entity.ScanConfigEntity
import com.filescanner.app.service.ScanService
import com.filescanner.app.ui.components.CardItem
import com.filescanner.app.ui.components.ConfirmDialog
import com.filescanner.app.ui.components.TopBar

@Composable
fun ConfigListScreen(
    onBack: () -> Unit,
    onNavigateToEdit: (Long) -> Unit,
    onStartScan: (ScanConfigEntity) -> Unit,
    viewModel: ScanConfigViewModel = viewModel()
) {
    val configs by viewModel.configs.collectAsStateWithLifecycle()
    var toDelete by remember { mutableStateOf<ScanConfigEntity?>(null) }

    Scaffold(
        topBar = { TopBar(title = stringResource(R.string.config_title), onBack = onBack) },
        floatingActionButton = {
            FloatingActionButton(onClick = { onNavigateToEdit(-1) }) {
                Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_config))
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
        ) {
            if (configs.isEmpty()) {
                CardItem(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        stringResource(R.string.config_list_empty),
                        modifier = Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 13.sp
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(configs, key = { it.id }) { cfg ->
                        ConfigCard(
                            config = cfg,
                            onStart = { onStartScan(cfg) },
                            onEdit = { onNavigateToEdit(cfg.id) },
                            onDelete = { toDelete = cfg }
                        )
                    }
                }
            }
        }
    }

    if (toDelete != null) {
        ConfirmDialog(
            title = stringResource(R.string.delete_config),
            message = stringResource(R.string.delete_config_confirm),
            confirmText = stringResource(R.string.delete_config),
            onConfirm = {
                viewModel.delete(toDelete!!.id)
                toDelete = null
            },
            onDismiss = { toDelete = null }
        )
    }
}

@Composable
private fun ConfigCard(
    config: ScanConfigEntity,
    onStart: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    CardItem(onClick = onStart) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        config.name.ifBlank { config.folderName.ifBlank { stringResource(R.string.unnamed_config) } },
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        config.folderName.ifBlank { config.folderUri },
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 12.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 2.dp)
                    )
                }
                IconButton(onClick = onEdit) {
                    Icon(Icons.Filled.Edit, contentDescription = stringResource(R.string.edit_config))
                }
                IconButton(onClick = onDelete) {
                    Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.delete_config))
                }
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    config.fileTypes.ifBlank { "txt" },
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.primary
                )
                if (!config.recursive) {
                    Text("· " + stringResource(R.string.not_recursive), fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (config.excludedFolders.isNotBlank()) {
                    Text("· " + stringResource(R.string.has_excluded), fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            // 整卡可点击“开始扫描”，额外给一个明确的入口
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 10.dp),
                horizontalArrangement = Arrangement.End
            ) {
                androidx.compose.material3.TextButton(onClick = onStart) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null)
                    Text(stringResource(R.string.start_scan), modifier = Modifier.padding(start = 4.dp))
                }
            }
        }
    }
}
