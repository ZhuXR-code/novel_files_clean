package com.bookscleanandroid.app.util

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.bookscleanandroid.app.util.LogUtil
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
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
        // 是否已同意隐私协议（首次启动必须主动同意）
        val PRIVACY_AGREED = booleanPreferencesKey("privacy_agreed")
        // 列表/合集模式：已勾选文件是否自动排到最前面（默认关闭）
        val CHECKED_SORT_TO_FRONT = booleanPreferencesKey("checked_sort_to_front")
    }

    val themeMode: Flow<String> = context.dataStore.data
        .catch { e -> LogUtil.e("PreferencesUtil", "读取 themeMode 失败: ${e.message}"); emit(emptyPreferences()) }
        .map { it[THEME_MODE] ?: "system" }
    val scanFileTypes: Flow<String> = context.dataStore.data
        .catch { e -> LogUtil.e("PreferencesUtil", "读取 scanFileTypes 失败: ${e.message}"); emit(emptyPreferences()) }
        .map { it[SCAN_FILE_TYPES] ?: "txt" }
    val minFileSizeKb: Flow<Int> = context.dataStore.data
        .catch { e -> LogUtil.e("PreferencesUtil", "读取 minFileSizeKb 失败: ${e.message}"); emit(emptyPreferences()) }
        .map { it[MIN_FILE_SIZE] ?: 0 }
    val recursive: Flow<Boolean> = context.dataStore.data
        .catch { e -> LogUtil.e("PreferencesUtil", "读取 recursive 失败: ${e.message}"); emit(emptyPreferences()) }
        .map { it[RECURSIVE] ?: true }
    val groupMinCount: Flow<Int> = context.dataStore.data
        .catch { e -> LogUtil.e("PreferencesUtil", "读取 groupMinCount 失败: ${e.message}"); emit(emptyPreferences()) }
        .map { it[GROUP_MIN_COUNT] ?: 0 }
    val groupMaxCount: Flow<Int> = context.dataStore.data
        .catch { e -> LogUtil.e("PreferencesUtil", "读取 groupMaxCount 失败: ${e.message}"); emit(emptyPreferences()) }
        .map { it[GROUP_MAX_COUNT] ?: -1 }
    val groupExcludeNames: Flow<String> = context.dataStore.data
        .catch { e -> LogUtil.e("PreferencesUtil", "读取 groupExcludeNames 失败: ${e.message}"); emit(emptyPreferences()) }
        .map { it[GROUP_EXCLUDE_NAMES] ?: "" }
    val fontScaleMode: Flow<String> = context.dataStore.data
        .catch { e -> LogUtil.e("PreferencesUtil", "读取 fontScaleMode 失败: ${e.message}"); emit(emptyPreferences()) }
        .map { it[FONT_SCALE] ?: "standard" }
    val previewScrollbarMode: Flow<String> = context.dataStore.data
        .catch { e -> LogUtil.e("PreferencesUtil", "读取 previewScrollbarMode 失败: ${e.message}"); emit(emptyPreferences()) }
        .map { it[PREVIEW_SCROLLBAR_MODE] ?: "vertical" }
    /** 是否已同意隐私协议。 */
    val privacyAgreed: Flow<Boolean> = context.dataStore.data
        .catch { e -> LogUtil.e("PreferencesUtil", "读取 privacyAgreed 失败: ${e.message}"); emit(emptyPreferences()) }
        .map { it[PRIVACY_AGREED] ?: false }

    suspend fun setThemeMode(mode: String) {
        try {
            context.dataStore.edit { it[THEME_MODE] = mode }
            LogUtil.d("PreferencesUtil", "设置 themeMode=$mode")
        } catch (e: Exception) {
            LogUtil.e("PreferencesUtil", "设置 themeMode 失败: ${e.message}")
        }
    }

    suspend fun setPreviewScrollbarMode(mode: String) {
        try {
            context.dataStore.edit { it[PREVIEW_SCROLLBAR_MODE] = mode }
            LogUtil.d("PreferencesUtil", "设置 previewScrollbarMode=$mode")
        } catch (e: Exception) {
            LogUtil.e("PreferencesUtil", "设置 previewScrollbarMode 失败: ${e.message}")
        }
    }

    suspend fun setFontScale(mode: String) {
        try {
            context.dataStore.edit { it[FONT_SCALE] = mode }
            LogUtil.d("PreferencesUtil", "设置 fontScale=$mode")
        } catch (e: Exception) {
            LogUtil.e("PreferencesUtil", "设置 fontScale 失败: ${e.message}")
        }
    }

    suspend fun setGroupFilter(minCount: Int, maxCount: Int, excludeNames: String) {
        try {
            context.dataStore.edit {
                it[GROUP_MIN_COUNT] = minCount.coerceAtLeast(0)
                it[GROUP_MAX_COUNT] = maxCount
                it[GROUP_EXCLUDE_NAMES] = excludeNames
            }
            LogUtil.d("PreferencesUtil", "设置合集筛选 min=$minCount max=$maxCount exclude=$excludeNames")
        } catch (e: Exception) {
            LogUtil.e("PreferencesUtil", "设置合集筛选失败: ${e.message}")
        }
    }

    /** 关键词替换默认规则是否已预埋过。 */
    suspend fun isKeywordSeeded(): Boolean =
        try {
            context.dataStore.data.map { it[KW_SEED_DONE] ?: false }.first()
        } catch (e: Exception) {
            LogUtil.e("PreferencesUtil", "读取 kwSeed 失败: ${e.message}")
            false
        }

    /** 标记关键词替换默认规则已预埋。 */
    suspend fun setKeywordSeeded() {
        try {
            context.dataStore.edit { it[KW_SEED_DONE] = true }
            LogUtil.d("PreferencesUtil", "标记关键词默认规则已预埋")
        } catch (e: Exception) {
            LogUtil.e("PreferencesUtil", "标记 kwSeed 失败: ${e.message}")
        }
    }

    /** 记录用户已同意隐私协议。 */
    suspend fun setPrivacyAgreed(v: Boolean) {
        try {
            context.dataStore.edit { it[PRIVACY_AGREED] = v }
            LogUtil.d("PreferencesUtil", "设置隐私协议同意=$v")
        } catch (e: Exception) {
            LogUtil.e("PreferencesUtil", "设置隐私协议失败: ${e.message}")
        }
    }

    /** 已勾选文件是否自动排到最前面（默认 false）。 */
    val checkedSortToFront: Flow<Boolean> =
        context.dataStore.data
            .catch { e -> LogUtil.e("PreferencesUtil", "读取 checkedSortToFront 失败: ${e.message}"); emit(emptyPreferences()) }
            .map { it[CHECKED_SORT_TO_FRONT] ?: false }

    suspend fun setCheckedSortToFront(v: Boolean) {
        try {
            context.dataStore.edit { it[CHECKED_SORT_TO_FRONT] = v }
            LogUtil.d("PreferencesUtil", "设置 checkedSortToFront=$v")
        } catch (e: Exception) {
            LogUtil.e("PreferencesUtil", "设置 checkedSortToFront 失败: ${e.message}")
        }
    }
}
