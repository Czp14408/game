class_name HeroArt
extends RefCounted
## 主角美术资源访问层：按语义取姿势纹理、按方向取行走序列。
## 边界：只读资源 + 纯计算的方向映射；不做布局、不承载业务规则。
## 依据：游戏后续优化迭代计划.md §4.5；资产由 tools/slice_hero_sheet.py 生成。

const ROOT := "res://assets/hero"
const WALK_FRAMES := 5
const WALK_FPS := 7.0

## 四方向行走序列名（与 assets/hero/walk 下的文件名一致）
const DIR_DOWN := &"down"
const DIR_UP := &"up"
const DIR_LEFT := &"left"
const DIR_RIGHT := &"right"
const DIRECTIONS: Array[StringName] = [&"down", &"up", &"left", &"right"]

## 语义姿势名（与 assets/hero/pose 下的文件名一致）
const POSE_WAVE := &"wave"            ## 挥手
const POSE_SALUTE := &"salute"        ## 敬礼
const POSE_PUNCH := &"punch"          ## 出拳
const POSE_CHEER_BACK := &"cheer_back" ## 背身高举
const POSE_JUMP := &"jump"            ## 跳跃欢呼
const POSE_THINK := &"think"          ## 低头
const POSE_RUN := &"run"              ## 奔跑
const POSE_SPRINT := &"sprint"        ## 冲刺
const POSE_DOWN := &"down"            ## 倒地
const POSE_POCKETS := &"pockets"      ## 插兜站立

## 界面语义 → 姿势。集中在此，避免各页面各自硬编码文件名。
const POSE_HOME := &"wave"            ## 开局页立绘
const POSE_BATTLE := &"punch"         ## 战斗页头像
const POSE_VICTORY := &"jump"         ## 结算：阶段完成
const POSE_DEFEAT := &"down"          ## 结算：试炼失败
const POSE_SURRENDER := &"think"      ## 结算：主动认输

static var _cache: Dictionary = {}


static func pose(key: StringName) -> Texture2D:
	return _load("pose/%s.png" % key)


static func walk(dir: StringName, frame: int) -> Texture2D:
	return _load("walk/%s_%d.png" % [dir, posmod(frame, WALK_FRAMES)])


static func walk_frames(dir: StringName) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i in WALK_FRAMES:
		out.append(walk(dir, i))
	return out


## 到位纹理的尺寸；缺失时返回 Vector2.ZERO（供调用方做容错布局）。
static func size_of(tex: Texture2D) -> Vector2:
	return Vector2.ZERO if tex == null else tex.get_size()


## 方向映射（纯函数）。
## 判定规则：纵向分量不弱于横向时取上下——小地图以纵向探索为主，
## 正面/背面比侧面更容易辨认朝向；完全静止时朝上（背面），与交互点在上方的布局一致。
static func direction_of(dir: Vector2) -> StringName:
	if dir == Vector2.ZERO:
		return DIR_UP
	if absf(dir.y) >= absf(dir.x):
		return DIR_UP if dir.y < 0.0 else DIR_DOWN
	return DIR_RIGHT if dir.x > 0.0 else DIR_LEFT


## 帧序号（纯函数）：按经过时间推进并回绕，保证长时间移动不会越界。
static func frame_index(phase: float, frames: int = WALK_FRAMES, fps: float = WALK_FPS) -> int:
	if frames <= 0:
		return 0
	return posmod(int(floor(maxf(phase, 0.0) * fps)), frames)


static func texture_exists(rel: String) -> bool:
	return ResourceLoader.exists("%s/%s" % [ROOT, rel])


static func _load(rel: String) -> Texture2D:
	var path := "%s/%s" % [ROOT, rel]
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	else:
		push_warning("主角资源缺失：%s" % path)
	_cache[path] = tex
	return tex
