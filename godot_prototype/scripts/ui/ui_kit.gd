class_name UiKit
extends RefCounted
## 占位界面工具箱：统一 Theme、面板、按钮、数值条。
## 边界：只负责展示与命令转发，不承载业务规则。

const COL_BG := Color(0.09, 0.09, 0.11)
const COL_PANEL := Color(0.15, 0.15, 0.18)
const COL_PANEL_2 := Color(0.19, 0.19, 0.23)
const COL_TEXT := Color(0.90, 0.90, 0.92)
const COL_MUTED := Color(0.62, 0.62, 0.68)
const COL_ACCENT := Color(0.85, 0.70, 0.42)
const COL_PLAYER := Color(0.36, 0.62, 0.95)
const COL_ENEMY := Color(0.87, 0.35, 0.35)
const COL_MERCHANT := Color(0.42, 0.78, 0.45)
const COL_INTEL := Color(0.90, 0.82, 0.35)
const COL_HP := Color(0.78, 0.28, 0.30)
const COL_SHIELD := Color(0.42, 0.66, 0.90)
const COL_BURN := Color(0.95, 0.55, 0.25)
const COL_POISON := Color(0.55, 0.80, 0.35)


static func make_theme() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif",
	])
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	theme.default_font = font
	theme.default_font_size = 16

	var panel := StyleBoxFlat.new()
	panel.bg_color = COL_PANEL
	panel.set_corner_radius_all(6)
	panel.set_border_width_all(1)
	panel.border_color = Color(0.30, 0.30, 0.36)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	theme.set_stylebox("panel", "PanelContainer", panel)

	var btn := StyleBoxFlat.new()
	btn.bg_color = COL_PANEL_2
	btn.set_corner_radius_all(4)
	btn.content_margin_left = 12
	btn.content_margin_right = 12
	btn.content_margin_top = 6
	btn.content_margin_bottom = 6
	theme.set_stylebox("normal", "Button", btn)
	var btn_hover := btn.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.26, 0.26, 0.32)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_hover)
	var btn_disabled := btn.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color(0.13, 0.13, 0.15)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_color("font_color", "Button", COL_TEXT)
	theme.set_color("font_disabled_color", "Button", COL_MUTED)

	theme.set_color("font_color", "Label", COL_TEXT)
	return theme


static func page_root(title: String) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", COL_ACCENT)
	root.add_child(t)
	return root


static func panel(title: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	var box := VBoxContainer.new()
	box.name = "Body"
	box.add_theme_constant_override("separation", 6)
	p.add_child(box)
	if title != "":
		var l := Label.new()
		l.text = title
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", COL_ACCENT)
		box.add_child(l)
	return p


static func body(panel_node: PanelContainer) -> VBoxContainer:
	return panel_node.get_node("Body")


static func row(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func grid(columns: int = 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 4)
	return g


static func label(text: String, size: int = 15, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 自动换行会把标签的最小宽度压到 0，放进 HBoxContainer 时会被旁边的按钮挤成
	# 「一字一行」。让标签默认吃掉剩余宽度，才能保持正常排版。
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, on_pressed: Callable, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func key_label(text: String, color: Color) -> Label:
	var l := label(text, 14, color)
	l.custom_minimum_size = Vector2(96, 20)
	return l


## 生命 / 护盾条
static func bar(value: float, maximum: float, color: Color, width: int = 220, height: int = 16) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, height)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2.ZERO
	fill.size = Vector2(width * clampf(value / maxf(maximum, 1.0), 0.0, 1.0), height)
	holder.add_child(fill)
	return holder


static func spacer(height: int = 6) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s


## 把内容放进可滚动容器。
## 注意：ScrollContainer 只把「横向带 SIZE_EXPAND」的子节点撑到容器宽度，
## 否则子节点会被压到最小宽度（表现为文字一字一行）。此处统一补上该标记。
static func scroll_into(child: Control) -> ScrollContainer:
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := scroll()
	s.add_child(child)
	return s


static func join(names: PackedStringArray, sep: String = "、") -> String:
	return sep.join(names)


## 效果与触发关系的可读文本（用于战前机制信息与战后统计归属）
static func effect_text(def: ItemDef) -> String:
	if def == null:
		return "—"
	match def.category:
		ItemDef.CAT_WEAPON:
			return "攻击伤害"
		ItemDef.CAT_SHIELD:
			return "获得护盾"
		ItemDef.CAT_HEAL:
			return "治疗量"
		ItemDef.CAT_BURN:
			return "施加灼烧"
		ItemDef.CAT_POISON:
			return "施加中毒"
		ItemDef.CAT_HASTE:
			return "加速己方另一物品"
		ItemDef.CAT_SLOW:
			return "减速敌方一个物品"
		ItemDef.CAT_FREEZE:
			return "冰冻敌方一个物品"
		ItemDef.CAT_CONSUMABLE:
			return "战斗外恢复 %d 生命" % int(def.out_of_combat_heal)
		ItemDef.CAT_MATERIAL:
			return "可出售材料"
	return "—"


static func trigger_text(def: ItemDef) -> String:
	if def == null:
		return ""
	var parts := PackedStringArray()
	if def.self_passive == ItemDef.PASSIVE_CHARGE_ON_WEAPON_USE:
		parts.append("自身被动：使用武器时充能自身 1 秒")
	for e in def.effects:
		match e.emits_event:
			&"use_weapon":
				parts.append("释放产生「使用武器」事件")
			&"use_shield":
				parts.append("释放产生「使用护盾物品」事件")
			&"heal":
				parts.append("释放产生「治疗」事件")
			&"apply_burn":
				parts.append("释放产生「施加灼烧」事件")
			&"apply_poison":
				parts.append("释放产生「施加中毒」事件")
	return "；".join(parts)
