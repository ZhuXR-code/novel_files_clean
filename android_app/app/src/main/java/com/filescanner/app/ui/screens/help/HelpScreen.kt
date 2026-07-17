package com.filescanner.app.ui.screens.help

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.sp

import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.filescanner.app.R
import com.filescanner.app.ui.components.TopBar

@Composable
fun HelpScreen(onBack: () -> Unit) {
    val items = listOf(
        "1. 开始扫描" to "在首页点击「开始扫描」，选择包含 txt/md 文件的文件夹。应用会递归读取文件、解析书名与作者、并计算内容指纹（SHA-256）用于识别重复。",
        "2. 查看文库" to "扫描完成后进入文库，可按「全部 / 已标记」筛选，按时间、名称、大小排序，并支持搜索；合集模式下按书名聚合查看重复。列表过长时，屏幕右下角会出现「回到顶层 / 回到底层」悬浮按钮，快速跳转。",
        "3. 标记重复" to "合集模式下点击右上角菜单「标记重复」：按 PC 端逻辑（同作者 + 纯数字进度，保留最大进度与最大文件）智能勾选待删的重复项；也可「按书名/作者相同标记」给文件加星标、「清除标记」取消。",
        "4. 选择并删除" to "勾选要删除的文件（合集模式下「标记重复」会自动勾选重复项），底部出现「删除选中」按钮，确认后由前台服务逐个删除并实时显示结果。",
        "5. 删除安全" to "删除通过系统 SAF 授权进行，删除前可在确认页取消勾选。删除后文件进入回收站（部分系统）或直接移除，请谨慎操作。",
        "6. 设置" to "可调整主题、配置关键词替换规则（文件名数据清洗）；支持导出已标记清单与清空本地数据。",
        "7. 权限说明" to "使用「文档树」授权访问所选择的文件夹，不会读取其他目录，也不会上传任何文件。"
    )

    Scaffold(
        topBar = { TopBar(title = stringResource(R.string.help), onBack = onBack) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            items.forEach { (title, body) ->
                Text(
                    title,
                    fontWeight = MaterialTheme.typography.titleSmall.fontWeight,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 12.dp, bottom = 4.dp)
                )
                Text(
                    body,
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    lineHeight = 20.sp
                )
            }
        }
    }
}
