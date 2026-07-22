# 文件清理 - 纯血鸿蒙版（harmony_app）

TXT 批量文件清理与文件内容识别系统的 **HarmonyOS NEXT 原生**实现，功能完整镜像安卓端
（`android_app/`），纯本地运行、不联网、无后端依赖。

## 技术栈

- **HarmonyOS NEXT**（Stage 模型）
- **ArkTS + ArkUI**
- **@ohos.data.relationalStore**（本地关系型数据库，纯本地存储）
- 文件访问：`@ohos.file.picker`（DocumentViewPicker）+ `@ohos.file.fs`
- 哈希：`@ohos.cryptoFramework`（MD5）
- 日志/导出：`@ohos.file.fs` 写入应用沙箱

## 目录结构

```
harmony_app/
├── AppScope/                 # 应用级配置（bundleName、图标、名称）
├── entry/                    # 主模块
│   ├── build-profile.json5   # 模块构建配置
│   ├── obfuscation-rules.txt # 混淆规则占位
│   ├── src/main/
│   │   ├── module.json5      # 模块/Ability 声明
│   │   ├── resources/        # 字符串、颜色、图标、页面注册
│   │   └── ets/
│   │       ├── entryability/EntryAbility.ts  # 入口，初始化数据库
│   │       ├── model/        # 数据模型：ScannedFile/ScanConfig/ScanRun/...
│   │       ├── database/     # RdbHelper + 4 个 Dao
│   │       ├── utils/        # Parser/KeywordReplace/DupLogic/LogUtil/...
│   │       ├── service/      # ScanService/DeleteService/ExportService
│   │       └── pages/        # 14 个页面
```

## 构建步骤（DevEco Studio）

1. **环境要求**
   - DevEco Studio 5.0 或以上
   - HarmonyOS NEXT SDK，`compatibleSdkVersion = 5.0.0(12)`（API 12）
   - Node.js 与 ohpm（DevEco 自带）

2. **打开工程**：`File → Open`，选择 `harmony_app/` 目录。

3. **同步依赖**：DevEco 打开后会自动执行 `ohpm install`；如需手动，在终端运行 `ohpm install`。

4. **签名配置**（必须，否则无法运行）：
   - `File → Project Structure → Signing Configs`
   - 勾选 **Automatically generate signature**（需登录华为开发者账号并连接模拟器/真机）
   - 自动签名会在 `build-profile.json5` 中填充 `signingConfigs`

5. **运行 / 构建**：
   - 调试：选择模拟器或真机，点击 **Run**
   - 出包：`Build → Build Haps(s) / APP(s)`

> 说明：根 `build-profile.json5` 的 `products[].signingConfig` 默认引用 `default`，
> 初始 `signingConfigs` 为空数组，由 DevEco 自动签名时填充，属官方标准模板写法。

## 权限配置说明

本应用**无需在 `module.json5` 声明任何危险权限**：

- **扫描目录访问**：通过 `DocumentViewPicker`（`selectMode = DIR`）由用户主动选择目录，
  属于用户显式授权访问，不需要 `ohos.permission.READ_MEDIA` 等清单权限。
- **CSV 导出 / 日志写入**：均写入应用沙箱 `filesDir`，不需要任何存储权限。

因此 `module.json5` 的 `abilities` 中**未配置 `requestPermissions`**。
若后续需将导出文件写到共享目录（如下载目录），再按场景申请对应权限。

## 与安卓端功能对照

| 能力 | 安卓端 | 鸿蒙端 |
|------|--------|--------|
| 文件名解析 | `Parser.kt` | `utils/Parser.ts`（正则对齐） |
| 五则去重 | `FileRepository.selectDuplicateIds` | `utils/DupLogic.ts` |
| 关键词替换 | `KeywordReplace.kt` | `utils/KeywordReplace.ts`（字面量） |
| 文件扫描 | SAF 遍历 | `ScanService`（Picker + fs 遍历，增量写库） |
| 文库/合集浏览 | Room 查询 | `LibraryScreen` |
| 标记重复 / 一键清理 | —— | `LibraryScreen` / `OneClickCleanup` |
| 物理删除 + 记录 | —— | `DeleteService` |
| CSV 导出 | —— | `ExportService` |
| 操作日志 | —— | `LogUtil`（UTF-8 解码） |
| 配置管理 | —— | `ScanConfig` 相关页面 |

数据模型 4 张表对齐安卓 v8：`scanned_file` / `scan_config` / `scan_run` / `keyword_replace_rules`。

## 已知真机校准点

1. **文件遍历 API**：`ScanService` 用 `DocumentViewPicker` 选目录返回授权 URI，再用
   `@ohos.file.fs`（`fileIo`）递归遍历。NEXT 的 Picker URI 文件访问行为以真机/模拟器官方
   文档为准，请在模拟器实测目录遍历、哈希读取、删除。
2. **目录授权持久化**：保存的 `folderUri` 因 NEXT 安全模型，下次扫描可能需重新选目录授权。
3. **Kit 包可用性**：本工程依赖 `@kit.ArkUI` / `@kit.ArkData` / `@kit.CoreFileKit` /
   `@kit.CryptoArchitectureKit` / `@kit.ArkTS`，请确保所用 SDK 版本均已提供上述 Kit。
4. **数据库位置**：`RdbHelper` 在应用沙箱创建 `file_scanner.db`，卸载应用即清除。

## 说明

本机（Windows）无 DevEco Studio 与鸿蒙 SDK，源码工程无法在本机编译，需由用户在
DevEco Studio + 模拟器/真机完成构建与验证。

## 变更记录

### 2026-07-22 按安卓端未提交优化同步

以当前 git 工作区中 `android_app/` 已改文件为基准，对鸿蒙端做以下对齐：

- `utils/Parser.ts`：书名/作者前缀兼容"作家"；标签识别支持【】、[]、（）、()；作者尾部清洗新增"更新至N / 补番 / 修"；进度提取新增"番外 / 更新至N"；新增 cleanTitle 清洗书名前导标签。
- `utils/DupLogic.ts` + `database/ScannedFileDao.ts`：新增 `markDuplicatesByName` / `markDuplicatesByNameSql`（按书名+作者相同标记重复），并新增 `setCheckedForIds` / `clearChecked` / `getCheckedIds` / `markIds` / `clearMarked` / `getMarked` / `getFilesByTitle` / `getByPath` / `deleteAll` 等批量方法。
- `utils/KeywordReplace.ts` + `database/KeywordReplaceDao.ts` + `EntryAbility.ts`：新增 10 条默认去水印规则，启动时按 pattern 幂等补齐；DAO 新增 `countByScopeAndPattern` / `maxSortOrder` / `upsert` / `setEnabled`。
- `service/ScanService.ts` + `pages/ScanProgress.ets`：新增 `stop()` 停止扫描，进度回调节流，扫描停止后保留已写入结果。
- `service/DeleteService.ts` + `pages/DeleteConfirm.ets` + `pages/DeleteProgress.ets`：新增 `deleteSource` 开关（仅删记录 或 删记录+源文件）、分批删除、删除后重算受影响文库的 `file_count`。
- `pages/LibraryScreen.ets`：新增"书名标重"、"清空标记"按钮，搜索防抖，显示已勾选/已标记统计。
- `pages/KeywordReplace.ets`：新增规则默认追加到 sortOrder 末尾，开关仅更新 enabled 字段。
- `pages/LibraryList.ets`：删除文库时同步清空该文库下的文件记录，避免数据残留。

> 2026-07-22 二次补充：
> - `pages/LibraryScreen.ets` 补齐合集高级筛选（minCount/maxCount/excludeNames）、UNMARKED/UNCHECKED 筛选、搜索防抖、合集展开按筛选条件缓存。
> - `service/ScanService.ts` 由 DFS 栈改为 BFS 层级遍历；说明鸿蒙端 `fileIo.listFile` 已天然等效 Android SAF 批量 children 查询。
> - `utils/Parser.ts` 的 `SOURCE_SITES` 同步安卓端新增 `fw/ht/米国度/米国`。
> - `database/KeywordReplaceDao.ts` 新增 `countAll()`；`utils/PreferencesUtil.ts` 新增 `KW_SEED_DONE` 常量；`EntryAbility` 在默认规则补齐成功后写入该标记。
