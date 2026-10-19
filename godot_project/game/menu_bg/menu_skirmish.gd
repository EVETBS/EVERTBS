extends Node
class_name MenuSkirmish

## Rusted-Warfare-style menu backdrop: 40s locked shots over a live local skirmish.
## Presentation mirrors the EVERTBS trial board battle view: eve_ship_art models,
## compact BoardUnitOverhead (tonnage + standing bg + faction badge), turret VFX, wakes,
## and cell arcs weighted by ships on the cell.

const SHIP_ART := preload("res://art_modules/eve_ship_art/scripts/eve_ship_art_module.gd")
const DevBalance := preload("res://game/board/dev_balance.gd")
const OVERHEAD_SCR := preload("res://game/board/hud/unit_overhead.gd")
const TURRET_VFX_SCR := preload("res://game/board/fx/turret_vfx.gd")
const COMBAT_FX_SCR := preload("res://art_modules/eve_combat_fx/eve_combat_fx_module.gd")

const SHIPS_JSON := "res://data/board/ships.json"
const EQUIP_JSON := "res://data/board/equipment.json"
const SHOT_S := 40.0
## Prefetch next shot this many seconds before cut (MENU_BACKDROP §4).
const PREP_LEAD_MIN := 2.0
const PREP_LEAD_MAX := 5.0
const PREP_SPAWNS_PER_FRAME := 2
const WORK_MAX := 1000.0
const CAPTURE_PER_S := 100.0
const MAX_SYSTEMS := 30
const CONE_DOT := 0.35
const EDGE_SPACING := 78.0
const MAX_DIST := EDGE_SPACING * 12.0
const RESPAWN_S := 4.0
const HIT_CHANCE := 0.8
## Backdrop hulls use hit-count HP, not shield/armor/structure (MENU_BACKDROP §3).
const HIT_HP := 5
## Match empty_system_scale / scale tween (MENU_BACKDROP §3).
const EMPTY_SYSTEM_SCALE := 0.62
const SCALE_TWEEN_S := 0.95
const SHIP_DEATH_FX := preload("res://game/board/fx/ship_death_fx.gd")
const RING_IN := 12.0
const RING_OUT := 26.0
const UNIT_Y := 1.6
const MODEL_D := BoardTypes.HULL_DIAMETER
## Menu backdrop camera defaults (captured from live preview).
const CAM_DIST := 140.0
## Reject shots whose start or end frame holds fewer readable systems (MENU_BACKDROP §3).
const MIN_FRAMED := 4
const FRAME_TRIES := 16
## Composition tries per prep frame so direction settles inside the 2–5s lead (MENU_BACKDROP §4).
const PLAN_TRIES_PER_FRAME := 2
const READABLE_DIST := EDGE_SPACING * 6.0
const CAM_DIST_MAX := 420.0
const CAM_DIST_STEP := 40.0
const CAM_PITCH := deg_to_rad(20.80)
const CAM_FOV := 42.0
## Framing test only. Rendered camera FOV stays CAM_FOV (MENU_BACKDROP §3).
const FRAME_FOV_MUL := 1.5
const CAM_DRIFT := 36.0
const CAM_YAW_DRIFT := deg_to_rad(9.0)
const CAM_PITCH_MIN := deg_to_rad(18.0)
const CAM_PITCH_MAX := deg_to_rad(78.0)
const CAM_PITCH_RATE := deg_to_rad(28.0)
const CAM_SPEED_MIN := 0.25
const CAM_SPEED_MAX := 6.0
const CAM_SPEED_DEFAULT := 4.5
const CAM_SPEED_RATE := 0.55
const CAPTURE_SYNC_S := 0.12
const JUMP_SPEED_MUL := 3.0
const ARC_TWEEN_S := 0.35
const ARC_RETARGET_EPS := 0.022
const SPAN_MAX := deg_to_rad(120.0)
const TRAIL_LIFE := 0.85
const TON_ALIASES := {
	"battlecruiser": "battleCruiser",
	"industrial_command": "industrialCommand",
}
const OVERLAY_SETS := {
	"fleet": {"bg": "08_corp_standing_bg.png", "badge": "07_corp_fleet_badge.png"},
	"enemy": {"bg": "02_red_bg.png", "badge": "01_red_minus_badge.png"},
	"friendly": {"bg": "05_blue_bg.png", "badge": "06_friendly_badge.png"},
}

enum UState { SETTLED, MOVE, JUMP }

var _map: BigmapFromStarfield
var _board: BoardPresenter
var _cam: Camera3D
var _territory: Node3D
var _root: Node3D
var _staging: Node3D
var _vfx
var _combat_fx
var _rng := RandomNumberGenerator.new()
var _territory_dirty := false
var _legion: Array = []
var _sleepers: Array = []
var _equip: Dictionary = {}
var _ton_tex: Dictionary = {}
var _overlay_tex: Dictionary = {}
var _visible: Dictionary = {}
var _units: Array = []
var _prep_units: Array = []
var _prep: Dictionary = {}
var _prep_lead := 3.5
var _arcs: Dictionary = {}
var _shot_t := 0.0
var _cam_a := Vector3.ZERO
var _cam_b := Vector3.ZERO
var _look_a := Vector3.ZERO
var _look_b := Vector3.ZERO
var _look_side := Vector3.RIGHT
var _cam_yaw_a := 0.0
var _cam_yaw_b := 0.0
var _cam_pitch := CAM_PITCH
var _shot_cam_dist := CAM_DIST
var _last_framed := 0
var _cam_speed_mul := CAM_SPEED_DEFAULT
var _work_dirty: Dictionary = {}
var _scale_cur: Dictionary = {}
var _uid := 0
var _trail_mat: StandardMaterial3D
var allow_cam_controls := false


func setup(map: BigmapFromStarfield, board: BoardPresenter, cam: Camera3D, territory: Node3D = null) -> void:
	add_to_group("evertbs_menu_skirmish")
	DevBalance.load()
	_map = map
	_board = board
	_cam = cam
	_territory = territory
	_cam.fov = CAM_FOV
	_rng.randomize()
	_load_ships()
	_load_equipment()
	var host: Node = cam.get_parent()
	if host == null:
		host = self
	_root = Node3D.new()
	_root.name = "SkirmishUnits"
	host.add_child(_root)
	_staging = Node3D.new()
	_staging.name = "SkirmishStaging"
	host.add_child(_staging)
	_vfx = TURRET_VFX_SCR.new()
	_vfx.name = "SkirmishTurretVfx"
	host.add_child(_vfx)
	_combat_fx = COMBAT_FX_SCR.new()
	_combat_fx.name = "SkirmishCombatFx"
	host.add_child(_combat_fx)
	var world: Node3D = host as Node3D
	if world == null:
		world = _root
	_combat_fx.setup(world)
	call_deferred("_warm_ship_death_fx")
	_trail_mat = _make_trail_mat()
	_prep_lead = _rng.randf_range(PREP_LEAD_MIN, PREP_LEAD_MAX)
	_begin_shot()


func _process(delta: float) -> void:
	if _map == null or _cam == null:
		return
	_shot_t += delta
	_handle_cam_controls(delta)
	var k := clampf(_shot_t / SHOT_S, 0.0, 1.0)
	var prev_p := _cam.global_position
	_cam.global_position = _cam_a.lerp(_cam_b, k)
	var look := _look_a.lerp(_look_b, k)
	if look.distance_squared_to(_cam.global_position) > 1.0:
		_cam.look_at(look, Vector3.UP)
	if _cam.has_method("sync_from_transform"):
		_cam.call("sync_from_transform")
	# #region agent log
	if Engine.get_process_frames() % 45 == 0:
		DebugSessionLog.append("D", "menu_skirmish._process", "auto_cam", {
			"shot_t": _shot_t, "k": k,
			"prev": [prev_p.x, prev_p.y, prev_p.z],
			"pos": [_cam.global_position.x, _cam.global_position.y, _cam.global_position.z],
			"moved": prev_p.distance_to(_cam.global_position),
			"current": _cam.current, "runId": "pre-fix"
		})
	# #endregion
	if _prep.is_empty() and _shot_t >= SHOT_S - _prep_lead:
		_prep_begin()
	elif not _prep.is_empty() and not bool(_prep.get("ready", false)):
		_prep_step()
	_tick_units(delta)
	_flush_work_dirty()
	_flush_territory_colors()
	_tick_arcs(delta)
	_tick_system_scales(delta)
	_place_units()
	if _shot_t >= SHOT_S:
		_begin_shot()


func _handle_cam_controls(delta: float) -> void:
	if not allow_cam_controls:
		return
	## QE = pitch only; AD = travel speed (shot duration stays SHOT_S, distance scales).
	## Speed must not shove the look point sideways mid-shot (that felt like panning).
	var pitch_delta := 0.0
	if Input.is_key_pressed(KEY_E):
		pitch_delta += CAM_PITCH_RATE * delta
	if Input.is_key_pressed(KEY_Q):
		pitch_delta -= CAM_PITCH_RATE * delta
	if absf(pitch_delta) > 0.00001:
		var np := clampf(_cam_pitch + pitch_delta, CAM_PITCH_MIN, CAM_PITCH_MAX)
		if not is_equal_approx(np, _cam_pitch):
			_cam_pitch = np
			_rebuild_orbit_only()
			_refresh_status()
	var speed_delta := 0.0
	if Input.is_key_pressed(KEY_D):
		speed_delta += CAM_SPEED_RATE * delta
	if Input.is_key_pressed(KEY_A):
		speed_delta -= CAM_SPEED_RATE * delta
	if absf(speed_delta) > 0.00001:
		var ns := clampf(_cam_speed_mul + speed_delta, CAM_SPEED_MIN, CAM_SPEED_MAX)
		if not is_equal_approx(ns, _cam_speed_mul):
			_cam_speed_mul = ns
			_apply_speed_preserving_look()
			_refresh_status()


func _rebuild_shot_path() -> void:
	## Fresh shot: full path from anchor, length = CAM_DRIFT * speed.
	_look_b = _look_a + _look_side * (CAM_DRIFT * _cam_speed_mul)
	_rebuild_orbit_only()


func _rebuild_orbit_only() -> void:
	_cam_a = _look_a + _orbit_offset(_cam_yaw_a)
	_cam_b = _look_b + _orbit_offset(_cam_yaw_b)


func _apply_speed_preserving_look() -> void:
	## Keep the current look point fixed; only stretch remaining/past path with new speed.
	var k := clampf(_shot_t / SHOT_S, 0.0, 1.0)
	var cur := _look_a.lerp(_look_b, k)
	var dist := CAM_DRIFT * _cam_speed_mul
	_look_a = cur - _look_side * (dist * k)
	_look_b = cur + _look_side * (dist * (1.0 - k))
	_rebuild_orbit_only()


func _refresh_status() -> void:
	var pitch_deg := rad_to_deg(_cam_pitch)
	var fov := _cam.fov if _cam else CAM_FOV
	print("CAMERA_STATE pitch=%.2fdeg fov=%.2f speed×%.4f" % [pitch_deg, fov, _cam_speed_mul])
	var p := get_parent()
	if p == null or not p.get("status_label"):
		return
	var lab: Label = p.status_label
	if lab == null:
		return
	lab.text = "主菜单长镜头 %.0fs · 俯仰%.1f° FOV%.1f · 移速×%.2f · QE俯仰 AD移速" % [SHOT_S, pitch_deg, fov, _cam_speed_mul]


# --- data ---------------------------------------------------------------

func _load_ships() -> void:
	_legion.clear()
	_sleepers.clear()
	var data = _read_json(SHIPS_JSON)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("menu skirmish: missing ships.json")
		return
	for s in data.get("ships", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sid := str(s.get("id", ""))
		if sid == "":
			continue
		if sid.begins_with("sleeper_"):
			_sleepers.append(s)
		else:
			_legion.append(s)
	print("menu skirmish ships legion=", _legion.size(), " sleepers=", _sleepers.size())


func _load_equipment() -> void:
	var data = _read_json(EQUIP_JSON)
	_equip = data if typeof(data) == TYPE_DICTIONARY else {}


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	return data


func _build_weapons(def: Dictionary) -> Array:
	var out: Array = []
	var fit: Dictionary = def.get("fit", {})
	var pd_mul := 1.0
	for h in fit.get("hidden", []):
		if typeof(h) == TYPE_DICTIONARY and str(h.get("kind", "")) == "pd_damage_mul":
			pd_mul = float(h.get("value", 1.0))
	for h in fit.get("hidden", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var kind := str(h.get("kind", ""))
		if kind != "weapon" and kind != "pd":
			continue
		var eq: Dictionary = _equip.get(str(h.get("ref", "")), {})
		if eq.is_empty():
			continue
		var cycle := maxf(float(eq.get("cycle_s", 2.0)), 0.2)
		var w := {
			"fx": str(eq.get("fx", "rail")),
			"cycle": cycle,
			"cd": _rng.randf() * cycle,
			"range": int(h.get("range_cells", eq.get("range_cells", 0))),
			"heal": 0.0,
			"dmg": 0.0,
		}
		if kind == "pd":
			w["dmg"] = float(eq.get("damage", 0)) * pd_mul
			for _i in maxi(int(h.get("count", 1)), 1):
				var wc := w.duplicate()
				wc["cd"] = _rng.randf() * cycle
				out.append(wc)
			continue
		if str(eq.get("kind", "")) == "remote_armor":
			w["heal"] = float(eq.get("heal_armor", 0))
		else:
			w["dmg"] = float(eq.get("damage_emp", 0)) + float(eq.get("damage_thermal", 0)) \
				+ float(eq.get("damage_kinetic", 0)) + float(eq.get("damage_explosive", 0))
		out.append(w)
	return out


# --- shots --------------------------------------------------------------

func _begin_shot() -> void:
	var t0 := Time.get_ticks_msec()
	var used_prep := bool(_prep.get("ready", false))
	_shot_t = 0.0
	_work_dirty.clear()
	if used_prep:
		_commit_prepared_shot()
	else:
		_abort_prep()
		_begin_shot_sync()
	_prep.clear()
	_prep_lead = _rng.randf_range(PREP_LEAD_MIN, PREP_LEAD_MAX)
	var commit_ms := Time.get_ticks_msec() - t0
	# #region agent log
	DebugSessionLog.append("MB1", "menu_skirmish._begin_shot", "commit", {
		"used_prep": used_prep, "commit_ms": commit_ms,
		"systems": _visible.size(), "units": _units.size(),
		"next_lead": _prep_lead, "runId": "pre-fix"
	})
	# #endregion
	_snap_system_scales()
	_refresh_status()
	print(
		"menu skirmish shot systems=", _visible.size(),
		" framed=", _last_framed,
		" cam_dist=", snappedf(_shot_cam_dist, 0.1),
		" units=", _units.size(), " speed×", _cam_speed_mul,
		" prep=", used_prep, " commit_ms=", commit_ms
	)


func _begin_shot_sync() -> void:
	## Fallback when prefetch missed the window (first shot / hitch).
	_clear_units()
	var old_visible := _visible
	var plan := _plan_shot_camera()
	if plan.is_empty():
		return
	_apply_camera_plan(plan)
	_visible = plan["visible"]
	for sid in old_visible.keys():
		if not _visible.has(sid):
			_reset_arcs(str(sid))
	_arcs.clear()
	_roll_occupation()
	if _board:
		_board.set_visible_systems(_visible)
	_flush_territory_colors()
	_spawn_distribution()
	_tick_arcs(0.0, true)


func _plan_shot_camera() -> Dictionary:
	## Sync fallback only (first shot / prep miss). Normal cuts lock direction in prep.
	var best: Dictionary = {}
	var best_n := -1
	for _try in FRAME_TRIES:
		var plan := _compose_shot(CAM_DIST)
		if plan.is_empty():
			return {}
		var n := int(plan.get("framed", 0))
		if n > best_n:
			best = plan
			best_n = n
		if n >= MIN_FRAMED:
			return plan
	return _widen_until_framed(best)


func _compose_shot(dist: float) -> Dictionary:
	var anchor := _random_system_id()
	if anchor == "":
		return {}
	var look: Vector3 = _map.systems[anchor]["center"]
	look.y = UNIT_Y
	var yaw_a := _rng.randf() * TAU
	var yaw_sign := 1.0 if _rng.randf() < 0.5 else -1.0
	var yaw_b := yaw_a + CAM_YAW_DRIFT * yaw_sign
	var look_side := Vector3(cos(yaw_a), 0.0, -sin(yaw_a))
	var look_b := look + look_side * (CAM_DRIFT * _cam_speed_mul)
	return _shot_from(anchor, look, look_b, look_side, yaw_a, yaw_b, dist)


func _retarget_distance(plan: Dictionary, dist: float) -> Dictionary:
	return _shot_from(
		str(plan["anchor"]), plan["look_a"], plan["look_b"], plan["look_side"],
		float(plan["yaw_a"]), float(plan["yaw_b"]), dist
	)


func _shot_from(
	anchor: String, look: Vector3, look_b: Vector3, look_side: Vector3,
	yaw_a: float, yaw_b: float, dist: float
) -> Dictionary:
	var cam_a := look + _offset_at(yaw_a, dist)
	var cam_b := look_b + _offset_at(yaw_b, dist)
	var fwd := look - cam_a
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3(0, 0, -1)
	var plan := {
		"anchor": anchor,
		"look_a": look,
		"look_b": look_b,
		"cam_a": cam_a,
		"cam_b": cam_b,
		"yaw_a": yaw_a,
		"yaw_b": yaw_b,
		"look_side": look_side,
		"cam_dist": dist,
		"visible": _pick_visible(cam_a, fwd),
	}
	plan["framed"] = _framed_span(plan)
	return plan


func _framed_span(plan: Dictionary) -> int:
	return mini(
		_count_framed(plan["cam_a"], plan["look_a"]),
		_count_framed(plan["cam_b"], plan["look_b"])
	)


func _view_aspect() -> float:
	if _cam and is_instance_valid(_cam):
		var vp := _cam.get_viewport()
		if vp:
			var s := vp.get_visible_rect().size
			if s.y > 1.0:
				return maxf(s.x / s.y, 0.5)
	return 16.0 / 9.0


func _count_framed(cam_pos: Vector3, look: Vector3) -> int:
	var fwd := look - cam_pos
	if fwd.length_squared() < 1.0:
		return 0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(fwd).normalized()
	var fov := (_cam.fov if _cam else CAM_FOV) * FRAME_FOV_MUL
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var tan_h := tan_v * _view_aspect()
	var n := 0
	for sid in _map.systems.keys():
		var center: Vector3 = _map.systems[sid]["center"]
		var to := center - cam_pos
		var dist := to.length()
		if dist > READABLE_DIST or dist < 1.0:
			continue
		var dir := to / dist
		var df := dir.dot(fwd)
		if df <= 0.05:
			continue
		if absf(dir.dot(right) / df) > tan_h:
			continue
		if absf(dir.dot(up) / df) > tan_v:
			continue
		n += 1
	return n


func _apply_camera_plan(plan: Dictionary) -> void:
	_shot_cam_dist = float(plan.get("cam_dist", CAM_DIST))
	_last_framed = int(plan.get("framed", 0))
	_look_a = plan["look_a"]
	_look_b = plan["look_b"]
	_cam_a = plan["cam_a"]
	_cam_b = plan["cam_b"]
	_cam_yaw_a = float(plan["yaw_a"])
	_cam_yaw_b = float(plan["yaw_b"])
	_look_side = plan["look_side"]
	_cam.global_position = _cam_a
	if _look_a.distance_squared_to(_cam_a) > 1.0:
		_cam.look_at(_look_a, Vector3.UP)
	if _cam.has_method("sync_from_transform"):
		_cam.call("sync_from_transform")


func _prep_begin() -> void:
	_abort_prep()
	_prep = {
		"phase": "plan",
		"ready": false,
		"t0": Time.get_ticks_msec(),
		"spawn_i": 0,
		"plan_try": 0,
		"best_plan": {},
		"best_framed": -1,
		"pull_dist": CAM_DIST + CAM_DIST_STEP,
	}
	# #region agent log
	DebugSessionLog.append("MB1", "menu_skirmish._prep_begin", "start", {
		"shot_t": _shot_t, "lead": _prep_lead, "runId": "pre-fix"
	})
	# #endregion


func _prep_step() -> void:
	if _prep.is_empty() or bool(_prep.get("ready", false)):
		return
	match str(_prep.get("phase", "")):
		"plan":
			_prep_plan_try_step()
		"plan_pull":
			_prep_plan_pull_step()
		"occ":
			_prep_build_occupation_and_specs()
			_prep["phase"] = "spawn"
			_prep["spawn_i"] = 0
		"spawn":
			_prep_spawn_budget()
		_:
			_prep["ready"] = true


func _prep_lock_plan(plan: Dictionary) -> void:
	## Direction is final once locked; commit must not re-roll.
	_prep["plan"] = plan
	_prep["phase"] = "occ"
	# #region agent log
	DebugSessionLog.append("MB1", "menu_skirmish._prep_lock_plan", "direction_locked", {
		"framed": int(plan.get("framed", 0)),
		"cam_dist": float(plan.get("cam_dist", CAM_DIST)),
		"tries": int(_prep.get("plan_try", 0)),
		"anchor": str(plan.get("anchor", "")),
		"elapsed_ms": Time.get_ticks_msec() - int(_prep.get("t0", Time.get_ticks_msec())),
		"runId": "pre-fix"
	})
	# #endregion


func _prep_plan_try_step() -> void:
	var budget := PLAN_TRIES_PER_FRAME
	while budget > 0 and int(_prep.get("plan_try", 0)) < FRAME_TRIES:
		budget -= 1
		_prep["plan_try"] = int(_prep.get("plan_try", 0)) + 1
		var plan := _compose_shot(CAM_DIST)
		if plan.is_empty():
			_abort_prep()
			return
		var n := int(plan.get("framed", 0))
		if n > int(_prep.get("best_framed", -1)):
			_prep["best_plan"] = plan
			_prep["best_framed"] = n
		if n >= MIN_FRAMED:
			_prep_lock_plan(plan)
			return
	if int(_prep.get("plan_try", 0)) < FRAME_TRIES:
		return
	if int(_prep.get("best_framed", -1)) >= MIN_FRAMED:
		_prep_lock_plan(_prep.get("best_plan", {}))
		return
	_prep["phase"] = "plan_pull"
	_prep["pull_dist"] = CAM_DIST + CAM_DIST_STEP


func _prep_plan_pull_step() -> void:
	var best: Dictionary = _prep.get("best_plan", {})
	if best.is_empty():
		_abort_prep()
		return
	var dist := float(_prep.get("pull_dist", CAM_DIST + CAM_DIST_STEP))
	if dist > CAM_DIST_MAX + 0.01:
		_prep_lock_plan(best)
		return
	var widened := _retarget_distance(best, dist)
	var n := int(widened.get("framed", 0))
	if n > int(_prep.get("best_framed", -1)):
		_prep["best_plan"] = widened
		_prep["best_framed"] = n
		best = widened
	_prep["pull_dist"] = dist + CAM_DIST_STEP
	if n >= MIN_FRAMED or float(_prep["pull_dist"]) > CAM_DIST_MAX + 0.01:
		_prep_lock_plan(best)


func _widen_until_framed(best: Dictionary) -> Dictionary:
	if best.is_empty():
		return {}
	var best_n := int(best.get("framed", 0))
	if best_n >= MIN_FRAMED:
		return best
	var dist := CAM_DIST + CAM_DIST_STEP
	while dist <= CAM_DIST_MAX + 0.01:
		var widened := _retarget_distance(best, dist)
		var n := int(widened.get("framed", 0))
		if n > best_n:
			best = widened
			best_n = n
		if best_n >= MIN_FRAMED:
			return best
		dist += CAM_DIST_STEP
	return best


func _prep_build_occupation_and_specs() -> void:
	var plan: Dictionary = _prep.get("plan", {})
	var visible: Dictionary = plan.get("visible", {})
	var sov_pool: Array = [
		BigmapFromStarfield.VIEWER_FAC,
		BigmapFromStarfield.ALLY_FAC,
		BigmapFromStarfield.HOSTILE_FAC,
		BigmapFromStarfield.HOSTILE2_FAC,
	]
	var occ: Dictionary = {}
	var specs: Array = []
	for sid in visible.keys():
		var s := str(sid)
		if not _map.systems.has(s):
			continue
		var cells: Array = _map.systems[s]["cells"]
		var row: Array = []
		var picks: Array = []
		for i in cells.size():
			var kind := int(cells[i].get("kind", 0))
			var owner := 0
			var work := 0.0
			if kind == BoardKinds.CellKind.EMPTY:
				owner = 0
				work = 0.0
			elif kind == BoardKinds.CellKind.SOV:
				if _rng.randf() < 0.12:
					owner = 0
				else:
					owner = int(sov_pool[_rng.randi_range(0, sov_pool.size() - 1)])
				work = WORK_MAX
			else:
				owner = _rng.randi_range(0, 3)
				work = WORK_MAX
			row.append({"i": i, "owner": owner, "work": work, "kind": kind})
			if kind != BoardKinds.CellKind.EMPTY:
				picks.append(i)
		occ[s] = row
		picks.shuffle()
		for k in mini(3, picks.size()):
			var ci: int = picks[k]
			specs.append({"sid": s, "cell": ci, "fac": int(row[ci]["owner"])})
	_prep["occ"] = occ
	_prep["spawn_specs"] = specs


func _prep_spawn_budget() -> void:
	var specs: Array = _prep.get("spawn_specs", [])
	var i := int(_prep.get("spawn_i", 0))
	var n := 0
	while n < PREP_SPAWNS_PER_FRAME and i < specs.size():
		var sp: Dictionary = specs[i]
		_spawn_unit(str(sp["sid"]), int(sp["cell"]), int(sp["fac"]), true)
		i += 1
		n += 1
	_prep["spawn_i"] = i
	if i >= specs.size():
		_prep["ready"] = true
		_prep["phase"] = "done"
		var prep_ms := Time.get_ticks_msec() - int(_prep.get("t0", Time.get_ticks_msec()))
		# #region agent log
		DebugSessionLog.append("MB1", "menu_skirmish._prep_spawn_budget", "ready", {
			"prep_ms": prep_ms, "units": _prep_units.size(),
			"specs": specs.size(), "systems": (_prep.get("plan", {}) as Dictionary).get("visible", {}).size(),
			"runId": "pre-fix"
		})
		# #endregion


func _apply_occ_snapshot(occ: Dictionary) -> void:
	for sid in occ.keys():
		var s := str(sid)
		if not _map.systems.has(s):
			continue
		var cells: Array = _map.systems[s]["cells"]
		for entry in occ[s]:
			var i := int(entry.get("i", -1))
			if i < 0 or i >= cells.size():
				continue
			cells[i]["owner"] = int(entry.get("owner", 0))
			cells[i]["work"] = float(entry.get("work", 0.0))
	_territory_dirty = true


func _commit_prepared_shot() -> void:
	var plan: Dictionary = _prep.get("plan", {})
	var old_visible := _visible
	_clear_units()
	_apply_occ_snapshot(_prep.get("occ", {}))
	_apply_camera_plan(plan)
	_visible = plan.get("visible", {})
	for sid in old_visible.keys():
		if not _visible.has(sid):
			_reset_arcs(str(sid))
	_arcs.clear()
	if _board:
		_board.set_visible_systems(_visible)
	_flush_territory_colors()
	## Promote staged units into the live sim (avoid reparent look_at edge cases).
	for u in _prep_units:
		var node: Node3D = u.get("node") as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if _root and node.get_parent() != _root:
			var gpos := node.global_position
			var old_p := node.get_parent()
			if old_p:
				old_p.remove_child(node)
			_root.add_child(node)
			node.global_position = gpos
		node.visible = true
		_assign_goal(u)
		_units.append(u)
	_prep_units.clear()
	_tick_arcs(0.0, true)


func _abort_prep() -> void:
	for u in _prep_units:
		var node: Node3D = u.get("node")
		if node and is_instance_valid(node):
			node.queue_free()
	_prep_units.clear()
	if _staging:
		for c in _staging.get_children():
			c.queue_free()
	_prep.clear()


func _orbit_offset(yaw: float) -> Vector3:
	return _offset_at(yaw, _shot_cam_dist)


func _offset_at(yaw: float, dist: float) -> Vector3:
	var flat := dist * cos(_cam_pitch)
	return Vector3(sin(yaw) * flat, dist * sin(_cam_pitch), cos(yaw) * flat)


func _random_system_id() -> String:
	var keys: Array = _map.systems.keys()
	if keys.is_empty():
		return ""
	return str(keys[_rng.randi_range(0, keys.size() - 1)])


func _pick_visible(cam_pos: Vector3, fwd: Vector3) -> Dictionary:
	var cam_xz := Vector2(cam_pos.x, cam_pos.z)
	var scored: Array = []
	for sid in _map.systems.keys():
		var c: Vector3 = _map.systems[sid]["center"]
		var rel := Vector2(c.x, c.z) - cam_xz
		var dist := rel.length()
		if dist > MAX_DIST or dist < 1.0:
			continue
		if rel.normalized().dot(Vector2(fwd.x, fwd.z)) < CONE_DOT:
			continue
		scored.append({"id": str(sid), "d": dist})
	scored.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	var out: Dictionary = {}
	for i in mini(MAX_SYSTEMS, scored.size()):
		out[str(scored[i]["id"])] = true
	return out


func _roll_occupation() -> void:
	## SOV owners use the same faction pool as bake-time paint (1..4, ~12% unowned).
	## Other cells may be sleeper-owned (0) for skirmish spawns.
	var sov_pool: Array = [
		BigmapFromStarfield.VIEWER_FAC,
		BigmapFromStarfield.ALLY_FAC,
		BigmapFromStarfield.HOSTILE_FAC,
		BigmapFromStarfield.HOSTILE2_FAC,
	]
	for sid in _visible.keys():
		for c in _map.systems[sid]["cells"]:
			var kind := int(c.get("kind", 0))
			if kind == BoardKinds.CellKind.EMPTY:
				c["owner"] = 0
				c["work"] = 0.0
				continue
			if kind == BoardKinds.CellKind.SOV:
				if _rng.randf() < 0.12:
					c["owner"] = 0
				else:
					c["owner"] = int(sov_pool[_rng.randi_range(0, sov_pool.size() - 1)])
			else:
				c["owner"] = _rng.randi_range(0, 3)
			c["work"] = WORK_MAX
	_territory_dirty = true


func _spawn_distribution() -> void:
	for sid in _visible.keys():
		var cells: Array = _map.systems[str(sid)]["cells"]
		var picks: Array = []
		for i in cells.size():
			if int(cells[i].get("kind", 0)) != BoardKinds.CellKind.EMPTY:
				picks.append(i)
		picks.shuffle()
		for k in mini(3, picks.size()):
			var ci: int = picks[k]
			_spawn_unit(str(sid), ci, int(cells[ci].get("owner", 0)))


# --- units --------------------------------------------------------------

func _pool_for(fac: int) -> Array:
	var pool: Array = _sleepers if fac == 0 else _legion
	if pool.is_empty():
		pool = _legion if not _legion.is_empty() else _sleepers
	return pool


func _spawn_unit(sid: String, cell_i: int, fac: int, staged: bool = false) -> void:
	var pool := _pool_for(fac)
	if pool.is_empty():
		return
	var parent: Node3D = _staging if staged and _staging else _root
	if parent == null:
		return
	_uid += 1
	var node := Node3D.new()
	node.name = "U%d" % _uid
	parent.add_child(node)
	var trail := MeshInstance3D.new()
	trail.name = "Trail"
	trail.top_level = true
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.material_override = _trail_mat
	trail.visible = false
	node.add_child(trail)
	var oh: Node3D = OVERHEAD_SCR.new()
	oh.name = "Overhead"
	oh.top_level = true
	node.add_child(oh)
	var u := {
		"id": _uid,
		"fac": fac,
		"node": node,
		"oh": oh,
		"trail": trail,
		"trail_pts": [],
		"trail_streams": [],
		"trail_nozzles": [],
		"trail_acc": 0.0,
		"sid": sid,
		"cell": cell_i,
		"goal_sid": sid,
		"goal_cell": cell_i,
		"state": UState.SETTLED,
		"pos": _slot_pos(sid, cell_i, 0, 1),
		"face": Vector3(0, 0, -1),
		"capturing": false,
		"dead": false,
		"respawn": 0.0,
	}
	_apply_hull(u, pool[_rng.randi_range(0, pool.size() - 1)])
	node.global_position = u["pos"]
	if staged:
		node.visible = false
		_prep_units.append(u)
	else:
		_units.append(u)
		_assign_goal(u)


func _apply_hull(u: Dictionary, def: Dictionary) -> void:
	var fac := int(u["fac"])
	u["def"] = def
	u["hp_max"] = float(HIT_HP)
	u["hp"] = float(HIT_HP)
	u["resist"] = clampf(float(def.get("resist", 0)) / 100.0, 0.0, 0.9)
	u["spd"] = clampf(float(def.get("speed", 150.0)) * 0.06, 9.0, 22.0)
	u["ton"] = str(def.get("tonnage", "destroyer"))
	u["weapons"] = _build_weapons(def)
	var node: Node3D = u["node"]
	var old := node.get_node_or_null("Model")
	if old:
		node.remove_child(old)
		old.queue_free()
	var model_key := str(def.get("model", def.get("id", "")))
	var hull_d := DevBalance.hull_diameter(str(def.get("id", "")))
	var model: Node3D = null
	if SHIP_ART.has_model(model_key):
		model = SHIP_ART.spawn_model(node, model_key, hull_d, str(def.get("id", "")))
	if model == null:
		model = SHIP_ART.make_fallback_sphere(hull_d * 0.18, "Model")
		node.add_child(model)
	u["trail_nozzles"] = SHIP_ART.engine_nozzle_locals(model_key, model) if model != null else []
	u["trail_streams"] = []
	u["trail_pts"] = []
	var oh = u["oh"]
	oh.set_alive_view(true)
	oh.set_tonnage_icon(_tonnage_icon(str(u["ton"])))
	oh.set_compact_icon_only(true)
	var show_badge := fac != 0
	oh.set_show_faction_badge(show_badge)
	if show_badge:
		var ov := _overlay_set(_rel_for(fac))
		oh.set_tonnage_overlays(ov.get("bg"), ov.get("badge"))
	else:
		oh.set_tonnage_overlays(null, null)


func _rel_for(fac: int) -> String:
	match fac:
		BigmapFromStarfield.VIEWER_FAC:
			return "self"
		BigmapFromStarfield.ALLY_FAC:
			return "ally"
		_:
			return "hostile"


func _overlay_set(rel: String) -> Dictionary:
	var key := "friendly"
	if rel == "self" or rel == "fleet" or rel == "allied":
		key = "fleet"
	elif rel == "hostile" or rel == "enemy":
		key = "enemy"
	if _overlay_tex.has(key):
		return _overlay_tex[key]
	var conf: Dictionary = OVERLAY_SETS[key]
	var out := {"bg": null, "badge": null}
	for k2 in ["bg", "badge"]:
		var p2 := "res://assets/ui/sprites/tonnage_overlays/%s" % conf[k2]
		if not ResourceLoader.exists(p2) and key == "fleet":
			p2 = "res://assets/ui/sprites/tonnage_overlays/%s" % (
				"04_fleet_member_bg.png" if k2 == "bg" else "03_fleet_member.png"
			)
		if ResourceLoader.exists(p2):
			out[k2] = load(p2)
	_overlay_tex[key] = out
	return out


func _tonnage_icon(ton: String) -> Texture2D:
	if _ton_tex.has(ton):
		return _ton_tex[ton]
	var file_key := str(TON_ALIASES.get(ton, ton))
	var path := "res://assets/ui/sprites/tonnage/%s_32.png" % file_key
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/sprites/tonnage/%s_32.png" % ton
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/sprites/tonnage/destroyer_32.png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_ton_tex[ton] = tex
	return tex


func dev_rescale_hull(ship_id: String) -> void:
	var hull_d := DevBalance.hull_diameter(ship_id)
	for u in _units:
		_rescale_unit_hull(u, ship_id, hull_d)
	for u in _prep_units:
		_rescale_unit_hull(u, ship_id, hull_d)


func _rescale_unit_hull(u: Dictionary, ship_id: String, hull_d: float) -> void:
	var def: Dictionary = u.get("def", {})
	if str(def.get("id", "")) != ship_id:
		return
	var node: Node3D = u.get("node")
	if node == null or not is_instance_valid(node):
		return
	var model := node.get_node_or_null("Model") as Node3D
	if model == null:
		return
	var model_key := str(def.get("model", def.get("id", "")))
	if SHIP_ART.has_model(model_key):
		SHIP_ART.apply_pose_and_scale(model, model_key, hull_d, ship_id)
		u["trail_nozzles"] = SHIP_ART.engine_nozzle_locals(model_key, model)
		return
	var mi := model as MeshInstance3D
	if mi != null and mi.mesh is SphereMesh:
		var sph := mi.mesh as SphereMesh
		sph.radius = hull_d * 0.18
		sph.height = sph.radius * 2.0


func _make_trail_mat() -> StandardMaterial3D:
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.vertex_color_use_as_albedo = true
	tmat.albedo_color = Color(1, 1, 1, 1)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.emission_enabled = true
	tmat.emission = Color(0.35, 0.75, 1.0)
	tmat.emission_energy_multiplier = 1.8
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tmat.no_depth_test = false
	tmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return tmat


func _clear_units() -> void:
	_units.clear()
	if _root == null:
		return
	for c in _root.get_children():
		c.queue_free()


# --- simulation ---------------------------------------------------------

func _tick_units(delta: float) -> void:
	for u in _units:
		if bool(u["dead"]):
			u["respawn"] = float(u["respawn"]) - delta
			if float(u["respawn"]) <= 0.0:
				_respawn(u)
			continue
		match int(u["state"]):
			UState.JUMP:
				_tick_jump(u, delta)
			UState.MOVE:
				_tick_move(u, delta)
			_:
				_tick_settled(u, delta)
		_tick_trail(u, delta)


func _tick_settled(u: Dictionary, delta: float) -> void:
	_tick_weapons(u, delta)
	if bool(u["dead"]):
		return
	if _hostile_on_cell(u):
		u["capturing"] = false
		return
	var cell := _cell_of(u)
	if cell.is_empty() or int(cell.get("kind", 0)) == BoardKinds.CellKind.EMPTY:
		_assign_goal(u)
		_start_move_if_needed(u)
		return
	var fac := int(u["fac"])
	var owner := int(cell.get("owner", 0))
	## Own / ally cells are never flipped — leave and find a real target.
	if _is_allied(fac, owner) and float(cell.get("work", 0.0)) >= WORK_MAX - 0.5:
		u["capturing"] = false
		_assign_goal(u)
		_start_move_if_needed(u)
		return
	if owner != fac and _is_allied(fac, owner):
		u["capturing"] = false
		_assign_goal(u)
		_start_move_if_needed(u)
		return
	## Same polarity as BoardCaptureSystem: work falls from WORK_MAX→0; rim mid spreads.
	if not bool(u["capturing"]):
		u["capturing"] = true
		u["cap_sync_t"] = 0.0
		if owner != fac and float(cell.get("work", WORK_MAX)) >= WORK_MAX - 0.5:
			cell["work"] = WORK_MAX
		cell["capturing"] = fac
		_mark_work_dirty(str(u["sid"]))
	cell["capturing"] = fac
	cell["work"] = maxf(0.0, float(cell.get("work", WORK_MAX)) - CAPTURE_PER_S * delta)
	u["cap_sync_t"] = float(u.get("cap_sync_t", 0.0)) + delta
	if float(u["cap_sync_t"]) >= CAPTURE_SYNC_S:
		u["cap_sync_t"] = 0.0
		_mark_work_dirty(str(u["sid"]))
	if float(cell["work"]) <= 0.01:
		cell["owner"] = fac
		cell["work"] = WORK_MAX
		cell["capturing"] = 0
		u["capturing"] = false
		_mark_work_dirty(str(u["sid"]))
		if int(cell.get("kind", -1)) == BoardKinds.CellKind.SOV:
			_territory_dirty = true
		_assign_goal(u)
		_start_move_if_needed(u)


func _start_move_if_needed(u: Dictionary) -> void:
	if str(u["goal_sid"]) != str(u["sid"]) or int(u["goal_cell"]) != int(u["cell"]):
		u["state"] = UState.MOVE
		u["capturing"] = false


func _tick_move(u: Dictionary, delta: float) -> void:
	var sid := str(u["sid"])
	var goal_sid := str(u["goal_sid"])
	if goal_sid == sid:
		var target := _slot_pos(sid, int(u["goal_cell"]), 0, 1)
		if _arc_step(u, target, delta):
			u["cell"] = int(u["goal_cell"])
			u["state"] = UState.SETTLED
			u["capturing"] = false
		return
	var fac := int(u["fac"])
	var hop := _next_hop(sid, goal_sid, fac)
	if hop == "" or hop == sid:
		## No passable gate toward goal — capture something here or retarget.
		_assign_goal(u)
		if str(u["goal_sid"]) == sid:
			u["state"] = UState.SETTLED
		return
	var gate := _gate_cell(sid, hop)
	if gate < 0:
		_assign_goal(u)
		u["state"] = UState.SETTLED
		return
	if _arc_step(u, _slot_pos(sid, gate, 0, 1), delta):
		u["cell"] = gate
		if _can_pass_gate(fac, sid, gate):
			_begin_jump(u, hop)
		else:
			## Door closed: occupy this gate instead of jumping.
			u["goal_sid"] = sid
			u["goal_cell"] = gate
			u["state"] = UState.SETTLED
			u["capturing"] = false


func _begin_jump(u: Dictionary, hop: String) -> void:
	if hop == "" or not _map.systems.has(hop):
		u["goal_sid"] = u["sid"]
		u["goal_cell"] = u["cell"]
		u["state"] = UState.SETTLED
		return
	var back := _gate_cell(hop, str(u["sid"]))
	if back < 0:
		back = _nearest_cell(hop, u["pos"])
	u["jump_sid"] = hop
	u["jump_cell"] = back
	u["state"] = UState.JUMP


func _tick_jump(u: Dictionary, delta: float) -> void:
	var hop := str(u["jump_sid"])
	var dest := _slot_pos(hop, int(u["jump_cell"]), 0, 1)
	var pos: Vector3 = u["pos"]
	var d := dest - pos
	var step := float(u["spd"]) * JUMP_SPEED_MUL * delta
	if d.length() <= step:
		u["pos"] = dest
		u["sid"] = hop
		u["cell"] = int(u["jump_cell"])
		if str(u["goal_sid"]) == hop and int(u["goal_cell"]) == int(u["cell"]):
			u["state"] = UState.SETTLED
		else:
			u["state"] = UState.MOVE
		return
	u["face"] = d.normalized()
	u["pos"] = pos + d.normalized() * step


func _arc_step(u: Dictionary, target: Vector3, delta: float) -> bool:
	## Ring travel: sweep the shorter way around the wedge band, not a chord through the hub.
	var center: Vector3 = _map.systems[str(u["sid"])]["center"]
	var pos: Vector3 = u["pos"]
	var p := pos - center
	var t := target - center
	var ang := atan2(p.x, -p.z)
	var r := Vector2(p.x, p.z).length()
	var tang := atan2(t.x, -t.z)
	var tr := Vector2(t.x, t.z).length()
	var step := float(u["spd"]) * delta
	var r_mid := maxf((r + tr) * 0.5, 4.0)
	var d_ang := wrapf(tang - ang, -PI, PI)
	var ang_step := step / r_mid
	if absf(d_ang) <= ang_step and absf(tr - r) <= step:
		u["face"] = _flat_dir(target - pos, u["face"])
		u["pos"] = target
		return true
	ang += clampf(d_ang, -ang_step, ang_step)
	r = move_toward(r, tr, step * 0.6)
	var np := center + Vector3(sin(ang) * r, UNIT_Y, -cos(ang) * r)
	u["face"] = _flat_dir(np - pos, u["face"])
	u["pos"] = np
	u["cell"] = _cell_at_angle(str(u["sid"]), ang)
	return false


func _flat_dir(v: Vector3, fallback: Vector3) -> Vector3:
	v.y = 0.0
	if v.length_squared() < 0.000001:
		return fallback
	return v.normalized()


func _tick_weapons(u: Dictionary, delta: float) -> void:
	for w in u["weapons"]:
		w["cd"] = float(w["cd"]) - delta
		if float(w["cd"]) > 0.0:
			continue
		var tgt := _pick_target(u, w)
		if tgt.is_empty():
			w["cd"] = 0.25
			continue
		w["cd"] = float(w["cycle"])
		var shot_n := int(w.get("shot_n", 0))
		w["shot_n"] = shot_n + 1
		var from: Vector3 = _fx_emit_point(u, shot_n, str(w.get("fx", "")))
		var to: Vector3 = _fx_hit_point(tgt)
		u["face"] = _flat_dir(to - from, u["face"])
		if float(w["heal"]) > 0.0:
			## Repair still plays; it does not refund hit-count HP.
			_fire_fx(str(w["fx"]), from, to)
			continue
		var hit := _rng.randf() <= HIT_CHANCE
		if not hit:
			_fire_fx(str(w["fx"]), from, _miss_point(from, to, tgt))
			continue
		_fire_fx(str(w["fx"]), from, to)
		tgt["hp"] = float(tgt["hp"]) - 1.0
		if float(tgt["hp"]) <= 0.0:
			_kill(tgt)


func _fire_fx(fx: String, from: Vector3, to: Vector3) -> void:
	## Beam width tracks the battle-view plate side so it reads at backdrop distance.
	if from.distance_squared_to(to) < 0.25:
		return
	var dist := _cam.global_position.distance_to(from.lerp(to, 0.5))
	var plate_sc := clampf(dist / OVERHEAD_SCR.REF_DIST, OVERHEAD_SCR.SC_MIN, OVERHEAD_SCR.SC_MAX)
	var thick := OVERHEAD_SCR.BADGE_WU * plate_sc * 0.25
	if _combat_fx != null:
		_combat_fx.play_shot(fx, from, to, thick, 0.5)
	if _vfx != null:
		_vfx.play_tips(fx, from, to, thick, 0.5)


func _pick_target(u: Dictionary, w: Dictionary) -> Dictionary:
	var heal := float(w["heal"]) > 0.0
	var best: Dictionary = {}
	var best_steps := 1 << 20
	var n: int = _map.systems[str(u["sid"])]["cells"].size()
	for o in _units:
		if bool(o["dead"]) or int(o["id"]) == int(u["id"]) or int(o["state"]) != UState.SETTLED:
			continue
		if str(o["sid"]) != str(u["sid"]):
			continue
		var friendly := _is_allied(int(u["fac"]), int(o["fac"]))
		if heal != friendly:
			continue
		if heal and float(o["hp"]) >= float(o["hp_max"]) - 1.0:
			continue
		var steps := _arc_steps(int(u["cell"]), int(o["cell"]), n)
		if steps > int(w["range"]):
			continue
		if steps < best_steps:
			best_steps = steps
			best = o
	return best


func _arc_steps(a: int, b: int, n: int) -> int:
	var d := absi(a - b)
	return mini(d, maxi(n - d, 0))


func _unit_art_model(u: Dictionary) -> Node3D:
	var node: Node3D = u.get("node")
	if node == null or not is_instance_valid(node):
		return null
	var model := node.get_node_or_null("Model") as Node3D
	if model == null or not is_instance_valid(model) or not model.is_inside_tree():
		return null
	return model


func _fx_emit_point(u: Dictionary, shot_n: int = 0, fx_kind: String = "") -> Vector3:
	var model := _unit_art_model(u)
	if model != null:
		return SHIP_ART.muzzle_world_at(model, shot_n, fx_kind)
	return u.get("pos", Vector3.ZERO) as Vector3


func _fx_hit_point(u: Dictionary) -> Vector3:
	var model := _unit_art_model(u)
	if model != null:
		return SHIP_ART.hull_center_world(model)
	return u.get("pos", Vector3.ZERO) as Vector3


func _miss_point(from: Vector3, anchor: Vector3, tgt: Dictionary) -> Vector3:
	var graze_r := 0.55
	var hull := _unit_art_model(tgt)
	if hull != null:
		graze_r = SHIP_ART.graze_radius_world(hull)
	else:
		var ton_w := 1.0
		match str(tgt.get("ton", "destroyer")):
			"frigate": ton_w = 1.0
			"destroyer": ton_w = 2.0
			"cruiser": ton_w = 3.0
			"battlecruiser": ton_w = 4.0
			_: ton_w = 5.0
		graze_r = maxf(0.55, 0.55 * ton_w)
	return SHIP_ART.graze_miss_world(from, anchor, graze_r, _rng.randi())


func _hostile_on_cell(u: Dictionary) -> bool:
	for o in _units:
		if bool(o["dead"]) or int(o["id"]) == int(u["id"]) or int(o["state"]) != UState.SETTLED:
			continue
		if str(o["sid"]) != str(u["sid"]) or int(o["cell"]) != int(u["cell"]):
			continue
		if not _is_allied(int(u["fac"]), int(o["fac"])):
			return true
	return false


func _warm_ship_death_fx() -> void:
	SHIP_DEATH_FX.warm()


func _kill(u: Dictionary) -> void:
	u["dead"] = true
	u["hp"] = 0.0
	u["respawn"] = RESPAWN_S
	var node_pos: Node3D = u["node"]
	if node_pos:
		SHIP_DEATH_FX.spawn(self, node_pos.global_position, str(u.get("ton", "")))
	u["capturing"] = false
	u["trail_pts"] = []
	var node: Node3D = u["node"]
	node.visible = false
	(u["trail"] as MeshInstance3D).visible = false
	u["oh"].set_alive_view(false)


func _respawn(u: Dictionary) -> void:
	var spot := _respawn_spot(int(u["fac"]))
	if str(spot["sid"]) == "":
		u["respawn"] = RESPAWN_S
		return
	var pool := _pool_for(int(u["fac"]))
	if not pool.is_empty():
		_apply_hull(u, pool[_rng.randi_range(0, pool.size() - 1)])
	u["hp"] = float(u["hp_max"])
	u["dead"] = false
	u["capturing"] = false
	u["state"] = UState.SETTLED
	u["sid"] = spot["sid"]
	u["cell"] = spot["cell"]
	u["goal_sid"] = spot["sid"]
	u["goal_cell"] = spot["cell"]
	u["pos"] = _slot_pos(str(spot["sid"]), int(spot["cell"]), 0, 1)
	var node: Node3D = u["node"]
	node.visible = true
	node.global_position = u["pos"]
	_assign_goal(u)


func _respawn_spot(fac: int) -> Dictionary:
	var stations: Array = []
	var owned: Array = []
	for sid in _visible.keys():
		var cells: Array = _map.systems[str(sid)]["cells"]
		for i in cells.size():
			var c: Dictionary = cells[i]
			var kind := int(c.get("kind", 0))
			if kind == BoardKinds.CellKind.EMPTY or int(c.get("owner", -1)) != fac:
				continue
			if kind == BoardKinds.CellKind.STATION:
				stations.append({"sid": str(sid), "cell": i})
			else:
				owned.append({"sid": str(sid), "cell": i})
	if not stations.is_empty():
		return stations[_rng.randi_range(0, stations.size() - 1)]
	if not owned.is_empty():
		return owned[_rng.randi_range(0, owned.size() - 1)]
	var keys: Array = _visible.keys()
	if keys.is_empty():
		return {"sid": "", "cell": 0}
	return {"sid": str(keys[_rng.randi_range(0, keys.size() - 1)]), "cell": 0}


func _cell_of(u: Dictionary) -> Dictionary:
	if not _map.systems.has(str(u["sid"])):
		return {}
	var cells: Array = _map.systems[str(u["sid"])]["cells"]
	var i := int(u["cell"])
	if i < 0 or i >= cells.size():
		return {}
	return cells[i]


func _is_allied(a: int, b: int) -> bool:
	if a == b:
		return true
	## Viewer(1) and Ally(2) share a coalition; nobody else does.
	var v := BigmapFromStarfield.VIEWER_FAC
	var al := BigmapFromStarfield.ALLY_FAC
	return (a == v and b == al) or (a == al and b == v)


func _can_pass_gate(fac: int, sid: String, gate_i: int) -> bool:
	## Same rule as BoardMapModel.can_pass_gate (MENU_BACKDROP / STARMAP §3).
	if gate_i < 0 or not _map.systems.has(sid):
		return false
	var cells: Array = _map.systems[sid]["cells"]
	if gate_i >= cells.size():
		return false
	var c: Dictionary = cells[gate_i]
	if int(c.get("kind", -1)) != BoardKinds.CellKind.GATE:
		return false
	var owner := int(c.get("owner", 0))
	if owner == 0:
		return false
	return _is_allied(fac, owner)


func _cell_wanted(c: Dictionary, fac: int) -> bool:
	if int(c.get("kind", 0)) == BoardKinds.CellKind.EMPTY:
		return false
	var owner := int(c.get("owner", 0))
	if owner == fac:
		return float(c.get("work", 0.0)) < WORK_MAX - 0.5
	## Never target a coalition ally's cell (even mid-capture).
	if _is_allied(fac, owner):
		return false
	return true


func _assign_goal(u: Dictionary) -> void:
	var fac := int(u["fac"])
	var sid := str(u["sid"])
	var cells: Array = _map.systems[sid]["cells"]
	var here_cell := int(u["cell"])
	var best_i := -1
	var best_steps := 1 << 20
	for i in cells.size():
		if not _cell_wanted(cells[i], fac):
			continue
		var s := _arc_steps(here_cell, i, cells.size())
		if s < best_steps:
			best_steps = s
			best_i = i
	if best_i >= 0:
		u["goal_sid"] = sid
		u["goal_cell"] = best_i
		return
	var best := ""
	var best_cell := -1
	var best_d := 1.0e20
	var here: Vector3 = _map.systems[sid]["center"]
	for osid in _visible.keys():
		if str(osid) == sid:
			continue
		if _next_hop(sid, str(osid), fac) == "":
			continue
		var ocells: Array = _map.systems[str(osid)]["cells"]
		for i in ocells.size():
			if not _cell_wanted(ocells[i], fac):
				continue
			var d := here.distance_squared_to(_map.systems[str(osid)]["center"])
			if d < best_d:
				best_d = d
				best = str(osid)
				best_cell = i
	if best != "":
		u["goal_sid"] = best
		u["goal_cell"] = best_cell
		return
	## Whole shot already ours: patrol to a random cell so the screen keeps moving.
	var keys: Array = _visible.keys()
	if keys.is_empty():
		return
	var rsid := str(keys[_rng.randi_range(0, keys.size() - 1)])
	var rcells: Array = _map.systems[rsid]["cells"]
	u["goal_sid"] = rsid
	u["goal_cell"] = _rng.randi_range(0, rcells.size() - 1)


func _next_hop(src: String, dst: String, fac: int = -1) -> String:
	if src == dst or not _visible.has(dst):
		return dst
	var q: Array = [src]
	var prev: Dictionary = {src: ""}
	var qi := 0
	while qi < q.size():
		var cur: String = q[qi]
		qi += 1
		if cur == dst:
			break
		for link in _map.systems[cur]["links"]:
			var nxt := str(link)
			if not _visible.has(nxt) or prev.has(nxt):
				continue
			var gate_i := _gate_cell(cur, nxt)
			if fac >= 0 and not _can_pass_gate(fac, cur, gate_i):
				continue
			prev[nxt] = cur
			q.append(nxt)
	if not prev.has(dst):
		return ""
	var step := dst
	while str(prev.get(step, "")) != src and str(prev.get(step, "")) != "":
		step = str(prev[step])
	return step


func _gate_cell(sid: String, to_id: String) -> int:
	if not _map.systems.has(sid):
		return -1
	var cells: Array = _map.systems[sid]["cells"]
	for i in cells.size():
		if int(cells[i].get("kind", -1)) == BoardKinds.CellKind.GATE and str(cells[i].get("gate_to", "")) == to_id:
			return i
	return -1


func _nearest_cell(sid: String, pos: Vector3) -> int:
	var center: Vector3 = _map.systems[sid]["center"]
	var p := pos - center
	return _cell_at_angle(sid, atan2(p.x, -p.z))


func _cell_at_angle(sid: String, ang: float) -> int:
	var cells: Array = _map.systems[sid]["cells"]
	var a := fposmod(ang, TAU)
	for i in cells.size():
		var c: Dictionary = cells[i]
		var half := float(c.get("angle_half", 0.0))
		var rel := fposmod(a - (float(c.get("angle_center", 0.0)) - half), TAU)
		if rel <= half * 2.0:
			return i
	return 0


# --- arcs (trial board: weight = 1 + ships on the cell) -----------------

func _cell_min_span(c: Dictionary) -> float:
	if int(c.get("kind", -1)) == BoardKinds.CellKind.GATE:
		return deg_to_rad(30.0)
	return deg_to_rad(8.0)


func _compute_spans(cells: Array, weights: PackedFloat32Array) -> PackedFloat32Array:
	var n := cells.size()
	var mins := PackedFloat32Array()
	mins.resize(n)
	var total := 0.0
	for i in n:
		mins[i] = _cell_min_span(cells[i])
		total += weights[i]
	var spans := PackedFloat32Array()
	spans.resize(n)
	for i in n:
		spans[i] = TAU * weights[i] / maxf(total, 0.001)
	for _iter in 12:
		var locked := 0.0
		var free_w := 0.0
		var free_i: Array = []
		for i in n:
			if spans[i] <= mins[i] + 1e-5:
				spans[i] = mins[i]
				locked += mins[i]
			elif spans[i] >= SPAN_MAX - 1e-5:
				spans[i] = SPAN_MAX
				locked += SPAN_MAX
			else:
				free_i.append(i)
				free_w += weights[i]
		var remain := TAU - locked
		if free_i.is_empty() or remain <= 1e-6 or free_w <= 1e-6:
			break
		var changed := false
		for i in free_i:
			var c := clampf(remain * weights[i] / free_w, mins[i], SPAN_MAX)
			if absf(c - spans[i]) > 1e-5:
				changed = true
			spans[i] = c
		if not changed:
			break
	var ssum := 0.0
	for i in n:
		ssum += spans[i]
	if ssum > 1e-6:
		for i in n:
			spans[i] *= TAU / ssum
	return spans


func _cell_weights(sid: String) -> PackedFloat32Array:
	var n: int = _map.systems[sid]["cells"].size()
	var w := PackedFloat32Array()
	w.resize(n)
	w.fill(1.0)
	for u in _units:
		if bool(u["dead"]) or int(u["fac"]) == 0 or int(u["state"]) == UState.JUMP:
			continue
		if str(u["sid"]) != sid:
			continue
		var ci := int(u["cell"])
		if ci >= 0 and ci < n:
			w[ci] += 1.0
	return w


func _current_spans(sid: String) -> PackedFloat32Array:
	var cells: Array = _map.systems[sid]["cells"]
	var out := PackedFloat32Array()
	out.resize(cells.size())
	for i in cells.size():
		out[i] = maxf(float(cells[i].get("angle_half", PI / float(cells.size()))) * 2.0, 0.001)
	return out


func _write_spans(sid: String, spans: PackedFloat32Array) -> void:
	var sys: Dictionary = _map.systems[sid]
	var cells: Array = sys["cells"]
	var a := float(sys.get("ring_phase", 0.0))
	for i in cells.size():
		cells[i]["angle_half"] = spans[i] * 0.5
		cells[i]["angle_center"] = fposmod(a + spans[i] * 0.5, TAU)
		a += spans[i]


func _reset_arcs(sid: String) -> void:
	var cells: Array = _map.systems[sid]["cells"]
	var w := PackedFloat32Array()
	w.resize(cells.size())
	w.fill(1.0)
	_write_spans(sid, _compute_spans(cells, w))
	_sync(sid)


func _tick_arcs(delta: float, snap: bool = false) -> void:
	for sid_v in _visible.keys():
		var sid := str(sid_v)
		var cells: Array = _map.systems[sid]["cells"]
		if cells.size() < 2:
			continue
		var desired := _compute_spans(cells, _cell_weights(sid))
		var st: Dictionary = _arcs.get(sid, {})
		if snap or st.is_empty():
			_arcs[sid] = {"from": desired, "to": desired, "t": 1.0}
			_write_spans(sid, desired)
			_sync(sid)
			continue
		var to_sp: PackedFloat32Array = st["to"]
		var max_d := 0.0
		for i in cells.size():
			max_d = maxf(max_d, absf(desired[i] - to_sp[i]))
		if max_d > ARC_RETARGET_EPS:
			st["from"] = _current_spans(sid)
			st["to"] = desired
			st["t"] = 0.0
		var t := float(st["t"])
		if t >= 1.0:
			continue
		t = minf(1.0, t + delta / ARC_TWEEN_S)
		st["t"] = t
		var e := t * t * (3.0 - 2.0 * t)
		var from_sp: PackedFloat32Array = st["from"]
		var dst_sp: PackedFloat32Array = st["to"]
		var spans := PackedFloat32Array()
		spans.resize(cells.size())
		var ssum := 0.0
		for i in cells.size():
			spans[i] = lerpf(from_sp[i], dst_sp[i], e)
			ssum += spans[i]
		for i in cells.size():
			spans[i] *= TAU / maxf(ssum, 0.001)
		_write_spans(sid, spans)
		_sync(sid)


func _mark_work_dirty(sid: String) -> void:
	_work_dirty[sid] = true


func _flush_work_dirty() -> void:
	if _work_dirty.is_empty():
		return
	for sid in _work_dirty.keys():
		_sync(str(sid))
	_work_dirty.clear()


func _sync(sid: String) -> void:
	if _board:
		_board.sync_system(sid)


func _flush_territory_colors() -> void:
	if not _territory_dirty:
		return
	_territory_dirty = false
	if _territory == null or _map == null:
		return
	var n := TerritoryBaker.sync_site_colors(_territory, _map)
	# #region agent log
	DebugSessionLog.append("BG", "menu_skirmish._flush_territory_colors", "sov_sync", {
		"layers": n, "visible": _visible.size(), "runId": "pre-fix"
	})
	# #endregion


# --- placement / presentation -------------------------------------------

func _slot_pos(sid: String, cell_i: int, slot: int, total: int) -> Vector3:
	var sys: Dictionary = _map.systems[sid]
	var cells: Array = sys["cells"]
	if cell_i < 0 or cell_i >= cells.size():
		return sys["center"]
	var c: Dictionary = cells[cell_i]
	var sc := _system_visual_scale(sid)
	return SHIP_ART.sector_slot_pos(
		sys["center"], float(c.get("angle_center", 0.0)), float(c.get("angle_half", PI / 12.0)),
		RING_IN * sc, RING_OUT * sc, slot, total, UNIT_Y
	)


func _system_visual_scale(sid: String) -> float:
	if _board and _board.has_method("visual_scale_of"):
		return float(_board.visual_scale_of(sid))
	return float(_scale_cur.get(sid, 1.0))


func _presence_sid(u: Dictionary) -> String:
	var origin := str(u.get("sid", ""))
	if int(u.get("state", UState.SETTLED)) != UState.JUMP or _map == null:
		return origin
	var dest := str(u.get("jump_sid", origin))
	if dest == "" or not _map.systems.has(dest) or not _map.systems.has(origin):
		return origin
	var pos: Vector3 = u.get("pos", _map.systems[origin]["center"])
	var co: Vector3 = _map.systems[origin]["center"]
	var cd: Vector3 = _map.systems[dest]["center"]
	if pos.distance_squared_to(cd) < pos.distance_squared_to(co):
		return dest
	return origin


func _target_system_scales() -> Dictionary:
	var want: Dictionary = {}
	for sid in _visible.keys():
		want[str(sid)] = EMPTY_SYSTEM_SCALE
	for u in _units:
		if bool(u.get("dead", false)):
			continue
		var sid := _presence_sid(u)
		if want.has(sid):
			want[sid] = 1.0
	return want


func _snap_system_scales() -> void:
	if _board == null or not _board.has_method("apply_visual_scale"):
		return
	var want := _target_system_scales()
	for sid in want.keys():
		var s := float(want[sid])
		_scale_cur[sid] = s
		_board.apply_visual_scale(str(sid), s)


func _tick_system_scales(delta: float) -> void:
	if _board == null or not _board.has_method("apply_visual_scale"):
		return
	var want := _target_system_scales()
	var step := absf(1.0 - EMPTY_SYSTEM_SCALE) / SCALE_TWEEN_S * delta
	for sid in want.keys():
		var tgt := float(want[sid])
		var cur := float(_scale_cur.get(sid, tgt))
		var nxt := move_toward(cur, tgt, step)
		_scale_cur[sid] = nxt
		if absf(nxt - cur) > 0.0008:
			_board.apply_visual_scale(str(sid), nxt)


func _place_units() -> void:
	var groups: Dictionary = {}
	for u in _units:
		if bool(u["dead"]) or int(u["state"]) != UState.SETTLED:
			continue
		var key := "%s:%d" % [str(u["sid"]), int(u["cell"])]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(u)
	for key in groups.keys():
		var members: Array = groups[key]
		for i in members.size():
			var u: Dictionary = members[i]
			var tgt := _slot_pos(str(u["sid"]), int(u["cell"]), i, members.size())
			var pos: Vector3 = u["pos"]
			u["pos"] = pos.lerp(tgt, 0.15)
	for u in _units:
		if bool(u["dead"]):
			continue
		var node: Node3D = u["node"]
		var pos: Vector3 = u["pos"]
		node.global_position = pos
		var face: Vector3 = u["face"]
		if face.length_squared() > 0.0001:
			node.look_at(pos + face, Vector3.UP)
		u["oh"].face_camera(_cam, pos)


func _ensure_trail_nozzles(u: Dictionary) -> Array:
	var locals: Array = u.get("trail_nozzles", [])
	if not locals.is_empty():
		return locals
	var node: Node3D = u.get("node")
	if node == null:
		return locals
	var model := node.get_node_or_null("Model") as Node3D
	if model == null:
		return locals
	var model_key := str(model.get_meta("model_key", ""))
	if model_key == "":
		var def: Dictionary = u.get("def", {})
		model_key = str(def.get("model", def.get("id", "")))
	locals = SHIP_ART.engine_nozzle_locals(model_key, model)
	u["trail_nozzles"] = locals
	return locals

func _trail_heads_world(u: Dictionary) -> Array:
	var heads: Array = []
	var node: Node3D = u.get("node")
	if node != null:
		var model := node.get_node_or_null("Model") as Node3D
		var locals := _ensure_trail_nozzles(u)
		if model != null and not locals.is_empty():
			heads = SHIP_ART.engine_nozzle_worlds(model, locals)
	if heads.is_empty():
		var fd: Vector3 = u.get("face", Vector3(0, 0, -1))
		var stern: Vector3 = u["pos"] - fd * 1.1
		stern.y = UNIT_Y + 0.15
		heads.append(stern)
	return heads

func _tick_trail(u: Dictionary, delta: float) -> void:
	var trail: MeshInstance3D = u["trail"]
	var moving := int(u["state"]) != UState.SETTLED
	var heads: Array = _trail_heads_world(u) if moving else []
	var streams: Array = u.get("trail_streams", [])
	if moving:
		while streams.size() < heads.size():
			streams.append([])
		while streams.size() > heads.size():
			streams.remove_at(streams.size() - 1)
	var acc := float(u["trail_acc"]) + delta
	var do_stamp: bool = moving and acc >= 0.05
	if do_stamp:
		acc = 0.0
	var any_pts := false
	for si in range(maxi(streams.size(), heads.size() if moving else 0)):
		var pts: Array = streams[si] if si < streams.size() and typeof(streams[si]) == TYPE_ARRAY else []
		var aged: Array = []
		for p in pts:
			var age := float(p["age"]) + delta
			if age < TRAIL_LIFE:
				aged.append({"pos": p["pos"], "age": age})
		pts = aged
		if do_stamp and si < heads.size():
			var head: Vector3 = heads[si]
			if pts.is_empty() or (pts[pts.size() - 1]["pos"] as Vector3).distance_to(head) >= 0.12:
				pts.append({"pos": head, "age": 0.0})
			while pts.size() > 24:
				pts.remove_at(0)
		if si < streams.size():
			streams[si] = pts
		elif not pts.is_empty():
			streams.append(pts)
		if pts.size() >= 2:
			any_pts = true
	u["trail_acc"] = acc
	u["trail_streams"] = streams
	u["trail_pts"] = streams[0] if not streams.is_empty() else []
	if not any_pts:
		trail.visible = false
		trail.mesh = null
		return
	trail.mesh = _trail_mesh_streams(streams)
	trail.global_position = Vector3.ZERO
	trail.visible = true


func _trail_mesh_streams(streams: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w := 0.11
	var any := false
	for stream in streams:
		if typeof(stream) != TYPE_ARRAY:
			continue
		var pts: Array = stream
		if pts.size() < 2:
			continue
		for i in range(pts.size() - 1):
			var a: Vector3 = pts[i]["pos"]
			var b: Vector3 = pts[i + 1]["pos"]
			var dir := b - a
			dir.y = 0.0
			if dir.length_squared() < 0.0001:
				continue
			dir = dir.normalized()
			var side := Vector3(-dir.z, 0, dir.x) * half_w
			var c0 := Color(0.45, 0.85, 1.0, clampf(1.0 - float(pts[i]["age"]) / TRAIL_LIFE, 0.0, 1.0) * 0.55)
			var c1 := Color(0.45, 0.85, 1.0, clampf(1.0 - float(pts[i + 1]["age"]) / TRAIL_LIFE, 0.0, 1.0) * 0.55)
			var up := Vector3(0, half_w, 0)
			for off in [side, up]:
				st.set_color(c0); st.add_vertex(a + off)
				st.set_color(c1); st.add_vertex(b + off)
				st.set_color(c1); st.add_vertex(b - off)
				st.set_color(c0); st.add_vertex(a + off)
				st.set_color(c1); st.add_vertex(b - off)
				st.set_color(c0); st.add_vertex(a - off)
			any = true
	return st.commit() if any else null


func _trail_mesh(pts: Array) -> ArrayMesh:
	return _trail_mesh_streams([pts])
