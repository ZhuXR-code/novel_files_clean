package com.filescanner.app.ui.screens.settings

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.filescanner.app.FileScannerApp
import com.filescanner.app.util.LogUtil
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class SettingsViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as FileScannerApp
    private val prefs = app.preferencesUtil
    private val repo = app.repository

    val themeMode: StateFlow<String> = prefs.themeMode
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "system")

    val fontScaleMode: StateFlow<String> = prefs.fontScaleMode
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "standard")

    val previewScrollbarMode: StateFlow<String> = prefs.previewScrollbarMode
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "vertical")

    fun setTheme(mode: String) {
        viewModelScope.launch(Dispatchers.IO) { prefs.setThemeMode(mode) }
    }

    fun setFontScale(mode: String) {
        viewModelScope.launch(Dispatchers.IO) { prefs.setFontScale(mode) }
    }

    fun setPreviewScrollbarMode(mode: String) {
        viewModelScope.launch(Dispatchers.IO) { prefs.setPreviewScrollbarMode(mode) }
    }


    suspend fun exportMarked(context: Context): String? {
        return withContext(Dispatchers.IO) { repo.exportMarked(context) }
    }

    fun clearData(onDone: () -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                repo.deleteAll()
                LogUtil.i("Settings", "All local data cleared")
            } catch (e: Exception) {
                LogUtil.e("Settings", "clearData failed: ${e.message}")
            }
            onDone()
        }
    }
}
