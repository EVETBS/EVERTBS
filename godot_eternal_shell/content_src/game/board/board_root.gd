extends Node3D
## EVERTBS / eve战棋 board test orchestrator (sleeper NPC) — bricks talk via AdminProxy.

const DATA := preload("res://game/board/board_data.gd")
const MAP_MODEL := preload("res://game/board/map/map_model.gd")
const CAPTURE := preload("res://game/board/capture/capture_system.gd")
const PILOTS := preload("res://game/board/pilots/pilot_system.gd")
const AI := preload("res://game/board/ai/ai_controller.gd")
const NAV := preload("res://game/board/player_nav/player_nav.gd")
const FX := preload("res://game/board/combat/combat_formulas.gd")
const OVERHEAD_SCR := preload("res://game/board/hud/unit_overhead.gd")
const COMBAT_FX_SCR := preload("res://art_modules/eve_combat_fx/eve_combat_fx_module.gd")
const TIP_VFX_SCR := preload("res://game/board/fx/turret_vfx.gd")
const SHIP_DEATH_FX := preload("res://game/board/fx/ship_death_fx.gd")
const FLOAT_SCR := preload("res://game/board/fx/float_text_pool.gd")
const BR_TRACKER := preload("res://game/board/battle_report_tracker.gd")
const SHIP_ART := preload("res://art_modules/eve_ship_art/scripts/eve_ship_art_module.gd")
const CALLOUT_SCR := preload("res://game/board/hud/tactical_callout_layer.gd")
const MemberTableScr := preload("res://game/board/pilots/member_table.gd")
const CrewRankScr := preload("res://game/board/pilots/crew_rank.gd")
const SIM_CLOCK_SCR := preload("res://game/board/sim_clock.gd")
const HP_BATCH_SCR := preload("res://game/board/hud/hp_bar_batch.gd")
const IMPOSTOR_BAKER_SCR := preload("res://game/board/fx/ship_impostor_baker.gd")
const MASS_DRAW_SCR := preload("res://game/board/fx/ship_mass_draw.gd")
const DevBalance := preload("res://game/board/dev_balance.gd")
const DevWindowScr := preload("res://game/dev_options_window.gd")

var data: BoardData
var map: BoardMapModel
var capture: BoardCaptureSystem
var pilots_sys: BoardPilotSystem
var admin: BoardAdminProxy
var br_tracker: BoardBattleReportTracker

var pilots: Array = []
var units: Array = []
var next_unit_i = 1
var selection: Array = [] # unit ids
var control_groups: Dictionary = {}
var viewer_faction = 1
var _boot_layout := "res://data/board/layout.json"
var rng = RandomNumberGenerator.new()
## Soft-key bar (mobile): sticky Ctrl like Windows OSK.
var soft_ctrl_sticky := false
var soft_ctrl_btn: Button
var hud_layer: Control
var bottom_bar: Control
var chat_panel: Control
var chat_log: RichTextLabel
var chat_scroll: ScrollContainer
var _chat_stick := true
var _chat_snapping := false
var _chat_lines: Array = []
const CHAT_MAX_LINES := 80
var deputy_panel: Control
var deputy_opt: OptionButton
var deputy_fleet_box: VBoxContainer
var deputy_group := -1
var player_deputy: BoardAiController
var player_deputy_name := "羊"
var faction_ai: Dictionary = {} ## fac -> BoardAiController
var faction_deputy_name: Dictionary = {} ## fac -> display name
var _faction_out: Dictionary = {} ## fac -> true once defeated (MATCH_FLOW §4.0); irreversible
var _defeat_spared_logged: Dictionary = {}
var _deputy_cmd_count := -1
var _marker_announce: Dictionary = {} ## kind -> last announced place key
var _prev_deputy_member_ids: Dictionary = {}
var diplo_btn: Button
var diplo_panel: Control
var diplo_offer: Dictionary = {} ## "a>b" -> true while semicircle
var diplo_ai_wait: Dictionary = {} ## "a>b" -> seconds until the AI accepts
var menu_btn: Button
var menu_window: Window
var menu_pause_lab: Label
var menu_page: VBoxContainer
var settings_page: VBoxContainer
var menu_load_page: VBoxContainer
var sim_paused := false
var _mp: MpMatchDriver
var _mp_fog_box: CheckBox
var _mp_cheat_lab: Label
var _mp_cheat_list: VBoxContainer
var _dev_window: Window
var _dev_pause_held := false
var _dev_pause_restore := false
var _live_prep := 1.0
var _live_move := 1.0
var _live_jump := 1.0
var _live_land := 1.0
var deputy_name_lab: Label
var deputy_face: TextureRect
var settings_bgm_vol := 1.0
var settings_sfx_vol := 1.0
var settings_battle_full_plates := false
var settings_deputy_btn: Button
var settings_deputy_list: VBoxContainer
var _br_sort_col := ""
var _br_sort_report := ""
var map_markers: Dictionary = {} ## kind -> {pos, yaw, scale, a, b}
const MARKER_ARROW_HALF := 80.0
const MARKER_ICON_W := 40.0
const MARKER_BOARD_Y := -0.05
const MARKER_SCALE_MIN := 0.4
const MARKER_SCALE_MAX := 4.0
const EDGE_PAN_PX := 32.0
var _marker_resize_logged: Dictionary = {}
var _marker_board: Node3D
var _marker_handles_on := true
var _sim_clock := 0.0
var _sync_waves: Dictionary = {} ## gid -> {uid: start clock}
var _marker_drag_kind := ""
var _marker_drag_prev := Vector3.ZERO
var _marker_tex_cache: Dictionary = {}
var marker_layer: Control
var marker_btns: Dictionary = {}
var _digit_last_g := -1
var _digit_last_ms := 0
const DIGIT_DBL_MS := 400
const BUBBLE_PULSE_S := 45.0
## Touch → mouse / cam (BOARD_AND_INPUT §5.1).
var _touch_pts: Dictionary = {} ## index -> {pos: Vector2, t0: float, moved: bool}
var _touch_long_fired: Dictionary = {} ## index -> true
var _pinch_prev_dist := -1.0
var _pinch_prev_angle := 0.0
var _touch_panning := false
var _ui_scroll: Control
var _ui_scroll_last := Vector2.ZERO
var _zoom_col: Control
var _hold_grow := false
var _hold_origin := Vector2.ZERO
var _hold_half := 0.0
var _suppress_lmb_until := 0.0
var _callout_click_t := -1.0
var _callout_click_key := ""
const HOLD_ARM_S := 1.0
const HOLD_GROW_PX := 140.0

var drag_start = Vector2.ZERO
var dragging = false
var box_selecting = false
var _left_drag_start := Vector2.ZERO
var _left_dragging := false
var _left_box_selecting := false
var _lmb_press_on_left_list := false
## faction_id -> {sys, cell}; auto-launch ships path here after undock.
var rally_by_fac: Dictionary = {}
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
## RTS mass-unit draw: nearest-N hulls, hysteresis, staggered load, frustum skip, no model shadows.
const BATTLE_MODEL_BUDGET := 150
const MODEL_HYSTERESIS := 40
const MODEL_LOADS_PER_TICK := 2
const MODEL_DROPS_PER_TICK := 3
var _battle_model_ids: Dictionary = {}
var _battle_model_acc := 0.0
var _model_want: Dictionary = {}
var _model_load_q: Array = []
var _model_drop_q: Array = []
var _model_view_battle := false
var _sim_clk = SIM_CLOCK_SCR.new()
var _fight_n := 0
var _hp_batch: Control
var _imp_baker: Node
var _mass_draw: Node3D
var _dilate_lab: Label
var _lock_line_mat: StandardMaterial3D
var rebuild_timer = 0.0
var match_over = false
var match_msg = ""
var match_modes: Array = ["hua_di"] ## gu_dou | hua_di | jian_mie
var match_limit_s: int = 5400
var annihilate_goal: int = 50
var match_stats: Dictionary = {} ## fac -> {built,kills,losses,occupy_score,reports}
var _mp_kill_log: Array = []
var _mp_seen_kills: Dictionary = {}
var _match_clock_lab: Button
var _scoreboard_win: Window
var _settle_layer: Control
var _focus_lines: Dictionary = {} ## unit_id -> MeshInstance3D
var _occupy_tick_acc := 0.0
var _ten_min_warned := false
var _auto_launch_locked := false
var _winner_faction := -1
var _settle_detail_on := false
var combat_fx
var tip_vfx
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
## Station exit rises from under the cell. Duration and state: SHIPS.md §7.
const UNDOCK_RISE_S := 1.0
const UNDOCK_SINK_Y := 5.5
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
	## Hot ids: skip sync disk (land hitch). A/B/C/E kept for mobile cam debug.
	if hid in ["ARC", "TON"]:
		return
	DebugSessionLog.append(hid, loc, msg, data_payload)
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
	_mp_apply_host_tables()
	DevBalance.load()
	if FileAccess.file_exists(MpCampaignNet.LIVE_PATH):
		DevBalance.master_on = false
		DevBalance.scale_prep = 1.0
		DevBalance.scale_move = 1.0
		DevBalance.scale_jump = 1.0
		DevBalance.scale_landing = 1.0
	else:
		DevBalance.apply_to_data(data)
	add_to_group("evertbs_board")
	_live_prep = DevBalance.scale_prep
	_live_move = DevBalance.scale_move
	_live_jump = DevBalance.scale_jump
	_live_land = DevBalance.scale_landing
	map = MAP_MODEL.new()
	var layout_path := "res://data/board/layout.json"
	var boot_factions: Array = []
	if FileAccess.file_exists("user://board_boot.json"):
		var boot_raw = JSON.parse_string(FileAccess.get_file_as_string("user://board_boot.json"))
		if typeof(boot_raw) == TYPE_DICTIONARY:
			var lp := str(boot_raw.get("layout", layout_path))
			if not lp.is_empty() and FileAccess.file_exists(lp):
				layout_path = lp
			var facs = boot_raw.get("factions", [])
			if typeof(facs) == TYPE_ARRAY:
				boot_factions = facs
	_boot_layout = layout_path
	map.load_layout(layout_path)
	_load_match_modes_from_layout()
	if not boot_factions.is_empty():
		data.apply_saved_members(boot_factions)
		_apply_saved_roster(boot_factions)
	settings_bgm_vol = PlayerSettings.get_bgm()
	settings_sfx_vol = PlayerSettings.get_sfx()
	settings_battle_full_plates = PlayerSettings.get_full_plates()
	capture = CAPTURE.new()
	capture.admin = admin
	pilots_sys = PILOTS.new()
	pilots_sys.admin = admin
	pilots_sys.data = data
	if typeof(map.layout) == TYPE_DICTIONARY and (map.layout as Dictionary).has("viewer_faction"):
		data.diplomacy["viewer_faction"] = int((map.layout as Dictionary).get("viewer_faction", 1))
	viewer_faction = int(data.diplomacy.get("viewer_faction", 1))
	br_tracker = BR_TRACKER.new()
	br_tracker.viewer_faction = viewer_faction
	br_tracker.is_npc_faction = Callable(data, "is_npc_faction")
	br_tracker.is_with_viewer = Callable(self, "_br_with_viewer")
	br_tracker.faction_label = Callable(self, "_faction_label")
	_spawn_opening()
	_apply_opening_npc_owners()
	_register_opening_garrison_posts()
	_setup_deputies()
	_mp_boot()
	_setup_ai_autobuild()
	if DevBalance.master() and DevBalance.want_resource:
		dev_push_resource_bonus(true)
	dev_restamp_work()
	_build_scene_nodes()
	_refresh_occupancy()
	## Lock phase from equal-arc gate bearings (STARMAP §2.0). No fixed clockwise bias.
	for sid0 in map.systems.keys():
		map.systems[sid0]["ring_phase"] = map.desired_ring_phase(str(sid0))
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
	## UI_AND_SHELL §2: press 全体制造 once on entry; SHIPS §7.3 starter chat lines.
	call_deferred("_on_entry_auto_prod_and_starters")
	## Dump after first visibility tick so garrison samples include HP / plate state.
	get_tree().create_timer(1.2).timeout.connect(func(): mcp_dump_debug())
	combat_fx = COMBAT_FX_SCR.new()
	combat_fx.name = "CombatFx"
	add_child(combat_fx)
	combat_fx.setup(self)
	tip_vfx = TIP_VFX_SCR.new()
	tip_vfx.name = "TipVfx"
	add_child(tip_vfx)
	call_deferred("_warm_ship_death_fx")
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

func _on_entry_auto_prod_and_starters() -> void:
	_on_all_current_ships_to_prod()
	var n_st := 0
	for p in pilots:
		if int(p.get("faction", 0)) != viewer_faction or not bool(p.get("starter", false)):
			continue
		var sid := str(p.get("default_ship", p.get("last_ship_id", "")))
		var def: Dictionary = data.ship_def(sid)
		var sname := str(def.get("name", sid))
		if not sname.ends_with("级"):
			sname += "级"
		_chat_append("%s：已确认首发资格，首发舰为[%s]" % [str(p.get("name", p.get("id", ""))), sname])
		n_st += 1
	# #region agent log
	_dbg59("ENTRY", "board_root._on_entry_auto_prod_and_starters", "done", {
		"starters": n_st, "pilots": pilots.size(), "runId": "roster-v2"
	})
	# #endregion

func _setup_ai_autobuild() -> void:
	for p in pilots:
		if data.is_npc_faction(int(p["faction"])):
			continue
		var ship_id := str(p.get("default_ship", "gila_cc2"))
		## Chuang-led AI faction: prefer higher tonnage / PD-leaning defaults when available.
		var pf := int(p["faction"])
		if pf != viewer_faction and faction_ai.has(pf):
			ship_id = _deputy_build_ship(faction_ai[pf], p)
		var def: Dictionary = data.ship_def(ship_id)
		var ton: String = def.get("tonnage", "destroyer")
		p["default_ship"] = ship_id
		p["last_ship_id"] = ship_id
		pilots_sys.set_auto(p, ton, ship_id)

func _ship_has_armor_link(def: Dictionary) -> bool:
	for slot in def.get("fit", {}).get("slots", []):
		if str(slot) == "armor_link":
			return true
	return false

func _ship_pd_dps(def: Dictionary) -> float:
	## Same numbers as _build_pd, without consuming rng.
	var mul := 1.0
	var hidden: Array = def.get("fit", {}).get("hidden", [])
	for h in hidden:
		if str(h.get("kind", "")) == "pd_damage_mul":
			mul = float(h.get("value", 1.0))
	var dps := 0.0
	for h2 in hidden:
		if str(h2.get("kind", "")) != "pd":
			continue
		var eq: Dictionary = data.equipment.get(str(h2.get("ref", "")), {})
		dps += float(int(h2.get("count", 1))) * float(eq.get("damage", 100)) * mul / maxf(float(eq.get("cycle_s", 1.4)), 0.001)
	return dps

func _ship_player_buildable(def: Dictionary) -> bool:
	## Sleepers / NPC hulls are not manufacturable (SHIPS §8).
	if def.is_empty():
		return false
	if bool(def.get("npc", false)) or bool(def.get("npc_hull", false)):
		return false
	return true

func _pilot_has_ship(p: Dictionary, ship_id: String) -> bool:
	if ship_id == "" or data == null:
		return false
	var mid := str(p.get("member_id", ""))
	if mid == "":
		return true
	return CrewRank.member_has_ship(data.member_by_id(mid), ship_id)

func _pilot_can_build_ton(p: Dictionary, ton: String) -> bool:
	if ton == "":
		return false
	var held := BoardResourceAssign.pilot_held_count(map, str(p.get("id", "")))
	return held >= BoardResourceAssign.unlock_need(data, ton)

func _chuang_build_ship(p: Dictionary) -> String:
	## 创.md §3: among buildable tonnages, highest PD DPS, then higher tonnage; keep current on tie.
	var current := _pilot_current_ship_id(p)
	if data == null:
		return current
	var best := ""
	var best_dps := -1.0
	var best_w := -1
	for sid in data.ships.keys():
		var def: Dictionary = data.ship_def(str(sid))
		if not _ship_player_buildable(def) or not _pilot_has_ship(p, str(sid)):
			continue
		var ton := str(def.get("tonnage", ""))
		if not _pilot_can_build_ton(p, ton):
			continue
		var dps := snappedf(_ship_pd_dps(def), 0.01)
		var w := BoardTypes.tonnage_weight(ton)
		var better := dps > best_dps or (dps == best_dps and w > best_w)
		var tie := dps == best_dps and w == best_w and str(sid) == current
		if better or tie:
			best = str(sid)
			best_dps = dps
			best_w = w
	return best if best != "" else current

func _ship_has_fit_slot(def: Dictionary, slot: String) -> bool:
	for s in def.get("fit", {}).get("slots", []):
		if str(s) == slot:
			return true
	return false

func _ship_max_range_cells(def: Dictionary) -> int:
	var mul := 1.0
	var hidden: Array = def.get("fit", {}).get("hidden", [])
	for h in hidden:
		if str(h.get("kind", "")) == "range_mul":
			mul = float(h.get("value", 1.0))
	var best := 0
	for h2 in hidden:
		if str(h2.get("kind", "")) != "weapon":
			continue
		var eq: Dictionary = data.equipment.get(str(h2.get("ref", "")), {})
		var rc := int(ceil(float(h2.get("range_cells", eq.get("range_cells", 0))) * mul))
		if rc > best:
			best = rc
	return best

func _slot_ship_for(p: Dictionary, slot: String) -> String:
	var best := ""
	var best_w := -1
	var any_best := ""
	var any_w := -1
	for sid in data.ships.keys():
		var def: Dictionary = data.ship_def(str(sid))
		if not _ship_player_buildable(def) or not _pilot_has_ship(p, str(sid)) or not _ship_has_fit_slot(def, slot):
			continue
		var ton := str(def.get("tonnage", ""))
		var w := BoardTypes.tonnage_weight(ton)
		if w > any_w:
			any_w = w
			any_best = str(sid)
		if _pilot_can_build_ton(p, ton) and w > best_w:
			best_w = w
			best = str(sid)
	return best if best != "" else any_best

func _link_ship_for(p: Dictionary) -> String:
	return _slot_ship_for(p, "armor_link")

func _pilot_can_fly_slot(p: Dictionary, slot: String) -> bool:
	var cur := _pilot_current_ship_id(p)
	if cur != "" and _ship_has_fit_slot(data.ship_def(cur), slot):
		return true
	return _slot_ship_for(p, slot) != "" and _pilot_can_build_ton(p, str(data.ship_def(_slot_ship_for(p, slot)).get("tonnage", "")))

func _stamp_roster_caps(p: Dictionary, row: Dictionary) -> void:
	if str(row.get("pilot_id", "")) == "":
		row["pilot_id"] = str(p.get("id", ""))
	var sid := str(row.get("ship_id", ""))
	if sid == "":
		sid = _pilot_current_ship_id(p)
	var def: Dictionary = data.ship_def(sid) if data else {}
	row["has_bubble"] = _ship_has_fit_slot(def, "bubble")
	row["has_shield"] = _ship_has_fit_slot(def, "shield_field")
	row["has_link"] = _ship_has_fit_slot(def, "armor_link")
	row["has_range"] = _ship_max_range_cells(def) > 0
	row["pd_dps"] = _ship_pd_dps(def)
	row["can_bubble"] = _pilot_can_fly_slot(p, "bubble")
	row["can_shield"] = _pilot_can_fly_slot(p, "shield_field")
	row["can_link"] = _pilot_can_fly_slot(p, "armor_link")
	var gila: Dictionary = data.ship_def("gila_cc2") if data else {}
	row["can_gila"] = _pilot_can_build_ton(p, str(gila.get("tonnage", "cruiser")))

func _appoint_slot(ctrl: BoardAiController, f: Dictionary) -> String:
	var appoint := str(f.get("appoint", ""))
	if appoint != "":
		return appoint
	if str(ctrl.deputy_id) == "chuang" and str(f.get("role", "")) == "attrition":
		return "link"
	if str(ctrl.deputy_id) == "yang":
		return "link"
	return ""

func _keep_appointee(f: Dictionary, key: String, pool_ids: Dictionary, out: Dictionary, slot: String) -> String:
	var members: Array = f.get("members", [])
	var rp := str(f.get(key, ""))
	var keep := false
	if rp != "" and pool_ids.has(rp) and not out.has(rp):
		var rpp: Dictionary = _pilot_by_id(rp)
		var ru = _unit_by_id(str(rpp.get("unit_id", "")))
		keep = ru.is_empty() or not ru.get("alive", false) or members.has(str(ru.get("id", "")))
	if not keep:
		rp = ""
		var best_w := -1
		var best_fit := false
		for uid in members:
			var u = _unit_by_id(str(uid))
			if u.is_empty() or not u.get("alive", false):
				continue
			var pid := str(u.get("pilot_id", ""))
			if pid == "" or not pool_ids.has(pid) or out.has(pid):
				continue
			var fit := _ship_has_fit_slot(data.ship_def(str(u.get("ship_id", ""))), slot)
			var w := BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
			if (fit and not best_fit) or (fit == best_fit and (w > best_w or (w == best_w and (rp == "" or pid < rp)))):
				rp = pid
				best_w = w
				best_fit = fit
	if rp == "":
		f.erase(key)
		return ""
	f[key] = rp
	return rp

func _assign_deputy_designations(ctrl: BoardAiController, pool: Array, out: Dictionary) -> void:
	var pool_ids: Dictionary = {}
	for p in pool:
		pool_ids[str(p.get("id", ""))] = true
	for f in ctrl.fleets:
		var fid := int(f.get("id", -1))
		var appoint := _appoint_slot(ctrl, f)
		if appoint == "link" or appoint == "both":
			var link_pid := _keep_appointee(f, "req_pilot", pool_ids, out, "armor_link")
			if link_pid != "":
				out[link_pid] = {"ship": _slot_ship_for(_pilot_by_id(link_pid), "armor_link"), "fleet": fid}
		elif str(f.get("req_pilot", "")) != "" and appoint != "bubble":
			f.erase("req_pilot")
		if appoint == "shield" or appoint == "both":
			var sh_pid := _keep_appointee(f, "req_shield", pool_ids, out, "shield_field")
			if sh_pid != "":
				out[sh_pid] = {"ship": _slot_ship_for(_pilot_by_id(sh_pid), "shield_field"), "fleet": fid}
		else:
			f.erase("req_shield")
		if appoint == "bubble":
			var bub_pid := _keep_appointee(f, "req_pilot", pool_ids, out, "bubble")
			if bub_pid != "":
				out[bub_pid] = {"ship": _slot_ship_for(_pilot_by_id(bub_pid), "bubble"), "fleet": fid}
		if str(f.get("role", "")) == "raid":
			for pid in f.get("pilot_ids", []):
				var ps := str(pid)
				if ps == "" or not pool_ids.has(ps):
					continue
				out[ps] = {"ship": "gila_cc2", "fleet": fid}

func _tick_deputy_designations() -> void:
	var out: Dictionary = {}
	if deputy_group >= 0 and player_deputy != null:
		_assign_deputy_designations(player_deputy, _commanded_pilots(deputy_group), out)
	for fid in faction_ai.keys():
		if _faction_out.has(int(fid)):
			continue
		_assign_deputy_designations(faction_ai[fid], _faction_pilots(int(fid)), out)
	for p in pilots:
		var pid := str(p.get("id", ""))
		if out.has(pid):
			p["deputy_req_ship"] = str(out[pid]["ship"])
			p["deputy_req_fleet"] = int(out[pid]["fleet"])
		elif p.has("deputy_req_ship"):
			p.erase("deputy_req_ship")
			p.erase("deputy_req_fleet")

func _setup_deputies() -> void:
	faction_ai.clear()
	faction_deputy_name.clear()
	## UI_AND_SHELL §0.2: custom campaign may pin a deputy per faction (layout.deputies).
	var dep_map: Dictionary = map.layout.get("deputies", {}) if map != null else {}
	player_deputy = AI.new()
	player_deputy.faction = viewer_faction
	player_deputy.deputy_id = _deputy_id_for(viewer_faction, dep_map)
	player_deputy_name = _deputy_display_name(str(player_deputy.deputy_id))
	for f in data.factions.get("factions", []):
		var fid := int(f.get("id", -1))
		if bool(f.get("npc", false)) or fid == viewer_faction:
			continue
		if typeof(map.layout) == TYPE_DICTIONARY and bool((map.layout as Dictionary).get("mp", false)):
			var ai_facs: Array = (map.layout as Dictionary).get("ai_factions", [])
			if not ai_facs.has(fid):
				continue
		var ctrl := AI.new()
		ctrl.faction = fid
		## Default: legion 2 loads Chuang; others Yang (指挥接口). layout.deputies overrides.
		ctrl.deputy_id = _deputy_id_for(fid, dep_map)
		faction_deputy_name[fid] = _deputy_display_name(str(ctrl.deputy_id))
		ctrl.setup_fleets(_roster_entries(_faction_pilots(fid)))
		_flush_deputy_shortage(ctrl, str(faction_deputy_name[fid]))
		faction_ai[fid] = ctrl
		_rebalance_faction_resources(fid)
	_rebuild_player_deputy()

func dev_pause_for_data(hold: bool) -> void:
	if hold:
		if _dev_pause_held:
			return
		_dev_pause_restore = sim_paused
		_dev_pause_held = true
		sim_paused = true
		return
	if not _dev_pause_held:
		return
	sim_paused = _dev_pause_restore
	_dev_pause_held = false

func dev_push_resource_bonus(on: bool) -> void:
	var ids: Array = []
	var bonus := 0
	if on and DevBalance.master():
		bonus = 23
		for p in _faction_pilots(viewer_faction):
			ids.append(str(p.get("id", "")))
	var payload := {"faction": viewer_faction, "bonus": bonus, "pilots": ids}
	var res: Dictionary = {}
	if admin:
		res = admin.request("dev.resource_bonus", payload)
	if res.get("accepted", res.get("ok", true)) == false:
		return
	var applied = res.get("payload", payload)
	if typeof(applied) != TYPE_DICTIONARY:
		applied = payload
	DevBalance.apply_resource_payload(applied)

func dev_switch_viewer(new_fid: int) -> void:
	if new_fid == viewer_faction or data == null or data.is_npc_faction(new_fid):
		return
	if not faction_ai.has(new_fid):
		return
	var old: int = viewer_faction
	for u in units:
		var fac := int(u.get("faction", -1))
		if fac == old:
			u["player_hold"] = false
		elif fac == new_fid and not bool(u.get("garrison", false)):
			u["path"] = []
			u.erase("order_dest_sys")
			u.erase("order_dest_cell")
			u["player_hold"] = false
	var old_ctrl: BoardAiController = player_deputy
	var new_ctrl: BoardAiController = faction_ai[new_fid]
	faction_ai.erase(new_fid)
	if old_ctrl == null:
		old_ctrl = AI.new()
		old_ctrl.faction = old
		var dep_map: Dictionary = map.layout.get("deputies", {}) if map != null else {}
		old_ctrl.deputy_id = _deputy_id_for(old, dep_map)
	old_ctrl.faction = old
	faction_ai[old] = old_ctrl
	faction_deputy_name[old] = _deputy_display_name(str(old_ctrl.deputy_id))
	old_ctrl.setup_fleets(_roster_entries(_faction_pilots(old)))
	_flush_deputy_shortage(old_ctrl, str(faction_deputy_name[old]))
	_rebalance_faction_resources(old)
	viewer_faction = new_fid
	data.diplomacy["viewer_faction"] = new_fid
	if br_tracker:
		br_tracker.viewer_faction = new_fid
	player_deputy = new_ctrl
	player_deputy.faction = new_fid
	player_deputy_name = _deputy_display_name(str(player_deputy.deputy_id))
	deputy_group = -1
	_rebuild_player_deputy()
	if deputy_name_lab:
		deputy_name_lab.text = player_deputy_name
	_refresh_deputy_face()
	if deputy_opt:
		deputy_opt.set_block_signals(true)
		for i in deputy_opt.item_count:
			if deputy_opt.get_item_id(i) == -2:
				deputy_opt.select(i)
				break
		deputy_opt.set_block_signals(false)
	_clear_selection()
	_rebuild_hud_list()
	_rebuild_group_dict()
	if starmap_view:
		starmap_view.setup(map, data.diplomacy, viewer_faction)
		starmap_view.set_units(units)
	dev_push_resource_bonus(DevBalance.master() and DevBalance.want_resource)

func dev_set_hull(ship_id: String, ns: float, na: float, nh: float) -> void:
	var def := data.ship_def(ship_id)
	if def.is_empty():
		return
	var os := float(def.get("shield", 1.0))
	var oa := float(def.get("armor", 1.0))
	var oh := float(def.get("structure", 1.0))
	DevBalance.apply_to_data(data)
	_scale_fielded_hull(ship_id, os, ns, oa, na, oh, nh)

func _scale_fielded_hull(ship_id: String, os: float, ns: float, oa: float, na: float, oh: float, nh: float) -> void:
	var rs := ns / os if os > 0.0 else 1.0
	var ra := na / oa if oa > 0.0 else 1.0
	var rh := nh / oh if oh > 0.0 else 1.0
	if absf(rs - 1.0) < 0.0001 and absf(ra - 1.0) < 0.0001 and absf(rh - 1.0) < 0.0001:
		return
	for u in units:
		if str(u.get("ship_id", "")) != ship_id:
			continue
		var inst = u.get("inst", {})
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		_scale_inst(inst, "shield", rs)
		_scale_inst(inst, "max_s", rs)
		_scale_inst(inst, "pristine_s", rs)
		_scale_inst(inst, "armor", ra)
		_scale_inst(inst, "max_a", ra)
		_scale_inst(inst, "pristine_a", ra)
		_scale_inst(inst, "structure", rh)
		_scale_inst(inst, "max_h", rh)
		_scale_inst(inst, "pristine_h", rh)

func _scale_inst(inst: Dictionary, key: String, ratio: float) -> void:
	if inst.has(key):
		inst[key] = float(inst[key]) * ratio

func dev_reapply_fits() -> void:
	DevBalance.apply_to_data(data)
	for u in units:
		if not bool(u.get("alive", false)):
			continue
		var def := data.ship_def(str(u.get("ship_id", "")))
		_init_unit_combat(u)
		u["pd"] = _build_pd(def)

func dev_restamp_work() -> void:
	if map == null:
		return
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			var kind := int(c.get("kind", BoardTypes.CellKind.EMPTY))
			if kind == BoardTypes.CellKind.EMPTY:
				continue
			var cap := DevBalance.work_cap(kind)
			var old := float(c.get("dev_cap", BoardTypes.WORK_MAX))
			var work := float(c.get("work", old))
			if absf(old - cap) > 0.01:
				if work >= old - 0.5:
					c["work"] = cap
				else:
					c["work"] = clampf(work * cap / maxf(old, 0.001), 0.0, cap)
			c["dev_cap"] = cap
	map.capture_dirty = true

func dev_rescale_hull(ship_id: String) -> void:
	var target_d := DevBalance.hull_diameter(ship_id)
	for u in units:
		if str(u.get("ship_id", "")) != ship_id:
			continue
		if not unit_nodes.has(u["id"]):
			continue
		var n: Node3D = unit_nodes[u["id"]]
		var model := n.get_node_or_null("Model") as Node3D
		if model != null and is_instance_valid(model):
			var model_key := str(model.get_meta("model_key", ""))
			if model_key == "":
				model_key = str(data.ship_def(ship_id).get("model", ship_id))
			SHIP_ART.apply_pose_and_scale(model, model_key, target_d, ship_id)
			u["trail_nozzles"] = SHIP_ART.engine_nozzle_locals(model_key, model)
		_fit_pick_body_to_model(n)

func dev_rescale_motion() -> void:
	var np := DevBalance.scale_prep
	var nm := DevBalance.scale_move
	var nj := DevBalance.scale_jump
	var nl := DevBalance.scale_landing
	var rp := np / maxf(_live_prep, 0.0001)
	var rm := nm / maxf(_live_move, 0.0001)
	var rj := nj / maxf(_live_jump, 0.0001)
	var rl := nl / maxf(_live_land, 0.0001)
	_live_prep = np
	_live_move = nm
	_live_jump = nj
	_live_land = nl
	if absf(rp - 1.0) < 0.0001 and absf(rm - 1.0) < 0.0001 and absf(rj - 1.0) < 0.0001 and absf(rl - 1.0) < 0.0001:
		return
	for u in units:
		var phase := int(u.get("phase", BoardTypes.MovePhase.IDLE))
		if phase == BoardTypes.MovePhase.PREP:
			u["phase_t"] = float(u.get("phase_t", 0.0)) * rp
		elif phase == BoardTypes.MovePhase.INVULN:
			var ratio := rj if str(u.get("step_kind", "")) == "jump" else rm
			u["phase_t"] = float(u.get("phase_t", 0.0)) * ratio
			u["step_invuln"] = float(u.get("step_invuln", 0.0)) * ratio
		elif phase == BoardTypes.MovePhase.LANDING:
			u["phase_t"] = float(u.get("phase_t", 0.0)) * rl

func dev_rescale_land_arc() -> void:
	for u in units:
		if int(u.get("phase", BoardTypes.MovePhase.IDLE)) != BoardTypes.MovePhase.LANDING:
			continue
		var skip := int(u.get("land_arc_skip", -1))
		if skip < 0:
			continue
		var new_m := DevBalance.land_arc_of(skip)
		var old_m := float(u.get("land_arc_used", new_m))
		if old_m > 0.0:
			u["phase_t"] = float(u.get("phase_t", 0.0)) * new_m / old_m
		u["land_arc_used"] = new_m

func _dev_prep(u: Dictionary) -> float:
	var base: float
	if u.has("prep_s"):
		base = maxf(float(u.get("prep_s", 0.0)), 0.0)
	else:
		base = BoardTypes.align_prep_s(float(u.get("inertia", 1.0)), float(u.get("mass", 1e6)))
	return base * DevBalance.scale_prep

func _dev_move(u: Dictionary) -> float:
	return maxf(float(u.get("move_s", 0.0)), 0.0) * DevBalance.scale_move

func _dev_jump(u: Dictionary) -> float:
	return maxf(float(u.get("jump_s", 0.0)), 0.0) * DevBalance.scale_jump

func _dev_land(u: Dictionary) -> float:
	return maxf(float(u.get("landing_s", 0.0)), 0.0) * DevBalance.scale_landing

func _hit_speed(u: Dictionary) -> float:
	## Afterburner bonus is read only when resolving damage, not when moving.
	return float(u.get("speed", 0.0)) * (1.0 + float(u.get("ab_speed_bonus", 0.0)))

func _landing_phase_t(u: Dictionary) -> float:
	## Gate and undock keep a full landing. Same-system hops scale by the short arc.
	var base := _dev_land(u)
	var kind := str(u.get("step_kind", ""))
	if kind == "jump" or kind == "undock":
		u["land_arc_skip"] = -1
		u["land_arc_used"] = 1.0
		return base
	var n := int(map.systems[str(u.get("sys", ""))]["cells"].size())
	var steps := BoardTypes.shorter_arc_steps(int(u.get("from_cell", u["cell"])), int(u.get("to_cell", u["cell"])), n)
	var skip := maxi(steps - 1, 0)
	var mul := DevBalance.land_arc_of(skip)
	u["land_arc_skip"] = skip
	u["land_arc_used"] = mul
	return base * mul

func _intra_land(sys: String, from_cell: int, to_cell: int, landing_s: float) -> float:
	var n := int(map.systems[sys]["cells"].size())
	return landing_s * DevBalance.land_arc_mul(from_cell, to_cell, n)

func _hidden_on(h) -> bool:
	return typeof(h) == TYPE_DICTIONARY and h.get("enabled", true) != false

func _dph_mul(u: Dictionary) -> float:
	var def: Dictionary = data.ship_def(str(u.get("ship_id", "")))
	for h in def.get("fit", {}).get("hidden", []):
		if not _hidden_on(h):
			continue
		if str(h.get("kind", "")) != "dph_mul":
			continue
		return maxf(0.0, float(h.get("value", 1.0)))
	return 1.0

func _known_deputy(did: String) -> bool:
	return did == "yang" or did == "six" or did == "chuang" or did == "bei" or did == "i"

func _deputy_choice_rows() -> Array:
	return [
		{"id": "yang", "name": "\u7f8a"},
		{"id": "six", "name": "6"},
		{"id": "chuang", "name": "\u521b"},
		{"id": "bei", "name": "\u72c8"},
		{"id": "i", "name": "I"},
	]

func _deputy_id_for(fid: int, dep_map: Dictionary) -> String:
	var did := str(dep_map.get(str(fid), "")).strip_edges()
	if _known_deputy(did):
		return did
	if fid == viewer_faction:
		var saved := PlayerSettings.get_deputy_id()
		if _known_deputy(saved):
			return saved
	return "chuang" if fid == 2 else "yang"

func _deputy_display_name(did: String) -> String:
	match did:
		"chuang":
			return "\u521b"
		"six":
			return "6"
		"bei":
			return "\u72c8"
		"i":
			return "I"
		_:
			return "\u7f8a"

func _faction_pilots(fid: int) -> Array:
	var out: Array = []
	for p in pilots:
		if int(p.get("faction", -1)) != fid:
			continue
		out.append(p)
	return out

func _commanded_pilots(group_n: int) -> Array:
	var out: Array = []
	if group_n < 0:
		return out
	for p in pilots:
		if int(p.get("faction", -1)) != viewer_faction:
			continue
		if int(p.get("ctrl_group", -1)) == group_n:
			out.append(p)
	return out

func _roster_entries(plist: Array) -> Array:
	## One row per commanded pilot. Alive ship keeps its unit dict so fleet_id writes through.
	## A pilot with no ship still counts toward N; weight uses last or default hull.
	var out: Array = []
	for p in plist:
		var u = _unit_by_id(str(p.get("unit_id", "")))
		if not u.is_empty() and u.get("alive", false) and not bool(u.get("garrison", false)):
			_stamp_roster_caps(p, u)
			out.append(u)
			continue
		var sid := str(p.get("last_ship_id", ""))
		if sid == "":
			sid = str(p.get("default_ship", ""))
		var def: Dictionary = data.ship_def(sid) if data else {}
		var stub := {
			"id": "",
			"pilot_id": str(p.get("id", "")),
			"faction": int(p.get("faction", 0)),
			"alive": true,
			"garrison": false,
			"tonnage": str(def.get("tonnage", "destroyer")),
			"ship_id": sid,
			"pd": [],
			"guard": {},
		}
		_stamp_roster_caps(p, stub)
		out.append(stub)
	return out

func _commanded_id_set(group_n: int) -> Dictionary:
	var out: Dictionary = {}
	if group_n < 0:
		return out
	for u in units:
		if not u.get("alive", false):
			continue
		if int(u.get("faction", -1)) != viewer_faction:
			continue
		if int(u.get("ctrl_group", -1)) == group_n:
			out[str(u.get("id", ""))] = true
	return out

func _rebuild_player_deputy() -> void:
	if player_deputy == null:
		return
	var cmd_pilots := _commanded_pilots(deputy_group)
	var ids := _commanded_id_set(deputy_group)
	## Empty pilot roster must not mean "all faction ships" (AI full-faction path).
	var releasing: bool = deputy_group < 0 or cmd_pilots.is_empty()
	if releasing:
		_halt_deputy_scheduled_moves(_prev_deputy_member_ids)
		player_deputy.fleets.clear()
		_prev_deputy_member_ids.clear()
	else:
		player_deputy.setup_fleets(_roster_entries(cmd_pilots))
		_flush_deputy_shortage(player_deputy, player_deputy_name)
		_prev_deputy_member_ids = ids.duplicate()
	_refresh_deputy_fleet_ui()
	_chat_deputy_cmd_count(false)

func _halt_deputy_scheduled_moves(member_ids: Dictionary) -> void:
	## Drop non-player-hold paths left by deputy station/marker orders.
	for uid in member_ids.keys():
		var u = _unit_by_id(str(uid))
		if u.is_empty() or not u.get("alive", false):
			continue
		if bool(u.get("player_hold", false)):
			continue
		u["path"] = []
		u["phase"] = BoardTypes.MovePhase.IDLE
		u["phase_t"] = 0.0
		u.erase("order_dest_sys")
		u.erase("order_dest_cell")
		u.erase("sync_gid")
		_clear_move_line(str(u.get("id", "")))

func _apply_saved_roster(factions_in: Array) -> void:
	var rebuilt: Array = []
	for fac in factions_in:
		if typeof(fac) != TYPE_DICTIONARY:
			continue
		var fid := int(fac.get("id", 0))
		for member in fac.get("members", []):
			if typeof(member) != TYPE_DICTIONARY:
				continue
			var mid := str(member.get("id", ""))
			var eight := mid.is_valid_int() and mid.length() == 8
			var placement := str(member.get("placement_id", mid))
			rebuilt.append({
				"id": placement,
				"member_id": mid if eight else "",
				"name": str(member.get("name", placement)),
				"faction": int(member.get("faction", fid)),
				"home": str(member.get("home", "")),
				"ship": str(member.get("ship", "jdl_haiyan")),
				"cell_kind": str(member.get("cell_kind", "station")),
				"gate_to": str(member.get("gate_to", "")),
			})
	if not rebuilt.is_empty():
		map.layout["pilots"] = rebuilt

func _pilot_crew_eq(pilot: Dictionary) -> Dictionary:
	if data == null:
		return {}
	var eq = data.equipment.get(str(pilot.get("crew_equip_id", "")), {})
	return eq if typeof(eq) == TYPE_DICTIONARY else {}

func _spawn_opening() -> void:
	## SHIPS §7: register pilots in station with no hull; they manufacture then undock.
	for raw in map.layout.get("pilots", []):
		var p = pilots_sys.make_pilot(raw)
		pilots.append(p)
		var home_sys: String = str(p["home"])
		if not map.systems.has(home_sys):
			push_error("pilot %s home missing: %s" % [p["id"], home_sys])
			continue
		p["in_station"] = true
		p["current_station"] = home_sys
		p["home_station"] = home_sys
		p["unit_id"] = ""
		var ship_id := str(p.get("default_ship", "gila_cc2"))
		p["last_ship_id"] = ship_id
		var def: Dictionary = data.ship_def(ship_id)
		var ton: String = str(def.get("tonnage", "destroyer"))
		pilots_sys.set_auto(p, ton, ship_id)
		print("spawn_station %s fac=%s home=%s ship=%s" % [p["id"], p["faction"], home_sys, ship_id])
		# #region agent log
		_agent_dbg("H6", "board_root._spawn_opening", "station_only", {
			"id": p["id"], "fac": int(p["faction"]), "home": home_sys, "ship": ship_id, "runId": "post-fix"
		})
		# #endregion
	# #region agent log
	var by_fac: Dictionary = {}
	for p2 in pilots:
		var fid := int(p2.get("faction", 0))
		if not by_fac.has(fid):
			by_fac[fid] = {"n": 0, "st": 0}
		by_fac[fid]["n"] = int(by_fac[fid]["n"]) + 1
		if bool(p2.get("starter", false)):
			by_fac[fid]["st"] = int(by_fac[fid]["st"]) + 1
	_dbg59("ROSTER", "board_root._spawn_opening", "roster_fill", {"by_fac": by_fac, "runId": "roster-fill"})
	# #endregion

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
	if map == null or not data.is_npc_faction(npc_fac):
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
			c["work"] = DevBalance.work_cap(kind)
			c["dev_cap"] = c["work"]
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
	if not data.is_npc_faction(npc_fac):
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
	var uid := _alloc_unit_id()
	var u = {
		"id": uid,
		"pilot_id": "",
		"pilot_name": "未知冬眠者",
		"faction": faction,
		"ship_id": ship_id,
		"model_key": str(def.get("model", ship_id)),
		"npc_hull": true,
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
		"post_sys": sys,
		"post_cell": cell,
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
		"bubble_cd": 0.0,
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

func _pair_attack_forbidden(att: Dictionary, tgt: Dictionary) -> bool:
	var rel := _rel_between(int(att.get("faction", -1)), int(tgt.get("faction", -1)))
	if rel == "self" or rel == "ally":
		return true
	if not bool(tgt.get("garrison", false)) or not bool(tgt.get("garrison_pledged", false)):
		return false
	var sid := str(tgt.get("sys", ""))
	var ci := int(tgt.get("cell", -1))
	if not map.systems.has(sid) or ci < 0:
		return false
	var cell_owner := int(map.systems[sid]["cells"][ci].get("owner", 0))
	var orel := _rel_between(int(att.get("faction", -1)), cell_owner)
	return orel == "ally" or orel == "self"

func _attack_forbidden_on(tgt: Dictionary) -> bool:
	return _pair_attack_forbidden({"faction": viewer_faction}, tgt)

func _br_with_viewer(fac: int) -> bool:
	var rel := _rel_between(viewer_faction, int(fac))
	return rel == "self" or rel == "ally"

func _faction_label(fac: int) -> String:
	for f in data.factions.get("factions", []):
		if int(f.get("id", -1)) == int(fac):
			return str(f.get("name", fac))
	return "势力%d" % int(fac)

func _join_fac_names(names) -> String:
	var parts := PackedStringArray()
	if names is Array:
		for n in names:
			var s := str(n)
			if s != "":
				parts.append(s)
	return "、".join(parts)

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
	if not _battle_fx_allowed(uid):
		return
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
	var fac := int(post.get("faction", data.primary_npc_faction()))
	if _faction_out.has(fac):
		return
	post["revealed"] = true
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

func _alloc_unit_id() -> String:
	var n := int(next_unit_i)
	next_unit_i = n + 1
	if _mp != null and _mp.active():
		return "p%d_u%d" % [_mp._me(), n]
	return "u%d" % n

func _spawn_unit(pilot: Dictionary, inst: Dictionary, sys: String, cell: int) -> Dictionary:
	var def: Dictionary = data.ship_def(inst["ship_id"])
	var uid := _alloc_unit_id()
	pilot["last_ship_id"] = str(inst["ship_id"])
	pilot["last_ship_tonnage"] = str(def.get("tonnage", "destroyer"))
	pilot["last_ship_name"] = str(def.get("name", inst["ship_id"]))
	var u = {
		"id": uid,
		"pilot_id": pilot["id"],
		"pilot_name": str(pilot.get("name", pilot["id"])),
		"faction": int(pilot["faction"]),
		"ship_id": inst["ship_id"],
		"model_key": str(def.get("model", inst["ship_id"])),
		"npc_hull": bool(def.get("npc_hull", false)),
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
		"move_s": float(def.get("move_s", 2)) * MemberTableScr.effect_mul(_pilot_crew_eq(pilot), "move_penalty_mul"),
		"crew_equip": _pilot_crew_eq(pilot),
		"landing_s": float(def.get("landing_s", 3)),
		"jump_s": float(def.get("jump_s", 3)),
		"inertia": float(def.get("inertia", 1)),
		"mass": float(def.get("mass", 1e6)),
		"speed": float(def.get("speed", 200)),
		"ab_speed_bonus": 0.0,
		"interdict_on": false,
		"interdict_since": 0.0,
		"signature_radius": float(def.get("signature_radius", 65)),
		"inst": inst,
		"bubble_on": false,
		"bubble_t": 0.0,
		"bubble_cd": 0.0,
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
		"player_hold": false,
	}
	if not pilot.has("ctrl_group"):
		var born_fac := int(pilot.get("faction", 0))
		if typeof(map.layout) == TYPE_DICTIONARY and (map.layout as Dictionary).has("ai_factions"):
			var ai_facs: Array = (map.layout as Dictionary).get("ai_factions", [])
			pilot["ctrl_group"] = 0 if ai_facs.has(born_fac) else -1
		else:
			pilot["ctrl_group"] = 0 if born_fac != viewer_faction else -1
	u["ctrl_group"] = int(pilot.get("ctrl_group", -1))
	if def.has("prep_s"):
		u["prep_s"] = float(def.get("prep_s", 0.0))
	_init_unit_combat(u)
	_mark_cell_enter(u, sys, cell)
	units.append(u)
	if int(u.get("faction", -1)) == viewer_faction:
		_rebuild_group_dict()
	return u

func _has_bubble_immune(def: Dictionary) -> bool:
	for h in def.get("fit", {}).get("hidden", []):
		if not _hidden_on(h):
			continue
		if str(h.get("kind")) == "bubble_immune":
			return true
	return false

func _build_pd(def: Dictionary) -> Array:
	var guns: Array = []
	var range_mul = 1.0
	var pd_damage_mul = 1.0
	for h in def.get("fit", {}).get("hidden", []):
		if not _hidden_on(h):
			continue
		if str(h.get("kind")) == "range_mul":
			range_mul = float(h.get("value", 1.0))
		elif str(h.get("kind")) == "pd_damage_mul":
			pd_damage_mul = float(h.get("value", 1.0))
	for h in def.get("fit", {}).get("hidden", []):
		if not _hidden_on(h):
			continue
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
				"optimal": float(eq.get("optimal_m", 0)),
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
	var cycle_mul = 1.0
	var cycle_kind := ""
	var missile_add := 0
	var explosion_mul := 1.0
	for h in def.get("fit", {}).get("hidden", []):
		if not _hidden_on(h):
			continue
		match str(h.get("kind")):
			"range_mul":
				range_mul = float(h.get("value", 1.0))
			"weapon_cycle_mul":
				cycle_mul = float(h.get("value", 1.0))
				cycle_kind = str(h.get("weapon_kind", ""))
			"missile_range_add":
				missile_add = int(h.get("value", 0))
			"missile_explosion_mul":
				explosion_mul = float(h.get("value", 1.0))
	for h in def.get("fit", {}).get("hidden", []):
		if not _hidden_on(h):
			continue
		if str(h.get("kind")) != "weapon":
			continue
		var ref: String = str(h.get("ref", ""))
		var eq: Dictionary = data.equipment.get(ref, {})
		if eq.is_empty():
			continue
		var rc = int(ceil(float(h.get("range_cells", eq.get("range_cells", 0))) * range_mul))
		var wkind = str(eq.get("kind", "weapon"))
		if wkind == "missile":
			rc += missile_add
		var cycle0 := float(eq.get("cycle_s", 4.0))
		if cycle_kind != "" and wkind == cycle_kind:
			cycle0 *= cycle_mul
		var track0 := float(eq.get("tracking", 1))
		var expl := int(eq.get("explosion_cells", 0))
		var er := float(eq.get("explosion_radius", 0.0))
		if wkind == "missile":
			expl = int(round(float(expl) * explosion_mul))
			er *= explosion_mul
		out.append({
			"ref": ref,
			"kind": wkind,
			"cycle": cycle0,
			"cycle_base": cycle0,
			"cd": rng.randf() * 0.5,
			"cap": float(eq.get("cap_cost", 0)),
			"fx": str(eq.get("fx", "laser")),
			"tracking": track0,
			"tracking_base": track0,
			"shot_n": 0,
			"sig_res": float(eq.get("signature_resolution", 40)),
			"falloff": float(eq.get("falloff_m", 4000)),
			"optimal": float(eq.get("optimal_m", 0)),
			"range_cells": rc,
			"lock_t": 0.0,
			"lock_id": "",
			"lock_need": 1.0,
			"heal_armor": float(eq.get("heal_armor", 0)),
			"heal_shield": float(eq.get("heal_shield", 0)),
			"explosion_cells": expl,
			"explosion_radius": er,
			"explosion_velocity": float(eq.get("explosion_velocity", 0.0)),
			"drf": float(eq.get("drf", 0.0)),
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
		if not _hidden_on(h):
			continue
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
			"afterburner":
				var ab_eq: Dictionary = data.equipment.get(str(h.get("ref", "")), {})
				u["ab_speed_bonus"] = float(ab_eq.get("speed_bonus", 0.0))
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
		if not _hidden_on(h2):
			continue
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
	u["implant"] = {"ref": "", "auto_on": false, "armed": false, "stacks": 0, "shots": 0, "shield_heal_cd": 0.0}
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind")) == "implant":
			u["implant"]["ref"] = str(h.get("ref", ""))
			u["implant"]["auto_on"] = true ## 有植入体则默认开
			u["implant"]["armed"] = true
			break
	_init_sniper_weapons(u)

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

func _unit_between_cells(u: Dictionary) -> bool:
	## Cross-cell INVULN: no cell membership, not an attack target (TACTICAL_TOPDOWN §9).
	if u.is_empty():
		return false
	return int(u.get("phase", 0)) == BoardTypes.MovePhase.INVULN

func _weapon_in_range(a: Dictionary, b: Dictionary, w: Dictionary) -> bool:
	if _unit_between_cells(a) or _unit_between_cells(b):
		return false
	if a["sys"] != b["sys"]:
		return false
	var n: int = map.systems[a["sys"]]["cells"].size()
	var steps = BoardTypes.shorter_arc_steps(int(a["cell"]), int(b["cell"]), n)
	return steps <= int(w["range_cells"])

func _pd_tracking_distance_m(a: Dictionary, b: Dictionary) -> float:
	if _unit_between_cells(a) or _unit_between_cells(b):
		return 999999.0
	if a["sys"] != b["sys"]:
		return 999999.0
	var n: int = map.systems[a["sys"]]["cells"].size()
	var steps = BoardTypes.shorter_arc_steps(int(a["cell"]), int(b["cell"]), n)
	return float(steps + 1) * BoardTypes.TRACKING_METERS_PER_CELL

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

func _sniper_implant(u: Dictionary) -> Dictionary:
	var imp: Dictionary = _implant_data(u)
	if imp.is_empty() or str(imp.get("id", "")) != "implant_sniper":
		return {}
	return imp

func _weapon_is_damage(w: Dictionary) -> bool:
	var kind := str(w.get("kind", ""))
	return kind != "remote_armor" and kind != "remote_shield"

func _write_sniper_weapon(w: Dictionary, armed: bool, every: float, tracking_mul: float) -> void:
	var base_c := float(w.get("cycle_base", w.get("cycle", 4.0)))
	var base_t := float(w.get("tracking_base", w.get("tracking", 1.0)))
	w["cycle_base"] = base_c
	w["tracking_base"] = base_t
	if armed:
		w["cycle"] = base_c * every
		w["tracking"] = base_t * tracking_mul
	else:
		w["cycle"] = base_c
		w["tracking"] = base_t

func _init_sniper_weapons(u: Dictionary) -> void:
	var imp := _sniper_implant(u)
	if imp.is_empty():
		return
	var armed := bool(u.get("implant", {}).get("armed", false))
	var every := float(imp.get("every", 10))
	var tmul := float(imp.get("tracking_mul", 1000))
	for w in u.get("weapons", []):
		if not _weapon_is_damage(w):
			continue
		_write_sniper_weapon(w, armed, every, tmul)

func _sample_sniper_on_cd(u: Dictionary, w: Dictionary) -> void:
	## Latch: sample implant.auto_on only when this weapon's CD has finished.
	if float(w.get("cd", 0.0)) > 0.0:
		w["sniper_sampled"] = false
		return
	if not _weapon_is_damage(w):
		return
	var imp := _sniper_implant(u)
	if imp.is_empty():
		return
	if bool(w.get("sniper_sampled", false)):
		return
	var armed := bool(u.get("implant", {}).get("auto_on", false))
	u["implant"]["armed"] = armed
	_write_sniper_weapon(w, armed, float(imp.get("every", 10)), float(imp.get("tracking_mul", 1000)))
	w["sniper_sampled"] = true

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
	if _fx_ok() and _battle_fx_allowed(str(u.get("id", ""))) and float_text and heal > 0.05:
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
	if _fx_ok() and _battle_fx_allowed(str(bearer.get("id", ""))) and float_text and absorb > 0.05:
		float_text.add_damage(_damage_float_pos(bearer), absorb, hash(str(bearer["id"])))
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
	if _fx_ok() and _battle_fx_allowed(str(bearer.get("id", ""))) and float_text and absorb > 0.05:
		float_text.add_damage(_damage_float_pos(bearer), absorb, hash(str(bearer["id"])))
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
	var atk_eq: Dictionary = {}
	if attacker and not attacker.is_empty() and typeof(attacker.get("crew_equip", {})) == TYPE_DICTIONARY:
		atk_eq = attacker.get("crew_equip", {})
	raw *= MemberTableScr.effect_mul(atk_eq, "weapon_damage_mul")
	var max_loss_ratio := 0.1 * MemberTableScr.effect_mul(atk_eq, "cap_convert_mul")
	## Hidden sleeper_hull_lock: incoming hits never cut max HP.
	if bool(target.get("no_max_loss", false)):
		skip_max_loss = true
		# #region agent log
		_dbg59("DMG", "board_root._apply_damage_to_unit", "no_max_loss", {
			"tgt": str(target.get("id", "")), "ship": str(target.get("ship_id", "")),
			"raw": raw, "runId": "no-cap-dmg"
		})
		# #endregion
	## Sleepers dealing damage never chip target max HP (SHIPS §1).
	if attacker and not attacker.is_empty() and _unit_is_sleeper(attacker):
		skip_max_loss = true
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
		portion, resist, skip_max_loss, max_loss_ratio
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
	if _fx_ok() and _battle_fx_allowed(str(target.get("id", ""))) and float_text and dealt_hp > 0.05:
		float_text.add_damage(_damage_float_pos(target), dealt_hp, hash(str(target["id"])))
	if attacker and not attacker.is_empty():
		attacker["dealt_timer"] = 1.2
		if br_tracker and (dealt_hp > 0.05 or max_loss > 0.05):
			br_tracker.note_damage(attacker, target, max_loss)
	target["took_damage"] = dealt_hp > 0.05
	target["dealt_timer"] = 1.2
	if res["killed"]:
		if br_tracker:
			br_tracker.note_kill(attacker if attacker else {}, target)
		_note_kill_chat(attacker if attacker else {}, target)
		_note_match_kill(attacker if attacker else {}, target)
		_note_deputy_fleet_wipe_before_kill(target)
		_note_enemy_deputy_fleet_wipe(attacker if attacker else {}, target)
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
			_play_turret_vfx("heal", _vfx_endpoint(u), _vfx_endpoint(u) + Vector3(0.0, 0.8, 0.0), str(u.get("id", "")))
			if _fx_ok() and _battle_fx_allowed(str(u.get("id", ""))) and float_text and hs > 0.05:
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
			_play_turret_vfx("heal", _vfx_endpoint(u), _vfx_endpoint(u) + Vector3(0.0, 0.8, 0.0), str(u.get("id", "")))
			if _fx_ok() and _battle_fx_allowed(str(u.get("id", ""))) and float_text and ha > 0.05:
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
	if _fx_ok() and _battle_fx_allowed(str(u.get("id", ""))) and float_text and heal > 0.05:
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
		if not _mp_sim_unit(u):
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
			if _unit_between_cells(tgt):
				w["lock_id"] = ""
				w["lock_t"] = 0.0
				w["retarget_t"] = 0.0
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
				and not _pair_attack_forbidden(u, focus) \
				and not _unit_between_cells(u) and not _unit_between_cells(focus) \
				and str(u["sys"]) == str(focus["sys"]):
			return focus
	for o in units:
		if not o.get("alive", false):
			continue
		if _unit_between_cells(u) or _unit_between_cells(o):
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
			if _pair_attack_forbidden(u, o):
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
	if _weapon_is_damage(w) and _unit_between_cells(tgt):
		return
	if float(inst["cap"]) < float(w.get("cap", 0)):
		return
	inst["cap"] -= float(w.get("cap", 0))
	if str(w.get("kind", "")) == "remote_armor":
		var heal = float(w.get("heal_armor", 0)) * _dph_mul(u)
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
		_play_turret_vfx(str(w.get("fx", "repair")), _vfx_emit_point(u), _vfx_hit_point(tgt), str(u.get("id", "")))
		if _fx_ok() and _battle_fx_allowed(str(tgt.get("id", ""))) and float_text and heal > 0.05:
			float_text.add_heal(tgt["pos"], heal, hash(str(tgt["id"]) + "rr"))
		# #region agent log
		_agent_dbg("RR1", "board_root._fire_weapon", "remote_heal", {
			"unit": str(u.get("id", "")), "tgt": str(tgt.get("id", "")),
			"heal": heal, "runId": "post-fix"
		})
		# #endregion
		return
	if str(w.get("kind", "")) == "remote_shield":
		var heal_s = float(w.get("heal_shield", 0)) * _dph_mul(u)
		var tinst_s: Dictionary = tgt["inst"]
		var room_s = float(tinst_s["max_s"]) - float(tinst_s["shield"])
		heal_s = minf(heal_s, maxf(0.0, room_s))
		if heal_s <= 0.05:
			inst["cap"] += float(w.get("cap", 0))
			return
		tinst_s["shield"] = float(tinst_s["shield"]) + heal_s
		_play_turret_vfx(str(w.get("fx", "repair")), _vfx_emit_point(u), _vfx_hit_point(tgt), str(u.get("id", "")))
		if _fx_ok() and _battle_fx_allowed(str(tgt.get("id", ""))) and float_text and heal_s > 0.05:
			float_text.add_heal(tgt["pos"], heal_s, hash(str(tgt["id"]) + "rs"))
		return
	## Tracking uses (cell steps + 1) meters, same as PD.
	var dist_m = _pd_tracking_distance_m(u, tgt)
	if str(w.get("kind", "")) == "missile":
		var paper = _weapon_raw(eq, w) * _dph_mul(u)
		var sniper_m := _sniper_implant(u)
		if not sniper_m.is_empty() and bool(u.get("implant", {}).get("armed", false)):
			paper *= float(sniper_m.get("mul", 10))
		var dr = BoardCombatFormulas.missile_damage_factor(
			float(tgt["signature_radius"]),
			_hit_speed(tgt),
			float(w.get("explosion_radius", 40.0)),
			float(w.get("explosion_velocity", 170.0)),
			float(w.get("drf", 0.604))
		)
		paper *= dr
		if paper > 0.0:
			_apply_damage_to_unit(u, tgt, paper, int(tgt["inst"]["resist"]))
			_missile_splash(u, tgt, paper, int(w.get("explosion_cells", 0)))
		_play_weapon_vfx(u, w, tgt, true)
		return
	var tracking = float(w.get("tracking", 1))
	var raw = _weapon_raw(eq, w) * _dph_mul(u)
	var sniper := _sniper_implant(u)
	if not sniper.is_empty() and bool(u.get("implant", {}).get("armed", false)):
		raw *= float(sniper.get("mul", 10))
	var p_hit = BoardCombatFormulas.turret_hit_chance(
		tracking, float(w.get("sig_res", 40)), float(w.get("falloff", 4000)),
		float(w.get("optimal", 0)), _hit_speed(tgt), float(tgt["signature_radius"]), dist_m
	)
	var hit = rng.randf() <= p_hit
	raw = _focus_on_hit(u, hit, raw)
	if not hit or raw <= 0.0:
		_play_weapon_vfx(u, w, tgt, false)
		return
	raw *= BoardCombatFormulas.roll_quality(rng)
	# #region agent log
	var ship_id_fire := str(u.get("ship_id", ""))
	var wref := str(w.get("ref", ""))
	if ship_id_fire == "mmte_longjuanfeng" or wref.begins_with("weapon_large_cannon"):
		_dbg59("DMG", "board_root._fire_weapon", "cannon_fire", {
			"ship": ship_id_fire, "name": str(u.get("ship_name", u.get("name", ""))),
			"ref": wref, "raw": raw, "p_hit": p_hit, "hit": hit,
			"from": str(u.get("id", "")), "to": str(tgt.get("id", "")),
			"tgt_ship": str(tgt.get("ship_id", "")),
			"runId": "tornado-cannon"
		})
	# #endregion
	_apply_damage_to_unit(u, tgt, raw, int(tgt["inst"]["resist"]))
	_play_weapon_vfx(u, w, tgt, true)

func _missile_splash(att: Dictionary, primary: Dictionary, raw: float, radius: int) -> void:
	if radius <= 0 or raw <= 0.0:
		return
	var sys := str(primary.get("sys", ""))
	if not map.systems.has(sys):
		return
	var n: int = map.systems[sys]["cells"].size()
	var origin := int(primary.get("cell", -1))
	for o in units:
		if not o.get("alive", false):
			continue
		if str(o.get("id", "")) == str(primary.get("id", "")):
			continue
		if str(o.get("sys", "")) != sys:
			continue
		if _rel_between(int(att.get("faction", -1)), int(o.get("faction", -1))) != "hostile":
			continue
		if BoardTypes.shorter_arc_steps(origin, int(o.get("cell", -1)), n) > radius:
			continue
		_apply_damage_to_unit(att, o, raw, int(o["inst"]["resist"]))

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

func _unit_art_model(u: Dictionary) -> Node3D:
	var uid := str(u.get("id", ""))
	if not unit_nodes.has(uid):
		return null
	var n: Node3D = unit_nodes[uid]
	var model := n.get_node_or_null("Model") as Node3D
	if model == null or not is_instance_valid(model) or not model.is_inside_tree():
		return null
	return model

func _vfx_emit_point(u: Dictionary, shot_n: int = -1, fx_kind: String = "") -> Vector3:
	if cam and cam.tactical_mode and not cam.starmap_mode:
		return _vfx_endpoint(u)
	var model := _unit_art_model(u)
	if model != null:
		var n := shot_n
		if n < 0:
			n = int(u.get("fx_emit_i", 0))
			u["fx_emit_i"] = n + 1
		return SHIP_ART.muzzle_world_at(model, n, fx_kind)
	return u.get("pos", Vector3.ZERO) as Vector3

func _vfx_hit_point(u: Dictionary) -> Vector3:
	if cam and cam.tactical_mode and not cam.starmap_mode:
		return _vfx_endpoint(u)
	var model := _unit_art_model(u)
	if model != null:
		return SHIP_ART.hull_center_world(model)
	return u.get("pos", Vector3.ZERO) as Vector3

func _vfx_miss_endpoint(att: Dictionary, tgt: Dictionary, shot_n: int, aim_from: Variant = null) -> Vector3:
	## Graze: tactical uses icon circle; battle uses bounding-sphere tangent.
	var from: Vector3 = aim_from if typeof(aim_from) == TYPE_VECTOR3 else _vfx_emit_point(att, shot_n)
	var anchor: Vector3 = _vfx_hit_point(tgt)
	var key := "%s|%s|%d" % [str(att.get("id", "")), str(tgt.get("id", "")), shot_n]
	var graze_r := 0.55
	if cam != null and cam.tactical_mode and not cam.starmap_mode:
		graze_r = BoardUnitOverhead.icon_circum_radius_world() * 1.25
		var dir := anchor - from
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			dir = tgt.get("face_dir", Vector3.ZERO)
			dir.y = 0.0
		if dir.length_squared() < 0.0001:
			dir = Vector3(0.0, 0.0, -1.0)
		var dir_n := dir.normalized()
		var lat := Vector3(-dir_n.z, 0.0, dir_n.x)
		if lat.length_squared() < 0.0001:
			lat = Vector3.RIGHT
		var lat_n := lat.normalized()
		var side := 1.0
		if absi(hash(key)) % 2 != 0:
			side = -1.0
		var miss := anchor + lat_n * side * graze_r + dir_n * (graze_r * 0.8)
		miss.y += 0.25
		return miss
	var hull := _unit_art_model(tgt)
	if hull != null:
		graze_r = SHIP_ART.graze_radius_world(hull)
	else:
		var ton_w := float(BoardTypes.tonnage_weight(str(tgt.get("tonnage", "destroyer"))))
		graze_r = maxf(0.55, 0.55 * ton_w)
	return SHIP_ART.graze_miss_world(from, anchor, graze_r, hash(key))

func _play_weapon_vfx(u: Dictionary, w: Dictionary, tgt: Dictionary, hit: bool) -> void:
	var shot_n := int(w.get("shot_n", 0))
	w["shot_n"] = shot_n + 1
	var fx := str(w.get("fx", "laser"))
	var from := _vfx_emit_point(u, shot_n, fx)
	var dest := _vfx_hit_point(tgt) if hit else _vfx_miss_endpoint(u, tgt, shot_n, from)
	_play_turret_vfx(fx, from, dest, str(u.get("id", "")))

func _play_pd_vfx(u: Dictionary, g: Dictionary, tgt: Dictionary, hit: bool) -> void:
	var shot_n := int(g.get("shot_n", 0))
	g["shot_n"] = shot_n + 1
	var fx := str(g.get("fx", "rail"))
	var from := _vfx_emit_point(u, shot_n, fx)
	var dest := _vfx_hit_point(tgt) if hit else _vfx_miss_endpoint(u, tgt, shot_n, from)
	_play_turret_vfx(fx, from, dest, str(u.get("id", "")))

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
		var mp := get_viewport().get_mouse_position()
		return _hover_is_hud_control() or _mouse_over_blocking_hud(mp)
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
	_setup_cmd_draw()
	popup = PopupMenu.new()
	add_child(popup)
	popup.id_pressed.connect(_on_any_popup)

func _ensure_unit_node(u: Dictionary) -> void:
	if unit_nodes.has(u["id"]):
		return
	var root = get_node("Units")
	var n = Node3D.new()
	n.name = u["id"]
	var target_d = DevBalance.hull_diameter(str(u.get("ship_id", "")))
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
	# placeholder proxy (transparent sphere; no faction fill)
	var mesh: MeshInstance3D = SHIP_ART.make_fallback_sphere(target_r * 0.35, "Proxy")
	mesh.visible = false
	n.add_child(mesh)
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
	tmat.no_depth_test = false
	tmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
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
	_battle_model_acc = 1.0


func _is_battle_view() -> bool:
	return cam != null and not cam.tactical_mode and not cam.starmap_mode

func _battle_fx_allowed(uid: String) -> bool:
	if not _is_battle_view():
		return true
	return _battle_model_ids.has(uid)

func _tick_battle_model_budget(delta: float) -> void:
	## Battle: nearest hulls, sticky hysteresis so pan/zoom does not thrash the cutoff.
	## Tactical/starmap: unload instead of instantiating the whole fleet (repeated view switches were stacking hulls).
	## Loads and frees are staggered (RTS streaming), never a full set in one frame.
	var battle := _is_battle_view()
	if battle != _model_view_battle:
		_model_view_battle = battle
		_battle_model_acc = 1.0
	_battle_model_acc += delta
	if _battle_model_acc >= 0.4:
		_battle_model_acc = 0.0
		_rebuild_model_want()
	var drops := 0
	while drops < MODEL_DROPS_PER_TICK and not _model_drop_q.is_empty():
		var uid := str(_model_drop_q.pop_front())
		if _model_want.has(uid):
			continue
		var u = _unit_by_id(uid)
		if not u.is_empty():
			_unload_ship_model(u)
		_battle_model_ids.erase(uid)
		drops += 1
	var loads := 0
	while loads < MODEL_LOADS_PER_TICK and not _model_load_q.is_empty():
		var uid2 := str(_model_load_q.pop_front())
		if not _model_want.has(uid2) or _battle_model_ids.has(uid2):
			continue
		var u2 = _unit_by_id(uid2)
		if u2.is_empty() or not unit_nodes.has(uid2):
			continue
		var n: Node3D = unit_nodes[uid2]
		var existing := n.get_node_or_null("Model") as Node3D
		if existing != null and existing.is_queued_for_deletion():
			_model_load_q.push_back(uid2)
			break
		_load_ship_model(u2)
		_battle_model_ids[uid2] = true
		if absf(float(u2.get("cloak_dir", 0.0))) > 0.01 or float(u2.get("cloak_t", 1.0)) < 0.999:
			_ensure_cloak_fx(u2)
		loads += 1

func _rebuild_model_want() -> void:
	var want: Dictionary = {}
	if _is_battle_view():
		var cam_pos := Vector3.ZERO
		if cam != null and cam.cam != null:
			cam_pos = cam.cam.global_position
		var ranked: Array = []
		for u in units:
			if not u.get("alive", false) or not unit_nodes.has(u["id"]):
				continue
			var p: Vector3 = u["pos"]
			ranked.append({"id": str(u["id"]), "d": p.distance_squared_to(cam_pos)})
		ranked.sort_custom(func(a, b):
			if float(a["d"]) == float(b["d"]):
				return str(a["id"]) < str(b["id"])
			return float(a["d"]) < float(b["d"])
		)
		var sticky := BATTLE_MODEL_BUDGET + MODEL_HYSTERESIS
		for i in ranked.size():
			var uid := str(ranked[i]["id"])
			if i < BATTLE_MODEL_BUDGET or (_battle_model_ids.has(uid) and i < sticky):
				want[uid] = true
	_model_want = want
	_model_load_q.clear()
	_model_drop_q.clear()
	for uid in _battle_model_ids.keys():
		if not want.has(str(uid)):
			_model_drop_q.append(str(uid))
	for uid2 in want.keys():
		if not _battle_model_ids.has(str(uid2)):
			_model_load_q.append(str(uid2))

func _load_ship_model(u: Dictionary) -> void:
	if not unit_nodes.has(u["id"]):
		return
	var n: Node3D = unit_nodes[u["id"]]
	var existing := n.get_node_or_null("Model") as Node3D
	if existing != null:
		## A queued free from the previous view must finish before another spawn (no stacked hulls).
		return
	var def: Dictionary = data.ship_def(str(u.get("ship_id", "")))
	var target_d = DevBalance.hull_diameter(str(u.get("ship_id", "")))
	var model_key := str(def.get("model", u.get("ship_id", "")))
	if not SHIP_ART.has_model(model_key):
		var proxy := n.get_node_or_null("Proxy") as MeshInstance3D
		if proxy:
			proxy.visible = true
		return
	var inst: Node3D = SHIP_ART.spawn_model(n, model_key, target_d, str(u.get("ship_id", "")))
	if inst == null:
		var proxy_fail := n.get_node_or_null("Proxy") as MeshInstance3D
		if proxy_fail:
			proxy_fail.visible = true
		return
	_strip_model_shadows(inst)
	u["trail_nozzles"] = SHIP_ART.engine_nozzle_locals(model_key, inst)
	u["trail_streams"] = []
	var proxy2 := n.get_node_or_null("Proxy") as MeshInstance3D
	if proxy2:
		proxy2.visible = false
	call_deferred("_reapply_art_model", inst, model_key)

func _strip_model_shadows(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in root.get_children():
		_strip_model_shadows(c)


func _pick_col(n: Node3D) -> CollisionShape3D:
	var body := n.get_node_or_null("PickBody") as StaticBody3D
	if body == null or body.get_child_count() == 0:
		return null
	return body.get_child(0) as CollisionShape3D

func _fit_pick_body_to_model(n: Node3D) -> void:
	## Battlefield click hits the drawn hull: box = model AABB in the ship node frame.
	if n == null or not is_instance_valid(n):
		return
	var model := n.get_node_or_null("Model") as Node3D
	var col := _pick_col(n)
	if model == null or col == null or not model.is_inside_tree():
		return
	var local_aabb := _mesh_aabb_local(model)
	if local_aabb.size == Vector3.ZERO:
		return
	var aabb: AABB = (n.global_transform.affine_inverse() * model.global_transform) * local_aabb
	if not col.has_meta("disk_shape"):
		col.set_meta("disk_shape", col.shape)
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(aabb.size.x, 0.6), maxf(aabb.size.y, 0.6), maxf(aabb.size.z, 0.6))
	col.shape = box
	col.position = aabb.get_center()

func _restore_pick_disk(n: Node3D) -> void:
	var col := _pick_col(n)
	if col == null or not col.has_meta("disk_shape"):
		return
	col.shape = col.get_meta("disk_shape")
	col.position = Vector3.ZERO

func _unload_ship_model(u: Dictionary) -> void:
	if not unit_nodes.has(u["id"]):
		return
	var n: Node3D = unit_nodes[u["id"]]
	_restore_pick_disk(n)
	var model := n.get_node_or_null("Model") as Node3D
	if model != null and not model.is_queued_for_deletion():
		model.queue_free()
	var proxy := n.get_node_or_null("Proxy") as MeshInstance3D
	if proxy:
		proxy.visible = false
	var trail := n.get_node_or_null("Trail") as MeshInstance3D
	if trail:
		trail.visible = false
		trail.mesh = null
	u["trail_pts"] = []
	u["trail_streams"] = []
	u["trail_nozzles"] = []
	var cloak := n.get_node_or_null("CloakFx")
	if cloak != null and not cloak.is_queued_for_deletion():
		cloak.queue_free()


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
	SHIP_ART.fit_scale(inst, target_diameter)

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
	var unit_root := get_node_or_null("Units")
	var host: Node = inst
	while host != null and host.get_parent() != unit_root:
		host = host.get_parent()
	_fit_pick_body_to_model(host as Node3D)
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
	_build_match_clock(layer)
	hud_layer = layer
	_build_bottom_bar(layer)
	_build_deputy_panel(layer)
	_build_diplomacy(layer)
	_build_game_menu(layer)
	_build_marker_layer(layer)
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
	## UI_AND_SHELL §3: black α=0.08 backdrop under 战报 / 详情.
	br_scroll.add_theme_stylebox_override("panel", _right_col_backdrop())
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
	detail.add_theme_stylebox_override("normal", _right_col_backdrop())
	_apply_ui_font(detail)
	right_col.add_child(detail)
	layer.add_child(right_col)
	_build_zoom_buttons(layer)
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
		_refresh_pilot_row_places(row, p)
	if need_rebuild_bars:
		_rebuild_hud_list()

func _rebuild_hud_list() -> void:
	if left_rows == null:
		return
	for c in left_rows.get_children():
		c.queue_free()
	for p in _sorted_viewer_pilots():
		left_rows.add_child(_make_pilot_row(p))

func _sorted_viewer_pilots() -> Array:
	var mine: Array = []
	for p in pilots:
		if int(p["faction"]) != viewer_faction:
			continue
		mine.append(p)
	mine.sort_custom(func(a, b):
		var sa := _pilot_list_sort_key(a)
		var sb := _pilot_list_sort_key(b)
		if sa[0] != sb[0]:
			return sa[0] < sb[0]
		if sa[1] != sb[1]:
			return sa[1] < sb[1]
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return mine

func _pilot_list_sort_key(p: Dictionary) -> Array:
	## Lower = earlier: selected first, then numbered groups, then rest.
	var uid := str(p.get("unit_id", ""))
	var selected := 0 if (uid != "" and selection.has(uid)) else 1
	var nums = _pilot_group_numbers(p)
	var group_rank := 0 if not nums.is_empty() else 1
	var first_g := int(nums[0]) if not nums.is_empty() else 99
	return [selected, group_rank, first_g]

func _pin_selected_left_rows() -> void:
	if left_rows == null:
		return
	var rows: Array = left_rows.get_children()
	if rows.is_empty():
		return
	rows.sort_custom(func(ra, rb):
		var pa = _pilot_by_id(str(ra.get_meta("pilot", "")))
		var pb = _pilot_by_id(str(rb.get_meta("pilot", "")))
		var sa := _pilot_list_sort_key(pa) if not pa.is_empty() else [2, 1, 99]
		var sb := _pilot_list_sort_key(pb) if not pb.is_empty() else [2, 1, 99]
		if sa[0] != sb[0]:
			return sa[0] < sb[0]
		if sa[1] != sb[1]:
			return sa[1] < sb[1]
		return sa[2] < sb[2]
	)
	for i in range(rows.size()):
		left_rows.move_child(rows[i], i)

func _build_bottom_bar(parent: Control) -> void:
	## ScrollContainer so soft-key min-width cannot stretch under side columns.
	bottom_bar = ScrollContainer.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bottom_bar.z_index = 50
	bottom_bar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bottom_bar.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.name = "BottomRow"
	row.add_theme_constant_override("separation", 6)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_build_soft_key_bar(row)
	for spec in [["trench", "战壕"], ["target", "目标"], ["arrow", "箭头"]]:
		var b := Button.new()
		b.text = spec[1]
		b.custom_minimum_size = Vector2(64, 36)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.pressed.connect(_on_marker_button.bind(spec[0]))
		_apply_ui_font(b)
		row.add_child(b)
		marker_btns[spec[0]] = b
	bottom_bar.add_child(row)
	parent.add_child(bottom_bar)
	_build_chat_panel(parent)
	_layout_bottom_bar()

func _build_chat_panel(parent: Control) -> void:
	chat_panel = PanelContainer.new()
	chat_panel.name = "ChatPanel"
	chat_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	chat_panel.z_index = 45
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	chat_panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.name = "ChatScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(scroll)
	chat_scroll = scroll
	## Spacer on top pushes the log to the panel floor while lines are few.
	var stack := VBoxContainer.new()
	stack.name = "ChatStack"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(stack)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(spacer)
	chat_log = RichTextLabel.new()
	chat_log.name = "ChatLog"
	chat_log.bbcode_enabled = false
	chat_log.fit_content = true
	chat_log.scroll_active = false
	chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_log.size_flags_vertical = Control.SIZE_SHRINK_END
	chat_log.mouse_filter = Control.MOUSE_FILTER_PASS
	_apply_ui_font(chat_log)
	chat_log.add_theme_font_size_override("normal_font_size", 13)
	stack.add_child(chat_log)
	if _mp != null and _mp.active():
		var mp_edit := LineEdit.new()
		mp_edit.name = "MpChatEdit"
		mp_edit.placeholder_text = "对所有人说"
		mp_edit.text_submitted.connect(_on_mp_chat_submit)
		stack.add_child(mp_edit)
	var vbar := scroll.get_v_scroll_bar()
	vbar.value_changed.connect(_on_chat_scroll_value)
	vbar.changed.connect(_on_chat_scroll_range)
	parent.add_child(chat_panel)
	if not _chat_lines.is_empty():
		chat_log.text = "\n".join(PackedStringArray(_chat_lines))
	_layout_chat_panel()

func _layout_bottom_bar() -> void:
	if bottom_bar == null or not is_instance_valid(bottom_bar):
		return
	var vr := get_viewport().get_visible_rect().size
	## Between LeftCol (360+8) and RightCol (vr.x-316); do not underlap side columns.
	var left_x := 376.0
	var right_x := vr.x - 324.0
	var w := maxf(right_x - left_x, 280.0)
	bottom_bar.position = Vector2(left_x, vr.y - 52)
	bottom_bar.size = Vector2(w, 44)
	_layout_chat_panel()

func _layout_chat_panel() -> void:
	if chat_panel == null or not is_instance_valid(chat_panel):
		return
	var vr := get_viewport().get_visible_rect().size
	var left_x := 376.0
	var h := 180.0
	var w := 420.0
	chat_panel.position = Vector2(left_x, vr.y - 52.0 - 8.0 - h)
	chat_panel.size = Vector2(w, h)

func _unit_is_sleeper(u: Dictionary) -> bool:
	if u.is_empty():
		return false
	if bool(u.get("garrison", false)):
		return true
	return data != null and data.is_npc_faction(int(u.get("faction", -1)))

func _chat_append(line: String) -> void:
	if line == "":
		return
	_chat_lines.append(line)
	while _chat_lines.size() > CHAT_MAX_LINES:
		_chat_lines.remove_at(0)
	if chat_log == null:
		return
	chat_log.text = "\n".join(PackedStringArray(_chat_lines))
	# #region agent log
	var vb := chat_scroll.get_v_scroll_bar() if chat_scroll else null
	_dbg59("CHAT", "board_root._chat_append", "append", {
		"stick": _chat_stick, "value": vb.value if vb else -1.0,
		"max": vb.max_value if vb else -1.0, "page": vb.page if vb else -1.0,
		"lines": _chat_lines.size(), "runId": "post-fix"
	})
	# #endregion

func _chat_at_bottom(vbar: ScrollBar) -> bool:
	return vbar.value >= vbar.max_value - vbar.page - 4.0

func _on_chat_scroll_value(_v: float) -> void:
	if chat_scroll == null or _chat_snapping:
		return
	_chat_stick = _chat_at_bottom(chat_scroll.get_v_scroll_bar())

func _on_chat_scroll_range() -> void:
	## Content grew: follow only when the reader was already at the newest line.
	if chat_scroll == null or not _chat_stick:
		return
	var vbar := chat_scroll.get_v_scroll_bar()
	_chat_snapping = true
	vbar.value = vbar.max_value
	_chat_snapping = false

func _chat_deputy(line_body: String) -> void:
	_chat_append("%s：%s" % [player_deputy_name, line_body])

func _flush_deputy_shortage(ctrl: BoardAiController, speaker: String) -> void:
	if ctrl == null:
		return
	for line in ctrl.shortage_lines:
		_chat_append("%s\uff1a%s" % [speaker, str(line)])
	ctrl.shortage_lines.clear()

func _pilot_display_name_of_unit(u: Dictionary) -> String:
	if u.is_empty():
		return "未知"
	var p = _pilot_by_id(str(u.get("pilot_id", "")))
	if not p.is_empty():
		return str(p.get("name", p.get("id", "未知")))
	return str(u.get("pilot_name", u.get("name", "未知")))

func _ship_name_of_unit(u: Dictionary) -> String:
	if u.is_empty():
		return "?"
	var nm := str(u.get("ship_name", ""))
	if nm != "":
		return nm
	var def: Dictionary = data.ship_def(str(u.get("ship_id", ""))) if data else {}
	return str(def.get("name", u.get("ship_id", "?")))

func _ship_class_label(u: Dictionary) -> String:
	var nm := _ship_name_of_unit(u)
	if nm.ends_with("级"):
		return nm
	return nm + "级"

func _note_kill_chat(attacker: Dictionary, target: Dictionary) -> void:
	## Own member loss: the member speaks, whoever the killer is. Own kill: killer speaks; no sleeper victims.
	if target.is_empty() or _unit_is_sleeper(target):
		return
	var att_mine: bool = not attacker.is_empty() and int(attacker.get("faction", -1)) == viewer_faction \
			and bool(attacker.get("commandable", true)) and not bool(attacker.get("garrison", false))
	var tgt_mine: bool = int(target.get("faction", -1)) == viewer_faction \
			and bool(target.get("commandable", true)) and not bool(target.get("garrison", false))
	# #region agent log
	_dbg59("KILL", "board_root._note_kill_chat", "kill", {
		"att": str(attacker.get("id", "")), "att_fac": int(attacker.get("faction", -1)),
		"att_sleeper": not attacker.is_empty() and _unit_is_sleeper(attacker),
		"tgt": str(target.get("id", "")), "tgt_fac": int(target.get("faction", -1)),
		"att_mine": att_mine, "tgt_mine": tgt_mine, "runId": "post-fix"
	})
	# #endregion
	if tgt_mine:
		var self_name := _pilot_display_name_of_unit(target)
		_chat_append("%s：击毁%s[%s]" % [self_name, self_name, _ship_class_label(target)])
		return
	if att_mine:
		_chat_append("%s：击毁%s[%s]" % [
			_pilot_display_name_of_unit(attacker),
			_pilot_display_name_of_unit(target),
			_ship_class_label(target)
		])

func _cell_kind_zh(kind: int) -> String:
	match kind:
		BoardTypes.CellKind.GATE:
			return "星门"
		BoardTypes.CellKind.RESOURCE:
			return "资源"
		BoardTypes.CellKind.STATION:
			return "空间站"
		BoardTypes.CellKind.SOV:
			return "主权"
		_:
			return "地点"

func _sys_display_name(sid: String) -> String:
	if map == null or not map.systems.has(sid):
		return sid
	return str(map.systems[sid].get("name", sid))

func _chat_deputy_cmd_count(force: bool) -> void:
	var n := 0
	if deputy_group >= 0:
		n = _commanded_pilots(deputy_group).size()
	if not force and n == _deputy_cmd_count:
		return
	# #region agent log
	var stk: Array = []
	for fr in get_stack():
		stk.append("%s:%d" % [str(fr.get("function", "")), int(fr.get("line", 0))])
	_dbg59("CMD", "board_root._chat_deputy_cmd_count", "post", {
		"n": n, "prev": _deputy_cmd_count, "force": force, "group": deputy_group,
		"stack": stk.slice(0, 5), "runId": "post-fix"
	})
	# #endregion
	_deputy_cmd_count = n
	if n > 0:
		_chat_deputy("已确认对%d人的指挥权，正在调度" % n)
	else:
		_chat_deputy("已确认对0人的指挥权，我将实时替您关注战场")

func _note_deputy_fleet_wipe_before_kill(target: Dictionary) -> void:
	if player_deputy == null or deputy_group < 0 or target.is_empty():
		return
	if int(target.get("faction", -1)) != viewer_faction:
		return
	var tid := str(target.get("id", ""))
	var role_n: Dictionary = {}
	var role_i: Dictionary = {}
	for f0 in player_deputy.fleets:
		var r0 := str(f0.get("role", "main"))
		role_n[r0] = int(role_n.get(r0, 0)) + 1
	for f in player_deputy.fleets:
		var role := str(f.get("role", "main"))
		var ix := int(role_i.get(role, 0))
		role_i[role] = ix + 1
		var members: Array = f.get("members", [])
		var has := false
		for m in members:
			if str(m) == tid:
				has = true
				break
		if not has:
			continue
		var alive_left := 0
		var last_sys := str(target.get("sys", ""))
		for m2 in members:
			var ou = _unit_by_id(str(m2))
			if ou.is_empty() or not ou.get("alive", false):
				continue
			if str(ou.get("id", "")) == tid:
				continue
			alive_left += 1
			last_sys = str(ou.get("sys", last_sys))
		if alive_left > 0:
			continue
		var fname := _fleet_role_label(role, ix, int(role_n.get(role, 1)))
		_chat_deputy("%s 在%s处被全歼，正在组织新舰队。" % [fname, _sys_display_name(last_sys)])
		return

func _faction_holds_station(fac: int) -> bool:
	for sid in map.systems.keys():
		var sc = map.station_cell(sid)
		if sc >= 0 and int(map.systems[sid]["cells"][sc]["owner"]) == fac:
			return true
	return false

func _faction_live_ships(fac: int) -> int:
	var n := 0
	for u in units:
		if int(u.get("faction", -1)) == fac and u.get("alive", false) and not bool(u.get("garrison", false)):
			n += 1
	return n

func _defeat_faction(fac: int) -> void:
	## MATCH_FLOW §4.0: one-shot surrender; no more launches; remaining garrisons leave the board.
	_faction_out[fac] = true
	var removed := 0
	for u in units:
		if int(u.get("faction", -1)) == fac and u.get("alive", false):
			_kill_unit(u)
			removed += 1
	for p in pilots:
		if int(p.get("faction", -1)) != fac:
			continue
		p["in_station"] = false
		p["current_station"] = ""
		p["home_station"] = ""
		for ton in p.get("auto_build", {}).keys():
			pilots_sys.set_auto(p, str(ton), "")
	_chat_deputy("%s势力已投降" % _faction_label(fac))
	# #region agent log
	_dbg59("DEF", "board_root._defeat_faction", "defeated", {
		"fac": fac, "removed_units": removed, "t": _sim_clock, "runId": "post-fix"
	})
	# #endregion

func _announce_marker_confirm(kind: String) -> void:
	var key := ""
	var body := ""
	match kind:
		"trench":
			var sys := _trench_defense_system()
			if sys == "":
				return
			key = "trench:" + sys
			body = "指令收到，确认在%s构筑防线" % _sys_display_name(sys)
		"target":
			if not map_markers.has("target"):
				return
			var tsys := _nearest_system(map_markers["target"]["pos"])
			if tsys == "":
				return
			key = "target:" + tsys
			body = "指令收到，确认%s为进攻目标" % _sys_display_name(tsys)
		"arrow":
			if not map_markers.has("arrow"):
				return
			var names := _arrow_corridor_sys_names()
			if names.is_empty():
				return
			key = "arrow:" + ",".join(names)
			body = "指令收到，设%s，为优先导航途经点" % "，".join(names)
		_:
			return
	if str(_marker_announce.get(kind, "")) == key:
		return
	_marker_announce[kind] = key
	_chat_deputy(body)

func _arrow_corridor_sys_names() -> PackedStringArray:
	var out := PackedStringArray()
	if not map_markers.has("arrow"):
		return out
	var m: Dictionary = map_markers["arrow"]
	var a: Vector3 = m.get("a", Vector3.ZERO)
	var b: Vector3 = m.get("b", Vector3.ZERO)
	var ab := b - a
	var ab_len2 := ab.length_squared()
	var hits: Array = []
	for sid in map.systems.keys():
		var c: Vector3 = map.systems[sid]["center"]
		var t := 0.5
		if ab_len2 > 0.001:
			t = clampf((c - a).dot(ab) / ab_len2, -0.2, 1.2)
		var foot := a + ab * t
		var dist := Vector3(c.x - foot.x, 0.0, c.z - foot.z).length()
		if dist <= 40.0 and t >= -0.05 and t <= 1.05:
			hits.append({"sid": str(sid), "t": t})
	hits.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	for h in hits:
		out.append(_sys_display_name(str(h["sid"])))
	if out.is_empty():
		var nearest := _nearest_system(m.get("pos", a))
		if nearest != "":
			out.append(_sys_display_name(nearest))
	return out

func _build_soft_key_bar(parent: Control) -> void:
	var bar = HBoxContainer.new()
	bar.name = "SoftKeyBar"
	bar.add_theme_constant_override("separation", 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	soft_ctrl_btn = Button.new()
	soft_ctrl_btn.name = "SoftCtrl"
	soft_ctrl_btn.text = "Ctrl"
	soft_ctrl_btn.toggle_mode = true
	soft_ctrl_btn.custom_minimum_size = Vector2(48, 36)
	soft_ctrl_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	soft_ctrl_btn.toggled.connect(_on_soft_ctrl_toggled)
	_apply_ui_font(soft_ctrl_btn)
	bar.add_child(soft_ctrl_btn)
	for d in range(1, 11):
		var g := d % 10 ## 1..9 then 0
		var b = Button.new()
		b.text = str(g)
		b.custom_minimum_size = Vector2(32, 36)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.pressed.connect(_on_soft_digit.bind(g))
		_apply_ui_font(b)
		bar.add_child(b)
	parent.add_child(bar)

func _on_soft_ctrl_toggled(on: bool) -> void:
	soft_ctrl_sticky = on
	_refresh_soft_ctrl_btn()

func _refresh_soft_ctrl_btn() -> void:
	if soft_ctrl_btn == null:
		return
	soft_ctrl_btn.set_pressed_no_signal(soft_ctrl_sticky)
	soft_ctrl_btn.modulate = Color(1.0, 0.85, 0.35, 1.0) if soft_ctrl_sticky else Color.WHITE

func _clear_soft_ctrl_sticky() -> void:
	soft_ctrl_sticky = false
	_refresh_soft_ctrl_btn()

func _on_soft_digit(g: int) -> void:
	if soft_ctrl_sticky:
		_assign_control_group(g)
		_clear_soft_ctrl_sticky()
		return
	_select_control_group(g, true)

func _build_deputy_panel(parent: Control) -> void:
	deputy_panel = PanelContainer.new()
	deputy_panel.name = "DeputyPanel"
	deputy_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	deputy_panel.custom_minimum_size = Vector2(210, 72)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	deputy_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var face_box := Control.new()
	face_box.name = "DeputyFaceBox"
	face_box.custom_minimum_size = Vector2(48, 48)
	face_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	face_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face_box.clip_contents = true
	face_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(face_box)
	deputy_face = TextureRect.new()
	deputy_face.name = "DeputyFace"
	deputy_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	deputy_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	deputy_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face_box.add_child(deputy_face)
	deputy_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deputy_name_lab = Label.new()
	deputy_name_lab.text = player_deputy_name
	_apply_ui_font(deputy_name_lab)
	head.add_child(deputy_name_lab)
	_refresh_deputy_face()
	deputy_opt = OptionButton.new()
	deputy_opt.custom_minimum_size = Vector2(190, 28)
	_apply_ui_font(deputy_opt)
	## id -1 auto-assigns to 0 and collides with group 0 — use -2 for wait.
	deputy_opt.add_item("等待分配", -2)
	for g in [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]:
		deputy_opt.add_item("代为指挥编队 %d" % g, g)
	deputy_opt.item_selected.connect(_on_deputy_group_picked)
	box.add_child(deputy_opt)
	deputy_fleet_box = VBoxContainer.new()
	box.add_child(deputy_fleet_box)
	parent.add_child(deputy_panel)
	_layout_deputy_panel()

func _layout_deputy_panel() -> void:
	if deputy_panel == null or not is_instance_valid(deputy_panel):
		return
	deputy_panel.position = Vector2(376, 8)

func _deputy_face_path(deputy_id: String) -> String:
	return "res://assets/ui/deputies/%s.png" % deputy_id

func _refresh_deputy_face() -> void:
	if deputy_face == null or not is_instance_valid(deputy_face):
		return
	var did := "yang"
	if player_deputy != null:
		did = str(player_deputy.deputy_id)
	var path := _deputy_face_path(did)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img:
			tex = ImageTexture.create_from_image(img)
	deputy_face.texture = tex
	# #region agent log
	_dbg59("FACE", "board_root._refresh_deputy_face", "face", {
		"did": did, "res_exists": ResourceLoader.exists(path), "file_exists": FileAccess.file_exists(path),
		"tex_ok": tex != null, "tex_size": str(tex.get_size()) if tex else "",
		"rect_size": str(deputy_face.size), "box": deputy_face.get_parent().get_class(),
		"img_alpha": tex.get_image().detect_alpha() if tex else -1, "runId": "post-fix"
	})
	# #endregion

func _on_deputy_group_picked(idx: int) -> void:
	if deputy_opt == null:
		return
	var gid := int(deputy_opt.get_item_id(idx))
	## -2 (wait) or any negative → release command.
	deputy_group = gid if gid >= 0 else -1
	_mp_on_deputy(viewer_faction, deputy_group)
	_rebuild_player_deputy()
	_rebalance_deputy_resources()

func _pilot_is_guard(p: Dictionary) -> bool:
	var sid := _pilot_display_ship_id(p)
	var def: Dictionary = data.ship_def(sid)
	var fit: Dictionary = def.get("fit", {})
	for slot in fit.get("slots", []):
		if typeof(slot) != TYPE_STRING:
			continue
		if slot == "armor_link" or slot == "shield_field":
			return true
	for h in fit.get("hidden", []):
		var k := str(h.get("kind", ""))
		if k.begins_with("guard"):
			return true
		var ref := str(h.get("ref", ""))
		if ref == "armor_link" or ref == "shield_field":
			return true
	return false

func _deputy_resource_rows(ctrl: BoardAiController, plist: Array) -> Array:
	var rows: Array = []
	for p in plist:
		var pid := str(p.get("id", ""))
		var guard := false
		var shield := false
		var raid := false
		var uid := str(p.get("unit_id", ""))
		for f in ctrl.fleets:
			if str(f.get("req_pilot", "")) == pid:
				guard = true
			var in_f := (f.get("pilot_ids", []) as Array).has(pid) or (uid != "" and (f.get("members", []) as Array).has(uid))
			if not in_f:
				continue
			if str(f.get("role", "")) == "shield":
				shield = true
			if str(f.get("role", "")) == "raid":
				raid = true
		rows.append({"id": pid, "guard": guard, "shield": shield, "raid": raid})
	return rows

func _rebalance_ctrl(ctrl: BoardAiController, plist: Array) -> void:
	if ctrl == null or plist.is_empty():
		return
	var rows := _deputy_resource_rows(ctrl, plist)
	var did := str(ctrl.deputy_id)
	if did == "chuang" or did == "i":
		BoardResourceAssign.rebalance_even(map, rows)
	elif did == "six":
		BoardResourceAssign.rebalance_six(map, rows)
	elif did == "bei":
		BoardResourceAssign.rebalance_bei(map, rows)
	else:
		BoardResourceAssign.rebalance_yang(map, rows)

func _rebalance_faction_resources(fid: int) -> void:
	var ctrl: BoardAiController = faction_ai.get(fid)
	if ctrl == null:
		return
	_rebalance_ctrl(ctrl, _faction_pilots(fid))

func _rebalance_deputy_resources() -> void:
	if deputy_group < 0 or player_deputy == null:
		return
	_rebalance_ctrl(player_deputy, _commanded_pilots(deputy_group))

func _fleet_role_label(role: String, index_among_role: int, role_count: int) -> String:
	var base := "主力舰队"
	match role:
		"mid":
			base = "中型舰队"
		"small":
			base = "小型舰队"
		"attrition":
			base = "战术换损舰队"
		"shield":
			base = "\u76fe\u5b88\u8230\u961f"
		"raid":
			base = "\u62a2\u5360\u8230\u961f"
		"tac_main":
			base = "\u6218\u672f\u4e3b\u529b\u8230\u961f"
		"main":
			base = "主力舰队"
		_:
			base = role if role != "" else "舰队"
	if role_count > 1:
		return "%s%d" % [base, index_among_role + 1]
	return base

func _refresh_deputy_fleet_ui() -> void:
	if deputy_fleet_box == null:
		return
	for c in deputy_fleet_box.get_children():
		c.queue_free()
	if player_deputy == null:
		return
	var role_n: Dictionary = {}
	var role_i: Dictionary = {}
	for f0 in player_deputy.fleets:
		var r0 := str(f0.get("role", "main"))
		role_n[r0] = int(role_n.get(r0, 0)) + 1
	for f in player_deputy.fleets:
		var b := Button.new()
		var role := str(f.get("role", "main"))
		var ix := int(role_i.get(role, 0))
		role_i[role] = ix + 1
		var label := _fleet_role_label(role, ix, int(role_n.get(role, 1)))
		var mark := str(f.get("marker", ""))
		if mark != "":
			label += "·" + mark
		b.text = "%s %d" % [label, _fleet_display_weight(f)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		_apply_ui_font(b)
		var fid := int(f.get("id", 0))
		b.pressed.connect(_select_deputy_fleet.bind(fid))
		b.gui_input.connect(_on_deputy_fleet_gui.bind(fid))
		deputy_fleet_box.add_child(b)

func _fleet_display_weight(f: Dictionary) -> int:
	return int(f.get("weight", 0))

func _select_deputy_fleet(fid: int) -> void:
	if player_deputy == null:
		return
	for f in player_deputy.fleets:
		if int(f.get("id", -1)) != fid:
			continue
		selection = (f.get("members", []) as Array).duplicate()
		_update_detail()
		_pin_selected_left_rows()
		return

func _on_deputy_fleet_gui(ev: InputEvent, fid: int) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if player_deputy == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	var total := 0
	var req_pid := ""
	var shield_pid := ""
	var req_seen := false
	var shield_seen := false
	for f in player_deputy.fleets:
		if int(f.get("id", -1)) != fid:
			continue
		total = _fleet_display_weight(f)
		req_pid = str(f.get("req_pilot", ""))
		shield_pid = str(f.get("req_shield", ""))
		for uid in f.get("members", []):
			var u = _unit_by_id(str(uid))
			if u.is_empty():
				continue
			var uw := BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
			var nm := str(u.get("pilot_name", uid)).replace("[", "[lb]")
			var upid := str(u.get("pilot_id", ""))
			if upid != "" and upid == req_pid:
				req_seen = true
				lines.append("[color=yellow]%s[/color]  %d  [color=yellow]%s[/color]" % [nm, uw, _req_ship_note(upid)])
			elif upid != "" and upid == shield_pid:
				shield_seen = true
				lines.append("[color=yellow]%s[/color]  %d  [color=yellow]%s[/color]" % [nm, uw, _req_ship_note(upid)])
			else:
				lines.append("%s  %d" % [nm, uw])
	if req_pid != "" and not req_seen:
		var rp: Dictionary = _pilot_by_id(req_pid)
		if not rp.is_empty():
			lines.append("[color=yellow]%s[/color]  [color=yellow]%s[/color]" % [
				str(rp.get("name", req_pid)).replace("[", "[lb]"), _req_ship_note(req_pid)])
	if shield_pid != "" and shield_pid != req_pid and not shield_seen:
		var sp: Dictionary = _pilot_by_id(shield_pid)
		if not sp.is_empty():
			lines.append("[color=yellow]%s[/color]  [color=yellow]%s[/color]" % [
				str(sp.get("name", shield_pid)).replace("[", "[lb]"), _req_ship_note(shield_pid)])
	if lines.is_empty() and total <= 0:
		return
	var pop := PopupPanel.new()
	add_child(pop)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rtl.scroll_active = false
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_ui_font(rtl)
	rtl.text = "[color=#9a9a9a]权重合计  %d[/color]\n%s" % [total, "\n".join(lines)]
	pop.add_child(rtl)
	pop.popup_hide.connect(pop.queue_free)
	pop.position = Vector2i(mb.global_position)
	pop.reset_size()
	pop.popup()
	# #region agent log
	_dbg59("DSG", "board_root._on_deputy_fleet_gui", "fleet_detail", {
		"fleet": fid, "req_pilot": req_pid, "req_on_board": req_seen, "rows": lines.size(), "runId": "post-fix"
	})
	# #endregion

func _req_ship_note(pid: String) -> String:
	var p: Dictionary = _pilot_by_id(pid)
	var sid := str(p.get("deputy_req_ship", ""))
	var nm := str(data.ship_def(sid).get("name", sid)) if sid != "" else "装甲链接舰"
	return "被要求驾驶%s" % nm

func _build_diplomacy(parent: Control) -> void:
	diplo_btn = Button.new()
	diplo_btn.name = "DiploBtn"
	diplo_btn.text = "外交"
	diplo_btn.custom_minimum_size = Vector2(72, 32)
	diplo_btn.size = Vector2(72, 32)
	diplo_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	diplo_btn.z_index = 50
	_apply_ui_font(diplo_btn)
	diplo_btn.pressed.connect(_toggle_diplomacy)
	parent.add_child(diplo_btn)
	diplo_panel = PanelContainer.new()
	diplo_panel.name = "DiploPanel"
	diplo_panel.visible = false
	diplo_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	diplo_panel.z_index = 80
	parent.add_child(diplo_panel)
	_layout_diplomacy()
	_rebuild_diplomacy_rows()

func _layout_diplomacy() -> void:
	if diplo_btn == null:
		return
	var vr := get_viewport().get_visible_rect().size
	diplo_btn.position = Vector2(vr.x - 88, 8)
	if diplo_panel:
		## Left of RightCol (vr.x - 316) so the column cannot eat clicks.
		var pw := maxf(diplo_panel.size.x, 220.0)
		diplo_panel.position = Vector2(vr.x - 316.0 - 12.0 - pw, 44.0)
	_layout_game_menu()

func _toggle_diplomacy() -> void:
	if diplo_panel == null:
		return
	diplo_panel.visible = not diplo_panel.visible
	if diplo_panel.visible:
		_close_game_menu()
		_rebuild_diplomacy_rows()

func _build_game_menu(parent: Control) -> void:
	menu_btn = Button.new()
	menu_btn.name = "MenuBtn"
	menu_btn.text = "菜单"
	menu_btn.custom_minimum_size = Vector2(72, 32)
	menu_btn.size = Vector2(72, 32)
	menu_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_btn.z_index = 50
	_apply_ui_font(menu_btn)
	menu_btn.pressed.connect(_toggle_game_menu)
	parent.add_child(menu_btn)
	menu_window = Window.new()
	menu_window.name = "GameMenuWindow"
	menu_window.title = "菜单"
	menu_window.transient = true
	## Not exclusive: the deputy OptionButton popup must receive the click.
	menu_window.exclusive = false
	menu_window.unresizable = true
	menu_window.transparent = false
	menu_window.borderless = true
	menu_window.always_on_top = true
	menu_window.visible = false
	menu_window.min_size = Vector2i(300, 280)
	menu_window.size = Vector2i(320, 440)
	menu_window.close_requested.connect(_close_game_menu)
	add_child(menu_window)
	var root := PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.14, 1.0)
	sb.set_content_margin_all(12)
	root.add_theme_stylebox_override("panel", sb)
	menu_window.add_child(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	menu_pause_lab = Label.new()
	menu_pause_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_ui_font(menu_pause_lab)
	box.add_child(menu_pause_lab)
	menu_page = VBoxContainer.new()
	menu_page.add_theme_constant_override("separation", 4)
	box.add_child(menu_page)
	for item in [
		{"t": "继续游戏", "id": "continue"},
		{"t": "读取存档", "id": "load"},
		{"t": "保存存档", "id": "save"},
		{"t": "回到主菜单", "id": "main"},
		{"t": "设置", "id": "settings"},
	]:
		var b := Button.new()
		b.text = str(item["t"])
		b.custom_minimum_size = Vector2(260, 32)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		_apply_ui_font(b)
		b.pressed.connect(_on_game_menu_item.bind(str(item["id"])))
		menu_page.add_child(b)
	settings_page = VBoxContainer.new()
	settings_page.visible = false
	settings_page.add_theme_constant_override("separation", 8)
	box.add_child(settings_page)
	menu_load_page = VBoxContainer.new()
	menu_load_page.visible = false
	menu_load_page.add_theme_constant_override("separation", 4)
	box.add_child(menu_load_page)
	_rebuild_settings_panel()
	_layout_game_menu()
	_apply_audio_volumes()

func _layout_game_menu() -> void:
	if menu_btn == null:
		return
	var vr := get_viewport().get_visible_rect().size
	menu_btn.position = Vector2(vr.x - 168, 8)

func _close_game_menu() -> void:
	if _dev_pause_held:
		_dev_pause_restore = false
	else:
		sim_paused = false
	if menu_window and is_instance_valid(menu_window):
		menu_window.hide()
	if menu_page:
		menu_page.visible = true
	if settings_page:
		settings_page.visible = false
	if menu_load_page:
		menu_load_page.visible = false

func _toggle_game_menu() -> void:
	if menu_window == null:
		return
	if menu_window.visible:
		_close_game_menu()
		return
	if diplo_panel:
		diplo_panel.visible = false
	sim_paused = true
	if menu_pause_lab:
		menu_pause_lab.text = "%s发起了暂停" % _faction_label(viewer_faction)
	if menu_page:
		menu_page.visible = true
	if settings_page:
		settings_page.visible = false
	if menu_load_page:
		menu_load_page.visible = false
	menu_window.popup_centered()

func _on_game_menu_item(item_id: String) -> void:
	match item_id:
		"continue":
			_close_game_menu()
		"load":
			_show_pause_load_list()
		"save":
			var saved: Dictionary = BoardSave.save_match(_boot_layout, _match_factions_payload())
			if bool(saved.get("ok", false)):
				_chat_append("已保存「%s」" % str(saved.get("name", "")))
			else:
				_chat_append("保存存档失败")
		"main":
			_close_game_menu()
			get_tree().change_scene_to_file("res://game/main_menu.tscn")
		"settings":
			if menu_page:
				menu_page.visible = false
			if menu_load_page:
				menu_load_page.visible = false
			if settings_page:
				settings_page.visible = true
				_rebuild_settings_panel()

func _show_pause_load_list() -> void:
	if menu_load_page == null:
		return
	if menu_page:
		menu_page.visible = false
	if settings_page:
		settings_page.visible = false
	menu_load_page.visible = true
	for c in menu_load_page.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "读取存档"
	_apply_ui_font(title)
	menu_load_page.add_child(title)
	var slots: Array = BoardSave.list_slots()
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "暂无存档"
		_apply_ui_font(empty)
		menu_load_page.add_child(empty)
	for s in slots:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var b := Button.new()
		b.text = "%s  %s" % [str(s.get("name", "")), str(s.get("updated_at", ""))]
		b.custom_minimum_size = Vector2(260, 32)
		_apply_ui_font(b)
		b.pressed.connect(_load_pause_slot.bind(str(s.get("id", ""))))
		menu_load_page.add_child(b)
	var back := Button.new()
	back.text = "返回"
	_apply_ui_font(back)
	back.pressed.connect(func() -> void:
		menu_load_page.visible = false
		if menu_page:
			menu_page.visible = true
	)
	menu_load_page.add_child(back)

func _load_pause_slot(slot_id: String) -> void:
	var r: Dictionary = BoardSave.load_slot(slot_id)
	if not bool(r.get("ok", false)):
		_chat_append("读取存档失败")
		return
	_close_game_menu()
	get_tree().change_scene_to_file(str(r.get("scene", "res://game/board_test.tscn")))

func _rebuild_settings_panel() -> void:
	if settings_page == null:
		return
	for c in settings_page.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "设置"
	_apply_ui_font(title)
	settings_page.add_child(title)
	_add_settings_volume_row(settings_page, "背景音乐大小", settings_bgm_vol, "_on_settings_bgm")
	_add_settings_volume_row(settings_page, "音效大小", settings_sfx_vol, "_on_settings_sfx")
	var plate_row := HBoxContainer.new()
	settings_page.add_child(plate_row)
	var plate_lab := Label.new()
	plate_lab.text = "战场视角下时刻展示完整铭牌"
	plate_lab.custom_minimum_size = Vector2(200, 28)
	_apply_ui_font(plate_lab)
	plate_row.add_child(plate_lab)
	var plate_chk := CheckButton.new()
	plate_chk.button_pressed = settings_battle_full_plates
	plate_chk.text = "开" if settings_battle_full_plates else "关"
	_apply_ui_font(plate_chk)
	plate_chk.toggled.connect(_on_settings_full_plates)
	plate_row.add_child(plate_chk)
	_add_op_sensitivity_row(settings_page)
	var dep_row := HBoxContainer.new()
	dep_row.add_theme_constant_override("separation", 8)
	settings_page.add_child(dep_row)
	var dep_lab := Label.new()
	dep_lab.text = "切换副指挥官"
	dep_lab.custom_minimum_size = Vector2(120, 28)
	_apply_ui_font(dep_lab)
	dep_row.add_child(dep_lab)
	## Unfold inside the pause window. A PopupMenu is clipped by this sub-window.
	var cur := "yang"
	var cur_name := _deputy_display_name(cur)
	if player_deputy != null:
		cur = str(player_deputy.deputy_id)
		cur_name = _deputy_display_name(cur)
	settings_deputy_btn = Button.new()
	settings_deputy_btn.custom_minimum_size = Vector2(120, 28)
	settings_deputy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_deputy_btn.focus_mode = Control.FOCUS_NONE
	settings_deputy_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_deputy_btn.text = "%s ▼" % cur_name
	_apply_ui_font(settings_deputy_btn)
	settings_deputy_btn.pressed.connect(_toggle_settings_deputy_list)
	dep_row.add_child(settings_deputy_btn)
	settings_deputy_list = VBoxContainer.new()
	settings_deputy_list.visible = false
	settings_deputy_list.add_theme_constant_override("separation", 2)
	settings_page.add_child(settings_deputy_list)
	for spec in _deputy_choice_rows():
		var choice := Button.new()
		var mark := "（当前）" if str(spec["id"]) == cur else ""
		choice.text = "%s%s" % [str(spec["name"]), mark]
		choice.custom_minimum_size = Vector2(120, 28)
		choice.mouse_filter = Control.MOUSE_FILTER_STOP
		choice.focus_mode = Control.FOCUS_NONE
		_apply_ui_font(choice)
		choice.pressed.connect(_on_settings_deputy_picked.bind(str(spec["id"]), str(spec["name"])))
		settings_deputy_list.add_child(choice)
	var dev_btn := Button.new()
	dev_btn.text = "开发者选项"
	dev_btn.custom_minimum_size = Vector2(160, 28)
	_apply_ui_font(dev_btn)
	dev_btn.pressed.connect(_open_dev_options)
	settings_page.add_child(dev_btn)
	_mp_fog_box = CheckBox.new()
	_mp_fog_box.text = "战争迷雾"
	_mp_fog_box.button_pressed = _mp != null and _mp.fog_on
	_mp_fog_box.toggled.connect(_on_mp_fog_toggled)
	settings_page.add_child(_mp_fog_box)
	if _mp != null and _mp.active():
		var cheat_btn := Button.new()
		cheat_btn.text = "怀疑作弊"
		cheat_btn.custom_minimum_size = Vector2(160, 28)
		_apply_ui_font(cheat_btn)
		cheat_btn.pressed.connect(_toggle_mp_cheat_list)
		settings_page.add_child(cheat_btn)
		_mp_cheat_list = VBoxContainer.new()
		_mp_cheat_list.visible = false
		settings_page.add_child(_mp_cheat_list)
		_fill_mp_cheat_list()
		_mp_cheat_lab = Label.new()
		_mp_cheat_lab.text = ""
		settings_page.add_child(_mp_cheat_lab)
	var export_dbg := Button.new()
	export_dbg.text = "导出 debug 日志"
	export_dbg.custom_minimum_size = Vector2(160, 28)
	_apply_ui_font(export_dbg)
	export_dbg.pressed.connect(_on_export_debug_log)
	settings_page.add_child(export_dbg)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(80, 28)
	_apply_ui_font(back)
	back.pressed.connect(func():
		if settings_page:
			settings_page.visible = false
		if menu_page:
			menu_page.visible = true
	)
	settings_page.add_child(back)


func _open_dev_options() -> void:
	if _mp_block_dev():
		return
	var paused_before := sim_paused
	if _dev_window == null or not is_instance_valid(_dev_window):
		_dev_window = DevWindowScr.new()
		add_child(_dev_window)
	_dev_window.present()
	DebugSessionLog.append("UI", "board_root._open_dev_options", "click", {
		"control": "开发者选项",
		"surface": "match_settings",
		"deputy_row": settings_deputy_btn != null,
		"paused_before": paused_before,
		"paused_after": sim_paused,
		"dev_window_visible": _dev_window.visible,
		"runId": "grok-ui",
	})

func _on_export_debug_log() -> void:
	var res: Dictionary = DebugSessionLog.export_now()
	var dlg := AcceptDialog.new()
	dlg.title = "导出 debug 日志"
	dlg.dialog_text = DebugSessionLog.format_result(res)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
	# #region agent log
	_dbg59("EXP", "board_root._on_export_debug_log", "export", {
		"ok": bool(res.get("ok", false)), "bytes": int(res.get("bytes", 0)),
		"lines": int(res.get("lines", 0)), "path": str(res.get("path", "")),
		"runId": "pre-fix"
	})
	# #endregion

func _add_settings_volume_row(box: VBoxContainer, label_text: String, value: float, method_name: String) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(140, 28)
	_apply_ui_font(lab)
	row.add_child(lab)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(160, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(Callable(self, method_name))
	row.add_child(slider)

func _add_op_sensitivity_row(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var lab := Label.new()
	lab.text = "操作灵敏度"
	lab.custom_minimum_size = Vector2(140, 28)
	_apply_ui_font(lab)
	row.add_child(lab)
	var val := Label.new()
	val.custom_minimum_size = Vector2(48, 28)
	val.text = "%.1f" % PlayerSettings.get_op_sensitivity()
	_apply_ui_font(val)
	var slider := HSlider.new()
	slider.min_value = 0.1
	slider.max_value = 10.0
	slider.step = 0.1
	slider.value = PlayerSettings.get_op_sensitivity()
	slider.custom_minimum_size = Vector2(160, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void:
		var snapped := snappedf(v, 0.1)
		PlayerSettings.set_op_sensitivity(snapped)
		val.text = "%.1f" % snapped
	)
	row.add_child(slider)
	row.add_child(val)

func _on_settings_bgm(v: float) -> void:
	settings_bgm_vol = clampf(v, 0.0, 1.0)
	PlayerSettings.set_bgm(settings_bgm_vol)
	_apply_audio_volumes()

func _on_settings_sfx(v: float) -> void:
	settings_sfx_vol = clampf(v, 0.0, 1.0)
	PlayerSettings.set_sfx(settings_sfx_vol)
	_apply_audio_volumes()

func _on_settings_full_plates(on: bool) -> void:
	settings_battle_full_plates = on
	PlayerSettings.set_full_plates(on)
	if settings_page:
		for c in settings_page.find_children("*", "CheckButton", true, false):
			var chk := c as CheckButton
			if chk:
				chk.text = "开" if on else "关"

func _ensure_named_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx

func _apply_audio_volumes() -> void:
	var music_i := _ensure_named_bus("Music")
	var sfx_i := _ensure_named_bus("SFX")
	AudioServer.set_bus_volume_db(music_i, linear_to_db(maxf(settings_bgm_vol, 0.0001)) if settings_bgm_vol > 0.001 else -80.0)
	AudioServer.set_bus_volume_db(sfx_i, linear_to_db(maxf(settings_sfx_vol, 0.0001)) if settings_sfx_vol > 0.001 else -80.0)

func _toggle_settings_deputy_list() -> void:
	if settings_deputy_list == null:
		return
	settings_deputy_list.visible = not settings_deputy_list.visible
	if settings_deputy_btn:
		var shown := _deputy_display_name("yang")
		if player_deputy != null:
			shown = _deputy_display_name(str(player_deputy.deputy_id))
		settings_deputy_btn.text = "%s %s" % [shown, "▲" if settings_deputy_list.visible else "▼"]

func _on_settings_deputy_picked(did: String, dname: String) -> void:
	PlayerSettings.set_deputy_id(did)
	if player_deputy == null:
		return
	if not _known_deputy(did):
		return
	if str(player_deputy.deputy_id) != did:
		var old_name := player_deputy_name
		_chat_append("%s：收到指令，现和%s交接。" % [old_name, dname])
		_chat_append("%s：收到指令，现我已接手。" % dname)
		player_deputy.deputy_id = did
		player_deputy_name = dname
		if deputy_name_lab:
			deputy_name_lab.text = dname
		_refresh_deputy_face()
		_rebuild_player_deputy()
		_rebalance_deputy_resources()
	if settings_page:
		_rebuild_settings_panel.call_deferred()

func _rebuild_diplomacy_rows() -> void:
	if diplo_panel == null:
		return
	for c in diplo_panel.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	diplo_panel.add_child(box)
	for f in data.factions.get("factions", []):
		if bool(f.get("npc", false)):
			continue
		var fid := int(f.get("id", -1))
		var row := HBoxContainer.new()
		box.add_child(row)
		var lab := Label.new()
		lab.text = str(f.get("name", fid))
		lab.custom_minimum_size = Vector2(140, 28)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_ui_font(lab)
		row.add_child(lab)
		if fid == viewer_faction:
			continue
		var mark := Button.new()
		mark.name = "DiploMark"
		mark.flat = true
		mark.focus_mode = Control.FOCUS_NONE
		mark.custom_minimum_size = Vector2(32, 32)
		mark.size = Vector2(32, 32)
		mark.mouse_filter = Control.MOUSE_FILTER_STOP
		var empty := StyleBoxEmpty.new()
		mark.add_theme_stylebox_override("normal", empty)
		mark.add_theme_stylebox_override("hover", empty)
		mark.add_theme_stylebox_override("pressed", empty)
		mark.add_theme_stylebox_override("focus", empty)
		var glyph := Control.new()
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var rel := _rel_between(viewer_faction, fid)
		var offer := bool(diplo_offer.get("%d>%d" % [viewer_faction, fid], false))
		glyph.draw.connect(_draw_diplo_mark.bind(glyph, rel == "ally", offer and rel != "ally"))
		mark.add_child(glyph)
		mark.pressed.connect(_offer_alliance.bind(viewer_faction, fid))
		row.add_child(mark)
	call_deferred("_fit_diplo_panel")

func _fit_diplo_panel() -> void:
	if diplo_panel == null or not is_instance_valid(diplo_panel):
		return
	var ms := diplo_panel.get_combined_minimum_size()
	diplo_panel.size = Vector2(maxf(ms.x, 200.0), maxf(ms.y, 88.0))

func _draw_diplo_mark(mark: Control, full: bool, half: bool) -> void:
	var c := mark.size * 0.5
	var r := 8.0
	var col := Color(0.3, 0.55, 1, 1)
	if full:
		mark.draw_arc(c, r, 0.0, TAU, 24, col, 2.0, true)
	elif half:
		mark.draw_arc(c, r, PI, TAU, 16, col, 2.0, true)
	else:
		mark.draw_arc(c, r, 0.0, TAU, 24, Color(0.6, 0.6, 0.6, 0.8), 1.0, true)

func _offer_alliance(from_fac: int, to_fac: int) -> void:
	if from_fac == to_fac or data.is_npc_faction(to_fac):
		return
	var to_player := false
	for f in data.factions.get("factions", []):
		if int(f.get("id", -1)) == to_fac and not bool(f.get("npc", false)):
			to_player = true
	if not to_player:
		return
	var key := "%d>%d" % [from_fac, to_fac]
	var back := "%d>%d" % [to_fac, from_fac]
	if _rel_between(from_fac, to_fac) == "ally":
		_set_alliance(from_fac, to_fac, false)
		diplo_offer.erase(key)
		diplo_offer.erase(back)
		diplo_ai_wait.erase(key)
		diplo_ai_wait.erase(back)
		_rebuild_diplomacy_rows()
		if map:
			map.capture_dirty = true
		return
	## Human factions wait for the other player. Only ai_factions accept on a timer.
	var target_is_ai := _mp_faction_is_ai(to_fac)
	if target_is_ai:
		if diplo_ai_wait.has(key):
			return
		diplo_offer[key] = true
		diplo_ai_wait[key] = 1.0
		_rebuild_diplomacy_rows()
		return
	diplo_offer[key] = true
	if not target_is_ai and from_fac == viewer_faction:
		_mp_offer_diplo(from_fac, to_fac)
	if bool(diplo_offer.get(back, false)):
		_set_alliance(from_fac, to_fac, true)
		diplo_offer.erase(key)
		diplo_offer.erase(back)
	_rebuild_diplomacy_rows()
	if map:
		map.capture_dirty = true

func _tick_diplo_offers(delta: float) -> void:
	if diplo_ai_wait.is_empty():
		return
	var done: Array = []
	for k in diplo_ai_wait.keys():
		diplo_ai_wait[k] = float(diplo_ai_wait[k]) - delta
		if float(diplo_ai_wait[k]) <= 0.0:
			done.append(k)
	if done.is_empty():
		return
	for k2 in done:
		diplo_ai_wait.erase(k2)
		diplo_offer.erase(k2)
		var bits: PackedStringArray = str(k2).split(">")
		if bits.size() == 2:
			_set_alliance(int(bits[0]), int(bits[1]), true)
	_rebuild_diplomacy_rows()
	if map:
		map.capture_dirty = true

func _set_alliance(a: int, b: int, on: bool) -> void:
	_mp_on_diplo(a, b, on)
	var rels: Dictionary = data.diplomacy.get("relations", {})
	var ra: Dictionary = rels.get(str(a), {})
	var rb: Dictionary = rels.get(str(b), {})
	ra[str(b)] = "ally" if on else "hostile"
	rb[str(a)] = "ally" if on else "hostile"
	ra[str(a)] = "self"
	rb[str(b)] = "self"
	rels[str(a)] = ra
	rels[str(b)] = rb
	data.diplomacy["relations"] = rels

func _build_marker_layer(parent: Control) -> void:
	marker_layer = Control.new()
	marker_layer.name = "MarkerLayer"
	marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(marker_layer)

func _on_marker_button(kind: String) -> void:
	if map_markers.has(kind):
		map_markers.erase(kind)
		_marker_announce.erase(kind)
		_sync_nav_arrow()
		_refresh_marker_widgets()
		return
	var vr := get_viewport().get_visible_rect().size
	var pos := _screen_to_ground(vr * 0.5)
	## Start at about one third of the screen width on the board, whatever the zoom.
	var span := _screen_to_ground(vr * 0.5 + Vector2(vr.x / 6.0, 0.0)).distance_to(
		_screen_to_ground(vr * 0.5 - Vector2(vr.x / 6.0, 0.0)))
	var base_w := MARKER_ARROW_HALF * 2.0 if kind == "arrow" else MARKER_ICON_W
	var sc0 := clampf(span / base_w, MARKER_SCALE_MIN, MARKER_SCALE_MAX)
	map_markers[kind] = {"pos": pos, "yaw": 0.0, "scale": sc0}
	_marker_handles_on = true
	_marker_resize_logged.erase(kind)
	_sync_marker_segment(kind)
	_sync_nav_arrow()
	_refresh_marker_widgets()
	_announce_marker_confirm(str(kind))

func _sync_marker_segment(kind: String) -> void:
	if not map_markers.has(kind):
		return
	var m: Dictionary = map_markers[kind]
	var pos: Vector3 = m["pos"]
	var yaw: float = float(m.get("yaw", 0.0))
	var axis := Vector3(cos(yaw), 0.0, sin(yaw))
	var half := MARKER_ARROW_HALF * float(m.get("scale", 1.0))
	m["a"] = pos - axis * half
	m["b"] = pos + axis * half
	map_markers[kind] = m

func _sync_nav_arrow() -> void:
	if map_markers.has("arrow"):
		var m: Dictionary = map_markers["arrow"]
		BoardPlayerNav.corridor_on = true
		BoardPlayerNav.corridor_a = m.get("a", Vector3.ZERO)
		BoardPlayerNav.corridor_b = m.get("b", Vector3.ZERO)
	else:
		BoardPlayerNav.corridor_on = false

func _marker_board_root() -> Node3D:
	if _marker_board == null or not is_instance_valid(_marker_board):
		_marker_board = Node3D.new()
		_marker_board.name = "MarkerBoard"
		add_child(_marker_board)
	return _marker_board

func _marker_world_size(kind: String) -> Vector2:
	## Board-plane quad: x along the marker axis, y is the XZ depth. Arrow width = corridor segment.
	var m: Dictionary = map_markers.get(kind, {})
	var sc := float(m.get("scale", 1.0))
	var w := (MARKER_ARROW_HALF * 2.0 if kind == "arrow" else MARKER_ICON_W) * sc
	var tex := _marker_tex(kind)
	var aspect := 0.5
	if tex:
		aspect = float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)
	return Vector2(w, w * aspect)

func _new_marker_handle(k: String, role: String, glyph: String) -> Button:
	var b := Button.new()
	b.name = "%s_%s" % [role, k]
	b.text = glyph
	b.custom_minimum_size = Vector2(22, 22)
	b.size = Vector2(22, 22)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.set_meta("kind", k)
	b.set_meta("role", role)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(1, 1, 1, 0.94)
	plate.set_corner_radius_all(3)
	plate.content_margin_left = 2
	plate.content_margin_right = 2
	plate.content_margin_top = 1
	plate.content_margin_bottom = 1
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, plate)
	b.add_theme_color_override("font_color", Color(0.1, 0.1, 0.12))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.1, 0.12))
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.12))
	return b

func _refresh_marker_widgets() -> void:
	if marker_layer == null:
		return
	for c in marker_layer.get_children():
		c.queue_free()
	var board := _marker_board_root()
	for c3 in board.get_children():
		c3.queue_free()
	for kind in map_markers.keys():
		var k := str(kind)
		var quad := MeshInstance3D.new()
		quad.name = "Mk_" + k
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE
		quad.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		## Under the ring (y 0.02) and territory (y 0.015). Draw first, write no depth.
		mat.render_priority = -8
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.albedo_texture = _marker_tex(k)
		quad.material_override = mat
		quad.set_meta("kind", k)
		board.add_child(quad)
		# #region agent log
		_dbg59("MKR", "board_root._refresh_marker_widgets", "quad_layer", {
			"kind": k, "y": MARKER_BOARD_Y, "priority": -8, "depth_draw": "disabled", "runId": "post-fix"
		})
		# #endregion
		var rotor := _new_marker_handle(k, "rot", "↻")
		rotor.gui_input.connect(_on_marker_rotate.bind(k))
		marker_layer.add_child(rotor)
		var sizer := _new_marker_handle(k, "siz", "⤡")
		sizer.gui_input.connect(_on_marker_resize.bind(k))
		marker_layer.add_child(sizer)

func _marker_tex(kind: String) -> Texture2D:
	if _marker_tex_cache.has(kind):
		return _marker_tex_cache[kind]
	var tex_path := ""
	match kind:
		"arrow":
			tex_path = "res://assets/ui/markers/arrow.svg"
		"target":
			tex_path = "res://assets/ui/markers/target.svg"
		"trench":
			tex_path = "res://assets/ui/markers/fortified_arc.svg"
	var tex: Texture2D = null
	if tex_path != "" and FileAccess.file_exists(tex_path):
		var img := Image.new()
		var err := img.load_svg_from_buffer(FileAccess.get_file_as_bytes(tex_path), 2.0)
		if err == OK and _whiten_marker_image(img):
			tex = ImageTexture.create_from_image(img)
	if tex == null and ResourceLoader.exists(tex_path):
		tex = load(tex_path) as Texture2D
	_marker_tex_cache[kind] = tex
	return tex

func _whiten_marker_image(img: Image) -> bool:
	## SVG ink is dark on transparency; an opaque white plate is dropped. Strokes render white.
	img.convert(Image.FORMAT_RGBA8)
	var any := false
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.04:
				continue
			if c.r > 0.82 and c.g > 0.82 and c.b > 0.82 and c.a > 0.92:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			img.set_pixel(x, y, Color(1, 1, 1, c.a))
			any = true
	return any

func _markers_visible() -> bool:
	## Battlefield, tactical, and starmap all draw placed icons.
	return cam != null and cam.cam != null

func _marker_axes(m: Dictionary) -> Array:
	var yaw := float(m.get("yaw", 0.0))
	return [Vector3(cos(yaw), 0.0, sin(yaw)), Vector3(-sin(yaw), 0.0, cos(yaw))]

func _tick_marker_widgets() -> void:
	if marker_layer == null:
		return
	var markers_on := _markers_visible()
	marker_layer.visible = markers_on
	var board := _marker_board_root()
	board.visible = markers_on
	if not markers_on:
		return
	for q in board.get_children():
		var kind := str(q.get_meta("kind", ""))
		if not map_markers.has(kind):
			continue
		var m: Dictionary = map_markers[kind]
		var sz := _marker_world_size(kind)
		(q as MeshInstance3D).transform = Transform3D(
			Basis(Vector3.UP, -float(m.get("yaw", 0.0))) * Basis.from_scale(Vector3(sz.x, 1.0, sz.y)),
			(m["pos"] as Vector3) + Vector3(0.0, MARKER_BOARD_Y, 0.0)
		)
	for w in marker_layer.get_children():
		var kind2 := str(w.get_meta("kind", ""))
		if not map_markers.has(kind2):
			continue
		var m2: Dictionary = map_markers[kind2]
		var sz2 := _marker_world_size(kind2)
		var ax: Array = _marker_axes(m2)
		var pos: Vector3 = m2["pos"]
		var anchor := pos + (ax[0] as Vector3) * (sz2.x * 0.5) + (ax[1] as Vector3) * (sz2.y * 0.5)
		if str(w.get_meta("role", "")) == "rot":
			anchor = pos + (ax[0] as Vector3) * (sz2.x * 0.5 + 4.0)
		if not _marker_handles_on or cam.cam.is_position_behind(anchor):
			w.visible = false
			continue
		w.visible = true
		w.position = cam.cam.unproject_position(anchor) - (w as Control).size * 0.5
		# #region agent log
		if not w.has_meta("dbg_logged"):
			w.set_meta("dbg_logged", true)
			_dbg59("MKR", "board_root._tick_marker_widgets", "handle", {
				"name": str(w.name), "pos": str(w.position), "size": str((w as Control).size),
				"layer_vis": marker_layer.is_visible_in_tree(), "layer_size": str(marker_layer.size),
				"parent": str(marker_layer.get_parent().name), "runId": "post-fix"
			})
		# #endregion
	## Confirm place after drag/rotate (LMB up); dedupe inside _announce_marker_confirm.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		for kind3 in map_markers.keys():
			_announce_marker_confirm(str(kind3))

func _marker_hit_kind(screen: Vector2) -> String:
	## Ray to the board plane; inside the quad rectangle in its own frame.
	if cam == null or cam.cam == null:
		return ""
	var g := _screen_to_ground(screen)
	for kind in map_markers.keys():
		var k := str(kind)
		var m: Dictionary = map_markers[k]
		var sz := _marker_world_size(k)
		var ax: Array = _marker_axes(m)
		var rel: Vector3 = g - (m["pos"] as Vector3)
		if absf(rel.dot(ax[0])) <= sz.x * 0.5 and absf(rel.dot(ax[1])) <= sz.y * 0.5:
			return k
	return ""

func _marker_drag_motion(screen: Vector2) -> void:
	if _marker_drag_kind == "" or not map_markers.has(_marker_drag_kind):
		return
	var m: Dictionary = map_markers[_marker_drag_kind]
	var g := _screen_to_ground(screen)
	m["pos"] = (m["pos"] as Vector3) + (g - _marker_drag_prev)
	_marker_drag_prev = g
	map_markers[_marker_drag_kind] = m
	_sync_marker_segment(_marker_drag_kind)
	_sync_nav_arrow()

func _on_marker_rotate(ev: InputEvent, kind: String) -> void:
	if not (ev is InputEventMouseMotion):
		return
	var mm := ev as InputEventMouseMotion
	if not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	if not map_markers.has(kind) or cam == null or cam.cam == null:
		return
	var m: Dictionary = map_markers[kind]
	var rel := _screen_to_ground(mm.global_position) - (m["pos"] as Vector3)
	if Vector2(rel.x, rel.z).length() < 0.5:
		return
	## Axis (cos yaw, 0, sin yaw) points at the board point under the cursor.
	m["yaw"] = atan2(rel.z, rel.x)
	map_markers[kind] = m
	_sync_marker_segment(kind)
	_sync_nav_arrow()

func _on_marker_resize(ev: InputEvent, kind: String) -> void:
	if not (ev is InputEventMouseMotion):
		return
	var mm := ev as InputEventMouseMotion
	if not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	if not map_markers.has(kind) or cam == null or cam.cam == null:
		return
	var m: Dictionary = map_markers[kind]
	var rel := _screen_to_ground(mm.global_position) - (m["pos"] as Vector3)
	var ax: Array = _marker_axes(m)
	var half := _marker_world_size(kind) * 0.5 / maxf(float(m.get("scale", 1.0)), 0.001)
	var sc := clampf(maxf(absf(rel.dot(ax[0])) / half.x, absf(rel.dot(ax[1])) / half.y), MARKER_SCALE_MIN, MARKER_SCALE_MAX)
	m["scale"] = sc
	map_markers[kind] = m
	_sync_marker_segment(kind)
	_sync_nav_arrow()
	# #region agent log
	if not _marker_resize_logged.has(kind):
		_marker_resize_logged[kind] = true
		_dbg59("MKR", "board_root._on_marker_resize", "resize", {"kind": kind, "scale": sc, "runId": "post-fix"})
	# #endregion

func _screen_to_ground(screen: Vector2) -> Vector3:
	if cam == null or cam.cam == null:
		return Vector3.ZERO
	var origin := cam.cam.project_ray_origin(screen)
	var dir := cam.cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3(origin.x, 0.0, origin.z)
	var t := -origin.y / dir.y
	var hit := origin + dir * t
	return Vector3(hit.x, 0.0, hit.z)

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
	## UI_AND_SHELL §2.3: portrait fills the whole frame; ship art sits lower-middle over it.
	var pilot_face = TextureRect.new()
	pilot_face.name = "PilotFace"
	pilot_face.position = Vector2(2, 2)
	pilot_face.size = Vector2(48, 48)
	pilot_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pilot_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pilot_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mid := str(p.get("member_id", ""))
	var mem: Dictionary = data.member_by_id(mid) if data != null and mid != "" else {}
	var pkey := str(mem.get("portrait", "")).strip_edges()
	pilot_face.texture = MemberTableScr.load_portrait(pkey, PackedStringArray([pid, mid]))
	frame.add_child(pilot_face)
	# Ship art: lower-middle of the frame, covers a bit under half of the portrait.
	var portrait = TextureRect.new()
	portrait.name = "ShipArt"
	var art_h = 52.0 * 0.46 * 1.2
	var art_w = 40.0 * 1.2
	portrait.position = Vector2((52.0 - art_w) * 0.5, 52.0 - art_h + 2.0)
	portrait.size = Vector2(art_w, art_h)
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
	## Group number: single-digit corner badge on ship portrait (not a text line).
	var grp_badge = Label.new()
	grp_badge.name = "GroupBadge"
	grp_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grp_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grp_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grp_badge.custom_minimum_size = Vector2(16, 16)
	grp_badge.size = Vector2(16, 16)
	grp_badge.position = Vector2(52 - 17, 1.0 - 6.0) ## half a glyph above the yellow box
	grp_badge.add_theme_font_size_override("font_size", 12)
	grp_badge.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1, 1))
	grp_badge.add_theme_color_override("font_outline_color", Color(0.98, 0.88, 0.35, 1))
	grp_badge.add_theme_constant_override("outline_size", 4)
	_apply_ui_font(grp_badge)
	var grp_bg = Panel.new()
	grp_bg.name = "GroupBadgeBg"
	grp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grp_bg.custom_minimum_size = Vector2(16, 16)
	grp_bg.size = Vector2(16, 16)
	grp_bg.position = Vector2(52 - 17, 1)
	var grp_sb = StyleBoxFlat.new()
	grp_sb.bg_color = Color(0.95, 0.82, 0.28, 0.95)
	grp_sb.set_corner_radius_all(3)
	grp_sb.set_border_width_all(1)
	grp_sb.border_color = Color(0.15, 0.12, 0.05, 0.9)
	grp_bg.add_theme_stylebox_override("panel", grp_sb)
	frame.add_child(grp_bg)
	frame.add_child(grp_badge)
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
	var place_mod := Color(0.75, 0.8, 0.88)
	var l_sys := Label.new()
	l_sys.name = "SysLab"
	l_sys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_sys.modulate = place_mod
	_apply_ui_font(l_sys)
	vb.add_child(l_sys)
	var l_home := Label.new()
	l_home.name = "HomeLab"
	l_home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_home.modulate = place_mod
	_apply_ui_font(l_home)
	vb.add_child(l_home)
	var l_cur := Label.new()
	l_cur.name = "CurLab"
	l_cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_cur.modulate = place_mod
	_apply_ui_font(l_cur)
	vb.add_child(l_cur)
	var res_n = _pilot_resource_count(str(p["id"])) if map != null else 0
	if res_n > 0:
		var l_res := Label.new()
		l_res.name = "ResLab"
		l_res.text = "资源点：R%d" % res_n
		l_res.modulate = place_mod
		l_res.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_ui_font(l_res)
		vb.add_child(l_res)
	hb.add_child(vb)
	row.set_meta("pilot", pid)
	_refresh_pilot_row_places(row, p)
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
	for built0 in pilots_sys.tick_build(pilots, 0.05, map):
		if typeof(built0) == TYPE_DICTIONARY:
			_note_match_built(int(built0.get("faction", -1)))
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
	if _auto_launch_locked:
		auto_launch_enabled = true
		if auto_launch_btn:
			auto_launch_btn.set_pressed_no_signal(true)
		_refresh_auto_launch_btn()
		return
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

func _pilot_commanded_by_player_deputy(p: Dictionary) -> bool:
	if deputy_group < 0 or player_deputy == null:
		return false
	if int(p.get("faction", -1)) != viewer_faction:
		return false
	return int(p.get("ctrl_group", -1)) == deputy_group

func _pilot_current_ship_id(p: Dictionary) -> String:
	var u = _unit_by_id(str(p.get("unit_id", "")))
	if not u.is_empty() and u.get("alive", false):
		var sid := str(u.get("ship_id", ""))
		if sid != "":
			return sid
	var last := str(p.get("last_ship_id", ""))
	if last != "":
		return last
	return str(p.get("default_ship", ""))

func _yang_build_ship(p: Dictionary) -> String:
	## Largest hull whose bar can move. Keep the current hull when it is already that tonnage.
	var current := _pilot_current_ship_id(p)
	var held := BoardResourceAssign.pilot_held_count(map, str(p.get("id", "")))
	var best := ""
	var best_w := -1
	if data == null:
		return current
	for sid in data.ships.keys():
		var def: Dictionary = data.ship_def(str(sid))
		if not _ship_player_buildable(def) or not _pilot_has_ship(p, str(sid)):
			continue
		var ton := str(def.get("tonnage", ""))
		if ton == "" or held < BoardResourceAssign.unlock_need(data, ton):
			continue
		var w := BoardTypes.tonnage_weight(ton)
		if w > best_w:
			best_w = w
			best = str(sid)
		elif w == best_w and str(sid) == current:
			best = current
	if current != "" and best_w >= 0:
		var cdef: Dictionary = data.ship_def(current)
		var cton := str(cdef.get("tonnage", ""))
		if cton != "" and not bool(cdef.get("npc", false)) and held >= BoardResourceAssign.unlock_need(data, cton):
			if BoardTypes.tonnage_weight(cton) == best_w:
				return current
	if best != "":
		return best
	return current

func _deputy_set_build(p: Dictionary, ship_id: String) -> void:
	if ship_id == "" or data == null:
		return
	var def: Dictionary = data.ship_def(ship_id)
	var ton := str(def.get("tonnage", ""))
	if ton == "":
		return
	for ton2 in p["auto_build"].keys():
		var want := ship_id if str(ton2) == ton else ""
		if str(p["auto_build"].get(ton2, "")) != want:
			pilots_sys.set_auto(p, str(ton2), want)

func _deputy_pick_launch_ship(p: Dictionary, target: String) -> String:
	var counts: Dictionary = pilots_sys.storage_count_by_model(p)
	if counts.is_empty():
		return ""
	if target != "" and int(counts.get(target, 0)) > 0:
		return target
	var best := ""
	var best_w := -1
	for sid in counts.keys():
		var w := BoardTypes.tonnage_weight(data.ship_def(str(sid)).get("tonnage", "destroyer"))
		if w > best_w:
			best_w = w
			best = str(sid)
	return best

func _pilot_in_deputy_role(ctrl: BoardAiController, p: Dictionary, role: String) -> bool:
	var pid := str(p.get("id", ""))
	var uid := str(p.get("unit_id", ""))
	for f in ctrl.fleets:
		if str(f.get("role", "")) != role:
			continue
		if (f.get("pilot_ids", []) as Array).has(pid):
			return true
		if uid != "" and (f.get("members", []) as Array).has(uid):
			return true
	return false

func _deputy_build_ship(ctrl: BoardAiController, p: Dictionary) -> String:
	var req := str(p.get("deputy_req_ship", ""))
	if req != "":
		return req
	if str(ctrl.deputy_id) == "bei" and _pilot_in_deputy_role(ctrl, p, "raid"):
		return "gila_cc2"
	if str(ctrl.deputy_id) == "chuang":
		return _chuang_build_ship(p)
	return _yang_build_ship(p)

func _pilot_has_hull_ready(p: Dictionary) -> bool:
	var u = _unit_by_id(str(p.get("unit_id", "")))
	if not u.is_empty() and u.get("alive", false):
		return true
	var counts: Dictionary = pilots_sys.storage_count_by_model(p)
	for sid in counts.keys():
		if int(counts[sid]) > 0:
			return true
	return false

func _fleet_wave_ready(f: Dictionary) -> bool:
	for pid in f.get("wait_pilots", []):
		var p: Dictionary = _pilot_by_id(str(pid))
		if p.is_empty():
			continue
		if not _pilot_has_hull_ready(p):
			return false
	return true

func _deputy_wave_blocked(ctrl: BoardAiController, p: Dictionary) -> bool:
	if str(ctrl.deputy_id) != "yang" and str(ctrl.deputy_id) != "six":
		return false
	var pid := str(p.get("id", ""))
	for f in ctrl.fleets:
		if not bool(f.get("wait_out", false)):
			continue
		if not (f.get("wait_pilots", []) as Array).has(pid):
			continue
		if not _fleet_wave_ready(f):
			return true
		f["wait_out"] = false
		f["wait_pilots"] = []
		return false
	return false

func _deputy_arm_pilot(ctrl: BoardAiController, p: Dictionary) -> bool:
	var ship_id := str(p.get("deputy_req_ship", ""))
	var designated := ship_id != ""
	if not designated:
		ship_id = _deputy_build_ship(ctrl, p)
		designated = str(ctrl.deputy_id) == "bei" and _pilot_in_deputy_role(ctrl, p, "raid")
	# #region agent log
	if str(p.get("_dbg_build", "")) != ship_id:
		p["_dbg_build"] = ship_id
		_dbg59("DSG", "board_root._deputy_arm_pilot", "build_pick", {
			"deputy": str(ctrl.deputy_id), "pilot": str(p.get("id", "")), "name": str(p.get("name", "")),
			"ship": ship_id, "designated": designated,
			"held": BoardResourceAssign.pilot_held_count(map, str(p.get("id", ""))), "runId": "post-fix"
		})
	# #endregion
	_deputy_set_build(p, ship_id)
	if _deputy_wave_blocked(ctrl, p):
		return false
	if str(p.get("unit_id", "")) != "":
		return false
	if designated and int(pilots_sys.storage_count_by_model(p).get(ship_id, 0)) <= 0 \
			and _pilot_can_build_ton(p, str(data.ship_def(ship_id).get("tonnage", ""))):
		## Designated pilot waits for the link hull while its bar can move.
		return false
	var launch_id := _deputy_pick_launch_ship(p, ship_id)
	if launch_id == "":
		return false
	_launch_pilot(p, launch_id)
	return str(p.get("unit_id", "")) != ""

func _release_ship_from_deputy_fleets(u: Dictionary) -> void:
	if u.is_empty() or bool(u.get("garrison", false)):
		return
	var uid := str(u.get("id", ""))
	var w := BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
	var touched := false
	if player_deputy != null and int(u.get("faction", -1)) == viewer_faction:
		if player_deputy.remove_member(uid, w):
			touched = true
	var fac := int(u.get("faction", -1))
	if faction_ai.has(fac):
		var ctrl: BoardAiController = faction_ai[fac]
		if ctrl.remove_member(uid, w):
			touched = true
	if touched and fac == viewer_faction:
		_refresh_deputy_fleet_ui()

func _slot_launched_ship(u: Dictionary) -> void:
	if u.is_empty() or bool(u.get("garrison", false)):
		return
	var fac := int(u.get("faction", -1))
	if fac == viewer_faction:
		if player_deputy == null or deputy_group < 0:
			return
		if int(u.get("ctrl_group", -1)) != deputy_group:
			return
		if player_deputy.fleets.is_empty():
			_rebuild_player_deputy()
			return
		_accept_into_deputy(player_deputy, u)
		_refresh_deputy_fleet_ui()
	elif faction_ai.has(fac):
		var ctrl: BoardAiController = faction_ai[fac]
		if ctrl.fleets.is_empty():
			ctrl.setup_fleets(_roster_entries(_faction_pilots(fac)))
			return
		_accept_into_deputy(ctrl, u)

func _accept_into_deputy(ctrl: BoardAiController, u: Dictionary) -> void:
	## Designated pilot returns to its own fleet (指挥接口 指定驾驶); others fill the lowest share.
	var p: Dictionary = _pilot_by_id(str(u.get("pilot_id", "")))
	var rf := int(p.get("deputy_req_fleet", -1)) if not p.is_empty() else -1
	if rf >= 0 and ctrl.accept_ship_into(u, rf):
		# #region agent log
		_dbg59("DSG", "board_root._accept_into_deputy", "return_to_fleet", {
			"pilot": str(p.get("id", "")), "fleet": rf, "ship": str(u.get("ship_id", "")), "runId": "post-fix"
		})
		# #endregion
		return
	ctrl.accept_ship(u)

func _tick_deputy_industry() -> void:
	_tick_deputy_designations()
	if deputy_group >= 0 and player_deputy != null:
		for p in _commanded_pilots(deputy_group):
			_deputy_arm_pilot(player_deputy, p)
	for fid in faction_ai.keys():
		if _faction_out.has(int(fid)):
			continue
		var ctrl: BoardAiController = faction_ai[fid]
		for p in pilots:
			if int(p.get("faction", -1)) != int(fid):
				continue
			_deputy_arm_pilot(ctrl, p)

func _apply_rally_after_auto_launch(p: Dictionary) -> void:
	var fac := int(p.get("faction", -1))
	if not rally_by_fac.has(fac):
		return
	var r: Dictionary = rally_by_fac[fac]
	var rs := str(r.get("sys", ""))
	var rc := int(r.get("cell", -1))
	if rs == "" or rc < 0:
		return
	var u: Dictionary = _unit_by_id(str(p.get("unit_id", "")))
	if u.is_empty() or not bool(u.get("alive", false)):
		return
	if str(u.get("sys", "")) == rs and int(u.get("cell", -1)) == rc:
		return
	_queue_unit_move(u, rs, rc)


func _tick_auto_launch() -> void:
	if not auto_launch_enabled:
		return
	for p in pilots:
		if int(p.get("faction", 0)) != viewer_faction:
			continue
		if _pilot_commanded_by_player_deputy(p):
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
		_apply_rally_after_auto_launch(p)
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
	left_col.size = Vector2(360, maxf(vh - 72.0, 200.0))
	_layout_bottom_bar()
	_layout_deputy_panel()
	_layout_diplomacy()
	if left_scroll:
		left_scroll.custom_minimum_size = Vector2(360, 120)
		left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_mouse_hint()

func _right_col_backdrop() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.08)
	sb.set_border_width_all(0)
	sb.set_content_margin_all(4)
	return sb

func _build_zoom_buttons(layer: Control) -> void:
	## Beside the tactical icon field, on the right column's left edge.
	var col := VBoxContainer.new()
	col.name = "TacticalZoom"
	col.mouse_filter = Control.MOUSE_FILTER_STOP
	col.z_index = 60
	col.add_theme_constant_override("separation", 6)
	var up := Button.new()
	up.name = "ZoomIn"
	up.text = "上"
	up.custom_minimum_size = Vector2(48, 48)
	up.mouse_filter = Control.MOUSE_FILTER_STOP
	up.pressed.connect(func() -> void:
		if cam:
			cam.zoom_by_factor(0.9)
	)
	var down := Button.new()
	down.name = "ZoomOut"
	down.text = "下"
	down.custom_minimum_size = Vector2(48, 48)
	down.mouse_filter = Control.MOUSE_FILTER_STOP
	down.pressed.connect(func() -> void:
		if cam:
			cam.zoom_by_factor(1.1)
	)
	_apply_ui_font(up)
	_apply_ui_font(down)
	col.add_child(up)
	col.add_child(down)
	layer.add_child(col)
	_zoom_col = col


func _layout_right_col() -> void:
	var layer = hud.get_child(0) if hud else null
	if layer == null:
		return
	var right_col = layer.find_child("RightCol", true, false) as Control
	if right_col == null:
		return
	var vr = get_viewport().get_visible_rect().size
	## Stay clear of the diplomacy button (top) and the bottom key bar.
	right_col.position = Vector2(vr.x - 316.0, 48.0)
	right_col.size = Vector2(300.0, maxf(vr.y - 48.0 - 60.0, 200.0))
	if _zoom_col:
		_zoom_col.position = Vector2(right_col.position.x - 56.0, right_col.position.y + right_col.size.y * 0.5 - 51.0)
	_layout_bottom_bar()

func _ensure_br_window() -> void:
	if br_window != null and is_instance_valid(br_window):
		return
	br_window = Window.new()
	br_window.title = "战报"
	br_window.size = Vector2i(980, 600)
	br_window.visible = false
	br_window.close_requested.connect(func():
		if br_window != null and is_instance_valid(br_window):
			br_window.hide()
	)
	## Window must live under CanvasLayer/Control tree — parenting to Node3D
	## then popup_centered can free/invalid the window and crash on reopen.
	var host: Node = self
	if hud != null and is_instance_valid(hud):
		host = hud
	host.add_child(br_window)
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
	if br_window == null or not is_instance_valid(br_window):
		return null
	return br_window.find_child("BrBodyVBox", true, false) as VBoxContainer

func _br_clear_body(vbox: VBoxContainer) -> void:
	if vbox == null:
		return
	var kids := vbox.get_children()
	for c in kids:
		vbox.remove_child(c)
		c.free()

func _br_compact_rows(rows: Array) -> Array:
	## Collapse per-tick duplicate rows (blank pilot id) so opening the window does not build thousands of controls.
	var by_uid: Dictionary = {}
	var order: Array = []
	for row in rows:
		if not (row is Dictionary):
			continue
		var src: Dictionary = row
		var uid := str(src.get("unit_id", ""))
		if uid == "":
			uid = str(src.get("pilot_id", ""))
		if uid == "":
			continue
		if not by_uid.has(uid):
			by_uid[uid] = src.duplicate(true)
			order.append(uid)
			continue
		var acc: Dictionary = by_uid[uid]
		acc["max_loss_dealt"] = float(acc.get("max_loss_dealt", 0.0)) + float(src.get("max_loss_dealt", 0.0))
		acc["max_loss_taken"] = float(acc.get("max_loss_taken", 0.0)) + float(src.get("max_loss_taken", 0.0))
		acc["kills"] = int(acc.get("kills", 0)) + int(src.get("kills", 0))
		acc["stay_s"] = maxf(float(acc.get("stay_s", 0.0)), float(src.get("stay_s", 0.0)))
		if bool(src.get("destroyed", false)):
			acc["destroyed"] = true
	var out: Array = []
	for uid2 in order:
		out.append(by_uid[uid2])
	return out

func _on_br_sort_header(col: String, report_id: String) -> void:
	_br_sort_col = col
	_br_sort_report = report_id
	call_deferred("_open_br_report", report_id)

func _br_sort_rows(rows: Array, col: String) -> Array:
	if col == "":
		return rows
	var out := rows.duplicate()
	out.sort_custom(func(a, b):
		return _br_row_rank_before(a, b, col)
	)
	return out

func _br_row_rank_before(a: Dictionary, b: Dictionary, col: String) -> bool:
	var av := _br_col_number(a, col)
	var bv := _br_col_number(b, col)
	if col == "pilot" or col == "ship":
		var as_ := str(a.get("pilot_name" if col == "pilot" else "ship_name", ""))
		var bs_ := str(b.get("pilot_name" if col == "pilot" else "ship_name", ""))
		if as_ != bs_:
			return as_ > bs_
	elif av != bv:
		return av > bv
	return str(a.get("pilot_name", "")) < str(b.get("pilot_name", ""))

func _br_col_number(row: Dictionary, col: String) -> float:
	match col:
		"ton":
			return float(BoardTypes.tonnage_weight(str(row.get("tonnage", "destroyer"))))
		"dealt":
			return float(row.get("max_loss_dealt", 0.0))
		"taken":
			return float(row.get("max_loss_taken", 0.0))
		"kills":
			return float(int(row.get("kills", 0)))
		"stay":
			return float(row.get("stay_s", 0.0))
		_:
			return 0.0

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
	if _br_sort_report != report_id:
		_br_sort_col = ""
	_br_sort_report = report_id
	_ensure_br_window()
	var rep: Dictionary = {}
	for r in br_tracker.closed:
		if str(r.get("id", "")) == report_id:
			rep = r
			break
	if rep.is_empty():
		return
	var vbox := _br_body_vbox()
	if vbox == null or br_window == null or not is_instance_valid(br_window):
		return
	_br_clear_body(vbox)
	var st = br_tracker.format_clock(float(rep.get("start_t", 0)))
	var et = br_tracker.format_clock(float(rep.get("end_t", 0)))
	var head_row = HBoxContainer.new()
	head_row.alignment = BoxContainer.ALIGNMENT_CENTER
	head_row.add_theme_constant_override("separation", 10)
	var mine_who := _join_fac_names(rep.get("mine_names", []))
	var foe_who := _join_fac_names(rep.get("foe_names", []))
	var left_h = Label.new()
	left_h.text = "我方 %s\n%d舰 · 损失 %d舰 · 吨位%d" % [
		mine_who,
		int(rep.get("mine_ships", 0)), int(rep.get("mine_lost", 0)), int(rep.get("mine_ton", 0))
	]
	left_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	left_h.add_theme_font_size_override("font_size", 16)
	_apply_ui_font(left_h)
	var vs_h = Label.new()
	vs_h.text = "vs"
	vs_h.add_theme_font_size_override("font_size", 28)
	vs_h.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
	_apply_ui_font(vs_h)
	var right_h = Label.new()
	right_h.text = "敌方 %s\n%d舰 · 损失 %d舰 · 吨位%d" % [
		foe_who,
		int(rep.get("foe_ships", 0)), int(rep.get("foe_lost", 0)), int(rep.get("foe_ton", 0))
	]
	right_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	var headers := [
		{"t": "参战驾驶员", "k": "pilot"},
		{"t": "吨位", "k": "ton"},
		{"t": "驾驶舰船", "k": "ship"},
		{"t": "造成上限降低", "k": "dealt"},
		{"t": "受到上限降低", "k": "taken"},
		{"t": "击毁舰船数", "k": "kills"},
		{"t": "星系内停留时长", "k": "stay"},
	]
	for hspec in headers:
		var spec: Dictionary = hspec
		var hl := Button.new()
		var title := str(spec["t"])
		if _br_sort_col == str(spec["k"]):
			title += " ↓"
		hl.text = title
		hl.flat = true
		hl.focus_mode = Control.FOCUS_NONE
		hl.mouse_filter = Control.MOUSE_FILTER_STOP
		hl.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hl.add_theme_font_size_override("font_size", 13)
		_apply_ui_font(hl)
		hl.pressed.connect(_on_br_sort_header.bind(str(spec["k"]), report_id))
		grid.add_child(hl)
	var row_n := 0
	var rows: Array = _br_sort_rows(_br_compact_rows(rep.get("rows", [])), _br_sort_col)
	for row in rows:
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

func _unit_sync_on(u: Dictionary) -> bool:
	## SHIPS §10: per-unit state, default 关.
	return bool(u.get("sync_move", false))

func _movers_all_sync(movers: Array) -> bool:
	if movers.is_empty():
		return false
	for m in movers:
		if not _unit_sync_on(m):
			return false
	return true

func _selection_sync_state() -> String:
	## "on" | "off" | "mixed" | "none" over selected own alive units.
	var on_n := 0
	var off_n := 0
	for id in selection:
		var un = _unit_by_id(str(id))
		if un.is_empty() or int(un.get("faction", -1)) != viewer_faction or not un.get("alive", false):
			continue
		if _unit_sync_on(un):
			on_n += 1
		else:
			off_n += 1
	if on_n + off_n == 0:
		return "none"
	if on_n > 0 and off_n > 0:
		return "mixed"
	return "on" if on_n > 0 else "off"

func _on_sync_move_toggled(on: bool) -> void:
	## Button sets the state of every selected own unit (UI_AND_SHELL §2 item 4).
	var state := _selection_sync_state()
	if state == "none":
		_refresh_sync_move_btn()
		return
	var want: bool = on if state == "mixed" else (state != "on")
	var n := 0
	for id in selection:
		var un = _unit_by_id(str(id))
		if un.is_empty() or int(un.get("faction", -1)) != viewer_faction or not un.get("alive", false):
			continue
		un["sync_move"] = want
		if not want and un.has("sync_gid"):
			un.erase("sync_gid")
		n += 1
	sync_move_enabled = want
	_refresh_sync_move_btn()
	# #region agent log
	_dbg59("SYNC", "board_root.sync_move", "toggle_selected", {"want": want, "n": n, "prev": state, "runId": "sync-unit"})
	# #endregion

func _refresh_sync_move_btn() -> void:
	if sync_move_btn == null:
		return
	## UI_AND_SHELL §2.1: label = state of the selected set.
	var state := _selection_sync_state()
	var txt := "关"
	match state:
		"on":
			txt = "开"
		"mixed":
			txt = "混"
		"none":
			txt = "未选中"
	sync_move_btn.text = "单位同步移动（%s）" % txt
	if sync_move_btn.toggle_mode:
		sync_move_btn.set_pressed_no_signal(state == "on")

func _refresh_left_state_toggles() -> void:
	_refresh_auto_launch_btn()
	_refresh_sync_move_btn()

func _clear_all_sync_gids() -> void:
	for o in units:
		if o.has("sync_gid"):
			o.erase("sync_gid")

func _ensure_trail_nozzles(u: Dictionary) -> Array:
	var locals: Array = u.get("trail_nozzles", [])
	if not locals.is_empty():
		return locals
	if not unit_nodes.has(u["id"]):
		return locals
	var n: Node3D = unit_nodes[u["id"]]
	var model := n.get_node_or_null("Model") as Node3D
	if model == null:
		return locals
	var model_key := str(model.get_meta("model_key", ""))
	if model_key == "":
		var def: Dictionary = data.ship_def(str(u.get("ship_id", "")))
		model_key = str(def.get("model", u.get("ship_id", "")))
	locals = SHIP_ART.engine_nozzle_locals(model_key, model)
	u["trail_nozzles"] = locals
	return locals

func _trail_heads_world(u: Dictionary) -> Array:
	var heads: Array = []
	if unit_nodes.has(u["id"]):
		var n: Node3D = unit_nodes[u["id"]]
		var model := n.get_node_or_null("Model") as Node3D
		var locals := _ensure_trail_nozzles(u)
		if model != null and not locals.is_empty():
			heads = SHIP_ART.engine_nozzle_worlds(model, locals)
	if heads.is_empty():
		var stern: Vector3 = u["pos"]
		var fd: Vector3 = u.get("face_dir", Vector3.FORWARD)
		if fd.length_squared() > 0.0001:
			stern = u["pos"] - fd.normalized() * 1.1
		stern.y = BoardTypes.UNIT_Y + 0.15
		heads.append(stern)
	return heads

func _stamp_unit_trail(u: Dictionary, delta: float) -> void:
	## EveAC-style: stamp wake in world; head pinned to engine nozzles.
	var heads: Array = _trail_heads_world(u)
	var streams: Array = u.get("trail_streams", [])
	while streams.size() < heads.size():
		streams.append([])
	while streams.size() > heads.size():
		streams.remove_at(streams.size() - 1)
	var acc = float(u.get("trail_acc", 0.0)) + delta
	var interval = 0.05
	var do_stamp: bool = acc >= interval
	if do_stamp:
		acc = 0.0
	for si in range(heads.size()):
		var pts: Array = streams[si] if typeof(streams[si]) == TYPE_ARRAY else []
		var aged: Array = []
		for p in pts:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var age = float(p.get("age", 0.0)) + delta
			if age < 0.85:
				aged.append({"pos": p["pos"], "age": age})
		pts = aged
		if do_stamp:
			var head: Vector3 = heads[si]
			var ok = true
			if pts.size() > 0:
				var last: Vector3 = pts[pts.size() - 1]["pos"]
				if last.distance_to(head) < 0.12:
					ok = false
			if ok:
				pts.append({"pos": head, "age": 0.0})
			while pts.size() > 24:
				pts.remove_at(0)
		streams[si] = pts
	u["trail_streams"] = streams
	u["trail_pts"] = streams[0] if not streams.is_empty() else []
	u["trail_acc"] = acc

func _rebuild_unit_trail_mesh(trail: MeshInstance3D, u: Dictionary) -> void:
	var streams: Array = u.get("trail_streams", [])
	if streams.is_empty():
		var legacy: Array = u.get("trail_pts", [])
		if not legacy.is_empty():
			streams = [legacy]
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w = 0.11
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
			var up = Vector3(0, half_w, 0)
			st.set_color(c0); st.add_vertex(a + up)
			st.set_color(c1); st.add_vertex(b + up)
			st.set_color(c1); st.add_vertex(b - up)
			st.set_color(c0); st.add_vertex(a + up)
			st.set_color(c1); st.add_vertex(b - up)
			st.set_color(c0); st.add_vertex(a - up)
			any = true
	trail.mesh = st.commit() if any else null

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

func _current_station_label(p: Dictionary) -> String:
	var cs: String = str(p.get("current_station", ""))
	if cs == "" or not map.systems.has(cs):
		return "无"
	return str(map.systems[cs]["name"])

func _refresh_pilot_row_places(row: Control, p: Dictionary) -> void:
	if row == null or p.is_empty():
		return
	var sys_lab := row.find_child("SysLab", true, false) as Label
	if sys_lab:
		sys_lab.text = "所在星系：%s" % _sys_label(p)
	var home_lab := row.find_child("HomeLab", true, false) as Label
	if home_lab:
		home_lab.text = "初始空间站：%s" % _home_label(p)
	var cur_lab := row.find_child("CurLab", true, false) as Label
	if cur_lab:
		cur_lab.text = "当前空间站：%s" % _current_station_label(p)

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

func _tick_edge_pan() -> void:
	## CNC-style: invisible bands. Intent only — camera integrates velocity in tick_breathe.
	if cam == null:
		return
	if cam.panning or cam.rotating or _marker_drag_kind != "" \
			or (popup != null and popup.visible) \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		cam.cut_edge_pan()
		return
	var vp := get_viewport()
	if vp == null:
		cam.cut_edge_pan()
		return
	var mp := vp.get_mouse_position()
	var sz := vp.get_visible_rect().size
	if mp.x < 0.0 or mp.y < 0.0 or mp.x > sz.x or mp.y > sz.y:
		cam.set_edge_pan(Vector2.ZERO, 0.0)
		return
	if _mouse_over_blocking_hud(mp) or _hover_is_hud_control():
		cam.cut_edge_pan()
		return
	var dir := Vector2.ZERO
	var depth := 0.0
	if mp.x < EDGE_PAN_PX:
		dir.x = -1.0
		depth = 1.0
	elif mp.x > sz.x - EDGE_PAN_PX:
		dir.x = 1.0
		depth = 1.0
	if mp.y < EDGE_PAN_PX:
		dir.y = -1.0
		depth = 1.0
	elif mp.y > sz.y - EDGE_PAN_PX:
		dir.y = 1.0
		depth = 1.0
	cam.set_edge_pan(dir, depth)

func _setup_cmd_draw() -> void:
	_imp_baker = IMPOSTOR_BAKER_SCR.new()
	_imp_baker.name = "ImpostorBaker"
	add_child(_imp_baker)
	_mass_draw = MASS_DRAW_SCR.new()
	_mass_draw.name = "ShipMassDraw"
	add_child(_mass_draw)
	if _mass_draw.has_method("setup"):
		_mass_draw.setup(_imp_baker)


func _tick_command_layer(wall: float) -> void:
	_tick_edge_pan()
	_tick_mouse_hint(wall)
	_tick_touch_long_press()
	_consume_lmb_gesture()
	_consume_rmb_order()
	if cam and cam.has_method("tick_breathe"):
		cam.tick_breathe(wall)
	_update_box_overlay()
	_refresh_dilate_hint()
	# #region agent log
	if Engine.get_process_frames() % 90 == 0:
		_dbg59("CLK", "board_root._tick_command_layer", "clock", {
			"scale": float(_sim_clk.scale) if _sim_clk else 1.0,
			"fight": _fight_n,
			"runId": "cmd-clock"
		})
	# #endregion


func _refresh_dilate_hint() -> void:
	if _dilate_lab == null or _sim_clk == null:
		return
	var sc := float(_sim_clk.scale)
	if sc < 0.98:
		_dilate_lab.visible = true
		_dilate_lab.text = "时间膨胀 ×%.2f" % sc
	else:
		_dilate_lab.visible = false


func _sync_mass_and_bars(wall: float, spiked: bool) -> void:
	var battle := _is_battle_view()
	var star := cam != null and cam.starmap_mode
	if _mass_draw and _mass_draw.has_method("sync"):
		_mass_draw.sync(cam.cam if cam else null, units, _battle_model_ids, battle)
	if _hp_batch and _hp_batch.has_method("sync_units"):
		var host: Dictionary = {}
		for u2 in units:
			if not bool(u2.get("alive", false)):
				continue
			if _rel_for(int(u2.get("faction", 0))) == "hostile":
				host[str(u2.get("id", ""))] = true
		_hp_batch.sync_units(
			cam.cam if cam else null, units, selection, settings_battle_full_plates, wall, star,
			unit_nodes, host
		)
	if _imp_baker and _imp_baker.has_method("tick_idle"):
		var allow := (not spiked) and float(_sim_clk.scale) > 0.97 and battle
		_imp_baker.tick_idle(allow)
	if battle and _imp_baker:
		for u in units:
			if not bool(u.get("alive", false)) or bool(u.get("npc_hull", false)):
				continue
			var mk := str(u.get("model_key", ""))
			if mk != "":
				_imp_baker.enqueue(mk)


func _process(delta: float) -> void:
	if _mp != null:
		_mp.tick(delta)
		if _mp_cheat_lab != null:
			_mp_cheat_lab.text = _mp.audit_text()
	if sim_paused:
		_lmb_press_latch = false
		_lmb_release_latch = false
		_rmb_held = false
		_left_dragging = false
		_left_box_selecting = false
		if cam:
			cam.rotating = false
			cam.panning = false
			cam.cut_edge_pan()
		_refresh_dilate_hint()
		return
	_fight_n = _fighting_unit_count()
	_tick_command_layer(delta)
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
	var clk: Dictionary = _sim_clk.step(delta, _fight_n)
	var sim_dt: float = float(clk.get("sim_dt", delta))
	var spiked := bool(clk.get("spike", false))
	for built in pilots_sys.tick_build(pilots, sim_dt, map):
		if typeof(built) == TYPE_DICTIONARY:
			_note_match_built(int(built.get("faction", -1)))
	_tick_deputy_industry()
	_tick_auto_launch()
	_drain_order_queue(2)
	_tick_movement(sim_dt)
	_tick_sync_cohesion()
	_tick_capture(sim_dt)
	_tick_garrison_visibility(sim_dt)
	_tick_garrison_revive(sim_dt)
	_tick_regen_and_repair(sim_dt)
	_tick_weapon_locks(sim_dt)
	_tick_combat(sim_dt)
	_tick_ai(sim_dt)
	_tick_marker_widgets()
	_tick_diplo_offers(sim_dt)
	_tick_nav_resume(sim_dt)
	if br_tracker:
		br_tracker.tick(sim_dt)
		var before_br: int = br_tracker.closed.size()
		var before_active: int = br_tracker.active.size()
		var br_snap: Dictionary = br_tracker.tick_presence(
			units, map, sim_dt, Callable(self, "_atk_ready_ratio")
		)
		if br_tracker.active.size() != before_active:
			# #region agent log
			_dbg59("BR", "board_root.process", "br_start_bar", {
				"active": br_tracker.active.keys(), "closed": br_tracker.closed.size(),
				"viewer": viewer_faction, "clock": br_tracker.battle_clock, "runId": "post-fix"
			})
			# #endregion
			_refresh_br_list()
		if br_tracker.closed.size() != before_br:
			# #region agent log
			var last_rep: Dictionary = br_tracker.closed[br_tracker.closed.size() - 1]
			var facs_in: Dictionary = {}
			for rr in last_rep.get("rows", []):
				facs_in[int(rr.get("faction", -1))] = true
			_dbg59("BR", "board_root.process", "br_settle", {
				"closed": br_tracker.closed.size(), "active": br_tracker.active.size(),
				"sys": str(last_rep.get("sys", "")), "viewer": viewer_faction,
				"row_facs": facs_in.keys(), "mine_ships": int(last_rep.get("mine_ships", 0)),
				"closed_n": int(br_snap.get("closed_n", 0)),
				"clock": br_tracker.battle_clock, "runId": "post-fix"
			})
			# #endregion
			_refresh_br_list()
	var occ_info: Dictionary = _refresh_occupancy()
	var occ_changed_frame: bool = bool(occ_info.get("changed", false))
	var arc_changed_frame: bool = bool(occ_info.get("arcs", false))
	if bool(occ_info.get("scale", false)) and starmap_view:
		_starmap_scale_dirty = true
	## Soft arc 补帧 200ms (BH-35).
	var arcs_moving := map.tick_smooth_arcs(sim_dt) if map else false
	## Arc/scale morph: clamp idle into cell (no polar-slot chase; BH-38).
	_soft_follow_cell_slots(sim_dt, arcs_moving or occ_changed_frame)
	if starmap_view:
		var scaled = starmap_view.tick_smooth_scales(sim_dt)
		starmap_view.tick_screen_const_icons()
		## Paint force = color/owner only. Occupancy chatter must NOT force-paint every frame.
		var force_paint := map.capture_dirty
		if scaled or arcs_moving or force_paint or _starmap_scale_dirty:
			var painted := starmap_view.sync_ring_visuals(sim_dt, arcs_moving, scaled, force_paint)
			## Only clear after a real paint — throttle must not drop capture rim frames.
			if painted and map.capture_dirty:
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
	_separate_stacked_units(sim_dt)
	_curtain_acc += sim_dt
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
	_tick_battle_model_budget(sim_dt)
	_update_unit_visuals(sim_dt)
	if cam and cam.tactical_mode and not cam.starmap_mode and tactical_callouts:
		var callout_units: Array = []
		for uu in units:
			if _is_hostile_on_empty_cell(uu):
				continue
			if not _sleeper_plate_expanded(uu) and bool(uu.get("garrison", false)):
				continue
			callout_units.append(uu)
		tactical_callouts.view_yaw = float(cam.tactical_yaw)
		tactical_callouts.sync_occupied(callout_units, Callable(self, "_callout_claimant_ids"), sim_dt)
		_sync_tactical_overheads(sim_dt)
	elif cam and cam.starmap_mode and Engine.get_process_frames() % 30 == 0:
		_sync_starmap_rep_badges()
	rebuild_timer += sim_dt
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
	_tick_match_flow(sim_dt)
	_sync_mass_and_bars(delta, spiked)

func _add_cell_weight(sid: String, cell_i: int, amt: float) -> void:
	if amt <= 0.0 or not map.systems.has(sid) or _mp_fog_arc(sid):
		return
	var cells: Array = map.systems[sid]["cells"]
	if cell_i < 0 or cell_i >= cells.size():
		return
	cells[cell_i]["weight"] = float(cells[cell_i].get("weight", 1.0)) + amt

func _refresh_occupancy() -> Dictionary:
	## Per-cell weight → arc width. Quantize soft weights so arcs don't dirty every frame.
	for sid in map.systems.keys():
		if _mp_fog_arc(str(sid)):
			continue
		for c in map.systems[sid]["cells"]:
			c["weight"] = 1.0
	var sys_ships: Dictionary = {}
	for sid in map.systems.keys():
		sys_ships[sid] = 0.0
	for u in units:
		if not u.get("alive", false):
			continue
		if bool(u.get("garrison", false)):
			## Sleepers stay on the ring for system presence, but do not widen cell arcs.
			var gsid := str(u.get("sys", ""))
			if sys_ships.has(gsid):
				sys_ships[gsid] = float(sys_ships[gsid]) + 1.0
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

func _abort_garrison_travel(u: Dictionary) -> void:
	## Garrison never accepts a path. Pull a unit that already left back to its post.
	if not bool(u.get("garrison", false)):
		return
	var ph := int(u.get("phase", 0))
	var has_path := not (u.get("path", []) as Array).is_empty()
	if ph == BoardTypes.MovePhase.IDLE and not has_path and not u.has("order_dest_sys"):
		return
	u["path"] = []
	u.erase("order_dest_sys")
	u.erase("order_dest_cell")
	u.erase("nav_standby_on_sys_enter")
	var sys := str(u.get("post_sys", u.get("from_sys", u.get("sys", ""))))
	var cell := int(u.get("post_cell", u.get("from_cell", u.get("cell", -1))))
	if sys == "":
		sys = str(u.get("sys", ""))
	u["sys"] = sys
	u["cell"] = cell
	u["from_cell"] = cell
	u["to_cell"] = cell
	u["from_sys"] = sys
	u["to_sys"] = sys
	u["phase"] = BoardTypes.MovePhase.IDLE
	u["phase_t"] = 0.0
	u["player_hold"] = false
	_clear_reserve(u)
	if map != null and map.systems.has(sys) and cell >= 0:
		var home := _clamp_pos_to_cell(sys, cell, _cell_pos_visual(sys, cell, BoardTypes.UNIT_Y))
		u["pos"] = home
		u["rest_pos"] = home
		_mark_cell_enter(u, sys, cell)

func _begin_undock_rise(u: Dictionary) -> void:
	## Leave the station under the cell, same rules as cross-cell INVULN (SHIPS.md §7).
	var sys := str(u.get("sys", ""))
	var cell := int(u.get("cell", -1))
	if sys == "" or cell < 0 or map == null or not map.systems.has(sys):
		return
	u["from_sys"] = sys
	u["to_sys"] = sys
	u["from_cell"] = cell
	u["to_cell"] = cell
	u["step_kind"] = "undock"
	u["step_invuln"] = UNDOCK_RISE_S
	_enter_step_invuln(u)
	var surface := _cell_pos_visual(sys, cell, BoardTypes.UNIT_Y)
	u["pos"] = Vector3(surface.x, BoardTypes.UNIT_Y - UNDOCK_SINK_Y, surface.z)
	u["rest_pos"] = surface
	u["from_pos"] = u["pos"]
	u["to_pos"] = surface
	u.erase("cell_key")


func _tick_undock_rise(u: Dictionary) -> void:
	var sys := str(u.get("sys", ""))
	var cell := int(u.get("cell", -1))
	var surface := _cell_pos_visual(sys, cell, BoardTypes.UNIT_Y)
	var t0 := maxf(float(u.get("step_invuln", UNDOCK_RISE_S)), 0.01)
	var k := 1.0 - clampf(float(u.get("phase_t", 0.0)) / t0, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var y := lerpf(BoardTypes.UNIT_Y - UNDOCK_SINK_Y, BoardTypes.UNIT_Y, e)
	u["pos"] = Vector3(surface.x, y, surface.z)
	u["to_pos"] = surface


func _finish_undock_rise(u: Dictionary) -> void:
	var sys := str(u.get("sys", ""))
	var cell := int(u.get("cell", -1))
	var surface := _cell_pos_visual(sys, cell, BoardTypes.UNIT_Y)
	u["pos"] = surface
	u["rest_pos"] = surface
	u["phase"] = BoardTypes.MovePhase.IDLE
	u["phase_t"] = 0.0
	u["alpha"] = 1.0
	u["step_kind"] = ""
	_clear_reserve(u)
	_mark_cell_enter(u, sys, cell)


func _enter_step_invuln(u: Dictionary) -> void:
	## Cross-cell or gate transit: invulnerable, untargetable, belongs to no cell.
	u["phase"] = BoardTypes.MovePhase.INVULN
	u["phase_t"] = float(u.get("step_invuln", _dev_move(u)))
	u["alpha"] = BoardTypes.INVULN_ALPHA
	u["trail_pts"] = []
	u["trail_streams"] = []
	u["trail_acc"] = 0.0
	## Callout stays on departure until LANDING (TACTICAL_TOPDOWN §9).
	_guard_force_off(u)

func _tick_movement(delta: float) -> void:
	_sim_clock += delta
	for u in units:
		if not u.get("alive", false):
			continue
		if not _mp_sim_unit(u):
			continue
		if bool(u.get("garrison", false)):
			_abort_garrison_travel(u)
		match int(u["phase"]):
			BoardTypes.MovePhase.IDLE:
				u["float_t"] = float(u["float_t"]) + delta
				if not u["path"].is_empty():
					if _sync_start_blocked(u):
						continue
					_start_step(u)
			BoardTypes.MovePhase.PREP:
				if _cell_interdicted(str(u.get("sys", "")), int(u.get("cell", -1))):
					_abort_prep_for_hold(u)
					continue
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
					_enter_step_invuln(u)
					admin.request("board.move", {"unit": u["id"], "phase": "invuln"})
			BoardTypes.MovePhase.INVULN:
				u["phase_t"] = float(u["phase_t"]) - delta
				if str(u.get("step_kind", "")) == "undock":
					_tick_undock_rise(u)
					if float(u["phase_t"]) <= 0.0:
						_finish_undock_rise(u)
				else:
					var t0: float = float(u.get("step_invuln", _dev_move(u)))
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
						## INVULN belongs to no cell. Keep departure index until landing.
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
						u["phase_t"] = _landing_phase_t(u)
						u["alpha"] = 1.0
						_guard_force_off(u)
						## Jump arrivals share one mouth point. One-shot inner-biased slots, then soft separate.
						if str(u.get("step_kind", "")) == "jump":
							u["jump_wave"] = "%s:%d" % [str(u["sys"]), int(u["cell"])]
							_spread_jump_wave(str(u["sys"]), int(u["cell"]))
						else:
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

func _cell_interdicted(sys: String, cell: int) -> bool:
	for o in units:
		if not o.get("alive", false):
			continue
		if not o.get("interdict_on", false):
			continue
		if str(o.get("sys", "")) != sys:
			continue
		if int(o.get("cell", -1)) != cell:
			continue
		if int(o.get("phase", 0)) == BoardTypes.MovePhase.INVULN:
			continue
		return true
	return false

func _abort_prep_for_hold(u: Dictionary) -> void:
	var step := {
		"to": int(u.get("to_cell", u.get("cell", 0))),
		"kind": str(u.get("step_kind", "intra")),
	}
	if str(step["kind"]) == "jump":
		step["to_sys"] = str(u.get("to_sys", u.get("sys", "")))
	u["path"].push_front(step)
	u["phase"] = BoardTypes.MovePhase.IDLE
	u["phase_t"] = 0.0
	_clear_reserve(u)

func _start_step(u: Dictionary) -> void:
	if bool(u.get("garrison", false)):
		u["path"] = []
		u.erase("order_dest_sys")
		u.erase("order_dest_cell")
		return
	if _cell_interdicted(str(u.get("sys", "")), int(u.get("cell", -1))):
		return
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
		u["step_invuln"] = _dev_jump(u) + stag
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
		u["step_invuln"] = _dev_move(u)
	var prep = _dev_prep(u)
	_assign_reserve(u)
	# #region agent log
	_dbg59("STEP", "board_root._start_step", "start", {
		"unit": str(u["id"]), "kind": str(u["step_kind"]), "prep": 0.0 if str(u["step_kind"]) == "jump" else prep,
		"invuln": float(u["step_invuln"]), "gid": int(u.get("sync_gid", 0)), "clock": _sim_clock, "runId": "post-fix"
	})
	# #endregion
	if str(u["step_kind"]) == "jump":
		## Gate transit: no align prep. Gate time (invulnerable) then landing.
		_enter_step_invuln(u)
		admin.request("board.move", {"unit": u["id"], "phase": "invuln", "step": step})
		return
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
	var cells: Array = map.systems[sys]["cells"]
	var n = cells.size()
	var pull = 3
	if not mover.get("bubble_immune", false):
		for c in cells:
			if not c.get("bubble", false):
				continue
			var bi: int = c["index"]
			var d_from = BoardTypes.shorter_arc_steps(from_c, bi, n)
			var d_to = BoardTypes.shorter_arc_steps(to_c, bi, n)
			if d_from > d_to and d_from <= pull:
				return bi
	for o in units:
		if not o.get("alive", false) or not o.get("interdict_on", false):
			continue
		if str(o.get("sys", "")) != sys:
			continue
		if int(o.get("phase", 0)) == BoardTypes.MovePhase.INVULN:
			continue
		var hi: int = int(o.get("cell", -1))
		var hd_from = BoardTypes.shorter_arc_steps(from_c, hi, n)
		var hd_to = BoardTypes.shorter_arc_steps(to_c, hi, n)
		if hd_from > hd_to and hd_from <= pull:
			return hi
	return to_c

func _apply_bubble_pull_on_land(_u: Dictionary) -> void:
	# clear transit flags for this unit's gate
	var keys: Array = starmap_view.transit_gates.keys()
	for k in keys:
		# leave flags; simplified clear all when any lands
		pass
	starmap_view.transit_gates.clear()

func _tick_capture(delta: float) -> void:
	var saved := _mp_before_capture()
	var flips = capture.tick(map, units, delta)
	_mp_after_capture(saved)
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
		for fid in faction_ai.keys():
			if int(f["owner"]) != int(fid):
				(faction_ai[fid] as BoardAiController).on_capture_stolen(f["sys"], f["cell"])
		if player_deputy != null and deputy_group >= 0 and not _commanded_id_set(deputy_group).is_empty() \
				and int(f["owner"]) != viewer_faction:
			player_deputy.on_capture_stolen(f["sys"], f["cell"])
		if int(f.get("prev_owner", -1)) == viewer_faction and int(f.get("owner", -1)) != viewer_faction:
			var lost_sys := _sys_display_name(str(f.get("sys", "")))
			var lost_cell: Dictionary = map.systems[str(f["sys"])]["cells"][int(f["cell"])]
			if int(f.get("kind", -1)) == BoardTypes.CellKind.GATE and str(lost_cell.get("gate_to", "")) != "":
				var dest := _sys_display_name(str(lost_cell["gate_to"]))
				_chat_deputy("%s星系的%s门丢失，我们失去了从%s星系前往%s的路" % [lost_sys, dest, lost_sys, dest])
			else:
				_chat_deputy("%s地点的%s丢失" % [lost_sys, _cell_kind_zh(int(f.get("kind", -1)))])
		_update_home_stations_on_flip(f)
		_on_capture_flip_garrison(f)
	if need_ai_res:
		for fid2 in faction_ai.keys():
			_rebalance_faction_resources(int(fid2))
		_rebalance_deputy_resources()

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

func _tick_bubbles(delta: float) -> void:
	## Expire active light-bubble fields (pull only; no leave-block).
	for sid in map.systems.keys():
		var cells: Array = map.systems[sid]["cells"]
		for cell in cells:
			if not cell.get("bubble", false):
				continue
			var remain := float(cell.get("bubble_remain", 0.0)) - delta
			cell["bubble_t"] = float(cell.get("bubble_t", 0.0)) + delta
			if remain <= 0.0:
				cell["bubble"] = false
				cell["bubble_remain"] = 0.0
			else:
				cell["bubble_remain"] = remain
	## 45s pulse: if switch on at check, apply 45s pull field on current cell.
	for u in units:
		if not u.get("alive", false):
			continue
		if not u.get("bubble_on", false):
			continue
		u["bubble_cd"] = float(u.get("bubble_cd", 0.0)) - delta
		if float(u["bubble_cd"]) > 0.0:
			continue
		u["bubble_cd"] = BUBBLE_PULSE_S
		var cell2: Dictionary = map.systems[u["sys"]]["cells"][u["cell"]]
		cell2["bubble"] = true
		cell2["bubble_remain"] = BUBBLE_PULSE_S
		cell2["bubble_t"] = float(cell2.get("bubble_t", 0.0))

func _tick_combat(delta: float) -> void:
	_tick_bubbles(delta)
	for u in units:
		if not u.get("alive", false):
			continue
		if not _mp_sim_unit(u):
			continue
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
			if _unit_between_cells(tgt):
				g["target"] = ""
				continue
			pd_claimed[str(tgt["id"])] = true
			var dist_m = _pd_tracking_distance_m(u, tgt)
			var p_hit = BoardCombatFormulas.turret_hit_chance(
				g["tracking"], g["sig_res"], g["falloff"], float(g.get("optimal", 0.0)),
				_hit_speed(tgt), tgt["signature_radius"], dist_m
			)
			g["cd"] = float(g["cycle"])
			g["target"] = tgt["id"]
			var hit = rng.randf() <= p_hit
			var raw = float(g["damage"]) * _dph_mul(u)
			raw = _focus_on_hit(u, hit, raw)
			if not hit or raw <= 0.0:
				_play_pd_vfx(u, g, tgt, false)
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
			_play_pd_vfx(u, g, tgt, true)
		for w in u.get("weapons", []):
			w["cd"] = float(w["cd"]) - delta
			_sample_sniper_on_cd(u, w)
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
			and not _pair_attack_forbidden(u, focus) \
			and not _unit_between_cells(u) and not _unit_between_cells(focus) \
			and _pd_in_range(u, focus, g) and not claimed.has(str(focus["id"])):
		return focus
	var cur = _unit_by_id(str(g.get("target", "")))
	if cur and cur.get("alive", false) and not _unit_between_cells(cur) and _pd_in_range(u, cur, g):
		if not claimed.has(str(cur["id"])):
			return cur
	if cur and _unit_between_cells(cur):
		g["target"] = ""
	var best = {}
	var best_d = INF
	for o in units:
		if not o.get("alive", false):
			continue
		if _unit_between_cells(u) or _unit_between_cells(o):
			continue
		if int(o["faction"]) == int(u["faction"]):
			continue
		if _pair_attack_forbidden(u, o):
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
	if _unit_between_cells(a) or _unit_between_cells(b):
		return false
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
		if _unit_between_cells(u) or _unit_between_cells(o):
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
		if int(p.get("faction", -1)) == viewer_faction:
			_rebuild_group_dict()
			_refresh_all_group_badges()
	if cam.follow_unit_id == u["id"]:
		cam.clear_follow_keep_look()
	if _is_battle_view():
		var death_pos: Vector3 = u.get("pos", Vector3.ZERO)
		if unit_nodes.has(u["id"]):
			death_pos = (unit_nodes[u["id"]] as Node3D).global_position
		SHIP_DEATH_FX.spawn(self, death_pos, str(u.get("tonnage", "")))
	if unit_nodes.has(u["id"]):
		unit_nodes[u["id"]].visible = false
		var oh2 = unit_nodes[u["id"]].get_node_or_null("Overhead")
		if oh2 and oh2.has_method("set_alive_view"):
			oh2.set_alive_view(false)
		var body = unit_nodes[u["id"]].get_node_or_null("PickBody") as StaticBody3D
		if body:
			body.collision_layer = 0
	selection.erase(u["id"])
	_release_ship_from_deputy_fleets(u)
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

func _prepare_deputy_bubble(ctrl: BoardAiController, plist: Array) -> void:
	var ships: Dictionary = {}
	if data:
		for sid in data.ships.keys():
			if _ship_has_fit_slot(data.ship_def(str(sid)), "bubble"):
				ships[str(sid)] = true
	ctrl.bubble_ships = ships
	var stock: Dictionary = {}
	for p in plist:
		var counts: Dictionary = pilots_sys.storage_count_by_model(p)
		for sid2 in counts.keys():
			if int(counts[sid2]) > 0 and ships.has(str(sid2)):
				stock[str(p.get("id", ""))] = true
	ctrl.bubble_stock = stock

func _lowest_hp_enemy_in_cell(fac: int, sys: String, cell: int) -> Dictionary:
	var best: Dictionary = {}
	var best_hp := INF
	var rels: Dictionary = data.diplomacy.get("relations", {}).get(str(fac), {})
	for u in units:
		if not u.get("alive", false):
			continue
		var of := int(u.get("faction", -1))
		if of == fac:
			continue
		var rel := str(rels.get(str(of), "hostile"))
		if rel == "ally" or rel == "self":
			continue
		if str(u.get("sys", "")) != sys or int(u.get("cell", -1)) != cell:
			continue
		var inst: Dictionary = u.get("inst", {})
		var hp := float(inst.get("shield", 0)) + float(inst.get("armor", 0)) + float(inst.get("structure", 0))
		if hp < best_hp:
			best_hp = hp
			best = u
	return best

func _apply_deputy_orders(orders: Array, expect_fac: int) -> void:
	for o in orders:
		var u = _unit_by_id(str(o.get("unit_id", "")))
		if u.is_empty() or int(u.get("faction", 0)) != expect_fac:
			continue
		if bool(u.get("player_hold", false)):
			continue
		if o.has("sync"):
			if bool(o.get("sync", false)):
				u["sync_move"] = true
				u["sync_gid"] = 100000 + int(o.get("fleet_id", 0))
			else:
				u["sync_move"] = false
				u.erase("sync_gid")
		var kind := str(o.get("kind", "move"))
		if kind == "sync":
			continue
		if kind == "focus":
			var foe := _lowest_hp_enemy_in_cell(expect_fac, str(o.get("sys", "")), int(o.get("cell", -1)))
			if not foe.is_empty():
				u["focus_id"] = str(foe.get("id", ""))
			continue
		if kind == "dock":
			if _can_dock(u):
				_dock_unit(u)
			else:
				_order_move_ai(u, str(o.get("sys", "")), int(o.get("cell", -1)))
			continue
		_order_move_ai(u, str(o.get("sys", "")), int(o.get("cell", -1)))
		admin.request("ai.order", o)

func _tick_ai(delta: float) -> void:
	for u in units:
		if bool(u.get("player_hold", false)) and (u.get("path", []) as Array).is_empty() \
				and int(u.get("phase", 0)) == BoardTypes.MovePhase.IDLE:
			u["player_hold"] = false
		var fac := int(u.get("faction", 0))
		if fac == viewer_faction or data.is_npc_faction(fac) or not u.get("alive", false):
			continue
		u["dealt_timer"] = float(u.get("dealt_timer", 0.0)) + delta
	_sync_nav_arrow()
	for fid in faction_ai.keys():
		var ctrl: BoardAiController = faction_ai[fid]
		_apply_marker_tasks(ctrl)
		_prepare_deputy_bubble(ctrl, _faction_pilots(int(fid)))
		var orders = ctrl.tick_orders(map, _mp_ai_units(int(fid), units), data.diplomacy)
		_apply_deputy_orders(orders, int(fid))
		# #region agent log
		_ai_probe(int(fid), ctrl, orders)
		# #endregion
	if player_deputy != null and deputy_group >= 0 and not _commanded_id_set(deputy_group).is_empty():
		_apply_marker_tasks(player_deputy)
		_prepare_deputy_bubble(player_deputy, _commanded_pilots(deputy_group))
		var porders = player_deputy.tick_orders(map, _mp_ai_units(viewer_faction, units), data.diplomacy)
		_apply_deputy_orders(porders, viewer_faction)

# #region agent log
var _ai_probe_next: Dictionary = {}

func _ai_probe(fid: int, ctrl: BoardAiController, orders: Array) -> void:
	## Throttled (5 s / faction) AI decision snapshot for the far-enemy no-response check.
	if _sim_clock < float(_ai_probe_next.get(fid, 0.0)):
		return
	_ai_probe_next[fid] = _sim_clock + 5.0
	var my_w: float = ctrl.total_weight(units)
	var alive_mine := 0
	var in_fleet := 0
	var idle := 0
	var pathing := 0
	var held := 0
	var fleet_ids: Dictionary = {}
	for f in ctrl.fleets:
		for m in f["members"]:
			fleet_ids[str(m)] = true
	var lead_sys := ""
	for u in units:
		if int(u.get("faction", 0)) != fid or not u.get("alive", false) or bool(u.get("garrison", false)):
			continue
		alive_mine += 1
		if lead_sys == "":
			lead_sys = str(u.get("sys", ""))
		if fleet_ids.has(str(u["id"])):
			in_fleet += 1
		if int(u.get("phase", 0)) == BoardTypes.MovePhase.IDLE:
			idle += 1
		if not (u.get("path", []) as Array).is_empty():
			pathing += 1
		if bool(u.get("player_hold", false)):
			held += 1
	## Enemy presence as the AI sees it (10% threshold) vs raw (threshold 1.0).
	var enemy_sys_raw: Dictionary = {}
	var enemy_w_total := 0.0
	for u2 in units:
		if not u2.get("alive", false) or bool(u2.get("garrison", false)):
			continue
		if not ctrl._is_enemy_fac(int(u2["faction"])):
			continue
		var es := str(u2.get("sys", ""))
		enemy_sys_raw[es] = float(enemy_sys_raw.get(es, 0.0)) + BoardTypes.tonnage_weight(u2.get("tonnage", "destroyer"))
		enemy_w_total += BoardTypes.tonnage_weight(u2.get("tonnage", "destroyer"))
	var near_thr := ""
	var near_raw := ""
	if lead_sys != "" and map.systems.has(lead_sys):
		near_thr = ctrl._nearest_enemy_system(map, units, lead_sys, my_w)
		near_raw = ctrl._nearest_enemy_system(map, units, lead_sys, 1.0)
	var states: Array = []
	for f2 in ctrl.fleets:
		states.append("%s:%d" % [str(f2.get("state", "")), (f2.get("members", []) as Array).size()])
	_dbg59("L1", "board_root._ai_probe", "snapshot", {
		"fac": fid, "deputy": str(ctrl.deputy_id), "my_w": my_w, "alive": alive_mine, "in_fleet": in_fleet,
		"idle": idle, "pathing": pathing, "player_hold": held, "fleets": states,
		"lead_sys": lead_sys, "nearest_enemy_10pct": near_thr, "nearest_enemy_raw": near_raw,
		"enemy_sys_w": enemy_sys_raw, "enemy_w_total": enemy_w_total, "orders": orders.size(),
		"t": _sim_clock, "runId": "ai-far"
	})
# #endregion

func _unit_alpha_damage(u: Dictionary) -> float:
	var def: Dictionary = data.ship_def(str(u.get("ship_id", "")))
	var total := 0.0
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind", "")) != "weapon":
			continue
		var eq: Dictionary = data.equipment.get(str(h.get("ref", "")), {})
		var n := maxi(int(h.get("count", 1)), 1)
		total += (float(eq.get("damage_emp", 0)) + float(eq.get("damage_thermal", 0)) + float(eq.get("damage_kinetic", 0)) + float(eq.get("damage_explosive", 0))) * float(n)
	return total

func _unit_hull_hp(u: Dictionary) -> float:
	var inst: Dictionary = u.get("inst", {})
	if inst.has("max_s"):
		return float(inst.get("max_s", 0)) + float(inst.get("max_a", 0)) + float(inst.get("max_h", 0))
	var def: Dictionary = data.ship_def(str(u.get("ship_id", "")))
	return float(def.get("shield", 0)) + float(def.get("armor", 0)) + float(def.get("structure", 0))

func _pick_marker_fleet(ctrl: BoardAiController, mode: String, used: Dictionary) -> int:
	var best := -1
	var best_s := -1.0
	for f in ctrl.fleets:
		var fid := int(f.get("id", -1))
		if used.has(fid):
			continue
		if str(f.get("marker", "")) != "" and str(f.get("marker", "")) != mode:
			continue
		var score := 0.0
		for uid in f.get("members", []):
			var u = _unit_by_id(str(uid))
			if u.is_empty() or not u.get("alive", false):
				continue
			score += _unit_alpha_damage(u) if mode == "alpha" else _unit_hull_hp(u)
		if score > best_s:
			best_s = score
			best = fid
	return best

func _marker_fleet(ctrl: BoardAiController, fid: int) -> Dictionary:
	for f in ctrl.fleets:
		if int(f.get("id", -1)) == fid:
			return f
	return {}

func _trench_defense_system() -> String:
	if not map_markers.has("trench"):
		return ""
	var m: Dictionary = map_markers["trench"]
	var yaw: float = float(m.get("yaw", 0.0))
	var teeth := Vector3(sin(yaw), 0.0, -cos(yaw))
	var back := -teeth
	var origin: Vector3 = m["pos"]
	var best := ""
	var best_d := INF
	for sid in map.systems.keys():
		var center: Vector3 = map.systems[sid]["center"]
		var d := center - origin
		if d.dot(back) <= 1.0:
			continue
		var dist := d.length()
		if dist < best_d:
			best_d = dist
			best = str(sid)
	if best == "":
		best_d = INF
		for sid2 in map.systems.keys():
			var dist2: float = (map.systems[sid2]["center"] as Vector3).distance_to(origin)
			if dist2 < best_d:
				best_d = dist2
				best = str(sid2)
	return best

func _nearest_system(pos: Vector3) -> String:
	var best := ""
	var best_d := INF
	for sid in map.systems.keys():
		var dist: float = (map.systems[sid]["center"] as Vector3).distance_to(pos)
		if dist < best_d:
			best_d = dist
			best = str(sid)
	return best

func _apply_marker_tasks(ctrl: BoardAiController) -> void:
	var used: Dictionary = {}
	var trench_id := -1
	var target_id := -1
	if map_markers.has("trench"):
		trench_id = _pick_marker_fleet(ctrl, "alpha", used)
		if trench_id >= 0:
			used[trench_id] = true
	if map_markers.has("target"):
		target_id = _pick_marker_fleet(ctrl, "hp", used)
	for f in ctrl.fleets:
		var fid := int(f.get("id", -1))
		if fid != trench_id and fid != target_id and str(f.get("state", "")) == "marker":
			f["state"] = "station"
			f["marker"] = ""
	if trench_id >= 0:
		var tf := _marker_fleet(ctrl, trench_id)
		tf["state"] = "marker"
		tf["marker"] = "trench"
		var sys := _trench_defense_system()
		var cell := map.find_cell_of_kind(sys, BoardTypes.CellKind.GATE) if sys != "" else -1
		if cell >= 0:
			_order_fleet_idle(tf, sys, cell, false)
	if target_id >= 0:
		var gf := _marker_fleet(ctrl, target_id)
		gf["state"] = "marker"
		gf["marker"] = "target"
		var tpos: Vector3 = map_markers["target"]["pos"]
		var tsys := _nearest_system(tpos)
		var cells: Array = []
		if tsys != "" and map.systems.has(tsys):
			for c in map.systems[tsys]["cells"]:
				if int(c.get("kind", -1)) != BoardTypes.CellKind.EMPTY:
					cells.append(int(c["index"]))
		_order_fleet_spread(gf, tsys, cells)

func _order_fleet_idle(f: Dictionary, sys: String, cell: int, sync_on: bool) -> void:
	var gid := 8000 + int(f.get("id", 0))
	for uid in f.get("members", []):
		var u = _unit_by_id(str(uid))
		if u.is_empty() or not u.get("alive", false) or bool(u.get("player_hold", false)) \
				or bool(u.get("garrison", false)):
			continue
		if sync_on:
			u["sync_gid"] = gid
		if not (u.get("path", []) as Array).is_empty():
			continue
		if int(u.get("phase", 0)) != BoardTypes.MovePhase.IDLE:
			continue
		if str(u.get("sys", "")) == sys and int(u.get("cell", -1)) == cell:
			continue
		_order_move_ai(u, sys, cell)

func _order_fleet_spread(f: Dictionary, sys: String, cells: Array) -> void:
	if sys == "" or cells.is_empty():
		return
	var gid := 8100 + int(f.get("id", 0))
	var i := 0
	for uid in f.get("members", []):
		var u = _unit_by_id(str(uid))
		if u.is_empty() or not u.get("alive", false) or bool(u.get("player_hold", false)) \
				or bool(u.get("garrison", false)):
			continue
		u["sync_gid"] = gid
		var cell := int(cells[i % cells.size()])
		i += 1
		if not (u.get("path", []) as Array).is_empty():
			continue
		if int(u.get("phase", 0)) != BoardTypes.MovePhase.IDLE:
			continue
		if str(u.get("sys", "")) == sys and int(u.get("cell", -1)) == cell:
			continue
		_order_move_ai(u, sys, cell)

func _order_move_ai(u: Dictionary, to_sys: String, to_cell: int) -> void:
	## Garrison holds its post. Deputy fleets must not path it.
	if bool(u.get("garrison", false)):
		u["path"] = []
		u.erase("order_dest_sys")
		u.erase("order_dest_cell")
		return
	## Remember the strategic cell. A blocked gate only walks to the door; resume repaths after capture.
	var prep = _dev_prep(u)
	u["order_dest_sys"] = to_sys
	u["order_dest_cell"] = to_cell
	u["path"] = BoardPlayerNav.find_path(
		map, data.diplomacy, u["faction"],
		u["sys"], u["cell"], to_sys, to_cell,
		prep, _dev_move(u), _dev_land(u), _dev_jump(u)
	)
	# #region agent log
	if str(u["sys"]) != to_sys:
		_dbg59("L3", "board_root._order_move_ai", "ai_path", {
			"unit": u["id"], "fac": int(u["faction"]), "from": [u["sys"], u["cell"]], "to": [to_sys, to_cell],
			"path_len": (u["path"] as Array).size(), "runId": "ai-far"
		})
	# #endregion

func _update_unit_visuals(delta: float) -> void:
	var viewer_fight := _viewer_combat_plate_ids()
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
		if _mp_hide_unit(u):
			n.visible = false
			if oh:
				oh.visible = false
			continue
		n.global_position = u["pos"]
		## RTS: off-frustum units skip plates / trails / look_at (engine still culls the mesh).
		var in_frustum := true
		if cam != null and cam.cam != null:
			in_frustum = cam.cam.is_position_in_frustum(u["pos"] as Vector3)
		if not in_frustum:
			if oh:
				oh.visible = false
			var trail_off := n.get_node_or_null("Trail") as MeshInstance3D
			if trail_off:
				trail_off.visible = false
			continue
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
		var fx_on := _battle_fx_allowed(str(u.get("id", "")))
		if trail:
			if not fx_on:
				u["trail_pts"] = []
				u["trail_streams"] = []
				trail.visible = false
				trail.mesh = null
			elif tac:
				trail.visible = false
			elif moving:
				_stamp_unit_trail(u, delta)
				_rebuild_unit_trail_mesh(trail, u)
				trail.visible = true
			else:
				u["trail_pts"] = []
				u["trail_streams"] = []
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
			## Battlefield: full plate if selected, viewer non-sleeper fight, or settings always-full.
			## Tactical: sleeper compact until same-cell / lock expand (SHIPS §13).
			var battle_view := not tac and not star
			var compact := false
			if battle_view:
				if settings_battle_full_plates:
					compact = false
				else:
					compact = not sel_on and not viewer_fight.has(str(u.get("id", "")))
			elif bool(u.get("garrison", false)):
				compact = not _sleeper_plate_expanded(u)
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

func _spread_jump_wave(sys: String, cell: int) -> void:
	## One layout when a jump lands. Not a per-frame slot chase (BH-38).
	var wave := "%s:%d" % [sys, cell]
	var group: Array = []
	for uu in units:
		if not uu.get("alive", false):
			continue
		if str(uu.get("sys", "")) != sys or int(uu.get("cell", -1)) != cell:
			continue
		if str(uu.get("jump_wave", "")) != wave:
			continue
		var ph := int(uu.get("phase", 0))
		if ph != BoardTypes.MovePhase.IDLE and ph != BoardTypes.MovePhase.LANDING:
			continue
		group.append(uu)
	if group.is_empty():
		return
	group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	var n := group.size()
	for i in n:
		var p: Vector3 = _cell_slot_pos(sys, cell, i, n)
		var ship: Dictionary = group[i]
		ship["pos"] = p
		ship["rest_pos"] = p
		ship["land_pos"] = p


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
	## Dest claim only on LANDING. INVULN belongs to no cell (not a target, not a slot occupant).
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
		elif ph == BoardTypes.MovePhase.LANDING:
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
	if not _unit_sync_on(u) or _sync_group_stationary_one_cell(gid):
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
	## Per-unit sync_move: a gid only exists when the whole batch had it on.
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
	if not _unit_sync_on(u):
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
	var uid := str(u.get("id", ""))
	var wave: Dictionary = _sync_waves.get(gid, {})
	for wid in wave.keys():
		var wu = _unit_by_id(str(wid))
		if wu.is_empty() or not wu.get("alive", false) or int(wu.get("sync_gid", 0)) != gid \
				or wu["path"].is_empty() or int(wu.get("phase", 0)) != BoardTypes.MovePhase.IDLE:
			wave.erase(wid)
	if wave.has(uid):
		if _sim_clock + 0.0001 >= float(wave[uid]):
			wave.erase(uid)
			return false
		return true
	var peers := _sync_peers(gid)
	for o in peers:
		if str(o.get("id", "")) == uid:
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
	if not wave.is_empty():
		return true
	if u["path"].is_empty():
		return false
	wave = _sync_build_wave(gid, peers)
	_sync_waves[gid] = wave
	if wave.has(uid) and _sim_clock + 0.0001 >= float(wave[uid]):
		wave.erase(uid)
		return false
	return true

func _sync_step_total(o: Dictionary) -> float:
	## Gate: gate time only. Intra-system: align prep + cross time.
	var step: Dictionary = o["path"][0]
	if str(step.get("kind", "")) == "jump":
		return _dev_jump(o)
	return _dev_prep(o) + _dev_move(o)

func _sync_next_key(o: Dictionary) -> String:
	var step: Dictionary = o["path"][0]
	if str(step.get("kind", "")) == "jump":
		return "%s:%d" % [str(step.get("to_sys", "")), int(step.get("to", -1))]
	return "%s:%d" % [str(o.get("sys", "")), int(step.get("to", -1))]

func _sync_build_wave(gid: int, peers: Array) -> Dictionary:
	## One step for the whole group: the slowest member leads; others start late so all land together.
	var movers: Array = []
	for o in peers:
		if int(o.get("phase", 0)) == BoardTypes.MovePhase.IDLE and not o["path"].is_empty():
			movers.append(o)
	if movers.is_empty():
		return {}
	var dest := _sync_shared_dest(peers)
	var cur_keys := _sync_occupy_keys(peers, "")
	if not _sync_keys_span_ok(cur_keys):
		## Already spread: only the furthest-from-dest trailers step (catch up).
		var far := -1
		for o1 in movers:
			far = maxi(far, _sync_dist_to_dest(o1, dest))
		var trail: Array = []
		for o2 in movers:
			if _sync_dist_to_dest(o2, dest) == far:
				trail.append(o2)
		movers = trail
	else:
		## March span: the step may not open a third or non-adjacent cell (SHIPS §10).
		var keys := cur_keys.duplicate()
		for o3 in movers:
			keys.erase(_sync_unit_occupy_key(o3))
			keys[_sync_next_key(o3)] = true
		if not _sync_keys_span_ok(keys):
			var lead_next := _sync_next_key(movers[0])
			var kept: Array = []
			for o4 in movers:
				if _sync_next_key(o4) == lead_next:
					kept.append(o4)
			movers = kept
	var slowest := 0.0
	var leader := ""
	for o5 in movers:
		var t := _sync_step_total(o5)
		if t > slowest:
			slowest = t
			leader = str(o5.get("id", ""))
	var wave := {}
	for o6 in movers:
		wave[str(o6.get("id", ""))] = _sim_clock + (slowest - _sync_step_total(o6))
	# #region agent log
	var delays := {}
	for k in wave.keys():
		delays[k] = snappedf(float(wave[k]) - _sim_clock, 0.01)
	_dbg59("SYNC", "board_root._sync_build_wave", "wave", {
		"gid": gid, "leader": leader, "slowest": slowest, "delays": delays,
		"peers": peers.size(), "runId": "post-fix"
	})
	# #endregion
	return wave

func _check_defeat() -> void:
	## Kept for callers; match flow owns end conditions.
	_tick_match_victory_checks()

func _load_match_modes_from_layout() -> void:
	var lay: Dictionary = map.layout if map != null else {}
	var modes = lay.get("match_modes", ["hua_di"])
	match_modes.clear()
	if typeof(modes) == TYPE_ARRAY:
		for m in modes:
			var s := str(m)
			if s in ["gu_dou", "hua_di", "jian_mie"] and not match_modes.has(s):
				match_modes.append(s)
	if match_modes.is_empty():
		match_modes.append("hua_di")
	match_limit_s = maxi(600, int(lay.get("match_limit_s", 5400)))
	annihilate_goal = clampi(int(lay.get("annihilate_goal", 50)), 10, 1000)
	if match_modes.has("jian_mie"):
		auto_launch_enabled = true
		_auto_launch_locked = true
	_init_match_stats()

func _init_match_stats() -> void:
	match_stats.clear()
	for f in data.factions.get("factions", []):
		var fac := int(f.get("id", -1))
		if fac < 0:
			continue
		match_stats[fac] = {"built": 0, "kills": 0, "losses": 0, "occupy_score": 0.0, "reports": 0}

func _match_has(mode: String) -> bool:
	return match_modes.has(mode)

func _mode_names_joined() -> String:
	var names: PackedStringArray = []
	if _match_has("gu_dou"):
		names.append("蛊斗")
	if _match_has("hua_di"):
		names.append("画地")
	if _match_has("jian_mie"):
		names.append("歼灭")
	return "、".join(names) if names.size() > 0 else "画地"

func _stat_fac(fac: int) -> Dictionary:
	if not match_stats.has(fac):
		match_stats[fac] = {"built": 0, "kills": 0, "losses": 0, "occupy_score": 0.0, "reports": 0}
	return match_stats[fac]

func _note_match_kill(attacker: Dictionary, target: Dictionary) -> void:
	if _mp != null and _mp.active():
		var uid := str(target.get("id", ""))
		if uid == "" or _mp_seen_kills.has(uid):
			return
		var row := {
			"id": uid,
			"sys": str(target.get("sys", "")),
			"af": int(attacker.get("faction", -1)) if not attacker.is_empty() else -1,
			"vf": int(target.get("faction", -1)),
		}
		_mp_kill_log.append(row)
		_mp_apply_kill_event(row)
		return
	var tf := int(target.get("faction", -1))
	if tf >= 0:
		_stat_fac(tf)["losses"] = int(_stat_fac(tf).get("losses", 0)) + 1
	if not attacker.is_empty():
		var af := int(attacker.get("faction", -1))
		if af >= 0:
			_stat_fac(af)["kills"] = int(_stat_fac(af).get("kills", 0)) + 1

func _mp_apply_kill_event(row: Dictionary) -> void:
	var uid := str(row.get("id", ""))
	if uid == "" or _mp_seen_kills.has(uid):
		return
	_mp_seen_kills[uid] = true
	var vf := int(row.get("vf", -1))
	if vf >= 0:
		_stat_fac(vf)["losses"] = int(_stat_fac(vf).get("losses", 0)) + 1
	var af := int(row.get("af", -1))
	if af >= 0:
		_stat_fac(af)["kills"] = int(_stat_fac(af).get("kills", 0)) + 1

func _mp_take_kills(systems: Dictionary) -> Array:
	var keep: Array = []
	var out: Array = []
	for row_v in _mp_kill_log:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if systems.has(str(row.get("sys", ""))):
			out.append(row)
		else:
			keep.append(row)
	_mp_kill_log = keep
	return out

func _note_match_built(fac: int) -> void:
	if fac >= 0:
		_stat_fac(fac)["built"] = int(_stat_fac(fac).get("built", 0)) + 1

func _cell_occupy_points(kind: int) -> float:
	match kind:
		BoardTypes.CellKind.SOV:
			return 5.0
		BoardTypes.CellKind.STATION:
			return 4.0
		BoardTypes.CellKind.GATE:
			return 3.0
		BoardTypes.CellKind.RESOURCE:
			return 2.0
	return 0.0

func _tick_occupy_score(delta: float) -> void:
	if _mp != null and _mp.active() and not _mp.owns_global("victory"):
		return
	_occupy_tick_acc += delta
	while _occupy_tick_acc >= 1.0:
		_occupy_tick_acc -= 1.0
		for sid in map.systems.keys():
			for c in map.systems[sid]["cells"]:
				var ow := int(c.get("owner", 0))
				if ow == 0:
					continue
				var pts := _cell_occupy_points(int(c.get("kind", -1)))
				if pts <= 0.0:
					continue
				_stat_fac(ow)["occupy_score"] = float(_stat_fac(ow).get("occupy_score", 0.0)) + pts

func _format_sim_clock() -> String:
	var t := int(floor(_sim_clock))
	var h := t / 3600
	var m := (t % 3600) / 60
	var s := t % 60
	return "%d:%02d:%02d" % [h, m, s]

func _build_match_clock(layer: Control) -> void:
	_match_clock_lab = Button.new()
	_match_clock_lab.name = "MatchClock"
	_match_clock_lab.text = "0:00:00"
	_match_clock_lab.focus_mode = Control.FOCUS_NONE
	_match_clock_lab.custom_minimum_size = Vector2(120, 28)
	_apply_ui_font(_match_clock_lab)
	_match_clock_lab.pressed.connect(_open_scoreboard)
	layer.add_child(_match_clock_lab)
	_dilate_lab = Label.new()
	_dilate_lab.name = "TimeDilationHint"
	_dilate_lab.text = ""
	_dilate_lab.visible = false
	_dilate_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dilate_lab.modulate = Color(1.0, 0.82, 0.35, 0.95)
	_apply_ui_font(_dilate_lab)
	layer.add_child(_dilate_lab)
	_hp_batch = HP_BATCH_SCR.new()
	_hp_batch.name = "HpBarBatch"
	_hp_batch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_batch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hp_batch)
	_layout_match_clock()
	if not get_viewport().size_changed.is_connected(_layout_match_clock):
		get_viewport().size_changed.connect(_layout_match_clock)

func _layout_match_clock() -> void:
	if _match_clock_lab == null:
		return
	var sz := get_viewport().get_visible_rect().size
	_match_clock_lab.position = Vector2(sz.x * 0.5 - 60.0, 8.0)
	if _dilate_lab:
		_dilate_lab.position = Vector2(sz.x * 0.5 + 68.0, 10.0)
		_dilate_lab.size = Vector2(220, 24)

func _tick_match_flow(delta: float) -> void:
	if match_over:
		return
	if _match_clock_lab:
		_match_clock_lab.text = _format_sim_clock()
	_tick_occupy_score(delta)
	_sync_focus_lines()
	if _match_has("hua_di") and not _ten_min_warned:
		var left := float(match_limit_s) - _sim_clock
		if left <= 600.0 and left > 0.0:
			_ten_min_warned = true
			_chat_deputy("距离对局结束还有10分钟，本局以%s结算。" % _mode_names_joined())
	_tick_match_victory_checks()

func _every_faction_surrendered() -> bool:
	## All non-sleeper factions already failed this check. Empty rosters that still hold a station stay standing.
	var any := false
	for f in data.factions.get("factions", []):
		var fac := int(f.get("id", -1))
		if fac < 0 or bool(f.get("npc", false)):
			continue
		any = true
		if not _faction_out.has(fac):
			return false
	return any

func _standing_factions() -> Array:
	var standing: Array = []
	for f in data.factions.get("factions", []):
		var fac := int(f.get("id", -1))
		if fac < 0 or bool(f.get("npc", false)):
			continue
		if _faction_out.has(fac):
			continue
		var ships := _faction_live_ships(fac)
		var holds := _faction_holds_station(fac)
		if ships == 0 and holds:
			if not _defeat_spared_logged.has(fac):
				_defeat_spared_logged[fac] = true
		elif ships > 0:
			_defeat_spared_logged.erase(fac)
		if ships > 0 or holds:
			standing.append(fac)
		else:
			_defeat_faction(fac)
	return standing

func _cancel_all_alliances() -> void:
	var facs: Array = []
	for f in data.factions.get("factions", []):
		var fac := int(f.get("id", -1))
		if fac < 0 or bool(f.get("npc", false)):
			continue
		facs.append(fac)
	for i in range(facs.size()):
		for j in range(i + 1, facs.size()):
			_set_alliance(int(facs[i]), int(facs[j]), false)

func _sov_owner_counts() -> Dictionary:
	var counts: Dictionary = {}
	var total := 0
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c.get("kind", -1)) != BoardTypes.CellKind.SOV:
				continue
			total += 1
			var ow := int(c.get("owner", 0))
			if ow == 0:
				continue
			counts[ow] = int(counts.get(ow, 0)) + 1
	counts["_total"] = total
	return counts

func _faction_owns_all_sov(fac: int) -> bool:
	var sc := _sov_owner_counts()
	var total := int(sc.get("_total", 0))
	if total <= 0:
		return false
	return int(sc.get(fac, 0)) == total

func _tick_match_victory_checks() -> void:
	if match_over or not _mp_owns("victory"):
		return
	var standing := _standing_factions()
	if _every_faction_surrendered():
		_end_match(-1, "同时投降")
		return
	if _match_has("gu_dou"):
		if standing.size() == 2:
			_cancel_all_alliances()
		if standing.size() <= 1:
			_end_match(int(standing[0]) if standing.size() == 1 else -1, "蛊斗：最后存活势力获胜")
			return
	if _match_has("hua_di"):
		for fac in standing:
			if _faction_owns_all_sov(int(fac)):
				_end_match(int(fac), "画地：占领全部主权")
				return
		if _sim_clock >= float(match_limit_s):
			var best_fac := -1
			var best_sc := -1.0
			for fac2 in standing:
				var sc2 := float(_stat_fac(int(fac2)).get("occupy_score", 0.0))
				if sc2 > best_sc:
					best_sc = sc2
					best_fac = int(fac2)
			_end_match(best_fac, "画地：时限到占领分最高")
			return
	if _match_has("jian_mie"):
		for fac3 in standing:
			if int(_stat_fac(int(fac3)).get("kills", 0)) >= annihilate_goal:
				_end_match(int(fac3), "歼灭：击毁数达标")
				return

func _end_match(winner: int, reason: String) -> void:
	if match_over:
		return
	match_over = true
	_winner_faction = winner
	match_msg = reason
	_mp_match_end(winner, reason)
	print(match_msg)
	_show_settlement()

func _open_scoreboard() -> void:
	if _scoreboard_win != null and is_instance_valid(_scoreboard_win):
		_scoreboard_win.popup_centered(Vector2i(720, 420))
		_refresh_scoreboard_body()
		return
	_scoreboard_win = Window.new()
	_scoreboard_win.title = "计分板"
	_scoreboard_win.size = Vector2i(720, 420)
	_scoreboard_win.close_requested.connect(func() -> void:
		_scoreboard_win.hide()
	)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scoreboard_win.add_child(scroll)
	var body := RichTextLabel.new()
	body.name = "Body"
	body.bbcode_enabled = true
	body.fit_content = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_ui_font(body)
	scroll.add_child(body)
	add_child(_scoreboard_win)
	_refresh_scoreboard_body()
	_scoreboard_win.popup_centered()

func _refresh_scoreboard_body() -> void:
	if _scoreboard_win == null:
		return
	var body := _scoreboard_win.find_child("Body", true, false) as RichTextLabel
	if body == null:
		return
	_sync_report_counts()
	var lines: PackedStringArray = ["[b]计分板[/b]（含冬眠者）", "势力 | 制造 | 击毁 | 损失 | 占领分 | 战报"]
	for f in data.factions.get("factions", []):
		var fac := int(f.get("id", -1))
		if fac < 0:
			continue
		var st := _stat_fac(fac)
		lines.append("%s | %d | %d | %d | %.0f | %d" % [
			_faction_label(fac), int(st.get("built", 0)), int(st.get("kills", 0)),
			int(st.get("losses", 0)), float(st.get("occupy_score", 0.0)), int(st.get("reports", 0))
		])
	body.text = "\n".join(lines)

func _sync_report_counts() -> void:
	if br_tracker == null:
		return
	## Best-effort: count all report rows if tracker exposes them.
	var all_n := 0
	if br_tracker.has_method("all_reports"):
		var arr = br_tracker.call("all_reports")
		if typeof(arr) == TYPE_ARRAY:
			all_n = arr.size()
	elif "reports" in br_tracker:
		var r = br_tracker.get("reports")
		if typeof(r) == TYPE_ARRAY:
			all_n = r.size()
	for fac in match_stats.keys():
		_stat_fac(int(fac))["reports"] = all_n

func _show_settlement() -> void:
	if _settle_layer != null and is_instance_valid(_settle_layer):
		_settle_layer.visible = true
		_mp_after_settlement()
		return
	_settle_layer = Control.new()
	_settle_layer.name = "SettlementLayer"
	_settle_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settle_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	_settle_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(640, 420)
	panel.position = Vector2(-320, -210)
	_settle_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	var wname := _faction_label(_winner_faction) if _winner_faction >= 0 else "—"
	title.text = "结算 · %s 获胜 · %s" % [wname, match_msg]
	_apply_ui_font(title)
	box.add_child(title)
	var rtl := RichTextLabel.new()
	rtl.name = "SettleBody"
	rtl.bbcode_enabled = true
	rtl.custom_minimum_size = Vector2(600, 240)
	rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_ui_font(rtl)
	box.add_child(rtl)
	var row := HBoxContainer.new()
	box.add_child(row)
	var detail_btn := Button.new()
	detail_btn.text = "详情"
	detail_btn.pressed.connect(_toggle_settle_detail)
	row.add_child(detail_btn)
	var dl := Button.new()
	dl.text = "下载 CSV"
	dl.pressed.connect(_download_settle_csv)
	row.add_child(dl)
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(func() -> void:
		_settle_layer.visible = false
	)
	row.add_child(close_btn)
	if hud:
		hud.add_child(_settle_layer)
	else:
		add_child(_settle_layer)
	_fill_settle_summary(false)
	_mp_after_settlement()

func _fill_settle_summary(with_reports: bool) -> void:
	if _settle_layer == null:
		return
	var rtl := _settle_layer.find_child("SettleBody", true, false) as RichTextLabel
	if rtl == null:
		return
	_sync_report_counts()
	var lines: PackedStringArray = ["势力 | 制造 | 击毁 | 损失 | 占领分"]
	for f in data.factions.get("factions", []):
		var fac := int(f.get("id", -1))
		if fac < 0 or bool(f.get("npc", false)):
			continue
		var st := _stat_fac(fac)
		lines.append("%s | %d | %d | %d | %.0f" % [
			_faction_label(fac), int(st.get("built", 0)), int(st.get("kills", 0)),
			int(st.get("losses", 0)), float(st.get("occupy_score", 0.0))
		])
	if with_reports and br_tracker != null:
		lines.append("")
		lines.append("[b]战报[/b]")
		var reports: Array = []
		if br_tracker.has_method("all_reports"):
			reports = br_tracker.call("all_reports")
		elif "reports" in br_tracker:
			var r2 = br_tracker.get("reports")
			if typeof(r2) == TYPE_ARRAY:
				reports = r2
		for r in reports:
			if typeof(r) == TYPE_DICTIONARY:
				lines.append(str(r.get("text", r.get("line", str(r)))))
			else:
				lines.append(str(r))
	rtl.text = "\n".join(lines)

func _toggle_settle_detail() -> void:
	_settle_detail_on = not _settle_detail_on
	_fill_settle_summary(_settle_detail_on)

func _download_settle_csv() -> void:
	var path := "user://match_settlement_%d.csv" % int(Time.get_unix_time_from_system())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("section,faction,built,kills,losses,occupy_score,reports")
	for fac in match_stats.keys():
		var st := _stat_fac(int(fac))
		var npc := data.is_npc_faction(int(fac))
		if npc:
			continue
		f.store_line("settle,%s,%d,%d,%d,%.0f,%d" % [
			_faction_label(int(fac)), int(st.get("built", 0)), int(st.get("kills", 0)),
			int(st.get("losses", 0)), float(st.get("occupy_score", 0.0)), int(st.get("reports", 0))
		])
	f.store_line("report,text,,,,")
	var reports: Array = []
	if br_tracker != null:
		if br_tracker.has_method("all_reports"):
			reports = br_tracker.call("all_reports")
		elif "reports" in br_tracker:
			var r3 = br_tracker.get("reports")
			if typeof(r3) == TYPE_ARRAY:
				reports = r3
	for r in reports:
		var line := ""
		if typeof(r) == TYPE_DICTIONARY:
			line = str(r.get("text", r.get("line", str(r))))
		else:
			line = str(r)
		line = line.replace("\"", "'").replace(",", "，")
		f.store_line("report,\"%s\",,,," % line)
	f.close()
	_chat_append("结算 CSV 已保存：%s" % path)

func _apply_undock_lock_on_dock(u: Dictionary) -> void:
	var inst: Dictionary = u.get("inst", {})
	if inst.is_empty():
		return
	var max_hp := float(inst.get("max_s", 0)) + float(inst.get("max_a", 0)) + float(inst.get("max_h", 0))
	var cur_hp := float(inst.get("shield", 0)) + float(inst.get("armor", 0)) + float(inst.get("structure", 0))
	var missing := 0.0 if max_hp <= 0.001 else clampf(1.0 - cur_hp / max_hp, 0.0, 1.0)
	var bands := int(floor(missing / 0.10 + 0.0001))
	var lock_s := minf(20.0, float(bands) * 10.0)
	inst["undock_ready_at"] = _sim_clock + lock_s

func _take_ship_for_launch(p: Dictionary, ship_id: String) -> Dictionary:
	## Prefer unlocked same-type hull; locked same ship waits.
	var def: Dictionary = data.ship_def(ship_id)
	var ton: String = def.get("tonnage", "")
	var store: Array = p["storage"].get(ton, [])
	var unlocked_i := -1
	var any_i := -1
	for i in store.size():
		if str(store[i].get("ship_id", "")) != ship_id:
			continue
		if any_i < 0:
			any_i = i
		if float(store[i].get("undock_ready_at", 0.0)) <= _sim_clock + 0.001:
			unlocked_i = i
			break
	var pick := unlocked_i if unlocked_i >= 0 else any_i
	if pick < 0:
		return {}
	if unlocked_i < 0 and float(store[pick].get("undock_ready_at", 0.0)) > _sim_clock + 0.001:
		return {}
	var inst: Dictionary = store[pick]
	store.remove_at(pick)
	return inst

func _try_auto_swap_unlocked_same_ship(p: Dictionary, ship_id: String) -> Dictionary:
	return _take_ship_for_launch(p, ship_id)

func _damage_float_pos(u: Dictionary) -> Vector3:
	## Tactical top-down: numbers sit on the nameplate, not the hull.
	if cam != null and cam.tactical_mode and not cam.starmap_mode and unit_nodes.has(u.get("id", "")):
		var oh = unit_nodes[u["id"]].get_node_or_null("Overhead")
		if oh is Node3D:
			return (oh as Node3D).global_position
	return u.get("pos", Vector3.ZERO)

func _sync_focus_lines() -> void:
	## Thin red line to each finished weapon lock. PD has no lock and is not drawn.
	var live: Dictionary = {}
	var plate := cam != null and cam.tactical_mode
	if _lock_line_mat == null:
		_lock_line_mat = StandardMaterial3D.new()
		_lock_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_lock_line_mat.albedo_color = Color(1.0, 0.15, 0.12, 0.95)
		_lock_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_lock_line_mat.vertex_color_use_as_albedo = true
	for u in units:
		if not u.get("alive", false):
			continue
		var uid := str(u.get("id", ""))
		var seen: Dictionary = {}
		for w in u.get("weapons", []):
			var lid := str(w.get("lock_id", ""))
			if lid == "" or seen.has(lid):
				continue
			if float(w.get("lock_t", 0.0)) + 0.02 < float(w.get("lock_need", 1.0)):
				continue
			var tgt = _unit_by_id(lid)
			if tgt.is_empty() or not tgt.get("alive", false):
				continue
			seen[lid] = true
			var key := "%s>%s" % [uid, lid]
			live[key] = true
			if not _focus_lines.has(key):
				var mi := MeshInstance3D.new()
				mi.name = "LockLine"
				mi.material_override = _lock_line_mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				_focus_lines[key] = mi
			_set_lock_line_mesh(_focus_lines[key], _focus_line_pos(u, plate), _focus_line_pos(tgt, plate))
	for k in _focus_lines.keys():
		if not live.has(k):
			var n: Node = _focus_lines[k]
			if is_instance_valid(n):
				n.queue_free()
			_focus_lines.erase(k)

func _set_lock_line_mesh(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	if mi.has_meta("la"):
		var la: Vector3 = mi.get_meta("la")
		var lb: Vector3 = mi.get_meta("lb")
		if la.distance_squared_to(a) < 0.35 and lb.distance_squared_to(b) < 0.35:
			return
	mi.set_meta("la", a)
	mi.set_meta("lb", b)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.set_color(Color(1.0, 0.2, 0.15, 0.95))
	st.add_vertex(a + Vector3(0, 0.35, 0))
	st.add_vertex(b + Vector3(0, 0.35, 0))
	mi.mesh = st.commit()

func _focus_line_pos(u: Dictionary, use_plate: bool) -> Vector3:
	if use_plate:
		## Nameplate-ish: slightly above unit callout / system cell.
		var p: Vector3 = u.get("pos", Vector3.ZERO)
		if unit_nodes.has(u.get("id", "")):
			var oh = unit_nodes[u["id"]].get_node_or_null("Overhead")
			if oh is Node3D:
				return (oh as Node3D).global_position + Vector3(0, 0.4, 0)
		return p + Vector3(0, 2.2, 0)
	if unit_nodes.has(u.get("id", "")):
		return (unit_nodes[u["id"]] as Node3D).global_position
	return u.get("pos", Vector3.ZERO)

func _note_enemy_deputy_fleet_wipe(attacker: Dictionary, target: Dictionary) -> void:
	if attacker.is_empty() or target.is_empty():
		return
	var af := int(attacker.get("faction", -1))
	var tf := int(target.get("faction", -1))
	if af != viewer_faction or tf == viewer_faction:
		return
	if not faction_ai.has(tf):
		return
	var ctrl: BoardAiController = faction_ai[tf]
	var tid := str(target.get("id", ""))
	var role_n: Dictionary = {}
	var role_i: Dictionary = {}
	for f0 in ctrl.fleets:
		var r0 := str(f0.get("role", "main"))
		role_n[r0] = int(role_n.get(r0, 0)) + 1
	for f in ctrl.fleets:
		var role := str(f.get("role", "main"))
		var ix := int(role_i.get(role, 0))
		role_i[role] = ix + 1
		var members: Array = f.get("members", [])
		var has := false
		for m in members:
			if str(m) == tid:
				has = true
				break
		if not has:
			continue
		var alive_left := 0
		for m2 in members:
			var ou = _unit_by_id(str(m2))
			if ou.is_empty() or not ou.get("alive", false):
				continue
			if str(ou.get("id", "")) == tid:
				continue
			alive_left += 1
		if alive_left > 0:
			continue
		var my_dep := _deputy_display_name(str(player_deputy.deputy_id) if player_deputy else "yang")
		var enemy_dep := _deputy_display_name(str(ctrl.deputy_id))
		var legion := _faction_label(tf)
		if role == "attrition":
			_chat_append("%s：[%s]的[战术换损舰队]已被全歼，创真够莽的。" % [my_dep, legion])
		else:
			var fname := _fleet_role_label(role, ix, int(role_n.get(role, 1)))
			_chat_append("%s：[%s]的[%s]已被全歼，这下有%s好受的！" % [my_dep, legion, fname, enemy_dep])
		return

func _open_cell_menu(sys: String, cell: int, screen_pos: Vector2) -> void:
	popup.clear()
	popup.set_meta("pilot", "")
	popup.set_meta("unit", "")
	popup.set_meta("cell_sys", sys)
	popup.set_meta("cell_i", cell)
	popup.add_item("全部舰船向此移动", 501)
	var can_home := false
	if map.systems.has(sys):
		var cells: Array = map.systems[sys]["cells"]
		if cell >= 0 and cell < cells.size():
			var c: Dictionary = cells[cell]
			can_home = int(c.get("kind", -1)) == BoardTypes.CellKind.STATION \
				and int(c.get("owner", 0)) == viewer_faction
	popup.add_item("设为所有人初始空间站", 502)
	popup.set_item_disabled(popup.get_item_index(502), not can_home)
	popup.add_item("设为集结点", 503)
	popup.add_item("取消集结点", 504)
	popup.set_item_disabled(popup.get_item_index(504), not rally_by_fac.has(viewer_faction))
	popup.position = Vector2i(screen_pos)
	popup.popup()

func _on_cell_menu(id: int) -> void:
	var sys := str(popup.get_meta("cell_sys", ""))
	var cell := int(popup.get_meta("cell_i", -1))
	if sys == "" or cell < 0:
		return
	if id == 501:
		for u in units:
			if not u.get("alive", false):
				continue
			if int(u.get("faction", -1)) != viewer_faction:
				continue
			if bool(u.get("garrison", false)) or not bool(u.get("commandable", true)):
				continue
			_queue_unit_move(u, sys, cell)
	elif id == 502:
		for p in pilots:
			if int(p.get("faction", -1)) != viewer_faction:
				continue
			p["home_station"] = sys
			if bool(p.get("in_station", false)):
				p["current_station"] = sys
		_rebuild_hud_list()
	elif id == 503:
		rally_by_fac[viewer_faction] = {"sys": sys, "cell": cell}
		# #region agent log
		_dbg59("RALLY", "board_root._on_cell_menu", "set", {
			"sys": sys, "cell": cell, "fac": viewer_faction, "runId": "rally"
		})
		# #endregion
	elif id == 504:
		rally_by_fac.erase(viewer_faction)
		# #region agent log
		_dbg59("RALLY", "board_root._on_cell_menu", "clear", {
			"fac": viewer_faction, "runId": "rally"
		})
		# #endregion

# --- Input ---
func _input(event: InputEvent) -> void:
	## Menu window is its own viewport. Do not swallow clicks while paused.
	if sim_paused:
		return
	if _handle_touch_input(event):
		return
	## LMB: latch press/release only. UI hit-test gates the press, never the release
	## (Mindustry keyRelease(select) commits the rect even after the cursor enters UI).
	if event is InputEventMouseMotion and _marker_drag_kind != "":
		_marker_drag_motion(_event_pos(event))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _left_dragging:
		if _event_pos(event).distance_to(_left_drag_start) >= BoardTypes.BOX_DRAG_PX:
			_left_box_selecting = true
		return
	if event is InputEventMouseMotion and _ui_scroll and _is_mobile_board() and event.device >= 0:
		_apply_ui_scroll(_event_pos(event))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and dragging and _is_mobile_board() and _touch_pts.is_empty() and event.device >= 0:
		var mm := event as InputEventMouseMotion
		if cam and not _pointer_blocks_gesture_start(mm.position):
			cam.pan_by_screen_delta(mm.relative)
			_touch_panning = true
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and dragging and not _is_mobile_board():
		if _event_pos(event).distance_to(drag_start) >= BoardTypes.BOX_DRAG_PX:
			box_selecting = true
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var on_ui := _pointer_blocks_gesture_start(mb.position)
			## Board-plane marker quad: grab before select/box gestures.
			if not mb.pressed and _marker_drag_kind != "":
				# #region agent log
				_dbg59("MKR", "board_root._input", "drag_end", {
					"kind": _marker_drag_kind, "pos": str(map_markers.get(_marker_drag_kind, {}).get("pos", Vector3.ZERO)),
					"runId": "post-fix"
				})
				# #endregion
				_marker_drag_kind = ""
				get_viewport().set_input_as_handled()
				return
			if mb.pressed and not on_ui:
				var mk := _marker_hit_kind(mb.position)
				if mk != "":
					_marker_handles_on = true
					_marker_drag_kind = mk
					_marker_drag_prev = _screen_to_ground(mb.position)
					get_viewport().set_input_as_handled()
					return
			if mb.pressed:
				_lmb_press_latch = true
				_lmb_press_pos = mb.position
				_lmb_press_on_ui = on_ui
				_lmb_press_on_left_list = _pointer_on_left_list(mb.position)
				if _is_mobile_board() and mb.device >= 0:
					var scroll_at := _scroll_at(mb.position)
					if scroll_at:
						_ui_scroll = scroll_at
						_ui_scroll_last = mb.position
						_lmb_press_on_left_list = false
						_lmb_press_on_ui = true
			elif _ui_scroll and mb.device >= 0:
				_ui_scroll = null
			else:
				_lmb_release_latch = true
				_lmb_release_pos = mb.position
			## Diplomacy / bottom bar must receive the click. Swallow only board clicks.
			if not on_ui:
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
	if sim_paused:
		return
	if event is InputEventKey and event.pressed:
		_handle_key(event as InputEventKey)

func _handle_touch_input(event: InputEvent) -> bool:
	## Returns true when the event was consumed as touch.
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var idx := int(st.index)
		if st.pressed:
			var scroll_at := _scroll_at(st.position)
			if scroll_at:
				_ui_scroll = scroll_at
				_ui_scroll_last = st.position
				return true
			var blocked := _pointer_blocks_gesture_start(st.position)
			# #region agent log
			_dbg59("A", "board_root._handle_touch_input", "screen_touch_press", {
				"idx": idx, "pos": [st.position.x, st.position.y], "blocked": blocked,
				"hover": str(get_viewport().gui_get_hovered_control().name) if get_viewport() and get_viewport().gui_get_hovered_control() else "",
				"pts": _touch_pts.size(), "runId": "pre-fix"
			})
			# #endregion
			if blocked:
				return true
			_touch_pts[idx] = {
				"pos": st.position,
				"t0": Time.get_ticks_msec() / 1000.0,
				"moved": false,
			}
			_touch_long_fired.erase(idx)
			if _touch_pts.size() >= 2:
				_touch_panning = false
				_pinch_prev_dist = -1.0
			return true
		## Release
		if _ui_scroll != null and _touch_pts.is_empty():
			_ui_scroll = null
			return true
		var info: Dictionary = _touch_pts.get(idx, {})
		_touch_pts.erase(idx)
		var was_long := bool(_touch_long_fired.get(idx, false))
		var was_growing := bool(info.get("growing", false))
		_touch_long_fired.erase(idx)
		_hold_grow = false
		if _touch_pts.size() < 2:
			_pinch_prev_dist = -1.0
		if _touch_pts.is_empty():
			_touch_panning = false
		if was_growing:
			var origin: Vector2 = info.get("origin", st.position)
			var half := float(info.get("half", 0.0))
			_suppress_lmb_until = Time.get_ticks_msec() / 1000.0 + 0.35
			_box_select(origin - Vector2(half, half), origin + Vector2(half, half))
			return true
		if info.is_empty() or was_long or bool(info.get("moved", false)):
			return true
		if _touch_pts.size() == 0:
			## Single-finger tap → LMB click
			_lmb_press_latch = true
			_lmb_press_pos = st.position
			_lmb_press_on_ui = false
			_lmb_release_latch = true
			_lmb_release_pos = st.position
		return true
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _ui_scroll != null:
			_apply_ui_scroll(sd.position)
			get_viewport().set_input_as_handled()
			return true
		var idx2 := int(sd.index)
		if not _touch_pts.has(idx2):
			return true
		var info2: Dictionary = _touch_pts[idx2]
		var prev_pos: Vector2 = info2.get("pos", sd.position)
		var pos_delta: Vector2 = sd.position - prev_pos
		info2["pos"] = sd.position
		var slop := _touch_slop_px()
		if sd.relative.length() >= slop * 0.5 or pos_delta.length() >= slop:
			info2["moved"] = true
			info2["growing"] = false
			_hold_grow = false
		_touch_pts[idx2] = info2
		if _touch_pts.size() >= 2:
			# #region agent log
			if Engine.get_process_frames() % 10 == 0:
				_dbg59("E", "board_root._handle_touch_input", "pinch_path", {
					"pts": _touch_pts.size(), "rel": [sd.relative.x, sd.relative.y],
					"pos_d": [pos_delta.x, pos_delta.y], "runId": "pre-fix"
				})
			# #endregion
			_apply_pinch_or_rotate()
			return true
		## Single-finger drag → middle-button pan
		if cam and bool(info2.get("moved", false)):
			_touch_panning = true
			var pan_d: Vector2 = sd.relative
			## H-C: stretch/Android often reports relative=0; fall back to position delta.
			if pan_d.length_squared() < 0.0001:
				pan_d = pos_delta
			# #region agent log
			if Engine.get_process_frames() % 6 == 0:
				var look0: Vector3 = cam.look_at_point if cam else Vector3.ZERO
				cam.pan_by_screen_delta(pan_d)
				_dbg59("C", "board_root._handle_touch_input", "single_drag_pan", {
					"rel": [sd.relative.x, sd.relative.y], "pos_d": [pos_delta.x, pos_delta.y],
					"used": [pan_d.x, pan_d.y], "tac": cam.tactical_mode if cam else false,
					"look0": [look0.x, look0.z], "look1": [cam.look_at_point.x, cam.look_at_point.z],
					"runId": "pre-fix"
				})
			else:
				cam.pan_by_screen_delta(pan_d)
			# #endregion
		else:
			# #region agent log
			if Engine.get_process_frames() % 15 == 0:
				_dbg59("A", "board_root._handle_touch_input", "drag_no_pan", {
					"moved": bool(info2.get("moved", false)), "has_cam": cam != null,
					"rel": [sd.relative.x, sd.relative.y], "pos_d": [pos_delta.x, pos_delta.y],
					"runId": "pre-fix"
				})
			# #endregion
		return true
	# #region agent log
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if Engine.get_process_frames() % 20 == 0:
			_dbg59("A", "board_root._handle_touch_input", "mouse_lmb_drag_no_screen", {
				"pos": [_event_pos(event).x, _event_pos(event).y],
				"pts": _touch_pts.size(), "dragging": dragging,
				"feat_mobile": OS.has_feature("mobile"),
				"runId": "pre-fix"
			})
	# #endregion
	return false

func _apply_pinch_or_rotate() -> void:
	if cam == null or _touch_pts.size() < 2:
		return
	var keys: Array = _touch_pts.keys()
	var a: Dictionary = _touch_pts[keys[0]]
	var b: Dictionary = _touch_pts[keys[1]]
	var pa: Vector2 = a["pos"]
	var pb: Vector2 = b["pos"]
	var dist := pa.distance_to(pb)
	var ang := (pb - pa).angle()
	if _pinch_prev_dist < 0.0:
		_pinch_prev_dist = dist
		_pinch_prev_angle = ang
		return
	var dd := dist - _pinch_prev_dist
	if absf(dd) > 1.5:
		## Pinch open → zoom out (wheel down); pinch close → zoom in.
		var factor := 1.0 - clampf(dd * 0.004, -0.12, 0.12)
		cam.zoom_by_factor(factor)
	var dang := ang - _pinch_prev_angle
	while dang > PI:
		dang -= TAU
	while dang < -PI:
		dang += TAU
	## Two-finger rotate: tactical overview only.
	if cam.tactical_mode and not cam.starmap_mode and absf(dang) > 0.01:
		cam.add_tactical_yaw(dang)
	_pinch_prev_dist = dist
	_pinch_prev_angle = ang

func _is_mobile_board() -> bool:
	return OS.get_name() == "Android" or OS.has_feature("mobile")


func _touch_slop_px() -> float:
	## 1.0 keeps the 8px split. Higher sensitivity means a smaller move counts as a drag.
	return BoardTypes.BOX_DRAG_PX / maxf(PlayerSettings.get_op_sensitivity(), 0.1)


func _tick_touch_long_press() -> void:
	if _touch_pts.size() != 1:
		_hold_grow = false
		return
	var idx = _touch_pts.keys()[0]
	if bool(_touch_long_fired.get(idx, false)):
		return
	var info: Dictionary = _touch_pts[idx]
	if bool(info.get("moved", false)):
		_hold_grow = false
		return
	var now := Time.get_ticks_msec() / 1000.0
	var held := now - float(info.get("t0", 0.0))
	if held < HOLD_ARM_S:
		return
	if _is_mobile_board():
		if not bool(info.get("growing", false)):
			info["growing"] = true
			info["origin"] = info.get("pos", Vector2.ZERO)
			info["half"] = 8.0
			info["grow_t"] = now
		else:
			var dt := now - float(info.get("grow_t", now))
			info["grow_t"] = now
			info["half"] = float(info.get("half", 8.0)) + HOLD_GROW_PX * dt
		_touch_pts[idx] = info
		_hold_grow = true
		_hold_origin = info.get("origin", Vector2.ZERO)
		_hold_half = float(info.get("half", 8.0))
		return
	_touch_long_fired[idx] = true
	var pos: Vector2 = info.get("pos", Vector2.ZERO)
	var mb = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = true
	mb.position = pos
	_handle_mouse_button(mb)
	mb.pressed = false
	_handle_mouse_button(mb)

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
	if _hover_is_hud_control():
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

func _scroll_at(pos: Vector2) -> Control:
	var candidates: Array = []
	if left_scroll:
		candidates.append(left_scroll)
	if chat_scroll:
		candidates.append(chat_scroll)
	if bottom_bar:
		candidates.append(bottom_bar)
	if detail and detail.visible:
		candidates.append(detail)
	if hud:
		var br := hud.find_child("BrScroll", true, false) as Control
		if br:
			candidates.append(br)
	var best: Control = null
	var best_area := 1.0e20
	for c in candidates:
		var node := c as Control
		if node == null or not is_instance_valid(node) or not node.visible:
			continue
		var rect := node.get_global_rect()
		if rect.has_point(pos) and rect.get_area() < best_area:
			best = node
			best_area = rect.get_area()
	return best


func _apply_ui_scroll(pos: Vector2) -> void:
	if _ui_scroll == null or not is_instance_valid(_ui_scroll):
		return
	var delta := pos - _ui_scroll_last
	_ui_scroll_last = pos
	if _ui_scroll is ScrollContainer:
		var sc := _ui_scroll as ScrollContainer
		if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			sc.scroll_vertical = int(round(float(sc.scroll_vertical) - delta.y))
		if sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			sc.scroll_horizontal = int(round(float(sc.scroll_horizontal) - delta.x))
	elif _ui_scroll is RichTextLabel:
		var bar := (_ui_scroll as RichTextLabel).get_v_scroll_bar()
		if bar:
			bar.value -= delta.y


func _pointer_on_left_list(pos: Vector2) -> bool:
	if left_scroll == null or not is_instance_valid(left_scroll):
		return false
	return Rect2(left_scroll.global_position, left_scroll.size).has_point(pos)


func _consume_lmb_gesture() -> void:
	## Same-frame press+release both land here (input runs before process).
	var started_this_frame := false
	if _lmb_press_latch:
		_lmb_press_latch = false
		if _lmb_press_on_left_list:
			_left_drag_start = _lmb_press_pos
			_left_dragging = true
			_left_box_selecting = false
			started_this_frame = true
		elif not _lmb_press_on_ui:
			drag_start = _lmb_press_pos
			dragging = true
			box_selecting = false
			started_this_frame = true
	var lmb_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var vp_held := get_viewport()
	var held: Vector2 = vp_held.get_mouse_position() if vp_held else drag_start
	if _left_dragging and lmb_down:
		if held.distance_to(_left_drag_start) >= BoardTypes.BOX_DRAG_PX:
			_left_box_selecting = true
	if dragging and lmb_down and not _is_mobile_board():
		if held.distance_to(drag_start) >= BoardTypes.BOX_DRAG_PX:
			box_selecting = true
	## Lost mouse-up (focus change / event swallowed): button already up while dragging.
	## Skip the start frame — button state may not be latched yet.
	if (_left_dragging or dragging) and not lmb_down and not _lmb_release_latch and not started_this_frame:
		_lmb_release_latch = true
		_lmb_release_pos = held
		# #region agent log
		_dbg59("GEST", "board_root._consume_lmb_gesture", "lmb_up_synth", {
			"pos": [_lmb_release_pos.x, _lmb_release_pos.y], "box": box_selecting,
			"left": _left_box_selecting, "runId": "gesture-poll"
		})
		# #endregion
	if _lmb_release_latch:
		var rel := _lmb_release_pos
		_lmb_release_latch = false
		if _left_dragging:
			_finish_left_list_gesture(rel)
		elif dragging:
			_finish_lmb_gesture(rel)

func _finish_left_list_gesture(pos: Vector2) -> void:
	var dist := pos.distance_to(_left_drag_start)
	var was_box := _left_box_selecting or dist >= BoardTypes.BOX_DRAG_PX
	_left_dragging = false
	_left_box_selecting = false
	_lmb_press_on_left_list = false
	if was_box:
		_left_box_select(_left_drag_start, pos)
	# Click without box: row gui_input already selected on press.


func _left_box_select(a: Vector2, b: Vector2) -> void:
	var box := Rect2(a, b - a).abs()
	if box.size.x < 2.0 and box.size.y < 2.0:
		return
	if left_rows == null:
		return
	var found: Array = []
	for row in left_rows.get_children():
		if not (row is Control):
			continue
		var rr: Rect2 = (row as Control).get_global_rect()
		if rr.size.y < 1.0:
			continue
		var hit: Rect2 = box.intersection(rr)
		if hit.size.y < rr.size.y * 0.7:
			continue
		var pid := str(row.get_meta("pilot", ""))
		var p: Dictionary = _pilot_by_id(pid)
		if p.is_empty():
			continue
		var u: Dictionary = _unit_by_id(str(p.get("unit_id", "")))
		if u.is_empty() or not bool(u.get("alive", false)):
			continue
		if int(u.get("faction", -1)) != viewer_faction:
			continue
		if bool(u.get("garrison", false)) or not bool(u.get("commandable", true)):
			continue
		var uid := str(u.get("id", ""))
		if uid != "" and not found.has(uid):
			found.append(uid)
	if not found.is_empty():
		selection = found
		_detail_dirty = true
		_update_detail()
		# #region agent log
		_dbg59("SEL", "board_root._left_box_select", "left_box", {
			"n": found.size(), "ids": found.duplicate(), "runId": "left-box"
		})
		# #endregion


func _finish_lmb_gesture(pos: Vector2) -> void:
	var dist := pos.distance_to(drag_start)
	var was_box := false
	if not _is_mobile_board():
		was_box = box_selecting or dist >= BoardTypes.BOX_DRAG_PX
	dragging = false
	box_selecting = false
	if Time.get_ticks_msec() / 1000.0 < _suppress_lmb_until:
		return
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

func _hover_is_hud_control() -> bool:
	## Pick target, not the layout rect. A zero-size rect used to let _input swallow the click.
	var vp := get_viewport()
	if vp == null:
		return false
	var hovered: Control = vp.gui_get_hovered_control()
	while hovered != null:
		if _box_overlay and hovered == _box_overlay:
			return false
		var nm := str(hovered.name)
		if nm == "BottomBar" or nm == "SoftKeyBar" or nm == "DiploBtn" or nm == "DiploPanel" \
				or nm == "MenuBtn" or nm == "GameMenuWindow" \
				or nm == "DeputyPanel" or nm == "ChatPanel" or nm == "LeftCol" or nm == "RightCol" \
				or nm == "Detail":
			return true
		if hovered is Button and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return true
		hovered = hovered.get_parent() as Control
	return false

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
	for extra in [bottom_bar, chat_panel, deputy_panel, diplo_btn, diplo_panel, menu_btn, _zoom_col]:
		if extra and is_instance_valid(extra) and extra.visible:
			if extra.get_global_rect().grow(2.0).has_point(pos):
				return true
	return false

func _handle_key(e: InputEventKey) -> void:
	var ctrl_mod := e.ctrl_pressed or soft_ctrl_sticky
	if ctrl_mod and e.keycode >= KEY_0 and e.keycode <= KEY_9:
		var g = e.keycode - KEY_0
		_assign_control_group(g)
		if soft_ctrl_sticky and not e.ctrl_pressed:
			_clear_soft_ctrl_sticky()
		return
	if not e.ctrl_pressed and e.keycode >= KEY_0 and e.keycode <= KEY_9:
		var g2 = e.keycode - KEY_0
		_select_control_group(g2, true)
		return

func _assign_control_group(g: int) -> void:
	var sel: Array = []
	for id in selection:
		var u = _unit_by_id(str(id))
		if u.is_empty() or int(u.get("faction", 0)) != viewer_faction:
			continue
		sel.append(str(id))
	if sel.is_empty():
		return
	var all_this := true
	var any_num := false
	var any_plain := false
	for id in sel:
		var u2 = _unit_by_id(str(id))
		var cg := int(u2.get("ctrl_group", -1))
		if cg != g:
			all_this = false
		if cg < 0:
			any_plain = true
		else:
			any_num = true
	## All already this number: cancel. Mixed or other: write this number onto everyone.
	var clear := all_this and not (any_num and any_plain and false)
	if any_num and any_plain:
		clear = false
	if all_this:
		clear = true
	for id in sel:
		_set_unit_ctrl_group(str(id), -1 if clear else g)
	_rebuild_group_dict()
	_refresh_all_group_badges()
	_rebuild_hud_list()
	if deputy_group >= 0:
		_rebuild_player_deputy()
		_rebalance_deputy_resources()
	# #region agent log
	_dbg59("GRP", "board_root._assign_control_group", "set_group", {
		"g": g, "n": (control_groups[g] as Array).size(), "runId": "ctrl-group"
	})
	# #endregion

func _set_unit_ctrl_group(uid: String, g: int) -> void:
	var u = _unit_by_id(uid)
	if u.is_empty():
		return
	u["ctrl_group"] = g
	_mp_on_group(uid, g)
	var p = _pilot_by_id(str(u.get("pilot_id", "")))
	if not p.is_empty():
		p["ctrl_group"] = g

func _rebuild_group_dict() -> void:
	control_groups.clear()
	for u in units:
		if int(u.get("faction", -1)) != viewer_faction:
			continue
		var g := int(u.get("ctrl_group", -1))
		if g < 0:
			continue
		if not control_groups.has(g):
			control_groups[g] = []
		(control_groups[g] as Array).append(str(u.get("id", "")))

func _select_control_group(g: int, allow_dbl_follow: bool) -> void:
	var now := Time.get_ticks_msec()
	var is_dbl := allow_dbl_follow and g == _digit_last_g and (now - _digit_last_ms) <= DIGIT_DBL_MS
	_digit_last_g = g
	_digit_last_ms = now
	selection = control_groups.get(g, []).duplicate()
	_update_detail()
	_pin_selected_left_rows()
	if is_dbl:
		_follow_random_in_selection()

func _follow_random_in_selection() -> void:
	if cam == null or cam.starmap_mode:
		return
	var alive: Array = []
	for id in selection:
		var u = _unit_by_id(str(id))
		if u and u.get("alive", false):
			alive.append(u)
	if alive.is_empty():
		return
	var pick: Dictionary = alive[rng.randi_range(0, alive.size() - 1)]
	cam.set_follow(str(pick["id"]))
	cam.update_follow_pos(pick["pos"])

func _pilot_group_numbers(p: Dictionary) -> Array:
	## Number lives on the pilot. A dead ship does not clear it.
	var g := int(p.get("ctrl_group", -1))
	if g < 0:
		return []
	return [g]

func _refresh_pilot_row_group_badge(row: Control, p: Dictionary) -> void:
	if row == null:
		return
	var lab = row.find_child("GroupBadge", true, false) as Label
	var bg = row.find_child("GroupBadgeBg", true, false) as Control
	if lab == null:
		return
	var nums = _pilot_group_numbers(p)
	## Number stays on the pilot frame after the ship portrait is cleared.
	var badge_on := not nums.is_empty()
	if badge_on:
		lab.text = str(int(nums[0]))
		lab.visible = true
		if bg:
			bg.visible = true
	else:
		lab.text = ""
		lab.visible = false
		if bg:
			bg.visible = false

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
	_box_overlay.z_index = 200
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
	if hud_layer:
		hud_layer.add_child(_box_overlay)
	else:
		hud.add_child(_box_overlay)

func _update_box_overlay() -> void:
	_ensure_box_overlay()
	if _box_overlay == null:
		return
	var outline := _box_overlay.get_node_or_null("Outline") as ReferenceRect
	if _left_dragging and _left_box_selecting:
		var a = _left_drag_start
		var b = get_viewport().get_mouse_position()
		var r = Rect2(a, b - a).abs()
		_box_overlay.position = r.position
		_box_overlay.size = r.size.max(Vector2(2, 2))
		_box_overlay.color = Color(0.22, 0.52, 1.0, 0.18)
		if outline:
			outline.border_color = Color(0.4, 0.75, 1.0, 0.95)
		_box_overlay.visible = true
	elif _hold_grow:
		var half := maxf(_hold_half, 2.0)
		var r3 := Rect2(_hold_origin - Vector2(half, half), Vector2(half, half) * 2.0)
		_box_overlay.position = r3.position
		_box_overlay.size = r3.size
		_box_overlay.color = Color(0.2, 0.9, 0.35, 0.12)
		if outline:
			outline.border_color = Color(0.3, 1.0, 0.45, 0.9)
		_box_overlay.visible = true
	elif dragging and box_selecting:
		var a2 = drag_start
		var b2 = get_viewport().get_mouse_position()
		var r2 = Rect2(a2, b2 - a2).abs()
		_box_overlay.position = r2.position
		_box_overlay.size = r2.size.max(Vector2(2, 2))
		_box_overlay.color = Color(0.2, 0.9, 0.35, 0.12)
		if outline:
			outline.border_color = Color(0.3, 1.0, 0.45, 0.9)
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
			_marker_handles_on = false
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
		var cell_r = _pick_cell(screen_pos)
		if not cell_r.is_empty():
			_open_cell_menu(str(cell_r["sys"]), int(cell_r["cell"]), screen_pos)
			return
		_clear_selection()
		_marker_handles_on = false
		return
	if int(uhit.get("faction", -1)) == viewer_faction:
		if not selection.has(uhit["id"]):
			selection = [uhit["id"]]
	else:
		selection = [uhit["id"]]
	_detail_dirty = true
	_update_detail()
	_open_unit_menu(uhit, screen_pos)

func _try_callout_double(screen_pos: Vector2) -> bool:
	if cam == null or cam.cam == null or not cam.tactical_mode or cam.starmap_mode:
		return false
	if tactical_callouts == null or not tactical_callouts.has_method("hit_frame"):
		return false
	var fr: Dictionary = tactical_callouts.hit_frame(cam.cam, screen_pos)
	if fr.is_empty():
		_callout_click_key = ""
		return false
	var key := "%s:%d" % [str(fr.get("sys", "")), int(fr.get("cell", -1))]
	var now := Time.get_ticks_msec() / 1000.0
	var dbl := key == _callout_click_key and now - _callout_click_t <= 0.4
	_callout_click_key = key
	_callout_click_t = now
	if not dbl:
		return false
	var found: Array = []
	for idv in fr.get("unit_ids", []):
		var uu: Dictionary = _unit_by_id(str(idv))
		if uu.is_empty() or not bool(uu.get("alive", false)):
			continue
		if int(uu.get("faction", -1)) != viewer_faction:
			continue
		if bool(uu.get("garrison", false)) or not bool(uu.get("commandable", true)):
			continue
		var uid := str(uu.get("id", ""))
		if uid != "" and not found.has(uid):
			found.append(uid)
	if found.is_empty():
		return false
	selection = found
	_detail_dirty = true
	_update_detail()
	_callout_click_key = ""
	return true


func _left_click(screen_pos: Vector2) -> void:
	if Time.get_ticks_msec() / 1000.0 < _suppress_lmb_until:
		return
	if cam and cam.starmap_mode:
		## LMB: 点系全选；已选再点他系 → 落进系星门并待命。
		_starmap_click(screen_pos, false)
		return
	if _try_callout_double(screen_pos):
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
			if rel_atk == "hostile" and not _attack_forbidden_on(u):
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
	## Always allocate batch_id for shared sleeper click/dest; sync_gid only when every mover has sync_move on.
	_sync_gid_next += 1
	var batch_id := _sync_gid_next
	var sync_gid := batch_id if _movers_all_sync(movers) else 0
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
	var sync_gid := batch_id if _movers_all_sync(movers) else 0
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
	## Sync on (all movers): shortest non-zero range (whole group can engage).
	## Sync off: longest-range unit is the fleet reference (SHIPS §10).
	var use_longest := not _movers_all_sync(movers)
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
		## Only flock-flush while this unit's sync_move is on (gid alone must not keep syncing when 关).
		if gid <= 0 or not _unit_sync_on(u):
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
	u["player_hold"] = true
	_mp_on_path(u, to_sys, to_cell)
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
	var prep = _dev_prep(u)
	if str(u["sys"]) == to_sys:
		if int(u["cell"]) == to_cell:
			u["path"] = []
			u.erase("order_dest_sys")
			u.erase("order_dest_cell")
		else:
			u["path"] = [{
				"sys": to_sys, "from": int(u["cell"]), "to": to_cell,
				"kind": "intra",
				"duration": prep + _dev_move(u) + _intra_land(str(u["sys"]), int(u["cell"]), to_cell, _dev_land(u))
			}]
	else:
		u["path"] = BoardPlayerNav.find_path(
			map, data.diplomacy, u["faction"],
			u["sys"], u["cell"], to_sys, to_cell,
			prep, _dev_move(u), _dev_land(u), _dev_jump(u)
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
		u["step_invuln"] = _dev_move(u)
		u["path"] = []
		_assign_reserve(u)
	else:
		var prep = float(u.get("phase_t", _dev_prep(u)))
		var path = BoardPlayerNav.find_path(
			map, data.diplomacy, u["faction"],
			from_sys, from_cell, to_sys, to_cell,
			prep, _dev_move(u), _dev_land(u), _dev_jump(u)
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
			u["step_invuln"] = _dev_jump(u)
			## Gate transit never waits on align prep.
			_assign_reserve(u)
			_enter_step_invuln(u)
			_ensure_move_line(u, to_sys, to_cell)
			admin.request("board.move", {"unit": u["id"], "phase": "invuln"})
			return
		else:
			u["to_sys"] = from_sys
			var dest2 = _bubble_redirect(from_sys, from_cell, int(u["to_cell"]), u)
			u["to_cell"] = dest2
			u["step_invuln"] = _dev_move(u)
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
	## Idle at a blocked gate with a remembered dest → repath when that gate opens.
	## Player orders keep player_hold. Deputy orders repath without stealing the ship.
	for u in units:
		if not u.get("alive", false):
			continue
		if bool(u.get("garrison", false)):
			u["path"] = []
			u.erase("order_dest_sys")
			u.erase("order_dest_cell")
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
		if bool(u.get("player_hold", false)):
			_pathfind_apply(u, ds, dc)
		else:
			var prep_r = _dev_prep(u)
			u["path"] = BoardPlayerNav.find_path(
				map, data.diplomacy, u["faction"],
				u["sys"], u["cell"], ds, dc,
				prep_r, _dev_move(u), _dev_land(u), _dev_jump(u)
			)
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
		if _fit_has_slot(data.ship_def(u["ship_id"]), "interdiction"):
			popup.add_item("拦截立场：%s" % ("开" if u.get("interdict_on", false) else "关"), 20)
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
		popup.add_item("出站", 5)
		popup.set_item_disabled(popup.get_item_index(5), true)
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
	var cell_sys := str(popup.get_meta("cell_sys", ""))
	if cell_sys != "" and (id == 501 or id == 502 or id == 503 or id == 504):
		_on_cell_menu(id)
		popup.set_meta("cell_sys", "")
		return
	var pid: String = str(popup.get_meta("pilot", ""))
	if pid != "":
		_on_pilot_popup(id)
		return
	var uid: String = str(popup.get_meta("unit", ""))
	var u = _unit_by_id(uid)
	if u.is_empty():
		return
	var sel_units: Array = []
	for sid in selection:
		var su = _unit_by_id(str(sid))
		if not su.is_empty() and int(su.get("faction", -1)) == viewer_faction:
			sel_units.append(su)
	if sel_units.is_empty():
		sel_units.append(u)
	match id:
		1:
			var want_b := not bool(u.get("bubble_on", false))
			for su2 in sel_units:
				if int(su2["phase"]) == BoardTypes.MovePhase.LANDING or int(su2["phase"]) == BoardTypes.MovePhase.INVULN:
					continue
				su2["bubble_on"] = want_b
				if want_b:
					su2["bubble_cd"] = 0.0
				else:
					var cell_off: Dictionary = map.systems[su2["sys"]]["cells"][su2["cell"]]
					cell_off["bubble"] = false
					cell_off["bubble_remain"] = 0.0
		2:
			for su3 in sel_units:
				su3["path"].clear()
				if int(su3["phase"]) == BoardTypes.MovePhase.PREP:
					su3["phase"] = BoardTypes.MovePhase.IDLE
		3:
			if cam and cam.starmap_mode:
				return
			if cam.follow_unit_id == u["id"]:
				cam.clear_follow_keep_look()
			else:
				cam.set_follow(u["id"])
		4:
			for su4 in sel_units:
				_dock_unit(su4)
		5:
			## 出站：对选中驾驶员尝试出当前/上次舰（覆盖式）。
			for su5 in sel_units:
				var p5 = _pilot_by_id(str(su5.get("pilot_id", "")))
				if p5.is_empty():
					continue
				var sid5 := str(p5.get("last_ship_id", su5.get("ship_id", "")))
				if sid5 != "":
					_launch_pilot(p5, sid5)
		10:
			var want_fa := not bool(u.get("guard", {}).get("field_auto_on", true))
			for su6 in sel_units:
				if su6.has("guard") and su6["guard"].get("field_fitted", false):
					su6["guard"]["field_auto_on"] = want_fa
					_tick_guard_reopen(su6)
		11:
			var want_la := not bool(u.get("guard", {}).get("link_auto_on", true))
			for su7 in sel_units:
				if su7.has("guard") and su7["guard"].get("link_fitted", false):
					su7["guard"]["link_auto_on"] = want_la
					_tick_guard_reopen(su7)
		12:
			var want_ia := not bool(u.get("implant", {}).get("auto_on", true))
			for su8 in sel_units:
				if su8.has("implant") and str(su8.get("implant", {}).get("ref", "")) != "":
					su8["implant"]["auto_on"] = want_ia
		13:
			var want_fo := not bool(u.get("guard", {}).get("field_on", false))
			for su9 in sel_units:
				if su9.has("guard") and su9["guard"].get("field_fitted", false):
					su9["guard"]["field_on"] = want_fo
					if not want_fo:
						su9["guard"]["field_auto_on"] = false
					_tick_guard_reopen(su9)
		20:
			var want_h := not bool(u.get("interdict_on", false))
			for su20 in sel_units:
				if not _fit_has_slot(data.ship_def(su20["ship_id"]), "interdiction"):
					continue
				if int(su20["phase"]) == BoardTypes.MovePhase.LANDING or int(su20["phase"]) == BoardTypes.MovePhase.INVULN:
					continue
				if want_h:
					su20["interdict_on"] = true
					su20["interdict_since"] = _sim_clock
				elif _sim_clock - float(su20.get("interdict_since", 0.0)) >= 20.0:
					su20["interdict_on"] = false

func _dock_unit(u: Dictionary) -> void:
	if not _can_dock(u):
		return
	var p = _pilot_by_id(u["pilot_id"])
	if p.is_empty():
		return
	_apply_undock_lock_on_dock(u)
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

func _warm_ship_death_fx() -> void:
	SHIP_DEATH_FX.warm()


func _fx_ok() -> bool:
	## Tactical top-down keeps plate↔plate beams (TACTICAL_TOPDOWN). Starmap silences FX.
	return cam == null or not cam.starmap_mode

func _play_turret_vfx(fx_kind: String, from: Vector3, to: Vector3, src_id: String = "") -> void:
	if not _fx_ok() or combat_fx == null:
		return
	if src_id != "" and not _battle_fx_allowed(src_id):
		return
	## Tactical width and the 0.1s tip stay here. The art pack only draws the shot.
	var thick_wu := 0.0
	var width_mul := 1.0
	if cam != null and cam.tactical_mode and not cam.starmap_mode:
		thick_wu = BoardUnitOverhead.icon_circum_radius_world() * 0.5
	elif _is_battle_view():
		width_mul = 0.5
	combat_fx.play_shot(fx_kind, from, to, thick_wu, width_mul)
	if tip_vfx != null:
		tip_vfx.play_tips(fx_kind, from, to, thick_wu, width_mul)

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
		## Territory 底图：战场、战术、星图都显示。战场天空仍是全景。
		starmap_view.set_territory_visible(tier == "battle" or tier == "tactical" or tier == "starmap")
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
		## Sleepers (incl. pledged) never count toward reputation headcount.
		if bool(u.get("garrison", false)) or _unit_is_sleeper(u):
			continue
		var sid := str(u.get("sys", ""))
		if sid == "" or _mp_hide_unit(u):
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

func _fighting_unit_count() -> int:
	var by_id: Dictionary = {}
	for u0 in units:
		if typeof(u0) == TYPE_DICTIONARY:
			by_id[str(u0.get("id", ""))] = u0
	var ids: Dictionary = {}
	for u in units:
		if not bool(u.get("alive", false)):
			continue
		var uid := str(u.get("id", ""))
		var fac := int(u.get("faction", -1))
		_count_fight_peer(ids, by_id, uid, fac, str(u.get("focus_id", "")))
		for w in u.get("weapons", []):
			var kind := str(w.get("kind", ""))
			if kind == "remote_armor" or kind == "remote_shield":
				continue
			_count_fight_peer(ids, by_id, uid, fac, str(w.get("lock_id", "")))
		for g in u.get("pd", []):
			if float(g.get("cd", 0.0)) <= 0.0:
				continue
			_count_fight_peer(ids, by_id, uid, fac, str(g.get("target", "")))
	return ids.size()


func _count_fight_peer(ids: Dictionary, by_id: Dictionary, uid: String, fac: int, tid: String) -> void:
	if tid == "":
		return
	if not by_id.has(tid):
		return
	var t: Dictionary = by_id[tid]
	if bool(t.get("alive", false)) and int(t.get("faction", -1)) != fac:
		ids[uid] = true
		ids[str(t.get("id", ""))] = true


func _viewer_combat_plate_ids() -> Dictionary:
	## Ships whose battlefield plate stays full: both sides of a hostile fight that includes the viewer.
	var out: Dictionary = {}
	var viewer := int(viewer_faction)
	for u in units:
		if not u.get("alive", false):
			continue
		var u_ours := int(u.get("faction", -1)) == viewer
		var fid := str(u.get("focus_id", ""))
		if fid != "":
			_mark_viewer_fight(out, u, fid, u_ours, viewer)
		for w in u.get("weapons", []):
			var kind := str(w.get("kind", ""))
			if kind == "remote_armor" or kind == "remote_shield":
				continue
			var lid := str(w.get("lock_id", ""))
			if lid != "":
				_mark_viewer_fight(out, u, lid, u_ours, viewer)
		for g in u.get("pd", []):
			if float(g.get("cd", 0.0)) <= 0.0:
				continue
			var pt := str(g.get("target", ""))
			if pt != "":
				_mark_viewer_fight(out, u, pt, u_ours, viewer)
	return out

func _mark_viewer_fight(out: Dictionary, u: Dictionary, tid: String, u_ours: bool, viewer: int) -> void:
	var tgt = _unit_by_id(tid)
	if tgt.is_empty() or not tgt.get("alive", false):
		return
	## Fighting sleepers never expands battlefield plates (TACTICAL_TOPDOWN / SHIPS §13).
	if _unit_is_sleeper(u) or _unit_is_sleeper(tgt):
		return
	var t_ours := int(tgt.get("faction", -1)) == viewer
	if not u_ours and not t_ours:
		return
	if _rel_between(int(u.get("faction", 0)), int(tgt.get("faction", 0))) != "hostile":
		return
	out[str(u.get("id", ""))] = true
	out[tid] = true

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
		if _movers_all_sync(_selection_movers()):
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
		var in_gap := int(u.get("phase", 0)) == BoardTypes.MovePhase.INVULN
		if in_gap:
			## Stay on the departure slot. Do not slide across the gap between callouts.
			tactical_callouts.snap_overhead(uid, slot)
			_unit_oh_cell[uid] = key
		elif str(_unit_oh_cell.get(uid, "")) != key:
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
	popup.add_item("出站", 5)
	var can_undock := bool(p.get("in_station", false)) and str(p.get("unit_id", "")) == ""
	popup.set_item_disabled(popup.get_item_index(5), not can_undock)
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
			if str(def.get("tonnage")) != ton or not _ship_player_buildable(def) or not _pilot_has_ship(p, str(sid)):
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
	sm.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	sm.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	sm.add_theme_color_override("font_disabled_color", Color(0.42, 0.42, 0.46))
	sm.add_item("-", 6101)
	sm.set_item_disabled(sm.get_item_index(6101), held <= 0)
	## Status line stays a normal color. Disabling it is what painted it gray.
	sm.add_item("已分配 %d  （待分配 %d）" % [held, pool_show], 6100)
	sm.add_item("+", 6102)
	sm.set_item_disabled(sm.get_item_index(6102), pool_take <= 0)
	sm.add_item("打开分配面板…", 6103)
	# #region agent log
	var pc: Dictionary = BoardResourceAssign.pool_counts(map, int(p["faction"]), "")
	_dbg59("ASN", "board_root._fill_assign_submenu", "assign_pool", {
		"pid": str(p["id"]), "held": held, "pool_show": pool_show, "pool_take": pool_take,
		"minus_gray": held <= 0, "plus_gray": pool_take <= 0, "status_disabled": false,
		"empty": int(pc.get("empty", 0)), "auto": int(pc.get("auto", 0)), "runId": "post-fix"
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
	if id == 6100:
		return
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
		## Cover all selected friendlies + this pilot's hull.
		var docked_any := false
		for sid4 in selection:
			var u4 = _unit_by_id(str(sid4))
			if not u4.is_empty() and int(u4.get("faction", -1)) == viewer_faction:
				_dock_unit(u4)
				docked_any = true
		if not docked_any:
			var u = _unit_by_id(str(p.get("unit_id", "")))
			if u:
				_dock_unit(u)
	elif id == 5:
		## 出站：本驾驶员与其它站内己方团员覆盖出库（优先未锁同型）。
		var sid5 := str(p.get("last_ship_id", p.get("default_ship", "")))
		if sid5 != "":
			_launch_pilot(p, sid5)
		for p5 in pilots:
			if int(p5.get("faction", -1)) != viewer_faction:
				continue
			if str(p5.get("id", "")) == str(p.get("id", "")):
				continue
			if not bool(p5.get("in_station", false)) or str(p5.get("unit_id", "")) != "":
				continue
			var s5b := str(p5.get("last_ship_id", p5.get("default_ship", sid5)))
			if s5b != "":
				_launch_pilot(p5, s5b)
	elif id == 400:
		_popup_home_stations(p)
	elif id >= 1000 and id < 2000:
		var ship_id = str(popup.get_meta("launch_%d" % id, ""))
		_launch_pilot(p, ship_id)
		## Same model undock for other in-station selected pilots (overwrite launch).
		for p2 in pilots:
			if int(p2.get("faction", -1)) != viewer_faction:
				continue
			if str(p2.get("id", "")) == str(p.get("id", "")):
				continue
			if not bool(p2.get("in_station", false)):
				continue
			if str(p2.get("unit_id", "")) != "":
				continue
			_launch_pilot(p2, ship_id)
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
		if str(def.get("tonnage")) != ton or not _ship_player_buildable(def) or not _pilot_has_ship(_p, str(sid)):
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
	if _faction_out.has(int(p.get("faction", -1))):
		# #region agent log
		_dbg59("DEF", "board_root._launch_pilot", "launch_blocked_defeated", {
			"pilot": str(p.get("id", "")), "fac": int(p.get("faction", -1)), "runId": "post-fix"
		})
		# #endregion
		return
	var cs: String = str(p.get("current_station", ""))
	if cs == "" or not map.systems.has(cs):
		return
	var inst = _take_ship_for_launch(p, ship_id)
	if inst.is_empty():
		return
	if float(inst.get("undock_ready_at", 0.0)) > _sim_clock + 0.001:
		## Put back if still locked (should not happen after prefer unlocked).
		pilots_sys.dock_ship(p, inst)
		return
	var sc = map.station_cell(cs)
	var u = _spawn_unit(p, inst, cs, sc)
	p["unit_id"] = u["id"]
	p["in_station"] = false
	_begin_undock_rise(u)
	_ensure_unit_node(u)
	if br_tracker:
		br_tracker.note_unit_enter_sys(u, cs)
	admin.request("pilot.launch", {"pilot": p["id"], "ship": ship_id, "sys": cs})
	_slot_launched_ship(u)

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
	# #region agent log
	var hit_col = hit.get("collider") if not hit.is_empty() else null
	_dbg59("PICK", "board_root._pick_unit", "ray", {
		"screen": [screen_pos.x, screen_pos.y], "cam_y": cam.cam.global_position.y,
		"pitch_deg": rad_to_deg(asin(clampf(-dir.y, -1.0, 1.0))),
		"hit": str(hit_col.get_meta("unit_id")) if hit_col != null and hit_col.has_meta("unit_id") else "",
		"shape": str((_pick_col(hit_col.get_parent()).shape as Shape3D).get_class()) if hit_col != null and _pick_col(hit_col.get_parent()) != null else "",
		"tac": cam.tactical_mode, "runId": "post-fix"
	})
	# #endregion
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
	## Battlefield: a ray miss is a miss. Screen-distance fallback is for tactical tonnage icons only.
	if not cam.tactical_mode:
		return {}
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
	## Visible ring first (BOARD_AND_INPUT). Analytic plane only when rings are hidden.
	if cam == null or cam.cam == null or map == null:
		return {}
	var from = cam.cam.project_ray_origin(screen_pos)
	var dir = cam.cam.project_ray_normal(screen_pos)
	if starmap_view != null and starmap_view.has_method("rings_pick_active") \
			and bool(starmap_view.rings_pick_active()) \
			and starmap_view.has_method("pick_painted_cell"):
		return starmap_view.pick_painted_cell(from, dir)
	return _pick_cell_analytic(from, dir)

func _pick_cell_analytic(from: Vector3, dir: Vector3) -> Dictionary:
	## Starmap fallback: rings are hidden, so identify a system from the Y=0 hit.
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

func _describe_crew_equip(pilot_name: String, eq: Dictionary) -> String:
	var bits: PackedStringArray = PackedStringArray()
	var labels := {
		"hp_mul": "血量",
		"weapon_damage_mul": "单武器伤害",
		"cap_convert_mul": "上限伤害转化",
		"move_penalty_mul": "移速惩罚",
		"build_mul": "制造时间",
	}
	for key in CrewRankScr.EFFECT_KEYS:
		if not eq.has(key):
			continue
		bits.append("%s×%s" % [str(labels.get(key, key)), str(eq[key])])
	for k in eq.keys():
		var key2 := str(k)
		if key2 == "id" or key2 == "name" or key2 == "kind" or labels.has(key2):
			continue
		bits.append("%s=%s" % [key2, str(eq[k])])
	if bits.is_empty():
		return "驾驶员 · %s — 舰船操控与出站部署" % pilot_name
	return "驾驶员 · %s — %s" % [pilot_name, "，".join(bits)]

func _match_factions_payload() -> Array:
	var grouped: Dictionary = {}
	for p in pilots:
		var fid := int(p.get("faction", 0))
		if not grouped.has(fid):
			grouped[fid] = []
		var mid := str(p.get("member_id", ""))
		var row: Dictionary = {}
		if mid != "":
			row = data.member_by_id(mid).duplicate(true)
		if row.is_empty():
			row = {"id": str(p.get("id", "")), "name": str(p.get("name", ""))}
		row["home"] = str(p.get("home", ""))
		row["ship"] = str(p.get("default_ship", ""))
		row["cell_kind"] = str(p.get("opening_cell_kind", "station"))
		row["gate_to"] = str(p.get("opening_gate_to", ""))
		row["placement_id"] = str(p.get("id", ""))
		row["faction"] = fid
		grouped[fid].append(row)
	var out: Array = []
	for fid2 in grouped.keys():
		out.append({"id": int(fid2), "members": grouped[fid2]})
	return out

func _equip_def(ref_id: String) -> Dictionary:
	if ref_id == "" or data == null:
		return {}
	var eq = data.equipment.get(ref_id, {})
	return eq if typeof(eq) == TYPE_DICTIONARY else {}

func _format_equip_effect_lines(u: Dictionary, p: Dictionary) -> PackedStringArray:
	## Flat list: pilot + slot fits + hidden. No section headers.
	var lines: PackedStringArray = PackedStringArray()
	var pilot_name := str(p.get("name", p.get("id", "?")))
	lines.append(_describe_crew_equip(pilot_name, _pilot_crew_eq(p)))
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
					return "%s — 伤害周期×%d，单发×%d，跟踪×%d" % [
						inm, int(ieq.get("every", 10)), int(ieq.get("mul", 10)), int(ieq.get("tracking_mul", 1000))
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
	_pin_selected_left_rows()
	_refresh_sync_move_btn()
	if detail == null:
		return
	if selection.is_empty():
		detail.text = ""
		return
	var u = _unit_by_id(selection[0])
	if u.is_empty() or not u.get("alive", false) or _mp_hide_unit(u):
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
		float(_dev_move(u)), float(_dev_jump(u))
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


func _mp_boot() -> void:
	_mp = MpMatchDriver.new()
	_mp.attach(self)


func _mp_apply_host_tables() -> void:
	if not FileAccess.file_exists(MpCampaignNet.LIVE_PATH):
		return
	if not FileAccess.file_exists(MpCampaignNet.TABLES_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MpCampaignNet.TABLES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or data == null:
		return
	var ships: Array = (parsed as Dictionary).get("ships", [])
	if not ships.is_empty():
		data.ships.clear()
		for s_v in ships:
			if typeof(s_v) == TYPE_DICTIONARY:
				data.ships[str((s_v as Dictionary).get("id", ""))] = s_v
	var equip_v: Variant = (parsed as Dictionary).get("equipment", {})
	if typeof(equip_v) == TYPE_DICTIONARY and not (equip_v as Dictionary).is_empty():
		data.equipment = equip_v


func _mp_sim_unit(u: Dictionary) -> bool:
	return _mp == null or _mp.sim_unit(u)


func _mp_owns(which: String) -> bool:
	return _mp == null or _mp.owns_global(which)


func _mp_hide_unit(u: Dictionary) -> bool:
	return _mp != null and _mp.fog_hides_unit(u)


func _mp_fog_arc(sid: String) -> bool:
	return _mp != null and _mp.fog_blocks_arc(sid)


func _mp_ai_units(faction: int, rows: Array) -> Array:
	if _mp == null:
		return rows
	return _mp.ai_units(faction, rows)


func _mp_before_capture() -> Dictionary:
	if _mp == null:
		return {}
	return _mp.before_capture()


func _mp_after_capture(saved: Dictionary) -> void:
	if _mp != null:
		_mp.after_capture(saved)


func _mp_on_path(u: Dictionary, to_sys: String, to_cell: int) -> void:
	if _mp != null:
		_mp.on_path(u, to_sys, to_cell)


func _mp_on_group(uid: String, g: int) -> void:
	if _mp != null:
		_mp.on_group(uid, g)


func _mp_on_deputy(faction: int, group_id: int) -> void:
	if _mp != null:
		_mp.on_deputy(faction, group_id)


func _mp_on_diplo(a: int, b: int, on: bool) -> void:
	if _mp != null:
		_mp.on_diplo(a, b, on)


func _mp_match_end(winner: int, reason: String) -> void:
	if _mp != null:
		_mp.on_match_end(winner, reason)


func _mp_after_settlement() -> void:
	if _mp != null:
		_mp.after_settlement()


func _mp_offer_diplo(from_fac: int, to_fac: int) -> void:
	if _mp != null:
		_mp.offer_diplo(from_fac, to_fac)


func _mp_faction_is_ai(fid: int) -> bool:
	if map == null or typeof(map.layout) != TYPE_DICTIONARY or not bool((map.layout as Dictionary).get("mp", false)):
		return fid != viewer_faction
	var ai_facs: Array = (map.layout as Dictionary).get("ai_factions", [])
	return ai_facs.has(fid)


func _mp_block_dev() -> bool:
	return _mp != null and _mp.block_dev()


func _on_mp_fog_toggled(on: bool) -> void:
	if _mp == null:
		return
	_mp.set_fog(on)
	if _mp_fog_box != null:
		_mp_fog_box.set_pressed_no_signal(_mp.fog_on)


func _toggle_mp_cheat_list() -> void:
	if _mp_cheat_list == null:
		return
	_mp_cheat_list.visible = not _mp_cheat_list.visible
	if _mp_cheat_list.visible:
		_fill_mp_cheat_list()


func _fill_mp_cheat_list() -> void:
	if _mp_cheat_list == null or _mp == null or _mp.net == null:
		return
	for c in _mp_cheat_list.get_children():
		c.queue_free()
	var me := 0
	if _mp.net.multiplayer.has_multiplayer_peer():
		me = _mp.net.multiplayer.get_unique_id()
	for m_v in _mp.net.room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if bool(m.get("ai", false)):
			continue
		var pid := int(m.get("peer", 0))
		if pid == 0 or pid == me:
			continue
		var b := Button.new()
		b.text = str(m.get("nick", "玩家"))
		b.pressed.connect(_on_mp_cheat_pick.bind(pid, str(m.get("nick", "玩家"))))
		_mp_cheat_list.add_child(b)


func _on_mp_cheat_pick(pid: int, nick: String) -> void:
	if _mp != null:
		_mp.start_audit(pid, nick)


func _on_mp_chat_submit(text: String) -> void:
	var body := text.strip_edges()
	if body == "" or _mp == null or _mp.net == null:
		return
	_mp.net.say_verbatim("[全体] %s：%s" % [_mp.net.local_nick, body], "all", 0)
	var edit := chat_log.get_parent().get_node_or_null("MpChatEdit") as LineEdit
	if edit:
		edit.text = ""
