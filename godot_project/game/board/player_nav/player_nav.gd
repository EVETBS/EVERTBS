extends RefCounted
class_name BoardPlayerNav

const DevBalance := preload("res://game/board/dev_balance.gd")
const FlowNavScr := preload("res://game/board/player_nav/capture_flow_nav.gd")

static var _flow_sig := ""
static var _flow_navs: Dictionary = {}
static var _scale_map: BoardMapModel = null

## Shortest-time path: start -> gates -> dest. Same-system one hop.

## Arrow corridor (BOARD §6.1). Empty when no arrow is on the map.
static var corridor_on := false
static var corridor_a := Vector3.ZERO
static var corridor_b := Vector3.ZERO

static func find_path(
	map: BoardMapModel,
	diplomacy: Dictionary,
	faction: int,
	from_sys: String,
	from_cell: int,
	to_sys: String,
	to_cell: int,
	prep_s: float,
	move_s: float,
	landing_s: float,
	jump_s: float
) -> Array:
	## Same system stays one hop. Cross-system shares a reverse distance field per faction and timing.
	if from_sys == to_sys:
		return _search(map, diplomacy, faction, from_sys, from_cell, to_sys, to_cell, prep_s, move_s, landing_s, jump_s, false)["path"]
	var plain: Dictionary = _flow_result(map, diplomacy, faction, from_sys, from_cell, to_sys, to_cell, prep_s, move_s, landing_s, jump_s, false)
	var chosen: Dictionary = plain
	if corridor_on:
		var weighted: Dictionary = _flow_result(map, diplomacy, faction, from_sys, from_cell, to_sys, to_cell, prep_s, move_s, landing_s, jump_s, true)
		var c0 := float(plain.get("route_cost", INF))
		var real := float(weighted.get("route_cost", INF))
		var one_jump := jump_s + landing_s
		if is_finite(real) and real <= maxf(c0 * 1.35, c0 + one_jump):
			chosen = weighted
	var status := str(chosen.get("status", ""))
	if status == "READY" or status == "MOVE_TO_CAPTURE":
		return chosen.get("steps", [])
	return []


static func _corridor_scale(_from_sys: String, to_sys: String) -> float:
	if _scale_map != null and _sys_in_corridor(_scale_map, to_sys):
		return 0.65
	return 1.0


static func _flow_signature(map: BoardMapModel, diplomacy: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var ids: Array = map.systems.keys()
	ids.sort()
	for sid_v in ids:
		var sid := str(sid_v)
		for c_v in map.systems[sid]["cells"]:
			var c: Dictionary = c_v
			if int(c.get("kind", -1)) != BoardTypes.CellKind.GATE:
				continue
			parts.append("%s:%d:%d" % [sid, int(c.get("index", -1)), int(c.get("owner", 0))])
	return "|".join(parts) + "#" + JSON.stringify(diplomacy.get("relations", {}))


static func _flow_result(
	map: BoardMapModel, diplomacy: Dictionary, faction: int,
	from_sys: String, from_cell: int, to_sys: String, to_cell: int,
	prep_s: float, move_s: float, landing_s: float, jump_s: float, corridor: bool
) -> Dictionary:
	var sig := _flow_signature(map, diplomacy)
	if sig != _flow_sig:
		_flow_sig = sig
		_flow_navs.clear()
	var key := "%d|%.3f|%.3f|%.3f|%.3f|%s" % [faction, prep_s, move_s, landing_s, jump_s, "c" if corridor else "p"]
	var nav: Object = _flow_navs.get(key, null)
	if nav == null:
		_scale_map = map
		nav = FlowNavScr.new()
		var scale := Callable(BoardPlayerNav, "_corridor_scale") if corridor else Callable()
		var built: bool = nav.configure_from_board(
			map, diplomacy, faction,
			{"prep": prep_s, "move": move_s, "landing": landing_s, "jump": jump_s},
			BoardTypes.CellKind.GATE,
			Callable(DevBalance, "land_arc_mul"),
			func(sys: String, cell: int, fac: int) -> bool:
				return not map.can_pass_gate(sys, cell, fac, diplomacy),
			1, scale
		)
		if not built:
			return {"status": "INVALID", "steps": [], "route_cost": INF}
		_flow_navs[key] = nav
	var result: Dictionary = nav.plan(FlowNavScr.node_key(from_sys, from_cell), FlowNavScr.node_key(to_sys, to_cell))
	DebugSessionLog.append("J1", "player_nav._flow_result", "flow", {
		"from": from_sys, "to": to_sys, "status": str(result.get("status", "")),
		"steps": (result.get("steps", []) as Array).size(), "corridor": corridor,
		"runId": "flow-nav"
	})
	return result

static func _sys_in_corridor(map: BoardMapModel, sid: String) -> bool:
	if not corridor_on or not map.systems.has(sid):
		return false
	var center: Vector3 = map.systems[sid]["center"]
	var a := Vector3(corridor_a.x, 0.0, corridor_a.z)
	var b := Vector3(corridor_b.x, 0.0, corridor_b.z)
	var p := Vector3(center.x, 0.0, center.z)
	var ab := b - a
	var ab_len := ab.length()
	if ab_len < 0.001:
		return false
	var t := (p - a).dot(ab) / (ab_len * ab_len)
	var ext := 20.0 / ab_len
	if t < -ext or t > 1.0 + ext:
		return false
	var foot := a + ab * t
	return p.distance_to(foot) <= 40.0

static func _search(
	map: BoardMapModel,
	diplomacy: Dictionary,
	faction: int,
	from_sys: String,
	from_cell: int,
	to_sys: String,
	to_cell: int,
	prep_s: float,
	move_s: float,
	landing_s: float,
	jump_s: float,
	use_arrow: bool
) -> Dictionary:
	if from_sys == to_sys:
		if from_cell == to_cell:
			return {"path": [], "real": 0.0}
		var intra := _intra_duration(map, from_sys, from_cell, to_cell, prep_s, move_s, landing_s)
		return {"path": [{
			"sys": from_sys, "from": from_cell, "to": to_cell,
			"kind": "intra",
			"duration": intra
		}], "real": intra}
	## Dijkstra-style expansion keyed by sys:cell (BOARD_AND_INPUT §6): prune at ENQUEUE,
	## so the frontier never blows up on long routes. cost = weighted selection cost; real = travel time.
	var q: Array = [{"sys": from_sys, "cell": from_cell, "cost": 0.0, "real": 0.0, "path": []}]
	var best: Dictionary = {}
	best["%s:%d" % [from_sys, from_cell]] = 0.0
	var best_path: Array = []
	var best_cost = INF
	var best_real = INF
	var guard = 0
	const GUARD_MAX := 20000
	while not q.is_empty() and guard < GUARD_MAX:
		guard += 1
		## Pop cheapest (small frontier: linear scan is fine).
		var bi := 0
		for qi in range(1, q.size()):
			if float(q[qi]["cost"]) < float(q[bi]["cost"]):
				bi = qi
		var cur: Dictionary = q[bi]
		q.remove_at(bi)
		var sid: String = cur["sys"]
		var cell: int = cur["cell"]
		var cost: float = cur["cost"]
		var real: float = cur["real"]
		var path: Array = cur["path"]
		var key = "%s:%d" % [sid, cell]
		if best.has(key) and best[key] < cost:
			continue
		if cost >= best_cost:
			continue
		if sid == to_sys:
			var last = path.duplicate()
			if cell != to_cell:
				var intra_d := _intra_duration(map, sid, cell, to_cell, prep_s, move_s, landing_s)
				last.append({
					"sys": sid, "from": cell, "to": to_cell,
					"kind": "intra",
					"duration": intra_d
				})
				cost += intra_d
				real += intra_d
			if cost < best_cost:
				best_cost = cost
				best_real = real
				best_path = last
			continue
		var sys: Dictionary = map.systems[sid]
		for c in sys["cells"]:
			if int(c["kind"]) != BoardTypes.CellKind.GATE:
				continue
			var gi: int = c["index"]
			if not map.can_pass_gate(sid, gi, faction, diplomacy):
				continue
			var to_side: String = c["gate_to"]
			var land = _paired_gate(map, to_side, sid)
			if land < 0:
				continue
			var step_path = path.duplicate()
			var step_cost = cost
			var step_real = real
			if cell != gi:
				var intra2 := _intra_duration(map, sid, cell, gi, prep_s, move_s, landing_s)
				step_path.append({
					"sys": sid, "from": cell, "to": gi,
					"kind": "intra",
					"duration": intra2
				})
				step_cost += intra2
				step_real += intra2
			var jump_d := prep_s + jump_s + landing_s
			step_path.append({
				"sys": sid, "from": gi, "to": land,
				"to_sys": to_side, "kind": "jump",
				"duration": jump_d
			})
			var jump_cost := jump_d
			if use_arrow and _sys_in_corridor(map, to_side):
				jump_cost *= 0.65
			step_cost += jump_cost
			step_real += jump_d
			var nkey := "%s:%d" % [to_side, land]
			if best.has(nkey) and float(best[nkey]) <= step_cost:
				continue
			best[nkey] = step_cost
			q.append({"sys": to_side, "cell": land, "cost": step_cost, "real": step_real, "path": step_path})
	# #region agent log
	var hops := 0
	for st0 in best_path:
		if str(st0.get("kind", "")) == "jump":
			hops += 1
	DebugSessionLog.append("J1", "player_nav._search", "bfs_done", {
		"from": from_sys, "to": to_sys, "pops": guard, "guard_hit": guard >= GUARD_MAX,
		"found": not best_path.is_empty(), "jumps": hops, "visited": best.size(), "arrow": use_arrow,
		"runId": "nav-depth"
	})
	# #endregion
	if not best_path.is_empty():
		return {"path": best_path, "real": best_real}
	var blocked := _path_to_first_blocked(map, diplomacy, faction, from_sys, from_cell, to_sys, prep_s, move_s, landing_s)
	var blocked_real := 0.0
	for st in blocked:
		blocked_real += float(st.get("duration", 0.0))
	# #region agent log
	var first_gate_owner := -1
	var first_gate_to := ""
	for st1 in blocked:
		if str(st1.get("kind", "")) == "intra":
			var gi2 := int(st1.get("to", -1))
			var cells2: Array = map.systems.get(from_sys, {}).get("cells", [])
			if gi2 >= 0 and gi2 < cells2.size():
				first_gate_owner = int(cells2[gi2].get("owner", -1))
				first_gate_to = str(cells2[gi2].get("gate_to", ""))
	DebugSessionLog.append("J2", "player_nav._search", "fallback_first_blocked", {
		"from": from_sys, "to": to_sys, "steps": blocked.size(), "gate_owner": first_gate_owner,
		"gate_to": first_gate_to, "faction": faction, "runId": "nav-depth"
	})
	# #endregion
	return {"path": blocked, "real": blocked_real}

static func _intra_duration(
	map: BoardMapModel, sys: String, from_cell: int, to_cell: int,
	prep_s: float, move_s: float, landing_s: float
) -> float:
	var n := int(map.systems[sys]["cells"].size())
	return prep_s + move_s + landing_s * DevBalance.land_arc_mul(from_cell, to_cell, n)

static func _paired_gate(map: BoardMapModel, sys_id: String, from_sys: String) -> int:
	var sys: Dictionary = map.systems.get(sys_id, {})
	for c in sys.get("cells", []):
		if int(c["kind"]) == BoardTypes.CellKind.GATE and str(c["gate_to"]) == from_sys:
			return int(c["index"])
	return -1

static func _path_to_first_blocked(
	map: BoardMapModel, diplomacy: Dictionary, faction: int,
	from_sys: String, from_cell: int, to_sys: String,
	prep_s: float, move_s: float, landing_s: float
) -> Array:
	# greedy: pick any gate toward BFS parent
	var parent: Dictionary = {}
	var q2: Array = [from_sys]
	parent[from_sys] = ""
	while not q2.is_empty():
		var s: String = q2.pop_front()
		if s == to_sys:
			break
		for link in map.systems[s]["links"]:
			if parent.has(link):
				continue
			parent[link] = s
			q2.append(link)
	if not parent.has(to_sys) and to_sys != from_sys:
		return []
	# reconstruct first hop system
	var cur = to_sys
	var prev = parent.get(cur, "")
	while prev != "" and prev != from_sys:
		cur = prev
		prev = parent.get(cur, "")
	var next_sys = cur if prev == from_sys else ""
	if next_sys == "":
		return []
	var gate_i = -1
	for c in map.systems[from_sys]["cells"]:
		if int(c["kind"]) == BoardTypes.CellKind.GATE and str(c["gate_to"]) == next_sys:
			gate_i = int(c["index"])
			break
	if gate_i < 0:
		return []
	var steps: Array = []
	if from_cell != gate_i:
		steps.append({
			"sys": from_sys, "from": from_cell, "to": gate_i,
			"kind": "intra", "duration": _intra_duration(map, from_sys, from_cell, gate_i, prep_s, move_s, landing_s)
		})
	# stop at gate if blocked
	if not map.can_pass_gate(from_sys, gate_i, faction, diplomacy):
		return steps
	return steps
