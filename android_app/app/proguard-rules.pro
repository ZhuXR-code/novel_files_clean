# ===== Room Database =====
-keep class com.filescanner.app.data.database.entity.** { *; }
-keep class com.filescanner.app.data.database.dao.** { *; }

# ===== Gson =====
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class com.filescanner.app.data.model.** { *; }


# ===== Compose =====
-dontwarn androidx.compose.**
-keep class androidx.compose.** { *; }

# ===== opencc4j（繁简转换）=====
# 字典以 classpath 资源(data/**)打包，代码通过反射/资源加载，需整体保留避免被裁剪。
-keep class com.github.houbb.opencc4j.** { *; }
-keep class com.github.houbb.heaven.** { *; }
-dontwarn com.github.houbb.**

# ===== TinyPinyin（拼音搜索）=====
# 内置字典以 assets 或 classpath 打包，需保留避免 Release 裁剪。
-keep class com.github.promeg.pinyinhelper.** { *; }
-keep class com.github.promeg.tinypinyin.** { *; }
-dontwarn com.github.promeg.**

# ===== Coroutines =====
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
