plugins {
    id("com.android.application") version "8.7.3" apply false
    // Compose 1.7.x（BOM 2024.12.01）官方配套的 Kotlin 为 2.0.21：
    // 其自带 Compose 编译器面向 1.7.x。用 2.1.0 时编译器面向 1.8.x，
    // 生成的代码会访问 RowColumnParentData.weight（1.7.6 中仍为 internal），
    // 导致 `weight` 报 "it is internal in file"。
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
    id("com.google.devtools.ksp") version "2.0.21-1.0.28" apply false
}
