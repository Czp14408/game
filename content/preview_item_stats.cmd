@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
if not defined GODOT_CONSOLE set "GODOT_CONSOLE=D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
"%GODOT_CONSOLE%" --headless --path godot_prototype --editor --import --quit
if errorlevel 1 exit /b %ERRORLEVEL%
"%GODOT_CONSOLE%" --path godot_prototype --rendering-method gl_compatibility --script res://tests/item_stats_preview.gd
