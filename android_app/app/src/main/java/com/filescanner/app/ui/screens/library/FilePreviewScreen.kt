package com.filescanner.app.ui.screens.library

import android.content.Context
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt
import androidx.lifecycle.viewmodel.compose.viewModel
import com.filescanner.app.R
import com.filescanner.app.ui.components.AppOutlinedButton
import com.filescanner.app.ui.components.TopBar
import com.filescanner.app.util.EncodingUtil
import com.filescanner.app.util.PreferencesUtil
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.io.InputStream
import java.io.InputStreamReader
import java.io.Reader

/** “前 50 行”模式的行数上限 */
private const val HEAD_LINES = 50

/** 全量模式下每批加载的行数（随滚动按需加载，避免一次性载入 50MB） */
private const val BATCH_LINES = 400

/** 单行最大字符数：超长无换行的行会被强制分段，防止单行几十 MB 撑爆内存/渲染 */
private const val MAX_LINE_CHARS = 4000

/** 编码探测采样字节数 */
private const val SAMPLE_BYTES = 64 * 1024

/**
 * 文件内容分批读取器（面向大文件，50MB 级别验证标准）。
 *
 * 设计要点：
 * - 编码：先采样 64KB 探测（BOM → UTF-8 严格校验 → GB18030 兜底），
 *   再以正确编码打开流，避免中文 txt（GBK/GB18030 常见）乱码；
 * - 性能：流式读取 + 按需分批取行，内存占用只随「用户实际浏览到的内容」增长，
 *   绝不一次性把整个文件读入内存；
 * - 兜底：无换行符的超长行按 [MAX_LINE_CHARS] 强制切段，防止 readLine 式
 *   一次构造几十 MB 的超大字符串。
 */
internal class PreviewLoader(
    private val context: Context,
    private val path: String
) : Closeable {

    var charsetName: String = "UTF-8"
        private set

    private var reader: Reader? = null
    private var eofReached = false
    private val carry = StringBuilder()
    private val buf = CharArray(32 * 1024)

    /** 是否已读尽（流到底且缓冲区已清空） */
    val isEof: Boolean get() = eofReached && carry.isEmpty()

    private fun openRawStream(): InputStream {
        return if (path.startsWith("content://")) {
            context.contentResolver.openInputStream(Uri.parse(path))
                ?: throw IOException("无法打开输入流（文件可能已被移动或删除）")
        } else {
            FileInputStream(File(path.removePrefix("file://")))
        }
    }

    /** 打开文件：先采样探测编码，再以探测到的编码重新打开流（跳过 BOM）。 */
    fun open() {
        val (charset, bomSkip) = EncodingUtil.detectEncodingAndBom(context, path, SAMPLE_BYTES)
        charsetName = charset.displayName()

        val ins = openRawStream()
        var skipped = 0L
        while (skipped < bomSkip) {
            val s = ins.skip(bomSkip - skipped)
            if (s <= 0) break
            skipped += s
        }
        reader = BufferedReader(InputStreamReader(ins, charset), 256 * 1024)
    }

    /**
     * 读取至多 [maxLines] 行。行尾 \r\n / \n 均兼容；
     * 超过 [MAX_LINE_CHARS] 仍无换行的内容强制切为一行返回。
     */
    fun readLines(maxLines: Int): List<String> {
        val r = reader ?: return emptyList()
        val out = ArrayList<String>(maxLines)
        while (out.size < maxLines) {
            val nl = carry.indexOf("\n")
            if (nl in 0..MAX_LINE_CHARS) {
                var end = nl
                if (end > 0 && carry[end - 1] == '\r') end--
                out.add(carry.substring(0, end))
                carry.delete(0, nl + 1)
                continue
            }
            if (carry.length > MAX_LINE_CHARS) {
                out.add(carry.substring(0, MAX_LINE_CHARS))
                carry.delete(0, MAX_LINE_CHARS)
                continue
            }
            if (eofReached) {
                if (carry.isNotEmpty()) {
                    out.add(carry.toString())
                    carry.setLength(0)
                }
                break
            }
            val n = try {
                r.read(buf)
            } catch (_: Exception) {
                -1
            }
            if (n < 0) eofReached = true else carry.append(buf, 0, n)
        }
        return out
    }

    override fun close() {
        try {
            reader?.close()
        } catch (_: Exception) {
        }
        reader = null
        eofReached = true
        carry.setLength(0)
    }
}

/**
 * 文件内容预览页。
 *
 * @param previewAll false = 仅前 50 行；true = 全部内容（随滚动分批加载）
 */
@Composable
fun FilePreviewScreen(
    fileId: Long,
    previewAll: Boolean,
    onBack: () -> Unit,
    viewModel: LibraryViewModel = viewModel()
) {
    val context = LocalContext.current
    val prefs = remember { PreferencesUtil(context) }
    val scrollbarMode by prefs.previewScrollbarMode.collectAsStateWithLifecycle(initialValue = "vertical")
    val lines = remember { mutableStateListOf<String>() }
    var loading by remember { mutableStateOf(true) }
    var loadingMore by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var eof by remember { mutableStateOf(false) }
    var charsetName by remember { mutableStateOf("") }
    var fileTitle by remember { mutableStateOf("") }
    val loaderHolder = remember { mutableStateOf<PreviewLoader?>(null) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // 当前预览页正文字号（仅作用于本页面，范围 10~28sp，默认 13）
    var previewFontSize by remember { mutableStateOf(13) }
    // 字号调节面板折叠/展开状态，默认展开
    var fontSizeExpanded by remember { mutableStateOf(true) }

    // 自定义可拖拽滚动条的状态
    val trackHeightPx = remember { mutableStateOf(0) }      // 内容区高度（px）
    val trackWidthPx = remember { mutableStateOf(0) }       // 内容区宽度（px）
    val scrollbarVisible by remember {
        derivedStateOf { lines.size > listState.layoutInfo.visibleItemsInfo.size }
    }

    // 首次进入：解析记录 → 打开文件（IO 线程）→ 加载首批内容
    LaunchedEffect(fileId, previewAll) {
        loading = true
        error = null
        try {
            val result = withContext(Dispatchers.IO) {
                val f = viewModel.getById(fileId)
                    ?: throw IOException(context.getString(R.string.file_not_found))
                val loader = PreviewLoader(context.applicationContext, f.path)
                loader.open()
                val first = loader.readLines(if (previewAll) BATCH_LINES else HEAD_LINES)
                Triple(f, loader, first)
            }
            fileTitle = result.first.title.ifBlank { result.first.fileName }
            loaderHolder.value = result.second
            charsetName = result.second.charsetName
            lines.addAll(result.third)
            eof = result.second.isEof || !previewAll
            if (!previewAll) {
                // 前 50 行模式：读完即关流，尽早释放文件句柄
                withContext(Dispatchers.IO) { runCatching { result.second.close() } }
            }
        } catch (e: Exception) {
            error = e.message ?: context.getString(R.string.error)
        } finally {
            loading = false
        }
    }

    // 离开页面时关闭流
    DisposableEffect(Unit) {
        onDispose {
            loaderHolder.value?.let { runCatching { it.close() } }
        }
    }

    // 全量模式：滚动接近已加载末尾时，按需加载下一批
    val shouldLoadMore by remember {
        derivedStateOf {
            val lastVisible = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            previewAll && !eof && !loading && !loadingMore &&
                lines.isNotEmpty() && lastVisible >= lines.size - 60
        }
    }
    LaunchedEffect(shouldLoadMore) {
        if (!shouldLoadMore) return@LaunchedEffect
        loadingMore = true
        try {
            val more = withContext(Dispatchers.IO) {
                loaderHolder.value?.readLines(BATCH_LINES) ?: emptyList()
            }
            lines.addAll(more)
            eof = loaderHolder.value?.isEof ?: true
        } finally {
            loadingMore = false
        }
    }

    Scaffold(
        topBar = {
            TopBar(
                title = fileTitle.ifBlank { stringResource(R.string.preview_title) },
                onBack = onBack,
                actions = {
                    IconButton(onClick = { fontSizeExpanded = !fontSizeExpanded }) {
                        Text(
                            if (fontSizeExpanded) "Aa" else "Aa",
                            fontSize = 14.sp,
                            fontWeight = if (fontSizeExpanded) FontWeight.Bold else FontWeight.Normal,
                            color = if (fontSizeExpanded)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.onSurfaceVariant
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
            // 信息栏：编码 + 已加载行数
            if (!loading && error == null) {
                // 折叠内容：A− / 当前字号 / A+
                if (fontSizeExpanded) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            stringResource(R.string.preview_font),
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(Modifier.width(10.dp))
                        AppOutlinedButton(
                            onClick = { previewFontSize = (previewFontSize - 1).coerceAtLeast(10) },
                            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 2.dp)
                        ) { Text("A−", fontSize = 12.sp) }
                        Spacer(Modifier.width(4.dp))
                        Text(
                            "$previewFontSize",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Spacer(Modifier.width(4.dp))
                        AppOutlinedButton(
                            onClick = { previewFontSize = (previewFontSize + 1).coerceAtMost(28) },
                            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 2.dp)
                        ) { Text("A+", fontSize = 12.sp) }
                    }
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        stringResource(R.string.preview_encoding, charsetName),
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        stringResource(R.string.preview_loaded_lines, lines.size),
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }

            when {
                loading -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator()
                        Spacer(Modifier.height(12.dp))
                        Text(
                            stringResource(R.string.preview_loading),
                            fontSize = 13.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                error != null -> Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        stringResource(R.string.preview_failed, error ?: ""),
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.error
                    )
                }

                lines.isEmpty() -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        stringResource(R.string.preview_empty_file),
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                else -> {
                    if (scrollbarMode == "vertical") {
                        VerticalPreviewContent(
                            lines = lines,
                            listState = listState,
                            previewAll = previewAll,
                            loadingMore = loadingMore,
                            eof = eof,
                            previewFontSize = previewFontSize,
                            scrollbarVisible = scrollbarVisible,
                            trackHeightPx = trackHeightPx,
                            scope = scope
                        )
                    } else {
                        HorizontalPreviewContent(
                            lines = lines,
                            listState = listState,
                            previewAll = previewAll,
                            loadingMore = loadingMore,
                            eof = eof,
                            previewFontSize = previewFontSize,
                            scrollbarVisible = scrollbarVisible,
                            trackWidthPx = trackWidthPx,
                            scope = scope
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PreviewLazyList(
    lines: List<String>,
    listState: androidx.compose.foundation.lazy.LazyListState,
    previewAll: Boolean,
    loadingMore: Boolean,
    eof: Boolean,
    previewFontSize: Int,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        state = listState,
        modifier = modifier.fillMaxSize()
    ) {
        itemsIndexed(lines) { index, line ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 1.dp)
            ) {
                Text(
                    (index + 1).toString(),
                    fontSize = (previewFontSize - 2).coerceAtLeast(10).sp,
                    color = MaterialTheme.colorScheme.outline,
                    modifier = Modifier.padding(end = 10.dp, top = 2.dp)
                )
                Text(
                    line,
                    fontSize = previewFontSize.sp,
                    lineHeight = (previewFontSize + 6).sp,
                    fontWeight = FontWeight.Normal
                )
            }
        }
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 14.dp),
                contentAlignment = Alignment.Center
            ) {
                when {
                    loadingMore -> Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.size(8.dp))
                        Text(
                            stringResource(R.string.preview_loading_more),
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    !previewAll -> Text(
                        stringResource(R.string.preview_head_done, HEAD_LINES),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )

                    eof -> Text(
                        stringResource(R.string.preview_eof),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun VerticalPreviewContent(
    lines: List<String>,
    listState: androidx.compose.foundation.lazy.LazyListState,
    previewAll: Boolean,
    loadingMore: Boolean,
    eof: Boolean,
    previewFontSize: Int,
    scrollbarVisible: Boolean,
    trackHeightPx: androidx.compose.runtime.MutableState<Int>,
    scope: kotlinx.coroutines.CoroutineScope
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(end = 2.dp)
            .onGloballyPositioned { coordinates -> trackHeightPx.value = coordinates.size.height }
    ) {
        PreviewLazyList(
            lines = lines,
            listState = listState,
            previewAll = previewAll,
            loadingMore = loadingMore,
            eof = eof,
            previewFontSize = previewFontSize
        )
        // 右侧可拖拽滚动条：在已加载范围内上下滑动浏览
        if (scrollbarVisible && trackHeightPx.value > 0) {
            val layoutInfo = listState.layoutInfo
            val total = lines.size
            val visible = layoutInfo.visibleItemsInfo.size.coerceAtLeast(1)
            val maxFirst = (total - visible).coerceAtLeast(0)
            val fraction = if (maxFirst <= 0) 0f
            else listState.firstVisibleItemIndex.toFloat() / maxFirst
            val thumbH = (trackHeightPx.value.toFloat() * visible / total.coerceAtLeast(1))
                .toInt().coerceAtLeast(48)
            val maxOff = (trackHeightPx.value - thumbH).coerceAtLeast(0)
            val thumbOffset = (fraction * maxOff).toInt()

            // 手指触摸/拖拽时滑条变宽，松开 0.5 秒后缩回
            val thumbWidthAnim = remember { Animatable(4f) }
            var thumbDragging by remember { mutableStateOf(false) }
            LaunchedEffect(thumbDragging) {
                if (thumbDragging) {
                    thumbWidthAnim.animateTo(12f, tween(150))
                } else {
                    delay(500)
                    thumbWidthAnim.animateTo(4f, tween(200))
                }
            }

            // 全高的触摸轨道（比可见滑块宽，方便点到），点按/拖拽均触发变宽
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .fillMaxHeight()
                    .width(20.dp)
                    .pointerInput(Unit) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            thumbDragging = true

                            // 首次触摸即跳转到对应位置
                            val mFirst = maxOf(
                                1,
                                (lines.size - listState.layoutInfo.visibleItemsInfo.size).coerceAtLeast(0)
                            )
                            val touchFrac =
                                (down.position.y / trackHeightPx.value).coerceIn(0f, 1f)
                            val jumpTarget = (touchFrac * mFirst).roundToInt()
                            scope.launch { listState.scrollToItem(jumpTarget) }

                            // 继续跟踪拖拽
                            do {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull() ?: break
                                if (change.pressed) {
                                    change.consume()
                                    val mOff =
                                        (trackHeightPx.value - thumbH).coerceAtLeast(1)
                                    val cur = if (mFirst <= 0) 0f
                                    else listState.firstVisibleItemIndex.toFloat() / mFirst
                                    val newFrac = (cur + (change.position.y - down.position.y) / mOff)
                                        .coerceIn(0f, 1f)
                                    val target = (newFrac * mFirst).roundToInt()
                                    scope.launch { listState.scrollToItem(target) }
                                }
                            } while (change.pressed)

                            thumbDragging = false
                        }
                    }
            ) {
                // 可见滑块（纯展示，手势由外层轨道统一处理）
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .offset { IntOffset(0, thumbOffset) }
                        .size(width = thumbWidthAnim.value.dp, height = thumbH.dp)
                        .background(
                            MaterialTheme.colorScheme.primary.copy(alpha = 0.55f),
                            RoundedCornerShape(2.dp)
                        )
                )
            }
        }
    }
}

@Composable
private fun HorizontalPreviewContent(
    lines: List<String>,
    listState: androidx.compose.foundation.lazy.LazyListState,
    previewAll: Boolean,
    loadingMore: Boolean,
    eof: Boolean,
    previewFontSize: Int,
    scrollbarVisible: Boolean,
    trackWidthPx: androidx.compose.runtime.MutableState<Int>,
    scope: kotlinx.coroutines.CoroutineScope
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .onGloballyPositioned { coordinates ->
                trackWidthPx.value = coordinates.size.width
            }
    ) {
        // 顶部可拖拽横向滚动条
        if (scrollbarVisible && trackWidthPx.value > 0) {
            val layoutInfo = listState.layoutInfo
            val total = lines.size
            val visible = layoutInfo.visibleItemsInfo.size.coerceAtLeast(1)
            val maxFirst = (total - visible).coerceAtLeast(0)
            val fraction = if (maxFirst <= 0) 0f
            else listState.firstVisibleItemIndex.toFloat() / maxFirst
            val thumbW = (trackWidthPx.value.toFloat() * visible / total.coerceAtLeast(1))
                .toInt().coerceAtLeast(48)
            val maxOff = (trackWidthPx.value - thumbW).coerceAtLeast(0)
            val thumbOffset = (fraction * maxOff).toInt()

            val dragState = rememberDraggableState { delta ->
                val mFirst = maxOf(
                    1,
                    (lines.size - listState.layoutInfo.visibleItemsInfo.size).coerceAtLeast(0)
                )
                val mOff = (trackWidthPx.value - thumbW).coerceAtLeast(1)
                val cur = if (mFirst <= 0) 0f
                else listState.firstVisibleItemIndex.toFloat() / mFirst
                val newFrac = (cur + delta / mOff).coerceIn(0f, 1f)
                val target = (newFrac * mFirst).roundToInt()
                scope.launch { listState.scrollToItem(target) }
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(20.dp)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
            ) {
                Box(
                    modifier = Modifier
                        .offset { IntOffset(thumbOffset, 0) }
                        .size(width = thumbW.dp, height = 4.dp)
                        .align(Alignment.CenterStart)
                        .background(
                            MaterialTheme.colorScheme.primary.copy(alpha = 0.55f),
                            RoundedCornerShape(2.dp)
                        )
                        .draggable(dragState, Orientation.Horizontal)
                )
            }
        } else {
            Spacer(modifier = Modifier.height(0.dp))
        }

        PreviewLazyList(
            lines = lines,
            listState = listState,
            previewAll = previewAll,
            loadingMore = loadingMore,
            eof = eof,
            previewFontSize = previewFontSize,
            modifier = Modifier.weight(1f)
        )
    }
}
