class_name SystemSkin
extends RefCounted
## 系统组件 v1 的皮肤访问层：读取 assets/ui/system_components_v1/manifest.json
## （素材几何：纹理尺寸、源图裁框、内腔、九宫格边距）与同目录的 layout.json
## （页面坐标：每张面板在设计画布上的目标矩形）。
##
## 边界：只读资源 + 纯查表；不做布局决策，不承载业务规则。
## 依据：godot_prototype/assets/ui/system_components_v1/README.md；
## ui修改迭代工作流.md（生成器／清单／访问层／页面三层职责）。
##
## 为什么不把页面坐标写死在 GDScript 里：素材几何由生成器测出来，
## 页面坐标由生成器布局表定义，界面层再抄一份，改素材或改布局时
## 就要同时改两处，必然漂移。此处只读 manifest 与 layout。

const ROOT := "res://assets/ui/system_components_v1"
const MANIFEST_PATH := ROOT + "/manifest.json"
const LAYOUT_PATH := ROOT + "/layout.json"

## 七张系统组件名（与 manifest.json 的 assets 字段一致）
const INVENTORY_TRAY := "inventory_tray"           ## 底部背包连续十格底板
const STATUS_PANEL := "status_panel"               ## 背包上方状态栏底板
const INFORMATION_PANEL := "information_panel"     ## 信息页底板
const TOOLTIP_PANEL := "tooltip_panel"             ## 物品/技能/剩余机会共用说明框
const CONTEXT_MENU := "context_menu"               ## 背包物品右键菜单
const MINIMAP_FRAME := "minimap_frame"             ## 右上角小地图框
const BATTLE_STATISTICS := "battle_statistics"     ## 战斗界面统计抽屉

const PANELS: Array[String] = [
	INVENTORY_TRAY, STATUS_PANEL, INFORMATION_PANEL,
	TOOLTIP_PANEL, CONTEXT_MENU, MINIMAP_FRAME, BATTLE_STATISTICS,
]

## 设计画布尺寸（与战斗页、共用面板保持一致：1280×690 = 720 减去顶部 30 像素状态条）
const DESIGN_SIZE := Vector2i(1280, 690)

static var _manifest: Dictionary = {}
static var _layout: Dictionary = {}
static var _loaded := false
static var _error := ""


static func load_error() -> String:
	_ensure()
	return _error


static func manifest() -> Dictionary:
	_ensure()
	return _manifest


static func layout() -> Dictionary:
	_ensure()
	return _layout


static func design_size() -> Vector2i:
	return DESIGN_SIZE


## 素材几何：纹理尺寸（导出 PNG 的实际尺寸）
static func texture_size(panel: String) -> Vector2i:
	_ensure()
	var assets: Dictionary = _manifest.get("assets", {})
	if not assets.has(panel):
		return Vector2i.ZERO
	var sz: Array = (assets[panel] as Dictionary).get("size", [])
	if sz.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(sz[0]), int(sz[1]))


## 素材几何：内腔矩形（相对纹理左上角；minimap_frame 为 null）
static func inner(panel: String) -> Rect2i:
	_ensure()
	var assets: Dictionary = _manifest.get("assets", {})
	if not assets.has(panel):
		return Rect2i()
	var raw: Variant = (assets[panel] as Dictionary).get("inner")
	if not (raw is Array):
		return Rect2i()
	return _arr_to_rect(raw)


## 素材几何：九宫格边距 [左, 上, 右, 下]（minimap_frame 为 null）
static func nine_patch_margins(panel: String) -> Vector2i:
	# 返回 Vector2i 仅为兼容；实际四边值通过 nine_patch_margins_ltrb 取
	return Vector2i.ZERO


## 素材几何：九宫格边距 [左, 上, 右, 下]
## 注意：minimap_frame 在 manifest 里是 JSON null——Dictionary.get(key, default)
## 对「键存在但值为 null」返回 null 而非默认值，必须显式判空，否则
## 给 typed Array 赋 Nil 会报脚本错误并使函数中止。
static func nine_patch_margins_ltrb(panel: String) -> Array:
	_ensure()
	var assets: Dictionary = _manifest.get("assets", {})
	if not assets.has(panel):
		return [0, 0, 0, 0]
	var raw: Variant = (assets[panel] as Dictionary).get("nine_patch_margins_ltrb")
	if not (raw is Array):
		return [0, 0, 0, 0]
	var arr: Array = raw
	var out: Array = [0, 0, 0, 0]
	for i in mini(arr.size(), 4):
		out[i] = int(arr[i])
	return out


## 素材几何：中心 alpha（用于估算透明度，最终须叠到真实场景校准）
static func center_alpha(panel: String) -> int:
	_ensure()
	var assets: Dictionary = _manifest.get("assets", {})
	if not assets.has(panel):
		return 0
	return int((assets[panel] as Dictionary).get("center_alpha", 0))


## 推荐控件类型：NinePatchRect 或 TextureRect
static func control_kind(panel: String) -> String:
	_ensure()
	var assets: Dictionary = _manifest.get("assets", {})
	if not assets.has(panel):
		return "TextureRect"
	return String((assets[panel] as Dictionary).get("control", "TextureRect"))


## 页面坐标：面板在设计画布上的目标矩形
static func rect(panel: String) -> Rect2i:
	_ensure()
	var panels: Dictionary = _layout.get("panels", {})
	if not panels.has(panel):
		return Rect2i()
	return _arr_to_rect((panels[panel] as Dictionary).get("rect", []))


## 页面坐标：面板内某个命名子区（如状态栏内的「战斗栏」「技能栏」「数值条」）的矩形
static func region(panel: String, key: String) -> Rect2i:
	_ensure()
	var panels: Dictionary = _layout.get("panels", {})
	if not panels.has(panel):
		return Rect2i()
	var regions: Dictionary = (panels[panel] as Dictionary).get("regions", {})
	if not regions.has(key):
		return Rect2i()
	return _arr_to_rect(regions[key])


## 页面坐标：面板内某个命名子区，落位到设计画布上（面板位置 + 子区位置）
static func region_abs(panel: String, key: String) -> Rect2i:
	var r := region(panel, key)
	if r.size.x <= 0:
		return Rect2i()
	return Rect2i(rect(panel).position + r.position, r.size)


## 加载纹理资源
static func texture(panel: String) -> Texture2D:
	_ensure()
	var path := "%s/%s.png" % [ROOT, panel]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


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
		_error = "缺少 %s，请先运行 tools/build_system_components_ui.py" % MANIFEST_PATH
		return
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_error = "%s 不是合法 JSON" % MANIFEST_PATH
		return
	_manifest = parsed
	# layout.json 可选——首次跑生成器后才会有；缺失时 layout 字典保持空，rect() 返回零矩形
	if FileAccess.file_exists(LAYOUT_PATH):
		var ltext := FileAccess.get_file_as_string(LAYOUT_PATH)
		var lparsed: Variant = JSON.parse_string(ltext)
		if typeof(lparsed) == TYPE_DICTIONARY:
			_layout = lparsed
