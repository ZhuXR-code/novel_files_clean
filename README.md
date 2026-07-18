# TXT 文件清理与内容识别系统

批量扫描本地 TXT 文件，自动从文件名/内容中解析出书名、作者等结构化信息，并按「书名+作者」进行合集归并、重复识别与清理的一体化工具。

项目同时提供 **PC 端**（网页版 / 本地软件版）与 **Android APP 端** 两套形态，核心解析与清理逻辑保持一致。

---

## 一、项目形态

| 形态 | 说明 | 数据库 | 入口 |
| --- | --- | --- | --- |
| PC 网页版 | 浏览器访问，前后端分离 | MySQL（外部） | `python start.py` |
| PC 本地软件版 | 独立窗口应用（pywebview + WebView2），不打开浏览器、不联网 | 内置 SQLite | `python launcher.py` / 打包后的 `FileScanner.exe` |
| Android APP | 原生移动端 | Room（SQLite） | `android_app/`（Android Studio 构建） |

> 形态切换靠环境变量 `DB_BACKEND`：不设置走 MySQL；`launcher.py` 在导入后端前设置 `DB_BACKEND=sqlite` 走本地 SQLite 分支。网页版的 MySQL 代码路径在本地模式下完全不被触碰。

---

## 二、目录结构

```
txt文件清理-单工程清理/
├─ backend/                # 后端（FastAPI）
│  ├─ app.py               #   主应用与 API 路由
│  ├─ db_config.py         #   MySQL / SQLite 双后端配置
│  ├─ models.py            #   ORM 数据模型
│  ├─ scanner.py           #   文件扫描
│  ├─ regex_parser.py      #   文件名 / 内容正则解析
│  ├─ keyword_replace.py   #   关键词替换规则
│  ├─ pipeline.py          #   解析流水线
│  └─ logger.py            #   多进程安全日志（轮转落盘 logs/app.log）
├─ frontend/               # 前端（原生 HTML/JS/CSS）
│  ├─ index.html
│  ├─ js/app.js
│  └─ css/
├─ android_app/            # Android APP（Kotlin + Jetpack Compose + Room）
├─ 安装部署/               # 各端安装/使用/运维手册
│  ├─ PC网页版/
│  ├─ PC桌面软件版/
│  └─ APP端/
├─ build/                  # 打包脚本（PyInstaller spec、Inno Setup iss）
├─ launcher.py             # 本地软件版启动器（SQLite）
├─ start.py                # 网页版一键启动脚本（MySQL）
├─ migrate_to_new_db.py    # 数据迁移脚本
├─ 文件名数据清洗.py       # 文件名数据清洗辅助脚本
└─ requirements.txt        # Python 依赖
```

---

## 三、快速开始（PC 端）

### 环境要求
- Python 3.9+
- 网页版另需可访问的 MySQL 实例

### 安装依赖
```bash
pip install -r requirements.txt
```

### 启动网页版（MySQL）
```bash
python start.py
```
脚本会检查依赖、启动 FastAPI 后端并等待服务就绪，随后即可在浏览器访问前端页面。

### 启动本地软件版（SQLite，无需 MySQL）
```bash
python launcher.py
```
- 以独立窗口打开，仅监听 `127.0.0.1`，不联网。
- 数据默认存放于 `%APPDATA%\FileScanner\file_scanner.db`。
- 使用 `python launcher.py --portable` 可将数据库放在程序旁的 `FileScannerData\` 目录，便于整体拷贝。

---

## 四、打包为 Windows 软件

- 生成单文件 EXE（PyInstaller）：
  ```bash
  python -m PyInstaller build/FileScanner.spec --noconfirm
  ```
  产物：`dist/FileScanner.exe`（打包前请先结束残留的 FileScanner 进程，避免 PermissionError）。

- 生成安装向导（Inno Setup）：在 `build/` 目录下执行 `ISCC.exe FileScanner.iss`，产物为 `build/output/FileScanner-Setup.exe`。

---

## 五、Android APP

源码位于 `android_app/`，使用 Kotlin + Jetpack Compose，数据层为 Room。用 Android Studio 打开 `android_app/` 目录即可构建；或命令行：
```bash
cd android_app
./gradlew assembleDebug
```
调试版包名 `com.filescanner.app.debug`，主 Activity `com.filescanner.app.MainActivity`。

---

## 六、核心功能

- **文件扫描**：批量扫描指定目录下的 TXT 文件。
- **结构化解析**：基于正则从文件名/内容识别书名、作者等字段，支持关键词替换规则。
- **合集模式**：按「书名+作者」归并成合集，识别重复文件（保留体积最大者），并提供计算进度条。
- **清理**：勾选重复项批量清理/删除。
- **日志**：PC 与 APP 两端均内置日志模块与关键节点，便于调试与问题定位（PC 日志落盘 `logs/app.log`，支持轮转）。

---

## 七、更多文档

各端的安装部署、使用指南与运维手册见 `安装部署/` 目录：
- `安装部署/PC网页版/`：安装部署手册、用户使用手册、产品功能操作介绍、运维手册
- `安装部署/PC桌面软件版/`：安装部署手册、用户使用手册、产品功能操作介绍、运维手册（本地 EXE / SQLite）
- `安装部署/APP端/`：安装部署手册、用户使用手册、产品功能操作介绍、运维手册
