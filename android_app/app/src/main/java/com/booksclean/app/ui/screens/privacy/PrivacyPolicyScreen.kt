package com.booksclean.app.ui.screens.privacy

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.booksclean.app.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.charset.Charset

/**
 * 隐私协议展示页。
 * - showActions=true：首次启动弹窗，必须主动选择"同意并继续"或"不同意并退出"，无返回按钮。
 * - showActions=false + onBack：设置页内查看，带返回。
 */
@Composable
fun PrivacyPolicyScreen(
    showActions: Boolean = false,
    onAgree: () -> Unit = {},
    onDisagree: () -> Unit = {},
    onBack: (() -> Unit)? = null
) {
    val context = LocalContext.current
    var content by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        content = withContext(Dispatchers.IO) {
            runCatching {
                context.resources.openRawResource(R.raw.privacy_policy)
                    .bufferedReader(Charset.forName("UTF-8")).use { it.readText() }
            }.getOrDefault("隐私协议加载失败，请重试或联系我们。")
        }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("隐私协议") },
                navigationIcon = {
                    if (onBack != null) {
                        TextButton(onClick = onBack) { Text("返回") }
                    }
                }
            )
        },
        bottomBar = {
            if (showActions) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    OutlinedButton(
                        onClick = onDisagree,
                        modifier = Modifier.weight(1f)
                    ) { Text("不同意并退出") }
                    Button(
                        onClick = onAgree,
                        modifier = Modifier.weight(1f)
                    ) { Text("同意并继续") }
                }
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier.fillMaxSize()
                .padding(padding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState())
        ) {
            Text(text = content, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
