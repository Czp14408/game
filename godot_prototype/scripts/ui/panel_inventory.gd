class_name PanelInventory
extends Control
## 背包、商店、整理共用的右侧面板：一块面板贴图 + 两行物品横栏 + 底部操作条。
## 依据：背包商店整理共用面板说明.md（视觉与布局）、ui修改迭代工作流.md（接入工序）。
## 边界：只负责把清单给的位置摆出来（贴图、单位格线、物品格、操作按钮），
## 哪件物品、能不能点、点了做什么，全部由页面通过 entries / ops 传进来。
##
## 为什么不套容器：面板边框、内部两条横栏的圆角都要求像素级对齐，容器会把子节点
## 按最小尺寸重排（工作流 §5.4）。这里全部绝对定位，矩形一律取自 InventorySkin。

signal cell_selected(row: String, index: int, entries_index: int)
signal op_pressed(op_id: String)

const CELL_PAD := 3          ## 物品格内边距
const CELL_FOOT_H := 12      ## 物品格底部小字行高
const CELL_TEXT_INSET := 4   ## 文字块离格边的距离：字形会溢出文本框 1 像素，贴边就会被裁掉
const OP_GAP := 6            ## 操作按钮间距
const OP_MIN_W := 64         ## 操作按钮最小宽度
const OP_MAX_W := 120        ## 操作按钮最大宽度
const OP_TEXT_INSET := 3     ## 操作条同样留出字形溢出余量

var _built := false
var _rows: Dictionary = {}          ## row -> {holder, field, cells, entries}
var _op_bar: Control
var _op_buttons: Dictionary = {}    ## op id -> Button
var _selected := ""                 ## 当前选中物品的 id（空表示未选中）


## 单位格与格线：格宽 = 横栏净宽 ÷ 槽位数，物品边框不得改变单位格宽（工作流 §6.2）。
## 未启用的格位不画格线——模板是二十格，但背包十点、商店四货位，
## 画出来就会被当成额外容量（说明文档「实际有效范围需按玩法规则启用」）。
class SlotField:
	extends Control

	var slot_count := 10
	var enabled_count := 10
	var line_color := Color(0.90, 0.96, 1.0, 0.20)
	var cap_color := Color(0.72, 0.88, 1.0, 0.45)

	func _draw() -> void:
		var n := maxi(slot_count, 1)
		var w := size.x / float(n)
		var upto := clampi(enabled_count, 0, n)
		for i in range(upto + 1):
			var x := roundf(i * w)
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), line_color, 1.0)
		if upto < n and upto > 0:
			# 右端封口：把「启用到这里」画成一条闭合的边，剩下的留白不带格线
			var xb := roundf(upto * w) - 0.5
			draw_line(Vector2(xb, 0.0), Vector2(xb, size.y), cap_color, 1.0)
			draw_line(Vector2(0.0, 0.5), Vector2(xb, 0.5), cap_color, 1.0)
			draw_line(Vector2(0.0, size.y - 0.5), Vector2(xb, size.y - 0.5), cap_color, 1.0)

	## 第 index 格起、跨 span 格的矩形（相对本控件）
	func cell_rect(index: int, span: int) -> Rect2:
		var n := maxi(slot_count, 1)
		var w := size.x / float(n)
		var lo := clampi(index, 0, n)
		var hi := clampi(index + maxi(span, 1), 0, n)
		var x0 := roundf(lo * w)
		var x1 := roundf(hi * w)
		return Rect2(x0, 0.0, maxf(x1 - x0, 1.0), size.y)


static func row_order() -> Array[String]:
	return [InventorySkin.ROW_A, InventorySkin.ROW_B]


func build() -> void:
	if _built:
		return
	_built = true
	name = "PanelInventory"
	mouse_filter = Control.MOUSE_FILTER_PASS
	var rect := InventorySkin.rect(InventorySkin.PANEL)
	position = Vector2(rect.position)
	size = Vector2(rect.size)

	var art := UiKit.panel_art(InventorySkin.texture(InventorySkin.PANEL),
		Rect2i(Vector2i.ZERO, rect.size))
	art.name = "PanelArt"
	add_child(art)

	for row in row_order():
		var r := InventorySkin.region(InventorySkin.PANEL, row)
		var holder := Control.new()
		holder.name = "Row_%s" % row
		holder.position = Vector2(r.position)
		holder.size = Vector2(r.size)
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(holder)

		var field := SlotField.new()
		field.name = "Slots_%s" % row
		field.slot_count = maxi(InventorySkin.slot_count(row), 1)
		field.enabled_count = field.slot_count
		field.position = Vector2.ZERO
		field.size = Vector2(r.size)
		field.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(field)

		_rows[row] = {"holder": holder, "field": field, "cells": [], "entries": []}

	var op := InventorySkin.region(InventorySkin.PANEL, InventorySkin.OP_BAR)
	_op_bar = Control.new()
	_op_bar.name = "OpBar"
	_op_bar.position = Vector2(op.position)
	_op_bar.size = Vector2(op.size)
	_op_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_op_bar)


## 铺一行物品。entries 里每项是一个字典：
##   id 唯一标识 | name 主标题 | sub 底部小字 | quality 品质档（-1 表示无）
##   size 占几格 | enabled 是否可点
## capacity 是本行**启用**的单位格数（默认等于模板槽位数）；小于槽位数时后半段不画格线。
func set_row(row: String, entries: Array, capacity: int = -1) -> void:
	if not _rows.has(row):
		return
	var info: Dictionary = _rows[row]
	var holder: Control = info["holder"]
	var field: SlotField = info["field"]
	var n := maxi(int(field.slot_count), 1)
	if capacity < 0:
		capacity = n
	capacity = clampi(capacity, 0, n)
	field.enabled_count = capacity

	for c in holder.get_children():
		if c == field:
			continue
		holder.remove_child(c)
		c.queue_free()
	info["cells"] = []
	info["entries"] = entries

	var cursor := 0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var span := maxi(int(e.get("size", 1)), 1)
		if cursor + span > capacity:
			break
		var box := field.cell_rect(cursor, span)
		var cell := _make_cell(e, box, row, i)
		holder.add_child(cell)
		info["cells"].append({"entry": e, "node": cell})
		cursor += span

	if capacity < n and capacity > 0:
		var w := field.size.x / float(n)
		var hint := UiKit.abs_label("未启用", 10, Color(0.68, 0.76, 0.84, 0.9),
			Rect2i(int(roundf(capacity * w)), 0, int(roundf((n - capacity) * w)), int(field.size.y)),
			HORIZONTAL_ALIGNMENT_CENTER)
		hint.name = "UnusedHint_%s" % row
		holder.add_child(hint)
	field.queue_redraw()
	_apply_selection_style()


## 操作条按钮组。ops 里每项：{id, label, disabled?, align?}（align 为 "right" 时靠右排）。
func set_ops(ops: Array) -> void:
	if _op_bar == null:
		return
	for c in _op_bar.get_children():
		_op_bar.remove_child(c)
		c.queue_free()
	_op_buttons.clear()

	var h := int(_op_bar.size.y)
	var left_x := 0
	var right_x := int(_op_bar.size.x)
	var rights: Array = []
	var lefts: Array = []
	for o in ops:
		if String(o.get("align", "left")) == "right":
			rights.append(o)
		else:
			lefts.append(o)

	for o in lefts:
		var w := _op_width(o)
		_add_op(o, Rect2i(left_x, 0, w, h))
		left_x += w + OP_GAP
	# 右组从右往左排，保证最右一个贴着内沿
	for i in range(rights.size() - 1, -1, -1):
		var o: Dictionary = rights[i]
		var w := _op_width(o)
		right_x -= w
		_add_op(o, Rect2i(right_x, 0, w, h))
		right_x -= OP_GAP


func _op_width(o: Dictionary) -> int:
	var label := String(o.get("label", ""))
	return clampi(label.length() * 12 + 16, OP_MIN_W, OP_MAX_W)


func _add_op(o: Dictionary, box: Rect2i) -> void:
	var id := String(o.get("id", ""))
	var b := UiKit.abs_sys_button_centered(String(o.get("label", "")),
		_on_op_pressed.bind(id), box, 11)
	b.name = "Op_%s" % id
	b.disabled = bool(o.get("disabled", false))
	_op_bar.add_child(b)
	_op_buttons[id] = b


func set_selected(id: String) -> void:
	_selected = id
	_apply_selection_style()


func selected() -> String:
	return _selected


## 按条目 id 找某行的物品格控件（找不到返回 null）。
## 供页面在 set_row 重建后定位反馈位置（如入包合成的短暂闪光）。
func cell_by_id(row: String, id: String) -> Control:
	if not _rows.has(row):
		return null
	for row_cell in _rows[row]["cells"]:
		var d: Dictionary = row_cell
		if String((d["entry"] as Dictionary).get("id", "")) == id:
			return d["node"] as Control
	return null


func _apply_selection_style() -> void:
	for row in _rows.keys():
		var info: Dictionary = _rows[row]
		for row_cell in info["cells"]:
			var cell: Dictionary = row_cell
			var e: Dictionary = cell["entry"]
			var node := cell["node"] as Button
			_apply_cell_style(node, int(e.get("quality", -1)), bool(e.get("enabled", true)),
				String(e.get("id", "")) == _selected and _selected != "")


func _apply_cell_style(b: Button, quality: int, enabled: bool, active: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.13, 0.20, 0.72) if enabled else Color(0.07, 0.11, 0.16, 0.45)
	box.set_border_width_all(2 if active else 1)
	box.border_color = UiKit.quality_color(quality) if quality >= 0 else Color(0.55, 0.70, 0.84, 0.55)
	if active:
		box.border_color = Color(0.98, 1.0, 1.0, 0.95)
		box.bg_color = Color(0.16, 0.28, 0.40, 0.78)
	elif not enabled:
		box.border_color = Color(0.45, 0.55, 0.64, 0.35)
	box.set_corner_radius_all(3)
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", box)
	var hot := box.duplicate() as StyleBoxFlat
	hot.bg_color = Color(0.20, 0.34, 0.48, 0.82)
	hot.border_color = Color(0.94, 0.99, 1.0, 0.95)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_stylebox_override("focus", hot)


func _make_cell(e: Dictionary, box: Rect2, row: String, index: int) -> Button:
	var b := Button.new()
	b.name = "Cell_%s_%d" % [row, index]
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.text = ""
	b.position = box.position
	b.size = box.size
	b.mouse_filter = Control.MOUSE_FILTER_STOP

	var w := int(box.size.x)
	var h := int(box.size.y)
	var pad := CELL_PAD
	var inner_w := maxi(w - pad * 2, 8)
	# 名与格数都从 CELL_TEXT_INSET 起算：文本框贴格边时，字形上下各会溢出约 1 像素，
	# 而 Button 开了 clip_text，溢出的部分直接被裁掉（真渲染截图里小字只剩上半截）。
	var name_h := maxi(h - pad - CELL_FOOT_H - CELL_TEXT_INSET, 12)
	b.add_child(UiKit.abs_block(String(e.get("name", "")), 11, UiKit.COL_TEXT,
		Rect2i(pad, CELL_TEXT_INSET, inner_w, name_h)))
	var quality := int(e.get("quality", -1))
	var sub := String(e.get("sub", ""))
	if sub != "":
		var col := UiKit.quality_color(quality) if quality >= 0 else Color(0.70, 0.81, 0.90)
		b.add_child(UiKit.abs_label(sub, 10, col,
			Rect2i(pad, h - CELL_FOOT_H - CELL_TEXT_INSET, inner_w, CELL_FOOT_H)))
	b.pressed.connect(_on_cell_pressed.bind(row, index))
	_apply_cell_style(b, quality, bool(e.get("enabled", true)), false)
	return b


func _on_cell_pressed(row: String, index: int) -> void:
	var info: Dictionary = _rows.get(row, {})
	var entries: Array = info.get("entries", [])
	if index < 0 or index >= entries.size():
		return
	var e: Dictionary = entries[index]
	if not bool(e.get("enabled", true)):
		return
	var id := String(e.get("id", ""))
	set_selected("" if id == _selected else id)
	cell_selected.emit(row, index, index)


func _on_op_pressed(op_id: String) -> void:
	op_pressed.emit(op_id)


# ---------------------------------------------------------------------------
# 布局自检：暴露真实排版结果，供无画面断言核对
# ---------------------------------------------------------------------------

func report() -> Dictionary:
	var rows := {}
	for row in _rows.keys():
		var info: Dictionary = _rows[row]
		var field: SlotField = info["field"]
		var cells: Array = []
		for row_cell in info["cells"]:
			var d: Dictionary = row_cell
			var node := d["node"] as Control
			cells.append({
				"id": String((d["entry"] as Dictionary).get("id", "")),
				"rect": Rect2i(Vector2i(node.position), Vector2i(node.size)),
			})
		rows[row] = {
			"region": Rect2i(Vector2i(field.position), Vector2i(field.size)),
			"slot_width": (field.size.x / float(maxi(field.slot_count, 1))),
			"slot_count": field.slot_count,
			"enabled": field.enabled_count,
			"cells": cells,
		}
	var ops: Array = []
	for id in _op_buttons.keys():
		var b := _op_buttons[id] as Control
		ops.append({
			"id": String(id),
			"rect": Rect2i(Vector2i(_op_bar.position) + Vector2i(b.position), Vector2i(b.size)),
			"disabled": (b as Button).disabled,
		})
	var regions := {}
	for key in InventorySkin.REGIONS:
		regions[key] = InventorySkin.region(InventorySkin.PANEL, key)
	return {
		"panel": Rect2i(Vector2i(position), Vector2i(size)),
		"regions": regions,
		"op_bar": Rect2i(Vector2i(_op_bar.position), Vector2i(_op_bar.size)) if _op_bar != null else Rect2i(),
		"rows": rows,
		"ops": ops,
		"selected": _selected,
		"texture": _texture_size(),
	}


func _texture_size() -> Vector2i:
	var tex := InventorySkin.texture(InventorySkin.PANEL)
	return Vector2i.ZERO if tex == null else Vector2i(tex.get_size())
