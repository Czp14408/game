class_name SessionRecorder
extends RefCounted
## 试炼日志：JSONL 事件流 + JSON 摘要，保存到 user://。
## 边界：日志用于验证，不增加游戏收益。
## 依据：游戏可玩原型技术方案.md 第 14 节。

var enabled: bool = true
var run_id: String = ""
var log_path: String = ""
var summary_path: String = ""
var _file: FileAccess = null
var _count: int = 0

var meta: Dictionary = {}
## 耗时分类统计（互斥，暂停与失去焦点另列）
var timing: Dictionary = {}


static func create(p_run_id: String) -> SessionRecorder:
	var r := SessionRecorder.new()
	r.run_id = p_run_id
	r.log_path = "user://logs/%s.jsonl" % p_run_id
	r.summary_path = "user://logs/%s.summary.json" % p_run_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
	return r


func start(p_meta: Dictionary) -> void:
	meta = p_meta.duplicate()
	if not enabled:
		return
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	record_event("run_start", meta)


func record_event(kind: String, data: Dictionary) -> void:
	if not enabled or _file == null:
		return
	_count += 1
	_file.store_line(JSON.stringify({"seq": _count, "kind": kind, "t": Time.get_ticks_msec(), "data": data}))


func add_time(bucket: String, seconds: float) -> void:
	timing[bucket] = float(timing.get(bucket, 0.0)) + seconds


func finish(summary: Dictionary) -> void:
	if not enabled:
		return
	record_event("run_end", summary)
	if _file != null:
		_file.close()
		_file = null
	var out := summary.duplicate()
	out["run_id"] = run_id
	out["meta"] = meta
	out["timing"] = timing
	out["event_count"] = _count
	var f := FileAccess.open(summary_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()


func global_log_path() -> String:
	return ProjectSettings.globalize_path(log_path)


func global_summary_path() -> String:
	return ProjectSettings.globalize_path(summary_path)
