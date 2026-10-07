class_name MapCanvas
extends Control
## 大地图画布：绘制 18 节点与双向连接，标出当前位置、可前往节点、费用与守路。
## 边界：只读状态、只画图；是否可前往由 WorldService 判定，本画布不修改任何状态。

signal node_clicked(node_id: String)

const NODE_RADIUS := 15.0
const CLICK_RADIUS := 22.0
const MARGIN := 58.0

var state: RunState
var world_def: WorldDef
var world_service: WorldService
var catalog: ContentCatalog
var hovered: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func reachable(node_id: String) -> bool:
	if state == null or world_def == null:
		return false
	if state.current_node_id == "":
		return node_id == world_def.entry_node_id
	return world_def.neighbors(state.current_node_id).has(node_id)


func fee_of(node_id: String) -> int:
	if world_service == null or state == null:
		return 0
	return world_service.entry_fee(state, node_id)


func _discovered(node_id: String) -> bool:
	if state == null:
		return false
	return state.node_state(node_id).entered


func _is_blocked(conn: ConnectionDef) -> bool:
	if world_service == null or state == null or conn.guard_enemy_id == &"":
		return false
	return world_service.is_connection_blocked(state, conn.node_a, conn.node_b)


func _intel_text(node_id: String) -> String:
	var nd := world_def.node_by_id(node_id) if world_def != null else null
	if nd == null or state == null:
		return ""
	if nd.is_main_target and state.known_intel.has("chief_node"):
		return "已知：主线目标"
	if nd.layout == NodeDef.LAYOUT_CAMP and state.known_intel.has("bandit_area"):
		return "已知：土匪活动区"
	return ""


func _plot(v: Vector2) -> Vector2:
	var inner := Vector2(maxf(size.x - MARGIN * 2.0, 1.0), maxf(size.y - MARGIN * 2.0, 1.0))
	return Vector2(MARGIN, MARGIN) + Vector2(v.x * inner.x, v.y * inner.y)


func _node_at(local_pos: Vector2) -> String:
	if world_def == null:
		return ""
	var best := ""
	var best_d := CLICK_RADIUS
	for nid in MapLayout.POSITIONS.keys():
		var d := local_pos.distance_to(_plot(MapLayout.position_of(nid)))
		if d <= best_d:
			best_d = d
			best = nid
	return best


func _draw() -> void:
	if world_def == null or state == null:
		return
	var font := get_theme_default_font()
	for conn in world_def.connections:
		var a := _plot(MapLayout.position_of(conn.node_a))
		var b := _plot(MapLayout.position_of(conn.node_b))
		var col := Color(0.30, 0.30, 0.36)
		var width := 1.5
		if _discovered(conn.node_a) or _discovered(conn.node_b):
			col = Color(0.40, 0.42, 0.50)
			width = 2.0
		if _is_blocked(conn):
			col = Color(0.70, 0.36, 0.30)
			width = 3.0
		draw_line(a, b, col, width)
		if _is_blocked(conn):
			_centered(font, (a + b) * 0.5 + Vector2(0.0, -6.0), "守路", 12, Color(0.92, 0.56, 0.46))
	for nid in MapLayout.POSITIONS.keys():
		_draw_node(font, nid)


func _draw_node(font: Font, nid: String) -> void:
	var c := _plot(MapLayout.position_of(nid))
	var discovered := _discovered(nid)
	var is_cur := state.current_node_id == nid
	var reach := reachable(nid)
	var nd := world_def.node_by_id(nid)

	var fill := Color(0.17, 0.17, 0.20)
	if discovered:
		fill = Color(0.25, 0.29, 0.37)
	if reach:
		fill = Color(0.22, 0.33, 0.28)
	if hovered == nid and reach:
		fill = Color(0.30, 0.46, 0.38)

	var outline := Color(0.38, 0.38, 0.44)
	var outline_w := 1.5
	if reach:
		outline = Color(0.52, 0.80, 0.58)
		outline_w = 2.5
	if is_cur:
		outline = UiKit.COL_ACCENT
		outline_w = 3.0
	if nd != null and nd.is_main_target and state.known_intel.has("chief_node") and not discovered:
		outline = UiKit.COL_ENEMY
		outline_w = 2.5

	draw_circle(c, NODE_RADIUS, fill)
	draw_arc(c, NODE_RADIUS, 0.0, TAU, 32, outline, outline_w, true)
	var num_col := UiKit.COL_TEXT if (discovered or reach) else UiKit.COL_MUTED
	_centered(font, c + Vector2(0.0, 4.0), nid, 13, num_col)

	if reach and not is_cur:
		var fee := fee_of(nid)
		_centered(font, c + Vector2(0.0, -NODE_RADIUS - 5.0), "免费" if fee == 0 else "%d" % fee, 12, UiKit.COL_ACCENT)

	var sub := ""
	if nd != null and (discovered or is_cur):
		sub = nd.display_name
	else:
		sub = _intel_text(nid)
	if sub != "":
		_centered(font, c + Vector2(0.0, NODE_RADIUS + 16.0), sub, 12, UiKit.COL_MUTED)


## 以 pos 为水平中心、pos.y 为基线的居中文字
func _centered(font: Font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	if font == null:
		return
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, pos - Vector2(sz.x * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _node_at((event as InputEventMouseMotion).position)
		if h != hovered:
			hovered = h
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var n := _node_at(mb.position)
			if n != "":
				node_clicked.emit(n)
