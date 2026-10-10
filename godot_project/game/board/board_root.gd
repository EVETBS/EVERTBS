extends Node3D
## EVETBS board test orchestrator 鈥?bricks talk via AdminProxy.

const DATA := preload("res://game/board/board_data.gd")
const MAP_MODEL := preload("res://game/board/map/map_model.gd")
const CAPTURE := preload("res://game/board/capture/capture_system.gd")
const PILOTS := preload("res://game/board/pilots/pilot_system.gd")
const AI := preload("res://game/board/ai/ai_controller.gd")
const NAV := preload("res://game/board/player_nav/player_nav.gd")
const FX := preload("res://game/board/combat/combat_formulas.gd")
const OVERHEAD_SCR := preload("res://game/board/hud/unit_overhead.gd")
const VFX_SCR := preload("res://game/board/fx/turret_vfx.gd")
const FLOAT_SCR := preload("res://game/board/fx/float_text_pool.gd")

var data: BoardData
var map: BoardMapModel
var capture: BoardCaptureSystem
var pilots_sys: BoardPilotSystem
var ai: BoardAiController
var admin: BoardAdminProxy

var pilots: Array = []
var units: Array = []
var next_unit_i = 1
var selection: Array = [] # unit ids
var control_groups: Dictionary = {}
var viewer_faction = 1
var rng = RandomNumberGenerator.new()

var drag_start = Vector2.ZERO
var dragging = false
var box_selecting = false
var _starmap_scale_dirty = false
var _starmap_rebuild_acc = 0.0
var _capture_rebuild_acc = 0.0
var _detail_dirty = true
var _box_overlay: ColorRect
var _order_queue: Array = []  # {id, sys, cell}
var _move_lines: Dictionary = {}  # unit_id -> MeshInstance3D
var _gate_stagger: Dictionary = {}  # "sys:cell" -> next delay
var popup: PopupMenu
var hud: CanvasLayer
var left_list: ItemList
var detail: RichTextLabel
var starmap_view: BoardStarmapView
var cam: BoardCamera
var unit_nodes: Dictionary = {}
var rebuild_timer = 0.0
var match_over = false
var match_msg = ""
var turret_vfx
var float_text
var left_scroll: ScrollContainer
var left_rows: VBoxContainer
var left_col: VBoxContainer
var all_prod_btn: Button
var sync_move_btn: Button
var sync_move_enabled: bool = false
var _sync_gid_next: int = 1
var _tonnage_tex: Dictionary = {}
var _portrait_tex: Dictionary = {}
var _curtain_root: Node3D
var _curtain_acc: float = 0.0


# region agent log
func _agent_dbg(hid: String, loc: String, msg: String, data_payload: Dictionary = {}) -> void:
	# Skip hot-path ids (order/move/capture tick) — sync FileAccess causes hitch
	if hid in ["H1", "H3", "C1", "H4"]:
		return
	var path := "h:/debug-455fdd.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var payload := {
		"sessionId": "455fdd",
		"hypothesisId": hid,
		"location": loc,
		"message": msg,
		"data": data_payload,
		"timestamp": Time.get_ticks_msec()
	}
	f.store_line(JSON.stringify(payload))
	f.close()
# endregion

func _ready() -> void:
	rng.randomize()
	admin = BoardAdminProxy.new()
	add_child(admin)
	data = DATA.new()
	data.load_all()
	map = MAP_MODEL.new()
	map.load_layout("res://data/board/layout.json")
	capture = CAPTURE.new()
	capture.admin = admin
	pilots_sys = PILOTS.new()
	pilots_sys.admin = admin
	pilots_sys.data = data
	ai = AI.new()
	viewer_faction = int(data.diplomacy.get("viewer_faction", 1))
	_spawn_opening()
	ai.setup_fleets(units)
	_setup_ai_autobuild()
	_build_scene_nodes()
	_refresh_occupancy()
	starmap_view.setup(map, data.diplomacy, viewer_faction)
	starmap_view.set_units(units)
	starmap_view.rebuild_labels(pilots)
	_reanchor_idle_units()
	_rebuild_hud_list()
	turret_vfx = VFX_SCR.new()
	turret_vfx.name = "TurretVfx"
	add_child(turret_vfx)
	float_text = FLOAT_SCR.new()
	float_text.name = "FloatText"
	add_child(float_text)

func _setup_ai_autobuild() -> void:
	for p in pilots:
		if int(p["faction"]) != 2:
			continue
		var def: Dictionary = data.ship_def(p["default_ship"])
		var ton: String = def.get("tonnage", "destroyer")
		pilots_sys.set_auto(p, ton, p["default_ship"])

func _spawn_opening() -> void:
	var used: Dictionary = {}  # "sys:cell" -> true
	for raw in map.layout.get("pilots", []):
		var p = pilots_sys.make_pilot(raw)
		pilots.append(p)
		var kind_s: String = raw.get("cell_kind", "resource")
		var kind = BoardTypes.CellKind.RESOURCE
		match kind_s:
			"gate":
				kind = BoardTypes.CellKind.GATE
			"station":
				kind = BoardTypes.CellKind.STATION
			"sov":
				kind = BoardTypes.CellKind.SOV
			"resource":
				kind = BoardTypes.CellKind.RESOURCE
			"empty":
				kind = BoardTypes.CellKind.EMPTY
		var cell = _pick_opening_cell(p["home"], kind, str(raw.get("gate_to", "")), used)
		if cell < 0:
			push_warning("opening cell missing for %s" % p["id"])
			cell = 0
		used["%s:%d" % [p["home"], cell]] = true
		var inst = pilots_sys.make_ship_instance(p["default_ship"])
		pilots_sys.apply_fit_resist(inst, p["default_ship"])
		var home_sys: String = str(p["home"])
		if not map.systems.has(home_sys):
			push_error("pilot %s home missing: %s" % [p["id"], home_sys])
			continue
		var u = _spawn_unit(p, inst, home_sys, cell)
		# hard lock: opening unit must stay in home system
		u["sys"] = home_sys
		u["cell"] = cell
		u["pos"] = map.cell_world_pos(home_sys, cell, BoardTypes.UNIT_Y)
		u["rest_pos"] = u["pos"]
		p["unit_id"] = u["id"]
		print("spawn %s fac=%s sys=%s cell=%d kind=%s" % [p["id"], p["faction"], home_sys, cell, kind_s])
		# #region agent log
		_agent_dbg("H6", "board_root._spawn_opening", "spawn", {
			"id": p["id"], "fac": int(p["faction"]), "home": home_sys, "cell": cell, "kind": kind_s, "runId": "post-fix"
		})
		# #endregion
		p["in_station"] = false
		p["current_station"] = home_sys
		p["home_station"] = home_sys
	_reanchor_idle_units()

func _pick_opening_cell(sys_id: String, kind: int, gate_to: String, used: Dictionary) -> int:
	if not map.systems.has(sys_id):
		return -1
	var cells: Array = map.systems[sys_id]["cells"]
	# prefer exact unused match
	for c in cells:
		if int(c["kind"]) != kind:
			continue
		if kind == BoardTypes.CellKind.GATE and gate_to != "" and str(c.get("gate_to", "")) != gate_to:
			continue
		var key = "%s:%d" % [sys_id, int(c["index"])]
		if used.has(key):
			continue
		return int(c["index"])
	# Kind exhausted: spread to any unused cell in-system (9 pilots / limited cells).
	for c in cells:
		var key2 = "%s:%d" % [sys_id, int(c["index"])]
		if used.has(key2):
			continue
		return int(c["index"])
	# Last resort: share preferred kind (or any cell).
	for c in cells:
		if int(c["kind"]) == kind:
			return int(c["index"])
	if not cells.is_empty():
		return int(cells[0]["index"])
	return -1

func _spawn_unit(pilot: Dictionary, inst: Dictionary, sys: String, cell: int) -> Dictionary:
	var def: Dictionary = data.ship_def(inst["ship_id"])
	var uid = "u%d" % next_unit_i
	next_unit_i += 1
	var u = {
		"id": uid,
		"pilot_id": pilot["id"],
		"faction": int(pilot["faction"]),
		"ship_id": inst["ship_id"],
		"name": def.get("name", inst["ship_id"]),
		"tonnage": def.get("tonnage", "destroyer"),
		"sys": sys,
		"cell": cell,
		"alive": true,
		"phase": BoardTypes.MovePhase.IDLE,
		"phase_t": 0.0,
		"path": [],
		"from_cell": cell,
		"to_cell": cell,
		"to_sys": sys,
		"work_rate": float(def.get("work_rate", 25)),
		"move_s": float(def.get("move_s", 2)),
		"landing_s": float(def.get("landing_s", 3)),
		"jump_s": float(def.get("jump_s", 3)),
		"inertia": float(def.get("inertia", 1)),
		"mass": float(def.get("mass", 1e6)),
		"speed": float(def.get("speed", 200)),
		"signature_radius": float(def.get("signature_radius", 65)),
		"inst": inst,
		"bubble_on": false,
		"bubble_t": 0.0,
		"pd": _build_pd(def),
		"bubble_immune": _has_bubble_immune(def),
		"float_t": rng.randf() * 10.0,
		"float_freq": rng.randf_range(-0.1, 0.1),
		"rest_pos": Vector3.ZERO,
		"pos": map.cell_world_pos(sys, cell, BoardTypes.UNIT_Y),
		"alpha": 1.0,
		"fleet_id": -1,
		"home": pilot["home"],
		"current_station": pilot.get("current_station", pilot["home"]),
		"dealt_timer": 0.0,
		"took_damage": false,
	}
	_init_unit_combat(u)
	units.append(u)
	return u

func _has_bubble_immune(def: Dictionary) -> bool:
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind")) == "bubble_immune":
			return true
	return false

func _build_pd(def: Dictionary) -> Array:
	var guns: Array = []
	var range_mul = 1.0
	var pd_damage_mul = 1.0
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind")) == "range_mul":
			range_mul = float(h.get("value", 1.0))
		elif str(h.get("kind")) == "pd_damage_mul":
			pd_damage_mul = float(h.get("value", 1.0))
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind")) != "pd":
			continue
		var ref: String = h.get("ref", "")
		var count: int = int(h.get("count", 1))
		var eq: Dictionary = data.equipment.get(ref, {})
		for _i in count:
			var rc = int(ceil(float(h.get("range_cells", eq.get("range_cells", 0))) * range_mul))
			guns.append({
				"ref": ref,
				"cycle": float(eq.get("cycle_s", 1.4)),
				"cd": rng.randf() * 0.5,
				"damage": float(eq.get("damage", 100)) * pd_damage_mul,
				"cap": float(eq.get("cap_cost", 1)),
				"fx": str(eq.get("fx", "rail")),
				"tracking": float(eq.get("tracking", 100)),
				"sig_res": float(eq.get("signature_resolution", 40)),
				"falloff": float(eq.get("falloff_m", 4000)),
				"range_cells": rc,
				"target": "",
			})
	return guns

func _fit_has_slot(def: Dictionary, slot_id: String) -> bool:
	for s in def.get("fit", {}).get("slots", []):
		if str(s) == slot_id:
			return true
	return false

func _build_weapons(def: Dictionary) -> Array:
	var out: Array = []
	var range_mul = 1.0
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind")) == "range_mul":
			range_mul = float(h.get("value", 1.0))
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind")) != "weapon":
			continue
		var ref: String = str(h.get("ref", ""))
		var eq: Dictionary = data.equipment.get(ref, {})
		if eq.is_empty():
			continue
		var rc = int(ceil(float(h.get("range_cells", eq.get("range_cells", 0))) * range_mul))
		var wkind = str(eq.get("kind", "weapon"))
		out.append({
			"ref": ref,
			"kind": wkind,
			"cycle": float(eq.get("cycle_s", 4.0)),
			"cd": rng.randf() * 0.5,
			"cap": float(eq.get("cap_cost", 0)),
			"fx": str(eq.get("fx", "laser")),
			"tracking": float(eq.get("tracking", 1)),
			"sig_res": float(eq.get("signature_resolution", 40)),
			"falloff": float(eq.get("falloff_m", 4000)),
			"optimal": float(eq.get("optimal_m", 0)),
			"range_cells": rc,
			"lock_t": 0.0,
			"lock_id": "",
			"lock_need": 1.0,
			"heal_armor": float(eq.get("heal_armor", 0)),
		})
	return out

func _init_unit_combat(u: Dictionary) -> void:
	var def: Dictionary = data.ship_def(u["ship_id"])
	u["hit_flash_t"] = 0.0
	u["hit_shake_t"] = 0.0
	u["hit_shake_phase"] = 0.0
	u["shield_regen_on"] = true ## all fielded ships; hidden entry also sets true
	u["cap_regen_on"] = true
	u["shield_regen_cd"] = rng.randf() * 30.0
	u["recharge_s"] = float(def.get("recharge_s", 400))
	u["scan_res"] = float(def.get("scan_res", 200))
	for h in def.get("fit", {}).get("hidden", []):
		match str(h.get("kind")):
			"shield_regen":
				u["shield_regen_on"] = true
			"cap_regen":
				u["cap_regen_on"] = true
	u["weapons"] = _build_weapons(def)
	u["self_rep"] = []
	for slot_ref in def.get("fit", {}).get("slots", []):
		if slot_ref == null:
			continue
		var eq: Dictionary = data.equipment.get(str(slot_ref), {})
		if eq.is_empty():
			continue
		if eq.has("heal_shield") or eq.has("heal_armor"):
			u["self_rep"].append({
				"ref": str(slot_ref),
				"cycle": float(eq.get("cycle_s", 3)),
				"cd": rng.randf() * 0.5,
				"cap": float(eq.get("cap_cost", 1)),
				"heal_shield": float(eq.get("heal_shield", 0)),
				"heal_armor": float(eq.get("heal_armor", 0)),
			})
	var field_fit = _fit_has_slot(def, "shield_field")
	var link_fit = _fit_has_slot(def, "armor_link")
	u["guard"] = {
		"field_fitted": field_fit,
		"link_fitted": link_fit,
		"field_on": false,
		"link_on": false,
		"field_auto_on": field_fit,
		"link_auto_on": link_fit,
	}
	## Spawn preference 自动开 → effect on if bar ≥20%.
	if field_fit:
		u["guard"]["field_on"] = float(u["inst"]["shield"]) >= float(u["inst"]["max_s"]) * 0.2
	if link_fit:
		u["guard"]["link_on"] = float(u["inst"]["armor"]) >= float(u["inst"]["max_a"]) * 0.2
	u["implant"] = {"ref": "", "auto_on": false, "stacks": 0, "shots": 0, "shield_heal_cd": 0.0}
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind")) == "implant":
			u["implant"]["ref"] = str(h.get("ref", ""))
			u["implant"]["auto_on"] = true
			break

func _guard_force_off(u: Dictionary) -> void:
	if not u.has("guard"):
		return
	u["guard"]["field_on"] = false
	u["guard"]["link_on"] = false

func _tick_guard_reopen(u: Dictionary) -> void:
	if not u.get("alive", false) or not u.has("guard"):
		return
	var ph: int = int(u.get("phase", 0))
	## Effect cannot be on during cross-cell INVULN or LANDING stun.
	if ph == BoardTypes.MovePhase.INVULN or ph == BoardTypes.MovePhase.LANDING:
		_guard_force_off(u)
		return
	var g: Dictionary = u["guard"]
	var inst: Dictionary = u["inst"]
	if g.get("field_fitted", false):
		if g.get("field_auto_on", false) and float(inst["shield"]) >= float(inst["max_s"]) * 0.2:
			g["field_on"] = true
		elif not g.get("field_auto_on", false):
			g["field_on"] = false
	if g.get("link_fitted", false):
		if g.get("link_auto_on", false) and float(inst["armor"]) >= float(inst["max_a"]) * 0.2:
			g["link_on"] = true
		elif not g.get("link_auto_on", false):
			g["link_on"] = false

func _weapon_in_range(a: Dictionary, b: Dictionary, w: Dictionary) -> bool:
	if a["sys"] != b["sys"]:
		return false
	var n: int = map.systems[a["sys"]]["cells"].size()
	var steps = BoardTypes.shorter_arc_steps(int(a["cell"]), int(b["cell"]), n)
	return steps <= int(w["range_cells"])

func _pd_tracking_distance_m(a: Dictionary, b: Dictionary) -> float:
	if a["sys"] != b["sys"]:
		return 999999.0
	var n: int = map.systems[a["sys"]]["cells"].size()
	var steps = BoardTypes.shorter_arc_steps(int(a["cell"]), int(b["cell"]), n)
	return float(steps + 1) * BoardTypes.METERS_PER_CELL

func _weapon_raw(eq: Dictionary, w: Dictionary) -> float:
	var raw = 0.0
	raw += float(eq.get("damage_emp", 0))
	raw += float(eq.get("damage_thermal", 0))
	raw += float(eq.get("damage_kinetic", 0))
	raw += float(eq.get("damage_explosive", 0))
	if raw <= 0.0:
		raw = float(w.get("heal_armor", 0))
	return raw

func _implant_data(u: Dictionary) -> Dictionary:
	var ref: String = str(u.get("implant", {}).get("ref", ""))
	if ref == "":
		return {}
	return data.equipment.get(ref, {})

func _apply_sniper_mod(u: Dictionary, tracking: float, raw: float) -> Dictionary:
	var imp: Dictionary = _implant_data(u)
	if imp.is_empty() or str(imp.get("id", "")) != "implant_sniper":
		return {"tracking": tracking, "raw": raw}
	if not u.get("implant", {}).get("auto_on", true):
		return {"tracking": tracking, "raw": raw}
	u["implant"]["shots"] = int(u["implant"].get("shots", 0)) + 1
	var every: int = int(imp.get("every", 10))
	if int(u["implant"]["shots"]) % every == 0:
		return {
			"tracking": float(imp.get("tracking_override", 9999)),
			"raw": raw * float(imp.get("mul", 10)),
		}
	return {"tracking": tracking, "raw": 0.0}

func _focus_on_hit(u: Dictionary, hit: bool, raw: float) -> float:
	var imp: Dictionary = _implant_data(u)
	if imp.is_empty() or str(imp.get("id", "")) != "implant_focus_crystal":
		return raw
	if not u.get("implant", {}).get("auto_on", true):
		return raw
	if hit:
		var pct: float = float(imp.get("stack_pct", 1)) / 100.0
		u["implant"]["stacks"] = mini(20, int(u["implant"].get("stacks", 0)) + 1)
		return raw * (1.0 + pct * float(u["implant"]["stacks"]))
	_focus_spend_stacks(u)
	return raw

func _focus_spend_stacks(u: Dictionary) -> void:
	## Clear stacks; if CD ready, heal stacks×1%×max_s then start 20s CD.
	var imp: Dictionary = _implant_data(u)
	if imp.is_empty() or str(imp.get("id", "")) != "implant_focus_crystal":
		return
	if not u.get("implant", {}).get("auto_on", true):
		u["implant"]["stacks"] = 0
		return
	var stacks: int = int(u["implant"].get("stacks", 0))
	u["implant"]["stacks"] = 0
	if stacks <= 0:
		return
	var cd: float = float(u["implant"].get("shield_heal_cd", 0.0))
	if cd > 0.0:
		return
	var inst: Dictionary = u["inst"]
	var heal: float = float(stacks) * (float(imp.get("stack_pct", 1)) / 100.0) * float(inst["max_s"])
	inst["shield"] = minf(float(inst["max_s"]), float(inst["shield"]) + heal)
	u["implant"]["shield_heal_cd"] = float(imp.get("shield_cd", 20))
	if float_text and heal > 0.05:
		float_text.add_heal(u["pos"], heal, hash(str(u["id"]) + "fc"))

func _tick_implant_passive(u: Dictionary, delta: float) -> void:
	var cd: float = float(u.get("implant", {}).get("shield_heal_cd", 0.0))
	if cd > 0.0:
		u["implant"]["shield_heal_cd"] = maxf(0.0, cd - delta)

func _guard_bearers(u: Dictionary, want_field: bool) -> Array:
	var out: Array = []
	for o in units:
		if not o.get("alive", false):
			continue
		if int(o["faction"]) != int(u["faction"]):
			continue
		if o["sys"] != u["sys"] or int(o["cell"]) != int(u["cell"]):
			continue
		var g: Dictionary = o.get("guard", {})
		if want_field and g.get("field_on", false):
			out.append(o)
		elif not want_field and g.get("link_on", false):
			out.append(o)
	return out

func _apply_shield_only_redirect(bearer: Dictionary, raw: float) -> float:
	## Absorb on bearer shield with no max-loss; return overflow raw (pre-resist of bearer).
	if not bearer.get("alive", false) or raw <= 0.0:
		return raw
	var inst: Dictionary = bearer["inst"]
	var resist: int = int(inst.get("resist", 0))
	var taken = raw * (1.0 - clampf(float(resist), 0.0, 100.0) / 100.0)
	var absorb = minf(float(inst["shield"]), taken)
	inst["shield"] = float(inst["shield"]) - absorb
	bearer["hit_flash_t"] = 0.05
	bearer["hit_shake_t"] = 0.2
	if float(inst["shield"]) <= 0.01 and bearer.has("guard"):
		bearer["guard"]["field_on"] = false
	if float_text and absorb > 0.05:
		float_text.add_damage(bearer["pos"], absorb, hash(str(bearer["id"])))
	if taken <= 0.0001:
		return 0.0
	var overflow_taken = taken - absorb
	## Convert overflow back to raw-equivalent for original target.
	var factor = 1.0 - clampf(float(resist), 0.0, 100.0) / 100.0
	if factor <= 0.0001:
		return 0.0
	return overflow_taken / factor

func _apply_armor_only_redirect(bearer: Dictionary, armor_raw: float) -> float:
	if not bearer.get("alive", false) or armor_raw <= 0.0:
		return armor_raw
	var inst: Dictionary = bearer["inst"]
	var resist: int = int(inst.get("resist", 0))
	var taken = armor_raw * (1.0 - clampf(float(resist), 0.0, 100.0) / 100.0)
	var absorb = minf(float(inst["armor"]), taken)
	inst["armor"] = float(inst["armor"]) - absorb
	bearer["hit_flash_t"] = 0.05
	bearer["hit_shake_t"] = 0.2
	if float(inst["armor"]) <= 0.01 and bearer.has("guard"):
		bearer["guard"]["link_on"] = false
	if float_text and absorb > 0.05:
		float_text.add_damage(bearer["pos"], absorb, hash(str(bearer["id"])))
	if taken <= 0.0001:
		return 0.0
	var overflow_taken = taken - absorb
	var factor = 1.0 - clampf(float(resist), 0.0, 100.0) / 100.0
	if factor <= 0.0001:
		return 0.0
	return overflow_taken / factor

func _apply_damage_to_unit(
	attacker: Dictionary,
	target: Dictionary,
	raw: float,
	resist: int,
	skip_redirect: bool = false,
	skip_max_loss: bool = false
) -> void:
	if not target.get("alive", false) or raw <= 0.0:
		return
	var portion = raw
	if not skip_redirect and attacker and not attacker.is_empty():
		var same_cell = str(attacker.get("sys", "")) == str(target.get("sys", "")) \
			and int(attacker.get("cell", -1)) == int(target.get("cell", -2))
		## Field: cross-cell inbound only — random field bearer absorbs on shield.
		if not same_cell:
			var fielders = _guard_bearers(target, true)
			if not fielders.is_empty():
				var bearer: Dictionary = fielders[rng.randi_range(0, fielders.size() - 1)]
				if str(bearer["id"]) != str(target["id"]):
					portion = _apply_shield_only_redirect(bearer, portion)
					if portion <= 0.0:
						return
		## Link: same-cell hostile hit — armor segment redirected to random linker.
		elif same_cell and int(attacker.get("faction", -1)) != int(target.get("faction", -2)):
			var linkers = _guard_bearers(target, false)
			if not linkers.is_empty() and portion > 0.0:
				var inst0: Dictionary = target["inst"]
				var factor0 = 1.0 - clampf(float(resist), 0.0, 100.0) / 100.0
				var taken0 = portion * factor0
				var shield_abs = minf(float(inst0["shield"]), taken0)
				var after_shield = taken0 - shield_abs
				var armor_cap_take = minf(float(inst0["armor"]), after_shield)
				if armor_cap_take > 0.0:
					var bearer2: Dictionary = linkers[rng.randi_range(0, linkers.size() - 1)]
					if str(bearer2["id"]) != str(target["id"]):
						var armor_raw = armor_cap_take / maxf(factor0, 0.0001)
						var overflow_armor = _apply_armor_only_redirect(bearer2, armor_raw)
						var struct_rem = maxf(0.0, after_shield - armor_cap_take)
						## Target keeps shield hit + overflow armor + structure remainder as raw.
						portion = (shield_abs + struct_rem) / maxf(factor0, 0.0001) + overflow_armor
	if portion <= 0.0:
		return
	var inst: Dictionary = target["inst"]
	var shield_before := float(inst["shield"])
	var before_hp := shield_before + float(inst["armor"]) + float(inst["structure"])
	var res = BoardCombatFormulas.apply_layer_damage(
		inst["shield"], inst["armor"], inst["structure"],
		inst["max_s"], inst["max_a"], inst["max_h"],
		portion, resist, skip_max_loss
	)
	inst["shield"] = res["shield"]
	inst["armor"] = res["armor"]
	inst["structure"] = res["structure"]
	inst["max_s"] = res["max_s"]
	inst["max_a"] = res["max_a"]
	inst["max_h"] = res["max_h"]
	var after_hp := float(inst["shield"]) + float(inst["armor"]) + float(inst["structure"])
	var dealt_hp := before_hp - after_hp
	target["hit_flash_t"] = 0.05
	target["hit_shake_t"] = 0.2
	if shield_before > 0.01 and float(inst["shield"]) <= 0.01:
		_focus_spend_stacks(target)
	if float(inst["shield"]) <= 0.01 and target.has("guard"):
		target["guard"]["field_on"] = false
	if float(inst["armor"]) <= 0.01 and target.has("guard"):
		target["guard"]["link_on"] = false
	if float_text and dealt_hp > 0.05:
		float_text.add_damage(target["pos"], dealt_hp, hash(str(target["id"])))
	if attacker and not attacker.is_empty():
		attacker["dealt_timer"] = 1.2
	target["took_damage"] = dealt_hp > 0.05
	target["dealt_timer"] = 1.2
	if res["killed"]:
		_kill_unit(target)
	elif attacker and not attacker.is_empty():
		admin.request("combat.damage", {"from": attacker["id"], "to": target["id"], "raw": portion})

func _tick_self_repair(u: Dictionary, delta: float) -> void:
	for r in u.get("self_rep", []):
		r["cd"] = float(r["cd"]) - delta
		if float(r["cd"]) > 0.0:
			continue
		var inst: Dictionary = u["inst"]
		if float(r.get("heal_shield", 0)) > 0.0:
			if float(inst["shield"]) >= float(inst["max_s"]):
				continue
			if float(inst["cap"]) < float(r["cap"]):
				continue
			inst["cap"] -= float(r["cap"])
			var hs = minf(float(r["heal_shield"]), float(inst["max_s"]) - float(inst["shield"]))
			inst["shield"] = float(inst["shield"]) + hs
			r["cd"] = float(r["cycle"])
			if float_text and hs > 0.05:
				float_text.add_heal(u["pos"], hs, hash(str(u["id"]) + "sr"))
		elif float(r.get("heal_armor", 0)) > 0.0:
			if float(inst["armor"]) >= float(inst["max_a"]):
				continue
			if float(inst["cap"]) < float(r["cap"]):
				continue
			inst["cap"] -= float(r["cap"])
			var ha = minf(float(r["heal_armor"]), float(inst["max_a"]) - float(inst["armor"]))
			inst["armor"] = float(inst["armor"]) + ha
			r["cd"] = float(r["cycle"])
			if float_text and ha > 0.05:
				float_text.add_heal(u["pos"], ha, hash(str(u["id"]) + "ar"))

func _tick_shield_regen(u: Dictionary, delta: float) -> void:
	## Hidden: every 30s restore 10% of current shield cap; no capacitor.
	if not u.get("shield_regen_on", false):
		return
	var inst: Dictionary = u["inst"]
	if float(inst["shield"]) >= float(inst["max_s"]):
		u["shield_regen_cd"] = float(u.get("shield_regen_cd", 30.0))
		return
	u["shield_regen_cd"] = float(u.get("shield_regen_cd", 30.0)) - delta
	if float(u["shield_regen_cd"]) > 0.0:
		return
	var heal = float(inst["max_s"]) * 0.1
	heal = minf(heal, float(inst["max_s"]) - float(inst["shield"]))
	inst["shield"] = float(inst["shield"]) + heal
	u["shield_regen_cd"] = 30.0
	if float_text and heal > 0.05:
		float_text.add_heal(u["pos"], heal, hash(str(u["id"]) + "sregen"))

func _tick_cap_regen(u: Dictionary, delta: float) -> void:
	if not u.get("cap_regen_on", false):
		return
	var inst: Dictionary = u["inst"]
	if float(inst["cap"]) >= float(inst["max_cap"]):
		return
	var rate = float(inst["max_cap"]) / maxf(float(u.get("recharge_s", 400)), 1.0)
	inst["cap"] = minf(float(inst["max_cap"]), float(inst["cap"]) + rate * delta)

func _tick_regen_and_repair(delta: float) -> void:
	for u in units:
		if not u.get("alive", false):
			continue
		_tick_self_repair(u, delta)
		_tick_shield_regen(u, delta)
		_tick_cap_regen(u, delta)
		_tick_implant_passive(u, delta)
		_tick_guard_reopen(u)

func _tick_weapon_locks(delta: float) -> void:
	for u in units:
		if not u.get("alive", false):
			continue
		for w in u.get("weapons", []):
			w["retarget_t"] = float(w.get("retarget_t", 0.0)) - delta
			var cur_id: String = str(w.get("lock_id", ""))
			var tgt = _unit_by_id(cur_id)
			var need_retarget = tgt.is_empty() or not tgt.get("alive", false) or float(w.get("retarget_t", 0.0)) <= 0.0
			if need_retarget:
				var cand = _pick_weapon_target(u, w)
				var new_id: String = str(cand.get("id", ""))
				if new_id != cur_id:
					## Lead-lock: if new candidate is in range, keep some progress; else reset.
					if not cand.is_empty() and _weapon_in_range(u, cand, w) and float(w.get("lock_t", 0.0)) > 0.0:
						w["lock_id"] = new_id
						## keep lock_t as lead progress
					else:
						w["lock_id"] = new_id
						w["lock_t"] = 0.0
					tgt = cand
				elif tgt.is_empty():
					tgt = cand
				w["retarget_t"] = 10.0 if not tgt.is_empty() else 0.5
			if tgt.is_empty():
				continue
			w["lock_need"] = 40000.0 / maxf(float(u["scan_res"]) * float(tgt["signature_radius"]), 1.0)
			## Lock timer advances only while same-sys and in weapon range (LANDING OK).
			if u["sys"] == tgt["sys"] and _weapon_in_range(u, tgt, w):
				w["lock_t"] = minf(float(w.get("lock_need", 1.0)), float(w.get("lock_t", 0.0)) + delta)
			## else: keep existing lock_t (do not reset)

func _unit_has_guard_fit(o: Dictionary) -> bool:
	var g: Dictionary = o.get("guard", {})
	return g.get("field_fitted", false) or g.get("link_fitted", false)

func _pick_weapon_target(u: Dictionary, w: Dictionary) -> Dictionary:
	var best = {}
	var best_key = INF
	var best_guard = false
	var is_rep = str(w.get("kind", "")) == "remote_armor"
	for o in units:
		if not o.get("alive", false):
			continue
		if is_rep:
			if int(o["faction"]) != int(u["faction"]) or o["id"] == u["id"]:
				continue
		else:
			if int(o["faction"]) == int(u["faction"]):
				continue
		if u["sys"] != o["sys"]:
			continue
		## Prefer in-range; allow out-of-range acquire but lock won't advance.
		var in_rng = _weapon_in_range(u, o, w)
		var key = INF
		var guard_pri = false
		if is_rep:
			guard_pri = _unit_has_guard_fit(o)
			var ti: Dictionary = o["inst"]
			key = float(ti["armor"]) / maxf(float(ti["max_a"]), 1.0)
			if not in_rng:
				key += 1000.0
		else:
			var n: int = map.systems[u["sys"]]["cells"].size()
			key = float(BoardTypes.shorter_arc_steps(int(u["cell"]), int(o["cell"]), n))
			if not in_rng:
				key += 1000.0
		if best.is_empty():
			best = o
			best_key = key
			best_guard = guard_pri
			continue
		if is_rep:
			if guard_pri and not best_guard:
				best = o
				best_key = key
				best_guard = true
				continue
			if (not guard_pri) and best_guard:
				continue
		if key < best_key:
			best_key = key
			best = o
			best_guard = guard_pri
	return best

func _fire_weapon(u: Dictionary, w: Dictionary, tgt: Dictionary) -> void:
	var eq: Dictionary = data.equipment.get(str(w.get("ref", "")), {})
	if eq.is_empty():
		return
	if not _weapon_in_range(u, tgt, w):
		return
	var inst: Dictionary = u["inst"]
	if float(inst["cap"]) < float(w.get("cap", 0)):
		return
	inst["cap"] -= float(w.get("cap", 0))
	if str(w.get("kind", "")) == "remote_armor":
		var heal = float(w.get("heal_armor", 0))
		var tinst: Dictionary = tgt["inst"]
		var room = float(tinst["max_a"]) - float(tinst["armor"])
		heal = minf(heal, maxf(0.0, room))
		tinst["armor"] = float(tinst["armor"]) + heal
		var imp: Dictionary = _implant_data(u)
		if imp.get("id", "") == "implant_armor_support" and u.get("implant", {}).get("auto_on", true):
			## +10% armor resist on healed target; does not stack on same target.
			if not tgt.get("armor_support_buff", false):
				tgt["armor_support_buff"] = true
				tinst["resist"] = int(tinst.get("resist", 0)) + int(imp.get("res_pct", 10))
		if turret_vfx:
			turret_vfx.play(str(w.get("fx", "repair")), u["pos"], tgt["pos"])
		if float_text and heal > 0.05:
			float_text.add_heal(tgt["pos"], heal, hash(str(tgt["id"]) + "rr"))
		return
	## Tracking uses (cell steps + 1) meters, same as PD.
	var dist_m = _pd_tracking_distance_m(u, tgt)
	var tracking = float(w.get("tracking", 1))
	var raw = _weapon_raw(eq, w)
	var sn = _apply_sniper_mod(u, tracking, raw)
	tracking = float(sn["tracking"])
	raw = float(sn["raw"])
	var p_hit = BoardCombatFormulas.turret_hit_chance(
		tracking, float(w.get("sig_res", 40)), float(w.get("falloff", 4000)),
		float(w.get("optimal", 0)), float(tgt["speed"]), float(tgt["signature_radius"]), dist_m
	)
	var hit = rng.randf() <= p_hit
	raw = _focus_on_hit(u, hit, raw)
	if not hit or raw <= 0.0:
		return
	raw *= BoardCombatFormulas.roll_quality(rng)
	_apply_damage_to_unit(u, tgt, raw, int(tgt["inst"]["resist"]))
	if turret_vfx:
		turret_vfx.play(str(w.get("fx", "laser")), u["pos"], tgt["pos"])

func _build_scene_nodes() -> void:
	# sky (panorama; race plate still better than broken UV dome)
	var env = WorldEnvironment.new()
	var e = Environment.new()
	# Flat ambient — board mesh is unshaded; keep energy low so nothing picks up shading
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	e.ambient_light_energy = 0.45
	var sky_tex = load("res://assets/skyboxes/board_panorama.jpeg")
	if sky_tex == null:
		sky_tex = load("res://assets/skyboxes/amarr.jpeg")
	if sky_tex == null:
		sky_tex = load("res://assets/skyboxes/races/ch1.jpg")
	if sky_tex:
		e.background_mode = Environment.BG_SKY
		var sky = Sky.new()
		var pan = PanoramaSkyMaterial.new()
		pan.panorama = sky_tex
		pan.energy_multiplier = 1.25
		sky.sky_material = pan
		e.sky = sky
	else:
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.01, 0.02, 0.04)
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = false
	add_child(sun)
	# starmap view
	starmap_view = BoardStarmapView.new()
	starmap_view.name = "StarmapView"
	var mi = MeshInstance3D.new()
	mi.name = "Mesh"
	var mat2 = StandardMaterial3D.new()
	mat2.vertex_color_use_as_albedo = true
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat2.albedo_color = Color(1, 1, 1, 1)
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat2.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = mat2
	starmap_view.add_child(mi)
	add_child(starmap_view)
	# camera
	cam = BoardCamera.new()
	cam.name = "BoardCamera"
	var c3 = Camera3D.new()
	c3.name = "Camera3D"
	c3.current = true
	cam.add_child(c3)
	add_child(cam)
	if starmap_view:
		starmap_view.set_camera(c3)
	var home_sid = ""
	for p in pilots:
		if int(p["faction"]) == viewer_faction:
			home_sid = str(p.get("home", ""))
			break
	if home_sid != "" and map.systems.has(home_sid):
		cam.look_at_point = map.systems[home_sid]["center"]
		cam.distance = 110.0
		cam._apply()
	# units root
	var ur = Node3D.new()
	ur.name = "Units"
	add_child(ur)
	for u in units:
		_ensure_unit_node(u)
	# HUD
	_build_hud()
	popup = PopupMenu.new()
	add_child(popup)
	popup.id_pressed.connect(_on_any_popup)

func _ensure_unit_node(u: Dictionary) -> void:
	var root = get_node("Units")
	var n = Node3D.new()
	n.name = u["id"]
	var target_d = (TAU * 26.0 / 24.0) * 0.55 * 1.5
	var target_r = target_d * 0.5
	# Add to tree first so AABB / physics work
	root.add_child(n)
	n.global_position = u["pos"]
	# click body
	var body = StaticBody3D.new()
	body.name = "PickBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_collision_layer_value(1, true)
	body.set_collision_layer_value(2, false)
	body.set_meta("unit_id", u["id"])
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = target_r
	col.shape = shape
	body.add_child(col)
	n.add_child(body)
	# placeholder proxy
	var mesh = MeshInstance3D.new()
	mesh.name = "Proxy"
	var sphere = SphereMesh.new()
	sphere.radius = target_r * 0.35
	sphere.height = sphere.radius * 2.0
	mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = BoardTypes.relation_color(_rel_for(u["faction"]))
	mesh.material_override = mat
	n.add_child(mesh)
	# glb + albedo (fix white membrane / oversized)
	var def: Dictionary = data.ship_def(u["ship_id"])
	var model_key = str(def.get("model", u["ship_id"]))
	var model_path = "res://assets/models/ships/%s/model.glb" % model_key
	var albedo_path = "res://assets/models/ships/%s/albedo.png" % model_key
	if ResourceLoader.exists(model_path):
		var packed = load(model_path)
		if packed != null and packed is PackedScene:
			var inst = (packed as PackedScene).instantiate()
			inst.name = "Model"
			var yaw_deg := _model_bow_yaw_deg(model_key)
			inst.rotation.y = deg_to_rad(yaw_deg)
			n.add_child(inst)
			_disable_model_collision(inst)
			_fit_model_scale(inst, target_d)
			_apply_ship_albedo(inst, albedo_path)
			# Re-apply next frame in case importer materials overwrite
			call_deferred("_apply_ship_albedo", inst, albedo_path)
			mesh.visible = false
			# #region agent log
			_agent_dbg("B5", "board_root.spawn_model", "bow_yaw", {
				"ship": str(u.get("ship_id", "")), "model": model_key, "yaw_deg": yaw_deg, "runId": "post-fix"
			})
			# #endregion
	# pick sphere fixed ? never inherit broken AABB (BH-04 / BH-08)
	shape.radius = clampf(target_r * 0.85, 1.2, 3.5)
	var ring = MeshInstance3D.new()
	ring.name = "SelectRing"
	ring.mesh = _make_flat_ring_mesh(1.35, 1.65, 32)
	ring.position = Vector3(0, -BoardTypes.UNIT_Y + 0.04, 0)
	ring.visible = false
	var rmat = StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.25, 0.95, 0.4, 0.55)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.no_depth_test = false
	ring.material_override = rmat
	n.add_child(ring)
	var ring_ol = MeshInstance3D.new()
	ring_ol.name = "SelectRingOutline"
	ring_ol.mesh = _make_flat_ring_mesh(1.65, 1.82, 32)
	ring_ol.position = Vector3(0, -BoardTypes.UNIT_Y + 0.035, 0)
	ring_ol.visible = false
	var omat = StandardMaterial3D.new()
	omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	omat.albedo_color = Color(0.05, 0.15, 0.08, 0.75)
	omat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	omat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_ol.material_override = omat
	n.add_child(ring_ol)
	# EveAC-like wake: stamped world points (head at stern, wake free in world)
	var trail = MeshInstance3D.new()
	trail.name = "Trail"
	trail.top_level = true
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tmat = StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.vertex_color_use_as_albedo = true
	tmat.albedo_color = Color(1, 1, 1, 1)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.emission_enabled = true
	tmat.emission = Color(0.35, 0.75, 1.0)
	tmat.emission_energy_multiplier = 1.8
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tmat.no_depth_test = true
	trail.material_override = tmat
	trail.visible = false
	n.add_child(trail)
	# overhead HP / name / tonnage (billboard)
	var oh = OVERHEAD_SCR.new()
	oh.name = "Overhead"
	oh.top_level = true
	n.add_child(oh)
	oh.set_tonnage_icon(_tonnage_icon(str(u.get("tonnage", "destroyer"))))
	unit_nodes[u["id"]] = n


func _mesh_aabb_size(node: Node3D) -> float:
	var aabb = _mesh_aabb_local(node)
	if aabb.size == Vector3.ZERO:
		return 1.0
	return maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))

func _mesh_aabb_local(root: Node3D) -> AABB:
	var aabb = AABB()
	var first = true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi = child as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D
		if root.is_inside_tree() and mi.is_inside_tree():
			xf = root.global_transform.affine_inverse() * mi.global_transform
		else:
			xf = _local_xform_to(root, mi)
		var a = xf * mi.get_aabb()
		if first:
			aabb = a
			first = false
		else:
			aabb = aabb.merge(a)
	return aabb

func _local_xform_to(root: Node, node: Node) -> Transform3D:
	var xf = Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

func _model_bow_yaw_deg(model_key: String) -> float:
	## Align mesh bow with Node3D look_at forward (-Z). Default 180° (bow was +Z).
	var yaw_deg := 180.0
	var boost_path := "res://assets/models/ships/%s/engine_boosters.json" % model_key
	if not FileAccess.file_exists(boost_path):
		return yaw_deg
	var txt := FileAccess.get_file_as_string(boost_path)
	if txt.is_empty():
		return yaw_deg
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return yaw_deg
	var root: Dictionary = parsed
	var bow: Dictionary = root.get("bow_fit", {}) as Dictionary
	if bow.has("model_yaw_deg"):
		yaw_deg = float(bow["model_yaw_deg"])
	elif root.has("model_yaw_deg"):
		yaw_deg = float(root["model_yaw_deg"])
	return yaw_deg

func _fit_model_scale(inst: Node3D, target_diameter: float) -> void:
	inst.scale = Vector3.ONE
	inst.position = Vector3.ZERO
	var aabb = _mesh_aabb_local(inst)
	var span = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if span < 0.001:
		span = 1.0
	var s = target_diameter / span
	inst.scale = Vector3.ONE * s
	# center on unit plane
	var mid = aabb.position + aabb.size * 0.5
	inst.position = Vector3(-mid.x * s, -aabb.position.y * s, -mid.z * s)

func _disable_model_collision(root: Node) -> void:
	for c in root.find_children("*", "CollisionObject3D", true, false):
		(c as CollisionObject3D).collision_layer = 0
		(c as CollisionObject3D).collision_mask = 0
	for cs in root.find_children("*", "CollisionShape3D", true, false):
		(cs as CollisionShape3D).disabled = true

func _set_model_hit_flash(model_root: Node3D, on: bool) -> void:
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_i: MeshInstance3D = mi as MeshInstance3D
		if mesh_i.material_override == null and mesh_i.mesh != null:
			continue
		var mat = mesh_i.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mesh_i.material_override = mat
		if not mesh_i.has_meta("flash_base"):
			mesh_i.set_meta("flash_base", mat.albedo_color)
		var base_c: Color = mesh_i.get_meta("flash_base")
		mat.albedo_color = base_c.lerp(Color(1, 1, 1, 1), 0.75) if on else base_c

func _apply_ship_albedo(inst: Node, albedo_path: String) -> void:
	var tex: Texture2D = null
	var nrm: Texture2D = null
	if ResourceLoader.exists(albedo_path):
		tex = load(albedo_path) as Texture2D
	var nrm_path = albedo_path.replace("albedo.png", "normal.png")
	if ResourceLoader.exists(nrm_path):
		nrm = load(nrm_path) as Texture2D
	var bm = StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	bm.vertex_color_use_as_albedo = false
	bm.metallic = 0.08
	bm.roughness = 0.72
	bm.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bm.texture_repeat = true
	bm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	if tex:
		bm.albedo_texture = tex
		bm.albedo_color = Color(0.92, 0.92, 0.94, 1.0)
		bm.ao_enabled = false
	else:
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(0.82, 0.84, 0.88, 1.0)
	if nrm and tex:
		bm.normal_enabled = true
		bm.normal_texture = nrm
		bm.normal_scale = 0.92
	# #region agent log
	_agent_dbg("H5", "board_root._apply_ship_albedo", "albedo", {
		"path": albedo_path, "has_tex": tex != null, "has_nrm": nrm != null,
		"shade": "per_pixel", "runId": "post-fix"
	})
	# #endregion
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = bm
		var sc = mi.mesh.get_surface_count()
		for si in sc:
			mi.set_surface_override_material(si, bm)

func _rel_for(fac: int) -> String:
	if int(fac) == int(viewer_faction):
		return "self"
	var rels: Dictionary = data.diplomacy.get("relations", {}).get(str(viewer_faction), {})
	return str(rels.get(str(fac), "hostile"))

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	var layer = Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(layer)
	left_col = VBoxContainer.new()
	left_col.name = "LeftCol"
	left_col.position = Vector2(8, 8)
	left_col.mouse_filter = Control.MOUSE_FILTER_STOP
	left_col.add_theme_constant_override("separation", 6)
	_layout_left_col()
	if not get_viewport().size_changed.is_connected(_layout_left_col):
		get_viewport().size_changed.connect(_layout_left_col)
	all_prod_btn = Button.new()
	all_prod_btn.name = "AllToProdBtn"
	all_prod_btn.text = "全体：当前驾驶舰 → 制造产线"
	all_prod_btn.custom_minimum_size = Vector2(0, 32)
	all_prod_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	all_prod_btn.pressed.connect(_on_all_current_ships_to_prod)
	left_col.add_child(all_prod_btn)
	left_scroll = ScrollContainer.new()
	left_scroll.name = "LeftScroll"
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.custom_minimum_size = Vector2(360, 120)
	left_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	left_rows = VBoxContainer.new()
	left_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_rows.add_theme_constant_override("separation", 6)
	left_scroll.add_child(left_rows)
	left_col.add_child(left_scroll)
	sync_move_btn = Button.new()
	sync_move_btn.name = "SyncMoveBtn"
	sync_move_btn.custom_minimum_size = Vector2(0, 32)
	sync_move_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_sync_move_btn()
	sync_move_btn.pressed.connect(_on_sync_move_pressed)
	left_col.add_child(sync_move_btn)
	layer.add_child(left_col)
	_layout_left_col()
	# keep ItemList stub for any legacy refs
	left_list = ItemList.new()
	left_list.visible = false
	layer.add_child(left_list)
	detail = RichTextLabel.new()
	detail.position = Vector2(1600, 8)
	detail.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	detail.offset_left = -320
	detail.offset_right = -8
	detail.offset_top = 8
	detail.offset_bottom = 648
	detail.size = Vector2(300, 640)
	detail.bbcode_enabled = true
	detail.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(detail)
	var hint = Label.new()
	hint.position = Vector2(320, 8)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.text = "中键旋转 | 滚轮缩放 | 左键框选/移动 | 右键菜单"
	layer.add_child(hint)

func _refresh_hud_progress_only() -> void:
	if left_rows == null:
		return
	# Avoid full queue_free flicker: update progress bars in place when possible
	var need_full = left_rows.get_child_count() == 0
	if need_full:
		_rebuild_hud_list()
		return
	var need_rebuild_bars = false
	for row in left_rows.get_children():
		var pid = str(row.get_meta("pilot", ""))
		var p = _pilot_by_id(pid)
		if p.is_empty():
			continue
		var active_tons := 0
		for ton_key in PILOTS.TONNAGES:
			var bjob = p.get("building", {}).get(ton_key)
			if bjob != null and typeof(bjob) == TYPE_DICTIONARY:
				active_tons += 1
		var bars = row.find_children("*", "ProgressBar", true, false)
		if bars.size() != active_tons:
			## Bar count drifted (new/finished jobs) — full rebuild next.
			need_rebuild_bars = true
		else:
			var bi = 0
			for ton_key2 in PILOTS.TONNAGES:
				var bj = p.get("building", {}).get(ton_key2)
				if bj == null or typeof(bj) != TYPE_DICTIONARY:
					continue
				if bi >= bars.size():
					break
				var bar = bars[bi] as ProgressBar
				var dur = float(bj.get("build_s", bj.get("duration", 1)))
				var elapsed = float(bj.get("t", 0))
				bar.value = clampf(elapsed / maxf(dur, 0.001), 0.0, 1.0) if dur > 0.001 else 0.0
				var head = bar.get_parent().get_child(1) if bar.get_parent() and bar.get_parent().get_child_count() > 1 else null
				if head is TextureRect:
					var w = maxf(bar.size.x, 200.0)
					(head as TextureRect).position = Vector2(maxf(0.0, bar.value * w - 7.0), -2)
				bi += 1
		# Switch sky + ship art when pilot's active ship changes
		var sid = str(p.get("default_ship", ""))
		var u = _unit_by_id(str(p.get("unit_id", "")))
		if u and u.get("alive", false):
			sid = str(u.get("ship_id", sid))
		elif str(p.get("unit_id", "")) != "" and (u.is_empty() or not u.get("alive", false)):
			# Ship destroyed — hide ship art until relaunch
			sid = ""
		_refresh_pilot_row_ship_art(row, sid)
	if need_rebuild_bars:
		_rebuild_hud_list()

func _rebuild_hud_list() -> void:
	if left_rows == null:
		return
	for c in left_rows.get_children():
		c.queue_free()
	for p in pilots:
		if int(p["faction"]) != viewer_faction:
			continue
		left_rows.add_child(_make_pilot_row(p))

func _make_pilot_row(p: Dictionary) -> Control:
	var row = PanelContainer.new()
	row.custom_minimum_size = Vector2(340, 72)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.clip_contents = true
	var pid = str(p["id"])
	var row_style = StyleBoxFlat.new()
	row_style.bg_color = Color(0.06, 0.08, 0.12, 0.35)
	row_style.set_border_width_all(0)
	row.add_theme_stylebox_override("panel", row_style)
	var row_sky = TextureRect.new()
	row_sky.name = "RowSky"
	row_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	row_sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	row_sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	row_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_sky.modulate = Color(1, 1, 1, 0.55)
	# PanelContainer hosts one child — wrap sky + content
	var row_wrap = Control.new()
	row_wrap.name = "RowWrap"
	row_wrap.custom_minimum_size = Vector2(340, 72)
	row_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(row_wrap)
	row_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row_wrap.add_child(row_sky)
	row.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			var mb = ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var row_u = _unit_by_id(str(p.get("unit_id", "")))
				if row_u:
					selection = [row_u["id"]]
					_update_detail()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_open_pilot_menu(p, get_viewport().get_mouse_position())
	)
	var wrap_n = row.get_node_or_null("RowWrap") as Control
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.clip_contents = false
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 6
	hb.offset_right = -6
	hb.offset_top = 4
	hb.offset_bottom = -4
	if wrap_n:
		wrap_n.add_child(hb)
	else:
		row.add_child(hb)
	var ton = "destroyer"
	var u = _unit_by_id(str(p.get("unit_id", "")))
	var ship_name = ""
	var ship_id = str(p.get("default_ship", ""))
	if u:
		ton = str(u.get("tonnage", ton))
		ship_name = str(u.get("name", ""))
		ship_id = str(u.get("ship_id", ship_id))
	else:
		var def: Dictionary = data.ship_def(ship_id)
		ton = str(def.get("tonnage", ton))
	var rsky = row.find_child("RowSky", true, false) as TextureRect
	if rsky:
		rsky.texture = _ship_sky_tex(ship_id)
	var ton_rect = TextureRect.new()
	ton_rect.custom_minimum_size = Vector2(32, 32)
	ton_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ton_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ton_rect.texture = _tonnage_icon(ton)
	ton_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ton_rect)
	# portrait frame: sky bg + pilot top + ship art (1.5x, overflow bottom 1/10)
	var frame = Control.new()
	frame.custom_minimum_size = Vector2(52, 52)
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sky_bg = TextureRect.new()
	sky_bg.name = "SkyBg"
	sky_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_bg.texture = null
	sky_bg.modulate = Color(1, 1, 1, 0.0)
	frame.add_child(sky_bg)
	var frame_bg = Panel.new()
	frame_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.15)
	sb.border_color = Color(0.55, 0.6, 0.7, 0.9)
	sb.set_border_width_all(2)
	frame_bg.add_theme_stylebox_override("panel", sb)
	frame.add_child(frame_bg)
	var pilot_slot = ColorRect.new()
	pilot_slot.position = Vector2(2, 2)
	pilot_slot.size = Vector2(48, 18)
	pilot_slot.color = Color(0.1, 0.12, 0.16, 0.55)
	pilot_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pilot_slot)
	var pilot_face = TextureRect.new()
	pilot_face.position = Vector2(2, 2)
	pilot_face.size = Vector2(48, 18)
	pilot_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pilot_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pilot_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face_path = "res://assets/ui/pilots/%s.png" % pid
	if ResourceLoader.exists(face_path):
		pilot_face.texture = load(face_path)
	frame.add_child(pilot_face)
	# Ship art 1.5x; bottom edge overflows frame by ~1/10 of frame height
	var portrait = TextureRect.new()
	portrait.name = "ShipArt"
	var art_h = 52.0 * 1.5 * 0.55  # tall-ish
	var overflow = 52.0 * 0.10
	portrait.position = Vector2(-8, 52.0 - art_h + overflow)
	portrait.size = Vector2(68, art_h)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ptex = _portrait_icon(ship_id)
	if ptex:
		portrait.texture = ptex
	frame.add_child(portrait)
	frame.set_meta("ship_id", ship_id)
	hb.add_child(frame)
	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	var l1 = Label.new()
	l1.text = "%s  %s" % [p["name"], ship_name]
	l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l1)
	# build progress (one bar per active tonnage job)
	var bars_wrap = VBoxContainer.new()
	bars_wrap.add_theme_constant_override("separation", 2)
	bars_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var any_bar = false
	for ton_key in PILOTS.TONNAGES:
		var bjob = p.get("building", {}).get(ton_key)
		if bjob == null or typeof(bjob) != TYPE_DICTIONARY:
			continue
		any_bar = true
		var row_bar = Control.new()
		row_bar.custom_minimum_size = Vector2(0, 10)
		row_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar = ProgressBar.new()
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.max_value = 1.0
		var dur = float(bjob.get("build_s", bjob.get("duration", 1)))
		var elapsed = float(bjob.get("t", 0))
		bar.value = clampf(elapsed / maxf(dur, 0.001), 0.0, 1.0) if dur > 0.001 else 0.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_bar.add_child(bar)
		var head = TextureRect.new()
		head.custom_minimum_size = Vector2(14, 14)
		head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.texture = _tonnage_icon(str(ton_key))
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.position = Vector2(maxf(0.0, bar.value * 200.0 - 7.0), -2)
		row_bar.add_child(head)
		bars_wrap.add_child(row_bar)
	## No active jobs → no empty bars (plan: 没有在造的吨位不画空条).
	if any_bar:
		vb.add_child(bars_wrap)
	var l2 = Label.new()
	var res_n = _pilot_resource_count(str(p["id"])) if map != null else 0
	var line2 = "%s / %s" % [_sys_label(p), _home_label(p)]
	if res_n > 0:
		line2 += " | R%d" % res_n
	l2.text = line2
	l2.modulate = Color(0.75, 0.8, 0.88)
	l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l2)
	hb.add_child(vb)
	row.set_meta("pilot", pid)
	return row

func _pilot_build_progress(p: Dictionary) -> float:
	var best = 0.0
	var building: Dictionary = p.get("building", {})
	for ton in building.keys():
		var b = building[ton]
		if b == null or typeof(b) != TYPE_DICTIONARY:
			continue
		var dur = float(b.get("build_s", b.get("duration", 0)))
		var elapsed = float(b.get("t", 0))
		if dur > 0.001:
			best = maxf(best, clampf(elapsed / dur, 0.0, 1.0))
		elif b.has("progress"):
			best = maxf(best, clampf(float(b["progress"]), 0.0, 1.0))
	return best

func _on_all_current_ships_to_prod() -> void:
	## 全体：把当前驾驶中的舰船型号写入对应吨位制造产线（auto_build）
	var n = 0
	var started = 0
	for p in pilots:
		if int(p.get("faction", 0)) != viewer_faction:
			continue
		var u = _unit_by_id(str(p.get("unit_id", "")))
		if u.is_empty() or not u.get("alive", false):
			continue
		var sid = str(u.get("ship_id", ""))
		if sid == "":
			continue
		var ton = str(u.get("tonnage", data.ship_def(sid).get("tonnage", "")))
		if ton == "":
			continue
		pilots_sys.set_auto(p, ton, sid)
		n += 1
	# Kick manufacture same frame so progress bars move immediately
	pilots_sys.tick_build(pilots, 0.05, map)
	for p2 in pilots:
		if int(p2.get("faction", 0)) != viewer_faction:
			continue
		var building: Dictionary = p2.get("building", {})
		for ton2 in building.keys():
			if building[ton2] != null:
				started += 1
				break
	_rebuild_hud_list()
	var btn: Button = all_prod_btn
	if btn == null and left_col:
		btn = left_col.get_node_or_null("AllToProdBtn") as Button
	if btn:
		all_prod_btn = btn
		if n <= 0:
			btn.text = "全体：无驾驶舰可写产线"
		else:
			btn.text = "已写入产线 ×%d（开工 %d）" % [n, started]
		get_tree().create_timer(2.2).timeout.connect(_reset_all_prod_btn_text)
	# #region agent log
	_agent_dbg("A5", "board_root.all_to_prod", "set_auto", {
		"count": n, "started": started,
		"btn": btn != null, "label": (btn.text if btn else ""),
		"runId": "post-fix"
	})
	# #endregion

func _reset_all_prod_btn_text() -> void:
	if all_prod_btn and is_instance_valid(all_prod_btn):
		all_prod_btn.text = "全体：当前驾驶舰 → 制造产线"

func _layout_left_col() -> void:
	if left_col == null or not is_instance_valid(left_col):
		return
	var vh = get_viewport().get_visible_rect().size.y
	var win_h = float(DisplayServer.window_get_size().y)
	if win_h > 100.0:
		vh = minf(vh, win_h)
	left_col.position = Vector2(8, 8)
	left_col.size = Vector2(360, maxf(280.0, vh - 16.0))

func _on_sync_move_pressed() -> void:
	sync_move_enabled = not sync_move_enabled
	_refresh_sync_move_btn()
	# #region agent log
	_agent_dbg("S7", "board_root.sync_move", "toggle", {"on": sync_move_enabled, "runId": "post-fix"})
	# #endregion

func _refresh_sync_move_btn() -> void:
	if sync_move_btn == null:
		return
	sync_move_btn.text = "单位同步移动（%s）" % ("开" if sync_move_enabled else "关")

func _stamp_unit_trail(u: Dictionary, delta: float) -> void:
	## EveAC-style: stamp wake points in world; head pinned to stern, history ages free
	var pts: Array = u.get("trail_pts", [])
	var acc = float(u.get("trail_acc", 0.0)) + delta
	# Age existing
	var aged: Array = []
	for p in pts:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var age = float(p.get("age", 0.0)) + delta
		if age < 0.85:
			aged.append({"pos": p["pos"], "age": age})
	pts = aged
	var interval = 0.05
	if acc >= interval:
		acc = 0.0
		var stern = u["pos"]
		var fd: Vector3 = u.get("face_dir", Vector3.FORWARD)
		if fd.length_squared() > 0.0001:
			stern = u["pos"] - fd.normalized() * 1.1
		stern.y = BoardTypes.UNIT_Y + 0.15
		# Avoid stacking identical stamps
		var ok = true
		if pts.size() > 0:
			var last: Vector3 = pts[pts.size() - 1]["pos"]
			if last.distance_to(stern) < 0.12:
				ok = false
		if ok:
			pts.append({"pos": stern, "age": 0.0})
		while pts.size() > 24:
			pts.remove_at(0)
	u["trail_pts"] = pts
	u["trail_acc"] = acc

func _rebuild_unit_trail_mesh(trail: MeshInstance3D, u: Dictionary) -> void:
	var pts: Array = u.get("trail_pts", [])
	if pts.size() < 2:
		trail.mesh = null
		return
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w = 0.11
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]["pos"]
		var b: Vector3 = pts[i + 1]["pos"]
		var dir = b - a
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		var side = Vector3(-dir.z, 0, dir.x) * half_w
		var age0 = float(pts[i].get("age", 0.0))
		var age1 = float(pts[i + 1].get("age", 0.0))
		var a0 = clampf(1.0 - age0 / 0.85, 0.0, 1.0) * 0.55
		var a1 = clampf(1.0 - age1 / 0.85, 0.0, 1.0) * 0.55
		var c0 = Color(0.45, 0.85, 1.0, a0)
		var c1 = Color(0.45, 0.85, 1.0, a1)
		st.set_color(c0); st.add_vertex(a + side)
		st.set_color(c1); st.add_vertex(b + side)
		st.set_color(c1); st.add_vertex(b - side)
		st.set_color(c0); st.add_vertex(a + side)
		st.set_color(c1); st.add_vertex(b - side)
		st.set_color(c0); st.add_vertex(a - side)
		# Crossed ribbon
		var up = Vector3(0, half_w, 0)
		st.set_color(c0); st.add_vertex(a + up)
		st.set_color(c1); st.add_vertex(b + up)
		st.set_color(c1); st.add_vertex(b - up)
		st.set_color(c0); st.add_vertex(a + up)
		st.set_color(c1); st.add_vertex(b - up)
		st.set_color(c0); st.add_vertex(a - up)
	trail.mesh = st.commit()
	trail.global_position = Vector3.ZERO
	# #region agent log
	if Engine.get_process_frames() % 40 == 0:
		_agent_dbg("A4", "board_root.trail", "stamp_count", {"unit": u["id"], "n": pts.size(), "runId": "post-fix"})
	# #endregion

func _tonnage_icon(ton: String) -> Texture2D:
	if _tonnage_tex.has(ton):
		return _tonnage_tex[ton]
	var path = "res://assets/ui/sprites/tonnage/%s_32.png" % ton
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/sprites/tonnage/destroyer_32.png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tonnage_tex[ton] = tex
	return tex

func _tonnage_overlay_set(rel: String) -> Dictionary:
	# EveAC allegiances from local viewer POV
	var key = "friendly"
	if rel == "self" or rel == "fleet" or rel == "allied":
		key = "fleet"
	elif rel == "hostile" or rel == "enemy":
		key = "enemy"
	elif rel == "friendly" or rel == "neutral":
		key = "friendly"
	var sets = {
		"fleet": {"bg": "04_fleet_member_bg.png", "badge": "03_fleet_member.png"},
		"enemy": {"bg": "02_red_bg.png", "badge": "01_red_minus_badge.png"},
		"friendly": {"bg": "05_blue_bg.png", "badge": "06_friendly_badge.png"},
	}
	var conf: Dictionary = sets.get(key, sets["friendly"])
	var out = {"bg": null, "badge": null}
	for k2 in ["bg", "badge"]:
		var p2 = "res://assets/ui/sprites/tonnage_overlays/%s" % conf[k2]
		if ResourceLoader.exists(p2):
			out[k2] = load(p2)
	return out

func _ship_sky_tex(ship_id: String) -> Texture2D:
	# EveAC legacy panoramas — pick by ship hash so switch ship swaps sky
	var skies = [
		"res://assets/skyboxes/amarr.jpeg",
		"res://assets/skyboxes/gallente.jpeg",
		"res://assets/skyboxes/wormhole.jpeg",
		"res://assets/skyboxes/races/ah1.jpg",
		"res://assets/skyboxes/races/ch1.jpg",
		"res://assets/skyboxes/races/gh1.jpg",
		"res://assets/skyboxes/races/mh1.jpg",
		"res://assets/skyboxes/board_panorama.jpeg",
	]
	var h = abs(hash(ship_id))
	var path = skies[h % skies.size()]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	for p in skies:
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null

func _refresh_pilot_row_ship_art(row: Control, ship_id: String) -> void:
	if row == null:
		return
	var rsky = row.find_child("RowSky", true, false) as TextureRect
	if rsky:
		rsky.texture = _ship_sky_tex(ship_id) if ship_id != "" else null
	var frame = null
	var hb_find = row.find_child("HBoxContainer", true, false)
	if hb_find == null:
		for c in row.get_children():
			if c is HBoxContainer:
				hb_find = c
				break
			for cc in c.get_children():
				if cc is HBoxContainer:
					hb_find = cc
					break
	if hb_find:
		for cc in hb_find.get_children():
			if cc is Control and (cc.has_node("SkyBg") or cc.has_node("ShipArt")):
				frame = cc
				break
	if frame == null:
		return
	var sky = frame.get_node_or_null("SkyBg") as TextureRect
	if sky:
		sky.texture = _ship_sky_tex(ship_id) if ship_id != "" else null
	var art = frame.get_node_or_null("ShipArt") as TextureRect
	if art:
		if ship_id == "":
			art.texture = null
			art.visible = false
		else:
			art.texture = _portrait_icon(ship_id)
			art.visible = true
	frame.set_meta("ship_id", ship_id)

func _portrait_icon(ship_id: String) -> Texture2D:
	if ship_id == "":
		return null
	if _portrait_tex.has(ship_id):
		return _portrait_tex[ship_id]
	var path = "res://assets/ui/portraits/%s.png" % ship_id
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_portrait_tex[ship_id] = tex
	return tex

func _pilot_resource_count(pid: String) -> int:
	var n = 0
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c.get("kind", -1)) != BoardTypes.CellKind.RESOURCE:
				continue
			if str(c.get("assigned_pilot_id", "")) == pid:
				n += 1
	return n

func _sys_label(p: Dictionary) -> String:
	var u = _unit_by_id(str(p.get("unit_id", "")))
	if u:
		return str(map.systems[u["sys"]]["name"])
	var cs: String = str(p.get("current_station", ""))
	if cs == "" or not map.systems.has(cs):
		return ""
	return str(map.systems[cs]["name"])

func _home_label(p: Dictionary) -> String:
	var h: String = str(p.get("home_station", ""))
	if h == "" or not map.systems.has(h):
		return "鏃犲綊灞炵┖闂寸珯"
	return str(map.systems[h]["name"])

func _unit_by_id(id: String) -> Dictionary:
	if id == "":
		return {}
	for u in units:
		if u["id"] == id:
			return u
	return {}

func _pilot_by_id(id: String) -> Dictionary:
	for p in pilots:
		if p["id"] == id:
			return p
	return {}

func _process(delta: float) -> void:
	if match_over:
		return
	pilots_sys.tick_build(pilots, delta, map)
	_drain_order_queue(2)
	_tick_movement(delta)
	_tick_capture(delta)
	_tick_regen_and_repair(delta)
	_tick_weapon_locks(delta)
	_tick_combat(delta)
	_tick_ai(delta)
	_tick_ai_respawn()
	var occ_changed_frame = _refresh_occupancy()
	if occ_changed_frame and starmap_view:
		_starmap_scale_dirty = true
	if starmap_view:
		var scaled = starmap_view.tick_smooth_scales(delta)
		starmap_view.tick_screen_const_icons()
		if scaled:
			_starmap_scale_dirty = true
		# Capture rim needs near-realtime remesh (not only 0.5s)
		if map.capture_dirty:
			_capture_rebuild_acc += delta
			if _capture_rebuild_acc >= 0.08:
				_capture_rebuild_acc = 0.0
				map.capture_dirty = false
				starmap_view.rebuild_mesh_only()
		if _starmap_scale_dirty:
			_starmap_rebuild_acc += delta
			if _starmap_rebuild_acc >= 0.04:
				_starmap_rebuild_acc = 0.0
				starmap_view.rebuild_mesh_only()
				starmap_view._rebuild_cell_pick()
				starmap_view.tick_icon_edge_follow()
				_reanchor_idle_units()
				var still = false
				var dump: Dictionary = {}
				for sid in map.systems.keys():
					var t = float(map.systems[sid].get("scale", 1.0))
					var v = starmap_view.visual_scale_of(sid)
					dump[sid] = {"t": t, "v": v}
					if absf(t - v) > 0.002:
						still = true
				_starmap_scale_dirty = still
				# #region agent log
				if Engine.get_process_frames() % 20 == 0:
					_agent_dbg("B6", "board_root.scale_tick", "smooth_remesh", {
						"still": still, "scales": dump, "runId": "post-fix"
					})
				# #endregion
	_separate_stacked_units(delta)
	_curtain_acc += delta
	if _curtain_acc >= 0.12:
		_curtain_acc = 0.0
		_rebuild_guard_curtains()
	_update_unit_visuals(delta)
	if cam and cam.has_method("tick_breathe"):
		cam.tick_breathe(delta)
	_update_box_overlay()
	rebuild_timer += delta
	if rebuild_timer > 0.35:
		rebuild_timer = 0.0
		var occ_changed = _refresh_occupancy()
		if occ_changed and starmap_view:
			_starmap_scale_dirty = true
			_starmap_rebuild_acc = 0.0
			starmap_view.rebuild_labels(pilots)
			starmap_view._rebuild_sector_icons()
			starmap_view.tick_icon_edge_follow()
			_reanchor_idle_units()
			# #region agent log
			var _sids = map.systems.keys()
			if _sids.size() > 0:
				var sid0 = str(_sids[0])
				var c0 = map.systems[sid0]["cells"][0]
				_agent_dbg("A1", "board_root.occupancy", "angles_locked", {
					"phase": float(map.systems[sid0].get("ring_phase", -1)),
					"c0": float(c0.get("angle_center", 0)), "half": float(c0.get("angle_half", 0)),
					"runId": "post-fix"
				})
			# #endregion
		_refresh_hud_progress_only()
		if _detail_dirty:
			_detail_dirty = false
			_update_detail()
	_check_defeat()

func _refresh_occupancy() -> bool:
	## Presence drives scale only. Angles stay locked (no ring rotation).
	## Jump blends weight from source → dest so rings ease instead of popping.
	## Soft reserve_weight (0→1 over PREP+INVULN) adds to dest presence before land.
	var weight: Dictionary = {}
	for sid in map.systems.keys():
		weight[sid] = 0.0
	for u in units:
		if not u.get("alive", false):
			continue
		_update_reserve_weight(u)
		var rw: float = clampf(float(u.get("reserve_weight", 0.0)), 0.0, 1.0)
		if u.get("step_kind") == "jump" and int(u.get("phase", 0)) == BoardTypes.MovePhase.INVULN:
			var t0j: float = maxf(float(u.get("step_invuln", 1.0)), 0.01)
			var kj: float = 1.0 - clampf(float(u.get("phase_t", 0.0)) / t0j, 0.0, 1.0)
			var src: String = str(u.get("from_sys", u.get("sys", "")))
			var dst: String = str(u.get("to_sys", u.get("sys", "")))
			if weight.has(src):
				weight[src] = float(weight[src]) + (1.0 - kj)
			if weight.has(dst):
				weight[dst] = float(weight[dst]) + kj
		else:
			var ph: int = int(u.get("phase", 0))
			var sid_u: String = str(u.get("sys", ""))
			if ph == BoardTypes.MovePhase.PREP or ph == BoardTypes.MovePhase.INVULN:
				## Source keeps (1-rw); dest gets rw so ring grows before touchdown.
				if weight.has(sid_u):
					weight[sid_u] = float(weight[sid_u]) + (1.0 - rw)
				var rsys: String = str(u.get("reserve_sys", u.get("to_sys", "")))
				if rsys != "" and weight.has(rsys):
					weight[rsys] = float(weight[rsys]) + rw
			else:
				if weight.has(sid_u):
					weight[sid_u] = float(weight[sid_u]) + 1.0
	var empty_s := float(map.layout.get("empty_system_scale", 0.62))
	var changed = false
	for sid in map.systems.keys():
		## Do NOT clamp presence to binary 1 — allow intermediate ring sizes.
		var presence := clampf(float(weight.get(sid, 0.0)), 0.0, 1.0)
		var eased := presence * presence * (3.0 - 2.0 * presence)
		var new_scale := lerpf(empty_s, 1.0, eased)
		var old_scale := float(map.systems[sid].get("scale", 1.0))
		if absf(old_scale - new_scale) > 0.0008:
			changed = true
			# #region agent log
			if Engine.get_process_frames() % 20 == 0:
				_agent_dbg("B3", "board_root._refresh_occupancy", "scale_target", {
					"sys": sid, "w": float(weight.get(sid, 0.0)), "old": old_scale, "new": new_scale, "runId": "post-fix"
				})
			# #endregion
		map.systems[sid]["scale"] = new_scale
	return changed

func _update_reserve_weight(u: Dictionary) -> void:
	var ph: int = int(u.get("phase", 0))
	if ph == BoardTypes.MovePhase.PREP or ph == BoardTypes.MovePhase.INVULN:
		var prep: float = maxf(float(u.get("step_prep", u.get("move_s", 1.0))), 0.01)
		var inv: float = maxf(float(u.get("step_invuln", u.get("move_s", 1.0))), 0.01)
		var total: float = prep + inv
		var left: float = float(u.get("phase_t", 0.0))
		var elapsed: float = 0.0
		if ph == BoardTypes.MovePhase.PREP:
			elapsed = prep - left
		else:
			elapsed = prep + (inv - left)
		u["reserve_weight"] = clampf(elapsed / total, 0.0, 1.0)
	elif ph == BoardTypes.MovePhase.LANDING or ph == BoardTypes.MovePhase.IDLE:
		u["reserve_weight"] = 0.0

func _tick_movement(delta: float) -> void:
	for u in units:
		if not u.get("alive", false):
			continue
		match int(u["phase"]):
			BoardTypes.MovePhase.IDLE:
				u["float_t"] = float(u["float_t"]) + delta
				if not u["path"].is_empty():
					if _sync_start_blocked(u):
						continue
					_start_step(u)
			BoardTypes.MovePhase.PREP:
				u["phase_t"] = float(u["phase_t"]) - delta
				var dest_p: Vector3 = u.get("to_pos", u["pos"])
				var creep_dir = Vector3(dest_p.x - u["pos"].x, 0.0, dest_p.z - u["pos"].z)
				if creep_dir.length_squared() > 0.0001:
					u["face_dir"] = creep_dir.normalized()
					var creep_speed = 0.28
					var step_v = u["face_dir"] * creep_speed * delta
					if step_v.length() > creep_dir.length():
						step_v = creep_dir
					var np = u["pos"] + step_v
					np.y = BoardTypes.UNIT_Y
					u["pos"] = _clamp_pos_to_cell(str(u["sys"]), int(u["cell"]), np)
				if u["phase_t"] <= 0.0:
					u["from_pos"] = Vector3(u["pos"].x, BoardTypes.UNIT_Y, u["pos"].z)
					u["phase"] = BoardTypes.MovePhase.INVULN
					u["phase_t"] = float(u.get("step_invuln", u["move_s"]))
					u["alpha"] = BoardTypes.INVULN_ALPHA
					u["trail_pts"] = []
					u["trail_acc"] = 0.0
					_guard_force_off(u)
					admin.request("board.move", {"unit": u["id"], "phase": "invuln"})
			BoardTypes.MovePhase.INVULN:
				u["phase_t"] = float(u["phase_t"]) - delta
				var t0: float = float(u.get("step_invuln", u["move_s"]))
				var k = 1.0 - clampf(u["phase_t"] / maxf(t0, 0.01), 0.0, 1.0)
				if u.get("step_kind") == "jump" and starmap_view:
					var fs: String = str(u.get("from_sys", u["sys"]))
					var ts: String = str(u.get("to_sys", u["sys"]))
					var a: Vector3 = starmap_view.gate_outer_point(fs, ts)
					var b: Vector3 = starmap_view.gate_outer_point(ts, fs)
					a.y = BoardTypes.UNIT_Y
					b.y = BoardTypes.UNIT_Y
					u["from_pos"] = a
					u["to_pos"] = b
					u["pos"] = a.lerp(b, k)
					var jd = Vector3(b.x - u["pos"].x, 0.0, b.z - u["pos"].z)
					if jd.length_squared() > 0.0001:
						u["face_dir"] = jd.normalized()
				else:
					# Chase reserved land slot (or live cell center) as ring scales
					var live: Vector3 = u.get("land_pos", _cell_pos_visual(str(u["sys"]), int(u["to_cell"]), BoardTypes.UNIT_Y))
					if u.has("reserve_slot"):
						live = _cell_slot_pos(str(u["sys"]), int(u["to_cell"]), int(u["reserve_slot"]), _cell_claim_count(str(u["sys"]), int(u["to_cell"])))
						u["land_pos"] = live
					u["to_pos"] = live
					var remain = Vector3(live.x - u["pos"].x, 0.0, live.z - u["pos"].z)
					var arrive = maxf(float(u["phase_t"]), delta)
					var step = remain * clampf(delta / arrive, 0.0, 1.0)
					u["pos"] = Vector3(u["pos"].x + step.x, BoardTypes.UNIT_Y, u["pos"].z + step.z)
					if remain.length_squared() > 0.0001:
						u["face_dir"] = remain.normalized()
					var seen := _cell_index_at(str(u["sys"]), u["pos"])
					if seen >= 0 and seen != int(u["cell"]):
						# #region agent log
						_agent_dbg("B2", "board_root.move", "cell_visual", {
							"unit": u["id"], "from": int(u["cell"]), "seen": seen, "want": int(u["to_cell"]), "runId": "post-fix"
						})
						# #endregion
						u["cell"] = seen
				if u["phase_t"] <= 0.0:
					if u.get("step_kind") == "jump":
						u["sys"] = u["to_sys"]
						u["cell"] = u["to_cell"]
						starmap_view.transit_gates.erase("%s:%d" % [u.get("from_sys", u["sys"]), int(u.get("from_cell", 0))])
					else:
						u["cell"] = u["to_cell"]
					u["phase"] = BoardTypes.MovePhase.LANDING
					u["phase_t"] = float(u["landing_s"])
					u["alpha"] = 1.0
					_guard_force_off(u)
					var land = u.get("land_pos", _clamp_pos_to_cell(str(u["sys"]), int(u["cell"]), u["pos"]))
					if u.has("reserve_slot"):
						land = _cell_slot_pos(str(u["sys"]), int(u["cell"]), int(u["reserve_slot"]), _cell_claim_count(str(u["sys"]), int(u["cell"])))
					u["land_pos"] = land
					u["rest_pos"] = land
					u["pos"] = land
					# #region agent log
					var _vc = _cell_pos_visual(str(u["sys"]), int(u["cell"]), BoardTypes.UNIT_Y)
					_agent_dbg("L1", "board_root.land", "land_pos", {
						"unit": u["id"], "sys": u["sys"], "cell": int(u["cell"]),
						"slot": int(u.get("reserve_slot", -1)),
						"px": u["pos"].x, "pz": u["pos"].z, "cx": _vc.x, "cz": _vc.z,
						"dist": u["pos"].distance_to(_vc), "runId": "post-fix"
					})
					# #endregion
					if u["path"].is_empty():
						_clear_move_line(str(u["id"]))
						u.erase("order_dest_sys")
						u.erase("sync_gid")
					_apply_bubble_pull_on_land(u)
			BoardTypes.MovePhase.LANDING:
				u["phase_t"] = float(u["phase_t"]) - delta
				if u.has("land_pos"):
					var lp: Vector3 = u["land_pos"]
					u["pos"] = u["pos"].lerp(Vector3(lp.x, BoardTypes.UNIT_Y, lp.z), clampf(delta * 4.0, 0.0, 1.0))
				if u["phase_t"] <= 0.0:
					u["phase"] = BoardTypes.MovePhase.IDLE
					_clear_reserve(u)
					if u["path"].is_empty():
						u.erase("sync_gid")
		_apply_figure8(u)

func _apply_figure8(u: Dictionary) -> void:
	if int(u["phase"]) != BoardTypes.MovePhase.IDLE:
		return
	var base: Vector3 = u.get("rest_pos", Vector3.ZERO)
	if base == Vector3.ZERO:
		base = _cell_pos_visual(u["sys"], int(u["cell"]), BoardTypes.UNIT_Y)
		u["rest_pos"] = base
	# Peaceful idle: stay put (tiny amp only if engaging)
	var in_combat = bool(u.get("took_damage", false)) or float(u.get("dealt_timer", 0.0)) > 0.0
	if not in_combat:
		u["pos"] = Vector3(base.x, BoardTypes.UNIT_Y, base.z)
		return
	var sc = starmap_view.visual_scale_of(u["sys"]) if starmap_view else float(map.systems[u["sys"]].get("scale", 1.0))
	var band = (float(map.layout.get("ring_outer", 26)) - float(map.layout.get("ring_inner", 12))) * sc
	var amp = band * 0.03
	var cycle = BoardTypes.FIGURE8_CYCLE_K * float(u["inertia"]) * 2.0
	var freq = 1.0 + float(u.get("float_freq", 0.0))
	var t = float(u["float_t"]) / maxf(cycle, 0.1) * TAU * freq
	var x = amp * sin(t)
	var z = amp * sin(t) * cos(t)
	var xr = (x - z) * 0.707
	var zr = (x + z) * 0.707
	var raw = Vector3(base.x + xr, BoardTypes.UNIT_Y, base.z + zr)
	u["pos"] = _clamp_pos_to_cell(u["sys"], int(u["cell"]), raw)
	# #region agent log
	if int(Time.get_ticks_msec() / 800.0) != int(u.get("_dbg_t", -1)):
		u["_dbg_t"] = int(Time.get_ticks_msec() / 800.0)
		var sysd: Dictionary = map.systems[u["sys"]]
		var ccell: Dictionary = sysd["cells"][int(u["cell"])]
		var center: Vector3 = sysd["center"]
		var local = Vector3(u["pos"].x - center.x, 0, u["pos"].z - center.z)
		var ang = atan2(local.x, -local.z)
		var ac = float(ccell["angle_center"])
		var ah = float(ccell["angle_half"])
		var dlt = absf(fposmod(ang - ac + PI, TAU) - PI)
		if dlt > ah * 0.98:
			_agent_dbg("H3", "board_root._apply_figure8", "out_of_cell", {
				"unit": u["id"], "dlt": dlt, "ah": ah, "sys": u["sys"], "cell": u["cell"],
				"runId": "post-fix"
			})
	# #endregion


func _make_flat_ring_mesh(r0: float, r1: float, segs: int) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var a0 = float(i) / float(segs) * TAU
		var a1 = float(i + 1) / float(segs) * TAU
		var p00 = Vector3(sin(a0) * r0, 0, -cos(a0) * r0)
		var p10 = Vector3(sin(a1) * r0, 0, -cos(a1) * r0)
		var p01 = Vector3(sin(a0) * r1, 0, -cos(a0) * r1)
		var p11 = Vector3(sin(a1) * r1, 0, -cos(a1) * r1)
		st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
		st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
	return st.commit()

func _clamp_pos_to_cell(sys: String, cell: int, pos: Vector3) -> Vector3:
	var sysd: Dictionary = map.systems[sys]
	var center: Vector3 = sysd["center"]
	var c: Dictionary = sysd["cells"][cell]
	var sc = starmap_view.visual_scale_of(sys) if starmap_view else float(sysd.get("scale", 1.0))
	# Match starmap_view gap + inset so ships stay inside drawn fill (not just data half)
	var gap := 0.022
	var pad_r := 1.15
	var inner: float = float(map.layout.get("ring_inner", 12)) * sc + pad_r
	var outer: float = float(map.layout.get("ring_outer", 26)) * sc - pad_r
	var local = Vector3(pos.x - center.x, 0, pos.z - center.z)
	var r = clampf(local.length(), inner, outer)
	var ang = atan2(local.x, -local.z)
	var ac = float(c["angle_center"])
	var ah = maxf(float(c["angle_half"]) - gap, 0.02) * 0.90
	var dlt = fposmod(ang - ac + PI, TAU) - PI
	dlt = clampf(dlt, -ah, ah)
	var a = ac + dlt
	var out = center + Vector3(sin(a) * r, BoardTypes.UNIT_Y, -cos(a) * r)
	# #region agent log
	if not c.has("_dbg_clamp"):
		c["_dbg_clamp"] = true
		_agent_dbg("L1", "board_root._clamp_pos_to_cell", "clamp_visual", {
			"sys": sys, "cell": cell, "ah": ah, "gap": gap, "r": r,
			"dlt_in": fposmod(ang - ac + PI, TAU) - PI, "dlt_out": dlt, "runId": "post-fix"
		})
	# #endregion
	return out

func _cell_index_at(sys: String, pos: Vector3) -> int:
	if not map.systems.has(sys):
		return -1
	var sysd: Dictionary = map.systems[sys]
	var center: Vector3 = sysd["center"]
	var local = Vector3(pos.x - center.x, 0, pos.z - center.z)
	if local.length_squared() < 0.01:
		return -1
	var ang = atan2(local.x, -local.z)
	var best := -1
	var best_d := 999.0
	for c in sysd["cells"]:
		var ac = float(c["angle_center"])
		var dlt = absf(fposmod(ang - ac + PI, TAU) - PI)
		if dlt < best_d:
			best_d = dlt
			best = int(c["index"])
	return best

func _cell_pos_visual(sys: String, cell: int, y: float = BoardTypes.UNIT_Y) -> Vector3:
	var s: Dictionary = map.systems[sys]
	var c: Dictionary = s["cells"][cell]
	var sc = starmap_view.visual_scale_of(sys) if starmap_view else float(s.get("scale", 1.0))
	var mid_r = (float(map.layout.get("ring_inner", 12)) + float(map.layout.get("ring_outer", 26))) * 0.5 * sc
	var a: float = float(c["angle_center"])
	return s["center"] + Vector3(sin(a) * mid_r, y, -cos(a) * mid_r)


func _cell_entry_pos(sys: String, from_cell: int, to_cell: int, from_pos: Vector3) -> Vector3:
	# Point inside destination sector near the shared separator — crossing the line = entered
	var _dest_center = _cell_pos_visual(sys, to_cell, BoardTypes.UNIT_Y)
	var _from_center = _cell_pos_visual(sys, from_cell, BoardTypes.UNIT_Y)
	var sysd: Dictionary = map.systems[sys]
	var center: Vector3 = sysd["center"]
	var sc = starmap_view.visual_scale_of(sys) if starmap_view else float(sysd.get("scale", 1.0))
	var mid_r = (float(map.layout.get("ring_inner", 12)) + float(map.layout.get("ring_outer", 26))) * 0.5 * sc
	# Keep caller's radial distance when possible
	var radial = Vector3(from_pos.x - center.x, 0, from_pos.z - center.z).length()
	if radial < 0.1:
		radial = mid_r
	var a0 = float(sysd["cells"][from_cell]["angle_center"])
	var a1 = float(sysd["cells"][to_cell]["angle_center"])
	var half1 = float(sysd["cells"][to_cell]["angle_half"])
	# Angle just inside dest near shared border
	var delta = fposmod(a1 - a0 + PI, TAU) - PI
	var border = a0 + delta * 0.5
	var inward = border + (1.0 if delta >= 0.0 else -1.0) * minf(half1 * 0.18, 0.12)
	var pos = center + Vector3(sin(inward) * radial, BoardTypes.UNIT_Y, -cos(inward) * radial)
	# Soft pull toward a free slot so stacks fan out
	var slot = _cell_slot_offset(sys, to_cell)
	return pos + slot

func _cell_slot_offset(sys: String, cell: int) -> Vector3:
	var n = 0
	for u in units:
		if u.get("alive", false) and u.get("sys") == sys and int(u.get("cell", -1)) == cell:
			n += 1
	var ang = float(n) * 0.9
	var rad = 1.6 + float(n % 3) * 0.7
	return Vector3(sin(ang) * rad, 0, -cos(ang) * rad)

func _start_step(u: Dictionary) -> void:
	var step: Dictionary = u["path"].pop_front()
	u["from_cell"] = int(u["cell"])
	u["to_cell"] = int(step["to"])
	u["step_kind"] = step["kind"]
	u["from_sys"] = u["sys"]
	if step["kind"] == "jump":
		u["to_sys"] = step.get("to_sys", u["sys"])
		u["from_pos"] = starmap_view.gate_outer_point(u["sys"], u["to_sys"]) if starmap_view else map.cell_world_pos(u["sys"], u["cell"], BoardTypes.UNIT_Y)
		u["from_pos"].y = BoardTypes.UNIT_Y
		u["to_pos"] = starmap_view.gate_outer_point(u["to_sys"], u["sys"]) if starmap_view else map.cell_world_pos(u["to_sys"], u["to_cell"], BoardTypes.UNIT_Y)
		u["to_pos"].y = BoardTypes.UNIT_Y
		var gk = "%s:%d" % [u["sys"], int(u["from_cell"])]
		var stag = float(_gate_stagger.get(gk, 0.0))
		_gate_stagger[gk] = stag + rng.randf_range(0.1, 0.5)
		u["step_invuln"] = float(u["jump_s"]) + stag
		starmap_view.transit_gates[gk] = true
	else:
		u["to_sys"] = u["sys"]
		u["from_pos"] = Vector3(u["pos"].x, BoardTypes.UNIT_Y, u["pos"].z)
		var dest = int(step["to"])
		dest = _bubble_redirect(u["sys"], int(u["cell"]), dest, u)
		u["to_cell"] = dest
		# Straight chord in world XZ (not angular arc on the ring)
		u["to_pos"] = _cell_entry_pos(u["sys"], int(u["cell"]), dest, u["from_pos"])
		u["to_pos"].y = BoardTypes.UNIT_Y
		u["step_invuln"] = float(u["move_s"])
	var prep = BoardTypes.align_prep_s(u["inertia"], u["mass"])
	if sync_move_enabled and int(u.get("sync_gid", 0)) > 0:
		var gid = int(u["sync_gid"])
		u["step_invuln"] = _sync_max_step_duration(gid, str(u["step_kind"]), float(u["step_invuln"]))
		prep = _sync_max_prep(gid, prep)
	_assign_reserve(u)
	u["phase"] = BoardTypes.MovePhase.PREP
	u["phase_t"] = prep
	admin.request("board.move", {"unit": u["id"], "phase": "prep", "step": step})
	# #region agent log
	_agent_dbg("S8", "board_root._start_step", "reserve", {
		"unit": u["id"], "sys": str(u.get("to_sys", u["sys"])), "cell": int(u["to_cell"]),
		"slot": int(u.get("reserve_slot", -1)), "sync": int(u.get("sync_gid", 0)),
		"inv": float(u.get("step_invuln", 0)), "runId": "post-fix"
	})
	# #endregion

func _bubble_redirect(sys: String, from_c: int, to_c: int, mover: Dictionary) -> int:
	if mover.get("bubble_immune", false):
		return to_c
	# check cells with bubble
	var cells: Array = map.systems[sys]["cells"]
	var n = cells.size()
	for c in cells:
		if not c.get("bubble", false):
			continue
		var bi: int = c["index"]
		# immune ships skip
		var pull = 3
		var d_from = BoardTypes.shorter_arc_steps(from_c, bi, n)
		var d_to = BoardTypes.shorter_arc_steps(to_c, bi, n)
		if d_from > d_to and d_from <= pull:
			return bi
	return to_c

func _apply_bubble_pull_on_land(_u: Dictionary) -> void:
	# clear transit flags for this unit's gate
	var keys: Array = starmap_view.transit_gates.keys()
	for k in keys:
		# leave flags; simplified clear all when any lands
		pass
	starmap_view.transit_gates.clear()

func _tick_capture(delta: float) -> void:
	var flips = capture.tick(map, units, delta)
	if map.capture_dirty or not flips.is_empty():
		# force link style refresh after ownership change
		if starmap_view and not flips.is_empty():
			starmap_view.rebuild()  # full once on flip (links+icons)
			map.capture_dirty = false
			# #region agent log
			_agent_dbg("C2", "board_root._tick_capture", "flip_rebuild", {
				"n": flips.size(), "owner0": int(flips[0].get("owner", 0)), "runId": "post-fix"
			})
			# #endregion
	var need_ai_res = false
	for f in flips:
		BoardResourceAssign.on_resource_owner_flip(map, f, pilots)
		if int(f.get("kind", -1)) == BoardTypes.CellKind.RESOURCE:
			BoardResourceAssign.auto_assign_new_cell(map, f, pilots, rng)
			need_ai_res = true
		if int(f["owner"]) != 2:
			ai.on_capture_stolen(f["sys"], f["cell"])
		_update_home_stations_on_flip(f)
	if need_ai_res:
		ai.redistribute_resources(map, pilots, rng)

func _update_home_stations_on_flip(f: Dictionary) -> void:
	var sys: String = f["sys"]
	var cell: int = f["cell"]
	var c: Dictionary = map.systems[sys]["cells"][cell]
	if int(c["kind"]) != BoardTypes.CellKind.STATION:
		return
	for p in pilots:
		if str(p.get("home_station", "")) != sys:
			continue
		if int(c["owner"]) == int(p["faction"]):
			continue
		# fall back
		p["home_station"] = _nearest_owned_station(p)
		# Docked pilots keep current_station even if this station flipped hostile
		if p["home_station"] == "" and not p.get("in_station", false):
			if str(p.get("unit_id", "")) == "":
				p["current_station"] = ""

func _nearest_owned_station(p: Dictionary) -> String:
	var fac: int = p["faction"]
	var from_sys = ""
	var u = _unit_by_id(str(p.get("unit_id", "")))
	if u:
		from_sys = u["sys"]
	else:
		from_sys = str(p.get("current_station", p.get("home", "")))
	var best = ""
	var best_d = 999
	for sid in map.systems.keys():
		var sc = map.station_cell(sid)
		if sc < 0:
			continue
		if int(map.systems[sid]["cells"][sc]["owner"]) != fac:
			continue
		var d = _gate_hops(from_sys, sid)
		if d < best_d:
			best_d = d
			best = sid
	return best

func _gate_hops(a: String, b: String) -> int:
	if a == b or a == "" or b == "":
		return 0
	var parent: Dictionary = {a: ""}
	var q: Array = [a]
	while not q.is_empty():
		var s: String = q.pop_front()
		if s == b:
			break
		for link in map.systems[s]["links"]:
			if parent.has(link):
				continue
			parent[link] = s
			q.append(link)
	if not parent.has(b):
		return 99
	var d = 0
	var cur = b
	while cur != a:
		cur = parent[cur]
		d += 1
	return d

func _tick_combat(delta: float) -> void:
	for u in units:
		if not u.get("alive", false):
			continue
		if u.get("bubble_on", false):
			u["bubble_t"] = float(u["bubble_t"]) + delta
			var cell: Dictionary = map.systems[u["sys"]]["cells"][u["cell"]]
			cell["bubble"] = true
			cell["bubble_t"] = u["bubble_t"]
		if int(u["phase"]) == BoardTypes.MovePhase.INVULN or int(u["phase"]) == BoardTypes.MovePhase.LANDING:
			continue
		var pd_claimed: Dictionary = {}
		for g in u["pd"]:
			g["cd"] = float(g["cd"]) - delta
			if g["cd"] > 0.0:
				continue
			var tgt = _pick_pd_target(u, g, pd_claimed)
			if tgt.is_empty():
				continue
			if int(tgt["phase"]) == BoardTypes.MovePhase.INVULN:
				g["cd"] = float(g["cycle"])
				continue # miss
			pd_claimed[str(tgt["id"])] = true
			var dist_m = _pd_tracking_distance_m(u, tgt)
			var p_hit = BoardCombatFormulas.turret_hit_chance(
				g["tracking"], g["sig_res"], g["falloff"], 0.0,
				tgt["speed"], tgt["signature_radius"], dist_m
			)
			g["cd"] = float(g["cycle"])
			g["target"] = tgt["id"]
			var hit = rng.randf() <= p_hit
			var raw = float(g["damage"])
			raw = _focus_on_hit(u, hit, raw)
			if not hit or raw <= 0.0:
				continue
			raw *= BoardCombatFormulas.roll_quality(rng)
			_apply_damage_to_unit(u, tgt, raw, int(tgt["inst"]["resist"]))
			if turret_vfx:
				turret_vfx.play(str(g.get("fx", "rail")), u["pos"], tgt["pos"])
		for w in u.get("weapons", []):
			w["cd"] = float(w["cd"]) - delta
			if float(w["cd"]) > 0.0:
				continue
			if float(w.get("lock_t", 0.0)) < float(w.get("lock_need", 1.0)):
				continue
			var wtgt = _unit_by_id(str(w.get("lock_id", "")))
			if wtgt.is_empty() or not wtgt.get("alive", false):
				continue
			if not _weapon_in_range(u, wtgt, w):
				continue
			w["cd"] = float(w["cycle"])
			## Keep lock on same target across cycles (do not reset lock_t / lock_id).
			_fire_weapon(u, w, wtgt)

func _combat_distance_m(a: Dictionary, b: Dictionary) -> float:
	if a["sys"] != b["sys"] or int(a["cell"]) != int(b["cell"]):
		return 999999.0
	var d: float = Vector3(a["pos"].x, 0, a["pos"].z).distance_to(Vector3(b["pos"].x, 0, b["pos"].z))
	var cell_m = BoardTypes.METERS_PER_CELL
	# map units: ring ~26 -> treat 1 world unit 鈮?cell fraction
	var cells = d / ((float(map.layout.get("ring_outer", 26)) - float(map.layout.get("ring_inner", 12))) + 0.001)
	cells = maxf(cells, BoardTypes.MIN_SAME_CELL_FRAC)
	return cells * cell_m

func _pick_pd_target(u: Dictionary, g: Dictionary, claimed: Dictionary = {}) -> Dictionary:
	var cur = _unit_by_id(str(g.get("target", "")))
	if cur and cur.get("alive", false) and _pd_in_range(u, cur, g):
		if not claimed.has(str(cur["id"])):
			return cur
	var best = {}
	var best_d = INF
	for o in units:
		if not o.get("alive", false):
			continue
		if int(o["faction"]) == int(u["faction"]):
			continue
		if claimed.has(str(o["id"])):
			continue
		if not _pd_in_range(u, o, g):
			continue
		var d: float = Vector3(u["pos"].x, 0, u["pos"].z).distance_to(Vector3(o["pos"].x, 0, o["pos"].z))
		if d < best_d:
			best_d = d
			best = o
	return best

func _pd_in_range(a: Dictionary, b: Dictionary, g: Dictionary) -> bool:
	if a["sys"] != b["sys"]:
		return false
	var n: int = map.systems[a["sys"]]["cells"].size()
	var steps = BoardTypes.shorter_arc_steps(int(a["cell"]), int(b["cell"]), n)
	return steps <= int(g["range_cells"])

func _kill_unit(u: Dictionary) -> void:
	u["alive"] = false
	var p = _pilot_by_id(u["pilot_id"])
	if p:
		p["unit_id"] = ""
		p["in_station"] = false
		var home: String = str(p.get("home_station", ""))
		p["current_station"] = home
		if home == "":
			p["current_station"] = ""
	if cam.follow_unit_id == u["id"]:
		cam.clear_follow_keep_look()
	if unit_nodes.has(u["id"]):
		unit_nodes[u["id"]].visible = false
		var oh2 = unit_nodes[u["id"]].get_node_or_null("Overhead")
		if oh2 and oh2.has_method("set_alive_view"):
			oh2.set_alive_view(false)
	selection.erase(u["id"])

func _tick_ai(delta: float) -> void:
	for u in units:
		if int(u.get("faction", 0)) != 2 or not u.get("alive", false):
			continue
		u["dealt_timer"] = float(u.get("dealt_timer", 0.0)) + delta
	var orders = ai.tick_orders(map, units, data.diplomacy)
	for o in orders:
		var u = _unit_by_id(o["unit_id"])
		if u.is_empty():
			continue
		if int(u.get("faction", 0)) != 2:
			continue  # never steer player ships
		_order_move_ai(u, o["sys"], o["cell"])
		admin.request("ai.order", o)

func _order_move_ai(u: Dictionary, to_sys: String, to_cell: int) -> void:
	# AI may path with capture stops 鈥?simplified: use player nav but allow detour skip
	var prep = BoardTypes.align_prep_s(u["inertia"], u["mass"])
	var path = BoardPlayerNav.find_path(
		map, data.diplomacy, u["faction"],
		u["sys"], u["cell"], to_sys, to_cell,
		prep, u["move_s"], u["landing_s"], u["jump_s"]
	)
	# insert capture waits by not skipping 鈥?movement already stops? We enqueue path; capture happens while idle on cells
	u["path"] = path

func _tick_ai_respawn() -> void:
	for p in pilots:
		if int(p["faction"]) != 2:
			continue
		if str(p.get("unit_id", "")) != "":
			continue
		var cs: String = str(p.get("current_station", ""))
		if cs == "" or not map.systems.has(cs):
			continue
		var counts = pilots_sys.storage_count_by_model(p)
		if counts.is_empty():
			continue
		var ship_id: String = counts.keys()[0]
		var inst = pilots_sys.take_one(p, ship_id)
		if inst.is_empty():
			continue
		var sc = map.station_cell(cs)
		if sc < 0:
			continue
		var u = _spawn_unit(p, inst, cs, sc)
		p["unit_id"] = u["id"]
		p["in_station"] = false
		_ensure_unit_node(u)
		# chase fleet
		var _fid = -1
		for x in units:
			if x.get("pilot_id") != p["id"] and int(x.get("faction", 0)) == 2 and x.get("alive", false) and int(x.get("fleet_id", -1)) >= 0:
				# find original fleet by scanning fleets members for this pilot's old 鈥?use default join lowest
				pass
		# assign to existing fleet of default ship peers 鈥?simplified: join fleet 0
		if not ai.fleets.is_empty():
			u["fleet_id"] = 0
			ai.fleets[0]["members"].append(u["id"])

func _update_unit_visuals(delta: float) -> void:
	for u in units:
		if float(u.get("dealt_timer", 0.0)) > 0.0:
			u["dealt_timer"] = maxf(0.0, float(u["dealt_timer"]) - delta)
			if float(u["dealt_timer"]) <= 0.0:
				u["took_damage"] = false
		if not unit_nodes.has(u["id"]):
			continue
		var n: Node3D = unit_nodes[u["id"]]
		var oh = n.get_node_or_null("Overhead")
		if not u.get("alive", false):
			n.visible = false
			if oh and oh.has_method("set_alive_view"):
				oh.set_alive_view(false)
			continue
		n.visible = true
		n.global_position = u["pos"]
		# Refresh order line endpoint while moving / pending
		if _move_lines.has(u["id"]) and u.has("order_dest_sys"):
			var ds = str(u["order_dest_sys"])
			var dc = int(u.get("order_dest_cell", u["cell"]))
			_set_line_mesh(_move_lines[u["id"]], u["pos"], _cell_pos_visual(ds, dc, BoardTypes.UNIT_Y))
		# Face movement direction (Model/Proxy yaw)
		var aim: Vector3 = u.get("to_pos", Vector3.ZERO) - u["pos"]
		aim.y = 0.0
		if aim.length_squared() < 0.0001:
			aim = u.get("face_dir", Vector3.ZERO)
			aim.y = 0.0
		if aim.length_squared() > 0.0001:
			u["face_dir"] = aim.normalized()
			var look = n.global_position + u["face_dir"]
			look.y = n.global_position.y
			if n.global_position.distance_squared_to(look) > 0.0001:
				n.look_at(look, Vector3.UP)
			# #region agent log
			if Engine.get_process_frames() % 40 == 0 and int(u.get("phase", 0)) != BoardTypes.MovePhase.IDLE:
				_agent_dbg("B1", "board_root.face", "bow", {"unit": u["id"], "fx": u["face_dir"].x, "fz": u["face_dir"].z, "runId": "post-fix"})
			# #endregion
		var flash_t = float(u.get("hit_flash_t", 0.0))
		var shake_t = float(u.get("hit_shake_t", 0.0))
		if flash_t > 0.0:
			u["hit_flash_t"] = maxf(0.0, flash_t - delta)
		if shake_t > 0.0:
			u["hit_shake_t"] = maxf(0.0, shake_t - delta)
			u["hit_shake_phase"] = float(u.get("hit_shake_phase", 0.0)) + delta * 22.0
		var model_n = n.get_node_or_null("Model") as Node3D
		if model_n:
			if not model_n.has_meta("base_local_pos"):
				model_n.set_meta("base_local_pos", model_n.position)
				model_n.set_meta("base_local_scale", model_n.scale)
			var base_pos: Vector3 = model_n.get_meta("base_local_pos")
			var base_sc: Vector3 = model_n.get_meta("base_local_scale")
			var ph = float(u.get("hit_shake_phase", 0.0))
			var amp = shake_t * 0.35
			model_n.position = base_pos + Vector3(sin(ph * 1.7) * amp, 0.0, cos(ph * 2.3) * amp)
			model_n.scale = base_sc * (1.0 + shake_t * 0.08 * sin(ph * 3.1))
			_set_model_hit_flash(model_n, flash_t > 0.0)
		var mat_mesh = n.get_node_or_null("Proxy") as MeshInstance3D
		if mat_mesh and mat_mesh.material_override and mat_mesh.visible:
			var col = BoardTypes.relation_color(_rel_for(u["faction"]))
			col.a = float(u.get("alpha", 1.0))
			if flash_t > 0.0:
				col = col.lerp(Color(1, 1, 1, col.a), 0.65)
			mat_mesh.material_override.albedo_color = col
		var ring = n.get_node_or_null("SelectRing")
		var ring_ol = n.get_node_or_null("SelectRingOutline")
		var sel_on = selection.has(u["id"])
		if ring:
			ring.visible = sel_on
		if ring_ol:
			ring_ol.visible = sel_on
		var moving = int(u["phase"]) == BoardTypes.MovePhase.INVULN
		var trail = n.get_node_or_null("Trail") as MeshInstance3D
		if trail:
			if moving:
				_stamp_unit_trail(u, delta)
				_rebuild_unit_trail_mesh(trail, u)
				trail.visible = true
			else:
				u["trail_pts"] = []
				trail.visible = false
				trail.mesh = null
		if oh:
			if oh.has_method("set_alive_view"):
				oh.set_alive_view(true)
			var p = _pilot_by_id(u["pilot_id"])
			var fac_name = ""
			for f in data.factions.get("factions", []):
				if int(f["id"]) == int(u["faction"]):
					fac_name = str(f.get("abbrev", ""))
					break
			var title = "[%s]%s %s" % [fac_name, p.get("name", ""), u["name"]]
			var inst: Dictionary = u["inst"]
			oh.update_view(
				title,
				float(inst["shield"]), float(inst["armor"]), float(inst["structure"]),
				float(inst["max_s"]), float(inst["max_a"]), float(inst["max_h"]),
				float(inst.get("pristine_s", inst["max_s"])),
				float(inst.get("pristine_a", inst["max_a"])),
				float(inst.get("pristine_h", inst["max_h"])),
				float(inst.get("cap", 0)), float(inst.get("max_cap", 1))
			)
			var rel = _rel_for(u["faction"])
			if oh.has_method("set_enemy_mirror"):
				oh.set_enemy_mirror(rel == "hostile")
			if oh.has_method("set_tonnage_overlays"):
				var ov = _tonnage_overlay_set(rel)
				oh.set_tonnage_overlays(ov.get("bg"), ov.get("badge"))
			if oh.has_method("set_faction_badge"):
				oh.set_faction_badge(BoardTypes.relation_color(rel))
			if cam and cam.cam and oh.has_method("face_camera"):
				oh.face_camera(cam.cam, u["pos"])
		if cam.follow_unit_id == u["id"]:
			cam.update_follow_pos(u["pos"])
			# #region agent log
			if Engine.get_process_frames() % 30 == 0 and cam.cam:
				_agent_dbg("A3", "board_root.follow", "follow_center", {
					"unit": u["id"], "ux": u["pos"].x, "uz": u["pos"].z,
					"fx": cam._look_smooth.x, "fz": cam._look_smooth.z,
					"cdist": cam.cam.global_position.distance_to(u["pos"]),
					"runId": "post-fix"
				})
			# #endregion

func _separate_stacked_units(delta: float) -> void:
	# Same-cell: maximize pairwise distance; include invisible incoming reserves as soft anchors
	var by_cell: Dictionary = {}
	for u in units:
		if not u.get("alive", false):
			continue
		var keys: Array = []
		if int(u["phase"]) == BoardTypes.MovePhase.IDLE:
			keys.append("%s:%d" % [u["sys"], int(u["cell"])])
		if u.has("reserve_sys") and u.has("reserve_cell"):
			keys.append("%s:%d" % [str(u["reserve_sys"]), int(u["reserve_cell"])])
		for key in keys:
			if not by_cell.has(key):
				by_cell[key] = []
			var already = false
			for ex in by_cell[key]:
				if str(ex.get("id", "")) == str(u.get("id", "")):
					already = true
					break
			if not already:
				by_cell[key].append(u)
	for key in by_cell.keys():
		var group: Array = by_cell[key]
		if group.size() < 2:
			continue
		var parts = key.split(":")
		var sys_k = parts[0]
		var cell_k = int(parts[1])
		var target = 4.5 + float(group.size()) * 0.65
		for i in group.size():
			var a: Dictionary = group[i]
			# Only push units physically in this cell (idle) or landing into it
			var ph = int(a["phase"])
			var in_here = (ph == BoardTypes.MovePhase.IDLE and str(a["sys"]) == sys_k and int(a["cell"]) == cell_k) \
				or (ph == BoardTypes.MovePhase.LANDING and str(a["sys"]) == sys_k and int(a["cell"]) == cell_k)
			if not in_here:
				continue
			var force = Vector3.ZERO
			var pa: Vector3 = a["pos"]
			for j in group.size():
				if i == j:
					continue
				var b: Dictionary = group[j]
				var pb: Vector3 = b.get("land_pos", b["pos"]) if b.has("land_pos") else b["pos"]
				if int(b["phase"]) == BoardTypes.MovePhase.IDLE:
					pb = b["pos"]
				var d = Vector3(pa.x - pb.x, 0, pa.z - pb.z)
				var dist = d.length()
				if dist < 0.001:
					d = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
					dist = 0.001
				var push_mag = (target - dist) / target
				## Soft: incoming reserves only push scaled by their reserve_weight.
				var rw_b: float = 1.0
				if int(b.get("phase", 0)) != BoardTypes.MovePhase.IDLE:
					rw_b = clampf(float(b.get("reserve_weight", 0.0)), 0.0, 1.0)
				if push_mag > 0.0:
					force += d.normalized() * push_mag * rw_b
			if force.length_squared() > 0.0001:
				var kpush = clampf(delta * 10.0, 0.0, 1.0)
				var np = pa + force.normalized() * (force.length() * 2.8 * kpush)
				np = _clamp_pos_to_cell(sys_k, cell_k, np)
				a["pos"] = np
				a["rest_pos"] = Vector3(np.x, BoardTypes.UNIT_Y, np.z)


func _rebuild_guard_curtains() -> void:
	## Vertical fade curtains on cell radial edges: blue field / yellow link / aurora both.
	if _curtain_root == null:
		_curtain_root = Node3D.new()
		_curtain_root.name = "GuardCurtains"
		add_child(_curtain_root)
	for c in _curtain_root.get_children():
		c.queue_free()
	if map == null:
		return
	var now_t: float = float(Time.get_ticks_msec()) * 0.001
	var cell_flags: Dictionary = {}
	for u in units:
		if not u.get("alive", false):
			continue
		var g: Dictionary = u.get("guard", {})
		var key = "%s:%d" % [str(u["sys"]), int(u["cell"])]
		if not cell_flags.has(key):
			cell_flags[key] = {"field": false, "link": false, "sys": str(u["sys"]), "cell": int(u["cell"])}
		if g.get("field_on", false):
			cell_flags[key]["field"] = true
		if g.get("link_on", false):
			cell_flags[key]["link"] = true
	for key in cell_flags.keys():
		var fl: Dictionary = cell_flags[key]
		var field_on: bool = fl["field"]
		var link_on: bool = fl["link"]
		if not field_on and not link_on:
			continue
		var sid: String = fl["sys"]
		var ci: int = fl["cell"]
		if not map.systems.has(sid):
			continue
		var sys: Dictionary = map.systems[sid]
		var cell: Dictionary = sys["cells"][ci]
		var sc: float = float(sys.get("visual_scale", sys.get("scale", 1.0)))
		var inner: float = float(map.layout.get("ring_inner", 12)) * sc
		var outer: float = float(map.layout.get("ring_outer", 26)) * sc
		var a0: float = float(cell["angle_center"]) - float(cell["angle_half"])
		var a1: float = float(cell["angle_center"]) + float(cell["angle_half"])
		var mode := "blue" if field_on and not link_on else ("yellow" if link_on and not field_on else "aurora")
		_add_edge_curtain(sys["center"], a0, inner, outer, mode, now_t, 0.0)
		_add_edge_curtain(sys["center"], a1, inner, outer, mode, now_t, 1.0)


func _add_edge_curtain(center: Vector3, ang: float, inner: float, outer: float, mode: String, now_t: float, edge_u: float) -> void:
	var n := 8
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h0 := -2.5
	var h1 := 6.5
	var y_steps := 6
	for i in n:
		var r0 = lerpf(inner, outer, float(i) / float(n))
		var r1 = lerpf(inner, outer, float(i + 1) / float(n))
		for yi in y_steps:
			var y0 = lerpf(h0, h1, float(yi) / float(y_steps))
			var y1 = lerpf(h0, h1, float(yi + 1) / float(y_steps))
			var yn = (float(yi) + 0.5) / float(y_steps)
			var fade = sin(yn * PI)
			var col: Color
			if mode == "blue":
				col = Color(0.25, 0.55, 1.0, 0.22 * fade)
			elif mode == "yellow":
				col = Color(1.0, 0.85, 0.2, 0.22 * fade)
			else:
				col = _aurora_color(fposmod(now_t / 8.0 + yn * 0.35 + edge_u * 0.2, 1.0))
				col.a = 0.28 * fade
			var a = center + Vector3(sin(ang) * r0, y0, -cos(ang) * r0)
			var b = center + Vector3(sin(ang) * r0, y1, -cos(ang) * r0)
			var c = center + Vector3(sin(ang) * r1, y0, -cos(ang) * r1)
			var d = center + Vector3(sin(ang) * r1, y1, -cos(ang) * r1)
			st.set_color(col)
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(d)
			st.add_vertex(c)
	var mi = MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	_curtain_root.add_child(mi)


func _aurora_color(p: float) -> Color:
	var stops: Array = [
		Color(0.15, 0.95, 0.35),
		Color(0.20, 0.90, 0.85),
		Color(0.25, 0.45, 1.0),
		Color(0.55, 0.25, 0.95),
		Color(0.15, 0.95, 0.35),
	]
	var seg = clampf(p, 0.0, 0.999) * 4.0
	var i = int(seg)
	var f = seg - float(i)
	return (stops[i] as Color).lerp(stops[i + 1] as Color, f)


func _reanchor_idle_units() -> void:
	# After angle/scale changes, keep idle ships on claim slots (reserves count)
	for u in units:
		if not u.get("alive", false):
			continue
		if int(u["phase"]) != BoardTypes.MovePhase.IDLE:
			continue
		var sys = str(u["sys"])
		var cell = int(u["cell"])
		var claimants = _cell_claimant_ids(sys, cell)
		var slot = claimants.find(str(u["id"]))
		if slot < 0:
			slot = 0
		u["rest_pos"] = _cell_slot_pos(sys, cell, slot, maxi(claimants.size(), 1))
		u["pos"] = u["rest_pos"]

func _cell_slot_pos(sys: String, cell: int, slot: int, total: int) -> Vector3:
	var base = _cell_pos_visual(sys, cell, BoardTypes.UNIT_Y)
	if total <= 1:
		return base
	var sysd: Dictionary = map.systems[sys]
	var center: Vector3 = sysd["center"]
	var radial = Vector3(base.x - center.x, 0, base.z - center.z)
	var tang = Vector3(-radial.z, 0, radial.x).normalized()
	if tang.length() < 0.1:
		tang = Vector3(1, 0, 0)
	var rad_n = radial.normalized()
	var spread = 3.2
	var t = float(slot) - float(total - 1) * 0.5
	return base + tang * (t * spread) + rad_n * ((slot % 2) * 1.2)

func _cell_claimant_ids(sys: String, cell: int) -> Array:
	var ids: Array = []
	for u in units:
		if not u.get("alive", false):
			continue
		var uid = str(u["id"])
		var ph = int(u["phase"])
		if ph == BoardTypes.MovePhase.IDLE and str(u["sys"]) == sys and int(u["cell"]) == cell:
			if not ids.has(uid):
				ids.append(uid)
		elif str(u.get("reserve_sys", "")) == sys and int(u.get("reserve_cell", -999)) == cell:
			if not ids.has(uid):
				ids.append(uid)
	ids.sort()
	return ids

func _cell_claim_count(sys: String, cell: int) -> int:
	return maxi(_cell_claimant_ids(sys, cell).size(), 1)

func _assign_reserve(u: Dictionary) -> void:
	var sys = str(u.get("to_sys", u["sys"]))
	var cell = int(u["to_cell"])
	u["reserve_sys"] = sys
	u["reserve_cell"] = cell
	var claimants = _cell_claimant_ids(sys, cell)
	var uid = str(u["id"])
	if not claimants.has(uid):
		claimants.append(uid)
		claimants.sort()
	var slot = claimants.find(uid)
	u["reserve_slot"] = slot
	var land = _cell_slot_pos(sys, cell, slot, maxi(claimants.size(), 1))
	u["land_pos"] = land
	# Intra hops: aim travel at reserved slot; jumps keep gate as to_pos
	if u.get("step_kind") != "jump":
		u["to_pos"] = land

func _clear_reserve(u: Dictionary) -> void:
	u.erase("reserve_sys")
	u.erase("reserve_cell")
	u.erase("reserve_slot")
	u.erase("land_pos")

func _sync_start_blocked(u: Dictionary) -> bool:
	if not sync_move_enabled:
		return false
	var gid = int(u.get("sync_gid", 0))
	if gid <= 0:
		return false
	for o in units:
		if int(o.get("sync_gid", 0)) != gid:
			continue
		if not o.get("alive", false):
			continue
		var ph = int(o["phase"])
		if ph == BoardTypes.MovePhase.PREP or ph == BoardTypes.MovePhase.INVULN or ph == BoardTypes.MovePhase.LANDING:
			return true
	return false

func _sync_max_step_duration(gid: int, kind: String, at_least: float) -> float:
	var mx = at_least
	for o in units:
		if int(o.get("sync_gid", 0)) != gid:
			continue
		if not o.get("alive", false):
			continue
		var next_kind = kind
		if not o["path"].is_empty():
			next_kind = str(o["path"][0].get("kind", kind))
		elif int(o["phase"]) != BoardTypes.MovePhase.IDLE:
			next_kind = str(o.get("step_kind", kind))
		elif o["path"].is_empty() and int(o["phase"]) == BoardTypes.MovePhase.IDLE:
			continue
		if next_kind == "jump":
			mx = maxf(mx, float(o.get("jump_s", 3.0)))
		else:
			mx = maxf(mx, float(o.get("move_s", 2.0)))
	return mx

func _sync_max_prep(gid: int, at_least: float) -> float:
	var mx = at_least
	for o in units:
		if int(o.get("sync_gid", 0)) != gid:
			continue
		if not o.get("alive", false):
			continue
		if o["path"].is_empty() and int(o["phase"]) == BoardTypes.MovePhase.IDLE:
			continue
		mx = maxf(mx, BoardTypes.align_prep_s(float(o.get("inertia", 1.0)), float(o.get("mass", 1e6))))
	return mx

func _check_defeat() -> void:
	for fac in [1, 2]:
		var has_home = false
		var hiding = false
		for p in pilots:
			if int(p["faction"]) != fac:
				continue
			if str(p.get("home_station", "")) != "":
				has_home = true
			if p.get("in_station", false) and str(p.get("current_station", "")) != "":
				hiding = true
		var alive = 0
		for u in units:
			if int(u.get("faction", 0)) == fac and u.get("alive", false):
				alive += 1
		# Hiding in any station (even hostile-held) prevents defeat
		if not has_home and alive == 0 and not hiding:
			match_over = true
			match_msg = "Faction %d defeated" % fac
			print(match_msg)

# --- Input ---
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or (event is InputEventMouseMotion and dragging):
		if _mouse_over_blocking_hud(_event_pos(event)):
			return
		if event is InputEventMouseMotion and dragging:
			if _event_pos(event).distance_to(drag_start) >= BoardTypes.BOX_DRAG_PX:
				box_selecting = true
		if event is InputEventMouseButton:
			_handle_mouse_button(event as InputEventMouseButton)
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_handle_key(event as InputEventKey)

func _event_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).position
	return get_viewport().get_mouse_position()

func _mouse_over_blocking_hud(pos: Vector2) -> bool:
	# Whole left column (prod btn + list + sync toggle) must not be stolen by board _input
	if left_col:
		var lc = Rect2(left_col.global_position, left_col.size)
		if lc.has_point(pos):
			return true
	if left_scroll:
		var lr = Rect2(left_scroll.global_position, left_scroll.size)
		if lr.has_point(pos):
			return true
	if all_prod_btn:
		var pr = Rect2(all_prod_btn.global_position, all_prod_btn.size)
		if pr.has_point(pos):
			return true
	if sync_move_btn:
		var sr = Rect2(sync_move_btn.global_position, sync_move_btn.size)
		if sr.has_point(pos):
			return true
	if detail and detail.visible:
		var dr = Rect2(detail.global_position, detail.size)
		if dr.has_point(pos):
			return true
	return false

func _handle_key(e: InputEventKey) -> void:
	if e.ctrl_pressed and e.keycode >= KEY_0 and e.keycode <= KEY_9:
		var g = e.keycode - KEY_0
		control_groups[g] = selection.filter(func(id): return _unit_by_id(id).get("faction", 0) == viewer_faction)
		return
	if not e.ctrl_pressed and e.keycode >= KEY_0 and e.keycode <= KEY_9:
		var g2 = e.keycode - KEY_0
		selection = control_groups.get(g2, []).duplicate()
		return

func _ensure_box_overlay() -> void:
	if _box_overlay != null:
		return
	if hud == null:
		return
	_box_overlay = ColorRect.new()
	_box_overlay.color = Color(0.2, 0.85, 0.4, 0.18)
	_box_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_overlay.visible = false
	# ColorRect has no style; draw via outline child
	var outline = ReferenceRect.new()
	outline.name = "Outline"
	outline.border_color = Color(0.3, 1.0, 0.45, 0.9)
	outline.border_width = 2.0
	outline.editor_only = false
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box_overlay.add_child(outline)
	hud.add_child(_box_overlay)

func _update_box_overlay() -> void:
	_ensure_box_overlay()
	if _box_overlay == null:
		return
	if dragging and box_selecting:
		var a = drag_start
		var b = get_viewport().get_mouse_position()
		var r = Rect2(a, b - a).abs()
		_box_overlay.position = r.position
		_box_overlay.size = r.size.max(Vector2(2, 2))
		_box_overlay.visible = true
	else:
		_box_overlay.visible = false

func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	# LMB: click=select / drag=box-select | RMB: click=move order (never box-clear)
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			drag_start = mb.position
			dragging = true
			box_selecting = false
		else:
			var dist = mb.position.distance_to(drag_start)
			dragging = false
			# #region agent log
			_agent_dbg("H1", "board_root._handle_mouse_button", "LMB release", {
				"dist": dist, "box": box_selecting, "sel": selection.duplicate(), "pos": [mb.position.x, mb.position.y]
			})
			# #endregion
			if box_selecting or dist >= BoardTypes.BOX_DRAG_PX:
				_box_select(drag_start, mb.position)
			else:
				_left_click(mb.position)
			box_selecting = false
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			return
		# #region agent log
		_agent_dbg("H2", "board_root._handle_mouse_button", "RMB release", {
			"sel": selection.duplicate(), "pos": [mb.position.x, mb.position.y]
		})
		# #endregion
		_right_click(mb.position)

func _right_click(screen_pos: Vector2) -> void:
	var cell = _pick_cell(screen_pos)
	var uhit = _pick_unit(screen_pos)
	# #region agent log
	_agent_dbg("H2", "board_root._right_click", "right_click", {
		"cell": cell,
		"unit_hit": str(uhit.get("id", "")),
		"sel": selection.duplicate(),
		"runId": "post-fix"
	})
	# #endregion
	if not uhit.is_empty():
		selection = [uhit["id"]]
		_detail_dirty = true
		_update_detail()
		if int(uhit["faction"]) == viewer_faction:
			_open_unit_menu(uhit, screen_pos)
		return
	if not selection.is_empty() and not cell.is_empty():
		var batch_gid := 0
		if sync_move_enabled:
			_sync_gid_next += 1
			batch_gid = _sync_gid_next
		for id in selection:
			var un = _unit_by_id(id)
			if un.is_empty() or int(un["faction"]) != viewer_faction:
				continue
			if not un.get("alive", false):
				continue
			if batch_gid > 0:
				un["sync_gid"] = batch_gid
			else:
				un.erase("sync_gid")
			_order_player_move(un, cell["sys"], int(cell["cell"]))
		_detail_dirty = true
		return

func _order_player_move(u: Dictionary, to_sys: String, to_cell: int) -> void:
	# RTS-style: show dest line immediately; pathfind deferred (avoids hitch on click)
	u["order_dest_sys"] = to_sys
	u["order_dest_cell"] = to_cell
	_ensure_move_line(u, to_sys, to_cell)
	# Coalesce: keep only latest order per unit
	var uid = str(u["id"])
	var filtered: Array = []
	for o in _order_queue:
		if str(o.get("id", "")) != uid:
			filtered.append(o)
	filtered.append({"id": uid, "sys": to_sys, "cell": to_cell})
	_order_queue = filtered
	# #region agent log
	_agent_dbg("P1", "board_root._order_player_move", "order_queued", {
		"unit": uid, "to": [to_sys, to_cell], "q": _order_queue.size(), "runId": "post-fix"
	})
	# #endregion

func _drain_order_queue(budget: int) -> void:
	var n = mini(budget, _order_queue.size())
	for _i in n:
		var o: Dictionary = _order_queue.pop_front()
		var u = _unit_by_id(str(o.get("id", "")))
		if u.is_empty() or not u.get("alive", false):
			continue
		_pathfind_apply(u, str(o["sys"]), int(o["cell"]))

func _pathfind_apply(u: Dictionary, to_sys: String, to_cell: int) -> void:
	# Same-system: O(1) path — skip graph BFS cost
	var prep = BoardTypes.align_prep_s(u["inertia"], u["mass"])
	if str(u["sys"]) == to_sys:
		if int(u["cell"]) == to_cell:
			u["path"] = []
		else:
			u["path"] = [{
				"sys": to_sys, "from": int(u["cell"]), "to": to_cell,
				"kind": "intra",
				"duration": prep + float(u["move_s"]) + float(u["landing_s"])
			}]
	else:
		u["path"] = BoardPlayerNav.find_path(
			map, data.diplomacy, u["faction"],
			u["sys"], u["cell"], to_sys, to_cell,
			prep, u["move_s"], u["landing_s"], u["jump_s"]
		)
	# #region agent log
	_agent_dbg("P1", "board_root._pathfind_apply", "path_ready", {
		"unit": u["id"], "path_len": u["path"].size(), "runId": "post-fix"
	})
	# #endregion
	admin.request("board.move", {"unit": u["id"], "path": u["path"]})

func _ensure_move_line(u: Dictionary, to_sys: String, to_cell: int) -> void:
	var uid = str(u["id"])
	var line: MeshInstance3D = _move_lines.get(uid) as MeshInstance3D
	if line == null:
		line = MeshInstance3D.new()
		line.name = "OrderLine_%s" % uid
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.35, 1.0, 0.45, 0.12)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		line.material_override = mat
		add_child(line)
		_move_lines[uid] = line
	var dest = _cell_pos_visual(to_sys, to_cell, BoardTypes.UNIT_Y)
	_set_line_mesh(line, u["pos"], dest)

func _set_line_mesh(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side = (b - a).cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3(0.15, 0, 0)
	else:
		side = side.normalized() * 0.12
	var a0 = a + Vector3(0, 0.2, 0)
	var b0 = b + Vector3(0, 0.2, 0)
	var col = Color(0.35, 1.0, 0.45, 0.12)
	st.set_color(col); st.add_vertex(a0 + side)
	st.set_color(col); st.add_vertex(b0 + side)
	st.set_color(col); st.add_vertex(b0 - side)
	st.set_color(col); st.add_vertex(a0 + side)
	st.set_color(col); st.add_vertex(b0 - side)
	st.set_color(col); st.add_vertex(a0 - side)
	mi.mesh = st.commit()

func _clear_move_line(uid: String) -> void:
	if _move_lines.has(uid):
		var mi = _move_lines[uid]
		if is_instance_valid(mi):
			mi.queue_free()
		_move_lines.erase(uid)

func _box_select(a: Vector2, b: Vector2) -> void:
	var r = Rect2(a, b - a).abs()
	if r.size.x < 2.0 and r.size.y < 2.0:
		return
	var found: Array = []
	if cam == null or cam.cam == null:
		return
	for u in units:
		if not u.get("alive", false) or int(u["faction"]) != viewer_faction:
			continue
		var world_pos: Vector3 = u["pos"]
		if unit_nodes.has(u["id"]):
			world_pos = unit_nodes[u["id"]].global_position
		if cam.cam.is_position_behind(world_pos):
			continue
		var hit = false
		if r.has_point(cam.cam.unproject_position(world_pos)):
			hit = true
		else:
			for off in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5), Vector3(0, 1.5, 0)]:
				var p2 = world_pos + off
				if cam.cam.is_position_behind(p2):
					continue
				if r.has_point(cam.cam.unproject_position(p2)):
					hit = true
					break
		if hit:
			found.append(u["id"])
	# Only replace selection when the box actually caught units
	if not found.is_empty():
		selection = found
		_detail_dirty = true
		_update_detail()

func _left_click(screen_pos: Vector2) -> void:
	var u = _pick_unit(screen_pos)
	var cell = _pick_cell(screen_pos)
	# #region agent log
	_agent_dbg("H1", "board_root._left_click", "left_click", {
		"unit": str(u.get("id", "")),
		"cell": cell,
		"sel_before": selection.duplicate(),
		"runId": "post-fix"
	})
	# #endregion
	if u.is_empty():
		if not selection.is_empty() and not cell.is_empty():
			var batch_gid2 := 0
			if sync_move_enabled:
				_sync_gid_next += 1
				batch_gid2 = _sync_gid_next
			for id in selection:
				var un = _unit_by_id(id)
				if un.is_empty() or int(un["faction"]) != viewer_faction:
					continue
				if not un.get("alive", false):
					continue
				if batch_gid2 > 0:
					un["sync_gid"] = batch_gid2
				else:
					un.erase("sync_gid")
				_order_player_move(un, cell["sys"], int(cell["cell"]))
			_detail_dirty = true
			return
		selection.clear()
		_detail_dirty = true
		_update_detail()
		return
	selection = [u["id"]]
	_detail_dirty = true
	_update_detail()

func _open_unit_menu(u: Dictionary, screen_pos: Vector2) -> void:
	popup.clear()
	popup.set_meta("pilot", "")
	if int(u["faction"]) == viewer_faction:
		popup.add_item("泡罩 开/关", 1)
		popup.add_item("停止", 2)
		popup.add_item("视角跟随" if cam.follow_unit_id != u["id"] else "取消跟随", 3)
		var g: Dictionary = u.get("guard", {})
		var fa = g.get("field_auto_on", true)
		popup.add_item("立场自动：%s" % ("开" if fa else "关"), 10)
		popup.set_item_disabled(popup.get_item_index(10), not g.get("field_fitted", false))
		var la = g.get("link_auto_on", true)
		popup.add_item("链接自动：%s" % ("开" if la else "关"), 11)
		popup.set_item_disabled(popup.get_item_index(11), not g.get("link_fitted", false))
		var ia = u.get("implant", {}).get("auto_on", true)
		popup.add_item("植入自动：%s" % ("开" if ia else "关"), 12)
		popup.set_item_disabled(popup.get_item_index(12), str(u.get("implant", {}).get("ref", "")) == "")
		var can_dock = _can_dock(u)
		popup.add_item("进站", 4)
		popup.set_item_disabled(popup.get_item_index(4), not can_dock)
	else:
		popup.add_item("视角跟随" if cam.follow_unit_id != u["id"] else "取消跟随", 3)
		popup.add_item("立场自动", 10)
		popup.set_item_disabled(popup.get_item_index(10), true)
		popup.add_item("链接自动", 11)
		popup.set_item_disabled(popup.get_item_index(11), true)
		popup.add_item("植入自动", 12)
		popup.set_item_disabled(popup.get_item_index(12), true)
	popup.set_meta("unit", u["id"])
	popup.position = Vector2i(screen_pos)
	popup.popup()

func _can_dock(u: Dictionary) -> bool:
	if int(u["phase"]) != BoardTypes.MovePhase.IDLE:
		return false
	var c: Dictionary = map.systems[u["sys"]]["cells"][u["cell"]]
	if int(c["kind"]) != BoardTypes.CellKind.STATION:
		return false
	var owner_fac = int(c["owner"])
	if owner_fac == 0:
		return false
	var rels: Dictionary = data.diplomacy.get("relations", {}).get(str(u["faction"]), {})
	var rel = str(rels.get(str(owner_fac), "hostile"))
	return rel == "self" or rel == "ally"

func _on_any_popup(id: int) -> void:
	var pid: String = str(popup.get_meta("pilot", ""))
	if pid != "":
		_on_pilot_popup(id)
		return
	var uid: String = str(popup.get_meta("unit", ""))
	var u = _unit_by_id(uid)
	if u.is_empty():
		return
	match id:
		1:
			if int(u["phase"]) == BoardTypes.MovePhase.LANDING or int(u["phase"]) == BoardTypes.MovePhase.INVULN:
				return
			u["bubble_on"] = not u.get("bubble_on", false)
			if not u["bubble_on"]:
				map.systems[u["sys"]]["cells"][u["cell"]]["bubble"] = false
		2:
			u["path"].clear()
			if int(u["phase"]) == BoardTypes.MovePhase.PREP:
				u["phase"] = BoardTypes.MovePhase.IDLE
		3:
			if cam.follow_unit_id == u["id"]:
				cam.clear_follow_keep_look()
			else:
				cam.set_follow(u["id"])
		4:
			_dock_unit(u)
		10:
			if u.has("guard") and u["guard"].get("field_fitted", false):
				u["guard"]["field_auto_on"] = not u["guard"].get("field_auto_on", true)
				_tick_guard_reopen(u)
		11:
			if u.has("guard") and u["guard"].get("link_fitted", false):
				u["guard"]["link_auto_on"] = not u["guard"].get("link_auto_on", true)
				_tick_guard_reopen(u)
		12:
			if u.has("implant") and str(u.get("implant", {}).get("ref", "")) != "":
				u["implant"]["auto_on"] = not u.get("implant", {}).get("auto_on", true)

func _dock_unit(u: Dictionary) -> void:
	if not _can_dock(u):
		return
	var p = _pilot_by_id(u["pilot_id"])
	if p.is_empty():
		return
	p["current_station"] = u["sys"]
	p["in_station"] = true
	pilots_sys.dock_ship(p, u["inst"])
	u["alive"] = false
	p["unit_id"] = ""
	if unit_nodes.has(u["id"]):
		unit_nodes[u["id"]].visible = false
		var oh2 = unit_nodes[u["id"]].get_node_or_null("Overhead")
		if oh2 and oh2.has_method("set_alive_view"):
			oh2.set_alive_view(false)
	selection.erase(u["id"])

func _on_left_selected(index: int) -> void:
	var pid: String = str(left_list.get_item_metadata(index))
	var p = _pilot_by_id(pid)
	if p.is_empty():
		return
	var uid = str(p.get("unit_id", ""))
	if uid != "":
		selection = [uid]
	_update_detail()

func _on_left_clicked(index: int, _at: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		_on_left_selected(index)
		return
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var pid: String = str(left_list.get_item_metadata(index))
	var p = _pilot_by_id(pid)
	if p.is_empty():
		return
	_open_pilot_menu(p, get_viewport().get_mouse_position())

func _open_pilot_menu(p: Dictionary, screen_pos: Vector2) -> void:
	popup.clear()
	popup.set_meta("pilot", p["id"])
	popup.set_meta("unit", "")
	_clear_popup_children(popup)
	var launch_sm = _make_submenu(popup, "出航")
	_fill_launch_submenu(launch_sm, p)
	var scrap_sm = _make_submenu(popup, "拆解舰船")
	_fill_scrap_submenu(scrap_sm, p)
	var build_sm = _make_submenu(popup, "制造")
	_fill_build_submenu(build_sm, p)
	var assign_sm = _make_submenu(popup, "分配资源点")
	_fill_assign_submenu(assign_sm, p)
	var u = _unit_by_id(str(p.get("unit_id", "")))
	var can_enter = u and _can_dock(u)
	popup.add_item("进站", 4)
	popup.set_item_disabled(popup.get_item_index(4), not can_enter)
	popup.add_item("设置母港…", 400)
	popup.set_item_disabled(popup.get_item_index(400), not p.get("in_station", false))
	if u and not u.is_empty():
		popup.add_item("视角跟随" if cam.follow_unit_id != str(u["id"]) else "取消跟随", 3)
	popup.position = Vector2i(screen_pos)
	popup.popup()

func _clear_popup_children(pm: PopupMenu) -> void:
	for c in pm.get_children():
		if c is PopupMenu:
			pm.remove_child(c)
			c.queue_free()

func _make_submenu(parent_pm: PopupMenu, title: String) -> PopupMenu:
	var sm = PopupMenu.new()
	sm.name = "Sub_%s" % title.replace(" ", "_")
	parent_pm.add_child(sm)
	sm.hide_on_item_selection = true
	parent_pm.add_submenu_node_item(title, sm)
	# also bind by index for engines that need set_item_submenu_node
	var idx = parent_pm.item_count - 1
	if parent_pm.has_method("set_item_submenu_node"):
		parent_pm.set_item_submenu_node(idx, sm)
	return sm

func _fill_launch_submenu(sm: PopupMenu, p: Dictionary) -> void:
	sm.clear()
	sm.set_meta("pilot", p["id"])
	if not sm.id_pressed.is_connected(_on_pilot_popup):
		sm.id_pressed.connect(_on_pilot_popup)
	var counts = pilots_sys.storage_count_by_model(p)
	var i = 0
	for sid in counts.keys():
		var id = 1000 + i
		var def: Dictionary = data.ship_def(sid)
		sm.add_item("%s x%d" % [def.get("name", sid), counts[sid]], id)
		sm.set_meta("launch_%d" % id, sid)
		popup.set_meta("launch_%d" % id, sid)
		i += 1
	if counts.is_empty():
		sm.add_item("（空）", 999)
		sm.set_item_disabled(0, true)

func _fill_scrap_submenu(sm: PopupMenu, p: Dictionary) -> void:
	sm.clear()
	sm.set_meta("pilot", p["id"])
	if not sm.id_pressed.is_connected(_on_pilot_popup):
		sm.id_pressed.connect(_on_pilot_popup)
	var counts = pilots_sys.storage_count_by_model(p)
	var i = 0
	for sid in counts.keys():
		var id = 2000 + i
		var def: Dictionary = data.ship_def(sid)
		sm.add_item("%s x%d" % [def.get("name", sid), counts[sid]], id)
		sm.set_meta("destroy_%d" % id, sid)
		popup.set_meta("destroy_%d" % id, sid)
		i += 1
	if counts.is_empty():
		sm.add_item("（空）", 2999)
		sm.set_item_disabled(0, true)

func _tonnage_zh(ton: String) -> String:
	match ton:
		"frigate":
			return "护卫舰"
		"destroyer":
			return "驱逐舰"
		"cruiser":
			return "巡洋舰"
		"battlecruiser":
			return "战列巡洋舰"
		"battleship":
			return "战列舰"
		_:
			return ton

func _fill_build_submenu(sm: PopupMenu, p: Dictionary) -> void:
	sm.clear()
	sm.set_meta("pilot", p["id"])
	var tons = ["frigate", "destroyer", "cruiser", "battlecruiser", "battleship"]
	for i in tons.size():
		var ton: String = tons[i]
		var ton_sm = PopupMenu.new()
		sm.add_child(ton_sm)
		var auto: String = str(p["auto_build"].get(ton, ""))
		var title = _tonnage_zh(ton)
		if auto == "":
			title += " [无]"
		else:
			title += " [%s]" % data.ship_def(auto).get("name", auto)
		sm.add_submenu_node_item(title, ton_sm)
		if sm.has_method("set_item_submenu_node"):
			sm.set_item_submenu_node(sm.item_count - 1, ton_sm)
		ton_sm.set_meta("pilot", p["id"])
		if not ton_sm.id_pressed.is_connected(_on_pilot_popup):
			ton_sm.id_pressed.connect(_on_pilot_popup)
		var base = 4100 + i * 50
		ton_sm.add_item("无", base)
		ton_sm.set_meta("autobuild_%d" % base, "")
		ton_sm.set_meta("autobuild_ton_%d" % base, ton)
		popup.set_meta("autobuild_%d" % base, "")
		popup.set_meta("autobuild_ton_%d" % base, ton)
		var j = 1
		for sid in data.ships.keys():
			var def: Dictionary = data.ships[sid]
			if str(def.get("tonnage")) != ton:
				continue
			var id = base + j
			ton_sm.add_item(str(def.get("name", sid)), id)
			ton_sm.set_meta("autobuild_%d" % id, sid)
			ton_sm.set_meta("autobuild_ton_%d" % id, ton)
			popup.set_meta("autobuild_%d" % id, sid)
			popup.set_meta("autobuild_ton_%d" % id, ton)
			j += 1

func _fill_assign_submenu(sm: PopupMenu, p: Dictionary) -> void:
	# number spinner as submenu items: -1 / show count / +1  (PopupMenu cannot host LineEdit; arrows via items)
	sm.clear()
	sm.set_meta("pilot", p["id"])
	if not sm.id_pressed.is_connected(_on_assign_step):
		sm.id_pressed.connect(_on_assign_step)
	var held = _pilot_resource_count(str(p["id"]))
	var pool = _faction_unassigned_resources(int(p["faction"]))
	sm.add_item("-", 6101)
	sm.add_item("已分配 %d  （空闲 %d）" % [held, pool], 6100)
	sm.set_item_disabled(sm.get_item_index(6100), true)
	sm.add_item("+", 6102)
	sm.add_item("打开分配面板…", 6103)

func _faction_unassigned_resources(fac: int) -> int:
	var n = 0
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c.get("kind", -1)) != BoardTypes.CellKind.RESOURCE:
				continue
			if int(c.get("owner", 0)) != fac:
				continue
			if str(c.get("assigned_pilot_id", "")) == "":
				n += 1
	return n

func _on_assign_step(id: int) -> void:
	var pid = str(popup.get_meta("pilot", ""))
	var p = _pilot_by_id(pid)
	if p.is_empty():
		return
	var held = _pilot_resource_count(pid)
	var pool = _faction_unassigned_resources(int(p["faction"]))
	var target = held
	if id == 6101:
		target = maxi(0, held - 1)
	elif id == 6102:
		target = mini(held + pool, held + 1)
	elif id == 6103:
		_open_assign_panel(p)
		return
	_set_pilot_resource_count(p, target)
	_rebuild_hud_list()
	if starmap_view:
		starmap_view.rebuild()

func _open_assign_panel(p: Dictionary) -> void:
	var panel = PopupPanel.new()
	panel.name = "AssignPanel"
	add_child(panel)
	var hb = HBoxContainer.new()
	panel.add_child(hb)
	var minus = Button.new()
	minus.text = "<"
	var edit = LineEdit.new()
	edit.custom_minimum_size = Vector2(64, 0)
	edit.text = str(_pilot_resource_count(str(p["id"])))
	var plus = Button.new()
	plus.text = ">"
	var ok = Button.new()
	ok.text = "OK"
	hb.add_child(minus)
	hb.add_child(edit)
	hb.add_child(plus)
	hb.add_child(ok)
	minus.pressed.connect(func():
		var v = int(edit.text) - 1
		edit.text = str(maxi(0, v))
	)
	plus.pressed.connect(func():
		var held = _pilot_resource_count(str(p["id"]))
		var pool = _faction_unassigned_resources(int(p["faction"]))
		var v = int(edit.text) + 1
		edit.text = str(mini(held + pool, v))
	)
	ok.pressed.connect(func():
		_set_pilot_resource_count(p, int(edit.text))
		_rebuild_hud_list()
		if starmap_view:
			starmap_view.rebuild()
		panel.queue_free()
	)
	panel.popup_centered(Vector2i(220, 48))

func _set_pilot_resource_count(p: Dictionary, target: int) -> void:
	var pid = str(p["id"])
	var fac = int(p["faction"])
	var held_cells: Array = []
	var free_cells: Array = []
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c.get("kind", -1)) != BoardTypes.CellKind.RESOURCE:
				continue
			if int(c.get("owner", 0)) != fac:
				continue
			if str(c.get("assigned_pilot_id", "")) == pid:
				held_cells.append({"sys": sid, "cell": c})
			elif str(c.get("assigned_pilot_id", "")) == "":
				free_cells.append({"sys": sid, "cell": c})
	target = clampi(target, 0, held_cells.size() + free_cells.size())
	while held_cells.size() > target:
		var i = rng.randi() % held_cells.size()
		var e = held_cells[i]
		e["cell"]["assigned_pilot_id"] = ""
		held_cells.remove_at(i)
	while held_cells.size() < target and free_cells.size() > 0:
		var j = rng.randi() % free_cells.size()
		var e2 = free_cells[j]
		e2["cell"]["assigned_pilot_id"] = pid
		e2["cell"]["last_assignee"] = pid
		held_cells.append(e2)
		free_cells.remove_at(j)
	admin.request("pilot.assign_resource", {"pilot": pid, "count": target})

func _on_pilot_popup(id: int) -> void:
	var pid: String = str(popup.get_meta("pilot", ""))
	var p = _pilot_by_id(pid)
	if p.is_empty():
		return
	if id == 100:
		_popup_launch_models(p)
	elif id == 200:
		_popup_destroy_models(p)
	elif id == 300:
		_popup_build_menu(p)
	elif id == 500:
		_popup_assign_resources(p)
	elif id == 3:
		var uf = _unit_by_id(str(p.get("unit_id", "")))
		if uf and not uf.is_empty():
			if cam.follow_unit_id == uf["id"]:
				cam.clear_follow_keep_look()
			else:
				cam.set_follow(uf["id"])
				cam.update_follow_pos(uf["pos"])
	elif id == 4:
		var u = _unit_by_id(str(p.get("unit_id", "")))
		if u:
			_dock_unit(u)
	elif id == 400:
		_popup_home_stations(p)
	elif id >= 1000 and id < 2000:
		var ship_id = str(popup.get_meta("launch_%d" % id, ""))
		_launch_pilot(p, ship_id)
	elif id >= 2000 and id < 3000:
		var ship_id2 = str(popup.get_meta("destroy_%d" % id, ""))
		pilots_sys.destroy_one(p, ship_id2)
	elif id >= 3000 and id < 4000:
		var ton = str(popup.get_meta("ton_%d" % id, ""))
		_popup_build_ships(p, ton)
	elif (id >= 4000 and id < 5000) or (id >= 4100 and id < 4500):
		var ship_id3 = str(popup.get_meta("autobuild_%d" % id, ""))
		var ton2 = str(popup.get_meta("autobuild_ton_%d" % id, ""))
		pilots_sys.set_auto(p, ton2, ship_id3)
	elif id >= 5000 and id < 6000:
		var sid = str(popup.get_meta("home_%d" % id, ""))
		p["home_station"] = sid


func _popup_assign_resources(p: Dictionary) -> void:
	var held = BoardResourceAssign.pilot_held_count(map, str(p["id"]))
	var mx = BoardResourceAssign.max_assignable(map, p)
	var win = Window.new()
	win.title = "分配资源点"
	win.size = Vector2i(280, 120)
	win.unresizable = true
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	var vbox = VBoxContainer.new()
	var box = HBoxContainer.new()
	var btn_l = Button.new()
	btn_l.text = "<"
	var edit = LineEdit.new()
	edit.text = str(held)
	edit.custom_minimum_size = Vector2(72, 0)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var btn_r = Button.new()
	btn_r.text = ">"
	var lbl = Label.new()
	lbl.text = " / %d" % mx
	box.add_child(btn_l)
	box.add_child(edit)
	box.add_child(btn_r)
	box.add_child(lbl)
	var ok = Button.new()
	ok.text = "确定"
	vbox.add_child(box)
	vbox.add_child(ok)
	margin.add_child(vbox)
	win.add_child(margin)
	add_child(win)
	btn_l.pressed.connect(func():
		var v = int(edit.text) if edit.text.is_valid_int() else held
		edit.text = str(maxi(0, v - 1))
	)
	btn_r.pressed.connect(func():
		var v = int(edit.text) if edit.text.is_valid_int() else held
		edit.text = str(mini(mx, v + 1))
	)
	var finish = func():
		var v = int(edit.text) if edit.text.is_valid_int() else held
		v = clampi(v, 0, mx)
		BoardResourceAssign.set_target_count(map, p, v, rng, admin)
		starmap_view.rebuild_labels(pilots)
		starmap_view.rebuild()
		_rebuild_hud_list()
		win.queue_free()
	ok.pressed.connect(finish)
	win.close_requested.connect(func(): win.queue_free())
	win.popup_centered()

func _popup_launch_models(p: Dictionary) -> void:
	popup.clear()
	var counts = pilots_sys.storage_count_by_model(p)
	var i = 0
	for sid in counts.keys():
		var id = 1000 + i
		var def: Dictionary = data.ship_def(sid)
		popup.add_item("%s 脳%d" % [def.get("name", sid), counts[sid]], id)
		popup.set_meta("launch_%d" % id, sid)
		i += 1
	if counts.is_empty():
		popup.add_item("（空）", 999)
		popup.set_item_disabled(0, true)
	popup.popup()

func _popup_destroy_models(p: Dictionary) -> void:
	popup.clear()
	var counts = pilots_sys.storage_count_by_model(p)
	var i = 0
	for sid in counts.keys():
		var id = 2000 + i
		var def: Dictionary = data.ship_def(sid)
		popup.add_item("%s 脳%d" % [def.get("name", sid), counts[sid]], id)
		popup.set_meta("destroy_%d" % id, sid)
		i += 1
	popup.popup()

func _popup_build_menu(p: Dictionary) -> void:
	popup.clear()
	var tons = BoardPilotSystem.TONNAGES
	for i in tons.size():
		var ton: String = tons[i]
		var id = 3000 + i
		var auto: String = str(p["auto_build"].get(ton, ""))
		var label = _tonnage_zh(ton)
		if auto == "":
			label += " [无]"
		else:
			label += " [%s]" % data.ship_def(auto).get("name", auto)
		popup.add_item(label, id)
		popup.set_meta("ton_%d" % id, ton)
	popup.popup()

func _popup_build_ships(_p: Dictionary, ton: String) -> void:
	popup.clear()
	var id0 = 4000
	popup.add_item("无", id0)
	popup.set_meta("autobuild_%d" % id0, "")
	popup.set_meta("autobuild_ton_%d" % id0, ton)
	var i = 1
	for sid in data.ships.keys():
		var def: Dictionary = data.ships[sid]
		if str(def.get("tonnage")) != ton:
			continue
		var id = 4000 + i
		popup.add_item(str(def.get("name", sid)), id)
		popup.set_meta("autobuild_%d" % id, sid)
		popup.set_meta("autobuild_ton_%d" % id, ton)
		i += 1
	popup.popup()

func _popup_home_stations(p: Dictionary) -> void:
	popup.clear()
	var i = 0
	for sid in map.systems.keys():
		var sc = map.station_cell(sid)
		if sc < 0:
			continue
		if int(map.systems[sid]["cells"][sc]["owner"]) != int(p["faction"]):
			continue
		var id = 5000 + i
		popup.add_item(str(map.systems[sid]["name"]), id)
		popup.set_meta("home_%d" % id, sid)
		i += 1
	popup.popup()

func _launch_pilot(p: Dictionary, ship_id: String) -> void:
	if str(p.get("unit_id", "")) != "":
		return
	var cs: String = str(p.get("current_station", ""))
	if cs == "" or not map.systems.has(cs):
		return
	var inst = pilots_sys.take_one(p, ship_id)
	if inst.is_empty():
		return
	var sc = map.station_cell(cs)
	var u = _spawn_unit(p, inst, cs, sc)
	p["unit_id"] = u["id"]
	p["in_station"] = false
	_ensure_unit_node(u)
	admin.request("pilot.launch", {"pilot": p["id"], "ship": ship_id, "sys": cs})

func _pick_unit(screen_pos: Vector2) -> Dictionary:
	if cam == null or cam.cam == null:
		return {}
	var from = cam.cam.project_ray_origin(screen_pos)
	var dir = cam.cam.project_ray_normal(screen_pos)
	var to = from + dir * 2000.0
	var space = get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.collision_mask = 1
	var hit = space.intersect_ray(q)
	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider != null:
			var uid = ""
			if collider.has_meta("unit_id"):
				uid = str(collider.get_meta("unit_id"))
			else:
				var n = collider as Node
				while n:
					if n.has_meta("unit_id"):
						uid = str(n.get_meta("unit_id"))
						break
					n = n.get_parent()
			if uid != "":
				var got = _unit_by_id(uid)
				if not got.is_empty():
					return got
	# Geometric fallback: nearest unit screen-distance
	var best = {}
	var best_d = 36.0
	for u in units:
		if not u.get("alive", false):
			continue
		var wp: Vector3 = u["pos"]
		if unit_nodes.has(u["id"]):
			wp = unit_nodes[u["id"]].global_position
		if cam.cam.is_position_behind(wp):
			continue
		var sp = cam.cam.unproject_position(wp)
		var d = sp.distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = u
	return best

func _pick_cell(screen_pos: Vector2) -> Dictionary:
	# Camera ray vs Y=0 + exclusive angular sector
	if cam == null or cam.cam == null:
		return {}
	var from = cam.cam.project_ray_origin(screen_pos)
	var dir = cam.cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return {}
	var tt = -from.y / dir.y
	if tt < 0.0:
		return {}
	var hitp = from + dir * tt
	var flat = Vector3(hitp.x, 0.0, hitp.z)
	var best = {}
	var best_score = INF
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		var center: Vector3 = sys["center"]
		var local = flat - center
		var r = local.length()
		var sc = starmap_view.visual_scale_of(sid) if starmap_view else float(sys.get("scale", 1.0))
		var inner: float = float(map.layout.get("ring_inner", 12)) * sc
		var outer: float = float(map.layout.get("ring_outer", 26)) * sc
		if r < inner - 0.05 or r > outer + 0.35:
			continue
		var ang = atan2(local.x, -local.z)
		if ang < 0.0:
			ang += TAU
		for c in sys["cells"]:
			var mid: float = float(c["angle_center"])
			var half: float = float(c["angle_half"])
			var d = absf(fposmod(ang - mid + PI, TAU) - PI)
			if d <= half + 0.0001:
				var mid_r = (inner + outer) * 0.5
				var score = absf(r - mid_r) + d * mid_r
				if score < best_score:
					best_score = score
					best = {"sys": sid, "cell": int(c["index"])}
	return best
func _update_detail() -> void:
	if selection.is_empty():
		detail.text = ""
		return
	var u = _unit_by_id(selection[0])
	if u.is_empty() or not u.get("alive", false):
		detail.text = ""
		return
	var p = _pilot_by_id(u["pilot_id"])
	var inst: Dictionary = u["inst"]
	var fac_name = ""
	for f in data.factions.get("factions", []):
		if int(f["id"]) == int(u["faction"]):
			fac_name = f.get("abbrev", "")
	detail.text = "[b][%s]%s %s[/b]\nPilot %s\nRel %s\nSystem %s\nHome %s\nShield %d/%d\nArmor %d/%d\nHull %d/%d\nCap %d/%d\nResist %d\nIntra %.1fs Jump %.1fs" % [
		fac_name, p.get("name", ""), u["name"],
		p.get("name", ""), _rel_for(u["faction"]),
		map.systems[u["sys"]]["name"], _home_label(p),
		int(inst["shield"]), int(inst["max_s"]),
		int(inst["armor"]), int(inst["max_a"]),
		int(inst["structure"]), int(inst["max_h"]),
		int(inst["cap"]), int(inst["max_cap"]),
		int(inst["resist"]),
		u["move_s"], u["jump_s"]
	]
