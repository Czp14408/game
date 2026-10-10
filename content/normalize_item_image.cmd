@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
if defined ITEM_IMAGE_PYTHON goto run
set "ITEM_IMAGE_PYTHON=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if exist "%ITEM_IMAGE_PYTHON%" goto run
set "ITEM_IMAGE_PYTHON=python"
:run
"%ITEM_IMAGE_PYTHON%" -c "import PIL, tkinter" >nul 2>nul
if errorlevel 1 (
  echo 需要带 tkinter 和 Pillow 的 Python。请设置 ITEM_IMAGE_PYTHON 为对应 python.exe 路径。
  echo 安装 Pillow：python -m pip install Pillow
  pause
  exit /b 1
)
"%ITEM_IMAGE_PYTHON%" -X utf8 godot_prototype\tools\normalize_item_image.py %*
if errorlevel 1 pause
