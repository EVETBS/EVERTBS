extends Control

## Breakout-style 弹球 — hot-update demo.

const FIELD_W := 640.0
const FIELD_H := 480.0
const PADDLE_W := 100.0
const PADDLE_H := 16.0
const BALL_R := 8.0
const BRICK_COLS := 8
const BRICK_ROWS := 5
const BRICK_GAP := 4.0

var _origin := Vector2.ZERO
var _paddle_x := 0.0
var _ball := Vector2.ZERO
var _vel := Vector2(220, -280)
var _bricks: Array = [] # {rect: Rect2, alive: bool, color: Color}
var _score := 0
var _lives := 3
var _alive := true
var _launched := false
var _version := "?"

@onready var _board: Control = $Board
@onready var _hud: Label = $HUD/Info


func _ready() -> void:
	_version = _read_version()
	$TopBar/Back.pressed.connect(func(): GameNav.go_main_menu(get_tree()))
	_layout_touch()
	_reset_round(true)
	set_process(true)
	_refresh()


func _read_version() -> String:
	var path := "user://online_update/applied_version.json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(data) == TYPE_DICTIONARY and data.has("version"):
				return str(data["version"])
	return "(editor)"


func _field_origin() -> Vector2:
	return Vector2((_board.size.x - FIELD_W) * 0.5, (_board.size.y - FIELD_H) * 0.5)


func _build_bricks() -> void:
	_bricks.clear()
	var top := 40.0
	var side := 20.0
	var bw := (FIELD_W - side * 2 - BRICK_GAP * (BRICK_COLS - 1)) / BRICK_COLS
	var bh := 22.0
	var palette: Array[Color] = [
		Color(0.95, 0.35, 0.4),
		Color(0.95, 0.6, 0.25),
		Color(0.95, 0.85, 0.3),
		Color(0.35, 0.85, 0.55),
		Color(0.35, 0.65, 0.95),
	]
	for row in range(BRICK_ROWS):
		for col in range(BRICK_COLS):
			var x := side + col * (bw + BRICK_GAP)
			var y := top + row * (bh + BRICK_GAP)
			_bricks.append({
				"rect": Rect2(x, y, bw, bh),
				"alive": true,
				"color": palette[row % palette.size()],
			})


func _reset_round(full: bool) -> void:
	_origin = _field_origin()
	_paddle_x = FIELD_W * 0.5 - PADDLE_W * 0.5
	_ball = Vector2(FIELD_W * 0.5, FIELD_H - 60)
	_vel = Vector2(220 if randf() > 0.5 else -220, -280)
	_launched = false
	if full:
		_score = 0
		_lives = 3
		_alive = true
		_build_bricks()


func _paddle_rect() -> Rect2:
	return Rect2(_paddle_x, FIELD_H - 36, PADDLE_W, PADDLE_H)


func _process(delta: float) -> void:
	if not _alive:
		return
	_origin = _field_origin()
	# keyboard hold
	var move := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		move -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		move += 1.0
	_paddle_x = clampf(_paddle_x + move * 420.0 * delta, 0.0, FIELD_W - PADDLE_W)

	if not _launched:
		_ball = Vector2(_paddle_x + PADDLE_W * 0.5, FIELD_H - 52)
		_board.queue_redraw()
		return

	_ball += _vel * delta
	# walls
	if _ball.x < BALL_R:
		_ball.x = BALL_R
		_vel.x = absf(_vel.x)
	elif _ball.x > FIELD_W - BALL_R:
		_ball.x = FIELD_W - BALL_R
		_vel.x = -absf(_vel.x)
	if _ball.y < BALL_R:
		_ball.y = BALL_R
		_vel.y = absf(_vel.y)

	# paddle
	var pr := _paddle_rect()
	if _vel.y > 0 and _ball.y + BALL_R >= pr.position.y and _ball.y - BALL_R <= pr.end.y:
		if _ball.x >= pr.position.x and _ball.x <= pr.end.x:
			_ball.y = pr.position.y - BALL_R
			_vel.y = -absf(_vel.y)
			var hit := (_ball.x - (pr.position.x + PADDLE_W * 0.5)) / (PADDLE_W * 0.5)
			_vel.x = clampf(_vel.x + hit * 120.0, -420.0, 420.0)

	# bricks
	for b in _bricks:
		if not b["alive"]:
			continue
		var r: Rect2 = b["rect"]
		if _circle_hits_rect(_ball, BALL_R, r):
			b["alive"] = false
			_score += 10
			_bounce_off_rect(r)
			break

	# miss
	if _ball.y > FIELD_H + 20:
		_lives -= 1
		if _lives <= 0:
			_alive = false
		else:
			_launched = false
			_ball = Vector2(_paddle_x + PADDLE_W * 0.5, FIELD_H - 52)
		_refresh()

	# win
	var remain := 0
	for b2 in _bricks:
		if b2["alive"]:
			remain += 1
	if remain == 0 and _alive:
		_score += 100
		_build_bricks()
		_launched = false

	_refresh()


func _circle_hits_rect(c: Vector2, radius: float, r: Rect2) -> bool:
	var nearest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	return nearest.distance_to(c) <= radius


func _bounce_off_rect(r: Rect2) -> void:
	var nearest := Vector2(clampf(_ball.x, r.position.x, r.end.x), clampf(_ball.y, r.position.y, r.end.y))
	var delta := _ball - nearest
	if absf(delta.x) > absf(delta.y):
		_vel.x = -_vel.x
	else:
		_vel.y = -_vel.y


func _refresh() -> void:
	var state := "PLAYING" if _alive else "GAME OVER — R 重开"
	if _alive and not _launched:
		state = "空格 / 点击发射"
	_hud.text = "弹球  score %s  lives %s  |  %s\ncontent %s  |  ESC/返回 主菜单" % [_score, _lives, state, _version]
	_board.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				GameNav.go_main_menu(get_tree())
			KEY_SPACE:
				if _alive:
					_launched = true
			KEY_R:
				_reset_round(true)
				_refresh()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _alive:
			_launched = true


func _layout_touch() -> void:
	for child in $Touch.get_children():
		if child is Button:
			(child as Button).pressed.connect(_on_touch.bind(child.name))


func _on_touch(n: String) -> void:
	match n:
		"Left":
			_paddle_x = clampf(_paddle_x - 40.0, 0.0, FIELD_W - PADDLE_W)
		"Right":
			_paddle_x = clampf(_paddle_x + 40.0, 0.0, FIELD_W - PADDLE_W)
		"Launch":
			if _alive:
				_launched = true
		"Restart":
			_reset_round(true)
	_refresh()
