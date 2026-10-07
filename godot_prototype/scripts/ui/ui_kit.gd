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

## 品质色（0 青铜 1 白银 2 黄金 3 钻石），与价目表的档位一致
const QUALITY_COLORS: Array[Color] = [
	Color(0.76, 0.54, 0.33),
	Color(0.82, 0.84, 0.88),
	Color(0.92, 0.78, 0.36),
	Color(0.55, 0.85, 0.95),
]


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


## 像素图显示：按给定方框等比缩放、居中，并强制最近邻采样。
## 为什么显式指定采样：像素图一旦被线性插值就会糊边，且不同显卡驱动默认值不一致，
## 不能依赖项目默认设置。
static func pixel_art(tex: Texture2D, box: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.custom_minimum_size = box
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s


static func quality_color(quality: int) -> Color:
	return QUALITY_COLORS[clampi(quality, 0, QUALITY_COLORS.size() - 1)]


# ---------------------------------------------------------------------------
# 绝对定位构件
# 战斗界面按组件规范用固定坐标排布（见 battle_skin.gd），不套容器：
# 容器会把子节点按最小尺寸重排，而组件边框要求像素级对齐。
# ---------------------------------------------------------------------------

## 指定尺寸的实心色块：生命填充、护盾填充、冷却条、遮罩
static func solid(color: Color, rect: Rect2i) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.position = Vector2(rect.position)
	c.size = Vector2(rect.size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 实心控件但不吃鼠标、可整体挪动（用于叠加覆盖层）
static func overlay(color: Color, size: Vector2) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.position = Vector2.ZERO
	c.size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 按目标矩形摆放的像素图。STRETCH_SCALE 而非按比例：面板纹理已由生成器
## 烘焙成目标尺寸，这里必须 1:1 落位，不能让它再等比缩放。
static func panel_art(tex: Texture2D, rect: Rect2i) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.position = Vector2(rect.position)
	t.size = Vector2(rect.size)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## 绝对定位的文本块。垂直居中，宽度给定，超出宽度的部分裁剪而不撑破面板。
static func abs_label(
	text: String,
	font_size: int,
	color: Color,
	rect: Rect2i,
	align: int = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var l := label(text, font_size, color)
	l.position = Vector2(rect.position)
	l.size = Vector2(rect.size)
	l.clip_text = true
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## 绝对定位的多行文本块（状态、技能、日志），顶端对齐并允许换行
static func abs_block(text: String, font_size: int, color: Color, rect: Rect2i) -> Label:
	var l := label(text, font_size, color)
	l.position = Vector2(rect.position)
	l.size = Vector2(rect.size)
	l.clip_text = true
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l


## 自带滚动的日志文本：按目标矩形绝对定位即可，不需要再外套 ScrollContainer。
## 为什么不用 Label：Label 同时开自动换行与 clip_text 时最小高度塌成 1 像素，
## 放进 ScrollContainer 会被排成 191×1（实测），整块区域看起来是空的。
## RichTextLabel 自己管换行与滚动，scroll_following 让追加内容时自动贴到最新一条，
## 高度完全不依赖容器推算——正是战斗记录需要的行为。
static func log_text(font_size: int, color: Color) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = false
	t.fit_content = false
	t.scroll_active = true
	t.scroll_following = true
	t.selection_enabled = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("normal_font_size", font_size)
	t.add_theme_color_override("default_color", color)
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	return t


## 绝对定位版本：矩形由调用方给定，控件自身不再参与容器重排。
static func abs_log(font_size: int, color: Color, rect: Rect2i) -> RichTextLabel:
	var t := log_text(font_size, color)
	t.position = Vector2(rect.position)
	t.size = Vector2(rect.size)
	return t


## 绝对定位的按钮：横向固定宽度，纵向按内容最小高度撑开。
## 这套按钮落在木框组件里面，所以用深色底 + 古铜描边，而不是全局主题的深灰圆角块；
## 只覆盖本控件的样式，不改全局主题，其他页面照旧。
static func abs_button(text: String, on_pressed: Callable, rect: Rect2i, font_size: int = 13) -> Button:
	var b := button(text, on_pressed)
	b.add_theme_font_size_override("font_size", font_size)
	b.clip_text = true
	b.position = Vector2(rect.position)
	b.size = Vector2(rect.size)
	_apply_wood_style(b)
	return b


static func _apply_wood_style(b: Button) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.14, 0.13, 0.13, 0.94)
	box.set_border_width_all(1)
	box.border_color = Color(0.50, 0.35, 0.19)
	box.set_corner_radius_all(3)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	b.add_theme_stylebox_override("normal", box)
	var hot := box.duplicate() as StyleBoxFlat
	hot.bg_color = Color(0.23, 0.19, 0.15, 0.96)
	hot.border_color = Color(0.80, 0.60, 0.32)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_stylebox_override("focus", hot)
	var off := box.duplicate() as StyleBoxFlat
	off.bg_color = Color(0.11, 0.11, 0.12, 0.9)
	off.border_color = Color(0.26, 0.22, 0.18)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_color_override("font_color", Color(0.93, 0.87, 0.77))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.85))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.43, 0.42))


## 绝对定位的浅蓝玻璃按钮：给「背包／商店／整理共用面板」用。
## 为什么另起一套而不是复用 abs_button：后者的深棕描边是配战斗页古铜木框的，
## 放到浅蓝半透明面板上会像两块不同风格的界面拼在一起。
## 纵向内边距取 0：共用面板的操作条实测只有 15 像素高，任何上下留白都会把字挤出按钮。
static func abs_sys_button(text: String, on_pressed: Callable, rect: Rect2i, font_size: int = 11) -> Button:
	var b := button(text, on_pressed)
	b.add_theme_font_size_override("font_size", font_size)
	b.clip_text = true
	b.position = Vector2(rect.position)
	b.size = Vector2(rect.size)
	_apply_sys_style(b)
	return b


## 极扁条带里的居中按钮：条高只有 15 像素，而 Button 自己的文字行高约 29 像素
## （11px 字 + 主题行距），无论怎么调 content_margin 与 clip_text 都只剩半个字。
## 做法：Button 自身不写字（clip_text 只裁自己的 text，不裁子节点），
## 文字交给一个不裁剪的 Label，按「条高 − 行高」的一半向上溢出摆放，字心正好落在条心。
static func abs_sys_button_centered(text: String, on_pressed: Callable, rect: Rect2i,
		font_size: int = 11) -> Button:
	var b := abs_sys_button("", on_pressed, rect, font_size)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(0, 0)
	var line_h := font_size * 2 + 7
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = false
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0))
	l.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	l.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	l.add_theme_color_override("font_disabled_color", Color(0.52, 0.60, 0.68))
	l.size = Vector2(rect.size.x, line_h)
	l.position = Vector2(0, roundf((float(rect.size.y) - float(line_h)) * 0.5))
	b.add_child(l)
	return b


static func _apply_sys_style(b: Button) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.72, 0.86, 0.96, 0.16)
	box.set_border_width_all(1)
	box.border_color = Color(0.82, 0.93, 1.0, 0.55)
	box.set_corner_radius_all(3)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", box)
	var hot := box.duplicate() as StyleBoxFlat
	hot.bg_color = Color(0.80, 0.92, 1.0, 0.34)
	hot.border_color = Color(0.94, 0.98, 1.0, 0.85)
	b.add_theme_stylebox_override("hover", hot)
	var down := box.duplicate() as StyleBoxFlat
	down.bg_color = Color(0.86, 0.95, 1.0, 0.46)
	down.border_color = Color(1.0, 1.0, 1.0, 0.95)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("focus", hot)
	var off := box.duplicate() as StyleBoxFlat
	off.bg_color = Color(0.45, 0.55, 0.64, 0.10)
	off.border_color = Color(0.62, 0.72, 0.80, 0.22)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.60, 0.67, 0.73))


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
