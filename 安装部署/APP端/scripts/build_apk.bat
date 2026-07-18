@echo off
REM 构建 APP 端 Android APK（调试版）。如需发布版把 assembleDebug 改为 assembleRelease。
setlocal
cd /d %~dp0\..\..

IF NOT EXIST android_app (
  echo [错误] 未找到 android_app 目录，请在工程根目录运行本脚本。
  exit /b 1
)

cd android_app
echo [1/2] 使用 Gradle Wrapper 构建 debug APK ...
call .\gradlew.bat assembleDebug --console=plain
IF ERRORLEVEL 1 (
  echo [失败] 构建出错，请检查 JDK / Android SDK 环境。
  exit /b 1
)

echo [2/2] 构建完成：
echo   android_app\app\build\outputs\apk\debug\app-debug.apk
echo 安装到设备（以 MuMu 7555 为例）：
echo   adb connect 127.0.0.1:7555
echo   adb -s 127.0.0.1:7555 install -r app\build\outputs\apk\debug\app-debug.apk
endlocal
