package com.filescanner.app.ui.navigation

object NavRoutes {
    const val HOME = "home"
    const val LIBRARY = "library"
    const val FILE_DETAIL = "file_detail/{id}"
    const val SCAN_PROGRESS = "scan_progress"
    const val DELETE_CONFIRM = "delete_confirm"
    const val DELETE_PROGRESS = "delete_progress"
    const val SETTINGS = "settings"
    const val HELP = "help"
    const val KEYWORD_REPLACE = "keyword_replace"
    const val CONFIG_LIST = "config_list"
    const val CONFIG_EDIT = "config_edit/{id}"

    fun configEdit(id: Long) = "config_edit/$id"
    fun fileDetail(id: Long) = "file_detail/$id"
}
