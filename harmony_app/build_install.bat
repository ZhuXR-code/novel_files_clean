@echo off
setlocal
set DEVECO=D:\Install\DevEco Studio
set PROJ=d:\user\project\批量文件清理和文件内容识别\txt文件清理-单工程清理\harmony_app
set HDC=%DEVECO%\sdk\default\openharmony\toolchains\hdc.exe
set PATH=%DEVECO%\tools\node\bin;%DEVECO%\tools\ohpm\bin;%DEVECO%\tools\hvigor\bin;%PATH%
set NODE_HOME=%DEVECO%\tools\node

cd /d "%PROJ%"

echo ============================================
echo [1/3] ohpm install (安装依赖)
echo ============================================
call ohpm install
if errorlevel 1 goto :fail

echo ============================================
echo [2/3] 构建 HAP (debug)
echo ============================================
call "%DEVECO%\tools\hvigor\bin\hvigorw.bat" assembleHap --mode module -p product=default -p buildMode=debug
if errorlevel 1 goto :fail

echo ============================================
echo [3/3] 安装到设备
echo ============================================
"%HDC%" list targets
set HAP=
for /r "%PROJ%\entry\build" %%f in (*.hap) do set "HAP=%%f"
if not defined HAP (echo 未找到 HAP 产物 & goto :fail)
echo 找到 HAP: %HAP%
"%HDC%" install "%HAP%"
if errorlevel 1 goto :fail
echo 安装完成，请在设备上启动 "TXT文件清理" App
goto :eof

:fail
echo.
echo [失败] 请检查上述错误信息
exit /b 1
