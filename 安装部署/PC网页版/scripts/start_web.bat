@echo off
REM PC 网页版启动脚本（Windows）
REM 用法：先在本文件上方填写你的 MySQL 账号，再双击运行；或自行 set 环境变量后 python start.py
setlocal
cd /d %~dp0\..\..

REM ---- 在此填写 MySQL 连接（生产环境建议改用系统/服务环境变量，勿把密码写死在脚本）----
set DB_USER=scanner
set DB_PASS=你的密码
set DB_HOST=127.0.0.1
REM DB_PORT / DB_NAME / CORS_ORIGINS 不填则用 backend/app.py 中的默认值

echo [文件清理助手-网页版] 正在启动（默认 http://localhost:8000）...
python start.py
endlocal
