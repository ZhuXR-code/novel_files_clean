plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.devtools.ksp")
}

android {
    namespace = "com.filescanner.app"
    compileSdk = 35
    buildToolsVersion = "36.1.0"

    defaultConfig {
        applicationId = "com.filescanner.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            // 本地没有签名文件时回退到 debug 签名，保证可直接构建；正式发布请配置 release 签名
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
            applicationIdSuffix = ".debug"
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    // 直接用 JUnit 控制台运行本地单测，绕开 AGP 测试 worker 的 classpath 装配怪象
    // （该工程路径含中文，AGP 的 test worker 偶发 ClassNotFoundException，与代码无关）。
    afterEvaluate {
        tasks.register<JavaExec>("runParserTest") {
            group = "verification"
            description = "直接运行 ParserTest（绕过 AGP test worker）"
            dependsOn("compileDebugUnitTestKotlin", "compileDebugKotlin", "kspDebugKotlin")
            val buildDir = layout.buildDirectory.get().asFile
            val ktTestDir = file("$buildDir/tmp/kotlin-classes/debugUnitTest")
            val mainClasses = file("$buildDir/tmp/kotlin-classes/debug")
            classpath(
                ktTestDir,
                mainClasses,
                configurations.getByName("debugUnitTestRuntimeClasspath"),
            )
            mainClass.set("org.junit.runner.JUnitCore")
            args("com.filescanner.app.util.ParserTest", "com.filescanner.app.util.LibraryLogicTest")
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.animation:animation")

    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")

    val roomVersion = "2.6.1"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    // Room 的 Paging3 集成：@RawQuery 返回 PagingSource 需要此依赖
    implementation("androidx.room:room-paging:$roomVersion")
    ksp("androidx.room:room-compiler:$roomVersion")

    // 分页：解决 10w 级文件列表全表加载导致的内存/卡顿问题
    val pagingVersion = "3.3.2"
    implementation("androidx.paging:paging-runtime:$pagingVersion")
    implementation("androidx.paging:paging-compose:$pagingVersion")

    // 拼音搜索：输入 dpcq 搜到「斗破苍穹」
    implementation("com.belerweb:pinyin4j:2.5.1")

    implementation("androidx.datastore:datastore-preferences:1.1.1")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // 繁体转简体（解析结果统一入库为简体）。纯 Java 实现，字典以 classpath 资源打包进 APK。
    implementation("com.github.houbb:opencc4j:1.8.1")

    debugImplementation("androidx.compose.ui:ui-tooling")

    // ---- 单元测试依赖 ----
    testImplementation("junit:junit:4.13.2")
    testImplementation("androidx.test:runner:1.6.2")
    testImplementation("androidx.test.ext:junit:1.2.1")
}
