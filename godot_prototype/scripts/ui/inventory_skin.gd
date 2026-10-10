class_name InventorySkin
extends RefCounted
## 共用面板布局访问层：旧美术清单提供资源，presentation.json 覆盖物品卡布局。
## 边界：只读资源 + 纯查表；不做布局决策，不承载业务规则。
## 依据：背包商店整理共用面板说明.md；资产由 tools/build_inventory_ui.py 生成。
##
## 为什么不把坐标写死在 GDScript 里：面板矩形、外框内腔与「两行物品横栏 + 底部操作条」
## 三段分区都由生成器按 alpha 与通腔比例测出来，界面层再抄一份，改素材或改布局时
## 就要同时改两处，必然漂移。此处只读 manifest。

const ROOT := "res://assets/ui/inventory_v1"
const MANIFEST_PATH := ROOT + "/manifest.json"

## 整块共用面板（背包、商店、整理三处同一张）
const PANEL := "panel"

## 面板内部三段分区（相对面板左上角）。名称与顺序固定，几何来自实测。
const ROW_A := "row_a"      ## 第一行物品横栏
const ROW_B := "row_b"      ## 第二行物品横栏
const OP_BAR := "op_bar"    ## 底部操作条（按模式显示适用操作）
const REGIONS: Array[String] = [ROW_A, ROW_B, OP_BAR]

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


static func rect(panel: String) -> Rect2i:
	return _rect_of(panel, "rect")


## 外框内腔矩形，坐标相对面板自身左上角。物品横栏与操作条都落在它里面。
static func inner(panel: String) -> Rect2i:
	return _rect_of(panel, "inner")


## 三段分区之一，坐标相对面板自身左上角。
static func region(panel: String, key: String) -> Rect2i:
	_ensure()
	var panels: Dictionary = _manifest.get("panels", {})
	if not panels.has(panel):
		return Rect2i()
	var regions: Dictionary = (panels[panel] as Dictionary).get("regions", {})
	if not regions.has(key):
		return Rect2i()
	return _arr_to_rect(regions[key])


## 三段分区之一，坐标落在设计画布上（面板位置 + 分区位置），可直接用于绝对定位。
static func region_abs(panel: String, key: String) -> Rect2i:
	var r := region(panel, key)
	if r.size.x <= 0:
		return Rect2i()
	return Rect2i(rect(panel).position + r.position, r.size)


## 可放内容的横向条带（面板局部坐标，start/x、end/y），自上而下与 REGIONS 同序。
static func bands_h(panel: String) -> Array[Vector2i]:
	_ensure()
	var out: Array[Vector2i] = []
	var panels: Dictionary = _manifest.get("panels", {})
	if not panels.has(panel):
		return out
	for pair in (panels[panel] as Dictionary).get("bands_h", []) as Array:
		var p: Array = pair
		if p.size() == 2:
			out.append(Vector2i(int(p[0]), int(p[1])))
	return out


## 某一行横栏的逻辑槽位数。界面按「净宽 ÷ 槽位数」算单位格宽，不烘焙格线。
static func slot_count(row: String) -> int:
	_ensure()
	var rows: Dictionary = _manifest.get("rows", {})
	return int(rows.get(row, 0))


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
	return _arr_to_rect((panels[panel] as Dictionary).get(key, []))


static func _arr_to_rect(arr: Variant) -> Rect2i:
	var a: Array = arr if arr is Array else []
	if a.size() != 4:
		return Rect2i()
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		_error = "缺少 %s，请先运行 tools/build_inventory_ui.py" % MANIFEST_PATH
		return
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_error = "%s 不是合法 JSON" % MANIFEST_PATH
		return
	_manifest = parsed
	# Item-card geometry is independent of the legacy baked panel artwork.
	var presentation: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/presentation.json"))
	if presentation is Dictionary:
		for key in presentation:
			_manifest["panels"][PANEL][key] = presentation[key]
	else:
		_error = "物品展示布局不是合法 JSON"
