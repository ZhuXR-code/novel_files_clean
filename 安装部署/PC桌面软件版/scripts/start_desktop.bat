@echo off
REM PC 桌面软件版启动脚本（Windows，源码方式）
REM 双击运行：以内置 SQLite 打开独立软件窗口，无需 MySQL、无需浏览器。
setlocal
cd /d %~dp0\..\..\..

echo [文件清理助手-桌面软件版] 正在启动本地窗口应用...
REM 如需便携模式（数据库放程序旁 FileScannerData\），改为：python launcher.py --portable
python launcher.py
endlocal
