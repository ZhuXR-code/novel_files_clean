package com.filescanner.app.util

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "settings")

class PreferencesUtil(private val context: Context) {
    companion object {
        val THEME_MODE = stringPreferencesKey("theme_mode")
        val SCAN_FILE_TYPES = stringPreferencesKey("scan_file_types") // "txt,md"
        val MIN_FILE_SIZE = intPreferencesKey("min_file_size_kb")
        val RECURSIVE = booleanPreferencesKey("recursive")
        // 合集模式设置
        val GROUP_MIN_COUNT = intPreferencesKey("group_min_count")   // 合集文件数下限，0=不限
        val GROUP_MAX_COUNT = intPreferencesKey("group_max_count")   // 合集文件数上限，-1=不限
        val GROUP_EXCLUDE_NAMES = stringPreferencesKey("group_exclude_names") // 排除的合集书名，逗号分隔
        // 全局字号："small" / "standard" / "large"
        val FONT_SCALE = stringPreferencesKey("font_scale")
        // 关键词替换默认规则是否已预埋，避免重复写入
        val KW_SEED_DONE = booleanPreferencesKey("kw_seed_done")
        // 预览滚动条方向："vertical" / "horizontal"
        val PREVIEW_SCROLLBAR_MODE = stringPreferencesKey("preview_scrollbar_mode")
    }

    val themeMode: Flow<String> = context.dataStore.data.map { it[THEME_MODE] ?: "system" }
    val scanFileTypes: Flow<String> = context.dataStore.data.map { it[SCAN_FILE_TYPES] ?: "txt" }
    val minFileSizeKb: Flow<Int> = context.dataStore.data.map { it[MIN_FILE_SIZE] ?: 0 }
    val recursive: Flow<Boolean> = context.dataStore.data.map { it[RECURSIVE] ?: true }
    val groupMinCount: Flow<Int> = context.dataStore.data.map { it[GROUP_MIN_COUNT] ?: 0 }
    val groupMaxCount: Flow<Int> = context.dataStore.data.map { it[GROUP_MAX_COUNT] ?: -1 }
    val groupExcludeNames: Flow<String> = context.dataStore.data.map { it[GROUP_EXCLUDE_NAMES] ?: "" }
    val fontScaleMode: Flow<String> = context.dataStore.data.map { it[FONT_SCALE] ?: "standard" }
    val previewScrollbarMode: Flow<String> = context.dataStore.data.map { it[PREVIEW_SCROLLBAR_MODE] ?: "vertical" }

    suspend fun setThemeMode(mode: String) {
        context.dataStore.edit { it[THEME_MODE] = mode }
    }

    suspend fun setPreviewScrollbarMode(mode: String) {
        context.dataStore.edit { it[PREVIEW_SCROLLBAR_MODE] = mode }
    }

    suspend fun setFontScale(mode: String) {
        context.dataStore.edit { it[FONT_SCALE] = mode }
    }

    suspend fun setGroupFilter(minCount: Int, maxCount: Int, excludeNames: String) {
        context.dataStore.edit {
            it[GROUP_MIN_COUNT] = minCount.coerceAtLeast(0)
            it[GROUP_MAX_COUNT] = maxCount
            it[GROUP_EXCLUDE_NAMES] = excludeNames
        }
    }

    /** 关键词替换默认规则是否已预埋过。 */
    suspend fun isKeywordSeeded(): Boolean =
        context.dataStore.data.map { it[KW_SEED_DONE] ?: false }.first()

    /** 标记关键词替换默认规则已预埋。 */
    suspend fun setKeywordSeeded() {
        context.dataStore.edit { it[KW_SEED_DONE] = true }
    }
}
