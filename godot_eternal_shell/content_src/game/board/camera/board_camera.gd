extends Node3D
class_name BoardCamera

signal tactical_changed(on: bool)
signal starmap_changed(on: bool)
signal view_tier_changed(tier: String) ## "battle" | "tactical" | "starmap"

@onready var cam: Camera3D = $Camera3D

var look_at_point = Vector3.ZERO
var follow_unit_id = ""
var distance: float = 140.0
var yaw = 0.0
var pitch = deg_to_rad(55.0)
var rotating = false
var panning := false
var _breathe_t := 0.0
var _look_smooth: Vector3 = Vector3.ZERO
var _look_init := false
const BREATHE_AMP := 0.35
const BREATHE_PERIOD := 24.0
const LOOK_LERP := 4.0
const LOOK_LERP_FOLLOW := 14.0

## 战场视角 — orbit close (TACTICAL_TOPDOWN.md).
const DIST_MIN := 24.0
## Baked defaults — TACTICAL_TOPDOWN.md（验收调参固化，无顶栏）。
var DIST_MAX := 485.0
const PITCH_MIN := deg_to_rad(18.0)
const PITCH_MAX := deg_to_rad(80.0)
const FOV := 42.0
## Sticky zoom past DIST_MAX → 战术俯视 (south = screen-down).
const TACTICAL_DIST_ENTER := 560.0
var TACTICAL_DIST_MIN := 360.0
## Ceiling for tactical/starmap zoom-out.
var TACTICAL_DIST_MAX := 3090.0
## Tactical further zoom-out → 星图视角.
var STARMAP_ENTER := 1400.0
const PAN_SENS := 0.22
const EDGE_PAN_SPEED_PX := 520.0
var _edge_dir := Vector2.ZERO
var _edge_depth := 0.0
var _edge_vel := Vector3.ZERO
## When valid and returns true, skip cam wheel/pan/rotate.
var block_input_fn: Callable = Callable()


func set_zoom_thresholds(battle_to_tac: float, tac_to_battle: float, tac_to_star: float, height_max: float = -1.0) -> void:
	DIST_MAX = clampf(battle_to_tac, 40.0, 600.0)
	TACTICAL_DIST_MIN = clampf(tac_to_battle, 100.0, 1500.0)
	if height_max > 0.0:
		TACTICAL_DIST_MAX = clampf(height_max, TACTICAL_DIST_MIN + 40.0, 20000.0)
	STARMAP_ENTER = clampf(tac_to_star, TACTICAL_DIST_MIN + 20.0, TACTICAL_DIST_MAX - 1.0)
	if distance > TACTICAL_DIST_MAX:
		distance = TACTICAL_DIST_MAX
		_apply()
	## Apply tier transitions immediately from the new thresholds.
	if not tactical_mode:
		if distance >= DIST_MAX - 0.01:
			enter_tactical()
		return
	if starmap_mode:
		_sync_starmap_from_distance()
		return
	## Tactical: pull below min → battle; push past enter → starmap.
	if distance <= TACTICAL_DIST_MIN + 0.5:
		exit_tactical()
	else:
		_sync_starmap_from_distance()


func mark_height_max_from_current() -> float:
	## Capture current camera height as zoom-out ceiling.
	TACTICAL_DIST_MAX = clampf(distance, TACTICAL_DIST_MIN + 40.0, 20000.0)
	if STARMAP_ENTER >= TACTICAL_DIST_MAX:
		STARMAP_ENTER = maxf(TACTICAL_DIST_MIN + 20.0, TACTICAL_DIST_MAX - 1.0)
	if distance > TACTICAL_DIST_MAX:
		distance = TACTICAL_DIST_MAX
		_apply()
	return TACTICAL_DIST_MAX

var tactical_mode := false
var starmap_mode := false
## Nadir view heading (screen-up world direction); MMB+wheel in tactical.
var tactical_yaw := 0.0
const TACTICAL_YAW_STEP := deg_to_rad(12.0)
var _saved_yaw := 0.0
var _saved_pitch := deg_to_rad(55.0)

func _ready() -> void:
	if cam:
		cam.fov = FOV
		cam.current = true
	_apply()

func view_tier() -> String:
	if starmap_mode:
		return "starmap"
	if tactical_mode:
		return "tactical"
	return "battle"

func set_follow(unit_id: String) -> void:
	if starmap_mode:
		return
	follow_unit_id = unit_id

func clear_follow_keep_look() -> void:
	follow_unit_id = ""

func update_follow_pos(pos: Vector3) -> void:
	if starmap_mode:
		return
	if follow_unit_id != "":
		look_at_point = pos
		if _look_init:
			_look_smooth = _look_smooth.lerp(pos, 0.55)
		else:
			_look_smooth = pos
			_look_init = true

func enter_tactical() -> void:
	if tactical_mode:
		return
	_saved_yaw = yaw
	_saved_pitch = pitch
	tactical_mode = true
	starmap_mode = false
	rotating = false
	panning = false
	distance = TACTICAL_DIST_ENTER
	_apply()
	tactical_changed.emit(true)
	starmap_changed.emit(false)
	view_tier_changed.emit("tactical")

func exit_tactical() -> void:
	if not tactical_mode:
		return
	var was_star := starmap_mode
	tactical_mode = false
	starmap_mode = false
	panning = false
	distance = DIST_MAX
	yaw = _saved_yaw
	pitch = clampf(_saved_pitch, PITCH_MIN, PITCH_MAX)
	_apply()
	if was_star:
		starmap_changed.emit(false)
	tactical_changed.emit(false)
	view_tier_changed.emit("battle")

func enter_starmap() -> void:
	if not tactical_mode or starmap_mode:
		return
	starmap_mode = true
	clear_follow_keep_look()
	if distance < STARMAP_ENTER:
		distance = STARMAP_ENTER
	_apply()
	starmap_changed.emit(true)
	view_tier_changed.emit("starmap")
	_dbg_zoom("enter_starmap", -1)

func exit_starmap() -> void:
	if not starmap_mode:
		return
	starmap_mode = false
	## Park just under enter line so next zoom-out re-enters cleanly.
	distance = minf(distance, STARMAP_ENTER - 1.0)
	distance = clampf(distance, TACTICAL_DIST_MIN, STARMAP_ENTER - 1.0)
	_apply()
	starmap_changed.emit(false)
	view_tier_changed.emit("tactical")
	_dbg_zoom("exit_starmap", -1)

func _sync_starmap_from_distance() -> void:
	if not tactical_mode:
		return
	## Enter as soon as height reaches STARMAP_ENTER (no +0.5 deadband).
	if distance >= STARMAP_ENTER:
		if not starmap_mode:
			enter_starmap()
	elif starmap_mode and distance < STARMAP_ENTER:
		exit_starmap()

func _dbg_zoom(msg: String, btn: int) -> void:
	# #region agent log
	var path := "H:/debug-59aff0.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify({
			"sessionId": "59aff0", "hypothesisId": "H_ZOOM",
			"location": "board_camera.zoom",
			"message": msg,
			"data": {
				"btn": btn, "dist": distance, "tac": tactical_mode,
				"star": starmap_mode, "tier": view_tier(),
				"pan": panning, "tyaw": tactical_yaw,
				"enter": STARMAP_ENTER, "runId": "tac-yaw"
			},
			"timestamp": Time.get_ticks_msec()
		}))
		f.close()
	# #endregion

func zoom_by_factor(factor: float) -> void:
	## factor < 1 zooms in; > 1 zooms out. Mirrors wheel path.
	if factor <= 0.0:
		return
	if tactical_mode:
		if starmap_mode:
			distance = clampf(distance * factor, TACTICAL_DIST_MIN, TACTICAL_DIST_MAX)
			_apply()
			_sync_starmap_from_distance()
		elif factor < 1.0 and distance <= TACTICAL_DIST_MIN + 0.5:
			exit_tactical()
		elif factor > 1.0:
			distance = minf(maxf(distance * factor, TACTICAL_DIST_MIN), TACTICAL_DIST_MAX)
			_apply()
			_sync_starmap_from_distance()
		else:
			distance = clampf(distance * factor, TACTICAL_DIST_MIN, STARMAP_ENTER - 0.01)
			_apply()
	else:
		if factor > 1.0 and distance >= DIST_MAX - 0.01:
			enter_tactical()
		else:
			distance = clampf(distance * factor, DIST_MIN, DIST_MAX)
			_apply()

func add_tactical_yaw(delta_rad: float) -> void:
	if not tactical_mode or starmap_mode:
		return
	tactical_yaw += delta_rad
	_apply()

func set_edge_pan(dir: Vector2, depth: float) -> void:
	_edge_dir = dir
	_edge_depth = clampf(depth, 0.0, 1.0)

func cut_edge_pan() -> void:
	_edge_dir = Vector2.ZERO
	_edge_depth = 0.0
	_edge_vel = Vector3.ZERO

func _screen_pan_axes() -> Array:
	if tactical_mode:
		return [
			Vector3(cos(tactical_yaw), 0.0, sin(tactical_yaw)),
			Vector3(sin(tactical_yaw), 0.0, -cos(tactical_yaw)),
		]
	return [
		Vector3(cos(yaw), 0.0, -sin(yaw)),
		Vector3(sin(yaw), 0.0, cos(yaw)),
	]

func _tick_edge_velocity(delta: float) -> void:
	## World-space velocity, same axes as middle-drag. Hotzone on = full speed.
	var desired := Vector3.ZERO
	if _edge_dir != Vector2.ZERO:
		var k := PAN_SENS * (distance / TACTICAL_DIST_ENTER) if tactical_mode else PAN_SENS * (distance / 140.0)
		var speed := EDGE_PAN_SPEED_PX * k ## full speed inside band (no depth lerp)
		var nd := _edge_dir.normalized()
		var ax: Array = _screen_pan_axes()
		## dir.y < 0 is the top band. CNC: look toward that screen edge.
		## Battle orbit `fwd` and tactical `s_up` have opposite screen-Y signs — split them.
		var y := -nd.y if tactical_mode else nd.y
		desired = (ax[0] as Vector3) * (nd.x * speed) + (ax[1] as Vector3) * (y * speed)
		clear_follow_keep_look()
	_edge_vel = desired if desired != Vector3.ZERO else Vector3.ZERO
	if _edge_vel.length_squared() < 0.04:
		_edge_vel = Vector3.ZERO
		return
	look_at_point += _edge_vel * delta
	_look_smooth = look_at_point
	_look_init = true

func pan_by_screen_delta(rel: Vector2) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var center := vp.get_visible_rect().size * 0.5
	pan_by_screen_points(center, center + rel)


func pan_by_screen_points(a: Vector2, b: Vector2) -> void:
	## Ground point under the pointer stays under the pointer. Missed rays are skipped.
	if cam == null or a.distance_squared_to(b) < 0.0000001:
		return
	var grounded: Variant = _ground_hit(a)
	var shifted: Variant = _ground_hit(b)
	if grounded == null or shifted == null:
		return
	look_at_point += (grounded as Vector3) - (shifted as Vector3)
	_look_smooth = look_at_point
	_look_init = true
	clear_follow_keep_look()
	_apply()


func _ground_hit(screen: Vector2) -> Variant:
	var origin := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.00001:
		return null
	#（地面交点比例写成 float，否则相机脚本编译失败、进对局黑屏）26.10.22 15:50 s
	var t: float = float(look_at_point.y - origin.y) / float(dir.y)
	#（地面交点比例写成 float，否则相机脚本编译失败、进对局黑屏）26.10.22 15:50 e
	if t < 0.0:
		return null
	return origin + dir * t


func release_stuck_buttons() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		panning = false
		rotating = false

## Prefer _input so wheel is not lost when board_root/_gui consumes unhandled path.
func _input(event: InputEvent) -> void:
	_handle_cam_input(event)

func _handle_cam_input(event: InputEvent) -> void:
	if block_input_fn.is_valid() and bool(block_input_fn.call()):
		## Don't leave middle-drag stuck when pointer enters HUD.
		rotating = false
		panning = false
		return
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if tactical_mode:
				panning = mb.pressed
				rotating = false
				if mb.pressed:
					clear_follow_keep_look()
				get_viewport().set_input_as_handled()
				return
			panning = false
			rotating = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			## 战术俯视：按住中键+滚轮 → 旋转朝向（不缩放）。
			if tactical_mode and not starmap_mode and panning:
				tactical_yaw -= TACTICAL_YAW_STEP
				_apply()
				_dbg_zoom("tac_yaw_ccw", mb.button_index)
				get_viewport().set_input_as_handled()
				return
			## Zoom in (拉近)
			if tactical_mode:
				if starmap_mode:
					distance = maxf(distance * 0.9, TACTICAL_DIST_MIN)
					_apply()
					_sync_starmap_from_distance()
				elif distance <= TACTICAL_DIST_MIN + 0.5:
					exit_tactical()
				else:
					distance = clampf(distance * 0.9, TACTICAL_DIST_MIN, STARMAP_ENTER - 0.01)
					_apply()
			else:
				distance = clampf(distance * 0.9, DIST_MIN, DIST_MAX)
				_apply()
			_dbg_zoom("wheel_in", mb.button_index)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if tactical_mode and not starmap_mode and panning:
				tactical_yaw += TACTICAL_YAW_STEP
				_apply()
				_dbg_zoom("tac_yaw_cw", mb.button_index)
				get_viewport().set_input_as_handled()
				return
			## Zoom out (缩小) — tactical past STARMAP_ENTER enters 星图
			if tactical_mode:
				var next_d := minf(maxf(distance * 1.1, TACTICAL_DIST_MIN), TACTICAL_DIST_MAX)
				distance = next_d
				_apply()
				_sync_starmap_from_distance()
				_dbg_zoom("wheel_out", mb.button_index)
				get_viewport().set_input_as_handled()
				return
			if distance >= DIST_MAX - 0.01:
				enter_tactical()
			else:
				distance = clampf(distance * 1.1, DIST_MIN, DIST_MAX)
				_apply()
			_dbg_zoom("wheel_out", mb.button_index)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		if tactical_mode and panning:
			pan_by_screen_points(mm.position - mm.relative, mm.position)
			get_viewport().set_input_as_handled()
		elif rotating and not tactical_mode:
			yaw -= mm.relative.x * 0.005
			pitch = clampf(pitch + mm.relative.y * 0.005, PITCH_MIN, PITCH_MAX)
			_apply()
			get_viewport().set_input_as_handled()

func tick_breathe(delta: float) -> void:
	release_stuck_buttons()
	_tick_edge_velocity(delta)
	if not _look_init:
		_look_smooth = look_at_point
		_look_init = true
	if _edge_vel == Vector3.ZERO:
		var rate = LOOK_LERP_FOLLOW if follow_unit_id != "" and not starmap_mode else LOOK_LERP
		_look_smooth = _look_smooth.lerp(look_at_point, clampf(delta * rate, 0.0, 1.0))
	if not tactical_mode and _edge_vel == Vector3.ZERO:
		_breathe_t += delta
	_apply()

func _apply() -> void:
	if cam == null:
		return
	cam.fov = FOV
	var focus = _look_smooth if _look_init else look_at_point
	#（先放父节点，再放子相机，避免父节点带动多移一截）26.10.22 15:20 s
	global_position = focus
	if tactical_mode:
		## Nadir: distance = height. tactical_yaw spins screen-up (default north = -Z).
		cam.global_position = focus + Vector3(0.0, distance, 0.0)
		var up := Vector3(sin(tactical_yaw), 0.0, -cos(tactical_yaw))
		if up.length_squared() < 0.0001:
			up = Vector3(0.0, 0.0, -1.0)
		if cam.global_position.distance_squared_to(focus) > 0.0001:
			cam.look_at(focus, up)
		return
	var cp = cos(pitch)
	var sp = sin(pitch)
	var cy = cos(yaw)
	var sy = sin(yaw)
	var offset = Vector3(sy * cp, sp, cy * cp) * distance
	var breath = Vector3.ZERO
	if follow_unit_id == "" and _edge_vel == Vector3.ZERO:
		var th = _breathe_t * TAU / BREATHE_PERIOD
		var s = sin(th)
		var c = cos(th)
		var local = Vector3(s, 0.0, s * c) * BREATHE_AMP
		var half = 0.70710678
		breath = Vector3(local.x * half - local.z * half, 0.0, local.x * half + local.z * half)
	cam.global_position = focus + offset + breath
	if cam.global_position.distance_squared_to(focus) > 0.0001:
		cam.look_at(focus, Vector3.UP)
	#（先放父节点，再放子相机，避免父节点带动多移一截）26.10.22 15:20 e
