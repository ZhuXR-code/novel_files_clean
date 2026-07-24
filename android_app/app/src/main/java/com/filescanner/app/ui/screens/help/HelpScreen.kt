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
        "1. 开始扫描" to "在首页点击「开始扫描」，进入「扫描配置」列表：可新增配置（选择文件夹、文件类型、是否递归、排除文件夹），或从已有配置直接开始。应用会递归读取文件、并在扫描时同步解析文件名提取书名/作者/进度/来源，用于识别重复。文件名解析已能正确处理作者名的修订后缀（如「作者：Nnnr（【修】山海镜花 融共同人）」会提取作者为 Nnnr，并正确识别来源、进度、书名）。扫描结果保存在本机，不会上传。",
        "2. 查看文库与筛选" to "扫描完成后进入文库，会按「每次扫描」分出多个文库。在文库内可按「全部 / 已勾选 / 未勾选 / 已标记 / 未标记」筛选，按时间、名称、大小排序。列表/合集两种视图通过顶部分段开关切换。",
        "2.1 搜索与拼音搜索" to "支持按书名、作者、文件名搜索。更强大的拼音搜索：输入拼音全拼（如 doupo）或首字母缩写（如 dpcq），即可搜到「斗破苍穹」等中文书名/作者名，不用切换到中文输入法即可快速定位目标。",
        "2.2 文件内容预览" to "在文库列表或文件详情点击文件即可进入「文件预览」，直接查看 txt 文本内容。预览页右侧新增一条可拖动的竖向滚动条，拖动滑块即可在已加载内容范围内快速上下滑动浏览，无需频繁滑动屏幕。内容较多时应用采用流式分批加载（默认仅读取前若干行，向下滚动到底部自动加载更多），并能自动识别 GBK / UTF-8 编码，避免大文件卡顿；右侧滚动条仅在内容超出一屏时出现。",
        "3. 分页浏览大库" to "面对几万、十几万条数据，底部「分页导航条」帮助你逐页浏览：①「每页」输入框填每页条数（默认 100，范围 10~2000），点「应用」生效；②「跳到」输入框填目标页码，点「跳转」直达该页；③「首页 / 上一页 / 下一页 / 末页」快速翻页。这样无需一次性加载全部数据，浏览更流畅。",
        "4. 合集模式与合集设置" to "合集模式按「书名」把同名文件聚合在一起，便于发现重复。点击右上角菜单「合集设置」可设置：合集内文件数量区间（最少~最多，留空表示不限）以及需要排除的合集书名。设置后只显示符合条件的合集。在合集视图中，每个合集的汇总卡片标题下会实时显示该合集「已勾选 X 个」，方便确认待删项的数量。",
        "5. 勾选重复与勾选" to "合集模式下点击右上角菜单「勾选重复」：在「同一文库内、按 (作者 + 小说名) 子分组」套用与 PC 端 backend/dup_logic.py 完全一致的五则规则智能勾选待删重复项——① 完全相等去重：小说名+作者+大小+进度 四字段完全一致的多本中（不再比较文件名），保留最新(创建最晚，并列取 id 最大) 一本，其余全部勾选；② 纯数字进度对比：同组内所有进度均为纯数字时，进度数字最大者不勾选，其余纯数字文件全部勾选；③ 含中文进度 / 完结特例：进度含中文(如完结/连载/断更) 不勾选，但若同组存在文件名带「完结/完本/全本/全集/完整/全套/全集版」等关键词、且「进度数字最大文件」的大小小于同组所有含中文进度文件的大小，则该进度最大文件也要勾选（存在更完整的完结版，部分进度版冗余应删）；④ 最大文件不勾选原则：已勾选文件中，本 (作者+小说名) 组内唯一文件大小最大者不勾选（并列最大时不据此保护，以免同尺寸重复组被整体保留）；⑤ 完结+N番外 组合排序：进度【严格】匹配「完结+数字番外」(如「完结+3番外」) 的文件，在同 (作者+小说名) 组内按数字 N 排序，数字最大者不勾选、其余勾选；但若被勾选的文件恰为本组 (作者+小说名) 内文件大小最大者，则也不勾选。示例：F1 进度 80%(2.0MB)、F2「斗破苍穹完结版.txt」进度 完结(5.0MB)、F3 进度 完结(6.0MB) → F2/F3 含中文受保护保留，F1 进度最大但比所有含中文文件都小且有完结关键词 → F1 强制勾选(删)，F2/F3 保留。也可「按书名/作者相同标记」给文件加星标、「清除标记」取消。星标（已标记）会贯穿筛选与导出。注意：「勾选重复」写入的是【勾选(checked)】而非星标，勾选会持久保存，可在顶部筛选选「已勾选 / 未勾选」聚焦待删项；行尾星标仅供手动标记，与「勾选重复」无关。勾选重复后，列表模式下已勾选文件自动排列到最前面，合集模式下包含已勾选项的合集排列到最前面，方便快速浏览和确认待删项。\n\n上述五则规则可在「设置」页的「勾选重复规则」中单独开启或关闭，默认全部启用。你可以按需只启用你想使用的规则，例如只想保留「精确重复去重」则关闭其余规则即可。关闭规则后「勾选重复」和删除操作都只按启用的规则执行。",
        "6. 选择并删除" to "勾选要删除的文件（合集模式下「勾选重复」会自动勾选重复项），底部出现「批量删除选中」按钮，点击先让你选择【仅删除记录】或【删除记录和源文件(不可恢复)】，确认后由前台服务逐个删除并实时显示结果；删除前在确认页仍可取消勾选。",
        "7. 删除安全" to "删除通过系统 SAF 授权进行，删除前可在确认页取消勾选。删除后文件进入回收站（部分系统）或直接移除，请谨慎操作。建议在「设置」中先用「导出已标记清单」备份待删列表。",
        "8. 设置" to "在「设置」中可调整主题与全局字号（自动适配不同手机屏幕）；配置「关键词替换」规则做文件名数据清洗（扫描阶段清洗文件名、解析阶段清洗书名/作者等）；「勾选重复规则」可分别开关六条去重规则（默认全部启用），关闭后「勾选重复」和删除操作不再使用该规则判断；支持导出已标记清单与清空本地数据。",
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
