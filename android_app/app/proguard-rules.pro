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

# ===== Coroutines =====
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
