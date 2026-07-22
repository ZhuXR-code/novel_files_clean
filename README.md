# TXT 文件清理与内容识别系统

批量扫描本地 TXT 文件，自动从文件名/内容中解析出书名、作者等结构化信息，并按「书名+作者」进行合集归并、重复识别与清理的一体化工具。

**使用方法**
> **方法一：配置扫描路径→扫描→工程类全部解析→合集模式→标记重复→批量删除选中**  
> **方法二：配置扫描路径→一键清理→确认要删除的文件**

项目同时提供 **PC 端**（网页版 / 本地软件版）与 **Android APP 端** 两套形态，核心解析与清理逻辑保持一致。

---

## 一、项目形态

| 形态 | 说明 | 数据库 | 入口 |
| --- | --- | --- | --- |
| PC 网页版 | 浏览器访问，前后端分离 | MySQL（外部） | `python start.py` |
| PC 本地软件版 | 独立窗口应用（pywebview + WebView2），不打开浏览器、不联网 | 内置 SQLite | `python launcher.py` / 打包后的 `FileScanner.exe` |
| Android APP | 原生移动端 | Room（SQLite） | `android_app/`（Android Studio 构建） |
| HarmonyOS NEXT | 纯血鸿蒙原生端 | relationalStore（SQLite） | `harmony_app/`（DevEco Studio 构建） |

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
│  ├─ logger.py            #   多进程安全日志（轮转落盘 logs/app.log）
│  └─ operation_log.py     #   操作日志（用户关键操作留痕，落盘 logs/operation.log）
├─ frontend/               # 前端（原生 HTML/JS/CSS）
│  ├─ index.html
│  ├─ js/app.js
│  └─ css/
├─ android_app/            # Android APP（Kotlin + Jetpack Compose + Room）
├─ harmony_app/            # HarmonyOS NEXT 原生 APP（ArkTS + ArkUI + relationalStore）
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
- 数据库默认存放在**程序安装目录内**的 `FileScannerData\file_scanner.db`，
  即数据随安装目录走，用户在安装向导中指定的路径即为数据根目录；
  不再散落到 `%APPDATA%`。可用环境变量 `SQLITE_DB_PATH` 自定义数据目录。

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
- **合集模式**：按「书名+作者」归并成合集，识别重复文件，并提供计算进度条。
- **标记重复**：在「同一合集内、按 (作者+小说名) 子分组」套用五则规则自动勾选待删重复项（核心算法见 `backend/dup_logic.py`，PC 网页版 / PC 桌面软件版共用，APP 端镜像同一逻辑，三端完全一致）：
  1. **完全相等去重**：`文件名+大小+小说名+作者+进度` 五字段完全一致的多本中，保留最新(创建最晚，并列取 id 最大) 一本，其余全部勾选；
  2. **纯数字进度对比**：同 (作者+小说名) 内，若**所有**进度均为纯数字，则进度数字最大者不勾选，其余纯数字文件全部勾选；
  3. **含中文进度 / 完结特例**：进度含中文(如「完结/连载/断更」) 不勾选；但若同组存在文件名带「完结」等关键词、且「进度数字最大文件」的大小小于同组**所有**含中文进度文件的大小，则该「进度数字最大文件」也要勾选（说明存在更完整的完结版，部分进度版冗余应删）；
  4. **最大文件不勾选原则**：已勾选文件中，本 (作者+小说名) 组内**唯一**文件大小最大者不勾选（并列最大时不据此保护，以免同尺寸重复组被整体保留）。
  5. **完结+N番外 组合排序**：进度【严格】匹配 `完结+数字番外`（如「完结+3番外」）的文件，在同 (作者+小说名) 组内按数字 N 排序，数字最大者不勾选、其余勾选；但若被勾选的文件恰为本组文件大小最大者，则也不勾选。
- **清理**：勾选重复项批量清理/删除。
- **日志**：PC 与 APP 两端均内置日志模块与关键节点，便于调试与问题定位。
  - PC 端：`logs/app.log` 为流水线调试日志（轮转落盘）；`logs/operation.log` 为**操作日志**（记录标记重复、删除记录、清空配置、一键清理删除等用户关键操作），前端「调试日志」面板可切换「操作日志 / 调试日志」并一键复制。
  - APP 端：统一日志工具同时写入 logcat、内存（最近 1000 条）与私有目录 `debug.log`；「设置 → 调试日志」可查看、刷新、复制、清空。

---

## 七、更多文档

各端的安装部署、使用指南与运维手册见 `安装部署/` 目录：
- `安装部署/PC网页版/`：安装部署手册、用户使用手册、产品功能操作介绍、运维手册
- `安装部署/PC桌面软件版/`：安装部署手册、用户使用手册、产品功能操作介绍、运维手册（本地 EXE / SQLite）
- `安装部署/APP端/`：安装部署手册、用户使用手册、产品功能操作介绍、运维手册

---

## 八、致谢

感谢以下老师在测试与优化方面的帮助：

- **Tetteyterettey**
- **星尘**

---

欢迎大家试用，也欢迎提出更多优化意见，ღ( ´･ᴗ･` ) 比心！

