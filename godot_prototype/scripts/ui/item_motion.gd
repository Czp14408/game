class_name ItemMotion
extends Control
## Shared pixel presentation. Reads combat state; never advances or changes cooldown.
var state: BattleItemState
var clock := 0.0
var charge_age := 1.0
var use_age := 1.0
var _charge_seq := 0
var _uses := 0
var progress := 0.0
const SLOW_TINT := Color("704b3a")
const SLOW_CORE := Color("c98a66")

func artwork_rect() -> Rect2:
	return Rect2(6,6,maxf(size.x-12,1),maxf(size.y-12,1))

func cooldown_line_y() -> float:
	var inner := artwork_rect()
	return roundf(inner.position.y+inner.size.y*(1-progress))

func configure(value: BattleItemState, rect: Rect2) -> void:
	state = value
	position = rect.position
	size = rect.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_charge_seq = state.charge_visual_seq
	_uses = state.uses

func sync() -> void:
	if state == null: return
	progress = clampf(1.0-float(state.cooldown_remaining_ms)/maxi(state.base_cd_ms,1),0,1)
	if state.charge_visual_seq != _charge_seq:
		charge_age = 0
		_charge_seq = state.charge_visual_seq
	if state.uses != _uses:
		use_age = 0
		_uses = state.uses

func _process(delta: float) -> void:
	sync()
	clock += delta
	charge_age += delta
	use_age += delta
	queue_redraw()

func _draw() -> void:
	if state == null: return
	var inner := artwork_rect()
	var line_y := cooldown_line_y()
	# Remaining cooldown darkens only the artwork. Readiness clears from bottom upwards.
	if progress < 1:
		draw_rect(Rect2(inner.position,Vector2(inner.size.x,roundf(inner.size.y*(1-progress)))),Color(GamePalette.BACKGROUND,0.48))
	var tint := GamePalette.QUALITIES[1]
	if state.freeze_ms > 0: tint = GamePalette.FOCUS
	elif state.haste_ms > 0 and state.slow_ms == 0: tint = GamePalette.FOCUS
	elif state.slow_ms > 0 and state.haste_ms == 0: tint = SLOW_CORE
	# A thin pixel scan edge replaces the separate bottom progress bar.
	if progress > 0 and progress < 1:
		draw_line(Vector2(inner.position.x,line_y),Vector2(inner.end.x-1,line_y),Color(tint,0.65),1)
		var phase := 0.0 if state.freeze_ms > 0 else fposmod(clock*12,8)
		for index in range(int(ceil(inner.size.x/8))):
			var x := inner.position.x+fposmod(index*8+phase,inner.size.x)
			draw_rect(Rect2(roundf(x),line_y-1,minf(3,inner.end.x-roundf(x)),2),Color(tint,0.8))
	if state.freeze_ms > 0:
		draw_rect(inner,Color(GamePalette.FOCUS,0.12))
		draw_rect(inner,GamePalette.FOCUS,false,1)
		var columns := maxi(2,int(inner.size.x/28))
		var rows := maxi(3,int((inner.size.y-24)/32))
		for row in range(rows):
			for column in range(columns):
				var seed_value := row*13+column*7
				var radius := float(4+seed_value%3*2)
				var center := Vector2(roundf(inner.position.x+(column+0.5)*inner.size.x/columns+(seed_value%5-2)*2),roundf(28+(row+0.5)*maxf(inner.end.y-34,1)/rows+(seed_value%7-3)*2))
				center.x = clampf(center.x,inner.position.x+radius,inner.end.x-radius)
				center.y = clampf(center.y,28+radius,inner.end.y-radius)
				for axis in [Vector2(1,0),Vector2(0,1),Vector2(1,1),Vector2(1,-1)]:
					var tip_a: Vector2 = (center-axis*radius).round()
					var tip_b: Vector2 = (center+axis*radius).round()
					draw_line(tip_a,tip_b,Color(GamePalette.FOCUS,0.75),1)
					if radius >= 6:
						var branch := Vector2(-axis.y,axis.x)
						for sign_value in [-1,1]:
							var joint: Vector2 = (center+axis*radius*0.65*sign_value).round()
							draw_line(joint,(joint-axis*2*sign_value+branch*2).round(),Color(GamePalette.FOCUS,0.65),1)
							draw_line(joint,(joint-axis*2*sign_value-branch*2).round(),Color(GamePalette.FOCUS,0.65),1)
				if radius >= 6:
					draw_rect(Rect2(center-Vector2.ONE,Vector2(2,2)),Color(GamePalette.TEXT,0.8))
		for corner in [inner.position,inner.end-Vector2(5,5)]:
			draw_rect(Rect2(corner,Vector2(5,2)),GamePalette.FOCUS)
	else:
		if state.haste_ms > 0:
			_draw_stream(inner,true)
		if state.slow_ms > 0:
			_draw_stream(inner,false)
	if charge_age < 0.42:
		var t := charge_age/0.42
		# Charge lights the actual cooldown edge, with pixels converging onto that edge.
		draw_rect(Rect2(inner.position.x,maxf(inner.position.y,line_y-1),inner.size.x,2),Color(GamePalette.SHIELD,1-t))
		for index in range(maxi(3,int(inner.size.x/10))):
			var x := roundf(inner.position.x+(index+0.5)*inner.size.x/maxi(3,int(inner.size.x/10)))
			var offset := (1-t)*7*(1 if index%2 == 0 else -1)
			var y := clampf(roundf(line_y+offset),inner.position.y,inner.end.y-2)
			draw_rect(Rect2(x,y,2,2),Color(GamePalette.SHIELD,1-t))
	if use_age < 0.18:
		draw_rect(inner,Color(GamePalette.TEXT,(1-use_age/0.18)*0.5),false,1)

func _draw_stream(inner: Rect2, fast: bool) -> void:
	var columns := maxi(2,int(inner.size.x/22))
	var rows := maxi(3,int((inner.size.y-24)/30))
	var travel_height := maxf(inner.end.y-28,1)
	var clip := Rect2(inner.position.x,28,inner.size.x,travel_height)
	var tint := GamePalette.TEXT if fast else SLOW_TINT
	var core := GamePalette.TEXT if fast else SLOW_CORE
	var direction := -1.0 if fast else 1.0
	for row in range(rows):
		for column in range(columns):
			var seed_value := row*13+column*7
			var variant := seed_value%3
			var width := float(2+variant)
			var tail_steps := 4+variant*2
			var speed := float(38+seed_value%17) if fast else float(7+seed_value%5)
			var x := roundf(inner.position.x+(column+0.5)*inner.size.x/columns+sin(clock*(1.8 if fast else 0.5)+seed_value)*2)
			var y := roundf(28+fposmod((row+0.5)*travel_height/rows+column*7+clock*speed*direction,travel_height))
			_stream_rect(Rect2(x-width/2-2,y-2,width+4,width+5),Color(GamePalette.FOCUS if fast else tint,0.07 if fast else 0.17),clip)
			for trail in range(tail_steps):
				var taper := 1.0-float(trail)/tail_steps
				var trail_width := maxf(1,roundf(width*taper))
				var point := Vector2(roundf(x-trail*0.35),roundf(y-direction*trail*2))
				_stream_rect(Rect2(point.x-trail_width/2,point.y,trail_width,2),Color(tint,0.7*taper),clip)
			_stream_rect(Rect2(x-width/2,y,width,width+1),Color(tint,0.8),clip)
			_stream_rect(Rect2(x-maxf(1,width-2)/2,y,maxf(1,width-2),width),Color(core,0.95),clip)

func _stream_rect(rect: Rect2, color: Color, clip: Rect2) -> void:
	var snapped := Rect2(rect.position.round(),rect.size)
	var visible_rect := snapped.intersection(clip)
	if visible_rect.has_area(): draw_rect(visible_rect,color)
