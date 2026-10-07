class_name PageResult
extends PageBase
## 结果页：结束原因、最终数值、物品与技能清单、日志位置与重新开局。
## 依据：技术方案第 14 节；试炼结束清除本次获得，不带入下一次试炼。

func build() -> void:
	var summary: Dictionary = payload.get("summary", {})
	var reason := String(payload.get("reason", ""))
	var root := add_root("试炼结束")

	var state_name := String(summary.get("state", ""))
	var headline := _headline(state_name)
	var head := UiKit.panel(headline)
	root.add_child(head)
	var hb := UiKit.body(head)
	var col := UiKit.COL_MERCHANT
	if state_name == "failed":
		col = UiKit.COL_ENEMY
	elif state_name == "surrendered":
		col = UiKit.COL_MUTED
	hb.add_child(UiKit.label("结束原因：%s" % reason, 18, col))
	hb.add_child(UiKit.label("最终状态：%s" % state_name, 15, UiKit.COL_TEXT))

	var cols := UiKit.row(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := UiKit.panel("最终数值")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var lb := UiKit.body(left)
	lb.add_child(UiKit.label("生命 %.1f / %.1f" % [float(summary.get("hp", 0.0)), float(summary.get("max_hp", 0.0))], 15, UiKit.COL_TEXT))
	lb.add_child(UiKit.label("货币 %d" % int(summary.get("money", 0)), 15, UiKit.COL_TEXT))
	lb.add_child(UiKit.label("累计战败 %d / %d" % [int(summary.get("defeats", 0)), RunState.MAX_DEFEATS], 15, UiKit.COL_TEXT))
	lb.add_child(UiKit.label("主线完成：%s" % ("是" if bool(summary.get("main_completed", false)) else "否"), 15, UiKit.COL_TEXT))
	lb.add_child(UiKit.label("已付费新节点数：%d" % int(summary.get("paid_nodes", 0)), 14, UiKit.COL_MUTED))
	lb.add_child(UiKit.label("职业／血统：%s / %s" % [summary.get("profession", ""), summary.get("bloodline", "")], 14, UiKit.COL_MUTED))
	var total := float(summary.get("timing_total_seconds", 0.0))
	lb.add_child(UiKit.label("本局各界面累计停留 %.1f 秒（不含暂停）" % total, 14, UiKit.COL_MUTED))

	var right := UiKit.panel("携带清单与日志")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rb := UiKit.body(right)
	rb.add_child(UiKit.label("战斗栏", 15, UiKit.COL_ACCENT))
	rb.add_child(UiKit.label(_join_items(summary.get("bar", [])), 14, UiKit.COL_TEXT))
	rb.add_child(UiKit.label("背包", 15, UiKit.COL_ACCENT))
	rb.add_child(UiKit.label(_join_items(summary.get("inventory", [])), 14, UiKit.COL_TEXT))
	rb.add_child(UiKit.label("技能", 15, UiKit.COL_ACCENT))
	var skills: Array = summary.get("skills", [])
	rb.add_child(UiKit.label("、".join(PackedStringArray(skills)) if not skills.is_empty() else "无", 14, UiKit.COL_TEXT))
	rb.add_child(UiKit.spacer(8))
	rb.add_child(UiKit.label("本次试炼获得的物品、货币、技能与成长已清除，不带入下一次试炼。", 13, UiKit.COL_MUTED))
	if ctrl.recorder != null:
		rb.add_child(UiKit.label("事件日志：%s" % ctrl.recorder.global_log_path(), 12, UiKit.COL_MUTED))
		rb.add_child(UiKit.label("摘要：%s" % ctrl.recorder.global_summary_path(), 12, UiKit.COL_MUTED))

	var footer := UiKit.row(8)
	root.add_child(footer)
	footer.add_child(UiKit.button("重新开始新试炼", _on_restart))


func _on_restart() -> void:
	ctrl.start_new_app()


func _headline(state_name: String) -> String:
	match state_name:
		"stage_complete":
			return "原型阶段完成"
		"failed":
			return "试炼失败（累计三次战败）"
		"surrendered":
			return "主动认输"
	return "试炼结束"


func _join_items(rows: Array) -> String:
	if rows.is_empty():
		return "无"
	var parts := PackedStringArray()
	for raw in rows:
		var arr: Array = raw
		if arr.is_empty():
			continue
		var s := String(arr[0])
		var colon := s.find(":q")
		var def_id := s if colon < 0 else s.substr(0, colon)
		var quality := 0
		var growth := 0.0
		if colon >= 0:
			var tail := s.substr(colon + 2)
			var plus := tail.find(":+")
			if plus >= 0:
				quality = int(tail.substr(0, plus))
				growth = float(tail.substr(plus + 2))
			else:
				quality = int(tail)
		var extra := ""
		if growth != 0.0:
			extra = "　成长 +%.1f" % growth
		parts.append("%s（%s）%s" % [
			catalog.item_display(StringName(def_id)), PriceTable.quality_name(quality), extra,
		])
	return "、".join(parts)
