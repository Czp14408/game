class_name OperationResult
extends RefCounted
## 业务操作的统一返回：success、reason 与已提交的状态变化。
## 失败不扣币不丢物。

var success: bool = false
var reason: String = ""
var data: Dictionary = {}


static func ok(p_data: Dictionary = {}) -> OperationResult:
	var r := OperationResult.new()
	r.success = true
	r.data = p_data
	return r


static func fail(p_reason: String) -> OperationResult:
	var r := OperationResult.new()
	r.success = false
	r.reason = p_reason
	return r
