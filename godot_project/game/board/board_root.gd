extends Node3D
## EVETBS board test orchestrator (sleeper NPC) 鈥?bricks talk via AdminProxy.

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
const BR_TRACKER := preload("res://game/board/battle_report_tracker.gd")
const SHIP_ART := preload("res://art_modules/eve_ship_art/scripts/eve_ship_art_module.gd")
const CALLOUT_SCR := preload("res://game/board/hud/tactical_callout_layer.gd")

var data: BoardData
var map: BoardMapModel
var capture: BoardCaptureSystem
var pilots_sys: BoardPilotSystem
var ai: BoardAiController
var admin: BoardAdminProxy
var br_tracker: BoardBattleReportTracker

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
## LMB edges latched in _input, consumed in _process (release is never dropped on UI).
var _lmb_press_latch := false
var _lmb_press_pos := Vector2.ZERO
var _lmb_press_on_ui := false
var _lmb_release_latch := false
var _lmb_release_pos := Vector2.ZERO
## RMB orders: release edge from Input state when the mouse event never arrives.
var _rmb_held := false
var _rmb_press_pos := Vector2.ZERO
var _rmb_press_on_ui := false
var _rmb_handled_by_input := false
var _starmap_scale_dirty = false
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
var auto_launch_btn: Button
var sync_move_btn: Button
var br_list: VBoxContainer
var br_window: Window
var br_body: RichTextLabel
var sync_move_enabled: bool = false ## UI default 关
var auto_launch_enabled: bool = true ## UI default 开
var _sync_gid_next: int = 1
var _tonnage_tex: Dictionary = {}
var _portrait_tex: Dictionary = {}
var _curtain_acc: float = 0.0
var _tips_fade_cache: Dictionary = {} ## path -> ImageTexture with left→right alpha
## Locked tactical + starmap defaults — TACTICAL_TOPDOWN.md
const TACTICAL_FONT_SCALE := 7.7
const TACTICAL_ICON_SCALE := 5.6
const TACTICAL_BORDER_JAGGED := 0.16
const TACTICAL_SYSNAME_SCALE := 1.85
## Baked view defaults (TACTICAL_TOPDOWN.md) — no runtime tune bar.
var starmap_name_scale: float = 6.55
var starmap_icon_scale: float = 2.6
var starmap_badge_scale: float = 10.05
var starmap_count_scale: float = 8.55
var mouse_hint: Label
var _mouse_hint_life: float = 10.0 ## seconds; flash then hide
const MOUSE_HINT_FLASH_HZ := 2.2
var tactical_callouts
var _world_env: WorldEnvironment
var _env_bg_mode_saved := -1
var _env_bg_color_saved := Color.BLACK
var _env_had_sky := false
var _unit_oh_cell: Dictionary = {} ## unit_id -> "sys:cell" last callout anchor
## Garrison revive: "sys:cell" -> {comp, faction, work_at_death, dead_at, pledged}
var _garrison_posts: Dictionary = {}
var _battle_clock: float = 0.0
## unit_id -> {sys, cell, times: PackedFloat32Array} for sleeper-cell order window
var _order_cell_clicks: Dictionary = {}
const GARRISON_REVIVE_S := 600.0
const SLEEPER_ORDER_WINDOW_S := 5.0
const GARRISON_CLOAK_S := 1.35
const GARRISON_SINK_Y := 5.5
const CLOAK_TEX := "res://assets/vfx/cloak/cloaking.png"
const UI_FONT_PATH := "res://assets/fonts/simhei.ttf"
var _ui_font: Font = null


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

func _dbg59(hid: String, loc: String, msg: String, data_payload: Dictionary = {}) -> void:
	## Hot ids: skip sync disk (land hitch). Keep PHASE/NAV/LAND/MCP only.
	if hid in ["A", "B", "C", "ARC", "TON"]:
		return
	var payload := {
		"sessionId": "59aff0",
		"hypothesisId": hid,
		"location": loc,
		"message": msg,
		"data": data_payload,
		"timestamp": Time.get_ticks_msec(),
		"runId": str(data_payload.get("runId", "pre-fix"))
	}
	var path := "h:/debug-59aff0.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(payload))
	f.close()
# endregion

func mcp_dump_debug() -> Dictionary:
	## MCP runtime probe: phase + gate bearings + blocked nav waiters + garrison.
	var out := {"ok": true, "systems": {}, "nav_wait": [], "garrison": [], "npc_facs": []}
	if map == null:
		return {"ok": false, "err": "no_map"}
	if data:
		out["npc_facs"] = data.npc_faction_ids()
	var g_alive := 0
	var g_by_kind: Dictionary = {}
	for u in units:
		if not u.get("alive", false) or not u.get("garrison", false):
			continue
		g_alive += 1
		var sid := str(u.get("sys", ""))
		var ci := int(u.get("cell", -1))
		var kind := -1
		if map.systems.has(sid) and ci >= 0 and ci < map.systems[sid]["cells"].size():
			kind = int(map.systems[sid]["cells"][ci].get("kind", -1))
		var kk := str(kind)
		g_by_kind[kk] = int(g_by_kind.get(kk, 0)) + 1
		if out["garrison"].size() < 24:
			var inst_g: Dictionary = u.get("inst", {})
			out["garrison"].append({
				"id": u["id"], "ship": u.get("ship_id"), "fac": int(u.get("faction", 0)),
				"sys": sid, "cell": ci, "kind": kind,
				"pledged": bool(u.get("garrison_pledged", false)),
				"cmd": bool(u.get("commandable", true)),
				"expanded": _sleeper_plate_expanded(u),
				"max_a": int(inst_g.get("max_a", 0)),
				"max_h": int(inst_g.get("max_h", 0)),
				"no_max_loss": bool(u.get("no_max_loss", false)),
				"pd_repair_max_loss": bool(u.get("pd_repair_max_loss", false)),
			})
	out["garrison_alive"] = g_alive
	out["garrison_by_kind"] = g_by_kind
	out["garrison_posts"] = _garrison_posts.size()
	var post_comp: Dictionary = {}
	for pk in _garrison_posts.keys():
		var post: Dictionary = _garrison_posts[pk]
		var parts: PackedStringArray = str(pk).split(":")
		if parts.size() < 2:
			continue
		var sid_p := str(parts[0])
		var ci_p := int(parts[1])
		var kind_p := -1
		if map.systems.has(sid_p) and ci_p >= 0 and ci_p < map.systems[sid_p]["cells"].size():
			kind_p = int(map.systems[sid_p]["cells"][ci_p].get("kind", -1))
		var kks := str(kind_p)
		if not post_comp.has(kks):
			post_comp[kks] = post.get("comp", [])
	out["post_comp_by_kind"] = post_comp
	var sleeper_hp: Dictionary = {}
	for sid_hp in ["sleeper_frigate_a", "sleeper_destroyer", "sleeper_cruiser_a"]:
		var def_hp: Dictionary = data.ship_def(sid_hp) if data else {}
		sleeper_hp[sid_hp] = {
			"armor": int(def_hp.get("armor", 0)),
			"structure": int(def_hp.get("structure", 0)),
		}
	out["sleeper_hp"] = sleeper_hp
	out["nameplate_y"] = BoardUnitOverhead.battle_nameplate_y
	out["br_active"] = br_tracker.active.keys() if br_tracker else []
	var station_pilots := 0
	for u2 in units:
		if not u2.get("alive", false) or bool(u2.get("garrison", false)):
			continue
		var s2 := str(u2.get("sys", ""))
		var c2 := int(u2.get("cell", -1))
		if map.systems.has(s2) and c2 >= 0 and c2 < map.systems[s2]["cells"].size():
			if int(map.systems[s2]["cells"][c2].get("kind", -1)) == BoardTypes.CellKind.STATION:
				station_pilots += 1
	out["pilots_on_station"] = station_pilots
	var npc_owned := 0
	var unowned_n := 0
	for sid3 in map.systems.keys():
		for c3 in map.systems[sid3]["cells"]:
			if int(c3.get("kind", 0)) == BoardTypes.CellKind.EMPTY:
				continue
			var ow := int(c3.get("owner", 0))
			if ow == 0:
				unowned_n += 1
			elif data.is_npc_faction(ow):
				npc_owned += 1
	out["npc_owned_cells"] = npc_owned
	out["unowned_cells"] = unowned_n
	for sid in map.systems.keys():
		var want = map.desired_ring_phase(str(sid))
		var cur = float(map.systems[sid].get("ring_phase", 0.0))
		var gates: Array = []
		var center: Vector3 = map.systems[sid]["center"]
		for c in map.systems[sid]["cells"]:
			if int(c["kind"]) != BoardTypes.CellKind.GATE:
				continue
			var to_id: String = str(c.get("gate_to", ""))
			var bearing_deg := 0.0
			if map.systems.has(to_id):
				var other: Vector3 = map.systems[to_id]["center"]
				var dir = other - center
				var bearing = atan2(dir.x, -dir.z)
				if bearing < 0.0:
					bearing += TAU
				bearing_deg = rad_to_deg(bearing)
			gates.append({
				"i": int(c["index"]),
				"to": to_id,
				"center_deg": snappedf(rad_to_deg(float(c["angle_center"])), 0.1),
				"span_deg": snappedf(rad_to_deg(float(c["angle_half"]) * 2.0), 0.1),
				"bearing_deg": snappedf(bearing_deg, 0.1),
				"pass": map.can_pass_gate(str(sid), int(c["index"]), viewer_faction, data.diplomacy if data else {}),
			})
		out["systems"][sid] = {
			"cur_deg": snappedf(rad_to_deg(cur), 0.1),
			"want_deg": snappedf(rad_to_deg(want), 0.1),
			"err_deg": snappedf(rad_to_deg(map._angle_delta(want, cur)), 0.1),
			"bias_deg": float(map.layout.get("ring_phase_bias_deg", 37.5)),
			"gates": gates,
		}
	for u in units:
		if not u.get("alive", false):
			continue
		if u.has("order_dest_sys") and u["path"].is_empty() and int(u.get("phase", 0)) == BoardTypes.MovePhase.IDLE:
			out["nav_wait"].append({
				"id": u["id"], "sys": u["sys"], "cell": int(u["cell"]),
				"dest": [u["order_dest_sys"], int(u.get("order_dest_cell", -1))]
			})
	_dbg59("MCP", "board_root.mcp_dump_debug", "dump", out)
	return out

func _ready() -> void:
	var t_ready := Time.get_ticks_msec()
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
	br_tracker = BR_TRACKER.new()
	br_tracker.viewer_faction = viewer_faction
	br_tracker.is_npc_faction = Callable(data, "is_npc_faction")
	_spawn_opening()
	_apply_opening_npc_owners()
	_register_opening_garrison_posts()
	ai.setup_fleets(units)
	_setup_ai_autobuild()
	_build_scene_nodes()
	_refresh_occupancy()
	## Identity equal phase + layout bias (CCW). Mean gate-align was CW ~30–45° vs expected.
	var bias := deg_to_rad(float(map.layout.get("ring_phase_bias_deg", 37.5)))
	for sid0 in map.systems.keys():
		var n0: int = map.systems[sid0]["cells"].size()
		var ident := -PI / float(maxi(n0, 1))
		map.systems[sid0]["ring_phase"] = fposmod(ident + bias, TAU)
		map._apply_ring_phase(str(sid0))
	starmap_view.setup(map, data.diplomacy, viewer_faction)
	starmap_view.npc_faction_ids.clear()
	for nid in data.npc_faction_ids():
		starmap_view.npc_faction_ids[int(nid)] = true
	starmap_view.set_units(units)
	## Labels already rebuilt inside setup→rebuild; defer second pass.
	call_deferred("_deferred_ready_labels")
	_reanchor_idle_units()
	_rebuild_hud_list()
	## Dump after first visibility tick so garrison samples include HP / plate state.
	get_tree().create_timer(1.2).timeout.connect(func(): mcp_dump_debug())
	turret_vfx = VFX_SCR.new()
	turret_vfx.name = "TurretVfx"
	add_child(turret_vfx)
	float_text = FLOAT_SCR.new()
	float_text.name = "FloatText"
	add_child(float_text)
	# #region agent log
	_dbg59("PERF", "board_root._ready", "setup_ms", {
		"ms": Time.get_ticks_msec() - t_ready, "runId": "post-fix"
	})
	# #endregion

func _deferred_ready_labels() -> void:
	if starmap_view:
		starmap_view.rebuild_labels(pilots)

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

func _garrison_composition_for_kind(kind: int) -> Array:
	## One hull per capturable kind (SHIPS §12).
	match kind:
		BoardTypes.CellKind.GATE:
			return ["sleeper_destroyer"]
		BoardTypes.CellKind.RESOURCE:
			return ["sleeper_destroyer"]
		BoardTypes.CellKind.SOV:
			return ["sleeper_frigate_a"]
		BoardTypes.CellKind.STATION:
			return ["sleeper_cruiser_a"]
		_:
			return []

func _apply_opening_npc_owners() -> void:
	## Capturable cells (except opening stations) belong to NPC; rim paints unowned.
	var npc_fac := data.primary_npc_faction()
	if npc_fac == 0 or map == null:
		return
	var station_owners: Dictionary = map.layout.get("opening_stations", {})
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			var kind: int = int(c.get("kind", BoardTypes.CellKind.EMPTY))
			if kind == BoardTypes.CellKind.EMPTY:
				continue
			if kind == BoardTypes.CellKind.STATION and station_owners.has(sid):
				continue
			c["owner"] = npc_fac
			c["work"] = BoardTypes.WORK_MAX
			c["capturing"] = 0
	map.capture_dirty = true
	# #region agent log
	_dbg59("GARR", "board_root._apply_opening_npc_owners", "npc_owners", {
		"npc": npc_fac, "runId": "sleeper-reveal"
	})
	# #endregion

func _register_opening_garrison_posts() -> void:
	## Register latent posts only — no units until system reveal (CAPTURE §6).
	var npc_fac := data.primary_npc_faction()
	if npc_fac == 0:
		return
	var n_posts := 0
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			var kind: int = int(c.get("kind", BoardTypes.CellKind.EMPTY))
			var comp := _garrison_composition_for_kind(kind)
			if comp.is_empty():
				continue
			var cell_owner := int(c.get("owner", 0))
			var pledged := cell_owner != 0 and not data.is_npc_faction(cell_owner)
			var fac := cell_owner if pledged else npc_fac
			if fac == 0:
				fac = npc_fac
			_register_garrison_post(str(sid), int(c["index"]), fac, comp, pledged)
			n_posts += 1
	# #region agent log
	var sample: Dictionary = {}
	for k in [BoardTypes.CellKind.GATE, BoardTypes.CellKind.RESOURCE, BoardTypes.CellKind.SOV, BoardTypes.CellKind.STATION]:
		sample[str(k)] = _garrison_composition_for_kind(k)
	_dbg59("GARR", "board_root._register_opening_garrison_posts", "posts", {
		"n": n_posts, "comp": sample, "runId": "sleeper-reveal"
	})
	# #endregion
	_reveal_opening_station_garrisons()

func _reveal_opening_station_garrisons() -> void:
	## Opening pledged station sleepers spawn immediately (CAPTURE §6 exception).
	var n_rev := 0
	var facs: Array = []
	for key in _garrison_posts.keys():
		var post: Dictionary = _garrison_posts[key]
		if not bool(post.get("pledged", false)):
			continue
		var parts: PackedStringArray = str(key).split(":")
		if parts.size() < 2:
			continue
		var sid := str(parts[0])
		var ci := int(parts[1])
		if not map.systems.has(sid) or ci < 0 or ci >= map.systems[sid]["cells"].size():
			continue
		if int(map.systems[sid]["cells"][ci].get("kind", -1)) != BoardTypes.CellKind.STATION:
			continue
		_reveal_garrison_cell(sid, ci)
		n_rev += 1
		facs.append(int(post.get("faction", 0)))
	# #region agent log
	_dbg59("GARR", "board_root._reveal_opening_station_garrisons", "station_pledge", {
		"n": n_rev, "facs": facs, "runId": "station-pledge"
	})
	# #endregion

func _register_garrison_post(sys: String, cell: int, faction: int, composition: Array, pledged: bool) -> void:
	var key := "%s:%d" % [sys, cell]
	_garrison_posts[key] = {
		"comp": composition.duplicate(),
		"faction": faction,
		"pledged": pledged,
		"dead_at": -1.0,
		"work_at_death": -1.0,
		"revealed": false,
		"hiding": false,
	}

func _spawn_garrison_at(sys: String, cell: int, faction: int, composition: Array, pledged: bool, with_cloak: bool = true) -> void:
	_register_garrison_post(sys, cell, faction, composition, pledged)
	var key := "%s:%d" % [sys, cell]
	_garrison_posts[key]["revealed"] = true
	_garrison_posts[key]["hiding"] = false
	for ship_id in composition:
		_spawn_garrison_unit(str(ship_id), sys, cell, faction, pledged, with_cloak)

func _spawn_garrison_unit(ship_id: String, sys: String, cell: int, faction: int, pledged: bool, with_cloak: bool = true) -> Dictionary:
	var inst = pilots_sys.make_ship_instance(ship_id)
	pilots_sys.apply_fit_resist(inst, ship_id)
	var def: Dictionary = data.ship_def(ship_id)
	var uid = "u%d" % next_unit_i
	next_unit_i += 1
	var u = {
		"id": uid,
		"pilot_id": "",
		"pilot_name": "未知冬眠者",
		"faction": faction,
		"ship_id": ship_id,
		"name": def.get("name", ship_id),
		"ship_name": str(def.get("name", ship_id)),
		"tonnage": def.get("tonnage", "frigate"),
		"sys": sys,
		"cell": cell,
		"alive": true,
		"phase": BoardTypes.MovePhase.IDLE,
		"phase_t": 0.0,
		"path": [],
		"from_cell": cell,
		"to_cell": cell,
		"to_sys": sys,
		"work_rate": float(def.get("work_rate", 8)),
		"move_s": float(def.get("move_s", 0)),
		"landing_s": float(def.get("landing_s", 0)),
		"jump_s": float(def.get("jump_s", 0)),
		"inertia": float(def.get("inertia", 1)),
		"mass": float(def.get("mass", 1e6)),
		"speed": float(def.get("speed", 200)),
		"signature_radius": float(def.get("signature_radius", 35)),
		"inst": inst,
		"bubble_on": false,
		"bubble_t": 0.0,
		"pd": _build_pd(def),
		"bubble_immune": true,
		"float_t": rng.randf() * 10.0,
		"float_freq": rng.randf_range(-0.1, 0.1),
		"rest_pos": Vector3.ZERO,
		"pos": map.cell_world_pos(sys, cell, BoardTypes.UNIT_Y),
		"alpha": 1.0 if not with_cloak else 0.0,
		"fleet_id": -1,
		"home": sys,
		"current_station": "",
		"dealt_timer": 0.0,
		"took_damage": false,
		"focus_id": "",
		"npc": true,
		"garrison": true,
		"commandable": false,
		"garrison_pledged": pledged,
		"garrison_cell_key": "%s:%d" % [sys, cell],
		"cloak_t": 0.0 if with_cloak else 1.0,
		"cloak_dir": 1.0 if with_cloak else 0.0, ## +1 reveal, -1 hide, 0 idle
	}
	if with_cloak:
		u["pos"].y = BoardTypes.UNIT_Y - GARRISON_SINK_Y
		u["rest_pos"] = Vector3(u["pos"].x, BoardTypes.UNIT_Y, u["pos"].z)
	else:
		u["rest_pos"] = u["pos"]
	_init_unit_combat(u)
	_mark_cell_enter(u, sys, cell)
	units.append(u)
	## Mid-game spawn (revive / capture flip) needs a node; opening waits for _build_scene_nodes.
	if has_node("Units"):
		_ensure_unit_node(u)
		_ensure_cloak_fx(u)
	return u

func _cell_has_alive_garrison(sys: String, cell: int) -> bool:
	var key := "%s:%d" % [sys, cell]
	for u in units:
		if not u.get("alive", false):
			continue
		if not u.get("garrison", false):
			continue
		if str(u.get("garrison_cell_key", "")) == key:
			return true
		if str(u.get("sys", "")) == sys and int(u.get("cell", -1)) == cell:
			return true
	return false

func _note_garrison_death(u: Dictionary) -> void:
	if not u.get("garrison", false):
		return
	var key := str(u.get("garrison_cell_key", ""))
	if key == "" or not _garrison_posts.has(key):
		key = "%s:%d" % [str(u.get("sys", "")), int(u.get("cell", -1))]
	if not _garrison_posts.has(key):
		return
	if _cell_has_alive_garrison(str(u.get("sys", "")), int(u.get("cell", -1))):
		return
	var parts = key.split(":")
	if parts.size() < 2:
		return
	var sid := str(parts[0])
	var ci := int(parts[1])
	var work := BoardTypes.WORK_MAX
	if map.systems.has(sid) and ci >= 0 and ci < map.systems[sid]["cells"].size():
		work = float(map.systems[sid]["cells"][ci].get("work", BoardTypes.WORK_MAX))
	var post: Dictionary = _garrison_posts[key]
	post["dead_at"] = _battle_clock
	post["work_at_death"] = work
	post["faction"] = int(u.get("faction", post.get("faction", 0)))
	post["pledged"] = bool(u.get("garrison_pledged", post.get("pledged", false)))

func _rel_between(fac_a: int, fac_b: int) -> String:
	if int(fac_a) == int(fac_b):
		return "self"
	if fac_b == 0:
		return "hostile"
	if data.is_npc_faction(fac_b) and not data.is_npc_faction(fac_a):
		return "hostile"
	var rels: Dictionary = data.diplomacy.get("relations", {}).get(str(fac_a), {})
	return str(rels.get(str(fac_b), "hostile"))

func _cell_wants_garrison_reveal(sys: String, cell: int) -> bool:
	## Non-sleeper in-system whose standing vs cell owner is not self/ally.
	## Opening pledged stations spawn revealed once (CAPTURE §6); after that same hide rules.
	if not map.systems.has(sys):
		return false
	var cells: Array = map.systems[sys]["cells"]
	if cell < 0 or cell >= cells.size():
		return false
	var cell_owner := int(cells[cell].get("owner", 0))
	for u in units:
		if not u.get("alive", false):
			continue
		if bool(u.get("garrison", false)) or bool(u.get("npc", false)):
			continue
		if str(u.get("sys", "")) != sys:
			continue
		if int(u.get("phase", 0)) == BoardTypes.MovePhase.INVULN and str(u.get("step_kind", "")) == "jump":
			continue
		var rel := _rel_between(int(u.get("faction", 0)), cell_owner)
		if rel != "self" and rel != "ally":
			return true
	return false

func _ensure_cloak_fx(u: Dictionary) -> void:
	var uid := str(u.get("id", ""))
	if not unit_nodes.has(uid):
		return
	var n: Node3D = unit_nodes[uid]
	if n.get_node_or_null("CloakFx") != null:
		return
	var spr := Sprite3D.new()
	spr.name = "CloakFx"
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.double_sided = true
	spr.pixel_size = 0.012
	spr.modulate = Color(0.55, 0.85, 1.0, 0.0)
	spr.position = Vector3(0, 0.8, 0)
	spr.no_depth_test = true
	if ResourceLoader.exists(CLOAK_TEX):
		spr.texture = load(CLOAK_TEX) as Texture2D
	n.add_child(spr)

func _despawn_garrison_unit_now(u: Dictionary) -> void:
	u["alive"] = false
	u["cloak_dir"] = 0.0
	u["cloak_t"] = 0.0
	_clear_reserve(u)
	if unit_nodes.has(u["id"]):
		unit_nodes[u["id"]].visible = false
		var oh = unit_nodes[u["id"]].get_node_or_null("Overhead")
		if oh and oh.has_method("set_alive_view"):
			oh.set_alive_view(false)
		var body = unit_nodes[u["id"]].get_node_or_null("PickBody") as StaticBody3D
		if body:
			body.collision_layer = 0

func _begin_hide_garrison_cell(sys: String, cell: int) -> void:
	var key := "%s:%d" % [sys, cell]
	if not _garrison_posts.has(key):
		return
	var post: Dictionary = _garrison_posts[key]
	post["hiding"] = true
	post["revealed"] = false
	for u in units:
		if not u.get("alive", false) or not u.get("garrison", false):
			continue
		if str(u.get("garrison_cell_key", "")) != key:
			continue
		u["cloak_dir"] = -1.0
		_ensure_cloak_fx(u)

func _reveal_garrison_cell(sys: String, cell: int) -> void:
	var key := "%s:%d" % [sys, cell]
	if not _garrison_posts.has(key):
		return
	var post: Dictionary = _garrison_posts[key]
	if float(post.get("dead_at", -1.0)) >= 0.0:
		return
	post["hiding"] = false
	if bool(post.get("revealed", false)) and _cell_has_alive_garrison(sys, cell):
		for u in units:
			if u.get("alive", false) and str(u.get("garrison_cell_key", "")) == key:
				if float(u.get("cloak_t", 1.0)) < 0.999:
					u["cloak_dir"] = 1.0
		return
	post["revealed"] = true
	var fac := int(post.get("faction", data.primary_npc_faction()))
	var pledged := bool(post.get("pledged", false))
	var comp: Array = post.get("comp", [])
	# #region agent log
	_dbg59("GARR", "board_root._reveal_garrison_cell", "reveal", {
		"sys": sys, "cell": cell, "fac": fac, "pledged": pledged, "n": comp.size(),
		"runId": "sleeper-reveal"
	})
	# #endregion
	for ship_id in comp:
		_spawn_garrison_unit(str(ship_id), sys, cell, fac, pledged, true)

func _tick_garrison_visibility(delta: float) -> void:
	## Reveal/hide by in-system foreign non-sleeper presence; drive cloak anim.
	for key in _garrison_posts.keys():
		var parts = str(key).split(":")
		if parts.size() < 2:
			continue
		var sid := str(parts[0])
		var ci := int(parts[1])
		var want := _cell_wants_garrison_reveal(sid, ci)
		var post: Dictionary = _garrison_posts[key]
		var has_alive := _cell_has_alive_garrison(sid, ci)
		var hiding := bool(post.get("hiding", false))
		if want:
			if hiding and has_alive:
				post["hiding"] = false
				post["revealed"] = true
				for u in units:
					if u.get("alive", false) and str(u.get("garrison_cell_key", "")) == key:
						u["cloak_dir"] = 1.0
			elif not bool(post.get("revealed", false)) and not has_alive:
				_reveal_garrison_cell(sid, ci)
		elif has_alive or bool(post.get("revealed", false)):
			if not hiding:
				# #region agent log
				_dbg59("GARR", "board_root._tick_garrison_visibility", "hide", {
					"sys": sid, "cell": ci, "runId": "sleeper-reveal"
				})
				# #endregion
				_begin_hide_garrison_cell(sid, ci)
	_tick_garrison_cloak_anim(delta)

func _tick_garrison_cloak_anim(delta: float) -> void:
	for u in units:
		if not u.get("garrison", false):
			continue
		var dir := float(u.get("cloak_dir", 0.0))
		if absf(dir) < 0.01 and float(u.get("cloak_t", 1.0)) >= 0.999 and u.get("alive", false):
			continue
		if absf(dir) < 0.01 and not u.get("alive", false):
			continue
		var t := float(u.get("cloak_t", 0.0))
		t = clampf(t + dir * delta / GARRISON_CLOAK_S, 0.0, 1.0)
		u["cloak_t"] = t
		## Ease: rise from below + alpha (EVE cloaking wash).
		var ease_t := t * t * (3.0 - 2.0 * t)
		var base := u.get("rest_pos", u.get("pos", Vector3.ZERO)) as Vector3
		if typeof(base) != TYPE_VECTOR3:
			base = Vector3(float(u["pos"].x), BoardTypes.UNIT_Y, float(u["pos"].z))
		u["pos"] = Vector3(base.x, BoardTypes.UNIT_Y - GARRISON_SINK_Y * (1.0 - ease_t), base.z)
		u["alpha"] = ease_t
		if unit_nodes.has(u["id"]):
			var n: Node3D = unit_nodes[u["id"]]
			n.visible = u.get("alive", false) or dir < 0.0
			n.global_position = u["pos"]
			var fx = n.get_node_or_null("CloakFx") as Sprite3D
			if fx:
				fx.visible = t < 0.98 and t > 0.02
				fx.modulate = Color(0.55, 0.85, 1.0, (1.0 - absf(ease_t - 0.5) * 2.0) * 0.75)
			var oh = n.get_node_or_null("Overhead")
			if oh:
				oh.visible = ease_t > 0.55 and u.get("alive", false)
		if dir > 0.0 and t >= 0.999:
			u["cloak_dir"] = 0.0
			u["alpha"] = 1.0
			u["pos"].y = BoardTypes.UNIT_Y
		elif dir < 0.0 and t <= 0.001:
			u["cloak_dir"] = 0.0
			var gkey := str(u.get("garrison_cell_key", ""))
			_despawn_garrison_unit_now(u)
			if gkey != "" and _garrison_posts.has(gkey):
				var gp := gkey.split(":")
				if gp.size() >= 2 and not _cell_has_alive_garrison(str(gp[0]), int(gp[1])):
					_garrison_posts[gkey]["hiding"] = false
					_garrison_posts[gkey]["revealed"] = false

func _tick_garrison_revive(delta: float) -> void:
	_battle_clock += delta
	var to_revive: Array = []
	for key in _garrison_posts.keys():
		var post: Dictionary = _garrison_posts[key]
		var dead_at := float(post.get("dead_at", -1.0))
		if dead_at < 0.0:
			continue
		var parts = str(key).split(":")
		if parts.size() < 2:
			continue
		var sid := str(parts[0])
		var ci := int(parts[1])
		if not map.systems.has(sid) or ci < 0 or ci >= map.systems[sid]["cells"].size():
			continue
		var work := float(map.systems[sid]["cells"][ci].get("work", BoardTypes.WORK_MAX))
		var work0 := float(post.get("work_at_death", work))
		if absf(work - work0) > 0.05:
			post["dead_at"] = -1.0
			post["work_at_death"] = -1.0
			continue
		if _battle_clock - dead_at < GARRISON_REVIVE_S:
			continue
		if _cell_has_alive_garrison(sid, ci):
			post["dead_at"] = -1.0
			continue
		to_revive.append(key)
	for key2 in to_revive:
		var post2: Dictionary = _garrison_posts[key2]
		var parts2 = str(key2).split(":")
		var sid2 := str(parts2[0])
		var ci2 := int(parts2[1])
		post2["dead_at"] = -1.0
		post2["work_at_death"] = -1.0
		post2["revealed"] = false
		post2["hiding"] = false
		## Only materialize if system currently wants reveal.
		if _cell_wants_garrison_reveal(sid2, ci2):
			_reveal_garrison_cell(sid2, ci2)

func _on_capture_flip_garrison(f: Dictionary) -> void:
	var sid := str(f.get("sys", ""))
	var ci := int(f.get("cell", -1))
	if sid == "" or ci < 0:
		return
	var key := "%s:%d" % [sid, ci]
	## Despawn living garrison on this cell, then re-register for new owner.
	for u in units:
		if not u.get("alive", false) or not u.get("garrison", false):
			continue
		if str(u.get("sys", "")) != sid or int(u.get("cell", -1)) != ci:
			continue
		_despawn_garrison_unit_now(u)
	var kind := int(f.get("kind", -1))
	if kind < 0 and map.systems.has(sid):
		kind = int(map.systems[sid]["cells"][ci].get("kind", -1))
	var comp := _garrison_composition_for_kind(kind)
	if comp.is_empty() and _garrison_posts.has(key):
		comp = _garrison_posts[key].get("comp", [])
	if comp.is_empty():
		return
	var new_owner := int(f.get("owner", 0))
	## NPC completes capture → unowned + hostile NPC garrison (CAPTURE §6).
	if data.is_npc_faction(new_owner) or new_owner == 0:
		if map.systems.has(sid) and ci >= 0 and ci < map.systems[sid]["cells"].size():
			map.systems[sid]["cells"][ci]["owner"] = 0
		var npc_fac := data.primary_npc_faction()
		_register_garrison_post(sid, ci, npc_fac, comp, false)
		if _cell_wants_garrison_reveal(sid, ci):
			_reveal_garrison_cell(sid, ci)
		return
	_register_garrison_post(sid, ci, new_owner, comp, true)
	if _cell_wants_garrison_reveal(sid, ci):
		_reveal_garrison_cell(sid, ci)

func _pick_opening_cell(sys_id: String, kind: int, gate_to: String, used: Dictionary) -> int:
	if not map.systems.has(sys_id):
		return -1
	var cells: Array = map.systems[sys_id]["cells"]
	## Opening station stack: all faction pilots share the home station cell (SHIPS §12).
	if kind == BoardTypes.CellKind.STATION:
		for c in cells:
			if int(c["kind"]) == BoardTypes.CellKind.STATION:
				return int(c["index"])
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
	pilot["last_ship_id"] = str(inst["ship_id"])
	pilot["last_ship_tonnage"] = str(def.get("tonnage", "destroyer"))
	pilot["last_ship_name"] = str(def.get("name", inst["ship_id"]))
	var u = {
		"id": uid,
		"pilot_id": pilot["id"],
		"pilot_name": str(pilot.get("name", pilot["id"])),
		"faction": int(pilot["faction"]),
		"ship_id": inst["ship_id"],
		"name": def.get("name", inst["ship_id"]),
		"ship_name": str(def.get("name", inst["ship_id"])),
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
		"focus_id": "",
	}
	_init_unit_combat(u)
	_mark_cell_enter(u, sys, cell)
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
	## Specials via hidden fit only (evetbs-ship-hidden-fit).
	u["shield_regen_on"] = false
	u["cap_regen_on"] = false
	u["shield_regen_cd"] = rng.randf() * 30.0
	u["recharge_s"] = float(def.get("recharge_s", 400))
	u["scan_res"] = float(def.get("scan_res", 200))
	var has_shield_h := false
	var has_cap_h := false
	u["no_max_loss"] = false
	u["pd_repair_max_loss"] = false
	for h in def.get("fit", {}).get("hidden", []):
		match str(h.get("kind")):
			"shield_regen":
				u["shield_regen_on"] = true
				has_shield_h = true
			"cap_regen":
				u["cap_regen_on"] = true
				has_cap_h = true
				if h.has("recharge_s"):
					u["recharge_s"] = float(h.get("recharge_s", u["recharge_s"]))
				else:
					var ceq: Dictionary = data.equipment.get("cap_regen", {})
					if ceq.has("recharge_s"):
						u["recharge_s"] = float(ceq.get("recharge_s", u["recharge_s"]))
			"no_max_loss":
				u["no_max_loss"] = true
			"pd_repair_max_loss":
				u["pd_repair_max_loss"] = true
	# #region agent log
	if bool(u.get("no_max_loss", false)) or bool(u.get("pd_repair_max_loss", false)):
		_dbg59("DMG", "board_root._init_unit_combat", "init_sleeper_max_flags", {
			"id": str(u.get("id", "")), "ship": str(u.get("ship_id", "")),
			"garrison": bool(u.get("garrison", false)),
			"no_max_loss": bool(u.get("no_max_loss", false)),
			"pd_repair_max_loss": bool(u.get("pd_repair_max_loss", false)),
			"runId": "pd-max-restore"
		})
	# #endregion
	## Player hulls: backfill missing regen if not npc_hull.
	if not bool(def.get("npc_hull", false)):
		if not has_shield_h:
			u["shield_regen_on"] = true
		if not has_cap_h:
			u["cap_regen_on"] = true
	u["weapons"] = _build_weapons(def)
	u["self_rep"] = []
	for slot_ref in def.get("fit", {}).get("slots", []):
		if slot_ref == null:
			continue
		_append_self_rep(u, str(slot_ref))
	for h2 in def.get("fit", {}).get("hidden", []):
		if str(h2.get("kind")) == "self_rep" and str(h2.get("ref", "")) != "":
			_append_self_rep(u, str(h2.get("ref")))
	_init_unit_guard_implant(u, def)

func _append_self_rep(u: Dictionary, ref: String) -> void:
	var eq: Dictionary = data.equipment.get(ref, {})
	if eq.is_empty():
		return
	if not eq.has("heal_shield") and not eq.has("heal_armor"):
		return
	u["self_rep"].append({
		"ref": ref,
		"cycle": float(eq.get("cycle_s", 3)),
		"cd": rng.randf() * 0.5,
		"cap": float(eq.get("cap_cost", 1)),
		"heal_shield": float(eq.get("heal_shield", 0)),
		"heal_armor": float(eq.get("heal_armor", 0)),
	})

func _init_unit_guard_implant(u: Dictionary, def: Dictionary) -> void:
	var field_fit = _fit_has_slot(def, "shield_field")
	var link_fit = _fit_has_slot(def, "armor_link")
	u["guard"] = {
		"field_fitted": field_fit,
		"link_fitted": link_fit,
		"field_on": false,
		"link_on": false,
		## 舰队护卫（护盾立场 / 装甲链接）：装了则自动偏好默认开。
		"field_auto_on": field_fit,
		"link_auto_on": link_fit,
	}
	## Auto-on preference → effect on if bar ≥20%.
	if field_fit:
		u["guard"]["field_on"] = float(u["inst"]["shield"]) >= float(u["inst"]["max_s"]) * 0.2
	if link_fit:
		u["guard"]["link_on"] = float(u["inst"]["armor"]) >= float(u["inst"]["max_a"]) * 0.2
	u["implant"] = {"ref": "", "auto_on": false, "stacks": 0, "shots": 0, "shield_heal_cd": 0.0}
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind")) == "implant":
			u["implant"]["ref"] = str(h.get("ref", ""))
			u["implant"]["auto_on"] = true ## 有植入体则默认开
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
	## Missing auto key → 开 when fitted (UI_AND_SHELL §2.1).
	if g.get("field_fitted", false):
		var field_auto := bool(g.get("field_auto_on", true))
		if field_auto and float(inst["shield"]) >= float(inst["max_s"]) * 0.2:
			g["field_on"] = true
		elif not field_auto:
			g["field_on"] = false
	if g.get("link_fitted", false):
		var link_auto := bool(g.get("link_auto_on", true))
		if link_auto and float(inst["armor"]) >= float(inst["max_a"]) * 0.2:
			g["link_on"] = true
		elif not link_auto:
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
	## 连续 every-1 轮 0 伤；第 every 轮 mul 倍且必中（tracking_override）。
	var imp: Dictionary = _implant_data(u)
	if imp.is_empty() or str(imp.get("id", "")) != "implant_sniper":
		return {"tracking": tracking, "raw": raw, "force_hit": false}
	if not u.get("implant", {}).get("auto_on", true):
		return {"tracking": tracking, "raw": raw, "force_hit": false}
	u["implant"]["shots"] = int(u["implant"].get("shots", 0)) + 1
	var every: int = int(imp.get("every", 10))
	if int(u["implant"]["shots"]) % every == 0:
		return {
			"tracking": float(imp.get("tracking_override", 9999)),
			"raw": raw * float(imp.get("mul", 10)),
			"force_hit": true,
		}
	return {"tracking": tracking, "raw": 0.0, "force_hit": false}

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
	if _fx_ok() and float_text and heal > 0.05:
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
	if _fx_ok() and float_text and absorb > 0.05:
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
	if _fx_ok() and float_text and absorb > 0.05:
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
) -> float:
	## Returns HP actually removed from target (0 if none).
	if not target.get("alive", false) or raw <= 0.0:
		return 0.0
	## Hidden sleeper_hull_lock: incoming hits never cut max HP.
	if bool(target.get("no_max_loss", false)):
		skip_max_loss = true
		# #region agent log
		_dbg59("DMG", "board_root._apply_damage_to_unit", "no_max_loss", {
			"tgt": str(target.get("id", "")), "ship": str(target.get("ship_id", "")),
			"raw": raw, "runId": "no-cap-dmg"
		})
		# #endregion
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
						return 0.0
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
		return 0.0
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
	var max_before := float(inst.get("max_s", 0)) + float(inst.get("max_a", 0)) + float(inst.get("max_h", 0))
	inst["max_s"] = res["max_s"]
	inst["max_a"] = res["max_a"]
	inst["max_h"] = res["max_h"]
	var max_after := float(inst["max_s"]) + float(inst["max_a"]) + float(inst["max_h"])
	var max_loss := maxf(0.0, max_before - max_after)
	var after_hp := float(inst["shield"]) + float(inst["armor"]) + float(inst["structure"])
	var dealt_hp := before_hp - after_hp
	target["hit_flash_t"] = 0.05
	target["hit_shake_t"] = 0.2
	# #region agent log
	if attacker and not attacker.is_empty():
		var ash := str(attacker.get("ship_id", ""))
		if ash == "mmte_longjuanfeng" or str(attacker.get("ship_name", "")).find("龙卷") >= 0:
			_dbg59("DMG", "board_root.damage", "tornado_dealt", {
				"from": str(attacker.get("id", "")), "to": str(target.get("id", "")),
				"ship": ash, "raw_portion": portion, "dealt_hp": dealt_hp,
				"max_loss": max_loss, "resist": resist,
				"tgt_ship": str(target.get("ship_id", "")),
				"killed": bool(res.get("killed", false)),
				"runId": "tornado-cannon"
			})
	# #endregion
	if shield_before > 0.01 and float(inst["shield"]) <= 0.01:
		_focus_spend_stacks(target)
	if float(inst["shield"]) <= 0.01 and target.has("guard"):
		target["guard"]["field_on"] = false
	if float(inst["armor"]) <= 0.01 and target.has("guard"):
		target["guard"]["link_on"] = false
	if _fx_ok() and float_text and dealt_hp > 0.05:
		float_text.add_damage(target["pos"], dealt_hp, hash(str(target["id"])))
	if attacker and not attacker.is_empty():
		attacker["dealt_timer"] = 1.2
		if br_tracker and (dealt_hp > 0.05 or max_loss > 0.05):
			br_tracker.note_damage(attacker, target, max_loss)
	target["took_damage"] = dealt_hp > 0.05
	target["dealt_timer"] = 1.2
	if res["killed"]:
		if br_tracker:
			br_tracker.note_kill(attacker if attacker else {}, target)
		_kill_unit(target)
		_refresh_br_list()
	elif attacker and not attacker.is_empty():
		admin.request("combat.damage", {"from": attacker["id"], "to": target["id"], "raw": portion})
	return dealt_hp

func _restore_unit_max_loss(u: Dictionary, amount: float) -> float:
	## Restore max_* toward pristine_* by `amount` (structure → armor → shield). Returns restored total.
	if amount <= 0.0 or u.is_empty() or not u.has("inst"):
		return 0.0
	var inst: Dictionary = u["inst"]
	var rem := amount
	var restored := 0.0
	var layers: Array = [
		["max_h", "pristine_h"],
		["max_a", "pristine_a"],
		["max_s", "pristine_s"],
	]
	for pair in layers:
		if rem <= 0.0:
			break
		var mk := str(pair[0])
		var pk := str(pair[1])
		var cur_max := float(inst.get(mk, 0.0))
		var pris := float(inst.get(pk, cur_max))
		var room := maxf(0.0, pris - cur_max)
		if room <= 0.0:
			continue
		var add := minf(rem, room)
		inst[mk] = cur_max + add
		rem -= add
		restored += add
	return restored

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
			if _fx_ok() and float_text and hs > 0.05:
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
			if _fx_ok() and float_text and ha > 0.05:
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
	if _fx_ok() and float_text and heal > 0.05:
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
	## Periodic remote-state sample (full-pool must stay unlocked).
	if Engine.get_process_frames() % 120 == 0:
		for u2 in units:
			if not u2.get("alive", false):
				continue
			for w2 in u2.get("weapons", []):
				var k2 := str(w2.get("kind", ""))
				if k2 != "remote_armor" and k2 != "remote_shield":
					continue
				var lid := str(w2.get("lock_id", ""))
				var room_sum := 0.0
				for o2 in units:
					if not o2.get("alive", false):
						continue
					if int(o2["faction"]) != int(u2["faction"]) or o2["id"] == u2["id"]:
						continue
					if str(u2["sys"]) != str(o2["sys"]):
						continue
					room_sum += _remote_heal_room(o2, w2)
				# #region agent log
				_agent_dbg("RR1", "board_root._tick_weapon_locks", "remote_state", {
					"unit": str(u2.get("id", "")), "lock_id": lid,
					"lock_t": float(w2.get("lock_t", 0.0)),
					"ally_room_sum": room_sum,
					"idle_ok": lid == "" and room_sum <= 0.5,
					"runId": "post-fix"
				})
				# #endregion
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
			var is_rep_lock := str(w.get("kind", "")) == "remote_armor" or str(w.get("kind", "")) == "remote_shield"
			if is_rep_lock and _remote_heal_room(tgt, w) <= 0.5:
				## Target topped up — drop lock so remote does not stay "enabled".
				w["lock_id"] = ""
				w["lock_t"] = 0.0
				w["retarget_t"] = 0.0
				# #region agent log
				_agent_dbg("RR1", "board_root._tick_weapon_locks", "remote_skip_full", {
					"unit": str(u.get("id", "")), "was": str(tgt.get("id", "")),
					"kind": str(w.get("kind", "")), "runId": "post-fix"
				})
				# #endregion
				continue
			w["lock_need"] = 40000.0 / maxf(float(u["scan_res"]) * float(tgt["signature_radius"]), 1.0)
			## Lock timer advances only while same-sys and in weapon range (LANDING OK).
			if u["sys"] == tgt["sys"] and _weapon_in_range(u, tgt, w):
				w["lock_t"] = minf(float(w.get("lock_need", 1.0)), float(w.get("lock_t", 0.0)) + delta)
			## else: keep existing lock_t (do not reset)

func _unit_has_guard_fit(o: Dictionary) -> bool:
	var g: Dictionary = o.get("guard", {})
	return g.get("field_fitted", false) or g.get("link_fitted", false)

func _remote_heal_room(tgt: Dictionary, w: Dictionary) -> float:
	## Remaining pool for this remote module kind (armor / future shield).
	if tgt.is_empty() or not tgt.has("inst"):
		return 0.0
	var ti: Dictionary = tgt["inst"]
	var kind := str(w.get("kind", ""))
	if kind == "remote_armor":
		return maxf(0.0, float(ti.get("max_a", 0.0)) - float(ti.get("armor", 0.0)))
	if kind == "remote_shield":
		return maxf(0.0, float(ti.get("max_s", 0.0)) - float(ti.get("shield", 0.0)))
	return 0.0

func _pick_weapon_target(u: Dictionary, w: Dictionary) -> Dictionary:
	var best = {}
	var best_key = INF
	var best_guard = false
	var is_rep = str(w.get("kind", "")) == "remote_armor" or str(w.get("kind", "")) == "remote_shield"
	## Player attack order: prefer focus hostile (same sys) for damage weapons.
	if not is_rep:
		var focus = _unit_by_id(str(u.get("focus_id", "")))
		if focus and focus.get("alive", false) and int(focus["faction"]) != int(u["faction"]) \
				and str(u["sys"]) == str(focus["sys"]):
			return focus
	for o in units:
		if not o.get("alive", false):
			continue
		if is_rep:
			if int(o["faction"]) != int(u["faction"]) or o["id"] == u["id"]:
				continue
			## Full corresponding pool → never acquire / enable remote.
			if _remote_heal_room(o, w) <= 0.5:
				continue
		else:
			if int(o["faction"]) == int(u["faction"]):
				continue
			## Auto-attack skips non-same-cell NPC units (SHIPS §13).
			if bool(o.get("npc", false)) and int(o.get("cell", -2)) != int(u.get("cell", -1)):
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
			if str(w.get("kind", "")) == "remote_shield":
				key = float(ti["shield"]) / maxf(float(ti["max_s"]), 1.0)
			else:
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
	var is_rep_fire := str(w.get("kind", "")) == "remote_armor" or str(w.get("kind", "")) == "remote_shield"
	if is_rep_fire and _remote_heal_room(tgt, w) <= 0.5:
		# #region agent log
		_agent_dbg("RR1", "board_root._fire_weapon", "remote_abort_full", {
			"unit": str(u.get("id", "")), "tgt": str(tgt.get("id", "")),
			"room": _remote_heal_room(tgt, w), "runId": "post-fix"
		})
		# #endregion
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
		if heal <= 0.05:
			inst["cap"] += float(w.get("cap", 0))
			return
		tinst["armor"] = float(tinst["armor"]) + heal
		var imp: Dictionary = _implant_data(u)
		if imp.get("id", "") == "implant_armor_support" and u.get("implant", {}).get("auto_on", true):
			## +10% armor resist on healed target; does not stack on same target.
			if not tgt.get("armor_support_buff", false):
				tgt["armor_support_buff"] = true
				tinst["resist"] = int(tinst.get("resist", 0)) + int(imp.get("res_pct", 10))
		_play_turret_vfx(str(w.get("fx", "repair")), _vfx_endpoint(u), _vfx_endpoint(tgt))
		if _fx_ok() and float_text and heal > 0.05:
			float_text.add_heal(tgt["pos"], heal, hash(str(tgt["id"]) + "rr"))
		# #region agent log
		_agent_dbg("RR1", "board_root._fire_weapon", "remote_heal", {
			"unit": str(u.get("id", "")), "tgt": str(tgt.get("id", "")),
			"heal": heal, "runId": "post-fix"
		})
		# #endregion
		return
	## Tracking uses (cell steps + 1) meters, same as PD.
	var dist_m = _pd_tracking_distance_m(u, tgt)
	var tracking = float(w.get("tracking", 1))
	var raw = _weapon_raw(eq, w)
	var sn = _apply_sniper_mod(u, tracking, raw)
	tracking = float(sn["tracking"])
	raw = float(sn["raw"])
	var force_hit := bool(sn.get("force_hit", false))
	var p_hit = BoardCombatFormulas.turret_hit_chance(
		tracking, float(w.get("sig_res", 40)), float(w.get("falloff", 4000)),
		float(w.get("optimal", 0)), float(tgt["speed"]), float(tgt["signature_radius"]), dist_m
	)
	var hit = force_hit or rng.randf() <= p_hit
	raw = _focus_on_hit(u, hit, raw)
	if not hit or raw <= 0.0:
		return
	raw *= BoardCombatFormulas.roll_quality(rng)
	# #region agent log
	var ship_id_fire := str(u.get("ship_id", ""))
	var wref := str(w.get("ref", ""))
	if ship_id_fire == "mmte_longjuanfeng" or wref.begins_with("weapon_large_cannon"):
		_dbg59("DMG", "board_root._fire_weapon", "cannon_fire", {
			"ship": ship_id_fire, "name": str(u.get("ship_name", u.get("name", ""))),
			"ref": wref, "raw": raw, "p_hit": p_hit, "hit": hit, "force_hit": force_hit,
			"from": str(u.get("id", "")), "to": str(tgt.get("id", "")),
			"tgt_ship": str(tgt.get("ship_id", "")),
			"runId": "tornado-cannon"
		})
	# #endregion
	_apply_damage_to_unit(u, tgt, raw, int(tgt["inst"]["resist"]))
	_play_turret_vfx(str(w.get("fx", "laser")), _vfx_endpoint(u), _vfx_endpoint(tgt))

func _vfx_endpoint(u: Dictionary) -> Vector3:
	## Tactical top-down: plate↔plate (same or cross callout); battle view: ship pos.
	if cam and cam.tactical_mode and not cam.starmap_mode:
		var uid := str(u.get("id", ""))
		if unit_nodes.has(uid):
			var oh = unit_nodes[uid].get_node_or_null("Overhead") as Node3D
			if oh != null and is_instance_valid(oh):
				var gp: Vector3 = oh.global_position
				if gp.length_squared() > 0.01:
					# #region agent log
					if Engine.get_process_frames() % 120 == 0:
						_dbg59("VFX", "board_root._vfx_endpoint", "plate", {
							"uid": uid, "y": gp.y, "runId": "vfx-plate"
						})
					# #endregion
					return gp
	return u.get("pos", Vector3.ZERO) as Vector3

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
	_world_env = env
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
	starmap_view.mesh_inst = mi
	add_child(starmap_view)
	# camera
	cam = BoardCamera.new()
	cam.name = "BoardCamera"
	var c3 = Camera3D.new()
	c3.name = "Camera3D"
	c3.current = true
	cam.add_child(c3)
	add_child(cam)
	if not cam.tactical_changed.is_connected(_on_tactical_changed):
		cam.tactical_changed.connect(_on_tactical_changed)
	if cam.has_signal("view_tier_changed") and not cam.view_tier_changed.is_connected(_on_view_tier_changed):
		cam.view_tier_changed.connect(_on_view_tier_changed)
	if cam.has_signal("starmap_changed") and not cam.starmap_changed.is_connected(_on_starmap_changed):
		cam.starmap_changed.connect(_on_starmap_changed)
	cam.block_input_fn = func() -> bool:
		return _mouse_over_blocking_hud(get_viewport().get_mouse_position())
	tactical_callouts = CALLOUT_SCR.new()
	tactical_callouts.name = "TacticalCallouts"
	tactical_callouts.setup(map, starmap_view)
	tactical_callouts.font_scale = TACTICAL_FONT_SCALE
	BoardUnitOverhead.font_scale = TACTICAL_FONT_SCALE
	tactical_callouts.set_active(false)
	add_child(tactical_callouts)
	if starmap_view:
		starmap_view.set_camera(c3)
	starmap_view.set_icon_scale(TACTICAL_ICON_SCALE)
	starmap_view.set_border_jagged(TACTICAL_BORDER_JAGGED)
	starmap_view.set_system_name_scale(TACTICAL_SYSNAME_SCALE)
	if starmap_view.has_method("set_starmap_name_scale"):
		starmap_view.set_starmap_name_scale(starmap_name_scale)
	if starmap_view.has_method("set_starmap_icon_scale"):
		starmap_view.set_starmap_icon_scale(starmap_icon_scale)
	if starmap_view.has_method("set_starmap_badge_scale"):
		starmap_view.set_starmap_badge_scale(starmap_badge_scale)
	if starmap_view.has_method("set_starmap_count_scale"):
		starmap_view.set_starmap_count_scale(starmap_count_scale)
	if starmap_view.has_method("set_view_tier"):
		starmap_view.set_view_tier("battle")
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
	if unit_nodes.has(u["id"]):
		return
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
	## Garrison sleepers are never LMB-selectable; keep PickBody inert.
	var can_pick := not bool(u.get("garrison", false)) and bool(u.get("commandable", true))
	body.collision_layer = 1 if can_pick else 0
	body.collision_mask = 0
	if can_pick:
		body.set_collision_layer_value(1, true)
	body.set_collision_layer_value(2, false)
	body.set_meta("unit_id", u["id"])
	var col = CollisionShape3D.new()
	## Flat disk pick (planar), not a tall sphere — stack logic is XZ-only.
	var shape = CylinderShape3D.new()
	shape.radius = target_r
	shape.height = 0.35
	col.shape = shape
	col.position = Vector3(0, 0.0, 0)
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
	## Art module spawn — unshaded fixed look, immune to board lights/env (no white film).
	var def: Dictionary = data.ship_def(u["ship_id"])
	var model_key = str(def.get("model", u["ship_id"]))
	if SHIP_ART.has_model(model_key):
		var inst: Node3D = SHIP_ART.spawn_model(n, model_key, target_d)
		if inst:
			mesh.visible = false
			call_deferred("_reapply_art_model", inst, model_key)
			# #region agent log
			var yaw_art: float = SHIP_ART.bow_yaw_deg(model_key)
			var yaw_legacy: float = _model_bow_yaw_deg(model_key)
			_agent_dbg("BOW", "board_root.spawn_model", "yaw_check", {
				"ship": str(u.get("ship_id", "")), "model": model_key,
				"yaw_art": yaw_art, "yaw_legacy": yaw_legacy,
				"match": is_equal_approx(yaw_art, yaw_legacy),
				"applied_deg": yaw_art, "runId": "post-fix"
			})
			# #endregion
	# pick disk fixed — never inherit broken AABB (BH-04 / BH-08)
	shape.radius = clampf(target_r * 0.85, 1.2, 3.5)
	shape.height = 0.35
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
		if mesh_i.material_override == null:
			continue
		## Art-module ships use ShaderMaterial — never replace (was wiping to white film).
		var smat := mesh_i.material_override as ShaderMaterial
		if smat != null:
			smat.set_shader_parameter("combat_emission_strength", 1.35 if on else 0.0)
			# #region agent log
			if Engine.get_process_frames() % 90 == 0:
				_agent_dbg("H5", "board_root._set_model_hit_flash", "keep_shader", {
					"on": on, "runId": "post-fix"
				})
			# #endregion
			continue
		var mat = mesh_i.material_override as StandardMaterial3D
		if mat == null:
			continue
		if not mesh_i.has_meta("flash_base"):
			mesh_i.set_meta("flash_base", mat.albedo_color)
		var base_c: Color = mesh_i.get_meta("flash_base")
		mat.albedo_color = base_c.lerp(Color(1, 1, 1, 1), 0.75) if on else base_c

func _reapply_art_model(inst: Node, model_key: String) -> void:
	if inst == null or not is_instance_valid(inst):
		return
	var tag: String = SHIP_ART.apply_fixed_material(inst, model_key)
	# #region agent log
	_agent_dbg("H5", "board_root._reapply_art_model", "albedo", {
		"model": model_key, "shade": tag, "runId": "post-fix"
	})
	# #endregion

func _rel_for(fac: int) -> String:
	if int(fac) == int(viewer_faction):
		return "self"
	var rels: Dictionary = data.diplomacy.get("relations", {}).get(str(viewer_faction), {})
	return str(rels.get(str(fac), "hostile"))


func _ui_cjk_font() -> Font:
	if _ui_font != null:
		return _ui_font
	if ResourceLoader.exists(UI_FONT_PATH):
		_ui_font = load(UI_FONT_PATH) as Font
	if _ui_font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC"])
		_ui_font = sf
	return _ui_font

func _apply_ui_font(ctrl: Control) -> void:
	if ctrl == null:
		return
	var f := _ui_cjk_font()
	if f == null:
		return
	ctrl.add_theme_font_override("font", f)
	## Propagate to common Control types that ignore parent theme font.
	if ctrl is Label or ctrl is Button or ctrl is RichTextLabel or ctrl is LineEdit:
		pass

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	var layer = Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(layer)
	var theme := Theme.new()
	var fnt := _ui_cjk_font()
	if fnt:
		theme.default_font = fnt
		theme.set_default_font_size(15)
	layer.theme = theme
	left_col = VBoxContainer.new()
	left_col.name = "LeftCol"
	left_col.position = Vector2(8, 8)
	left_col.mouse_filter = Control.MOUSE_FILTER_STOP
	left_col.add_theme_constant_override("separation", 6)
	if fnt:
		left_col.theme = theme
	# #region agent log
	_dbg59("UI", "board_root._build_hud", "cjk_font", {
		"path": UI_FONT_PATH, "ok": fnt != null, "runId": "ui-fix"
	})
	# #endregion
	_layout_left_col()
	if not get_viewport().size_changed.is_connected(_layout_left_col):
		get_viewport().size_changed.connect(_layout_left_col)
	all_prod_btn = Button.new()
	all_prod_btn.name = "AllToProdBtn"
	all_prod_btn.text = "全体制造当前驾驶舰船"
	all_prod_btn.custom_minimum_size = Vector2(0, 32)
	all_prod_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	all_prod_btn.pressed.connect(_on_all_current_ships_to_prod)
	_apply_ui_font(all_prod_btn)
	left_col.add_child(all_prod_btn)
	auto_launch_btn = Button.new()
	auto_launch_btn.name = "AutoLaunchBtn"
	auto_launch_btn.custom_minimum_size = Vector2(0, 32)
	auto_launch_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	auto_launch_btn.toggle_mode = true
	auto_launch_btn.set_pressed_no_signal(auto_launch_enabled)
	_refresh_auto_launch_btn()
	auto_launch_btn.toggled.connect(_on_auto_launch_toggled)
	_apply_ui_font(auto_launch_btn)
	left_col.add_child(auto_launch_btn)
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
	sync_move_btn.toggle_mode = true
	sync_move_btn.set_pressed_no_signal(sync_move_enabled)
	_refresh_sync_move_btn()
	sync_move_btn.toggled.connect(_on_sync_move_toggled)
	_apply_ui_font(sync_move_btn)
	left_col.add_child(sync_move_btn)
	layer.add_child(left_col)
	_layout_left_col()
	_apply_baked_view_tune()
	BoardUnitOverhead.cd_bar_px = 20.0
	## Re-sync labels after layout (avoid first-frame text/state mismatch).
	call_deferred("_refresh_left_state_toggles")
	# #region agent log
	_dbg59("CDB", "board_root._build_hud", "cd_bar_fixed", {
		"px": BoardUnitOverhead.cd_bar_px,
		"name_y": BoardUnitOverhead.battle_nameplate_y,
		"runId": "nameplate-y"
	})
	# #endregion
	# keep ItemList stub for any legacy refs
	left_list = ItemList.new()
	left_list.visible = false
	layer.add_child(left_list)
	var right_col = VBoxContainer.new()
	right_col.name = "RightCol"
	right_col.mouse_filter = Control.MOUSE_FILTER_STOP
	right_col.add_theme_constant_override("separation", 6)
	if fnt:
		right_col.theme = theme
	## 战报在上、详情在下（UI_AND_SHELL §3）。
	var br_title = Label.new()
	br_title.text = "战报"
	br_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_ui_font(br_title)
	right_col.add_child(br_title)
	var br_scroll = ScrollContainer.new()
	br_scroll.name = "BrScroll"
	br_scroll.custom_minimum_size = Vector2(300, 160)
	br_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	br_list = VBoxContainer.new()
	br_list.name = "BrList"
	br_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br_list.add_theme_constant_override("separation", 4)
	br_scroll.add_child(br_list)
	right_col.add_child(br_scroll)
	detail = RichTextLabel.new()
	detail.name = "Detail"
	detail.custom_minimum_size = Vector2(300, 280)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.bbcode_enabled = true
	detail.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_ui_font(detail)
	right_col.add_child(detail)
	layer.add_child(right_col)
	_layout_right_col()
	if not get_viewport().size_changed.is_connected(_layout_right_col):
		get_viewport().size_changed.connect(_layout_right_col)
	_ensure_br_window()
	_refresh_br_list()
	mouse_hint = Label.new()
	mouse_hint.name = "MouseHint"
	mouse_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_hint.text = "中键平移/旋转 | 滚轮缩放 | 中键+滚轮转俯视 | 左键框选/移动/攻击 | 右键空地取消选中"
	mouse_hint.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
	mouse_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.1, 0.9))
	mouse_hint.add_theme_constant_override("outline_size", 4)
	_apply_ui_font(mouse_hint)
	layer.add_child(mouse_hint)
	_mouse_hint_life = 10.0
	_layout_mouse_hint()

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
		## UI: only alive ship art/tonnage. last_ship is code-only (UI_AND_SHELL §2).
		var sid = _pilot_alive_ship_id(p)
		_refresh_pilot_row_ship_art(row, sid)
		_refresh_pilot_row_tonnage(row, p)
		_refresh_pilot_row_group_badge(row, p)
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
	## Min height only — grows with manufacture bars / text (no clip).
	row.custom_minimum_size = Vector2(340, 72)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.clip_contents = false
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pid = str(p["id"])
	var row_style = StyleBoxFlat.new()
	## Transparent plate — tips_skybox carries fill + right fade.
	row_style.bg_color = Color(0.08, 0.09, 0.12, 0.08)
	row_style.set_border_width_all(0)
	row.add_theme_stylebox_override("panel", row_style)
	## MarginContainer: all children share content rect; HBox drives height.
	var row_wrap = MarginContainer.new()
	row_wrap.name = "RowWrap"
	row_wrap.custom_minimum_size = Vector2(340, 0)
	row_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_wrap.add_theme_constant_override("margin_left", 6)
	row_wrap.add_theme_constant_override("margin_right", 6)
	row_wrap.add_theme_constant_override("margin_top", 4)
	row_wrap.add_theme_constant_override("margin_bottom", 4)
	row.add_child(row_wrap)
	var row_sky = TextureRect.new()
	row_sky.name = "RowSky"
	row_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	## SCALE fills row; pic+fade shader — COVERED was cropping into transparent fade edge.
	row_sky.stretch_mode = TextureRect.STRETCH_SCALE
	row_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row_sky.modulate = Color(1, 1, 1, 1)
	row_sky.material = SHIP_ART.tips_sky_material()
	row_wrap.add_child(row_sky)
	row.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			var mb = ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var row_u = _unit_by_id(str(p.get("unit_id", "")))
				if row_u:
					selection = [row_u["id"]]
					_update_detail()
					## Tactical (not 星图): LMB on pilot auto-follows ship world pos.
					if cam and cam.tactical_mode and not cam.starmap_mode and row_u.get("alive", false):
						cam.set_follow(str(row_u["id"]))
						cam.update_follow_pos(row_u["pos"])
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_open_pilot_menu(p, get_viewport().get_mouse_position())
	)
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.clip_contents = false
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row_wrap.add_child(hb)
	var ton := ""
	var u = _unit_by_id(str(p.get("unit_id", "")))
	var ship_name := ""
	var ship_id := _pilot_alive_ship_id(p)
	if u and u.get("alive", false):
		ton = str(u.get("tonnage", ""))
		ship_name = str(u.get("name", ""))
	var rsky = row.find_child("RowSky", true, false) as TextureRect
	if rsky:
		rsky.texture = _ship_sky_tex(ship_id) if ship_id != "" else null
	var ton_rect = TextureRect.new()
	ton_rect.name = "TonnageIcon"
	ton_rect.custom_minimum_size = Vector2(32, 32)
	ton_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ton_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ton_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ton != "":
		ton_rect.texture = _tonnage_icon(ton)
		ton_rect.visible = true
	else:
		ton_rect.texture = null
		ton_rect.visible = false
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
	sky_bg.stretch_mode = TextureRect.STRETCH_SCALE
	sky_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_bg.texture = null
	sky_bg.modulate = Color(1, 1, 1, 1)
	sky_bg.material = SHIP_ART.tips_sky_material()
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
		portrait.visible = true
	else:
		portrait.texture = null
		portrait.visible = false
	frame.add_child(portrait)
	frame.set_meta("ship_id", ship_id)
	hb.add_child(frame)
	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	var l1 = Label.new()
	l1.name = "PilotTitle"
	l1.text = "%s  %s" % [p["name"], ship_name]
	l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_ui_font(l1)
	vb.add_child(l1)
	# #region agent log
	if str(p.get("id", "")) == "p1_lind":
		_dbg59("UI", "board_root._make_pilot_row", "title_text", {
			"name": str(p.get("name", "")), "ship": ship_name,
			"cp0": (str(p.get("name", "")) as String).unicode_at(0) if str(p.get("name", "")).length() > 0 else -1,
			"runId": "ui-fix"
		})
	# #endregion
	var grp_lab = Label.new()
	grp_lab.name = "GroupBadge"
	grp_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grp_lab.add_theme_font_size_override("font_size", 14)
	grp_lab.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35, 1))
	_apply_ui_font(grp_lab)
	vb.add_child(grp_lab)
	_refresh_pilot_row_group_badge(row, p)
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
	_apply_ui_font(l2)
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
	## 全体：当前驾驶舰 → 产线；无船时回退 last_ship_id
	var n = 0
	var started = 0
	var used_last = 0
	for p in pilots:
		if int(p.get("faction", 0)) != viewer_faction:
			continue
		var u = _unit_by_id(str(p.get("unit_id", "")))
		var sid := ""
		var ton := ""
		if u and u.get("alive", false):
			sid = str(u.get("ship_id", ""))
			ton = str(u.get("tonnage", data.ship_def(sid).get("tonnage", "")))
		else:
			sid = str(p.get("last_ship_id", ""))
			ton = str(p.get("last_ship_tonnage", data.ship_def(sid).get("tonnage", "")))
			if sid != "":
				used_last += 1
		if sid == "" or ton == "":
			continue
		pilots_sys.set_auto(p, ton, sid)
		n += 1
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
			btn.text = "全体制造：无可用舰船"
		else:
			btn.text = "已写入产线 ×%d（开工 %d）" % [n, started]
		get_tree().create_timer(2.2).timeout.connect(_reset_all_prod_btn_text)
	# #region agent log
	_dbg59("SHIP", "board_root.all_to_prod", "set_auto", {
		"count": n, "started": started, "used_last": used_last, "runId": "last-ship"
	})
	_agent_dbg("A5", "board_root.all_to_prod", "set_auto", {
		"count": n, "started": started,
		"btn": btn != null, "label": (btn.text if btn else ""),
		"runId": "post-fix"
	})
	# #endregion

func _reset_all_prod_btn_text() -> void:
	if all_prod_btn and is_instance_valid(all_prod_btn):
		all_prod_btn.text = "全体制造当前驾驶舰船"

func _on_auto_launch_toggled(on: bool) -> void:
	auto_launch_enabled = on
	_refresh_auto_launch_btn()
	# #region agent log
	_dbg59("LAUNCH", "board_root.auto_launch", "toggle", {
		"on": auto_launch_enabled, "runId": "auto-launch"
	})
	# #endregion

func _refresh_auto_launch_btn() -> void:
	if auto_launch_btn == null:
		return
	## UI_AND_SHELL §2.1: label = current state (default 开).
	auto_launch_btn.text = "自动出航（%s）" % ("开" if auto_launch_enabled else "关")
	if auto_launch_btn.toggle_mode:
		auto_launch_btn.set_pressed_no_signal(auto_launch_enabled)

func _tick_auto_launch() -> void:
	if not auto_launch_enabled:
		return
	for p in pilots:
		if int(p.get("faction", 0)) != viewer_faction:
			continue
		if str(p.get("unit_id", "")) != "":
			continue
		var cs: String = str(p.get("current_station", ""))
		if cs == "" or not map.systems.has(cs):
			continue
		var prefer := str(p.get("last_ship_id", ""))
		var counts = pilots_sys.storage_count_by_model(p)
		var ship_id := ""
		if prefer != "" and int(counts.get(prefer, 0)) > 0:
			ship_id = prefer
		elif prefer != "":
			## Prefer last ship: wait until that model is manufactured (do not launch others).
			continue
		elif not counts.is_empty():
			ship_id = str(counts.keys()[0])
		else:
			continue
		_launch_pilot(p, ship_id)
		# #region agent log
		_dbg59("LAUNCH", "board_root._tick_auto_launch", "launch", {
			"pilot": str(p.get("id", "")), "ship": ship_id, "prefer": prefer, "runId": "auto-launch"
		})
		# #endregion

func _tick_mouse_hint(delta: float) -> void:
	if mouse_hint == null or not is_instance_valid(mouse_hint):
		return
	if _mouse_hint_life <= 0.0:
		if mouse_hint.visible:
			mouse_hint.visible = false
		return
	_mouse_hint_life = maxf(0.0, _mouse_hint_life - delta)
	mouse_hint.visible = true
	## Pulse alpha while alive; snuff out when timer ends.
	var pulse := 0.45 + 0.55 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * MOUSE_HINT_FLASH_HZ))
	if _mouse_hint_life < 1.0:
		pulse *= _mouse_hint_life
	mouse_hint.modulate = Color(1, 1, 1, pulse)
	if _mouse_hint_life <= 0.0:
		mouse_hint.visible = false


func _apply_baked_view_tune() -> void:
	## Persist + apply last accepted tune values as code defaults (no HUD).
	if cam:
		cam.set_zoom_thresholds(485.0, 360.0, 1400.0, 3090.0)
	starmap_name_scale = 6.55
	starmap_icon_scale = 2.6
	starmap_badge_scale = 10.05
	starmap_count_scale = 8.55
	if starmap_view:
		if starmap_view.has_method("set_starmap_name_scale"):
			starmap_view.set_starmap_name_scale(starmap_name_scale)
		if starmap_view.has_method("set_starmap_icon_scale"):
			starmap_view.set_starmap_icon_scale(starmap_icon_scale)
		if starmap_view.has_method("set_starmap_badge_scale"):
			starmap_view.set_starmap_badge_scale(starmap_badge_scale)
		if starmap_view.has_method("set_starmap_count_scale"):
			starmap_view.set_starmap_count_scale(starmap_count_scale)
	var cf := ConfigFile.new()
	cf.set_value("view_tune", "dist_max", 485.0)
	cf.set_value("view_tune", "tac_min", 360.0)
	cf.set_value("view_tune", "starmap_enter", 1400.0)
	cf.set_value("view_tune", "height_max", 3090.0)
	cf.set_value("view_tune", "starmap_name_scale", starmap_name_scale)
	cf.set_value("view_tune", "starmap_icon_scale", starmap_icon_scale)
	cf.set_value("view_tune", "starmap_badge_scale", starmap_badge_scale)
	cf.set_value("view_tune", "starmap_count_scale", starmap_count_scale)
	var err := cf.save("user://evetbs_board_view_tune.cfg")
	# #region agent log
	_dbg59("BAKE", "board_root._apply_baked_view_tune", "baked", {
		"err": err, "dist_max": 485.0, "tac_min": 360.0, "starmap_enter": 1400.0,
		"height_max": 3090.0, "name": starmap_name_scale, "icon": starmap_icon_scale,
		"badge": starmap_badge_scale, "count": starmap_count_scale, "runId": "bake-remove-hud"
	})
	# #endregion
	_layout_mouse_hint()


func _layout_mouse_hint() -> void:
	if mouse_hint == null or not is_instance_valid(mouse_hint):
		return
	var vr := get_viewport().get_visible_rect().size
	mouse_hint.position = Vector2(380, 8.0)
	mouse_hint.size = Vector2(maxf(vr.x - 700.0, 420.0), 28.0)


func _restore_game_mouse() -> void:
	## Tier jumps / focus can leave an invisible or captured cursor (BH-37).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if cam:
		cam.rotating = false
		cam.panning = false


func _layout_left_col() -> void:
	if left_col == null or not is_instance_valid(left_col):
		return
	## Top–bottom docked; at 1920×1280 baseline ~15 pilot rows fit in the scroll area.
	var vh = get_viewport().get_visible_rect().size.y
	left_col.position = Vector2(8, 8)
	left_col.size = Vector2(360, maxf(vh - 16.0, 200.0))
	if left_scroll:
		left_scroll.custom_minimum_size = Vector2(360, 120)
		left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_mouse_hint()

func _layout_right_col() -> void:
	var layer = hud.get_child(0) if hud else null
	if layer == null:
		return
	var right_col = layer.find_child("RightCol", true, false) as Control
	if right_col == null:
		return
	var vr = get_viewport().get_visible_rect().size
	right_col.position = Vector2(vr.x - 316.0, 8.0)
	right_col.size = Vector2(300.0, maxf(vr.y - 16.0, 200.0))

func _ensure_br_window() -> void:
	if br_window != null and is_instance_valid(br_window):
		return
	br_window = Window.new()
	br_window.title = "战报"
	br_window.size = Vector2i(980, 600)
	br_window.visible = false
	br_window.close_requested.connect(func(): br_window.hide())
	add_child(br_window)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	br_window.add_child(margin)
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	br_body = RichTextLabel.new() ## kept for compatibility; table uses VBox below
	br_body.visible = false
	var vbox = VBoxContainer.new()
	vbox.name = "BrBodyVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

func _br_body_vbox() -> VBoxContainer:
	_ensure_br_window()
	return br_window.find_child("BrBodyVBox", true, false) as VBoxContainer

func _refresh_br_list() -> void:
	if br_list == null or br_tracker == null:
		return
	for c in br_list.get_children():
		c.queue_free()
	for sys in br_tracker.active.keys():
		var sess: Dictionary = br_tracker.active[sys]
		var btn = Button.new()
		var t_on := "进行中 · %s" % str(sess.get("sys_name", sys))
		btn.text = t_on
		btn.tooltip_text = t_on
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = false
		_apply_ui_font(btn)
		btn.disabled = true
		br_list.add_child(btn)
	## Newest first
	var n = br_tracker.closed.size()
	for i in range(n - 1, -1, -1):
		var rep: Dictionary = br_tracker.closed[i]
		var btn2 = Button.new()
		var st = br_tracker.format_clock(float(rep.get("start_t", 0)))
		var et = br_tracker.format_clock(float(rep.get("end_t", 0)))
		var t_closed := "%s  %s–%s  我损%d/敌损%d" % [
			str(rep.get("sys_name", rep.get("sys", "?"))), st, et,
			int(rep.get("mine_lost", 0)), int(rep.get("foe_lost", 0))
		]
		btn2.text = t_closed
		btn2.tooltip_text = t_closed
		btn2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn2.clip_text = false
		_apply_ui_font(btn2)
		var rid = str(rep.get("id", ""))
		btn2.pressed.connect(_open_br_report.bind(rid))
		br_list.add_child(btn2)

func _br_tonnage_badge_cell(ton: String, fac: int) -> Control:
	var cell_ui = Control.new()
	cell_ui.custom_minimum_size = Vector2(36, 36)
	var bg = TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ton_r = TextureRect.new()
	ton_r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ton_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ton_r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ton_r.offset_left = 4
	ton_r.offset_top = 4
	ton_r.offset_right = -4
	ton_r.offset_bottom = -4
	var badge = TextureRect.new()
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.custom_minimum_size = Vector2(14, 14)
	badge.position = Vector2(22, 22)
	badge.size = Vector2(14, 14)
	var ov = _tonnage_overlay_set(_rel_for(fac))
	if ov.get("bg"):
		bg.texture = ov["bg"]
	ton_r.texture = _tonnage_icon(ton)
	if ov.get("badge"):
		badge.texture = ov["badge"]
	cell_ui.add_child(bg)
	cell_ui.add_child(ton_r)
	cell_ui.add_child(badge)
	return cell_ui

func _open_br_report(report_id: String) -> void:
	_ensure_br_window()
	var rep: Dictionary = {}
	for r in br_tracker.closed:
		if str(r.get("id", "")) == report_id:
			rep = r
			break
	if rep.is_empty():
		return
	var vbox := _br_body_vbox()
	if vbox == null:
		return
	for c in vbox.get_children():
		c.queue_free()
	var st = br_tracker.format_clock(float(rep.get("start_t", 0)))
	var et = br_tracker.format_clock(float(rep.get("end_t", 0)))
	var head_row = HBoxContainer.new()
	head_row.alignment = BoxContainer.ALIGNMENT_CENTER
	head_row.add_theme_constant_override("separation", 10)
	var left_h = Label.new()
	left_h.text = "我方 %d舰 · 损失 %d舰 · 吨位%d" % [
		int(rep.get("mine_ships", 0)), int(rep.get("mine_lost", 0)), int(rep.get("mine_ton", 0))
	]
	left_h.add_theme_font_size_override("font_size", 16)
	_apply_ui_font(left_h)
	var vs_h = Label.new()
	vs_h.text = "vs"
	vs_h.add_theme_font_size_override("font_size", 28)
	vs_h.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
	_apply_ui_font(vs_h)
	var right_h = Label.new()
	right_h.text = "敌方 %d舰 · 损失 %d舰 · 吨位%d" % [
		int(rep.get("foe_ships", 0)), int(rep.get("foe_lost", 0)), int(rep.get("foe_ton", 0))
	]
	right_h.add_theme_font_size_override("font_size", 16)
	_apply_ui_font(right_h)
	head_row.add_child(left_h)
	head_row.add_child(vs_h)
	head_row.add_child(right_h)
	vbox.add_child(head_row)
	var meta = Label.new()
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.text = "%s — %s · %s" % [st, et, str(rep.get("sys_name", ""))]
	_apply_ui_font(meta)
	vbox.add_child(meta)
	var grid = GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.custom_minimum_size = Vector2(920, 0)
	vbox.add_child(grid)
	for h in ["参战驾驶员", "吨位", "驾驶舰船", "造成上限降低", "受到上限降低", "击毁舰船数", "星系内停留时长"]:
		var hl = Label.new()
		hl.text = h
		hl.add_theme_font_size_override("font_size", 13)
		_apply_ui_font(hl)
		grid.add_child(hl)
	var row_n := 0
	for row in rep.get("rows", []):
		row_n += 1
		var name_l = Label.new()
		name_l.text = str(row.get("pilot_name", "?"))
		if bool(row.get("destroyed", false)):
			name_l.text += " ·击毁"
		_apply_ui_font(name_l)
		grid.add_child(name_l)
		grid.add_child(_br_tonnage_badge_cell(str(row.get("tonnage", "destroyer")), int(row.get("faction", 0))))
		var ship_l = Label.new()
		ship_l.text = str(row.get("ship_name", "?"))
		_apply_ui_font(ship_l)
		grid.add_child(ship_l)
		for key in ["max_loss_dealt", "max_loss_taken"]:
			var nl = Label.new()
			nl.text = str(int(round(float(row.get(key, 0)))))
			_apply_ui_font(nl)
			grid.add_child(nl)
		var kl = Label.new()
		kl.text = str(int(row.get("kills", 0)))
		_apply_ui_font(kl)
		grid.add_child(kl)
		var sl = Label.new()
		sl.text = "%0.1fs" % float(row.get("stay_s", 0))
		_apply_ui_font(sl)
		grid.add_child(sl)
	vbox.custom_minimum_size = Vector2(940, 0)
	br_window.title = "战报 · %s" % str(rep.get("sys_name", ""))
	br_window.popup_centered()
	# #region agent log
	_dbg59("BR", "board_root.open_br", "open", {
		"id": report_id, "rows": row_n,
		"mine": int(rep.get("mine_ships", 0)), "foe": int(rep.get("foe_ships", 0)),
		"runId": "br-wire"
	})
	# #endregion

func _on_sync_move_toggled(on: bool) -> void:
	sync_move_enabled = on
	if not sync_move_enabled:
		_clear_all_sync_gids()
	_refresh_sync_move_btn()
	# #region agent log
	_agent_dbg("S7", "board_root.sync_move", "toggle", {"on": sync_move_enabled, "runId": "post-fix"})
	# #endregion

func _refresh_sync_move_btn() -> void:
	if sync_move_btn == null:
		return
	## UI_AND_SHELL §2.1: label = current state (default 关).
	sync_move_btn.text = "单位同步移动（%s）" % ("开" if sync_move_enabled else "关")
	if sync_move_btn.toggle_mode:
		sync_move_btn.set_pressed_no_signal(sync_move_enabled)

func _refresh_left_state_toggles() -> void:
	_refresh_auto_launch_btn()
	_refresh_sync_move_btn()

func _clear_all_sync_gids() -> void:
	for o in units:
		if o.has("sync_gid"):
			o.erase("sync_gid")

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
	## EveAC files use camelCase for some keys (battleCruiser).
	var aliases := {
		"battlecruiser": "battleCruiser",
		"industrial_command": "industrialCommand",
		"force_auxiliary": "force_auxiliary",
	}
	var file_key: String = str(aliases.get(ton, ton))
	var path = "res://assets/ui/sprites/tonnage/%s_32.png" % file_key
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/sprites/tonnage/%s_32.png" % ton
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/sprites/tonnage/destroyer_32.png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tonnage_tex[ton] = tex
	return tex

func _tonnage_overlay_set(rel: String) -> Dictionary:
	# EveAC allegiances from local viewer POV; fleet uses user-provided corp assets.
	var key = "friendly"
	if rel == "self" or rel == "fleet" or rel == "allied":
		key = "fleet"
	elif rel == "hostile" or rel == "enemy":
		key = "enemy"
	elif rel == "friendly" or rel == "neutral":
		key = "friendly"
	var sets = {
		"fleet": {"bg": "08_corp_standing_bg.png", "badge": "07_corp_fleet_badge.png"},
		"enemy": {"bg": "02_red_bg.png", "badge": "01_red_minus_badge.png"},
		"friendly": {"bg": "05_blue_bg.png", "badge": "06_friendly_badge.png"},
	}
	var conf: Dictionary = sets.get(key, sets["friendly"])
	var out = {"bg": null, "badge": null}
	for k2 in ["bg", "badge"]:
		var p2 = "res://assets/ui/sprites/tonnage_overlays/%s" % conf[k2]
		## Fallback to EveAC fleet pair if corp assets missing.
		if not ResourceLoader.exists(p2) and key == "fleet":
			p2 = "res://assets/ui/sprites/tonnage_overlays/%s" % (
				"04_fleet_member_bg.png" if k2 == "bg" else "03_fleet_member.png"
			)
		if ResourceLoader.exists(p2):
			out[k2] = load(p2)
	return out

func _ship_tips_race(ship_id: String) -> String:
	## Map hull → empire tips key (EveAC pirate→empire fallback).
	match ship_id:
		"jdl_haiyan", "gila_cc2":
			return "caldari"
		"jmh_sitexiusi", "ss_youling":
			return "amarr"
		"mmte_longjuanfeng":
			return "minmatar"
		_:
			return "gallente"

func _ship_sky_tex(ship_id: String) -> Texture2D:
	## tips_*_pic baked alpha≈0.45 — force opaque RGB; fade shader handles right edge.
	if ship_id == "":
		return null
	var race := _ship_tips_race(ship_id)
	var path: String = SHIP_ART.tips_sky_pic_path(race)
	if _tips_fade_cache.has(path):
		return _tips_fade_cache[path]
	var abs_path := ProjectSettings.globalize_path(path)
	var img := Image.new()
	var loaded := false
	if FileAccess.file_exists(abs_path) and img.load(abs_path) == OK:
		loaded = true
	elif ResourceLoader.exists(path):
		var t0: Texture2D = load(path) as Texture2D
		if t0:
			img = t0.get_image()
			loaded = img != null
	if not loaded:
		return null
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			c.a = 1.0
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_tips_fade_cache[path] = tex
	# #region agent log
	_agent_dbg("SKY", "board_root._ship_sky_tex", "opaque_pic", {
		"race": race, "w": img.get_width(), "h": img.get_height(), "runId": "post-fix"
	})
	# #endregion
	return tex

func _refresh_pilot_row_ship_art(row: Control, ship_id: String) -> void:
	if row == null:
		return
	var rsky = row.find_child("RowSky", true, false) as TextureRect
	if rsky:
		rsky.texture = _ship_sky_tex(ship_id) if ship_id != "" else null
		rsky.material = SHIP_ART.tips_sky_material()
		rsky.stretch_mode = TextureRect.STRETCH_SCALE
		rsky.modulate = Color(1, 1, 1, 1)
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
		sky.material = SHIP_ART.tips_sky_material()
		sky.stretch_mode = TextureRect.STRETCH_SCALE
		sky.modulate = Color(1, 1, 1, 1)
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
		return "无归属"
	return str(map.systems[h]["name"])

func _home_label_for_unit(u: Dictionary, p: Dictionary) -> String:
	## Sleepers have no home station: leave blank (SHIPS 11 / UI 3).
	if bool(u.get("garrison", false)) or bool(u.get("npc", false)):
		return ""
	return _home_label(p)

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
	_tick_mouse_hint(delta)
	_consume_lmb_gesture()
	_consume_rmb_order()
	# #region agent log
	if Engine.get_process_frames() % 45 == 0:
		var mp := get_viewport().get_mouse_position() if get_viewport() else Vector2.ZERO
		var fo2 = get_viewport().gui_get_focus_owner() if get_viewport() else null
		var blocked := _mouse_over_blocking_hud(mp)
		_dbg59("M2", "board_root._process", "mouse_watch", {
			"mode": int(Input.mouse_mode), "blocked": blocked,
			"rmb_down": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),
			"mp": {"x": mp.x, "y": mp.y},
			"focus": str(fo2.get_path()) if fo2 else "",
			"rot": cam.rotating if cam else false, "pan": cam.panning if cam else false,
			"hint_vis": mouse_hint.visible if mouse_hint else false,
			"hint_a": mouse_hint.modulate.a if mouse_hint else -1.0,
			"runId": "mouse-pre"
		})
		## BH-37: any non-visible mode is a critical regression signal.
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			_dbg59("M1", "board_root._process", "MOUSE_CAPTURE_VIOLATION", {
				"mode": int(Input.mouse_mode), "runId": "mouse-pre"
			})
	# #endregion
	if match_over:
		return
	pilots_sys.tick_build(pilots, delta, map)
	_tick_auto_launch()
	_drain_order_queue(2)
	_tick_movement(delta)
	_tick_sync_cohesion()
	_tick_capture(delta)
	_tick_garrison_visibility(delta)
	_tick_garrison_revive(delta)
	_tick_regen_and_repair(delta)
	_tick_weapon_locks(delta)
	_tick_combat(delta)
	_tick_ai(delta)
	_tick_ai_respawn()
	_tick_nav_resume(delta)
	if br_tracker:
		br_tracker.tick(delta)
		var before_br: int = br_tracker.closed.size()
		var before_active: int = br_tracker.active.size()
		var br_snap: Dictionary = br_tracker.tick_presence(
			units, map, delta, Callable(self, "_atk_ready_ratio")
		)
		if br_tracker.active.size() != before_active:
			# #region agent log
			_dbg59("BR", "board_root.process", "br_start_bar", {
				"active": br_tracker.active.size(), "closed": br_tracker.closed.size(),
				"clock": br_tracker.battle_clock, "runId": "br-bar"
			})
			# #endregion
			_refresh_br_list()
		var br_events: Array = br_snap.get("events", [])
		if not br_events.is_empty():
			# #region agent log
			_dbg59("BR", "board_root.process", "br_check", {
				"events": br_events, "active": br_tracker.active.size(),
				"closed": br_tracker.closed.size(),
				"clock": br_tracker.battle_clock, "runId": "br-early"
			})
			# #endregion
		if br_tracker.closed.size() != before_br:
			# #region agent log
			_dbg59("BR", "board_root.process", "br_settle", {
				"closed": br_tracker.closed.size(), "active": br_tracker.active.size(),
				"events": br_events, "clock": br_tracker.battle_clock,
				"runId": "br-early"
			})
			# #endregion
			_refresh_br_list()
	var occ_info: Dictionary = _refresh_occupancy()
	var occ_changed_frame: bool = bool(occ_info.get("changed", false))
	var arc_changed_frame: bool = bool(occ_info.get("arcs", false))
	if bool(occ_info.get("scale", false)) and starmap_view:
		_starmap_scale_dirty = true
	## Soft arc 补帧 200ms (BH-35).
	var arcs_moving := map.tick_smooth_arcs(delta) if map else false
	## Arc/scale morph: clamp idle into cell (no polar-slot chase; BH-38).
	_soft_follow_cell_slots(delta, arcs_moving or occ_changed_frame)
	if starmap_view:
		var scaled = starmap_view.tick_smooth_scales(delta)
		starmap_view.tick_screen_const_icons()
		## Paint force = color/owner only. Occupancy chatter must NOT force-paint every frame.
		var force_paint := map.capture_dirty
		if scaled or arcs_moving or force_paint or _starmap_scale_dirty:
			starmap_view.sync_ring_visuals(delta, arcs_moving, scaled, force_paint)
			if map.capture_dirty:
				map.capture_dirty = false
			_starmap_scale_dirty = false
		starmap_view.tick_icon_edge_follow()
	# #region agent log
	if Engine.get_process_frames() % 30 == 0:
		_dbg59("PERF", "board_root.process", "board_tick", {
			"arcs": arcs_moving, "occ": occ_changed_frame, "arc_ch": arc_changed_frame,
			"runId": "post-fix"
		})
	# #endregion
	_separate_stacked_units(delta)
	_curtain_acc += delta
	if _curtain_acc >= 0.12:
		_curtain_acc = 0.0
		## 战场+战术：同步守卫立场/链接帷幕；星图清空 GPU 帷幕。
		if starmap_view and starmap_view.has_method("sync_guard_curtains"):
			var show_curtains := cam == null or not cam.starmap_mode
			if show_curtains:
				starmap_view.sync_guard_curtains(units)
			else:
				starmap_view.sync_guard_curtains([])
			# #region agent log
			var n_field := 0
			var n_link := 0
			if show_curtains:
				for uu in units:
					if not uu.get("alive", false):
						continue
					var gg: Dictionary = uu.get("guard", {})
					if gg.get("field_on", false):
						n_field += 1
					if gg.get("link_on", false):
						n_link += 1
			_dbg59("CUR", "board_root.sync_guard_curtains", "tick", {
				"show": show_curtains, "field": n_field, "link": n_link,
				"tier": cam.view_tier() if cam and cam.has_method("view_tier") else "?",
				"runId": "curtain-fix"
			})
			# #endregion
	_update_unit_visuals(delta)
	if cam and cam.tactical_mode and not cam.starmap_mode and tactical_callouts:
		var callout_units: Array = []
		for uu in units:
			if _is_hostile_on_empty_cell(uu):
				continue
			if not _sleeper_plate_expanded(uu) and bool(uu.get("garrison", false)):
				continue
			callout_units.append(uu)
		tactical_callouts.view_yaw = float(cam.tactical_yaw)
		tactical_callouts.sync_occupied(callout_units, Callable(self, "_callout_claimant_ids"), delta)
		_sync_tactical_overheads(delta)
	elif cam and cam.starmap_mode and Engine.get_process_frames() % 30 == 0:
		_sync_starmap_rep_badges()
	if cam and cam.has_method("tick_breathe"):
		cam.tick_breathe(delta)
	_update_box_overlay()
	rebuild_timer += delta
	if rebuild_timer > 0.35:
		rebuild_timer = 0.0
		var occ2: Dictionary = _refresh_occupancy()
		if bool(occ2.get("changed", false)) and starmap_view:
			_starmap_scale_dirty = true
			starmap_view.rebuild_labels(pilots)
			## Edge icons slide via tick_icon_edge_follow — GPU board syncs arcs/scale in _process (BH-35).
			starmap_view.tick_icon_edge_follow()
		_refresh_hud_progress_only()
		if _detail_dirty:
			_detail_dirty = false
			_update_detail()
	_check_defeat()

func _add_cell_weight(sid: String, cell_i: int, amt: float) -> void:
	if amt <= 0.0 or not map.systems.has(sid):
		return
	var cells: Array = map.systems[sid]["cells"]
	if cell_i < 0 or cell_i >= cells.size():
		return
	cells[cell_i]["weight"] = float(cells[cell_i].get("weight", 1.0)) + amt

func _refresh_occupancy() -> Dictionary:
	## Per-cell weight → arc width. Quantize soft weights so arcs don't dirty every frame.
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			c["weight"] = 1.0
	var sys_ships: Dictionary = {}
	for sid in map.systems.keys():
		sys_ships[sid] = 0.0
	for u in units:
		if not u.get("alive", false):
			continue
		_update_reserve_weight(u)
		## Quantize soft reserve (0.25 steps) — prevents remesh/reanchor storm on land.
		var rw: float = snappedf(clampf(float(u.get("reserve_weight", 0.0)), 0.0, 1.0), 0.25)
		if u.get("step_kind") == "jump" and int(u.get("phase", 0)) == BoardTypes.MovePhase.INVULN:
			var t0j: float = maxf(float(u.get("step_invuln", 1.0)), 0.01)
			var kj: float = snappedf(1.0 - clampf(float(u.get("phase_t", 0.0)) / t0j, 0.0, 1.0), 0.25)
			var src: String = str(u.get("from_sys", u.get("sys", "")))
			var dst: String = str(u.get("to_sys", u.get("sys", "")))
			var fc: int = int(u.get("from_cell", u.get("cell", 0)))
			var tc: int = int(u.get("to_cell", u.get("cell", 0)))
			_add_cell_weight(src, fc, 1.0 - kj)
			_add_cell_weight(dst, tc, kj)
			if sys_ships.has(src):
				sys_ships[src] = float(sys_ships[src]) + (1.0 - kj)
			if sys_ships.has(dst):
				sys_ships[dst] = float(sys_ships[dst]) + kj
		else:
			var ph: int = int(u.get("phase", 0))
			var sid_u: String = str(u.get("sys", ""))
			var cell_u: int = int(u.get("cell", 0))
			if ph == BoardTypes.MovePhase.PREP:
				## Prep: stay on origin only — no dest occupancy yet (BH-36 / jump-stutter).
				_add_cell_weight(sid_u, cell_u, 1.0)
				if sys_ships.has(sid_u):
					sys_ships[sid_u] = float(sys_ships[sid_u]) + 1.0
			elif ph == BoardTypes.MovePhase.INVULN:
				## Occupancy / scale starts only after invuln (destination claim).
				_add_cell_weight(sid_u, cell_u, 1.0 - rw)
				var rsys: String = str(u.get("reserve_sys", u.get("to_sys", "")))
				var rcell: int = int(u.get("reserve_cell", u.get("to_cell", -1)))
				if rsys != "" and rcell >= 0:
					_add_cell_weight(rsys, rcell, rw)
				if sys_ships.has(sid_u):
					sys_ships[sid_u] = float(sys_ships[sid_u]) + (1.0 - rw)
				if rsys != "" and sys_ships.has(rsys):
					sys_ships[rsys] = float(sys_ships[rsys]) + rw
			else:
				_add_cell_weight(sid_u, cell_u, 1.0)
				if sys_ships.has(sid_u):
					sys_ships[sid_u] = float(sys_ships[sid_u]) + 1.0
	var empty_s := float(map.layout.get("empty_system_scale", 0.62))
	var scale_changed := false
	var arcs_changed := false
	for sid in map.systems.keys():
		var wsum := float(sys_ships.get(sid, 0.0))
		var presence := clampf(wsum, 0.0, 1.0)
		var new_scale := lerpf(empty_s, 1.0, presence)
		var old_scale := float(map.systems[sid].get("scale", 1.0))
		if absf(old_scale - new_scale) > 0.0008:
			scale_changed = true
		map.systems[sid]["scale"] = new_scale
		if map.recompute_angles(str(sid)):
			arcs_changed = true
	return {"changed": scale_changed or arcs_changed, "arcs": arcs_changed, "scale": scale_changed}

func _update_reserve_weight(u: Dictionary) -> void:
	var ph: int = int(u.get("phase", 0))
	if ph == BoardTypes.MovePhase.PREP:
		## No dest occupancy during prep.
		u["reserve_weight"] = 0.0
	elif ph == BoardTypes.MovePhase.INVULN:
		## 0→1 over invuln only (slower board fatten/scale).
		var inv: float = maxf(float(u.get("step_invuln", u.get("move_s", 1.0))), 0.01)
		var left: float = float(u.get("phase_t", 0.0))
		var elapsed: float = inv - left
		u["reserve_weight"] = clampf(elapsed / inv, 0.0, 1.0)
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
					## Prep finished → commit current dest (may have been retargeted).
					if u.has("order_dest_sys") and str(u["order_dest_sys"]) == str(u.get("sys", "")) \
							and str(u.get("step_kind", "intra")) != "jump":
						var od = int(u.get("order_dest_cell", u["to_cell"]))
						var destf = _bubble_redirect(str(u["sys"]), int(u.get("from_cell", u["cell"])), od, u)
						u["to_cell"] = destf
						u["to_sys"] = u["sys"]
						_assign_reserve(u)
					u["from_pos"] = Vector3(u["pos"].x, BoardTypes.UNIT_Y, u["pos"].z)
					u["phase"] = BoardTypes.MovePhase.INVULN
					u["phase_t"] = float(u.get("step_invuln", u["move_s"]))
					u["alpha"] = BoardTypes.INVULN_ALPHA
					u["trail_pts"] = []
					u["trail_acc"] = 0.0
					## Callout stays on departure until LANDING (TACTICAL_TOPDOWN §9).
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
					## Chase live cell center (not polar slot) as ring scales — BH-38.
					var live: Vector3 = _cell_pos_visual(str(u["sys"]), int(u["to_cell"]), BoardTypes.UNIT_Y)
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
						_mark_cell_enter(u, str(u["sys"]), seen)
				if u["phase_t"] <= 0.0:
					if u.get("step_kind") == "jump":
						u["sys"] = u["to_sys"]
						u["cell"] = u["to_cell"]
						_mark_cell_enter(u, str(u["sys"]), int(u["cell"]))
						starmap_view.transit_gates.erase("%s:%d" % [u.get("from_sys", u["sys"]), int(u.get("from_cell", 0))])
						if br_tracker:
							br_tracker.note_unit_enter_sys(u, str(u["sys"]))
						## 星图指令：一进目标系即解除导航、原地待命（落进系星门）。
						if u.get("nav_standby_on_sys_enter", false) \
								and str(u["sys"]) == str(u.get("order_dest_sys", "")):
							u["path"] = []
							u.erase("nav_standby_on_sys_enter")
							# #region agent log
							_dbg59("SSB", "board_root.jump_land", "standby_on_enter", {
								"unit": u["id"], "sys": u["sys"], "cell": int(u["cell"]),
								"runId": "starmap-select"
							})
							# #endregion
					else:
						u["cell"] = u["to_cell"]
					_mark_cell_enter(u, str(u["sys"]), int(u["cell"]))
					u["phase"] = BoardTypes.MovePhase.LANDING
					u["phase_t"] = float(u["landing_s"])
					u["alpha"] = 1.0
					_guard_force_off(u)
					## Land at arrival clamp — soft separate spreads peers (BH-38).
					var land = _clamp_pos_to_cell(str(u["sys"]), int(u["cell"]), u["pos"])
					u["land_pos"] = land
					u["rest_pos"] = land
					u["pos"] = land
					# #region agent log
					_dbg59("LAND", "board_root.land", "land_clamp", {
						"unit": u["id"], "sys": u["sys"], "cell": int(u["cell"]),
						"claimants": _cell_claim_count(str(u["sys"]), int(u["cell"])),
						"runId": "sep-fix"
					})
					# #endregion
					if u["path"].is_empty():
						var at_dest: bool = false
						if u.has("order_dest_sys"):
							at_dest = str(u["sys"]) == str(u["order_dest_sys"]) \
								and int(u["cell"]) == int(u.get("order_dest_cell", -1))
						if at_dest or not u.has("order_dest_sys"):
							_clear_move_line(str(u["id"]))
							u.erase("order_dest_sys")
							u.erase("order_dest_cell")
						## else keep dest — waiting at blocked gate for nav resume
						## sync_gid cleared only when whole group is stationary on one cell.
						_sync_try_clear_gid(u)
					_apply_bubble_pull_on_land(u)
			BoardTypes.MovePhase.LANDING:
				u["phase_t"] = float(u["phase_t"]) - delta
				## Stay put; soft-separate handles peers. Only re-clamp if arcs moved.
				u["pos"] = _clamp_pos_to_cell(str(u["sys"]), int(u["cell"]), u["pos"])
				u["rest_pos"] = Vector3(u["pos"].x, BoardTypes.UNIT_Y, u["pos"].z)
				if u["phase_t"] <= 0.0:
					u["phase"] = BoardTypes.MovePhase.IDLE
					_clear_reserve(u)
					if u["path"].is_empty():
						_sync_try_clear_gid(u)
		_apply_figure8(u)

func _apply_figure8(u: Dictionary) -> void:
	## Combat: small figure-8 on XZ. Peaceful breathe is model-local Y in _update_unit_visuals.
	if int(u["phase"]) != BoardTypes.MovePhase.IDLE:
		return
	var base: Vector3 = u.get("rest_pos", Vector3.ZERO)
	if base == Vector3.ZERO:
		base = _cell_pos_visual(u["sys"], int(u["cell"]), BoardTypes.UNIT_Y)
		u["rest_pos"] = base
	var in_combat = bool(u.get("took_damage", false)) or float(u.get("dealt_timer", 0.0)) > 0.0
	if not in_combat:
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
	var pad_r := 1.15
	var inner: float = float(map.layout.get("ring_inner", 12)) * sc + pad_r
	var outer: float = float(map.layout.get("ring_outer", 26)) * sc - pad_r
	var gap := minf(0.55 / maxf(outer, 1.0), float(c.get("angle_half", 0.2)) * 0.22)
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
		_on_capture_flip_garrison(f)
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
			var dealt_pd := _apply_damage_to_unit(u, tgt, raw, int(tgt["inst"]["resist"]))
			## Hidden sleeper_pd_max_restore: PD dealt HP restores own max loss 1:1.
			if dealt_pd > 0.0 and bool(u.get("pd_repair_max_loss", false)):
				var restored := _restore_unit_max_loss(u, dealt_pd)
				# #region agent log
				_dbg59("DMG", "board_root._tick_combat", "pd_max_restore", {
					"unit": str(u.get("id", "")), "ship": str(u.get("ship_id", "")),
					"dealt": dealt_pd, "restored": restored, "runId": "pd-max-restore"
				})
				# #endregion
			_play_turret_vfx(str(g.get("fx", "rail")), _vfx_endpoint(u), _vfx_endpoint(tgt))
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
			var kind_w := str(w.get("kind", ""))
			if (kind_w == "remote_armor" or kind_w == "remote_shield") and _remote_heal_room(wtgt, w) <= 0.5:
				## Do not start cycle / VFX while corresponding pool is full.
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
	var focus = _unit_by_id(str(u.get("focus_id", "")))
	if focus and focus.get("alive", false) and int(focus["faction"]) != int(u["faction"]) \
			and _pd_in_range(u, focus, g) and not claimed.has(str(focus["id"])):
		return focus
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
		if bool(o.get("npc", false)) and int(o.get("cell", -2)) != int(u.get("cell", -1)):
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

func _channel_has_in_range_hostile(u: Dictionary, range_cells: int) -> bool:
	if not u.get("alive", false):
		return false
	for o in units:
		if not o.get("alive", false):
			continue
		if int(o["faction"]) == int(u["faction"]):
			continue
		if str(u["sys"]) != str(o["sys"]):
			continue
		var n: int = map.systems[u["sys"]]["cells"].size()
		var steps = BoardTypes.shorter_arc_steps(int(u["cell"]), int(o["cell"]), n)
		if steps <= range_cells:
			return true
	return false

func _atk_ready_ratio(u: Dictionary) -> float:
	## Read-only viz: 1 = about to fire; -1 = no in-range damage channel (TACTICAL_TOPDOWN).
	if not u.get("alive", false):
		return -1.0
	var ph: int = int(u.get("phase", 0))
	if ph == BoardTypes.MovePhase.INVULN or ph == BoardTypes.MovePhase.LANDING:
		return -1.0
	var best_t := INF
	var best_cycle := 1.0
	for g in u.get("pd", []):
		if not _channel_has_in_range_hostile(u, int(g.get("range_cells", 0))):
			continue
		var t: float = maxf(0.0, float(g.get("cd", 0.0)))
		if t < best_t:
			best_t = t
			best_cycle = maxf(float(g.get("cycle", 1.0)), 0.001)
	for w in u.get("weapons", []):
		var kind_w := str(w.get("kind", ""))
		if kind_w == "remote_armor" or kind_w == "remote_shield":
			continue
		if not _channel_has_in_range_hostile(u, int(w.get("range_cells", 0))):
			continue
		var cd_left: float = maxf(0.0, float(w.get("cd", 0.0)))
		var lock_left: float = maxf(0.0, float(w.get("lock_need", 0.0)) - float(w.get("lock_t", 0.0)))
		var t2: float = maxf(cd_left, lock_left)
		if t2 < best_t:
			best_t = t2
			best_cycle = maxf(float(w.get("cycle", 1.0)), 0.001)
	if best_t >= INF:
		return -1.0
	return 1.0 - clampf(best_t / best_cycle, 0.0, 1.0)

func _kill_unit(u: Dictionary) -> void:
	## Drop invisible landing reserve immediately (BH-38).
	if u.get("step_kind") == "jump" and starmap_view:
		starmap_view.transit_gates.erase("%s:%d" % [str(u.get("from_sys", u.get("sys", ""))), int(u.get("from_cell", 0))])
	u["alive"] = false
	u["phase"] = BoardTypes.MovePhase.IDLE
	u["phase_t"] = 0.0
	u["path"] = []
	u["alpha"] = 1.0
	u["focus_id"] = ""
	u.erase("sync_gid")
	u.erase("land_pos")
	u.erase("follow_from")
	u.erase("follow_to")
	u.erase("follow_t")
	## Clear others focusing this unit.
	var dead_id := str(u.get("id", ""))
	for ou in units:
		if str(ou.get("focus_id", "")) == dead_id:
			ou["focus_id"] = ""
	_clear_reserve(u)
	_clear_move_line(str(u["id"]))
	_note_garrison_death(u)
	var p = _pilot_by_id(str(u.get("pilot_id", "")))
	if not p.is_empty():
		_remember_last_ship(p, u)
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
		var body = unit_nodes[u["id"]].get_node_or_null("PickBody") as StaticBody3D
		if body:
			body.collision_layer = 0
	selection.erase(u["id"])
	_rebuild_hud_list()
	# #region agent log
	_dbg59("SEP", "board_root._kill_unit", "clear_reserve", {
		"unit": str(u.get("id", "")), "sys": str(u.get("sys", "")),
		"cell": int(u.get("cell", -1)), "runId": "sep-fix"
	})
	# #endregion

func _remember_last_ship(p: Dictionary, u: Dictionary) -> void:
	var sid := str(u.get("ship_id", ""))
	if sid == "":
		return
	p["last_ship_id"] = sid
	p["last_ship_tonnage"] = str(u.get("tonnage", data.ship_def(sid).get("tonnage", "")))
	p["last_ship_name"] = str(u.get("ship_name", u.get("name", sid)))

func _pilot_alive_ship_id(p: Dictionary) -> String:
	## Left-bar UI only — never fall back to last_ship (code-only).
	var u = _unit_by_id(str(p.get("unit_id", "")))
	if u and u.get("alive", false):
		return str(u.get("ship_id", ""))
	return ""

func _pilot_display_ship_id(p: Dictionary) -> String:
	## Code paths (auto-launch / 全体产线): alive → last_ship → default.
	var alive := _pilot_alive_ship_id(p)
	if alive != "":
		return alive
	var last := str(p.get("last_ship_id", ""))
	if last != "":
		return last
	return str(p.get("default_ship", ""))

func _refresh_pilot_row_tonnage(row: Control, p: Dictionary) -> void:
	if row == null:
		return
	var ton_rect := row.find_child("TonnageIcon", true, false) as TextureRect
	if ton_rect == null:
		return
	var u = _unit_by_id(str(p.get("unit_id", "")))
	if u and u.get("alive", false):
		var ton := str(u.get("tonnage", ""))
		ton_rect.texture = _tonnage_icon(ton) if ton != "" else null
		ton_rect.visible = ton != ""
	else:
		ton_rect.texture = null
		ton_rect.visible = false
	var title := row.find_child("PilotTitle", true, false) as Label
	if title:
		var ship_name := ""
		if u and u.get("alive", false):
			ship_name = str(u.get("name", ""))
		if ship_name != "":
			title.text = "%s  %s" % [p.get("name", ""), ship_name]
		else:
			title.text = str(p.get("name", ""))

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
		if br_tracker:
			br_tracker.note_unit_enter_sys(u, cs)
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
		## 星图: units stay hidden — distribution is on the point-line graph.
		if cam and cam.starmap_mode:
			n.visible = false
			if oh:
				oh.visible = false
			continue
		## 战术俯视：空白格敌对不展示。
		if cam and cam.tactical_mode and _is_hostile_on_empty_cell(u):
			n.visible = false
			if oh:
				oh.visible = false
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
			var breath_y := 0.0
			## Stationary idle breathe (does not fight soft_follow XZ).
			if int(u.get("phase", 0)) == BoardTypes.MovePhase.IDLE:
				var ft := float(u.get("float_t", 0.0))
				var ff := 1.0 + float(u.get("float_freq", 0.0))
				breath_y = sin(ft * TAU * 0.35 * ff) * 0.22
			model_n.position = base_pos + Vector3(sin(ph * 1.7) * amp, breath_y, cos(ph * 2.3) * amp)
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
		var tac := cam != null and cam.tactical_mode
		var star := cam != null and cam.starmap_mode
		## 铭牌黄光晕：仅战术俯视（非星图、非战场）。
		var tac_plate := tac and not star
		if model_n:
			model_n.visible = not tac
		var trail = n.get_node_or_null("Trail") as MeshInstance3D
		if trail:
			if tac:
				trail.visible = false
			elif moving:
				_stamp_unit_trail(u, delta)
				_rebuild_unit_trail_mesh(trail, u)
				trail.visible = true
			else:
				u["trail_pts"] = []
				trail.visible = false
				trail.mesh = null
		if ring and tac:
			ring.visible = false
		if ring_ol and tac:
			ring_ol.visible = false
		if oh:
			if oh.has_method("set_alive_view"):
				oh.set_alive_view(true)
			var p = _pilot_by_id(str(u.get("pilot_id", "")))
			var fac_name = ""
			for f in data.factions.get("factions", []):
				if int(f["id"]) == int(u["faction"]):
					fac_name = str(f.get("abbrev", ""))
					break
			var pname := str(u.get("pilot_name", p.get("name", "")))
			var title = "[%s]%s %s" % [fac_name, pname, u["name"]]
			var inst: Dictionary = u["inst"]
			var atk_r := _atk_ready_ratio(u)
			## Sleeper compact until expand. Tactical unexpanded → no callout/slot → oh hidden in sync.
			var compact := bool(u.get("garrison", false)) and not _sleeper_plate_expanded(u)
			var show_badge := not data.is_npc_faction(int(u.get("faction", 0)))
			if oh.has_method("set_compact_icon_only"):
				oh.set_compact_icon_only(compact)
			if oh.has_method("set_show_faction_badge"):
				oh.set_show_faction_badge(show_badge)
			# #region agent log
			if bool(u.get("garrison", false)) and Engine.get_process_frames() % 90 == 0:
				_dbg59("PLATE", "board_root._update_unit_visuals", "sleeper_plate", {
					"id": str(u.get("id", "")), "fac": int(u.get("faction", 0)),
					"pledged": bool(u.get("garrison_pledged", false)),
					"compact": compact, "expanded": not compact,
					"runId": "ui-fix"
				})
			# #endregion
			oh.update_view(
				title,
				float(inst["shield"]), float(inst["armor"]), float(inst["structure"]),
				float(inst["max_s"]), float(inst["max_a"]), float(inst["max_h"]),
				float(inst.get("pristine_s", inst["max_s"])),
				float(inst.get("pristine_a", inst["max_a"])),
				float(inst.get("pristine_h", inst["max_h"])),
				float(inst.get("cap", 0)), float(inst.get("max_cap", 1)),
				-1.0 if compact else atk_r
			)
			# #region agent log
			if Engine.get_process_frames() % 60 == 0 and atk_r >= 0.0:
				_dbg59("CDB", "board_root._update_unit_visuals", "atk_cd_bar", {
					"unit": str(u.get("id", "")), "ratio": atk_r, "runId": "cd-bar"
				})
			# #endregion
			var rel = _rel_for(u["faction"])
			if oh.has_method("set_enemy_mirror"):
				oh.set_enemy_mirror(rel == "hostile")
			if oh.has_method("set_tonnage_overlays"):
				var ov = _tonnage_overlay_set(rel)
				if show_badge:
					oh.set_tonnage_overlays(ov.get("bg"), ov.get("badge"))
				else:
					oh.set_tonnage_overlays(null, null)
			if oh.has_method("set_faction_badge"):
				oh.set_faction_badge(BoardTypes.relation_color(rel))
			## Orbit: face_camera. Tactical: place_tactical via _sync_tactical_overheads.
			if oh.has_method("set_selected_highlight"):
				oh.set_selected_highlight(tac_plate and sel_on)
			if not tac and cam and cam.cam and oh.has_method("face_camera"):
				oh.face_camera(cam.cam, u["pos"])
			# #region agent log
			if tac_plate and sel_on and Engine.get_process_frames() % 45 == 0:
				_dbg59("TSH", "board_root._update_unit_visuals", "tac_sel_glow", {
					"unit": u["id"], "sel": sel_on, "tac": tac, "star": star,
					"runId": "tac-sel-glow"
				})
			# #endregion
		if cam.follow_unit_id == u["id"]:
			## Follow always uses ship world pos (never callout/icon).
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

func _fan_cell_slots_xz(sys: String, cell: int) -> void:
	## Spawn / one-shot spread only; no continuous follow (BH-38).
	var claimants = _cell_claimant_ids(sys, cell)
	var n = claimants.size()
	if n <= 0:
		return
	for i in n:
		var uu = _unit_by_id(str(claimants[i]))
		if uu.is_empty():
			continue
		if int(uu.get("phase", 0)) != BoardTypes.MovePhase.IDLE:
			continue
		var p = _cell_slot_pos(sys, cell, i, n)
		uu["rest_pos"] = p
		uu["pos"] = p
		uu["reserve_slot"] = i
		uu.erase("follow_from")
		uu.erase("follow_to")
		uu.erase("follow_t")


func _separate_stacked_units(delta: float) -> void:
	## Soft XZ push inside cell; no polar-slot reanchor fight (BH-38).
	const MIN_XZ := 2.4
	const PUSH_RATE := 8.0
	var by_cell: Dictionary = {}
	for u in units:
		if not u.get("alive", false):
			continue
		var ph0 = int(u["phase"])
		if ph0 != BoardTypes.MovePhase.IDLE and ph0 != BoardTypes.MovePhase.LANDING:
			continue
		var key = "%s:%d" % [u["sys"], int(u["cell"])]
		if not by_cell.has(key):
			by_cell[key] = []
		by_cell[key].append(u)
	var any_push := false
	var max_pair := 0.0
	for key in by_cell.keys():
		var group: Array = by_cell[key]
		if group.size() < 2:
			continue
		var parts = key.split(":")
		var sys_k = parts[0]
		var cell_k = int(parts[1])
		for i in group.size():
			for j in range(i + 1, group.size()):
				var a: Dictionary = group[i]
				var b: Dictionary = group[j]
				var dx: float = float(a["pos"].x) - float(b["pos"].x)
				var dz: float = float(a["pos"].z) - float(b["pos"].z)
				var d: float = sqrt(dx * dx + dz * dz)
				if d < 0.05:
					var ang := float(hash(str(a["id"])) % 360) * TAU / 360.0
					dx = cos(ang) * 0.35
					dz = sin(ang) * 0.35
					d = 0.35
				if d >= MIN_XZ:
					continue
				any_push = true
				max_pair = maxf(max_pair, MIN_XZ - d)
				var nx := dx / d
				var nz := dz / d
				var push := (MIN_XZ - d) * 0.5 * clampf(delta * PUSH_RATE, 0.0, 1.0)
				a["pos"] = Vector3(float(a["pos"].x) + nx * push, BoardTypes.UNIT_Y, float(a["pos"].z) + nz * push)
				b["pos"] = Vector3(float(b["pos"].x) - nx * push, BoardTypes.UNIT_Y, float(b["pos"].z) - nz * push)
		for uu in group:
			uu["pos"] = _clamp_pos_to_cell(sys_k, cell_k, uu["pos"])
			uu["rest_pos"] = Vector3(uu["pos"].x, BoardTypes.UNIT_Y, uu["pos"].z)
	# #region agent log
	if any_push and Engine.get_process_frames() % 30 == 0:
		_dbg59("SEP", "board_root._separate_stacked_units", "soft_push", {
			"max_gap": max_pair, "cells": by_cell.size(), "runId": "sep-fix"
		})
	# #endregion


func _reanchor_idle_units() -> void:
	## Opening / rare: one-shot polar spread, then soft-separate owns spacing.
	var seen: Dictionary = {}
	for u in units:
		if not u.get("alive", false):
			continue
		if int(u["phase"]) != BoardTypes.MovePhase.IDLE:
			continue
		var key := "%s:%d" % [str(u["sys"]), int(u["cell"])]
		if seen.has(key):
			continue
		seen[key] = true
		_fan_cell_slots_xz(str(u["sys"]), int(u["cell"]))

func _soft_follow_cell_slots(_delta: float, force: bool) -> void:
	## BH-38: no slot chase. Arc/scale morph -> clamp idle into cell. Prep stays clamped.
	if not force:
		for u in units:
			if not u.get("alive", false):
				continue
			if int(u.get("phase", 0)) != BoardTypes.MovePhase.PREP:
				continue
			var sys_p = str(u.get("from_sys", u["sys"]))
			var cell_p = int(u.get("from_cell", u["cell"]))
			u["pos"] = _clamp_pos_to_cell(sys_p, cell_p, u["pos"])
		return
	for u in units:
		if not u.get("alive", false):
			continue
		var ph: int = int(u.get("phase", 0))
		if ph != BoardTypes.MovePhase.IDLE and ph != BoardTypes.MovePhase.PREP:
			continue
		var sys = str(u["sys"])
		var cell = int(u["cell"])
		if ph == BoardTypes.MovePhase.PREP:
			cell = int(u.get("from_cell", cell))
			sys = str(u.get("from_sys", sys))
			u["pos"] = _clamp_pos_to_cell(sys, cell, u["pos"])
			if u.get("step_kind") != "jump":
				_assign_reserve(u)
		else:
			## Sleepers follow cell wedges when arcs morph; others only clamp (BH-38).
			if bool(u.get("garrison", false)):
				var claimants_g: Array = _cell_claimant_ids(sys, cell)
				var n_g := maxi(claimants_g.size(), 1)
				var slot_g := int(u.get("reserve_slot", claimants_g.find(str(u.get("id", "")))))
				if slot_g < 0:
					slot_g = 0
				var tgt_g: Vector3 = _cell_slot_pos(sys, cell, slot_g, n_g)
				u["pos"] = tgt_g
				u["rest_pos"] = tgt_g
				# #region agent log
				if Engine.get_process_frames() % 90 == 0:
					_dbg59("GARR", "board_root._soft_follow_cell_slots", "sleeper_follow", {
						"id": str(u.get("id", "")), "sys": sys, "cell": cell,
						"slot": slot_g, "runId": "sleeper-arc"
					})
				# #endregion
			else:
				u["pos"] = _clamp_pos_to_cell(sys, cell, u["pos"])
				u["rest_pos"] = Vector3(u["pos"].x, BoardTypes.UNIT_Y, u["pos"].z)

func _cell_slot_pos(sys: String, cell: int, slot: int, total: int) -> Vector3:
	## Polar grid inside wedge via art module (fixes tangent-line packing).
	if not map.systems.has(sys):
		return Vector3.ZERO
	var sysd: Dictionary = map.systems[sys]
	var cells: Array = sysd["cells"]
	if cell < 0 or cell >= cells.size():
		return sysd["center"]
	var c: Dictionary = cells[cell]
	var sc := starmap_view.visual_scale_of(sys) if starmap_view else float(sysd.get("visual_scale", sysd.get("scale", 1.0)))
	var r_in := float(map.layout.get("ring_inner", 12)) * sc
	var r_out := float(map.layout.get("ring_outer", 26)) * sc
	return SHIP_ART.sector_slot_pos(
		sysd["center"],
		float(c.get("angle_center", 0.0)),
		float(c.get("angle_half", PI / 12.0)),
		r_in, r_out, slot, total, BoardTypes.UNIT_Y
	)

func _callout_anchor_for_unit(u: Dictionary) -> Dictionary:
	## TACTICAL_TOPDOWN §9: INVULN stays on departure; LANDING/IDLE/PREP use settled cell.
	if u.is_empty() or not u.get("alive", false):
		return {"sys": "", "cell": -1}
	var ph := int(u.get("phase", 0))
	if ph == BoardTypes.MovePhase.INVULN:
		var fs := str(u.get("from_sys", u.get("sys", "")))
		var fc := int(u.get("from_cell", u.get("cell", -1)))
		if fs != "" and fc >= 0:
			return {"sys": fs, "cell": fc}
	return {"sys": str(u.get("sys", "")), "cell": int(u.get("cell", -1))}

func _callout_claimant_ids(sys: String, cell: int) -> Array:
	## Units whose callout anchor is this cell (not INVULN→dest pass-through).
	var ids: Array = []
	for u in units:
		if not u.get("alive", false):
			continue
		var anc := _callout_anchor_for_unit(u)
		if str(anc.get("sys", "")) != sys or int(anc.get("cell", -999)) != cell:
			continue
		var uid := str(u["id"])
		if not ids.has(uid):
			ids.append(uid)
	ids.sort_custom(func(a, b):
		var ua: Dictionary = _unit_by_id(str(a))
		var ub: Dictionary = _unit_by_id(str(b))
		var ta := float(ua.get("cell_enter_t", 0.0))
		var tb := float(ub.get("cell_enter_t", 0.0))
		if absf(ta - tb) < 0.0001:
			return str(a) < str(b)
		return ta < tb
	)
	return ids

func _cell_claimant_ids(sys: String, cell: int) -> Array:
	## Dest claim only after INVULN/LANDING — prep reserve must not crowd the target cell.
	## Order = enter-cell time (callout slots stable; TACTICAL_TOPDOWN §8).
	var ids: Array = []
	for u in units:
		if not u.get("alive", false):
			continue
		var uid = str(u["id"])
		var ph = int(u["phase"])
		## IDLE/PREP still occupy current cell (callout stays until ship leaves).
		if (ph == BoardTypes.MovePhase.IDLE or ph == BoardTypes.MovePhase.PREP) \
				and str(u["sys"]) == sys and int(u["cell"]) == cell:
			if not ids.has(uid):
				ids.append(uid)
		elif ph == BoardTypes.MovePhase.INVULN or ph == BoardTypes.MovePhase.LANDING:
			if str(u.get("reserve_sys", u.get("to_sys", ""))) == sys \
					and int(u.get("reserve_cell", u.get("to_cell", -999))) == cell:
				if not ids.has(uid):
					ids.append(uid)
	ids.sort_custom(func(a, b):
		var ua: Dictionary = _unit_by_id(str(a))
		var ub: Dictionary = _unit_by_id(str(b))
		var ta := float(ua.get("cell_enter_t", 0.0))
		var tb := float(ub.get("cell_enter_t", 0.0))
		if absf(ta - tb) < 0.0001:
			return str(a) < str(b)
		return ta < tb
	)
	return ids

func _cell_claim_count(sys: String, cell: int) -> int:
	return maxi(_cell_claimant_ids(sys, cell).size(), 1)

func _assign_reserve(u: Dictionary) -> void:
	## Occupancy claim only — aim at cell center; soft-separate spreads on land (BH-38).
	var sys = str(u.get("to_sys", u["sys"]))
	var cell = int(u["to_cell"])
	u["reserve_sys"] = sys
	u["reserve_cell"] = cell
	var claimants = _cell_claimant_ids(sys, cell)
	var uid = str(u["id"])
	if not claimants.has(uid):
		claimants.append(uid)
	u["reserve_slot"] = claimants.find(uid)
	var land = _cell_pos_visual(sys, cell, BoardTypes.UNIT_Y)
	u["land_pos"] = land
	if u.get("step_kind") != "jump":
		u["to_pos"] = land

func _mark_cell_enter(u: Dictionary, sys: String, cell: int) -> void:
	## Stamp enter time for callout slot order (earlier = earlier slot).
	if u.is_empty() or sys == "" or cell < 0:
		return
	var key := "%s:%d" % [sys, cell]
	if str(u.get("cell_key", "")) == key:
		return
	u["cell_key"] = key
	u["cell_enter_t"] = br_tracker.battle_clock if br_tracker else float(Time.get_ticks_msec()) * 0.001
	# #region agent log
	_dbg59("CO", "board_root._mark_cell_enter", "enter", {
		"uid": str(u.get("id", "")), "key": key, "t": float(u["cell_enter_t"]),
		"runId": "callout-order"
	})
	# #endregion

func _clear_reserve(u: Dictionary) -> void:
	u.erase("reserve_sys")
	u.erase("reserve_cell")
	u.erase("reserve_slot")
	u.erase("land_pos")
	u.erase("reserve_weight")

func _sync_peers(gid: int) -> Array:
	var out: Array = []
	if gid <= 0:
		return out
	for o in units:
		if not o.get("alive", false):
			continue
		if int(o.get("sync_gid", 0)) != gid:
			continue
		out.append(o)
	return out

func _sync_unit_occupy_key(u: Dictionary) -> String:
	## Current cell, or reserved landing while in hop (SHIPS §10 march span).
	var ph := int(u.get("phase", 0))
	if ph == BoardTypes.MovePhase.PREP or ph == BoardTypes.MovePhase.INVULN \
			or ph == BoardTypes.MovePhase.LANDING:
		var rsys := str(u.get("reserve_sys", u.get("to_sys", u.get("sys", ""))))
		var rcell := int(u.get("reserve_cell", u.get("to_cell", u.get("cell", -1))))
		if rsys != "" and rcell >= 0:
			return "%s:%d" % [rsys, rcell]
	return "%s:%d" % [str(u.get("sys", "")), int(u.get("cell", -1))]

func _sync_occupy_keys(peers: Array, extra_key: String = "") -> Dictionary:
	var keys: Dictionary = {}
	for o in peers:
		keys[_sync_unit_occupy_key(o)] = true
	if extra_key != "":
		keys[extra_key] = true
	return keys

func _sync_keys_span_ok(keys: Dictionary) -> bool:
	## At most 2 cells; if 2, same system and arc steps ≤ 1.
	if keys.size() <= 1:
		return true
	if keys.size() > 2:
		return false
	var a := str(keys.keys()[0])
	var b := str(keys.keys()[1])
	var pa := a.split(":")
	var pb := b.split(":")
	if pa.size() < 2 or pb.size() < 2:
		return false
	if str(pa[0]) != str(pb[0]):
		return false
	var sid := str(pa[0])
	if not map.systems.has(sid):
		return false
	var n: int = map.systems[sid]["cells"].size()
	return BoardTypes.shorter_arc_steps(int(pa[1]), int(pb[1]), n) <= 1

func _sync_group_stationary_one_cell(gid: int) -> bool:
	var peers := _sync_peers(gid)
	if peers.is_empty():
		return true
	var key0 := ""
	for o in peers:
		if int(o.get("phase", 0)) != BoardTypes.MovePhase.IDLE:
			return false
		if not o["path"].is_empty():
			return false
		var k := "%s:%d" % [str(o.get("sys", "")), int(o.get("cell", -1))]
		if key0 == "":
			key0 = k
		elif k != key0:
			return false
	return true

func _sync_try_clear_gid(u: Dictionary) -> void:
	var gid := int(u.get("sync_gid", 0))
	if gid <= 0:
		return
	if not sync_move_enabled or _sync_group_stationary_one_cell(gid):
		for o in _sync_peers(gid):
			o.erase("sync_gid")
		u.erase("sync_gid")

func _sync_shared_dest(peers: Array) -> Dictionary:
	## Prefer any peer's order_dest; else first peer cell.
	for o in peers:
		if o.has("order_dest_sys"):
			return {"sys": str(o["order_dest_sys"]), "cell": int(o.get("order_dest_cell", 0))}
	if peers.is_empty():
		return {}
	var p0: Dictionary = peers[0]
	return {"sys": str(p0.get("sys", "")), "cell": int(p0.get("cell", 0))}

func _tick_sync_cohesion() -> void:
	## Stationary: pull stragglers onto one cell; clear gid when packed (SHIPS §10).
	if not sync_move_enabled:
		return
	var seen: Dictionary = {}
	for u in units:
		if not u.get("alive", false):
			continue
		var gid := int(u.get("sync_gid", 0))
		if gid <= 0 or seen.has(gid):
			continue
		seen[gid] = true
		var peers := _sync_peers(gid)
		if peers.is_empty():
			continue
		var all_idle := true
		for o in peers:
			if int(o.get("phase", 0)) != BoardTypes.MovePhase.IDLE or not o["path"].is_empty():
				all_idle = false
				break
		if not all_idle:
			continue
		if _sync_group_stationary_one_cell(gid):
			for o2 in peers:
				o2.erase("sync_gid")
			continue
		var dest := _sync_shared_dest(peers)
		if dest.is_empty():
			continue
		var ds := str(dest["sys"])
		var dc := int(dest["cell"])
		for o3 in peers:
			if str(o3.get("sys", "")) == ds and int(o3.get("cell", -1)) == dc:
				continue
			if o3.has("order_dest_sys") and str(o3["order_dest_sys"]) == ds \
					and int(o3.get("order_dest_cell", -1)) == dc:
				continue
			_queue_unit_move(o3, ds, dc)
		# #region agent log
		_dbg59("SYNC", "board_root._tick_sync_cohesion", "pull_one_cell", {
			"gid": gid, "n": peers.size(), "dest": [ds, dc], "runId": "sync-cohesion"
		})
		# #endregion

func _sync_dist_to_dest(u: Dictionary, dest: Dictionary) -> int:
	if dest.is_empty():
		return 0
	var ds := str(dest.get("sys", ""))
	var dc := int(dest.get("cell", 0))
	if str(u.get("sys", "")) != ds:
		return 1000 + u["path"].size()
	if not map.systems.has(ds):
		return 999
	var n: int = map.systems[ds]["cells"].size()
	return BoardTypes.shorter_arc_steps(int(u.get("cell", 0)), dc, n)

func _sync_start_blocked(u: Dictionary) -> bool:
	if not sync_move_enabled:
		return false
	var gid = int(u.get("sync_gid", 0))
	if gid <= 0:
		return false
	## Peers still queued for pathfind must not let others step first.
	for oq in _order_queue:
		var qu = _unit_by_id(str(oq.get("id", "")))
		if qu.is_empty() or not qu.get("alive", false):
			continue
		if int(qu.get("sync_gid", 0)) == gid and str(qu.get("id", "")) != str(u.get("id", "")):
			return true
	var peers := _sync_peers(gid)
	for o in peers:
		if str(o.get("id", "")) == str(u.get("id", "")):
			continue
		var ph = int(o["phase"])
		if ph == BoardTypes.MovePhase.PREP or ph == BoardTypes.MovePhase.INVULN or ph == BoardTypes.MovePhase.LANDING:
			return true
		## Has dest but no path yet (drain lag) and not already there.
		if ph == BoardTypes.MovePhase.IDLE and o["path"].is_empty() and o.has("order_dest_sys"):
			var at := str(o.get("sys", "")) == str(o.get("order_dest_sys", "")) \
				and int(o.get("cell", -1)) == int(o.get("order_dest_cell", -2))
			if not at:
				return true
	## March: group must stay within 2 adjacent cells (SHIPS §10).
	if u["path"].is_empty():
		return false
	var cur_keys := _sync_occupy_keys(peers, "")
	var dest := _sync_shared_dest(peers)
	if not _sync_keys_span_ok(cur_keys):
		## Already spread: only the furthest-from-dest trailer may start (catch up).
		var my_d := _sync_dist_to_dest(u, dest)
		for o2 in peers:
			if str(o2.get("id", "")) == str(u.get("id", "")):
				continue
			if _sync_dist_to_dest(o2, dest) > my_d:
				return true
		return false
	var step: Dictionary = u["path"][0]
	var next_key := ""
	if str(step.get("kind", "")) == "jump":
		next_key = "%s:%d" % [str(step.get("to_sys", "")), int(step.get("to", -1))]
	else:
		next_key = "%s:%d" % [str(u.get("sys", "")), int(step.get("to", -1))]
	var keys := cur_keys.duplicate()
	keys.erase(_sync_unit_occupy_key(u))
	keys[next_key] = true
	if not _sync_keys_span_ok(keys):
		# #region agent log
		_dbg59("SYNC", "board_root._sync_start_blocked", "span_block", {
			"unit": str(u.get("id", "")), "gid": gid, "next": next_key,
			"keys": keys.keys(), "runId": "sync-cohesion"
		})
		# #endregion
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
	## LMB: latch press/release only. UI hit-test gates the press, never the release
	## (Mindustry keyRelease(select) commits the rect even after the cursor enters UI).
	if event is InputEventMouseMotion and dragging:
		if _event_pos(event).distance_to(drag_start) >= BoardTypes.BOX_DRAG_PX:
			box_selecting = true
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_lmb_press_latch = true
				_lmb_press_pos = mb.position
				_lmb_press_on_ui = _pointer_blocks_gesture_start(mb.position)
			else:
				_lmb_release_latch = true
				_lmb_release_pos = mb.position
			if not _pointer_blocks_gesture_start(mb.position):
				get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			## Board RMB orders: only known HUD / popup blocks (BOARD_AND_INPUT).
			## Do NOT use gui hovered STOP — stray controls were swallowing moves.
			var rmb_ui := (popup != null and popup.visible) \
				or _mouse_over_blocking_hud(mb.position)
			# #region agent log
			if not mb.pressed or rmb_ui:
				var hv = get_viewport().gui_get_hovered_control() if get_viewport() else null
				_dbg59("RMB", "board_root._input", "rmb_gate", {
					"pressed": mb.pressed, "blocked": rmb_ui,
					"hud": _mouse_over_blocking_hud(mb.position),
					"popup": popup != null and popup.visible,
					"hovered": str(hv.get_path()) if hv else "",
					"pos": [mb.position.x, mb.position.y],
					"sel_n": selection.size(),
					"runId": "rmb-block"
				})
			# #endregion
			if rmb_ui:
				_rmb_press_on_ui = true
				return
			if mb.pressed:
				_rmb_held = true
				_rmb_press_pos = mb.position
				_rmb_press_on_ui = false
				_rmb_handled_by_input = false
			else:
				_rmb_handled_by_input = true
			_handle_mouse_button(mb)
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

func _pointer_blocks_gesture_start(pos: Vector2) -> bool:
	## Start-only. Release must not call this to abort an in-flight box.
	if popup and popup.visible:
		return true
	if _mouse_over_blocking_hud(pos):
		return true
	var vp := get_viewport()
	if vp == null:
		return false
	var hovered := vp.gui_get_hovered_control()
	if hovered == null or hovered.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	if _box_overlay and (hovered == _box_overlay or hovered.get_parent() == _box_overlay):
		return false
	return true

func _rmb_blocks_order(pos: Vector2) -> bool:
	return (popup != null and popup.visible) or _mouse_over_blocking_hud(pos)

func _consume_rmb_order() -> void:
	## Release edge from button state (BOARD_AND_INPUT). Editor may swallow the event.
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var vp := get_viewport()
	var mp := vp.get_mouse_position() if vp else _rmb_press_pos
	if down and not _rmb_held:
		_rmb_held = true
		_rmb_handled_by_input = false
		_rmb_press_pos = mp
		_rmb_press_on_ui = _rmb_blocks_order(mp)
		# #region agent log
		_dbg59("RMB", "board_root._consume_rmb_order", "rmb_poll", {
			"edge": "down", "on_ui": _rmb_press_on_ui,
			"pos": [mp.x, mp.y], "runId": "rmb-poll"
		})
		# #endregion
		return
	if down or not _rmb_held:
		return
	_rmb_held = false
	if _rmb_handled_by_input or _rmb_press_on_ui:
		return
	# #region agent log
	_dbg59("RMB", "board_root._consume_rmb_order", "rmb_poll", {
		"edge": "up", "pos": [mp.x, mp.y], "sel_n": selection.size(),
		"runId": "rmb-poll"
	})
	# #endregion
	_right_click(mp)

func _consume_lmb_gesture() -> void:
	## Same-frame press+release both land here (input runs before process).
	var started_this_frame := false
	if _lmb_press_latch:
		_lmb_press_latch = false
		if not _lmb_press_on_ui:
			drag_start = _lmb_press_pos
			dragging = true
			box_selecting = false
			started_this_frame = true
	var lmb_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if dragging and lmb_down:
		var held: Vector2 = drag_start
		var vp_held := get_viewport()
		if vp_held:
			held = vp_held.get_mouse_position()
		if held.distance_to(drag_start) >= BoardTypes.BOX_DRAG_PX:
			box_selecting = true
	## Lost mouse-up (focus change / event swallowed): button already up while dragging.
	## Skip the start frame — button state may not be latched yet.
	if dragging and not lmb_down and not _lmb_release_latch and not started_this_frame:
		_lmb_release_latch = true
		var vp_rel := get_viewport()
		_lmb_release_pos = vp_rel.get_mouse_position() if vp_rel else drag_start
		# #region agent log
		_dbg59("GEST", "board_root._consume_lmb_gesture", "lmb_up_synth", {
			"pos": [_lmb_release_pos.x, _lmb_release_pos.y], "box": box_selecting,
			"runId": "gesture-poll"
		})
		# #endregion
	if _lmb_release_latch:
		var rel := _lmb_release_pos
		_lmb_release_latch = false
		if dragging:
			_finish_lmb_gesture(rel)

func _finish_lmb_gesture(pos: Vector2) -> void:
	var dist := pos.distance_to(drag_start)
	var was_box := box_selecting or dist >= BoardTypes.BOX_DRAG_PX
	dragging = false
	box_selecting = false
	# #region agent log
	_dbg59("GEST", "board_root._finish_lmb_gesture", "lmb_up", {
		"box": was_box, "dist": dist,
		"over_ui": _mouse_over_blocking_hud(pos),
		"pos": [pos.x, pos.y],
		"runId": "gesture-poll"
	})
	# #endregion
	if was_box:
		_box_select(drag_start, pos)
	else:
		_left_click(pos)

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
	if auto_launch_btn:
		var ar = Rect2(auto_launch_btn.global_position, auto_launch_btn.size)
		if ar.has_point(pos):
			return true
	if sync_move_btn:
		var sr = Rect2(sync_move_btn.global_position, sync_move_btn.size)
		if sr.has_point(pos):
			return true
	if hud:
		var right_col = hud.find_child("RightCol", true, false) as Control
		if right_col and right_col.visible:
			var rr = Rect2(right_col.global_position, right_col.size)
			if rr.has_point(pos):
				return true
	if detail and detail.visible:
		var dr = Rect2(detail.global_position, detail.size)
		if dr.has_point(pos):
			return true
	return false

func _handle_key(e: InputEventKey) -> void:
	if e.ctrl_pressed and e.keycode >= KEY_0 and e.keycode <= KEY_9:
		var g = e.keycode - KEY_0
		## Clear this group number from other assignments first
		for gk in control_groups.keys():
			if int(gk) == g:
				continue
		control_groups[g] = selection.filter(func(id): return _unit_by_id(id).get("faction", 0) == viewer_faction)
		_refresh_all_group_badges()
		# #region agent log
		_dbg59("GRP", "board_root._handle_key", "set_group", {
			"g": g, "n": (control_groups[g] as Array).size(), "runId": "ctrl-group"
		})
		# #endregion
		return
	if not e.ctrl_pressed and e.keycode >= KEY_0 and e.keycode <= KEY_9:
		var g2 = e.keycode - KEY_0
		selection = control_groups.get(g2, []).duplicate()
		return

func _pilot_group_numbers(p: Dictionary) -> Array:
	var uid := str(p.get("unit_id", ""))
	var out: Array = []
	if uid == "":
		return out
	for gk in control_groups.keys():
		var arr: Array = control_groups[gk]
		if arr.has(uid):
			out.append(int(gk))
	out.sort()
	return out

func _refresh_pilot_row_group_badge(row: Control, p: Dictionary) -> void:
	if row == null:
		return
	var lab = row.find_child("GroupBadge", true, false) as Label
	if lab == null:
		return
	var nums = _pilot_group_numbers(p)
	if nums.is_empty():
		lab.text = ""
		lab.visible = false
	else:
		var parts: PackedStringArray = PackedStringArray()
		for n in nums:
			parts.append(str(n))
		lab.text = "编组 " + ", ".join(parts)
		lab.visible = true

func _refresh_all_group_badges() -> void:
	if left_rows == null:
		return
	for row in left_rows.get_children():
		var pid = str(row.get_meta("pilot", ""))
		var p = _pilot_by_id(pid)
		if not p.is_empty():
			_refresh_pilot_row_group_badge(row, p)

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
	## RMB only. LMB press/release lives in _consume_lmb_gesture.
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			return
		# #region agent log
		_agent_dbg("H2", "board_root._handle_mouse_button", "RMB release", {
			"sel": selection.duplicate(), "pos": [mb.position.x, mb.position.y]
		})
		# #endregion
		_right_click(mb.position)

func _has_friendly_selection() -> bool:
	for sid0 in selection:
		var su = _unit_by_id(str(sid0))
		if su and su.get("alive", false) and int(su["faction"]) == viewer_faction \
				and bool(su.get("commandable", true)):
			return true
	return false

func _clear_selection() -> void:
	selection.clear()
	_starmap_set_highlight("")
	_detail_dirty = true
	_update_detail()

func _right_click(screen_pos: Vector2) -> void:
	## CNC: RMB on empty ground clears selection. RMB does not move or attack.
	if cam and cam.starmap_mode:
		var sid := _pick_starmap_system(screen_pos)
		if sid == "":
			var cell_s = _pick_cell(screen_pos)
			sid = str(cell_s.get("sys", ""))
		if sid == "":
			_clear_selection()
		# #region agent log
		_dbg59("RMB", "board_root._right_click", "rmb_starmap", {
			"sid": sid, "cleared": sid == "", "runId": "cnc-lmb"
		})
		# #endregion
		return
	var uhit = _pick_unit(screen_pos, false)
	# #region agent log
	_dbg59("RMB", "board_root._right_click", "right_click", {
		"unit_hit": str(uhit.get("id", "")),
		"sel_n": selection.size(),
		"runId": "cnc-lmb"
	})
	# #endregion
	if uhit.is_empty():
		_clear_selection()
		return
	selection = [uhit["id"]]
	_detail_dirty = true
	_update_detail()
	_open_unit_menu(uhit, screen_pos)

func _left_click(screen_pos: Vector2) -> void:
	if cam and cam.starmap_mode:
		## LMB: 点系全选；已选再点他系 → 落进系星门并待命。
		_starmap_click(screen_pos, false)
		return
	var u = _tac_plate_pick_unit(screen_pos)
	var cell = _pick_cell(screen_pos)
	var has_friendly_sel := _has_friendly_selection()
	# #region agent log
	_dbg59("SEL", "board_root._left_click", "left_click", {
		"unit": str(u.get("id", "")),
		"garrison": bool(u.get("garrison", false)) if not u.is_empty() else false,
		"has_cell": not cell.is_empty(),
		"friendly_sel": has_friendly_sel,
		"tac": cam.tactical_mode if cam else false,
		"runId": "cnc-lmb"
	})
	# #endregion
	## Friendly hull (incl. pledged sleeper plate in tactical): select, do not march onto it.
	if not u.is_empty() and int(u.get("faction", -1)) == viewer_faction:
		selection = [u["id"]]
		_detail_dirty = true
		_update_detail()
		return
	if has_friendly_sel:
		if not u.is_empty():
			var rel_atk := _rel_for(int(u["faction"]))
			if rel_atk == "hostile":
				## Commandable hostiles always; tactical sleeper full plate also attackable.
				var can_atk := bool(u.get("commandable", true)) \
					or (bool(u.get("garrison", false)) and cam != null \
						and cam.tactical_mode and not cam.starmap_mode)
				if can_atk:
					_order_attack_focus(u)
					# #region agent log
					_dbg59("ATK", "board_root._left_click", "order_attack", {
						"tgt": str(u.get("id", "")), "sel_n": selection.size(),
						"garrison": bool(u.get("garrison", false)), "runId": "cnc-lmb"
					})
					# #endregion
					return
		if not cell.is_empty():
			_batch_order_move_to_cell(str(cell["sys"]), int(cell["cell"]))
			return
	if not u.is_empty():
		selection = [u["id"]]
		_detail_dirty = true
		_update_detail()

func _selection_movers() -> Array:
	var movers: Array = []
	for id in selection:
		var un = _unit_by_id(str(id))
		if un.is_empty() or int(un["faction"]) != viewer_faction:
			continue
		if not un.get("alive", false) or not bool(un.get("commandable", true)):
			continue
		movers.append(un)
	return movers

func _batch_order_move_to_cell(to_sys: String, to_cell: int) -> void:
	var movers: Array = _selection_movers()
	if movers.is_empty():
		return
	## Always allocate batch_id for shared sleeper click/dest; sync_gid only when toggle on.
	_sync_gid_next += 1
	var batch_id := _sync_gid_next
	var sync_gid := batch_id if sync_move_enabled else 0
	var adj := _apply_sleeper_cell_order_group(movers, to_sys, to_cell, batch_id)
	var dest_sys := str(adj.get("sys", to_sys))
	var dest_cell := int(adj.get("cell", to_cell))
	var focus := str(adj.get("focus_id", ""))
	for un in movers:
		if sync_gid > 0:
			un["sync_gid"] = sync_gid
		else:
			un.erase("sync_gid")
		if focus != "":
			un["focus_id"] = focus
		_queue_unit_move(un, dest_sys, dest_cell)
	# #region agent log
	_dbg59("SYNC", "board_root._batch_order_move_to_cell", "batch", {
		"n": movers.size(), "batch": batch_id, "gid": sync_gid,
		"raw": [to_sys, to_cell], "adj": [dest_sys, dest_cell],
		"focus": focus, "runId": "sync-sleeper"
	})
	# #endregion
	_detail_dirty = true

func _order_attack_focus(tgt: Dictionary) -> void:
	## Selected friendlies focus-fire tgt; move to its cell if needed (BOARD_AND_INPUT).
	if tgt.is_empty() or not tgt.get("alive", false):
		return
	var tid := str(tgt["id"])
	var movers: Array = _selection_movers()
	if movers.is_empty():
		return
	_sync_gid_next += 1
	var batch_id := _sync_gid_next
	var sync_gid := batch_id if sync_move_enabled else 0
	var need_move := false
	for un in movers:
		un["focus_id"] = tid
		if sync_gid > 0:
			un["sync_gid"] = sync_gid
		else:
			un.erase("sync_gid")
		if str(un["sys"]) != str(tgt["sys"]) or int(un["cell"]) != int(tgt["cell"]):
			need_move = true
	if need_move:
		var adj := _apply_sleeper_cell_order_group(
			movers, str(tgt["sys"]), int(tgt["cell"]), batch_id
		)
		var dest_sys := str(adj.get("sys", tgt["sys"]))
		var dest_cell := int(adj.get("cell", tgt["cell"]))
		for un2 in movers:
			if str(un2["sys"]) != dest_sys or int(un2["cell"]) != dest_cell:
				_queue_unit_move(un2, dest_sys, dest_cell)
	_detail_dirty = true

func _order_player_move(u: Dictionary, to_sys: String, to_cell: int) -> void:
	## Single-unit path (AI / legacy). Player multi-select uses _batch_order_move_to_cell.
	if not bool(u.get("commandable", true)):
		return
	var movers: Array = [u]
	_sync_gid_next += 1
	var batch_id := _sync_gid_next
	var adj := _apply_sleeper_cell_order_group(movers, to_sys, to_cell, batch_id)
	if str(adj.get("focus_id", "")) != "":
		u["focus_id"] = str(adj.get("focus_id", ""))
	_queue_unit_move(u, str(adj.get("sys", to_sys)), int(adj.get("cell", to_cell)))

func _queue_unit_move(u: Dictionary, dest_sys: String, dest_cell: int) -> void:
	u["order_dest_sys"] = dest_sys
	u["order_dest_cell"] = dest_cell
	_ensure_move_line(u, dest_sys, dest_cell)
	var uid = str(u["id"])
	var filtered: Array = []
	for o in _order_queue:
		if str(o.get("id", "")) != uid:
			filtered.append(o)
	filtered.append({"id": uid, "sys": dest_sys, "cell": dest_cell})
	_order_queue = filtered
	# #region agent log
	_dbg59("NAV", "board_root._queue_unit_move", "order_queued", {
		"unit": uid, "to": [dest_sys, dest_cell], "q": _order_queue.size(),
		"sync": int(u.get("sync_gid", 0)), "runId": "sync-sleeper"
	})
	# #endregion

func _hostile_sleeper_on_cell(sys: String, cell: int, from_fac: int) -> Dictionary:
	for o in units:
		if not o.get("alive", false) or not o.get("garrison", false):
			continue
		if str(o.get("sys", "")) != sys or int(o.get("cell", -1)) != cell:
			continue
		if int(o.get("faction", -1)) == int(from_fac):
			continue
		## Hostile / not same faction garrison (enemy NPC or enemy pledged).
		return o
	return {}

func _unit_max_nonzero_dmg_range(u: Dictionary) -> int:
	var best := 0
	for w in u.get("weapons", []):
		var kind_w := str(w.get("kind", ""))
		if kind_w == "remote_armor" or kind_w == "remote_shield":
			continue
		var rc := int(w.get("range_cells", 0))
		if rc > best:
			best = rc
	for g in u.get("pd", []):
		var rc2 := int(g.get("range_cells", 0))
		if rc2 > best:
			best = rc2
	return best

func _cell_steps_away(sys: String, from_cell: int, to_cell: int) -> int:
	if not map.systems.has(sys):
		return 999
	var n: int = map.systems[sys]["cells"].size()
	return BoardTypes.shorter_arc_steps(from_cell, to_cell, n)

func _cell_along_arc(sys: String, from_cell: int, to_cell: int, stop_steps_before: int) -> int:
	## Walk shorter arc from from→to; stop `stop_steps_before` steps short of to.
	if not map.systems.has(sys):
		return from_cell
	var n: int = map.systems[sys]["cells"].size()
	if n <= 0:
		return from_cell
	var cw := (to_cell - from_cell + n) % n
	var ccw := (from_cell - to_cell + n) % n
	var dir := 1 if cw <= ccw else -1
	var total := mini(cw, ccw)
	var travel := maxi(0, total - stop_steps_before)
	return (from_cell + dir * travel + n * 8) % n

func _apply_sleeper_cell_order_group(
	movers: Array, to_sys: String, to_cell: int, batch_id: int
) -> Dictionary:
	## Shared click count + one adjusted dest for multi-select (SHIPS §10/§13).
	var out := {"sys": to_sys, "cell": to_cell, "focus_id": ""}
	if movers.is_empty():
		return out
	var fac := int(movers[0].get("faction", 0))
	var sleeper := _hostile_sleeper_on_cell(to_sys, to_cell, fac)
	if sleeper.is_empty():
		return out
	## Sync on: shortest non-zero range (whole group can engage).
	## Sync off: longest-range unit is the fleet reference (SHIPS §10).
	var use_longest := not sync_move_enabled
	var range_ref := 0 if use_longest else 999
	var ref_cell := int(movers[0].get("cell", 0))
	var any_r := false
	var same_sys := true
	for m in movers:
		if str(m.get("sys", "")) != to_sys:
			same_sys = false
			continue
		var r := _unit_max_nonzero_dmg_range(m)
		if r <= 0:
			continue
		any_r = true
		if use_longest:
			if r > range_ref:
				range_ref = r
				ref_cell = int(m.get("cell", 0))
		else:
			range_ref = mini(range_ref, r)
	if not any_r or not same_sys:
		return out
	## Stable across clicks (not batch_id) so 1–2–3 count accumulates in the 5s window.
	var id_list: PackedStringArray = PackedStringArray()
	for m0 in movers:
		id_list.append(str(m0.get("id", "")))
	id_list.sort()
	var click_key := "%s@%s:%d" % [",".join(id_list), to_sys, to_cell]
	var now := _battle_clock
	var bag: Dictionary = _order_cell_clicks.get(click_key, {})
	var times: Array = bag.get("times", [])
	var kept: Array = []
	for t in times:
		if now - float(t) <= SLEEPER_ORDER_WINDOW_S:
			kept.append(float(t))
	kept.append(now)
	_order_cell_clicks[click_key] = {"sys": to_sys, "cell": to_cell, "times": kept}
	out["focus_id"] = str(sleeper.get("id", ""))
	if kept.size() >= 3:
		# #region agent log
		_dbg59("SYNC", "board_root._apply_sleeper_cell_order_group", "force_enter", {
			"batch": batch_id, "clicks": kept.size(), "cell": to_cell, "runId": "sync-sleeper"
		})
		# #endregion
		return out
	var approach_cell := ref_cell
	if not use_longest:
		## Sync on: farthest-by-steps defines approach arc.
		var far_steps := -1
		for m3 in movers:
			var st := _cell_steps_away(to_sys, int(m3.get("cell", 0)), to_cell)
			if st > far_steps:
				far_steps = st
				approach_cell = int(m3.get("cell", 0))
	out["cell"] = _cell_along_arc(to_sys, approach_cell, to_cell, range_ref)
	# #region agent log
	_dbg59("SYNC", "board_root._apply_sleeper_cell_order_group", "range_stop", {
		"batch": batch_id, "clicks": kept.size(), "range_ref": range_ref,
		"longest": use_longest, "approach": approach_cell,
		"raw": to_cell, "adj": out["cell"],
		"focus": out["focus_id"], "runId": "sync-sleeper"
	})
	# #endregion
	return out

func _drain_order_queue(budget: int) -> void:
	## Drain up to budget; when sync_gid set, flush all peers in the same call.
	var spent := 0
	while spent < budget and not _order_queue.is_empty():
		var o: Dictionary = _order_queue.pop_front()
		spent += 1
		var u = _unit_by_id(str(o.get("id", "")))
		if u.is_empty() or not u.get("alive", false):
			continue
		_pathfind_apply(u, str(o["sys"]), int(o["cell"]))
		var gid := int(u.get("sync_gid", 0))
		## Only flock-flush while sync toggle is on (gid alone must not keep syncing when 关).
		if gid <= 0 or not sync_move_enabled:
			continue
		var kept: Array = []
		var flushed := 0
		for o2 in _order_queue:
			var u2 = _unit_by_id(str(o2.get("id", "")))
			if not u2.is_empty() and u2.get("alive", false) \
					and int(u2.get("sync_gid", 0)) == gid:
				_pathfind_apply(u2, str(o2["sys"]), int(o2["cell"]))
				flushed += 1
			else:
				kept.append(o2)
		_order_queue = kept
		# #region agent log
		if flushed > 0:
			_dbg59("SYNC", "board_root._drain_order_queue", "flush_gid", {
				"gid": gid, "flushed": flushed, "runId": "sync-solo"
			})
		# #endregion

func _pathfind_apply(u: Dictionary, to_sys: String, to_cell: int) -> void:
	u["order_dest_sys"] = to_sys
	u["order_dest_cell"] = to_cell
	var ph: int = int(u.get("phase", 0))
	## INVULN / LANDING: remember dest only — current hop locked.
	if ph == BoardTypes.MovePhase.INVULN or ph == BoardTypes.MovePhase.LANDING:
		_ensure_move_line(u, to_sys, to_cell)
		# #region agent log
		_dbg59("PREP", "board_root._pathfind_apply", "dest_queued_locked", {
			"unit": u["id"], "phase": ph, "to": [to_sys, to_cell], "runId": "prep-retarget"
		})
		# #endregion
		return
	## PREP: retarget without resetting align timer (prep is not cell-tagged).
	if ph == BoardTypes.MovePhase.PREP:
		_retarget_during_prep(u, to_sys, to_cell)
		return
	# Same-system: O(1) path — skip graph BFS cost
	var prep = BoardTypes.align_prep_s(u["inertia"], u["mass"])
	if str(u["sys"]) == to_sys:
		if int(u["cell"]) == to_cell:
			u["path"] = []
			u.erase("order_dest_sys")
			u.erase("order_dest_cell")
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
	var blocked := false
	if str(u["sys"]) != to_sys:
		var at_goal := str(u["sys"]) == to_sys and int(u["cell"]) == to_cell
		blocked = not at_goal and u["path"].is_empty()
		if not u["path"].is_empty():
			var last: Dictionary = u["path"][u["path"].size() - 1]
			if str(last.get("kind", "")) != "jump" and str(last.get("sys", "")) != to_sys:
				blocked = true
	_dbg59("NAV", "board_root._pathfind_apply", "path_ready", {
		"unit": u["id"], "from": [u["sys"], u["cell"]], "to": [to_sys, to_cell],
		"path_len": u["path"].size(), "blocked_wait": blocked, "runId": "nav-phase"
	})
	_agent_dbg("P1", "board_root._pathfind_apply", "path_ready", {
		"unit": u["id"], "path_len": u["path"].size(), "runId": "post-fix"
	})
	# #endregion
	admin.request("board.move", {"unit": u["id"], "path": u["path"]})

func _retarget_during_prep(u: Dictionary, to_sys: String, to_cell: int) -> void:
	## Keep phase_t; rewrite hop destination. Prep is generic align, not cell-tagged.
	var from_sys := str(u.get("from_sys", u["sys"]))
	var from_cell := int(u.get("from_cell", u["cell"]))
	## Same cell as origin → cancel prep, stand by.
	if to_sys == from_sys and int(to_cell) == from_cell:
		_cancel_prep_standby(u)
		return
	if str(u.get("step_kind", "")) == "jump" and starmap_view:
		starmap_view.transit_gates.erase("%s:%d" % [from_sys, from_cell])
	if to_sys == from_sys:
		var dest = _bubble_redirect(from_sys, from_cell, to_cell, u)
		if dest == from_cell:
			_cancel_prep_standby(u)
			return
		u["to_sys"] = from_sys
		u["to_cell"] = dest
		u["step_kind"] = "intra"
		u["step_invuln"] = float(u["move_s"])
		if sync_move_enabled and int(u.get("sync_gid", 0)) > 0:
			u["step_invuln"] = _sync_max_step_duration(int(u["sync_gid"]), "intra", float(u["step_invuln"]))
		u["path"] = []
		_assign_reserve(u)
	else:
		var prep = float(u.get("phase_t", BoardTypes.align_prep_s(u["inertia"], u["mass"])))
		var path = BoardPlayerNav.find_path(
			map, data.diplomacy, u["faction"],
			from_sys, from_cell, to_sys, to_cell,
			prep, u["move_s"], u["landing_s"], u["jump_s"]
		)
		if path.is_empty():
			u["path"] = []
			_ensure_move_line(u, to_sys, to_cell)
			# #region agent log
			_dbg59("PREP", "board_root._retarget_during_prep", "blocked", {
				"unit": u["id"], "to": [to_sys, to_cell], "runId": "prep-retarget"
			})
			# #endregion
			return
		var step: Dictionary = path.pop_front()
		u["path"] = path
		u["to_cell"] = int(step["to"])
		u["step_kind"] = step["kind"]
		if step["kind"] == "jump":
			u["to_sys"] = step.get("to_sys", to_sys)
			u["from_pos"] = starmap_view.gate_outer_point(from_sys, u["to_sys"]) if starmap_view else map.cell_world_pos(from_sys, from_cell, BoardTypes.UNIT_Y)
			u["from_pos"].y = BoardTypes.UNIT_Y
			u["to_pos"] = starmap_view.gate_outer_point(u["to_sys"], from_sys) if starmap_view else map.cell_world_pos(u["to_sys"], int(u["to_cell"]), BoardTypes.UNIT_Y)
			u["to_pos"].y = BoardTypes.UNIT_Y
			var gk = "%s:%d" % [from_sys, from_cell]
			starmap_view.transit_gates[gk] = true
			u["step_invuln"] = float(u["jump_s"])
		else:
			u["to_sys"] = from_sys
			var dest2 = _bubble_redirect(from_sys, from_cell, int(u["to_cell"]), u)
			u["to_cell"] = dest2
			u["step_invuln"] = float(u["move_s"])
		_assign_reserve(u)
	_ensure_move_line(u, to_sys, to_cell)
	# #region agent log
	_dbg59("PREP", "board_root._retarget_during_prep", "retarget", {
		"unit": u["id"], "to_cell": int(u["to_cell"]), "to_sys": str(u["to_sys"]),
		"phase_t": float(u.get("phase_t", 0)), "kind": str(u.get("step_kind", "")),
		"runId": "prep-retarget"
	})
	# #endregion
	admin.request("board.move", {"unit": u["id"], "phase": "prep_retarget", "to": [to_sys, to_cell]})

func _cancel_prep_standby(u: Dictionary) -> void:
	var from_sys := str(u.get("from_sys", u["sys"]))
	var from_cell := int(u.get("from_cell", u["cell"]))
	if str(u.get("step_kind", "")) == "jump" and starmap_view:
		starmap_view.transit_gates.erase("%s:%d" % [from_sys, from_cell])
	u["phase"] = BoardTypes.MovePhase.IDLE
	u["phase_t"] = 0.0
	u["alpha"] = 1.0
	u["path"] = []
	u["sys"] = from_sys
	u["cell"] = from_cell
	u.erase("order_dest_sys")
	u.erase("order_dest_cell")
	_clear_reserve(u)
	_clear_move_line(str(u["id"]))
	u["pos"] = _clamp_pos_to_cell(from_sys, from_cell, u["pos"])
	u["rest_pos"] = Vector3(u["pos"].x, BoardTypes.UNIT_Y, u["pos"].z)
	## Keep sync_gid until whole group is packed on one cell (SHIPS §10).
	_sync_try_clear_gid(u)
	# #region agent log
	_dbg59("PREP", "board_root._cancel_prep_standby", "cancel_self_cell", {
		"unit": u["id"], "sys": from_sys, "cell": from_cell, "runId": "prep-cancel"
	})
	# #endregion
	admin.request("board.move", {"unit": u["id"], "phase": "idle_cancel"})

func _tick_nav_resume(delta: float) -> void:
	## Idle at blocked gate with a remembered dest → repath when gate opens.
	for u in units:
		if not u.get("alive", false):
			continue
		if int(u.get("faction", 0)) != viewer_faction:
			continue
		if int(u.get("phase", 0)) != BoardTypes.MovePhase.IDLE:
			continue
		if not u["path"].is_empty():
			continue
		if not u.has("order_dest_sys"):
			continue
		var ds: String = str(u["order_dest_sys"])
		var dc: int = int(u["order_dest_cell"])
		if str(u["sys"]) == ds and int(u["cell"]) == dc:
			u.erase("order_dest_sys")
			u.erase("order_dest_cell")
			continue
		var acc := float(u.get("nav_retry_acc", 0.0)) + delta
		if acc < 0.45:
			u["nav_retry_acc"] = acc
			continue
		u["nav_retry_acc"] = 0.0
		var before_len: int = u["path"].size()
		_pathfind_apply(u, ds, dc)
		# #region agent log
		if u["path"].size() != before_len or (not u["path"].is_empty()):
			_dbg59("NAV", "board_root._tick_nav_resume", "repath", {
				"unit": u["id"], "sys": u["sys"], "cell": int(u["cell"]),
				"dest": [ds, dc], "path_len": u["path"].size(), "runId": "nav-phase"
			})
		# #endregion

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
		if bool(u.get("garrison", false)) or not bool(u.get("commandable", true)):
			continue
		var world_pos: Vector3 = u["pos"]
		if cam.tactical_mode and unit_nodes.has(u["id"]):
			var ohb = unit_nodes[u["id"]].get_node_or_null("Overhead") as Node3D
			if ohb:
				world_pos = ohb.global_position
		elif unit_nodes.has(u["id"]):
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
		# #region agent log
		_dbg59("SEL", "board_root._box_select", "box", {
			"n": found.size(), "ids": found.duplicate(), "runId": "ui-fix"
		})
		# #endregion

func _open_unit_menu(u: Dictionary, screen_pos: Vector2) -> void:
	popup.clear()
	popup.set_meta("pilot", "")
	var star := cam != null and cam.starmap_mode
	if int(u["faction"]) == viewer_faction:
		## Toggle labels show current state (UI_AND_SHELL §2.1), not the next action.
		popup.add_item("拦截泡：%s" % ("开" if u.get("bubble_on", false) else "关"), 1)
		popup.add_item("停止", 2)
		popup.add_item("视角跟随" if cam.follow_unit_id != u["id"] else "取消跟随", 3)
		popup.set_item_disabled(popup.get_item_index(3), star)
		var g: Dictionary = u.get("guard", {})
		var fo = g.get("field_on", false)
		popup.add_item("舰队护卫立场：%s" % ("开" if fo else "关"), 13)
		popup.set_item_disabled(popup.get_item_index(13), not g.get("field_fitted", false))
		## Fitted → missing auto key reads as 开 (birth default).
		var fa = bool(g.get("field_auto_on", true)) if g.get("field_fitted", false) else false
		popup.add_item("舰队护卫立场自动：%s" % ("开" if fa else "关"), 10)
		popup.set_item_disabled(popup.get_item_index(10), not g.get("field_fitted", false))
		var la = bool(g.get("link_auto_on", true)) if g.get("link_fitted", false) else false
		popup.add_item("舰队护卫链接自动：%s" % ("开" if la else "关"), 11)
		popup.set_item_disabled(popup.get_item_index(11), not g.get("link_fitted", false))
		var has_imp := str(u.get("implant", {}).get("ref", "")) != ""
		var ia = bool(u.get("implant", {}).get("auto_on", true)) if has_imp else false
		popup.add_item("植入自动：%s" % ("开" if ia else "关"), 12)
		popup.set_item_disabled(popup.get_item_index(12), not has_imp)
		var can_dock = _can_dock(u)
		popup.add_item("进站", 4)
		popup.set_item_disabled(popup.get_item_index(4), not can_dock)
	else:
		popup.add_item("视角跟随" if cam.follow_unit_id != u["id"] else "取消跟随", 3)
		popup.set_item_disabled(popup.get_item_index(3), star)
		popup.add_item("舰队护卫立场：关", 13)
		popup.set_item_disabled(popup.get_item_index(13), true)
		popup.add_item("舰队护卫立场自动：关", 10)
		popup.set_item_disabled(popup.get_item_index(10), true)
		popup.add_item("舰队护卫链接自动：关", 11)
		popup.set_item_disabled(popup.get_item_index(11), true)
		popup.add_item("植入自动：关", 12)
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
			if cam and cam.starmap_mode:
				return
			if cam.follow_unit_id == u["id"]:
				cam.clear_follow_keep_look()
			else:
				cam.set_follow(u["id"])
		4:
			_dock_unit(u)
		10:
			if u.has("guard") and u["guard"].get("field_fitted", false):
				u["guard"]["field_auto_on"] = not bool(u["guard"].get("field_auto_on", true))
				_tick_guard_reopen(u)
		11:
			if u.has("guard") and u["guard"].get("link_fitted", false):
				u["guard"]["link_auto_on"] = not bool(u["guard"].get("link_auto_on", true))
				_tick_guard_reopen(u)
		12:
			if u.has("implant") and str(u.get("implant", {}).get("ref", "")) != "":
				u["implant"]["auto_on"] = not bool(u.get("implant", {}).get("auto_on", true))
		13:
			if u.has("guard") and u["guard"].get("field_fitted", false):
				var gon: bool = not u["guard"].get("field_on", false)
				u["guard"]["field_on"] = gon
				if not gon:
					u["guard"]["field_auto_on"] = false
				_tick_guard_reopen(u)

func _dock_unit(u: Dictionary) -> void:
	if not _can_dock(u):
		return
	var p = _pilot_by_id(u["pilot_id"])
	if p.is_empty():
		return
	_remember_last_ship(p, u)
	p["current_station"] = u["sys"]
	p["in_station"] = true
	pilots_sys.dock_ship(p, u["inst"])
	u["alive"] = false
	u["phase"] = BoardTypes.MovePhase.IDLE
	u["phase_t"] = 0.0
	u["path"] = []
	u.erase("land_pos")
	_clear_reserve(u)
	_clear_move_line(str(u["id"]))
	p["unit_id"] = ""
	if unit_nodes.has(u["id"]):
		unit_nodes[u["id"]].visible = false
		var oh2 = unit_nodes[u["id"]].get_node_or_null("Overhead")
		if oh2 and oh2.has_method("set_alive_view"):
			oh2.set_alive_view(false)
		var body = unit_nodes[u["id"]].get_node_or_null("PickBody") as StaticBody3D
		if body:
			body.collision_layer = 0
	selection.erase(u["id"])
	_rebuild_hud_list()

func _on_left_selected(index: int) -> void:
	var pid: String = str(left_list.get_item_metadata(index))
	var p = _pilot_by_id(pid)
	if p.is_empty():
		return
	var uid = str(p.get("unit_id", ""))
	if uid != "":
		selection = [uid]
		if cam and cam.tactical_mode:
			var uu = _unit_by_id(uid)
			if uu and uu.get("alive", false):
				cam.set_follow(uid)
				cam.update_follow_pos(uu["pos"])
	_update_detail()

func _fx_ok() -> bool:
	## Tactical top-down keeps plate↔plate beams (TACTICAL_TOPDOWN). Starmap silences FX.
	return cam == null or not cam.starmap_mode

func _play_turret_vfx(fx_kind: String, from: Vector3, to: Vector3) -> void:
	if not _fx_ok() or turret_vfx == null:
		return
	var c3d: Camera3D = cam.cam if cam != null else null
	## Tactical: beam width = tonnage icon circumscribed-circle radius (relative to plate scale).
	var thick_wu := 0.0
	if cam != null and cam.tactical_mode and not cam.starmap_mode:
		thick_wu = BoardUnitOverhead.icon_circum_radius_world()
	turret_vfx.play(fx_kind, from, to, c3d, thick_wu)

func _on_tactical_changed(on: bool) -> void:
	_set_tactical_mode(on)

func _on_starmap_changed(on: bool) -> void:
	if on and cam:
		cam.clear_follow_keep_look()
	_apply_view_tier(cam.view_tier() if cam else ("starmap" if on else "tactical"))

func _on_view_tier_changed(tier: String) -> void:
	_apply_view_tier(tier)

func _set_tactical_mode(on: bool) -> void:
	if _world_env and _world_env.environment and on:
		var e: Environment = _world_env.environment
		## Remember battle sky once; tactical uses black, starmap restores sky (底图).
		if _env_bg_mode_saved < 0:
			_env_bg_mode_saved = e.background_mode
			_env_bg_color_saved = e.background_color
			_env_had_sky = e.sky != null
	var tier := "battle"
	if on:
		tier = "starmap" if (cam and cam.starmap_mode) else "tactical"
	else:
		tier = "battle"
	_apply_env_for_tier(tier)
	_apply_view_tier(tier)
	# #region agent log
	_agent_dbg("TAC", "board_root._set_tactical_mode", "tactical", {
		"on": on, "tier": tier,
		"font": TACTICAL_FONT_SCALE, "icon": TACTICAL_ICON_SCALE,
		"jagged": TACTICAL_BORDER_JAGGED, "sysname": TACTICAL_SYSNAME_SCALE,
		"runId": "tiers"
	})
	# #endregion


func _apply_env_for_tier(tier: String) -> void:
	## 战术+星图：纯黑环境；战场：全景 sky。星图「底图」是 Territory，不是天空盒。
	if _world_env == null or _world_env.environment == null:
		return
	var e: Environment = _world_env.environment
	if tier == "tactical" or tier == "starmap":
		if _env_bg_mode_saved < 0:
			_env_bg_mode_saved = e.background_mode
			_env_bg_color_saved = e.background_color
			_env_had_sky = e.sky != null
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0, 0, 0, 1)
		return
	if _env_bg_mode_saved >= 0:
		e.background_mode = _env_bg_mode_saved as Environment.BGMode
		e.background_color = _env_bg_color_saved
	elif e.sky != null:
		e.background_mode = Environment.BG_SKY


func _apply_view_tier(tier: String) -> void:
	var tac := tier == "tactical" or tier == "starmap"
	var star := tier == "starmap"
	_apply_env_for_tier(tier)
	if tactical_callouts:
		tactical_callouts.set_active(tier == "tactical")
	if starmap_view and starmap_view.has_method("set_territory_visible"):
		## Territory 底图：战术与星图都显示。
		starmap_view.set_territory_visible(tier == "tactical" or tier == "starmap")
	if starmap_view and starmap_view.has_method("set_view_tier"):
		starmap_view.set_view_tier(tier)
	if not tac:
		_unit_oh_cell.clear()
	for u in units:
		if not unit_nodes.has(u["id"]):
			continue
		var n: Node3D = unit_nodes[u["id"]]
		_apply_unit_tactical_vis(n, tac)
		var oh = n.get_node_or_null("Overhead")
		if oh:
			oh.visible = not star
		## 星图: hide ship chrome entirely (counts live on StarmapGraph).
		if star:
			n.visible = false
		if not tac and cam and cam.cam:
			if oh and oh.has_method("face_camera"):
				oh.face_camera(cam.cam, u["pos"])
	if star:
		for lid in _move_lines.keys():
			var ln = _move_lines[lid]
			if ln is Node3D:
				(ln as Node3D).visible = false
		_sync_starmap_rep_badges()
	elif starmap_view and starmap_view.has_method("sync_rep_badges"):
		## Tear down point-line graph when leaving 星图.
		starmap_view.sync_rep_badges({})


func _sync_starmap_rep_badges() -> void:
	if starmap_view == null or not starmap_view.has_method("sync_rep_badges"):
		return
	var counts: Dictionary = {}
	var skipped_empty_hostile := 0
	for u in units:
		if not u.get("alive", false):
			continue
		var sid := str(u.get("sys", ""))
		if sid == "":
			continue
		var rel := _rel_for(int(u["faction"]))
		var bucket := "hostile"
		if rel == "self":
			bucket = "self"
		elif rel == "ally" or rel == "allied" or rel == "friendly" or rel == "fleet":
			bucket = "ally"
		## 星图：空白格敌对不统计。
		if bucket == "hostile" and _is_hostile_on_empty_cell(u):
			skipped_empty_hostile += 1
			continue
		if not counts.has(sid):
			counts[sid] = {"self": 0, "ally": 0, "hostile": 0}
		counts[sid][bucket] = int(counts[sid][bucket]) + 1
	# #region agent log
	_dbg59("EH1", "board_root._sync_starmap_rep_badges", "counts", {
		"skipped_empty_hostile": skipped_empty_hostile,
		"sys_n": counts.size(), "runId": "starmap-select"
	})
	# #endregion
	starmap_view.sync_rep_badges(counts)


func _is_hostile_on_empty_cell(u: Dictionary) -> bool:
	if u.is_empty() or not u.get("alive", false):
		return false
	var rel := _rel_for(int(u.get("faction", 0)))
	if rel != "hostile" and rel != "enemy":
		return false
	var sid := str(u.get("sys", ""))
	var ci := int(u.get("cell", -1))
	if map == null or sid == "" or ci < 0 or not map.systems.has(sid):
		return false
	var cells: Array = map.systems[sid].get("cells", [])
	if ci >= cells.size():
		return false
	return int(cells[ci].get("kind", -1)) == BoardTypes.CellKind.EMPTY

func _cell_has_non_npc_unit(sys: String, cell: int) -> bool:
	## Non-garrison ship of a non-NPC faction (pledged sleepers do NOT count).
	for o in units:
		if not o.get("alive", false):
			continue
		if bool(o.get("garrison", false)):
			continue
		if str(o.get("sys", "")) != sys or int(o.get("cell", -1)) != cell:
			continue
		if not data.is_npc_faction(int(o.get("faction", 0))):
			return true
	return false

func _sleeper_on_cell_locked(sys: String, cell: int) -> bool:
	for o in units:
		if not o.get("alive", false) or not o.get("garrison", false):
			continue
		if str(o.get("sys", "")) != sys or int(o.get("cell", -1)) != cell:
			continue
		var oid := str(o.get("id", ""))
		for other in units:
			if not other.get("alive", false):
				continue
			if str(other.get("focus_id", "")) == oid:
				return true
			for w in other.get("weapons", []):
				if str(w.get("lock_id", "")) == oid:
					return true
	return false

func _sleeper_plate_expanded(u: Dictionary) -> bool:
	## Full plate / callout when same-cell non-sleeper, or any sleeper on cell locked.
	## Same gate for battle and tactical (SHIPS §12–13); unexpanded tactical → no callout.
	if not u.get("alive", false):
		return true
	if not u.get("garrison", false):
		return true
	var sys := str(u.get("sys", ""))
	var cell := int(u.get("cell", -1))
	if _cell_has_non_npc_unit(sys, cell):
		return true
	if _sleeper_on_cell_locked(sys, cell):
		return true
	return false

func _tac_plate_pick_unit(screen_pos: Vector2) -> Dictionary:
	## Tactical: commandable first; else garrison full-plate hit for details/attack.
	var u := _pick_unit(screen_pos, false)
	if not u.is_empty():
		return u
	if cam == null or not cam.tactical_mode or cam.starmap_mode:
		return {}
	var any := _pick_unit(screen_pos, true)
	if any.is_empty():
		return {}
	if bool(any.get("garrison", false)) or not bool(any.get("commandable", true)):
		return any
	return {}


func _sov_cell_of(sid: String) -> int:
	if map == null or not map.systems.has(sid):
		return -1
	for c in map.systems[sid]["cells"]:
		if int(c.get("kind", -1)) == BoardTypes.CellKind.SOV:
			return int(c.get("index", -1))
	return -1


func _starmap_arrival_gate(from_sys: String, to_sys: String) -> int:
	## 进入 to_sys 时落点：拓扑最短路上对侧星门（gate_to = 上一跳系）。
	if map == null or from_sys == "" or to_sys == "" or from_sys == to_sys:
		return -1
	var parent: Dictionary = {}
	var q: Array = [from_sys]
	parent[from_sys] = ""
	while not q.is_empty():
		var s: String = str(q.pop_front())
		if s == to_sys:
			break
		if not map.systems.has(s):
			continue
		for link in map.systems[s].get("links", []):
			var lk := str(link)
			if parent.has(lk):
				continue
			parent[lk] = s
			q.append(lk)
	var prev := str(parent.get(to_sys, ""))
	if prev == "":
		prev = from_sys
	return map.find_cell_of_kind(to_sys, BoardTypes.CellKind.GATE, prev)


func _pick_starmap_system(screen_pos: Vector2) -> String:
	## 点线层点选：按系心投影距离（环 pick 打不到系心）。
	if cam == null or cam.cam == null or map == null:
		return ""
	var best := ""
	var best_d := 72.0 ## px
	for sid in map.systems.keys():
		var center: Vector3 = map.systems[sid]["center"]
		var wp := Vector3(center.x, 0.12, center.z)
		if cam.cam.is_position_behind(wp):
			continue
		var sp: Vector2 = cam.cam.unproject_position(wp)
		var d := sp.distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = str(sid)
	return best


func _selection_all_in_sys(sid: String) -> bool:
	if selection.is_empty() or sid == "":
		return false
	for id in selection:
		var u = _unit_by_id(id)
		if u.is_empty() or not u.get("alive", false):
			continue
		if str(u.get("sys", "")) != sid:
			return false
	return true


func _select_friendlies_in_sys(sid: String) -> void:
	var found: Array = []
	for u in units:
		if not u.get("alive", false):
			continue
		if str(u.get("sys", "")) != sid:
			continue
		if int(u["faction"]) != viewer_faction:
			continue
		found.append(u["id"])
	selection = found
	_detail_dirty = true
	_update_detail()


func _starmap_set_highlight(sid: String) -> void:
	if starmap_view and starmap_view.has_method("set_starmap_highlight"):
		starmap_view.set_starmap_highlight(sid)


func _starmap_click(screen_pos: Vector2, force_order: bool) -> void:
	var sid := _pick_starmap_system(screen_pos)
	if sid == "":
		## Fallback: ring sector pick (tactical geometry still valid).
		var cell = _pick_cell(screen_pos)
		sid = str(cell.get("sys", ""))
	if sid == "":
		return
	_starmap_set_highlight(sid)
	var want_order := force_order or (not selection.is_empty() and not _selection_all_in_sys(sid))
	if want_order and not selection.is_empty():
		var batch_gid := 0
		if sync_move_enabled:
			_sync_gid_next += 1
			batch_gid = _sync_gid_next
		var ordered := 0
		for id in selection:
			var un = _unit_by_id(id)
			if un.is_empty() or int(un["faction"]) != viewer_faction:
				continue
			if not un.get("alive", false):
				continue
			var from_sys := str(un.get("sys", ""))
			if from_sys == sid:
				continue ## 已在目标系：不改航
			var gate_i := _starmap_arrival_gate(from_sys, sid)
			if gate_i < 0:
				gate_i = _sov_cell_of(sid)
			if gate_i < 0:
				continue
			if batch_gid > 0:
				un["sync_gid"] = batch_gid
			else:
				un.erase("sync_gid")
			un["nav_standby_on_sys_enter"] = true
			_order_player_move(un, sid, gate_i)
			ordered += 1
		# #region agent log
		_dbg59("SS1", "board_root._starmap_click", "order_gate", {
			"sid": sid, "ordered": ordered, "sel": selection.size(),
			"force": force_order, "runId": "starmap-select"
		})
		# #endregion
		_detail_dirty = true
		return
	_select_friendlies_in_sys(sid)
	# #region agent log
	_dbg59("SS2", "board_root._starmap_click", "select_sys", {
		"sid": sid, "sel": selection.size(), "runId": "starmap-select"
	})
	# #endregion

func _apply_unit_tactical_vis(n: Node3D, tactical: bool) -> void:
	if n == null:
		return
	var model = n.get_node_or_null("Model")
	if model:
		model.visible = not tactical
	var proxy = n.get_node_or_null("Proxy") as MeshInstance3D
	if proxy:
		## Proxy only as fallback when no Model and not tactical.
		if tactical:
			proxy.visible = false
		elif model == null:
			proxy.visible = true
	var trail = n.get_node_or_null("Trail")
	if trail and tactical:
		trail.visible = false
	var ring = n.get_node_or_null("SelectRing")
	var ring_ol = n.get_node_or_null("SelectRingOutline")
	if tactical:
		if ring:
			ring.visible = false
		if ring_ol:
			ring_ol.visible = false
	var body = n.get_node_or_null("PickBody") as StaticBody3D
	if body:
		var uid_pick := str(n.name)
		var uu_pick = _unit_by_id(uid_pick)
		var garrison_inert := not uu_pick.is_empty() and (
			bool(uu_pick.get("garrison", false)) or not bool(uu_pick.get("commandable", true))
		)
		if tactical or garrison_inert:
			body.collision_layer = 0
		else:
			body.collision_layer = 1
			body.set_collision_layer_value(1, true)

func _sync_tactical_overheads(_delta: float) -> void:
	if tactical_callouts == null or cam == null or cam.cam == null:
		return
	for u in units:
		if not u.get("alive", false) or not unit_nodes.has(u["id"]):
			continue
		if _is_hostile_on_empty_cell(u):
			var n_hide: Node3D = unit_nodes[u["id"]]
			var oh_hide = n_hide.get_node_or_null("Overhead")
			if oh_hide:
				oh_hide.visible = false
			_unit_oh_cell.erase(str(u["id"]))
			continue
		var uid := str(u["id"])
		var n: Node3D = unit_nodes[uid]
		var oh = n.get_node_or_null("Overhead")
		if oh == null:
			continue
		var anc := _callout_anchor_for_unit(u)
		var sid := str(anc.get("sys", u.get("sys", "")))
		var cell := int(anc.get("cell", u.get("cell", 0)))
		var key := "%s:%d" % [sid, cell]
		var slot: Vector3 = tactical_callouts.slot_pos_for(uid, sid, cell)
		if slot == Vector3.ZERO:
			## No callout slot yet — keep overhead off the board (no compact tonnage icon).
			oh.visible = false
			_unit_oh_cell.erase(uid)
			continue
		oh.visible = true
		if str(_unit_oh_cell.get(uid, "")) != key:
			var from_pos: Vector3 = oh.global_position
			if from_pos.length_squared() < 0.01:
				from_pos = slot
			tactical_callouts.set_tween(uid, from_pos, slot, true)
			_unit_oh_cell[uid] = key
		else:
			tactical_callouts.update_tween_target(uid, slot)
		var pos: Vector3 = tactical_callouts.overhead_world_pos(uid, slot)
		if oh.has_method("place_tactical"):
			oh.place_tactical(cam.cam, pos)
		## Tactical full plates (incl. sleepers) get pick bodies; box-select still skips garrison.
		tactical_callouts.ensure_pick_body(oh, uid)

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
	sm.hide_on_item_selection = false
	if not sm.id_pressed.is_connected(_on_assign_step):
		sm.id_pressed.connect(_on_assign_step)
	var held = _pilot_resource_count(str(p["id"]))
	## Show ALL auto as 待分配; + still uses take-pool (excludes own auto).
	var pool_show = _faction_pool_resources(int(p["faction"]), "")
	var pool_take = _faction_pool_resources(int(p["faction"]), str(p["id"]))
	sm.set_meta("pool_take", pool_take)
	sm.add_item("-", 6101)
	sm.add_item("已分配 %d  （待分配 %d）" % [held, pool_show], 6100)
	sm.set_item_disabled(sm.get_item_index(6100), true)
	sm.add_item("+", 6102)
	sm.set_item_disabled(sm.get_item_index(6102), pool_take <= 0)
	sm.add_item("打开分配面板…", 6103)
	# #region agent log
	var pc: Dictionary = BoardResourceAssign.pool_counts(map, int(p["faction"]), "")
	_dbg59("ASN", "board_root._fill_assign_submenu", "assign_pool", {
		"pid": str(p["id"]), "held": held, "pool_show": pool_show, "pool_take": pool_take,
		"empty": int(pc.get("empty", 0)), "auto": int(pc.get("auto", 0)), "runId": "assign-pool"
	})
	# #endregion

func _faction_pool_resources(fac: int, exclude_pilot: String = "") -> int:
	## Empty + auto_assigned (SHIPS §待分配池). exclude="" → include everyone's auto.
	return BoardResourceAssign.list_pool_owned(map, fac, exclude_pilot).size()

func _on_assign_step(id: int) -> void:
	var pid = str(popup.get_meta("pilot", ""))
	var p = _pilot_by_id(pid)
	if p.is_empty():
		return
	var held = _pilot_resource_count(pid)
	var pool_take = _faction_pool_resources(int(p["faction"]), pid)
	var target = held
	if id == 6101:
		target = maxi(0, held - 1)
	elif id == 6102:
		target = mini(held + pool_take, held + 1)
	elif id == 6103:
		_open_assign_panel(p)
		return
	_set_pilot_resource_count(p, target)
	# #region agent log
	_dbg59("ASN", "board_root._on_assign_step", "assign_step", {
		"pid": pid, "id": id, "held_before": held, "pool_take": pool_take,
		"target": target, "held_after": _pilot_resource_count(pid), "runId": "assign-pool"
	})
	# #endregion
	_rebuild_hud_list()
	if starmap_view:
		starmap_view.rebuild_labels(pilots)
		starmap_view.tick_icon_edge_follow()
	## Refresh open submenu counts in place.
	for c in popup.get_children():
		if c is PopupMenu and str(c.name).begins_with("Sub_分配"):
			_fill_assign_submenu(c, p)
			break

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
		var pool_take = _faction_pool_resources(int(p["faction"]), str(p["id"]))
		var v = int(edit.text) + 1
		edit.text = str(mini(held + pool_take, v))
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
	BoardResourceAssign.set_target_count(map, p, target, rng, admin)

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
		popup.add_item("%s x%d" % [def.get("name", sid), counts[sid]], id)
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
		popup.add_item("%s x%d" % [def.get("name", sid), counts[sid]], id)
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
	if br_tracker:
		br_tracker.note_unit_enter_sys(u, cs)
	admin.request("pilot.launch", {"pilot": p["id"], "ship": ship_id, "sys": cs})

func _pick_unit(screen_pos: Vector2, allow_garrison: bool = true) -> Dictionary:
	if cam == null or cam.cam == null:
		return {}
	var from = cam.cam.project_ray_origin(screen_pos)
	var dir = cam.cam.project_ray_normal(screen_pos)
	var to = from + dir * 2000.0
	var space = get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	## Orbit: PickBody layer 1. Tactical: tonnage/callout layer 2.
	q.collision_mask = 2 if cam.tactical_mode else 1
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
					if not allow_garrison and (bool(got.get("garrison", false)) or not bool(got.get("commandable", true))):
						got = {}
					else:
						return got
	# Geometric fallback: nearest unit / overhead screen-distance
	var best = {}
	var best_d = 36.0
	for u in units:
		if not u.get("alive", false):
			continue
		if not allow_garrison and (bool(u.get("garrison", false)) or not bool(u.get("commandable", true))):
			continue
		## Tactical: sleepers have no pick body; never select via icon proximity unless attack.
		if cam.tactical_mode and not allow_garrison and bool(u.get("garrison", false)):
			continue
		var wp: Vector3 = u["pos"]
		if cam.tactical_mode and unit_nodes.has(u["id"]):
			var ohp = unit_nodes[u["id"]].get_node_or_null("Overhead") as Node3D
			if ohp:
				wp = ohp.global_position
		elif unit_nodes.has(u["id"]):
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
	## Ray ∩ board plane Y=0; angular span matches GPU separator keys (BOARD_AND_INPUT).
	if cam == null or cam.cam == null or map == null:
		return {}
	var from = cam.cam.project_ray_origin(screen_pos)
	var dir = cam.cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return {}
	var plane_y := 0.0
	var tt = (plane_y - from.y) / dir.y
	if tt < 0.0:
		return {}
	var hitp = from + dir * tt
	var flat = Vector3(hitp.x, 0.0, hitp.z)
	var best = {}
	var best_score = INF
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		var center: Vector3 = sys["center"]
		var local = flat - Vector3(center.x, 0.0, center.z)
		var r = local.length()
		var sc = starmap_view.visual_scale_of(sid) if starmap_view else float(sys.get("visual_scale", sys.get("scale", 1.0)))
		var inner: float = float(map.layout.get("ring_inner", 12)) * sc
		var outer: float = float(map.layout.get("ring_outer", 26)) * sc
		if r < inner - 0.05 or r > outer + 0.35:
			continue
		var ang = atan2(local.x, -local.z)
		if ang < 0.0:
			ang += TAU
		var cells: Array = sys["cells"]
		var n := cells.size()
		if n <= 0:
			continue
		for i in n:
			var c: Dictionary = cells[i]
			var k0: float = float(c["angle_center"]) - float(c["angle_half"])
			var nxt: Dictionary = cells[(i + 1) % n]
			var k1: float = float(nxt["angle_center"]) - float(nxt["angle_half"])
			var span: float = fposmod(k1 - k0, TAU)
			if span < 0.001:
				span = TAU / float(n)
			var rel: float = fposmod(ang - k0, TAU)
			if rel > span + 0.0001:
				continue
			var mid_r = (inner + outer) * 0.5
			var mid_ang = k0 + span * 0.5
			var d_ang = absf(fposmod(ang - mid_ang + PI, TAU) - PI)
			var score = absf(r - mid_r) + d_ang * mid_r
			if score < best_score:
				best_score = score
				best = {"sys": sid, "cell": int(c["index"])}
	return best
func _rel_zh(rel: String) -> String:
	match rel:
		"self", "fleet", "allied":
			return "己方"
		"friendly":
			return "友方"
		"neutral":
			return "中立"
		"hostile", "enemy":
			return "敌对"
		_:
			return rel

func _equip_def(ref_id: String) -> Dictionary:
	if ref_id == "" or data == null:
		return {}
	var eq = data.equipment.get(ref_id, {})
	return eq if typeof(eq) == TYPE_DICTIONARY else {}

func _format_equip_effect_lines(u: Dictionary, p: Dictionary) -> PackedStringArray:
	## Flat list: pilot + slot fits + hidden. No section headers.
	var lines: PackedStringArray = PackedStringArray()
	var pilot_name := str(p.get("name", p.get("id", "?")))
	lines.append("驾驶员 · %s — 舰船操控与出站部署" % pilot_name)
	var def: Dictionary = data.ship_def(str(u.get("ship_id", "")))
	var fit: Dictionary = def.get("fit", {})
	var slots: Array = fit.get("slots", [])
	for i in slots.size():
		var slot_ref = slots[i]
		if slot_ref == null or str(slot_ref) == "":
			continue
		var sid := str(slot_ref)
		var eq := _equip_def(sid)
		var ename := str(eq.get("name", sid))
		lines.append("%s — %s" % [ename, _describe_slot_equip(sid, eq)])
	for h in fit.get("hidden", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var line := _describe_hidden_equip(h)
		if line != "":
			lines.append(line)
	return lines

func _describe_slot_equip(sid: String, eq: Dictionary) -> String:
	match sid:
		"bubble":
			return "拦截泡；拉力%d格；最短持续%ds；电容%d" % [
				int(eq.get("pull_range_cells", 3)), int(eq.get("min_uptime_s", 15)), int(eq.get("cap_cost", 0))
			]
		"shield_field":
			return "守卫护盾立场"
		"armor_link":
			return "守卫装甲链接"
		"shield_booster_m":
			return "周期%.1fs；护盾+%d；电容%d" % [
				float(eq.get("cycle_s", 0)), int(eq.get("heal_shield", 0)), int(eq.get("cap_cost", 0))
			]
		"armor_repairer_m":
			return "周期%.1fs；装甲+%d；电容%d" % [
				float(eq.get("cycle_s", 0)), int(eq.get("heal_armor", 0)), int(eq.get("cap_cost", 0))
			]
		_:
			return str(eq.get("name", sid))

func _describe_hidden_equip(h: Dictionary) -> String:
	var kind := str(h.get("kind", ""))
	match kind:
		"pd":
			var ref := str(h.get("ref", ""))
			var eq := _equip_def(ref)
			var n := int(h.get("count", 1))
			var nm := str(eq.get("name", ref))
			if n > 1:
				nm = "%s×%d" % [nm, n]
			return "%s — 周期%.1fs；伤%d；电容%d；同系近防无需锁定" % [
				nm, float(eq.get("cycle_s", 0)), int(eq.get("damage", 0)), int(eq.get("cap_cost", 0))
			]
		"weapon":
			var wref := str(h.get("ref", ""))
			var weq := _equip_def(wref)
			var rc := int(h.get("range_cells", weq.get("range_cells", 0)))
			var wnm := str(weq.get("name", wref))
			var dmg_parts: PackedStringArray = PackedStringArray()
			if float(weq.get("damage_emp", 0)) > 0.0:
				dmg_parts.append("电磁%.0f" % float(weq.get("damage_emp", 0)))
			if float(weq.get("damage_thermal", 0)) > 0.0:
				dmg_parts.append("热能%.0f" % float(weq.get("damage_thermal", 0)))
			if float(weq.get("damage_kinetic", 0)) > 0.0:
				dmg_parts.append("动能%.0f" % float(weq.get("damage_kinetic", 0)))
			if float(weq.get("damage_explosive", 0)) > 0.0:
				dmg_parts.append("爆炸%.0f" % float(weq.get("damage_explosive", 0)))
			if int(weq.get("heal_armor", 0)) > 0:
				dmg_parts.append("装甲+%d" % int(weq.get("heal_armor", 0)))
			var dmg_s := "、".join(dmg_parts) if not dmg_parts.is_empty() else "—"
			return "%s — 射程%d格；周期%.1fs；%s；电容%d" % [
				wnm, rc, float(weq.get("cycle_s", 0)), dmg_s, int(weq.get("cap_cost", 0))
			]
		"implant":
			var iref := str(h.get("ref", ""))
			var ieq := _equip_def(iref)
			var inm := str(ieq.get("name", iref))
			match iref:
				"implant_sniper":
					var sdesc := str(ieq.get("desc", ""))
					if sdesc != "":
						return "%s — %s" % [inm, sdesc]
					return "%s — 连续%d轮0伤害，第%d轮%d倍伤害且必中" % [
						inm, int(ieq.get("every", 10)) - 1, int(ieq.get("every", 10)), int(ieq.get("mul", 10))
					]
				"implant_focus_crystal":
					return "%s — 叠层+%d%%；电容+%d%%；护盾冷却%d" % [
						inm, int(ieq.get("stack_pct", 0)), int(ieq.get("cap_pct", 0)), int(ieq.get("shield_cd", 0))
					]
				"implant_armor_support":
					return "%s — 抗性+%d%%" % [inm, int(ieq.get("res_pct", 0))]
				_:
					return inm
		"range_mul":
			return "射程倍率 — 武器射程×%.1f" % float(h.get("value", 1.0))
		"resistance_mul":
			return "抗性倍率 — 抗性×%.1f（封顶100）" % float(h.get("value", 1.0))
		"pd_damage_mul":
			return "近防伤害倍率 — 近防伤害×%.1f" % float(h.get("value", 1.0))
		"pd_repair_max_loss":
			var pref := str(h.get("ref", "sleeper_pd_max_restore"))
			var peq := _equip_def(pref)
			return "%s — 近防实伤 1:1 修复本舰上限损失" % str(peq.get("name", pref))
		"no_max_loss":
			var nref := str(h.get("ref", "sleeper_hull_lock"))
			var neq := _equip_def(nref)
			return "%s — 受击不扣血量上限" % str(neq.get("name", nref))
		"shield_regen":
			return "护盾回复 — 护盾自然回复"
		"cap_regen":
			return "电容回复 — 电容自然回复"
		_:
			return ""

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
			fac_name = f.get("abbrev", f.get("name", ""))
	var rel_s = _rel_zh(_rel_for(u["faction"]))
	var body := "[b][%s]%s %s[/b]\n驾驶员 %s\n声望 %s\n星系 %s\n所属站 %s\n护盾 %d/%d\n装甲 %d/%d\n结构 %d/%d\n电容 %d/%d\n抗性 %d\n同系跨格 %.1fs\n跃迁 %.1fs\n" % [
		fac_name, p.get("name", ""), u["name"],
		p.get("name", ""), rel_s,
		map.systems[u["sys"]]["name"], _home_label_for_unit(u, p),
		int(inst["shield"]), int(inst["max_s"]),
		int(inst["armor"]), int(inst["max_a"]),
		int(inst["structure"]), int(inst["max_h"]),
		int(inst["cap"]), int(inst["max_cap"]),
		int(inst["resist"]),
		float(u["move_s"]), float(u["jump_s"])
	]
	var eq_lines := _format_equip_effect_lines(u, p)
	for line in eq_lines:
		body += "%s\n" % line
	detail.text = body
	# #region agent log
	_dbg59("UI", "board_root._update_detail", "detail_zh", {
		"unit": str(u.get("id", "")), "ship": str(u.get("ship_id", "")),
		"equip_lines": eq_lines.size(), "runId": "detail-zh"
	})
	# #endregion
