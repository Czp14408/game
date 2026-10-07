#!/usr/bin/env bash
# 打包 Windows 便携试玩包。
#
# 说明：标准 .exe 导出需要与引擎同版本的导出模板
# （%APPDATA%/Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe）。
# 模板缺失时本脚本回退为「便携包」：随包附带同版本 Godot 运行程序 + 可编辑工程，
# 双击 run_game.bat 即在编辑器外直接运行游戏。
#
# 用法：bash tools/package_windows.sh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/d/Godot/Godot_v4.7.2-stable_win64.exe}"
GODOT_CONSOLE="${GODOT_CONSOLE:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}"
OUT_DIR="$GAME_DIR/dist/wudao_prototype"
PKG_PROJECT="$OUT_DIR/project"

if [[ ! -f "$GODOT_BIN" ]]; then
	echo "找不到 Godot 运行程序：$GODOT_BIN" >&2
	echo "可用 GODOT_BIN 环境变量指定路径。" >&2
	exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$PKG_PROJECT"

# 1) 工程本体（排除版本管理与导出产物）
cp -r "$PROJECT_DIR/." "$PKG_PROJECT/"
rm -rf "$PKG_PROJECT/.git" "$PKG_PROJECT/dist" "$PKG_PROJECT/build"

# 2) 引擎运行程序
cp "$GODOT_BIN" "$OUT_DIR/Godot_v4.7.2-stable_win64.exe"
if [[ -f "$GODOT_CONSOLE" ]]; then
	cp "$GODOT_CONSOLE" "$OUT_DIR/Godot_v4.7.2-stable_win64_console.exe"
fi

# 3) 启动脚本（只使用 %~dp0，不含非 ASCII 路径）
cat > "$OUT_DIR/run_game.bat" <<'BAT'
@echo off
setlocal
cd /d "%~dp0"
"Godot_v4.7.2-stable_win64.exe" --path "%~dp0project" %*
endlocal
BAT

cat > "$OUT_DIR/run_verify.bat" <<'BAT'
@echo off
setlocal
cd /d "%~dp0"
"Godot_v4.7.2-stable_win64.exe" --headless --path "%~dp0project" --script res://tests/headless_main.gd
echo 退出码：%ERRORLEVEL%
pause
endlocal
BAT

cat > "$OUT_DIR/run_autodemo.bat" <<'BAT'
@echo off
setlocal
cd /d "%~dp0"
"Godot_v4.7.2-stable_win64.exe" --headless --path "%~dp0project" -- --auto-demo 20261007
echo 退出码：%ERRORLEVEL%
pause
endlocal
BAT

cat > "$OUT_DIR/export_release.bat" <<'BAT'
@echo off
setlocal
cd /d "%~dp0"
echo 需要先安装同版本导出模板，然后本脚本产出标准单文件 exe。
"Godot_v4.7.2-stable_win64.exe" --headless --path "%~dp0project" --export-release "Windows Desktop" "%~dp0wudao_prototype.exe"
echo 退出码：%ERRORLEVEL%
pause
endlocal
BAT

cat > "$OUT_DIR/README.md" <<'MD'
# 武道试炼原型 · Windows 试玩包

这是「第一阶段可玩原型」的便携试玩包：随包附带同版本 Godot 运行程序与可编辑工程，
**不需要打开编辑器**，双击 `run_game.bat` 即可开始游玩。

## 怎么运行

| 脚本 | 作用 |
| --- | --- |
| `run_game.bat` | 开始游戏（键鼠） |
| `run_verify.bat` | 无画面规则与界面验证（621 项断言，需要控制台窗口） |
| `run_autodemo.bat` | 无画面自动演示：真实帧循环下走通整局 |
| `export_release.bat` | 产出标准单文件 `wudao_prototype.exe`（需先安装同版本导出模板） |

操作：`WASD`/方向键移动，`E` 交互，`Tab` 大地图，`B` 构筑，`Esc` 关闭界面/战斗中暂停，`F` 战斗中单步。

## 关于标准导出

标准导出需要与引擎同版本的导出模板：

```
%APPDATA%\Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe
```

本包未附带模板，因此 `run_game.bat` 使用同版本 Godot 运行程序以 `--path` 方式运行工程——
它**不打开编辑器**，但也不是单文件导出产物。装好模板后运行 `export_release.bat` 即可产出标准 exe。

## 目录

```
wudao_prototype/
├─ Godot_v4.7.2-stable_win64.exe          同版本运行程序
├─ run_game.bat / run_verify.bat / run_autodemo.bat / export_release.bat
└─ project/                                可编辑工程（data / scripts / scenes / tests / tools）
```

## 日志

每次试炼的 JSONL 事件日志与 JSON 摘要写在 `%APPDATA%\Godot\app_userdata\武道试炼原型\logs\`。

## 已知问题

完整清单见工程上级目录的 `游戏原型已知问题清单.md`，
其中明确区分了「已自动验证」与「需要人工在有显示环境下确认」的项。
MD

echo "已生成便携试玩包：$OUT_DIR"
ls -la "$OUT_DIR"
du -sh "$OUT_DIR"
