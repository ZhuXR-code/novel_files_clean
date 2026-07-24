package com.filescanner.app.ui.navigation

object NavRoutes {
    const val HOME = "home"
    const val LIBRARY = "library"
    const val FILE_DETAIL = "file_detail/{id}"
    const val FILE_PREVIEW = "file_preview/{id}/{all}"
    const val SCAN_PROGRESS = "scan_progress"
    const val DELETE_CONFIRM = "delete_confirm"
    const val DELETE_PROGRESS = "delete_progress"
    const val SETTINGS = "settings"
    const val HELP = "help"
    const val KEYWORD_REPLACE = "keyword_replace"
    const val CONFIG_LIST = "config_list"
    const val CONFIG_EDIT = "config_edit/{id}"
    const val ONE_CLICK = "one_click_cleanup"
    const val LOG_VIEWER = "log_viewer"
    const val DUP_RULE_CONFIG = "dup_rule_config"


    fun configEdit(id: Long) = "config_edit/$id"
    fun fileDetail(id: Long) = "file_detail/$id"
    fun filePreview(id: Long, all: Boolean) = "file_preview/$id/$all"
}
