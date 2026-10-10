@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
where py >nul 2>nul
if errorlevel 1 (
    python -X utf8 godot_prototype\tools\import_items.py %*
) else (
    py -3 -X utf8 godot_prototype\tools\import_items.py %*
)
set "ITEM_EXIT=%ERRORLEVEL%"
if not "%ITEM_EXIT%"=="0" echo Content was not updated. Fix the cell reported above and retry.
if "%~1"=="" pause
exit /b %ITEM_EXIT%
