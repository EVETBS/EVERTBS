extends RefCounted
class_name BoardPlayerNav

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
	## Returns array of steps: {sys, cell, kind: "intra"|"jump", duration}
	if not corridor_on or from_sys == to_sys:
		return _search(map, diplomacy, faction, from_sys, from_cell, to_sys, to_cell, prep_s, move_s, landing_s, jump_s, false)["path"]
	var weighted: Dictionary = _search(map, diplomacy, faction, from_sys, from_cell, to_sys, to_cell, prep_s, move_s, landing_s, jump_s, true)
	var plain: Dictionary = _search(map, diplomacy, faction, from_sys, from_cell, to_sys, to_cell, prep_s, move_s, landing_s, jump_s, false)
	var c0: float = float(plain.get("real", INF))
	var real: float = float(weighted.get("real", INF))
	var one_jump: float = prep_s + jump_s + landing_s
	if real > maxf(c0 * 1.35, c0 + one_jump):
		return plain.get("path", [])
	return weighted.get("path", [])

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
		var intra := prep_s + move_s + landing_s
		return {"path": [{
			"sys": from_sys, "from": from_cell, "to": to_cell,
			"kind": "intra",
			"duration": intra
		}], "real": intra}
	## BFS. cost is the weighted selection cost; real is unweighted travel time.
	var q: Array = [{"sys": from_sys, "cell": from_cell, "cost": 0.0, "real": 0.0, "path": []}]
	var best: Dictionary = {}
	var best_path: Array = []
	var best_cost = INF
	var best_real = INF
	var guard = 0
	while not q.is_empty() and guard < 400:
		guard += 1
		var cur: Dictionary = q.pop_front()
		var sid: String = cur["sys"]
		var cell: int = cur["cell"]
		var cost: float = cur["cost"]
		var real: float = cur["real"]
		var path: Array = cur["path"]
		var key = "%s:%d" % [sid, cell]
		if best.has(key) and best[key] <= cost:
			continue
		best[key] = cost
		if sid == to_sys:
			var last = path.duplicate()
			if cell != to_cell:
				var intra_d := prep_s + move_s + landing_s
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
				var intra2 := prep_s + move_s + landing_s
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
			q.append({"sys": to_side, "cell": land, "cost": step_cost, "real": step_real, "path": step_path})
	if not best_path.is_empty():
		return {"path": best_path, "real": best_real}
	var blocked := _path_to_first_blocked(map, diplomacy, faction, from_sys, from_cell, to_sys, prep_s, move_s, landing_s)
	var blocked_real := 0.0
	for st in blocked:
		blocked_real += float(st.get("duration", 0.0))
	return {"path": blocked, "real": blocked_real}

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
			"kind": "intra", "duration": prep_s + move_s + landing_s
		})
	# stop at gate if blocked
	if not map.can_pass_gate(from_sys, gate_i, faction, diplomacy):
		return steps
	return steps
