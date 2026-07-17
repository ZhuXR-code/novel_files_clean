package com.filescanner.app.ui.screens.delete

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.paging.LoadState
import androidx.paging.PagingData
import androidx.paging.compose.LazyPagingItems
import androidx.paging.compose.collectAsLazyPagingItems
import com.filescanner.app.FileScannerApp
import com.filescanner.app.R
import com.filescanner.app.data.database.entity.ScannedFileEntity
import com.filescanner.app.service.DeleteService
import com.filescanner.app.ui.components.CardItem
import com.filescanner.app.ui.components.TopBar
import com.filescanner.app.ui.components.AppButton
import com.filescanner.app.util.FormatUtil
import kotlinx.coroutines.flow.flowOf

/**
 * 待删除 id 的暂存单例。文库页把选择放入此处后再跳转确认页，
 * 避免把 10w 级 id 拼成字符串塞进导航路由（否则会撑爆回退栈 / TransactionTooLarge）。
 */
object PendingDeleteHolder {
    var ids: List<Long> = emptyList()
}

@Composable
fun DeleteConfirmScreen(
    onBack: () -> Unit,
    onStartDelete: () -> Unit
) {
    val context = LocalContext.current
    val repo = FileScannerApp.instance?.repository
    // 全部待删 id（决定删除范围与总数）；selected 初始全选，分页滚动中加载出的文件据此判定勾选态
    val allIds = remember { PendingDeleteHolder.ids }
    var selected by remember { mutableStateOf(allIds.toSet()) }

    // Paging3 分页加载全部待删文件，可滚动浏览，而非仅预览前若干条
    val pagingItems: LazyPagingItems<ScannedFileEntity> = remember(allIds, repo) {
        repo?.pagedByIds(allIds) ?: flowOf(PagingData.empty())
    }.collectAsLazyPagingItems()

    val total = allIds.size
    val count = selected.size

    Scaffold(
        topBar = { TopBar(title = stringResource(R.string.delete_confirm_title), onBack = onBack) },
        bottomBar = {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    stringResource(R.string.delete_confirm_msg, count, total),
                    modifier = Modifier.weight(1f),
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                AppButton(
                    onClick = {
                        val intent = Intent(context, DeleteService::class.java).apply {
                            action = DeleteService.ACTION_START_DELETE
                            putExtra("ids", selected.toLongArray())
                        }
                        context.startForegroundService(intent)
                        onStartDelete()
                    },
                    enabled = count > 0
                ) {
                    Text(stringResource(R.string.confirm_delete, count))
                }
            }
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
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Filled.Warning, contentDescription = null,
                    tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.padding(start = 8.dp))
                Text(
                    stringResource(R.string.delete_warning),
                    color = MaterialTheme.colorScheme.error,
                    fontWeight = MaterialTheme.typography.titleSmall.fontWeight
                )
            }
            val refreshLoading =
                pagingItems.loadState.refresh is LoadState.Loading && pagingItems.itemCount == 0
            when {
                total == 0 -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(stringResource(R.string.empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                refreshLoading -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(stringResource(R.string.loading), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(
                            count = pagingItems.itemCount,
                            key = { index -> pagingItems.peek(index)?.id ?: index },
                        ) { index ->
                            val f = pagingItems[index] ?: return@items
                            val isSel = selected.contains(f.id)
                            CardItem {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable {
                                            selected =
                                                if (isSel) selected - f.id else selected + f.id
                                        }
                                        .padding(12.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Checkbox(checked = isSel, onCheckedChange = {
                                        selected =
                                            if (it) selected + f.id else selected - f.id
                                    })
                                    Column(
                                        modifier = Modifier
                                            .weight(1f)
                                            .padding(start = 8.dp)
                                    ) {
                                        Text(f.title.ifBlank { f.fileName }, maxLines = 1,
                                            overflow = TextOverflow.Ellipsis)
                                        Spacer(Modifier.height(2.dp))
                                        Text(
                                            "${FormatUtil.formatSize(f.fileSize)} · ${f.path}",
                                            maxLines = 1, overflow = TextOverflow.Ellipsis,
                                            fontSize = 12.sp,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }
                            }
                        }
                        // 加载更多时的底部提示
                        if (pagingItems.loadState.append is LoadState.Loading) {
                            item {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(12.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        stringResource(R.string.loading),
                                        fontSize = 12.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
