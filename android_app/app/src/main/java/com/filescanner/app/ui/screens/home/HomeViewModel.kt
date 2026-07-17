package com.filescanner.app.ui.screens.home

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filescanner.app.FileScannerApp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

class HomeViewModel(application: Application) : AndroidViewModel(application) {
    private val repo = (application as FileScannerApp).repository

    // 直接订阅 COUNT(*) 流，不把全表 10w 行读进内存
    val stats: StateFlow<Pair<Int, Int>> = combine(
        repo.totalCount, repo.markedCount
    ) { total, marked -> Pair(total, marked) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), Pair(0, 0))
}
