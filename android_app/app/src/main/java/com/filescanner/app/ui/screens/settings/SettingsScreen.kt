package com.filescanner.app.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.sp

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.filescanner.app.R
import com.filescanner.app.ui.components.CardItem
import com.filescanner.app.ui.components.ConfirmDialog
import com.filescanner.app.ui.components.TopBar
import com.filescanner.app.ui.components.AppButton
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onNavigateToKeywordReplace: () -> Unit = {},
    viewModel: SettingsViewModel = viewModel()
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    val themeMode by viewModel.themeMode.collectAsStateWithLifecycle()
    val fontScaleMode by viewModel.fontScaleMode.collectAsStateWithLifecycle()

    var showClear by remember { mutableStateOf(false) }


    Scaffold(
        topBar = { TopBar(title = stringResource(R.string.settings), onBack = onBack) },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // 主题
            CardItem {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(stringResource(R.string.theme), fontWeight = MaterialTheme.typography.titleSmall.fontWeight)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = themeMode == "system", onClick = { viewModel.setTheme("system") })
                        Text(stringResource(R.string.theme_system))
                        RadioButton(selected = themeMode == "light", onClick = { viewModel.setTheme("light") })
                        Text(stringResource(R.string.theme_light))
                        RadioButton(selected = themeMode == "dark", onClick = { viewModel.setTheme("dark") })
                        Text(stringResource(R.string.theme_dark))
                    }
                }
            }

            // 全局字号
            CardItem {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(stringResource(R.string.font_size), fontWeight = MaterialTheme.typography.titleSmall.fontWeight)
                    Text(
                        stringResource(R.string.font_size_desc),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 2.dp, bottom = 4.dp)
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = fontScaleMode == "small", onClick = { viewModel.setFontScale("small") })
                        Text(stringResource(R.string.font_small))
                        RadioButton(selected = fontScaleMode == "standard", onClick = { viewModel.setFontScale("standard") })
                        Text(stringResource(R.string.font_standard))
                        RadioButton(selected = fontScaleMode == "large", onClick = { viewModel.setFontScale("large") })
                        Text(stringResource(R.string.font_large))
                    }
                }
            }


            // 关键词替换（文件名数据清洗）
            CardItem(onClick = onNavigateToKeywordReplace) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            stringResource(R.string.keyword_replace),
                            fontWeight = MaterialTheme.typography.titleSmall.fontWeight,
                            fontSize = MaterialTheme.typography.titleSmall.fontSize
                        )
                        Text(
                            stringResource(R.string.keyword_replace_desc),
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 2.dp)
                        )
                    }
                }
            }

            AppButton(
                onClick = {
                    scope.launch {
                        val path = viewModel.exportMarked(context)
                        if (path != null) {
                            snackbarHostState.showSnackbar(context.getString(R.string.export_success, path))
                        } else {
                            snackbarHostState.showSnackbar(context.getString(R.string.export_failed, "空或失败"))
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.export_marked))
            }

            AppButton(
                onClick = { showClear = true },
                modifier = Modifier.fillMaxWidth(),
                containerColor = MaterialTheme.colorScheme.error,
                contentColor = MaterialTheme.colorScheme.onError
            ) {
                Text(stringResource(R.string.clear_data))
            }

            CardItem {
                Text(
                    stringResource(R.string.about_text),
                    modifier = Modifier.padding(12.dp),
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }

    if (showClear) {
        ConfirmDialog(
            title = stringResource(R.string.clear_data),
            message = stringResource(R.string.clear_data_confirm),
            onConfirm = {
                showClear = false
                viewModel.clearData {
                    scope.launch { snackbarHostState.showSnackbar(context.getString(R.string.cleared)) }
                }
            },
            onDismiss = { showClear = false }
        )
    }
}
