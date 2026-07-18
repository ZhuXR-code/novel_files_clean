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
        "1. 开始扫描" to "在首页点击「开始扫描」，进入“扫描配置”列表：可新增配置（选择文件夹、文件类型、是否递归、排除文件夹），或从已有配置直接开始。应用会递归读取文件、解析书名与作者、并计算内容指纹（SHA-256）用于识别重复。扫描结果保存在本机，不会上传。",
        "2. 查看文库与筛选" to "扫描完成后进入文库，会按“每次扫描”分出多个文库。在文库内可按「全部 / 已标记」筛选，按时间、名称、大小排序，并支持搜索。列表/合集两种视图通过顶部分段开关切换。",
        "3. 分页浏览大库" to "面对几万、十几万条数据，底部「分页导航条」帮助你逐页浏览：①“每页”输入框填每页条数（默认 100，范围 10~2000），点「应用」生效；②“跳到”输入框填目标页码，点「跳转」直达该页；③「首页 / 上一页 / 下一页 / 末页」快速翻页。这样无需一次性加载全部数据，浏览更流畅。",
        "4. 合集模式与合集设置" to "合集模式按“书名”把同名文件聚合在一起，便于发现重复。点击右上角菜单「合集设置」可设置：合集内文件数量区间（最少~最多，留空表示不限）以及需要排除的合集书名。设置后只显示符合条件的合集。",
        "5. 标记重复" to "合集模式下点击右上角菜单「标记重复」：按 PC 端逻辑（同作者 + 纯数字进度，保留最大进度与最大文件）智能勾选待删的重复项；也可「按书名/作者相同标记」给文件加星标、「清除标记」取消。星标（已标记）会贯穿筛选与导出。",
        "6. 选择并删除" to "勾选要删除的文件（合集模式下「标记重复」会自动勾选重复项），底部出现「删除选中」按钮，确认后由前台服务逐个删除并实时显示结果；删除前可在确认页取消勾选。",
        "7. 删除安全" to "删除通过系统 SAF 授权进行，删除前可在确认页取消勾选。删除后文件进入回收站（部分系统）或直接移除，请谨慎操作。建议在“设置”中先用「导出已标记清单」备份待删列表。",
        "8. 设置" to "在“设置”中可调整主题与全局字号（自动适配不同手机屏幕）；配置“关键词替换”规则做文件名数据清洗（扫描阶段清洗文件名、解析阶段清洗书名/作者等）；支持导出已标记清单与清空本地数据。",
        "9. 权限与隐私" to "应用仅通过「文档树」授权访问你所选择的文件夹，不会读取其他目录，也不会上传任何文件。所有扫描、解析、删除都在本机完成，数据与网络无关。"
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
