extends Node
class_name BoardShipImpostorBaker
## Idle-bake 24 yaw impostors at 55 deg into user:// (TACTICAL_TOPDOWN). One cell per idle frame.

const SHIP_ART := preload("res://art_modules/eve_ship_art/scripts/eve_ship_art_module.gd")
const DIR := "user://content_runtime/data/board/ship_impostors"
const YAW_N := 24
const CELL := 128
const PITCH_DEG := 55.0

var manifest: Dictionary = {}
var _vp: SubViewport
var _rig: Node3D
var _cam: Camera3D
var _q: Array = []
var _busy_key := ""
var _busy_yaw := -1
var _wait := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_load_manifest()
	_vp = SubViewport.new()
	_vp.size = Vector2i(CELL, CELL)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	var world := Node3D.new()
	_vp.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(light)
	_rig = Node3D.new()
	_rig.name = "BakeRig"
	world.add_child(_rig)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	world.add_child(_cam)


func _load_manifest() -> void:
	var path := DIR.path_join("manifest.json")
	if not FileAccess.file_exists(path):
		manifest = {}
		return
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	manifest = raw if typeof(raw) == TYPE_DICTIONARY else {}


func save_manifest() -> void:
	var f := FileAccess.open(DIR.path_join("manifest.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(manifest))
		f.close()


func has_full(key: String) -> bool:
	var e = manifest.get(key, {})
	return typeof(e) == TYPE_DICTIONARY and int(e.get("ready", 0)) >= YAW_N


func tex_path(key: String) -> String:
	return DIR.path_join("%s.png" % key)


func enqueue(key: String) -> void:
	if key == "" or has_full(key) or not SHIP_ART.has_model(key):
		return
	var done := 0
	var e = manifest.get(key, {})
	if typeof(e) == TYPE_DICTIONARY:
		done = int(e.get("ready", 0))
	for i in range(done, YAW_N):
		var item := "%s:%d" % [key, i]
		if not _q.has(item):
			_q.append(item)


func tick_idle(allow: bool) -> void:
	if not allow or _q.is_empty():
		return
	if _busy_yaw >= 0:
		_wait += 1
		if _wait < 2:
			return
		_capture_busy()
		return
	var item := str(_q.pop_front())
	var parts := item.split(":")
	if parts.size() < 2:
		return
	_start_bake(parts[0], int(parts[1]))


func _start_bake(key: String, yaw_i: int) -> void:
	_clear_rig()
	var inst: Node3D = SHIP_ART.spawn_model(_rig, key, 4.0)
	if inst == null:
		return
	_busy_key = key
	_busy_yaw = yaw_i
	_wait = 0
	var yaw := deg_to_rad(float(yaw_i) * (360.0 / float(YAW_N)))
	inst.rotation.y += yaw
	var dist := 7.2
	var pitch := deg_to_rad(PITCH_DEG)
	_cam.position = Vector3(0.0, sin(pitch) * dist, cos(pitch) * dist)
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _capture_busy() -> void:
	var img: Image = _vp.get_texture().get_image()
	if img == null:
		_busy_yaw = -1
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var strip := _load_or_make(_busy_key)
	strip.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(_busy_yaw * CELL, 0))
	strip.save_png(ProjectSettings.globalize_path(tex_path(_busy_key)))
	var e: Dictionary = manifest.get(_busy_key, {})
	if typeof(e) != TYPE_DICTIONARY:
		e = {}
	e["ready"] = maxi(int(e.get("ready", 0)), _busy_yaw + 1)
	e["yaw_n"] = YAW_N
	e["cell"] = CELL
	e["pitch"] = PITCH_DEG
	manifest[_busy_key] = e
	save_manifest()
	_clear_rig()
	_busy_key = ""
	_busy_yaw = -1
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _load_or_make(key: String) -> Image:
	var p := tex_path(key)
	if FileAccess.file_exists(p):
		var img := Image.new()
		if img.load(p) == OK and img.get_height() == CELL and img.get_width() >= YAW_N * CELL:
			return img
	var blank := Image.create(YAW_N * CELL, CELL, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 0))
	return blank


func _clear_rig() -> void:
	if _rig == null:
		return
	for c in _rig.get_children():
		c.free()
