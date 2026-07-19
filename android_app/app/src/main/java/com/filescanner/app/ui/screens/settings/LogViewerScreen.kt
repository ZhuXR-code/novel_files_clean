package com.filescanner.app.ui.screens.settings

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.filescanner.app.R
import com.filescanner.app.ui.components.AppButton
import com.filescanner.app.ui.components.TopBar
import com.filescanner.app.util.LogUtil

@Composable
fun LogViewerScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    var logText by remember { mutableStateOf(LogUtil.getLogText()) }
    var toast by remember { mutableStateOf<String?>(null) }

    // 简单 toast（复用系统 Toast）
    toast?.let {
        android.widget.Toast.makeText(context, it, android.widget.Toast.LENGTH_SHORT).show()
        toast = null
    }

    Scaffold(
        topBar = {
            TopBar(
                title = stringResource(R.string.log_viewer_title),
                onBack = onBack,
                actions = {
                    Row(horizontalArrangement = Arrangement.End) {
                        Text(
                            stringResource(R.string.log_refresh),
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .padding(horizontal = 10.dp, vertical = 8.dp)
                                .clickable { logText = LogUtil.getLogText() }
                        )
                        Text(
                            stringResource(R.string.log_clear),
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .padding(horizontal = 10.dp, vertical = 8.dp)
                                .clickable {
                                    LogUtil.clearFile(context)
                                    logText = ""
                                    toast = context.getString(R.string.log_cleared)
                                }
                        )
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.End
            ) {
                AppButton(onClick = {
                    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("debug_log", logText))
                    toast = context.getString(R.string.log_copied)
                }) {
                    Text(stringResource(R.string.log_copy_all))
                }
            }
            SelectionContainer(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 12.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    text = if (logText.isBlank()) stringResource(R.string.log_empty) else logText,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    lineHeight = 16.sp
                )
            }
        }
    }
}
