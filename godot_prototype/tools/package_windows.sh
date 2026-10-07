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

# README 里的断言项数从实际跑一次的结果里取，写死会在下次加断言后静默过期
# （曾因此 README 与包内文档长期写着 779，而实际已是 890）。
# 取不到就退回「未测」而不是编一个数。
# 两个套件的输出格式不同，都认：
#   无画面  「===== 合计：通过 890，失败 0 =====」
#   截图    「[界面截图验证] 通过 128，失败 0，输出 …」
extract_pass_count() {
	sed -n 's/.*合计：通过 *\([0-9]\+\).*/\1/p;s/.*] 通过 *\([0-9]\+\).*/\1/p' "$1" | tail -1
}

read_assert_count() {
	local log count
	log="$(mktemp)"
	"$GODOT_CONSOLE" --headless --path "$PROJECT_DIR" \
		--script res://tests/headless_main.gd > "$log" 2>&1 || true
	count="$(extract_pass_count "$log")"
	rm -f "$log"
	[[ -n "$count" ]] && printf '%s' "$count" || printf '未测'
}

read_shot_count() {
	# 真渲染截图套件需要显示环境且要跑 2 分钟，打包时默认**不重跑**。
	# 传入 WD_SHOT_COUNT 用当次实测值；没传就如实写「未测」，不猜数字。
	# 想让它自己量：WD_SHOT_COUNT=auto bash tools/package_windows.sh
	if [[ "${WD_SHOT_COUNT:-}" == "auto" ]]; then
		local log count tmp
		log="$(mktemp)"
		tmp="$(mktemp -d)"
		"$GODOT_CONSOLE" --path "$PROJECT_DIR" -- --screenshots "$tmp" > "$log" 2>&1 || true
		count="$(extract_pass_count "$log")"
		rm -rf "$log" "$tmp"
		[[ -n "$count" ]] && { printf '%s' "$count"; return; }
	fi
	if [[ -n "${WD_SHOT_COUNT:-}" ]]; then
		printf '%s' "${WD_SHOT_COUNT}"
	else
		printf '未测（需显示环境）'
	fi
}

if [[ -f "$GODOT_CONSOLE" ]]; then
	echo "读取当前无画面断言项数（供 README 使用）……"
	HEADLESS_COUNT="$(read_assert_count)"
else
	HEADLESS_COUNT="未测"
fi
SHOT_COUNT="$(read_shot_count)"
echo "  无画面 ${HEADLESS_COUNT} 项 / 真渲染 ${SHOT_COUNT} 项"

cat > "$OUT_DIR/README.md" <<'MD'
# 武道试炼原型 · Windows 试玩包

这是「第一阶段可玩原型」的便携试玩包：随包附带同版本 Godot 运行程序与可编辑工程，
**不需要打开编辑器**，双击 `run_game.bat` 即可开始游玩。

## 怎么运行

| 脚本 | 作用 |
| --- | --- |
| `run_game.bat` | 开始游戏（键鼠） |
| `run_verify.bat` | 无画面规则与界面验证（当前 __HEADLESS_COUNT__ 项断言，需要控制台窗口） |
| `run_autodemo.bat` | 无画面自动演示：真实帧循环下走通整局 |
| `run_screenshots.bat` | 真实渲染下逐页截图 + 布局断言（当前 __SHOT_COUNT__ 项，需要显示环境，产出 `screenshots/`） |
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

需要真人操作核对的项见包内 `人工验收清单.md`（A–M 十三组，含键鼠手感、中文缺字、窗口缩放、
满包可继续操作、三条路线的玩法验收与 15 分钟节奏观察）。
其中 K 组是主角形象的观感验收：形象是否锐利、朝向是否看得懂、有没有挡住交互点——
这些自动化能证明「素材加载到了正确位置」，证明不了「看起来别不别扭」。
L 组是战斗界面观感验收：木框拼接口是否变形、生命槽与十格栏是否整齐、战斗记录是否每条一行——
自动化能证明「面板落到了清单矩形、内腔没被越界、日志有内容」，证明不了「看着顺不顺眼」。
M 组是背包／商店共用面板的观感验收：格线是否均匀、格内文字有没有被裁、商店上排是否被误读成二十格容量——
自动化能证明「面板落到了清单矩形、格宽由净宽换算、货位数正确」，证明不了「看着挤不挤」。

## 背包／商店共用面板

构筑与整理页、商店页的背包栏用同一张面板（`project/assets/ui/inventory_v1/panel.png`），
两处零改动复用。面板矩形与分区全部来自 `manifest.json`，界面层不写死坐标；
换素材只需重跑 `project/tools/build_inventory_ui.py`。偏差与实测值见《背包商店整理共用面板说明.md》「接入结果」。
已知的**有意取舍**（不是缺陷）：格子里只有文字没有物品图形（图标属R5 美术）、
商店上排只启用 4 个货位而不是画满二十格模板。完整清单见包内 `游戏原型已知问题清单.md` §9.7。

## 战斗界面

战斗页按《战斗UI组件与组合说明.md》§1–§2 用组件素材拼成固定布局：上下两方同构（头像／名称／状态／
技能／生命槽／十格物品栏），中间计时条，右侧操作栏分三段（战斗状态／操作与战斗记录／退出）。
面板矩形与内腔全部来自 `project/assets/ui/battle_v1/manifest.json`，界面层不写死坐标；
换素材只需重跑 `project/tools/build_battle_ui.py`。偏差与实测值见该说明文档 §6。

## 主角形象

主角形象取自一张 5×5 像素动作表，已切成四方向行走序列与 10 张语义姿势帧，落在 `project/assets/hero/`，
分别用在：开局页立绘、战斗页玩家侧头像、结算页三种结局立绘、小地图四方向行进指示物。
切图工具为 `project/tools/slice_hero_sheet.py`，换素材后重跑即可，不手工改图。
该画风已确定为后续美术的**基准方向**。已知缺口（无对手形象、单形象无法区分职业血统）见已知问题清单 §9.5。

## 可复查的证据

`R0收尾证据.md` 汇总了三条固定路线的逐场账本、三类构筑方向的供给样本与背包容量压力样本，
并给出与设计文档的逐项对照（含一处尚未成立的方向，如实记录）。
运行 `run_evidence.bat` 可在本包内重新生成全部三份证据。
MD

# 占位符在 heredoc 写完之后替换：模板正文全是 Markdown 反引号，
# 放进可展开 heredoc 会被 shell 当子命令执行，所以保持单引号 heredoc 不动。
sed -i "s/__HEADLESS_COUNT__/${HEADLESS_COUNT}/g; s/__SHOT_COUNT__/${SHOT_COUNT}/g" \
	"$OUT_DIR/README.md"

echo "已生成便携试玩包：$OUT_DIR"
ls -la "$OUT_DIR"
du -sh "$OUT_DIR"

# 4) 陈旧检测：包里最容易出现「跑起来看不到新效果」的情况——
#    工作区已经改完界面，试玩包还是上一次打包的旧工程。
#    这里比对两个来源的 mtime（新的那个更新 = 旧包）并直接报出来，
#    免得下次以为是改动没生效、白查代码。
STALE="$(find "$PROJECT_DIR/assets" "$PROJECT_DIR/scripts" "$PROJECT_DIR/data" \
	"$PROJECT_DIR/scenes" -type f -newer "$OUT_DIR/run_game.bat" -print 2>/dev/null | head -5)"
if [[ -n "$STALE" ]]; then
	echo "警告：包内 run_game.bat 比工程里这些文件旧，试玩包可能是上一版：" >&2
	echo "$STALE" | sed 's/^/      /' >&2
	echo "      请重新运行 tools/package_windows.sh。" >&2
fi
