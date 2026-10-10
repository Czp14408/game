class_name ItemCard
extends Button
## Presentation only: instance values are read without modifying definitions.

var definition: ItemDef
var instance: ItemInstance
var quality := 0
var battle_state: BattleItemState
var tooltip_body: RichTextLabel
var frame: Panel
var card_rect := Rect2()
var stat_layer: Control
var motion: ItemMotion
var _stat_signature := ""

func configure(entry: Dictionary) -> void:
	definition = entry["definition"]
	instance = entry.get("instance")
	quality = int(entry.get("quality", 0))
	battle_state = entry.get("battle_state")
	tooltip_text = definition.display_name
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state in ["normal", "hover", "pressed", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var footer := float(ItemCardLayout.FOOTER_HEIGHT) if entry.has("price_text") else 0.0
	var height := minf(size.y - footer, size.x * 2.0 / definition.size)
	var width := height * definition.size / 2.0
	card_rect = Rect2((size.x - width) / 2.0, 0, width, height)
	frame = Panel.new()
	frame.position = card_rect.position
	frame.size = card_rect.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	if definition.icon_path != "" and ResourceLoader.exists(definition.icon_path):
		var picture := TextureRect.new()
		picture.name = "ItemImage"
		picture.texture = load(definition.icon_path)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var inset := float(ItemSkin.settings()["image_inset"])
		picture.position = Vector2(inset, inset)
		picture.size = card_rect.size - Vector2(inset * 2, inset * 2)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(picture)
	else:
		# Legacy items have no authored image; never reuse another item's picture.
		var title := UiKit.abs_block(definition.display_name, 12, UiKit.COL_TEXT,
			Rect2i(5, 5, maxi(int(width) - 10, 1), maxi(int(height) - 10, 1)))
		title.name = "LegacyName"
		frame.add_child(title)
	if footer > 0:
		add_child(UiKit.abs_label(String(entry["price_text"]), 12, UiKit.COL_TEXT,
			Rect2i(0, int(height), int(size.x), int(footer)), HORIZONTAL_ALIGNMENT_CENTER))
	set_active(false)
	if battle_state != null:
		motion = ItemMotion.new()
		motion.name = "ItemMotion"
		motion.z_index = 2
		motion.configure(battle_state, card_rect)
		add_child(motion)
	stat_layer = Control.new()
	stat_layer.name = "ItemStats"
	stat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_layer.z_index = 5
	add_child(stat_layer)
	_refresh_stat_badges()

func set_active(active: bool) -> void:
	if frame == null:
		return
	frame.add_theme_stylebox_override("panel", ItemSkin.frame_style(quality, active))

func final_value() -> float:
	if battle_state != null:
		return battle_state.base_value + battle_state.battle_growth
	return definition.value_at(quality) + (instance.trial_growth if instance != null else 0.0)

func effect_value(effect: EffectDef) -> float:
	if effect.value_source == &"fixed":
		return effect.fixed_value
	var effects := battle_state.effects if battle_state != null and not battle_state.effects.is_empty() else definition.effects
	return final_value() if effects.find(effect) <= 0 else effect.value_at(quality, final_value())


func stat_values() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var effects := battle_state.effects if battle_state != null and not battle_state.effects.is_empty() else definition.effects
	for kind in GamePalette.STAT_ORDER:
		var seen: Array[float] = []
		for effect in effects:
			if String(effect.effect_type) != kind:
				continue
			var amount := effect_value(effect)
			if amount in seen:
				continue
			seen.append(amount)
			result.append({"kind": kind, "value": amount, "text": str(int(amount)) if amount >= 0 and amount <= ItemCardLayout.MAX_VALUE and is_equal_approx(amount, roundf(amount)) else "超限"})
	return result

func _refresh_stat_badges() -> void:
	if stat_layer == null:
		return
	var values := stat_values()
	var multicast := battle_state.multicast if battle_state != null else definition.multicast_at(quality)
	var signature := JSON.stringify({"values": values, "multicast": multicast})
	if signature == _stat_signature:
		return
	_stat_signature = signature
	for child in stat_layer.get_children():
		stat_layer.remove_child(child)
		child.queue_free()
	# One row only. A small item supports three badges; wider cards support all five kinds.
	var available := minf(size.x, card_rect.size.x + 16)
	var badge_width := minf(72, floorf((available - maxi(values.size()-1, 0) * ItemCardLayout.BADGE_GAP) / maxi(values.size(), 1)))
	var badges: Array[ItemStatBadge] = []
	var width := float(maxi(values.size()-1, 0) * ItemCardLayout.BADGE_GAP)
	for stat in values:
		var badge := ItemStatBadge.new()
		var preferred := maxf(24, ceilf(ItemStatBadge.badge_font.get_string_size(stat["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, ItemCardLayout.BADGE_FONT_SIZE).x) + 12)
		badge.configure(stat, minf(preferred, badge_width))
		badges.append(badge)
		width += badge.size.x
	var x := (size.x - width) / 2.0
	for badge in badges:
		badge.position = Vector2(roundf(x), -8)
		stat_layer.add_child(badge)
		x += badge.size.x + ItemCardLayout.BADGE_GAP

	if multicast > 1:
		var badge := ItemMulticastBadge.new()
		badge.name = "Multicast"
		badge.configure(multicast, quality, card_rect.size)
		badge.position = Vector2(roundf((size.x - badge.size.x) / 2), 18 if not values.is_empty() else -2)
		stat_layer.add_child(badge)
	var title := frame.get_node_or_null("LegacyName") as Label
	if title != null:
		title.position.y = 48 if multicast > 1 else (28 if not values.is_empty() else 5)
		title.size.y = maxf(card_rect.size.y - title.position.y - 5, 12)

func description() -> String:
	var labels := {"weapon": "武器", "tool": "工具", "material": "材料", "active": "主动"}
	var tags := PackedStringArray()
	for tag in definition.tags:
		tags.append(String(labels.get(String(tag), String(tag))))
	if not definition.display_tags.is_empty():
		tags = definition.display_tags
	var text := "[font_size=20]%s[/font_size]\n%s" % [definition.display_name, " ".join(tags)]
	if definition.cooldown_ms > 0:
		text += "\n冷却：%s 秒" % String.num(definition.cooldown_ms / 1000.0, 2).trim_suffix(".0")
	var multicast := battle_state.multicast if battle_state != null else definition.multicast_at(quality)
	if multicast > 1:
		text += "\n多重释放：×%d（冷却结束后连续使用 %d 次）" % [multicast, multicast]
	text += "\n──────────"
	if not definition.tier_weapon_growth.is_empty():
		text += "\n每次使用，所有 [b]武器[/b]（包含自身）提升 [b]%s[/b] 点 [img=16x16]res://assets/ui/stat_icons/attack.svg[/img]攻击；本场战斗有效。\n──────────" % String.num(definition.weapon_growth_at(quality), 0)
	var names := {"attack": "攻击", "poison": "中毒", "burn": "灼烧", "shield": "护盾", "heal": "治疗"}
	for effect in definition.effects:
		var kind := String(effect.effect_type)
		var amount := effect_value(effect)
		if names.has(kind):
			var icon := "[img=16x16]res://assets/ui/stat_icons/%s.svg[/img]" % kind
			var verb := "造成" if kind in ["attack", "poison", "burn"] else "获得"
			text += "\n每次使用，%s [b]%s[/b] 点 %s%s。" % [verb, String.num(amount, 2).trim_suffix(".0"), icon, names[kind]]
		else:
			text += "\n每次使用，%s：%s。" % [UiKit.effect_text(definition), String.num(amount, 2).trim_suffix(".0")]
	if definition.effects.is_empty():
		text += "\n" + UiKit.effect_text(definition)
	if definition.self_passive == ItemDef.PASSIVE_CHARGE_ON_WEAPON_USE:
		text += "\n──────────\n使用武器时，充能此物品 1 秒。"
	return text

func _make_custom_tooltip(_for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.theme = UiKit.make_theme()
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_theme_stylebox_override("panel", ItemSkin.frame_style(quality, false, true))
	var body := RichTextLabel.new()
	body.custom_minimum_size = Vector2(float(ItemSkin.settings()["tooltip_width"]), 0)
	body.fit_content = true
	body.scroll_active = false
	body.bbcode_enabled = true
	body.add_theme_color_override("default_color", UiKit.COL_TEXT)
	body.add_theme_font_size_override("normal_font_size", 16)
	body.text = description()
	tooltip_body = body
	panel.add_child(body)
	return panel

func _process(_delta: float) -> void:
	_refresh_stat_badges()
	if is_instance_valid(tooltip_body):
		var updated := description()
		if tooltip_body.text != updated:
			tooltip_body.text = updated
