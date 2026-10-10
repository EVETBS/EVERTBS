extends Node3D
class_name BoardCamera

@onready var cam: Camera3D = $Camera3D

var look_at_point = Vector3.ZERO
var follow_unit_id = ""
var distance = 140.0
var yaw = 0.0
var pitch = deg_to_rad(55.0)
var rotating = false
var _breathe_t := 0.0
var _look_smooth: Vector3 = Vector3.ZERO
var _look_init := false
const BREATHE_AMP := 0.35
const BREATHE_PERIOD := 24.0
const LOOK_LERP := 4.0
const LOOK_LERP_FOLLOW := 14.0

const DIST_MIN := 24.0
const DIST_MAX := 220.0
const PITCH_MIN := deg_to_rad(18.0)
const PITCH_MAX := deg_to_rad(80.0)
const FOV := 42.0

func _ready() -> void:
	if cam:
		cam.fov = FOV
		cam.current = true
	_apply()

func set_follow(unit_id: String) -> void:
	follow_unit_id = unit_id

func clear_follow_keep_look() -> void:
	follow_unit_id = ""

func update_follow_pos(pos: Vector3) -> void:
	if follow_unit_id != "":
		look_at_point = pos
		# Keep screen center on unit — snappier follow lerp
		if _look_init:
			_look_smooth = _look_smooth.lerp(pos, 0.55)
		else:
			_look_smooth = pos
			_look_init = true

func _unhandled_input(event: InputEvent) -> void:
	_handle_cam_input(event)

func _input(event: InputEvent) -> void:
	_handle_cam_input(event)

func _handle_cam_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			rotating = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance * 0.9, DIST_MIN, DIST_MAX)
			_apply()
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance * 1.1, DIST_MIN, DIST_MAX)
			_apply()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and rotating:
		var mm = event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.005
		pitch = clampf(pitch + mm.relative.y * 0.005, PITCH_MIN, PITCH_MAX)
		_apply()
		get_viewport().set_input_as_handled()

func tick_breathe(delta: float) -> void:
	if not _look_init:
		_look_smooth = look_at_point
		_look_init = true
	var rate = LOOK_LERP_FOLLOW if follow_unit_id != "" else LOOK_LERP
	_look_smooth = _look_smooth.lerp(look_at_point, clampf(delta * rate, 0.0, 1.0))
	_breathe_t += delta
	_apply()

func _apply() -> void:
	if cam == null:
		return
	cam.fov = FOV
	var focus = _look_smooth if _look_init else look_at_point
	var cp = cos(pitch)
	var sp = sin(pitch)
	var cy = cos(yaw)
	var sy = sin(yaw)
	var offset = Vector3(sy * cp, sp, cy * cp) * distance
	# Soft breathe only when NOT following (follow must keep unit at screen center)
	var breath = Vector3.ZERO
	if follow_unit_id == "":
		var th = _breathe_t * TAU / BREATHE_PERIOD
		var s = sin(th)
		var c = cos(th)
		var local = Vector3(s, 0.0, s * c) * BREATHE_AMP
		var half = 0.70710678
		breath = Vector3(local.x * half - local.z * half, 0.0, local.x * half + local.z * half)
	# Apply on Camera3D so view center == focus (parent look_at can leave child off-center)
	cam.global_position = focus + offset + breath
	if cam.global_position.distance_squared_to(focus) > 0.0001:
		cam.look_at(focus, Vector3.UP)
	global_position = focus
	# #region agent log
	if follow_unit_id != "" and Engine.get_process_frames() % 30 == 0:
		pass  # board_root logs follow center
	# #endregion