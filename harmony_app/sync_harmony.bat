@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul

rem ============================================================
rem  harmony_app  and  D:\Harmony\HarmonyCleaner  source sync
rem  Only sync source and project config, exclude build outputs.
rem
rem  Usage:
rem    sync_harmony.bat push            harmony_app  -> HarmonyCleaner
rem    sync_harmony.bat pull            HarmonyCleaner -> harmony_app
rem    sync_harmony.bat push preview    preview only (no change)
rem    sync_harmony.bat pull  preview   preview only (no change)
rem ============================================================

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"
set "WS=D:\Harmony\HarmonyCleaner"

set "XD=oh_modules node_modules .idea .hvigor .cxx build .test .preview .appanalyzer .git .clangd"
set "XF=local.properties oh-package-lock.json5 .clang-format .clang-tidy *.log"

set "MODE=%~1"
set "OPT=%~2"

if /i "%MODE%"=="push" (
  set "FROM=%SRC%"
  set "TO=%WS%"
) else if /i "%MODE%"=="pull" (
  set "FROM=%WS%"
  set "TO=%SRC%"
) else (
  echo.
  echo  Usage: sync_harmony.bat [push^|pull] [preview]
  echo    push = harmony_app  -^> HarmonyCleaner
  echo    pull = HarmonyCleaner -^> harmony_app
  echo    2nd arg "preview" = dry run
  echo.
  exit /b 1
)

if not exist "%FROM%\" ( echo [ERROR] source not found: %FROM% & exit /b 2 )

set "DRY="
if /i "%OPT%"=="preview" set "DRY=/L"

echo.
echo ============================================================
echo  FROM: %FROM%
echo  TO:   %TO%
if defined DRY echo  MODE: PREVIEW (no change)
echo ============================================================
echo.

robocopy "%FROM%" "%TO%" /MIR %DRY% /XD %XD% /XF %XF% /NP /R:1 /W:1 /NDL /XX
set "RC=%ERRORLEVEL%"

echo.
if %RC% GEQ 8 (
  echo [FAILED] robocopy exit code %RC%
  exit /b %RC%
)
echo [DONE] robocopy exit code %RC%  (0-7 = success)
exit /b 0
