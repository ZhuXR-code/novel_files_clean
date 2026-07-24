# TXT 文件清理与内容识别系统

批量扫描本地 TXT 文件，自动从文件名/内容中解析出书名、作者等结构化信息，并按「书名+作者」进行合集归并、重复识别与清理的一体化工具。

**使用方法**
> **方法一：配置扫描路径→扫描→工程类全部解析→合集模式→勾选重复→批量删除选中**  
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

> APP 端新增**预览页滚动条模式选择**（设置 → 阅读设置），支持竖向/横向（顶部）两种滚动条；触摸时自动加粗，0.5 秒不操作恢复。底部操作栏仅保留「清除勾选」和「删除」按钮，其他功能移至右上角菜单，界面更简洁。

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
- **勾选重复**（APP 端）：在「同一合集内、按 (作者+小说名) 子分组」套用规则自动勾选待删重复项（核心算法见 `android_app/.../data/repository/DupRuleLogic.kt` 与 `FileRepository.selectDuplicateIds`）。每条规则可在「设置 → 勾选重复规则」中**独立开关**，**勾选才生效、取消不生效**；内置规则不可删除，自定义规则可增删改。规则明细见 [6.1 勾选重复规则详解](#61-勾选重复规则详解)。
- **清理**：勾选重复项批量清理/删除。
- **日志**：PC 与 APP 两端均内置日志模块与关键节点，便于调试与问题定位。
  - PC 端：`logs/app.log` 为流水线调试日志（轮转落盘）；`logs/operation.log` 为**操作日志**（记录勾选重复、删除记录、清空配置、一键清理删除等用户关键操作），前端「调试日志」面板可切换「操作日志 / 调试日志」并一键复制。
  - APP 端：统一日志工具同时写入 logcat、内存（最近 1000 条）与私有目录 `debug.log`；「设置 → 调试日志」可查看、刷新、复制、清空。

### 6.1 勾选重复规则详解

「勾选重复」与「一键清理」两条 UI 路径共用同一套规则计算逻辑（APP 端为 `DupRuleLogic.computeDuplicateChecks` → `FileRepository.selectDuplicateIds`）。规则按「(作者 + 小说名)」子分组逐组计算，最终给出**应勾选删除**的文件集合。

#### 内置规则（6 条，不可删除，每条独立开关）

> 表中「默认」均为开启。勾选才生效；取消勾选则该规则不参与计算。

| rule_key | 名称 | 默认 | 启用时的行为 |
| --- | --- | --- | --- |
| `rule1` | 精确重复去重 | 开 | `小说名+作者+进度+文件大小` 完全相等的多本中，保留最新(创建最晚、并列取 id 最大) 一本，其余勾选 |
| `rule2` | 纯数字进度对比 | 开 | 有纯数字进度(可含小数、`%`) 的文件中，进度数字最大者不勾选，其余纯数字文件勾选 |
| `rule3a` | 含中文进度保护 | 开 | 含有中文进度(如「更新至50」) 的文件不勾选（保护，覆盖其他规则的强制勾选） |
| `rule3b` | 完结特例 | 开 | 同一本书若同时有「完结版」(文件名含「完结/全本」)与纯数字进度的文件：当数字进度最大的文件体积小于所有「完结字样」文件中最小的那个，说明它不完整，会勾选删除，只留下完结版 |
| `rule4` | 最大文件不勾选 | 开 | 同一组内文件大小**唯一**最大者不勾选（并列最大时不据此保护，以免同尺寸重复组被整体保留） |
| `rule5` | 完结+N番外/番外N去重 | 开 | 进度【严格】匹配 `完结+数字番外` 或 `完结+番外数字`(如「完结+3番外」「完结+番外5」) 的组内，按番外数 N 排序，N 最大者不勾选、其余勾选；但若被保护文件恰为本组唯一最大文件，则也不勾选 |

> 说明：`rule3a` / `rule4` 的保护优先级高于 `rule1`/`rule2`/`rule5` 的强制勾选——即被 `rule3a`/`rule4` 保护的文件即使被其他规则判定为"应勾选"也会从勾选集合移除（该保护逻辑已在近期修复，确保"勾选即生效"）。

#### 自定义规则（可增 / 删 / 改，每条独立开关）

- **匹配条件**：对所选字段（`file_name` 文件名 / `author` 作者 / `title` 书名 等）用正则匹配，多条条件为「且」关系，全部满足才命中。
- **动作 `action`**：
  - `check`（✓ 勾选）：命中后把该文件加入勾选集合；
  - `protect`（🛡️ 保护）：命中后把该文件从勾选集合移除。
- **示例**：文件名含「水印」→ `水印`；以「完结」开头 → `^完结`；作者等于张三 → `^张三$`。

#### 生效逻辑（勾选才生效的实现）

- 内置规则：`getEnabledBuiltinRuleKeys()` 用 SQL `WHERE enabled = 1 AND is_builtin = 1` 取出**仅启用**的规则 key，只把勾选项传入计算 → 未勾选的规则不参与。
- 自定义规则：`getEnabledUserRules()` 用 SQL `WHERE enabled = 1 AND is_builtin = 0 AND conditions IS NOT NULL` 取出**仅启用**的规则传入计算 → 未勾选的规则不参与。
- 因此「设置页勾选与否」直接决定该规则是否生效；修改后下次执行"勾选重复"即按新规则执行。

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

