package com.filescanner.app.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Density
import androidx.core.view.WindowCompat
import com.filescanner.app.FileScannerApp

// 极简单色 + 绿色强调
val Accent = Color(0xFF2D6A4F)
val AccentLight = Color(0xFF40916C)
val Neutral900 = Color(0xFF111827)
val Neutral800 = Color(0xFF1F2937)
val Neutral700 = Color(0xFF374151)
val Neutral600 = Color(0xFF4B5563)
val Neutral500 = Color(0xFF6B7280)
val Neutral400 = Color(0xFF9CA3AF)
val Neutral300 = Color(0xFFD1D5DB)
val Neutral200 = Color(0xFFE5E7EB)
val Neutral100 = Color(0xFFF3F4F6)
val Neutral50 = Color(0xFFF9FAFB)
val White = Color(0xFFFFFFFF)

private val DarkColorScheme = darkColorScheme(
    primary = AccentLight,
    onPrimary = White,
    primaryContainer = Color(0xFF1A3A2E),
    secondary = Neutral400,
    onSecondary = Neutral900,
    secondaryContainer = Neutral800,
    tertiary = Neutral500,
    onTertiary = White,
    tertiaryContainer = Neutral700,
    background = Neutral900,
    onBackground = Neutral100,
    surface = Neutral800,
    onSurface = Neutral100,
    surfaceVariant = Neutral700,
    onSurfaceVariant = Neutral400,
    outline = Neutral600,
    outlineVariant = Neutral700,
    error = Color(0xFFEF4444),
    onError = White
)

private val LightColorScheme = lightColorScheme(
    primary = Accent,
    onPrimary = White,
    primaryContainer = Color(0xFFD8F3DC),
    secondary = Neutral600,
    onSecondary = White,
    secondaryContainer = Neutral100,
    tertiary = Neutral500,
    onTertiary = White,
    tertiaryContainer = Neutral200,
    background = Neutral50,
    onBackground = Neutral900,
    surface = White,
    onSurface = Neutral900,
    surfaceVariant = Neutral100,
    onSurfaceVariant = Neutral500,
    outline = Neutral300,
    outlineVariant = Neutral200,
    error = Color(0xFFDC2626),
    onError = White
)

@Composable
fun FileScannerTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val app = FileScannerApp.instance
    val themeMode by if (app != null) {
        app.preferencesUtil.themeMode.collectAsState(initial = "system")
    } else {
        androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf("system") }
    }
    val fontScaleMode by if (app != null) {
        app.preferencesUtil.fontScaleMode.collectAsState(initial = "standard")
    } else {
        androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf("standard") }
    }


    val isDark = when (themeMode) {
        "dark" -> true
        "light" -> false
        else -> darkTheme
    }

    val colorScheme = if (isDark) DarkColorScheme else LightColorScheme

    // 全局字号：在系统字号基础上再乘以用户选择的比例，缩放所有 sp 文本，自适应不同手机
    val userScale = when (fontScaleMode) {
        "small" -> 0.85f
        "large" -> 1.2f
        else -> 1f
    }
    val baseDensity = LocalDensity.current
    val scaledDensity = Density(baseDensity.density, baseDensity.fontScale * userScale)

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.background.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !isDark
        }
    }

    CompositionLocalProvider(LocalDensity provides scaledDensity) {
        MaterialTheme(
            colorScheme = colorScheme,
            content = content
        )
    }
}
