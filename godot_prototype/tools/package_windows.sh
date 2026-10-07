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

# 优先重建整个输出目录；若旧包正被占用（例如试玩窗口还开着）无法删除，
# 则降级为就地覆盖更新——包内容仍是最新的，只是旧包里的陈旧文件不会被清理。
if ! rm -rf "$OUT_DIR"; then
	echo "注意：旧包目录未能删除（可能正被运行中的游戏占用），已改为就地覆盖更新。" >&2
	echo "      若要得到干净的重建结果，请先关闭游戏窗口再重跑本脚本。" >&2
fi
mkdir -p "$PKG_PROJECT"

# 1) 工程本体（排除版本管理与导出产物）
cp -r "$PROJECT_DIR/." "$PKG_PROJECT/"
rm -rf "$PKG_PROJECT/.git" "$PKG_PROJECT/dist" "$PKG_PROJECT/build"

# 2) 引擎运行程序
# 内容一致时直接跳过：某些环境下对已存在的同名大文件重写会被拒（Device or resource busy），
# 而文件其实完全相同，此时不该中断整次打包。
copy_binary() {
	local src="$1" dst="$2"
	if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
		echo "跳过（内容一致）：$(basename "$dst")"
		return 0
	fi
	if cp "$src" "$dst" 2>/dev/null; then
		return 0
	fi
	if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
		echo "跳过（覆盖被拒但内容一致）：$(basename "$dst")"
		return 0
	fi
	echo "警告：无法更新 $(basename "$dst")，包内该文件可能不是最新版本。" >&2
	return 1
}

copy_binary "$GODOT_BIN" "$OUT_DIR/Godot_v4.7.2-stable_win64.exe" || true
if [[ -f "$GODOT_CONSOLE" ]]; then
	copy_binary "$GODOT_CONSOLE" "$OUT_DIR/Godot_v4.7.2-stable_win64_console.exe" || true
fi

# 2.5) 随包附带验收文档，便于试玩者按项核对
for doc in "人工验收清单.md" "游戏原型已知问题清单.md" "R0收尾证据.md"; do
	if [[ -f "$GAME_DIR/$doc" ]]; then
		cp "$GAME_DIR/$doc" "$OUT_DIR/$doc"
	fi
done

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

cat > "$OUT_DIR/run_screenshots.bat" <<'BAT'
@echo off
setlocal
cd /d "%~dp0"
rem 真实渲染下逐页截图并做布局断言（需要显示环境，不能加 --headless）
"Godot_v4.7.2-stable_win64.exe" --path "%~dp0project" -- --screenshots "%~dp0screenshots"
echo 退出码：%ERRORLEVEL%
pause
endlocal
BAT

cat > "$OUT_DIR/run_evidence.bat" <<'BAT'
@echo off
setlocal
cd /d "%~dp0"
rem 重新生成 R0 收尾的三份证据（复演账本 / 构筑方向样本 / 背包容量压力样本）
set G=Godot_v4.7.2-stable_win64_console.exe
"%G%" --headless --path "%~dp0project" --script res://tests/replay_ledger.gd  -- --out "%~dp0evidence"
"%G%" --headless --path "%~dp0project" --script res://tests/build_samples.gd  -- --out "%~dp0evidence"
"%G%" --headless --path "%~dp0project" --script res://tests/carry_pressure.gd -- --out "%~dp0evidence"
echo 证据已写入 %~dp0evidence
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
| `run_verify.bat` | 无画面规则与界面验证（当前 646 项断言，需要控制台窗口） |
| `run_autodemo.bat` | 无画面自动演示：真实帧循环下走通整局 |
| `run_screenshots.bat` | 真实渲染下逐页截图 + 布局断言（需要显示环境，产出 `screenshots/`） |
| `run_evidence.bat` | 重新生成三份 R0 证据（复演账本 / 构筑方向样本 / 背包容量压力），产出 `evidence/` |
| `export_release.bat` | 产出标准单文件 `wudao_prototype.exe`（需先安装同版本导出模板） |

操作：`WASD`/方向键移动，`E` 交互，`Tab` 打开/收起大地图，`B` 构筑（仅小地图），`Esc` 战斗中暂停/继续，`F` 战斗中单步。
商店、构筑、战前等界面用界面内的按钮返回。

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
├─ run_game.bat / run_verify.bat / run_autodemo.bat / run_screenshots.bat
├─ run_evidence.bat / export_release.bat
└─ project/                                可编辑工程（data / scripts / scenes / tests / tools）
```

## 日志

每次试炼的 JSONL 事件日志与 JSON 摘要写在 `%APPDATA%\Godot\app_userdata\武道试炼原型\logs\`。

## 已知问题与人工验收

完整清单见包内的 `游戏原型已知问题清单.md`，其中明确区分了「已自动验证」与「需要人工在有显示环境下确认」的项。

需要真人操作核对的项见包内 `人工验收清单.md`（A–J 十组，含键鼠手感、中文缺字、窗口缩放、
满包可继续操作、三条路线的玩法验收与 15 分钟节奏观察）。

## 可复查的证据

`R0收尾证据.md` 汇总了三条固定路线的逐场账本、三类构筑方向的供给样本与背包容量压力样本，
并给出与设计文档的逐项对照（含一处尚未成立的方向，如实记录）。
运行 `run_evidence.bat` 可在本包内重新生成全部三份证据。
MD

echo "已生成便携试玩包：$OUT_DIR"
ls -la "$OUT_DIR"
du -sh "$OUT_DIR"
