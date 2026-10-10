@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
call content\update_items.cmd --workbook content\items.xlsx
if errorlevel 1 (pause & exit /b 1)
if not defined GODOT_CONSOLE set "GODOT_CONSOLE=D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT_CONSOLE%" (
    echo Set GODOT_CONSOLE to your Godot console executable path.
    pause
    exit /b 1
)
"%GODOT_CONSOLE%" --headless --path godot_prototype --editor --import --quit
if errorlevel 1 (pause & exit /b 1)
"%GODOT_CONSOLE%" --path godot_prototype -- --preview-item poison_vial
if errorlevel 1 pause
