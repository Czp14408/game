class_name PageBase
extends Control
## 页面基类：接收控制器与载荷，负责构建界面并转发命令。
## 构建入口为幂等的 ensure_built()，既可由 _ready 触发，也可由 AppRoot 显式触发，
## 从而在无画面脚本模式下（不派发 _ready）也能稳定构建。

var ctrl: RunController
var payload: Dictionary = {}
var catalog: ContentCatalog
var _built := false


func _init(p_ctrl: RunController = null, p_payload: Dictionary = {}) -> void:
	ctrl = p_ctrl
	payload = p_payload
	if ctrl != null:
		catalog = ctrl.catalog


func _ready() -> void:
	ensure_built()


func ensure_built() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	build()


func build() -> void:
	pass


func add_root(title: String) -> VBoxContainer:
	var r := UiKit.page_root(title)
	add_child(r)
	return r


func hud() -> String:
	var s := ctrl.state
	if s == null:
		return ""
	return "生命 %d/%d　货币 %d　战败 %d/%d　节点 %s　背包 %d/%d　战斗栏 %d/%d" % [
		int(s.current_hp), int(s.max_hp), s.money, s.defeats, RunState.MAX_DEFEATS,
		s.current_node_id, s.inventory_used(), RunState.INVENTORY_CAPACITY,
		s.bar_used(), RunState.BAR_CAPACITY,
	]


func item_line(it: ItemInstance) -> String:
	var def := catalog.item(it.definition_id)
	var growth := ""
	if it.trial_growth != 0.0:
		growth = "　试炼成长 +%.0f" % it.trial_growth
	return "%s（%s）%d 格%s" % [def.display_name, PriceTable.quality_name(it.quality), def.size, growth]
