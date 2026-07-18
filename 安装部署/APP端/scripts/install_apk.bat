@echo off
REM 安装 / 更新 APP 端 APK 到已连接设备。
setlocal
cd /d %~dp0\..\..

set APK=android_app\app\build\outputs\apk\debug\app-debug.apk
IF NOT EXIST %APK% (
  echo [错误] 未找到 %APK%，请先运行 build_apk.bat 构建。
  exit /b 1
)

echo 列出已连接设备：
adb devices
echo.
set /p DEV="请输入目标设备序列号（直接回车则用默认 127.0.0.1:7555）："
IF "%DEV%"=="" set DEV=127.0.0.1:7555

echo [安装] %APK% --^> %DEV%
adb -s %DEV% install -r %APK%
endlocal
