# =====================================================================
# sync_to_harmonycleaner.ps1
# Dual-project sync: harmony_app <-> HarmonyCleaner
#
# Usage:
#   .\sync_to_harmonycleaner.ps1           # harmony_app -> HarmonyCleaner (default)
#   .\sync_to_harmonycleaner.ps1 -Reverse  # HarmonyCleaner -> harmony_app
#
# harmony_app is the source project (edited by AI); HarmonyCleaner is the
# DevEco debug workspace. Their code must stay in sync. This script does a
# full sync of ets/ts source files.
#
# NOTE: The project path contains non-ASCII characters. We derive it from
# $PSScriptRoot at runtime instead of a hardcoded literal, so the script is
# not misread under an ANSI (GBK) codepage. All content below is ASCII-only.
# =====================================================================
param([switch]$Reverse)

$projectRoot = $PSScriptRoot
if (-not $projectRoot) {
    $projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$srcBase = Join-Path $projectRoot "harmony_app\entry\src\main\ets"
$dstBase = "D:\Harmony\HarmonyCleaner\entry\src\main\ets"

if ($Reverse) {
    $srcBase = "D:\Harmony\HarmonyCleaner\entry\src\main\ets"
    $dstBase = Join-Path $projectRoot "harmony_app\entry\src\main\ets"
    $direction = "HarmonyCleaner -> harmony_app"
} else {
    $direction = "harmony_app -> HarmonyCleaner"
}

if (-not (Test-Path $srcBase)) {
    Write-Output "ERROR: Source path not found: $srcBase"
    exit 1
}
if (-not (Test-Path $dstBase)) {
    Write-Output "ERROR: Destination path not found: $dstBase"
    Write-Output "Ensure DevEco workspace D:\Harmony\HarmonyCleaner exists."
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

Write-Output "[$direction] Synced $count ets/ts files."

# ---------------------------------------------------------------------
# Sync resources and module.json5 (not covered by the ets glob above).
# These directories use the same layout under entry\src\main.
# ---------------------------------------------------------------------
$srcMain = Join-Path $projectRoot "harmony_app\entry\src\main"
$dstMain = "D:\Harmony\HarmonyCleaner\entry\src\main"
if ($Reverse) {
    $srcMain = "D:\Harmony\HarmonyCleaner\entry\src\main"
    $dstMain = Join-Path $projectRoot "harmony_app\entry\src\main"
}

# resources (icons, strings, colors, media ...)
$srcRes = Join-Path $srcMain "resources"
$dstRes = Join-Path $dstMain "resources"
$resCount = 0
if (Test-Path $srcRes) {
    Get-ChildItem -Path $srcRes -Recurse | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
        $rel = $_.FullName.Substring($srcRes.Length)
        $target = Join-Path $dstRes $rel
        $targetDir = Split-Path $target -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item $_.FullName $target -Force
        $resCount++
    }
}
Write-Output "[$direction] Synced $resCount resource files."

# module.json5
$srcMod = Join-Path $srcMain "module.json5"
$dstMod = Join-Path $dstMain "module.json5"
if (Test-Path $srcMod) {
    Copy-Item $srcMod $dstMod -Force
    Write-Output "[$direction] Synced module.json5."
}
