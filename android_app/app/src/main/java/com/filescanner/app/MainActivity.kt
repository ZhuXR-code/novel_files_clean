package com.filescanner.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.filescanner.app.ui.navigation.NavRoutes
import com.filescanner.app.ui.navigation.NavRoutes.configEdit
import com.filescanner.app.ui.screens.cleanup.OneClickCleanupScreen
import com.filescanner.app.ui.screens.config.ConfigEditScreen
import com.filescanner.app.ui.screens.config.ConfigListScreen
import com.filescanner.app.ui.screens.delete.DeleteConfirmScreen
import com.filescanner.app.ui.screens.delete.DeleteProgressScreen
import com.filescanner.app.ui.screens.help.HelpScreen
import com.filescanner.app.ui.screens.home.HomeScreen
import com.filescanner.app.ui.screens.home.ScanProgressScreen
import com.filescanner.app.ui.screens.library.LibraryScreen
import com.filescanner.app.ui.screens.library.FileDetailScreen
import com.filescanner.app.ui.screens.library.FilePreviewScreen
import com.filescanner.app.ui.screens.settings.SettingsScreen
import com.filescanner.app.ui.screens.settings.KeywordReplaceScreen
import com.filescanner.app.ui.screens.settings.LogViewerScreen
import com.filescanner.app.ui.screens.settings.DupRuleConfigScreen
import com.filescanner.app.data.model.ScanStateManager
import com.filescanner.app.service.ScanService
import com.filescanner.app.ui.theme.FileScannerTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            FileScannerTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    AppNavigation()
                }
            }
        }
    }
}

@Composable
fun AppNavigation() {
    val navController = rememberNavController()
    val appContext = LocalContext.current
    NavHost(navController = navController, startDestination = NavRoutes.HOME) {
        composable(NavRoutes.HOME) {
            HomeScreen(
                onNavigateToLibrary = { navController.navigate(NavRoutes.LIBRARY) },
                onNavigateToSettings = { navController.navigate(NavRoutes.SETTINGS) },
                onNavigateToHelp = { navController.navigate(NavRoutes.HELP) },
                onNavigateToConfigList = { navController.navigate(NavRoutes.CONFIG_LIST) },
                onNavigateToOneClick = { navController.navigate(NavRoutes.ONE_CLICK) }
            )
        }
        composable(NavRoutes.ONE_CLICK) {
            OneClickCleanupScreen(onBack = { navController.popBackStack() })
        }
        composable(NavRoutes.LOG_VIEWER) {
            LogViewerScreen(onBack = { navController.popBackStack() })
        }
        composable(NavRoutes.CONFIG_LIST) {
            ConfigListScreen(
                onBack = { navController.popBackStack() },
                onNavigateToEdit = { id -> navController.navigate(configEdit(id)) },
                onStartScan = { config ->
                    val ctx = appContext
                    val intent = Intent(ctx, ScanService::class.java).apply {
                        action = ScanService.ACTION_START_SCAN
                        putExtra("tree_uri", config.folderUri)
                        putExtra("file_types", config.fileTypes.ifBlank { "txt" })
                        putExtra("min_size_kb", config.minSizeKb)
                        putExtra("recursive", config.recursive)
                        putExtra("excluded_folders", config.excludedFolders)
                        putExtra("config_name", config.name)
                        putExtra("folder_name", config.folderName)
                    }
                    ctx.startForegroundService(intent)
                    navController.navigate(NavRoutes.SCAN_PROGRESS)
                }
            )
        }
        composable(
            route = NavRoutes.CONFIG_EDIT,
            arguments = listOf(navArgument("id") { type = NavType.LongType })
        ) { backStack ->
            val id = backStack.arguments?.getLong("id") ?: -1L
            ConfigEditScreen(
                configId = id,
                onBack = { navController.popBackStack() }
            )
        }
        composable(NavRoutes.SCAN_PROGRESS) {
            ScanProgressScreen(
                onBack = { navController.popBackStack() },
                onFinished = {
                    // 把本次扫描的文库 id 传给文库页，直接进入已扫描结果列表（停止/完成后均保留）
                    navController.navigate("library?runId=${ScanStateManager.runId}") {
                        popUpTo(NavRoutes.SCAN_PROGRESS) { inclusive = true }
                    }
                }
            )
        }
        composable(
            route = "library?runId={runId}",
            arguments = listOf(navArgument("runId") { type = NavType.LongType; defaultValue = -1L })
        ) { backStack ->
            val runIdArg = backStack.arguments?.getLong("runId") ?: -1L
            LibraryScreen(
                onBack = { navController.popBackStack() },
                onNavigateToDeleteConfirm = { navController.navigate(NavRoutes.DELETE_CONFIRM) },
                onOpenFile = { id -> navController.navigate(NavRoutes.fileDetail(id)) },
                initialRunId = runIdArg
            )
        }
        composable(
            route = NavRoutes.FILE_DETAIL,
            arguments = listOf(navArgument("id") { type = NavType.LongType })
        ) { backStack ->
            val id = backStack.arguments?.getLong("id") ?: -1L
            FileDetailScreen(
                fileId = id,
                onBack = { navController.popBackStack() },
                onPreview = { fid, all -> navController.navigate(NavRoutes.filePreview(fid, all)) }
            )
        }
        composable(
            route = NavRoutes.FILE_PREVIEW,
            arguments = listOf(
                navArgument("id") { type = NavType.LongType },
                navArgument("all") { type = NavType.BoolType }
            )
        ) { backStack ->
            val id = backStack.arguments?.getLong("id") ?: -1L
            val all = backStack.arguments?.getBoolean("all") ?: false
            FilePreviewScreen(
                fileId = id,
                previewAll = all,
                onBack = { navController.popBackStack() }
            )
        }
        composable(route = NavRoutes.DELETE_CONFIRM) {
            DeleteConfirmScreen(
                onBack = { navController.popBackStack() },
                onStartDelete = {
                    navController.navigate(NavRoutes.DELETE_PROGRESS) {
                        // 删除开始后把确认页出栈，使删除完成后返回文库
                        popUpTo(NavRoutes.DELETE_CONFIRM) { inclusive = true }
                    }
                }
            )
        }
        composable(NavRoutes.DELETE_PROGRESS) {
            DeleteProgressScreen(
                onFinished = { navController.popBackStack() }
            )
        }
        composable(NavRoutes.SETTINGS) {
            SettingsScreen(
                onBack = { navController.popBackStack() },
                onNavigateToKeywordReplace = { navController.navigate(NavRoutes.KEYWORD_REPLACE) },
                onNavigateToLog = { navController.navigate(NavRoutes.LOG_VIEWER) },
                onNavigateToDupRuleConfig = { navController.navigate(NavRoutes.DUP_RULE_CONFIG) }
            )
        }
        composable(NavRoutes.DUP_RULE_CONFIG) {
            DupRuleConfigScreen(
                onBack = { navController.popBackStack() }
            )
        }
        composable(NavRoutes.KEYWORD_REPLACE) {
            KeywordReplaceScreen(
                onBack = { navController.popBackStack() }
            )
        }
        composable(NavRoutes.HELP) {
            HelpScreen(
                onBack = { navController.popBackStack() }
            )
        }
    }
}
