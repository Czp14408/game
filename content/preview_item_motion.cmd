@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
if not defined GODOT_CONSOLE set "GODOT_CONSOLE=D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
"%GODOT_CONSOLE%" --path godot_prototype --rendering-method gl_compatibility --script res://tests/item_motion_preview.gd
