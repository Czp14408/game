@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
where py >nul 2>nul
if errorlevel 1 (
  python -X utf8 godot_prototype\tools\archive_items.py
) else (
  py -3 -X utf8 godot_prototype\tools\archive_items.py
)
set "ITEM_ARCHIVE_EXIT=%ERRORLEVEL%"
if /I not "%~1"=="--no-pause" pause
exit /b %ITEM_ARCHIVE_EXIT%
