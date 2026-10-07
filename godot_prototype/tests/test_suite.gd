class_name TestSuite
extends RefCounted
## 极简测试套件：无画面运行，用于 M0—M5 的验收断言。

var suite_name: String = "unnamed"
var passed: int = 0
var failed: int = 0
var failures: PackedStringArray = []
var notes: PackedStringArray = []


func run() -> void:
	pass


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		failures.append(message)


func eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		failures.append("%s：期望 %s，实际 %s" % [message, str(expected), str(actual)])


func near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) <= tolerance:
		passed += 1
	else:
		failed += 1
		failures.append("%s：期望 %f±%f，实际 %f" % [message, expected, tolerance, actual])


func note(text: String) -> void:
	notes.append(text)


func summary() -> String:
	var lines := PackedStringArray()
	lines.append("── %s：通过 %d，失败 %d" % [suite_name, passed, failed])
	for f in failures:
		lines.append("   ✗ %s" % f)
	for n in notes:
		lines.append("   · %s" % n)
	return "\n".join(lines)
