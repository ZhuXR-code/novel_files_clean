package com.filescanner.app.ui.screens.config

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filescanner.app.FileScannerApp
import com.filescanner.app.data.database.entity.ScanConfigEntity
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class ScanConfigViewModel(application: Application) : AndroidViewModel(application) {
    private val dao = (application as FileScannerApp).database.scanConfigDao()

    val configs: StateFlow<List<ScanConfigEntity>> = dao.getAll()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    suspend fun getById(id: Long): ScanConfigEntity? = dao.getById(id)

    fun upsert(config: ScanConfigEntity, onDone: (Long) -> Unit = {}) {
        viewModelScope.launch {
            val newId = dao.upsert(config)
            onDone(if (config.id != 0L) config.id else newId)
        }
    }

    fun delete(id: Long, onDone: () -> Unit = {}) {
        viewModelScope.launch {
            dao.deleteById(id)
            onDone()
        }
    }
}
