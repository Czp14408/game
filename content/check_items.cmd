@echo off
chcp 65001 >nul
setlocal
call "%~dp0update_items.cmd" --check
set "ITEM_CHECK_EXIT=%ERRORLEVEL%"
echo.
if "%ITEM_CHECK_EXIT%"=="0" (
  echo 校验通过。本次未修改 Excel 或游戏内容；正式应用请运行 update_items.cmd。
) else (
  echo 校验失败。本次未修改 Excel 或游戏内容；请按提示修正后重试。
)
echo 最近报告可用 view_item_report.cmd 查看，请核对报告时间。
if /I not "%~1"=="--no-pause" pause
exit /b %ITEM_CHECK_EXIT%
