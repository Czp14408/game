class_name BattleSkin
extends RefCounted
## 战斗界面皮肤访问层：面板纹理与布局矩形统一来自生成器产出的 manifest。
## 边界：只读资源 + 纯查表；不做布局决策，不承载业务规则。
## 依据：战斗UI组件与组合说明.md §1–§2；资产由 tools/build_battle_ui.py 生成。
##
## 为什么不把坐标写死在 GDScript 里：布局表与九宫格参数由生成器决定，
## 若界面层再抄一份，改布局时要同时改两处，必然漂移。此处只读 manifest。

const ROOT := "res://assets/ui/battle_v1"
const MANIFEST_PATH := ROOT + "/manifest.json"

## 单侧面板基名（实际键为 <基名>_<side>，side 见 SIDE_*）
const PORTRAIT := "portrait"
const NAME := "name"
const STATUS := "status"
const SKILL := "skill"
const HEALTH := "health"
const TRAY := "tray"

## 双方面板共用、无侧别的面板
const MIDDLE := "middle"
const OPERATIONS := "operations"
const MODAL := "modal"

const SIDE_ENEMY := "enemy"
const SIDE_PLAYER := "player"
const SIDES: Array[String] = [SIDE_ENEMY, SIDE_PLAYER]

static var _manifest: Dictionary = {}
static var _loaded := false
static var _error := ""


static func manifest() -> Dictionary:
	_ensure()
	return _manifest


static func load_error() -> String:
	_ensure()
	return _error


static func design_size() -> Vector2i:
	_ensure()
	var d: Array = _manifest.get("design", [])
	if d.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(d[0]), int(d[1]))


static func has_panel(panel: String) -> bool:
	_ensure()
	return (_manifest.get("panels", {}) as Dictionary).has(panel)


static func panel_names() -> PackedStringArray:
	_ensure()
	var out := PackedStringArray()
	for k in (_manifest.get("panels", {}) as Dictionary).keys():
		out.append(String(k))
	out.sort()
	return out


## 侧别面板键：BattleSkin.side_panel(BattleSkin.TRAY, BattleSkin.SIDE_PLAYER) -> "tray_player"
static func side_panel(base: String, side: String) -> String:
	return "%s_%s" % [base, side]


static func rect(panel: String) -> Rect2i:
	return _rect_of(panel, "rect")


## 内腔矩形，坐标相对面板自身左上角。生命填充、十格线与文字都按它对齐。
static func inner(panel: String) -> Rect2i:
	return _rect_of(panel, "inner")


## 可放内容的横向条带（面板局部坐标，start/x、end/y）。
## 单腔面板只有一条，等于内腔；带内部横向分隔的面板会被切成多段
## （操作栏就是三段：顶部状态、中部操作与记录、底部退出）。
static func bands_h(panel: String) -> Array[Vector2i]:
	return _bands(panel, "bands_h")


static func bands_v(panel: String) -> Array[Vector2i]:
	return _bands(panel, "bands_v")


static func texture(panel: String) -> Texture2D:
	_ensure()
	var path := "%s/%s.png" % [ROOT, panel]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _rect_of(panel: String, key: String) -> Rect2i:
	_ensure()
	var panels: Dictionary = _manifest.get("panels", {})
	if not panels.has(panel):
		return Rect2i()
	var arr: Array = (panels[panel] as Dictionary).get(key, [])
	if arr.size() != 4:
		return Rect2i()
	return Rect2i(int(arr[0]), int(arr[1]), int(arr[2]), int(arr[3]))


static func _bands(panel: String, key: String) -> Array[Vector2i]:
	_ensure()
	var out: Array[Vector2i] = []
	var panels: Dictionary = _manifest.get("panels", {})
	if not panels.has(panel):
		return out
	for pair in (panels[panel] as Dictionary).get(key, []) as Array:
		var p: Array = pair
		if p.size() == 2:
			out.append(Vector2i(int(p[0]), int(p[1])))
	return out


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		_error = "缺少 %s，请先运行 tools/build_battle_ui.py" % MANIFEST_PATH
		return
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_error = "%s 不是合法 JSON" % MANIFEST_PATH
		return
	_manifest = parsed
