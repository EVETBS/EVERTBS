extends RefCounted
class_name BoardBattleReportTracker
## Per-system battle reports: start when attack-ready white bar begins reading;
## every 5s if no bars still moving → settle (BATTLE_REPORT.md).

var viewer_faction: int = 1
var battle_clock: float = 0.0
var active: Dictionary = {}
var closed: Array = []
var _next_id: int = 1
## Callable(int faction_id) -> bool; NPC mark gate for opening sessions.
var is_npc_faction: Callable = Callable()
## Callable(int faction_id) -> bool; viewer or ally at settle time.
var is_with_viewer: Callable = Callable()
## Callable(int faction_id) -> String; display name snapshot.
var faction_label: Callable = Callable()

const TON_W := {
	"frigate": 1,
	"destroyer": 2,
	"cruiser": 3,
	"battlecruiser": 4,
	"battleship": 5,
}
const QUIET_CHECK_S := 5.0
const BAR_MOVING_MAX := 0.995 ## ratio in [0, this) counts as "moving / 读数中"

func tick(delta: float) -> void:
	battle_clock += delta

func format_clock(t: float) -> String:
	var s := int(floor(t))
	var m := int(s / 60.0)
	var r := s % 60
	return "%02d:%02d" % [m, r]

func ton_weight(ton: String) -> int:
	return int(TON_W.get(str(ton), 2))

func _sys_name(map, sys_id: String) -> String:
	if map == null or not map.systems.has(sys_id):
		return sys_id
	return str(map.systems[sys_id].get("name", sys_id))

func _is_cross_jump(u: Dictionary) -> bool:
	## Mid warp between systems — not "in" origin nor destination for BR presence/stay.
	if not u.get("alive", false):
		return false
	if str(u.get("step_kind", "")) != "jump":
		return false
	var ph: int = int(u.get("phase", 0))
	return ph == BoardTypes.MovePhase.INVULN or ph == BoardTypes.MovePhase.PREP

func _ensure_session(sys_id: String, map = null) -> Dictionary:
	if active.has(sys_id):
		return active[sys_id]
	var sess := {
		"id": "br%d" % _next_id,
		"sys": sys_id,
		"sys_name": _sys_name(map, sys_id),
		"start_t": battle_clock,
		"last_activity_t": battle_clock,
		"rows": [],
		"pilot_open": {},
		"check_accum": 0.0,
	}
	_next_id += 1
	active[sys_id] = sess
	return sess

func _open_row(sess: Dictionary, u: Dictionary) -> Dictionary:
	var uid := str(u.get("id", ""))
	var rows: Array = sess["rows"]
	for i in rows.size():
		var existing: Dictionary = rows[i]
		if uid != "" and str(existing.get("unit_id", "")) == uid and not bool(existing.get("destroyed", false)):
			return existing
	## Blank pilot id (sleepers) must not share one key or every tick appends a row.
	var pid := str(u.get("pilot_id", "")).strip_edges()
	if pid == "":
		pid = uid if uid != "" else "?"
	if sess["pilot_open"].has(pid):
		var ix: int = int(sess["pilot_open"][pid])
		if ix >= 0 and ix < rows.size():
			var prev: Dictionary = rows[ix]
			if not bool(prev.get("destroyed", false)) and str(prev.get("unit_id", "")) == uid:
				return prev
	var row := {
		"pilot_id": pid,
		"pilot_name": str(u.get("pilot_name", pid)),
		"unit_id": str(u.get("id", "")),
		"faction": int(u.get("faction", 0)),
		"ship_id": str(u.get("ship_id", "")),
		"ship_name": str(u.get("ship_name", u.get("name", "?"))),
		"tonnage": str(u.get("tonnage", "destroyer")),
		"max_loss_dealt": 0.0,
		"max_loss_taken": 0.0,
		"kills": 0,
		"stay_s": 0.0,
		"destroyed": false,
		"in_sys": true,
	}
	sess["rows"].append(row)
	sess["pilot_open"][pid] = sess["rows"].size() - 1
	return row

func _row_for_unit(sess: Dictionary, u: Dictionary) -> Dictionary:
	var uid := str(u.get("id", ""))
	for r in sess["rows"]:
		if str(r.get("unit_id", "")) == uid and not bool(r.get("destroyed", false)):
			return r
	return _open_row(sess, u)

func _sys_allows_battle_report(sys_units: Array) -> bool:
	## ≥2 non-NPC factions required; NPC-only or single non-NPC + NPC → no BR.
	var non_npc: Dictionary = {}
	for u in sys_units:
		if not u.get("alive", false):
			continue
		var fac := int(u.get("faction", 0))
		var npc := false
		if is_npc_faction.is_valid():
			npc = bool(is_npc_faction.call(fac))
		elif bool(u.get("npc", false)):
			npc = true
		if not npc:
			non_npc[fac] = true
	return non_npc.size() >= 2

func seed_system_presence(sys_id: String, units: Array, map = null) -> void:
	var sess := _ensure_session(sys_id, map)
	for u in units:
		if not u.get("alive", false):
			continue
		if str(u.get("sys", "")) != sys_id:
			continue
		if _is_cross_jump(u):
			continue
		_open_row(sess, u)

func note_damage(attacker: Dictionary, target: Dictionary, max_loss: float) -> void:
	## Stats only — does not open a session (white-bar start owns that).
	if attacker.is_empty() or target.is_empty():
		return
	var sys_id := str(target.get("sys", ""))
	if sys_id == "" or not active.has(sys_id):
		return
	if int(attacker.get("faction", -1)) == int(target.get("faction", -2)):
		return
	var sess: Dictionary = active[sys_id]
	sess["last_activity_t"] = battle_clock
	var arow := _row_for_unit(sess, attacker)
	var trow := _row_for_unit(sess, target)
	if max_loss > 0.0:
		arow["max_loss_dealt"] = float(arow.get("max_loss_dealt", 0.0)) + max_loss
		trow["max_loss_taken"] = float(trow.get("max_loss_taken", 0.0)) + max_loss

func note_kill(attacker: Dictionary, target: Dictionary) -> void:
	if target.is_empty():
		return
	var sys_id := str(target.get("sys", ""))
	if sys_id == "" or not active.has(sys_id):
		return
	var sess: Dictionary = active[sys_id]
	sess["last_activity_t"] = battle_clock
	var trow := _row_for_unit(sess, target)
	trow["destroyed"] = true
	trow["in_sys"] = false
	var pid := str(target.get("pilot_id", ""))
	if sess["pilot_open"].has(pid) and str(trow.get("unit_id", "")) == str(target.get("id", "")):
		sess["pilot_open"].erase(pid)
	if not attacker.is_empty():
		var arow := _row_for_unit(sess, attacker)
		arow["kills"] = int(arow.get("kills", 0)) + 1

func note_unit_enter_sys(u: Dictionary, sys_id: String) -> void:
	if u.is_empty() or sys_id == "":
		return
	if not active.has(sys_id):
		return
	if _is_cross_jump(u):
		return
	_open_row(active[sys_id], u)

func tick_presence(units: Array, map = null, delta: float = 0.0, bar_fn: Callable = Callable()) -> Dictionary:
	## bar_fn(unit) -> float atk_ready_ratio (-1 hidden, 0..1 reading).
	## Returns debug snapshot for instrumentation.
	var living_by_sys: Dictionary = {}
	var units_by_sys: Dictionary = {}
	var reading_by_sys: Dictionary = {}
	var moving_by_sys: Dictionary = {}
	for u in units:
		if not u.get("alive", false):
			continue
		if _is_cross_jump(u):
			continue
		var sid := str(u.get("sys", ""))
		if sid == "":
			continue
		if not living_by_sys.has(sid):
			living_by_sys[sid] = {}
			units_by_sys[sid] = []
			reading_by_sys[sid] = false
			moving_by_sys[sid] = false
		var fac := int(u.get("faction", 0))
		var bag: Dictionary = living_by_sys[sid]
		bag[fac] = int(bag.get(fac, 0)) + 1
		units_by_sys[sid].append(u)
		var ratio := -1.0
		if bar_fn.is_valid():
			ratio = float(bar_fn.call(u))
		if ratio >= 0.0:
			reading_by_sys[sid] = true
			if ratio < BAR_MOVING_MAX:
				moving_by_sys[sid] = true
	## Start only while a bar is actually counting down. A full ready bar must not open another report.
	for sid0 in moving_by_sys.keys():
		if bool(moving_by_sys[sid0]) and not active.has(sid0):
			if _sys_allows_battle_report(units_by_sys.get(sid0, [])):
				seed_system_presence(str(sid0), units, map)
	var to_close: Array = []
	var dbg_close: Array = []
	for sid in active.keys():
		var sess: Dictionary = active[sid]
		for u2 in units_by_sys.get(sid, []):
			_open_row(sess, u2)
		var present_ids := {}
		for u3 in units_by_sys.get(sid, []):
			present_ids[str(u3.get("id", ""))] = true
		for r in sess["rows"]:
			if bool(r.get("destroyed", false)):
				r["in_sys"] = false
				continue
			var uid := str(r.get("unit_id", ""))
			var here := present_ids.has(uid)
			r["in_sys"] = here
			if here and delta > 0.0:
				r["stay_s"] = float(r.get("stay_s", 0.0)) + delta
		## Bars moving = activity. Settle only when quiet AND 5s since last activity.
		var any_moving := bool(moving_by_sys.get(sid, false))
		if any_moving:
			sess["last_activity_t"] = battle_clock
		sess["check_accum"] = float(sess.get("check_accum", 0.0)) + delta
		if float(sess["check_accum"]) >= QUIET_CHECK_S:
			sess["check_accum"] = 0.0
			var quiet_for := battle_clock - float(sess.get("last_activity_t", sess.get("start_t", 0.0)))
			if not any_moving and quiet_for >= QUIET_CHECK_S:
				to_close.append(sid)
				dbg_close.append({
					"sys": sid, "reason": "bars_quiet_and_idle_5s",
					"reading": bool(reading_by_sys.get(sid, false)),
					"moving": any_moving,
					"quiet_for": quiet_for,
					"living": (units_by_sys.get(sid, []) as Array).size()
				})
			elif not any_moving:
				dbg_close.append({
					"sys": sid, "reason": "bars_quiet_keep_alive",
					"quiet_for": quiet_for,
					"reading": bool(reading_by_sys.get(sid, false)),
					"living": (units_by_sys.get(sid, []) as Array).size()
				})
	for sid2 in to_close:
		_finalize(str(sid2), map)
	return {"closed_n": to_close.size(), "events": dbg_close}

func _finalize(sys_id: String, map) -> void:
	if not active.has(sys_id):
		return
	var sess: Dictionary = active[sys_id]
	active.erase(sys_id)
	if not _session_has_content(sess):
		return
	var end_t := battle_clock
	var span := maxf(0.0, end_t - float(sess.get("start_t", 0.0)))
	## Clamp stay to session length (presence accounting safety).
	for r in sess["rows"]:
		r["stay_s"] = clampf(float(r.get("stay_s", 0.0)), 0.0, span + 0.05)
		r["in_sys"] = false
	var mine_ships := 0
	var foe_ships := 0
	var mine_lost := 0
	var foe_lost := 0
	var mine_ton := 0
	var foe_ton := 0
	var mine_names: Array = []
	var foe_names: Array = []
	var seen_unit := {}
	var seen_fac := {}
	for r in sess["rows"]:
		var fac := int(r.get("faction", 0))
		var mine := _row_with_viewer(fac)
		r["side"] = "mine" if mine else "foe"
		var tw := ton_weight(str(r.get("tonnage", "destroyer")))
		var uid := str(r.get("unit_id", ""))
		if not seen_fac.has(fac):
			seen_fac[fac] = true
			var label := _fac_label(fac)
			if mine:
				mine_names.append(label)
			else:
				foe_names.append(label)
		if not seen_unit.has(uid):
			seen_unit[uid] = true
			if mine:
				mine_ships += 1
				mine_ton += tw
			else:
				foe_ships += 1
				foe_ton += tw
		if bool(r.get("destroyed", false)):
			if mine:
				mine_lost += 1
			else:
				foe_lost += 1
	var rep := {
		"id": sess["id"],
		"sys": sys_id,
		"sys_name": _sys_name(map, sys_id) if map else str(sess.get("sys_name", sys_id)),
		"start_t": float(sess.get("start_t", 0.0)),
		"end_t": end_t,
		"mine_ships": mine_ships,
		"foe_ships": foe_ships,
		"mine_lost": mine_lost,
		"foe_lost": foe_lost,
		"mine_ton": mine_ton,
		"foe_ton": foe_ton,
		"mine_names": mine_names,
		"foe_names": foe_names,
		"rows": sess["rows"].duplicate(true),
	}
	closed.append(rep)

func _session_has_content(sess: Dictionary) -> bool:
	for r in sess.get("rows", []):
		if float(r.get("max_loss_dealt", 0.0)) > 0.01:
			return true
		if float(r.get("max_loss_taken", 0.0)) > 0.01:
			return true
		if int(r.get("kills", 0)) > 0 or bool(r.get("destroyed", false)):
			return true
	return false

func _row_with_viewer(fac: int) -> bool:
	if int(fac) == int(viewer_faction):
		return true
	if is_with_viewer.is_valid():
		return bool(is_with_viewer.call(int(fac)))
	return false

func _fac_label(fac: int) -> String:
	if faction_label.is_valid():
		var s := str(faction_label.call(int(fac)))
		if s != "":
			return s
	return "势力%d" % int(fac)
