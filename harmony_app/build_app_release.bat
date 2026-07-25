@echo off
setlocal
chcp 65001 >nul

rem ============================================================
rem  Build release .app package for AGC internal testing
rem  Run AFTER signingConfigs (release) is configured in
rem  build-profile.json5. Build happens in the DevEco workspace
rem  (no Chinese chars in path).
rem ============================================================

set "DEVECO=D:\Install\DevEco Studio"
set "PROJ=D:\Harmony\HarmonyCleaner"
set "PATH=%DEVECO%\tools\node\bin;%DEVECO%\tools\ohpm\bin;%DEVECO%\tools\hvigor\bin;%PATH%"
set "NODE_HOME=%DEVECO%\tools\node"

cd /d "%PROJ%"

echo ============================================
echo [1/2] ohpm install
echo ============================================
call ohpm install
if errorlevel 1 goto :fail

echo ============================================
echo [2/2] assembleApp (release, signed)
echo ============================================
call "%DEVECO%\tools\hvigor\bin\hvigorw.bat" assembleApp --mode project -p product=default -p buildMode=release
if errorlevel 1 goto :fail

echo.
echo ============================================
echo  Output .app package:
dir /s /b "%PROJ%\build\outputs\*.app" 2>nul
dir /s /b "%PROJ%\entry\build\outputs\*.app" 2>nul
echo ============================================
echo  Upload this .app to AppGallery Connect internal testing.
goto :eof

:fail
echo.
echo [FAILED] check errors above
exit /b 1
