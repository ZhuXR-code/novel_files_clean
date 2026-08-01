# =====================================================================
# sync_to_harmonycleaner.ps1
# 双工程同步脚本：harmony_app <-> HarmonyCleaner
#
# 用法：
#   .\sync_to_harmonycleaner.ps1           # harmony_app -> HarmonyCleaner（默认）
#   .\sync_to_harmonycleaner.ps1 -Reverse  # HarmonyCleaner -> harmony_app（反向）
#
# 说明：harmony_app 是源工程（AI 编辑），HarmonyCleaner 是 DevEco 调试工作空间。
#       两者代码必须保持一致。本脚本全量同步 ets/ts 源码文件。
# =====================================================================
param([switch]$Reverse)

$srcBase = "d:\user\project\批量文件清理和文件内容识别\txt文件清理-单工程清理\harmony_app\entry\src\main\ets"
$dstBase = "D:\Harmony\HarmonyCleaner\entry\src\main\ets"

if ($Reverse) {
    $srcBase = "D:\Harmony\HarmonyCleaner\entry\src\main\ets"
    $dstBase = "d:\user\project\批量文件清理和文件内容识别\txt文件清理-单工程清理\harmony_app\entry\src\main\ets"
    $direction = "HarmonyCleaner -> harmony_app"
} else {
    $direction = "harmony_app -> HarmonyCleaner"
}

if (-not (Test-Path $srcBase)) {
    Write-Output "ERROR: Source path not found: $srcBase"
    exit 1
}

$count = 0
Get-ChildItem -Path $srcBase -Recurse -Include "*.ets", "*.ts" | ForEach-Object {
    $rel = $_.FullName.Substring($srcBase.Length)
    $target = Join-Path $dstBase $rel
    $targetDir = Split-Path $target -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    Copy-Item $_.FullName $target -Force
    $count++
}

Write-Output "[$direction] Synced $count files."
