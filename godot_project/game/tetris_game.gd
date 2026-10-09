extends Control

## Simple Tetris — hot-update PCK content.

const COLS := 10
const ROWS := 20
const CELL := 28
const TICK := 0.45

const SHAPES: Array = [
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)], # T
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(2, 0)], # I
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(1, -1)], # O
	[Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)], # S
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1)], # Z
	[Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1)], # J
	[Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(1, -1)], # L
]

const COLORS: Array[Color] = [
	Color(0.7, 0.35, 0.9),
	Color(0.3, 0.8, 0.95),
	Color(0.95, 0.85, 0.25),
	Color(0.35, 0.85, 0.4),
	Color(0.95, 0.35, 0.35),
	Color(0.35, 0.45, 0.95),
	Color(0.95, 0.55, 0.2),
]

var _grid: Array = [] # ROWS of PackedInt32Array, -1 empty else color idx
var _piece: Array[Vector2i] = []
var _origin := Vector2i(4, 1)
var _shape_i := 0
var _score := 0
var _alive := true
var _accum := 0.0
var _version := "?"

@onready var _board: Control = $Board
@onready var _hud: Label = $HUD/Info


func _ready() -> void:
	_version = _read_version()
	_init_grid()
	_spawn()
	$TopBar/Back.pressed.connect(_back_to_menu)
	_layout_touch()
	set_process(true)
	_refresh()


func _back_to_menu() -> void:
	GameNav.go_main_menu(get_tree())


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


func _init_grid() -> void:
	_grid.clear()
	for _y in range(ROWS):
		var row := PackedInt32Array()
		row.resize(COLS)
		for x in range(COLS):
			row[x] = -1
		_grid.append(row)


func _spawn() -> void:
	_shape_i = randi() % SHAPES.size()
	_piece.clear()
	for p in SHAPES[_shape_i]:
		_piece.append(p)
	_origin = Vector2i(COLS / 2, 1)
	if not _fits(_origin, _piece):
		_alive = false


func _cells(origin: Vector2i, shape: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in shape:
		out.append(origin + p)
	return out


func _fits(origin: Vector2i, shape: Array[Vector2i]) -> bool:
	for c in _cells(origin, shape):
		if c.x < 0 or c.x >= COLS or c.y >= ROWS:
			return false
		if c.y < 0:
			continue
		if int(_grid[c.y][c.x]) >= 0:
			return false
	return true


func _lock() -> void:
	for c in _cells(_origin, _piece):
		if c.y < 0 or c.y >= ROWS:
			continue
		_grid[c.y][c.x] = _shape_i
	_clear_lines()
	_spawn()
	_refresh()


func _clear_lines() -> void:
	var y := ROWS - 1
	while y >= 0:
		var full := true
		for x in range(COLS):
			if int(_grid[y][x]) < 0:
				full = false
				break
		if full:
			_score += 100
			_grid.remove_at(y)
			var row := PackedInt32Array()
			row.resize(COLS)
			for x in range(COLS):
				row[x] = -1
			_grid.insert(0, row)
		else:
			y -= 1


func _rotate() -> void:
	if _shape_i == 2: # O
		return
	var rotated: Array[Vector2i] = []
	for p in _piece:
		rotated.append(Vector2i(-p.y, p.x))
	if _fits(_origin, rotated):
		_piece = rotated


func _soft_drop() -> void:
	var nxt := _origin + Vector2i(0, 1)
	if _fits(nxt, _piece):
		_origin = nxt
	else:
		_lock()


func _hard_drop() -> void:
	while _fits(_origin + Vector2i(0, 1), _piece):
		_origin += Vector2i(0, 1)
	_lock()


func _move(dx: int) -> void:
	var nxt := _origin + Vector2i(dx, 0)
	if _fits(nxt, _piece):
		_origin = nxt


func _process(delta: float) -> void:
	if not _alive:
		return
	_accum += delta
	while _accum >= TICK:
		_accum -= TICK
		_soft_drop()
		_refresh()


func _refresh() -> void:
	var state := "PLAYING" if _alive else "GAME OVER — R 重开"
	_hud.text = "Tetris  score %s  |  %s\ncontent %s  |  ESC/返回 主菜单" % [_score, state, _version]
	_board.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.keycode == KEY_ESCAPE:
			_back_to_menu()
			return
		if not _alive:
			if k.keycode == KEY_R:
				_restart()
			return
		match k.keycode:
			KEY_LEFT, KEY_A:
				_move(-1)
			KEY_RIGHT, KEY_D:
				_move(1)
			KEY_DOWN, KEY_S:
				_soft_drop()
			KEY_UP, KEY_W:
				_rotate()
			KEY_SPACE:
				_hard_drop()
			KEY_R:
				_restart()
		_refresh()


func _restart() -> void:
	_score = 0
	_alive = true
	_init_grid()
	_spawn()
	_refresh()


func _layout_touch() -> void:
	for child in $Touch.get_children():
		if child is Button:
			(child as Button).pressed.connect(_on_touch.bind(child.name))


func _on_touch(n: String) -> void:
	if n == "BackTouch":
		_back_to_menu()
		return
	if not _alive:
		if n == "Restart":
			_restart()
		return
	match n:
		"Left":
			_move(-1)
		"Right":
			_move(1)
		"Down":
			_soft_drop()
		"Rotate":
			_rotate()
		"Drop":
			_hard_drop()
		"Restart":
			_restart()
	_refresh()
