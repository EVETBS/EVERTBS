extends Node
## EveAC-style pooled float text: damage accumulates red, heal accumulates green.

const COLOR_DAMAGE := Color(1.0, 0.45, 0.35)
const COLOR_HEAL := Color(0.35, 0.95, 0.55)
const GAP_RESET_S := 1.0
## UI_AND_SHELL §5: world size = font × pixel = 2.88 (5× the old 48 × 0.012).
## Any later tier / accumulation multiplier must multiply THIS base once, never stack.
const BASE_FONT := 120
const BASE_PIXEL := 0.024
const BASE_OUTLINE := 20
const TTL_S := 0.95

var _pool: Array = []
var _active: Array = []
var _tracks: Dictionary = {}

func add_damage(world_pos: Vector3, amount: float, track_id: int) -> void:
	_add_tracked(world_pos, absf(amount), track_id, "damage")

func add_heal(world_pos: Vector3, amount: float, track_id: int) -> void:
	_add_tracked(world_pos, absf(amount), track_id, "heal")

func _add_tracked(world_pos: Vector3, amount: float, track_id: int, channel: String) -> void:
	if track_id == 0:
		return
	if channel == "damage":
		if amount < 0.0:
			return
	elif amount < 0.5:
		return
	var now := Time.get_ticks_msec() * 0.001
	var key := "%d:%s" % [track_id, channel]
	var track: Dictionary = _tracks.get(key, {})
	var last_s := float(track.get("last_s", -9999.0))
	var sum := float(track.get("sum", 0.0))
	if now - last_s > GAP_RESET_S:
		sum = amount
		track["label"] = null
	else:
		sum += amount
	track["sum"] = sum
	track["last_s"] = now
	var shown := roundi(absf(sum))
	if channel != "damage" and shown < 1:
		_tracks[key] = track
		return
	var text := ("0" if shown <= 0 else "-%d" % shown) if channel == "damage" else "+%d" % shown
	var color := COLOR_DAMAGE if channel == "damage" else COLOR_HEAL
	var y_off := 1.2 if channel == "damage" else 1.65
	var lab_v = track.get("label", null)
	if lab_v is Label3D and is_instance_valid(lab_v):
		var lab := lab_v as Label3D
		lab.text = text
		lab.modulate = color
		lab.modulate.a = 1.0
		lab.global_position = world_pos + Vector3(0, y_off, 0)
		_refresh_entry(lab)
		_tracks[key] = track
		return
	var lab2 := _spawn(world_pos, text, color, key, y_off)
	track["label"] = lab2
	_tracks[key] = track

func _spawn(world_pos: Vector3, text: String, color: Color, track_key: String, y_off: float) -> Label3D:
	var lab: Label3D
	if _pool.is_empty():
		lab = Label3D.new()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.font_size = BASE_FONT
		lab.outline_size = BASE_OUTLINE
		lab.outline_modulate = Color(0, 0, 0, 0.85)
		lab.no_depth_test = true
		lab.pixel_size = BASE_PIXEL
		add_child(lab)
	else:
		lab = _pool.pop_back()
	lab.text = text
	lab.modulate = color
	lab.font_size = BASE_FONT
	lab.pixel_size = BASE_PIXEL
	lab.global_position = world_pos + Vector3(0, y_off, 0)
	lab.visible = true
	_active.append({"label": lab, "age": 0.0, "start_y": lab.global_position.y, "track_key": track_key})
	return lab

func _refresh_entry(lab: Label3D) -> void:
	for i in _active.size():
		if _active[i].get("label") == lab:
			_active[i]["age"] = 0.0
			_active[i]["start_y"] = lab.global_position.y
			return

func _process(delta: float) -> void:
	var i := 0
	while i < _active.size():
		var e: Dictionary = _active[i]
		e["age"] = float(e.get("age", 0.0)) + delta
		var lab = e.get("label") as Label3D
		if lab == null:
			_active.remove_at(i)
			continue
		var t := float(e["age"]) / TTL_S
		lab.global_position.y = float(e["start_y"]) + t * 1.2
		lab.modulate.a = clampf(1.0 - t, 0.0, 1.0)
		_active[i] = e
		if float(e["age"]) >= TTL_S:
			var key := str(e.get("track_key", ""))
			if _tracks.has(key):
				_tracks[key]["label"] = null
			lab.visible = false
			_pool.append(lab)
			_active.remove_at(i)
		else:
			i += 1
