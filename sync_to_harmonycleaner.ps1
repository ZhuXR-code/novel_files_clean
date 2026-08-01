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

Write-Output "[$direction] Synced $count files."
