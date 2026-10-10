@echo off
chcp 65001 >nul
if not exist "%~dp0reports\latest.html" (
  echo 请先运行 update_items.cmd 生成验收报告。
  pause
  exit /b 1
)
start "" "%~dp0reports\latest.html"
