extends SceneTree
## 无画面验证入口。
## 用法：godot --headless --path . --script res://tests/headless_main.gd
##
## 退出码：0 全部通过；1 存在失败。

func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	var suites: Array[TestSuite] = [
		CombatRegressionTest.new(),
		ContentValidationTest.new(),
	]
	for extra in ["res://tests/economy_service_test.gd", "res://tests/world_flow_test.gd",
			"res://tests/ui_smoke_test.gd"]:
		if ResourceLoader.exists(extra):
			suites.append(load(extra).new())
	var total_failed := 0
	var total_passed := 0
	print("===== 原型无画面验证 =====")
	for s in suites:
		s.run()
		if s is UiSmokeTest:
			# 布局检查需要真实帧推进，必须在同步断言之后单独 await
			await (s as UiSmokeTest).extend_with_frames()
		print(s.summary())
		total_failed += s.failed
		total_passed += s.passed
	print("===== 合计：通过 %d，失败 %d =====" % [total_passed, total_failed])
	quit(1 if total_failed > 0 else 0)
