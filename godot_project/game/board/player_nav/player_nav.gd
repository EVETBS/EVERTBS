extends RefCounted
class_name BoardPlayerNav

## Shortest-time path: start -> gates -> dest. Same-system one hop.

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
	if from_sys == to_sys:
		if from_cell == to_cell:
			return []
		return [{
			"sys": from_sys, "from": from_cell, "to": to_cell,
			"kind": "intra",
			"duration": prep_s + move_s + landing_s
		}]
	# BFS on systems with gate edges owned by self/ally
	var q: Array = [{"sys": from_sys, "cell": from_cell, "cost": 0.0, "path": []}]
	var best: Dictionary = {}
	var best_path: Array = []
	var best_cost = INF
	var guard = 0
	while not q.is_empty() and guard < 200:
		guard += 1
		var cur: Dictionary = q.pop_front()
		var sid: String = cur["sys"]
		var cell: int = cur["cell"]
		var cost: float = cur["cost"]
		var path: Array = cur["path"]
		var key = "%s:%d" % [sid, cell]
		if best.has(key) and best[key] <= cost:
			continue
		best[key] = cost
		if sid == to_sys:
			var last = path.duplicate()
			if cell != to_cell:
				last.append({
					"sys": sid, "from": cell, "to": to_cell,
					"kind": "intra",
					"duration": prep_s + move_s + landing_s
				})
				cost += prep_s + move_s + landing_s
			if cost < best_cost:
				best_cost = cost
				best_path = last
			continue
		var sys: Dictionary = map.systems[sid]
		for c in sys["cells"]:
			if int(c["kind"]) != BoardTypes.CellKind.GATE:
				continue
			var gi: int = c["index"]
			if not map.can_pass_gate(sid, gi, faction, diplomacy):
				# stop path at impassable gate via nearest route only — enqueue stop
				continue
			var to_side: String = c["gate_to"]
			var land = _paired_gate(map, to_side, sid)
			if land < 0:
				continue
			var step_path = path.duplicate()
			var step_cost = cost
			if cell != gi:
				step_path.append({
					"sys": sid, "from": cell, "to": gi,
					"kind": "intra",
					"duration": prep_s + move_s + landing_s
				})
				step_cost += prep_s + move_s + landing_s
			step_path.append({
				"sys": sid, "from": gi, "to": land,
				"to_sys": to_side, "kind": "jump",
				"duration": prep_s + jump_s + landing_s
			})
			step_cost += prep_s + jump_s + landing_s
			q.append({"sys": to_side, "cell": land, "cost": step_cost, "path": step_path})
	if not best_path.is_empty():
		return best_path
	# fallback: walk toward first impassable gate on nearest topology
	return _path_to_first_blocked(map, diplomacy, faction, from_sys, from_cell, to_sys, prep_s, move_s, landing_s)

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
