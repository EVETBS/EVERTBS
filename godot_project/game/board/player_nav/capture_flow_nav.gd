extends RefCounted
## Godot 4.x 独立教学示例，尚未接入或运行验证。
## 同一实例只服务一个阵营 + 移动代价配置 + 地图/外交快照。
## 来源与接线说明：RTS_PATHFINDING_TECHNIQUE_NOTES_2026-10-22.md
## 不修改舰船、占领、网络或显示；只返回执行前缀和等待原因。

const MAX_CACHED_GOALS := 8
var _incoming: Dictionary = {}
var _fields: Dictionary = {}
var _goal_order: Array = []
var _revision: int = 0
var _valid: bool = false
var _serial: int = 0


## edge = {from: String, to: String, cost: float, step: Dictionary,
##         requires_capture: bool, capturable: bool}
## requires_capture 表示当前不能通过；capturable 表示规则允许将其占领。
## cost 是移动耗时；本例没有擅自加入未知的战斗/占领耗时。
## configure 必须仅在快照变化时调用，不能每艘舰/每帧调用。
func configure(nodes: Array, edges: Array, revision: int) -> bool:
	_incoming.clear()
	_fields.clear()
	_goal_order.clear()
	_revision = revision
	_valid = false
	for node in nodes:
		_incoming[str(node)] = []
	for value in edges:
		var edge: Dictionary = value.duplicate(true)
		var source := str(edge.get("from", ""))
		var target := str(edge.get("to", ""))
		var cost := float(edge.get("cost", -1.0))
		if not _incoming.has(source) or not _incoming.has(target):
			push_error("导航边引用了不存在的节点")
			return false
		if not is_finite(cost) or cost < 0.0 or not edge.has("step"):
			push_error("导航边必须有非负有限代价和 step")
			return false
		edge["from"] = source
		edge["to"] = target
		edge["cost"] = cost
		_incoming[target].append(edge)
	_valid = true
	return true


func plan(start: String, goal: String) -> Dictionary:
	var result := {
		"status": "UNREACHABLE", "steps": [], "blocked_gate": {},
		"goal": goal, "revision": _revision, "route_cost": INF,
		"mode": "",
	}
	if not _valid or not _incoming.has(start) or not _incoming.has(goal):
		result["status"] = "INVALID"
		return result
	if start == goal:
		result["status"] = "ARRIVED"
		result["route_cost"] = 0.0
		return result
	var pair := _goal_fields(goal)
	var field: Dictionary = pair["open"]
	result["mode"] = "OPEN_ONLY"
	if not field["distance"].has(start):
		# 只有完整开放图不可达时，才启用允许占领的战略图。
		if not pair.has("capture"):
			pair["capture"] = _reverse_dijkstra(goal, true)
		field = pair["capture"]
		result["mode"] = "CAPTURE_ROUTE"
	if not field["distance"].has(start):
		return result
	result["route_cost"] = float(field["distance"][start])
	var steps: Array = []
	var cursor := start
	var seen: Dictionary = {}
	while cursor != goal:
		if seen.has(cursor) or not field["next"].has(cursor):
			# 不把损坏/不完整的路线当作可以执行的部分路径。
			result["status"] = "INVALID"
			return result
		seen[cursor] = true
		var edge: Dictionary = field["next"][cursor]
		if bool(edge.get("requires_capture", false)):
			var step: Dictionary = edge["step"]
			result["status"] = "WAIT_CAPTURE" if steps.is_empty() else "MOVE_TO_CAPTURE"
			result["steps"] = steps
			result["blocked_gate"] = {
				"node": cursor, "sys": str(step.get("sys", "")),
				"cell": int(step.get("from", -1)),
			}
			return result  # 绝不把尚未开放的 jump 放进执行队列。
		steps.append(edge["step"].duplicate(true))
		cursor = str(edge["to"])
	result["status"] = "READY"
	result["steps"] = steps
	return result


func _goal_fields(goal: String) -> Dictionary:
	if not _fields.has(goal):
		if _goal_order.size() >= MAX_CACHED_GOALS:
			_fields.erase(str(_goal_order.pop_front()))
		_goal_order.append(goal)
		_fields[goal] = {"open": _reverse_dijkstra(goal, false)}
	return _fields[goal]


## 在反向邻接表上搜索，但使用原方向边的权限与代价。
## 不能因为 B->A 开放就误认为 A->B 也开放。
func _reverse_dijkstra(goal: String, allow_capture: bool) -> Dictionary:
	var distance: Dictionary = {goal: 0.0}
	var next_edge: Dictionary = {}
	var heap: Array = []
	_serial = 0
	_heap_push(heap, goal, 0.0)
	while not heap.is_empty():
		var item := _heap_pop(heap)
		var current := str(item["node"])
		var known := float(item["cost"])
		if known > float(distance.get(current, INF)):
			continue
		for edge in _incoming[current]:
			if bool(edge.get("requires_capture", false)):
				if not allow_capture or not bool(edge.get("capturable", false)):
					continue
			var previous := str(edge["from"])
			var candidate := known + float(edge["cost"])
			if not is_finite(candidate):
				continue
			if candidate < float(distance.get(previous, INF)):
				distance[previous] = candidate
				next_edge[previous] = edge
				_heap_push(heap, previous, candidate)
	return {"distance": distance, "next": next_edge}


## 二叉最小堆；相同代价按入队顺序打破平局。
## 需调用方使用稳定的节点/边顺序；浮点计算仍不保证跨平台锁步一致。
func _less(a: Dictionary, b: Dictionary) -> bool:
	if float(a["cost"]) == float(b["cost"]):
		return int(a["serial"]) < int(b["serial"])
	return float(a["cost"]) < float(b["cost"])


func _heap_push(heap: Array, node: String, cost: float) -> void:
	_serial += 1
	heap.append({"node": node, "cost": cost, "serial": _serial})
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _less(heap[i], heap[parent]):
			break
		var swap: Dictionary = heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


func _heap_pop(heap: Array) -> Dictionary:
	var top: Dictionary = heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = tail
	var i := 0
	while true:
		var left := i * 2 + 1
		if left >= heap.size():
			break
		var child := left
		var right := left + 1
		if right < heap.size() and _less(heap[right], heap[left]):
			child = right
		if not _less(heap[child], heap[i]):
			break
		var swap: Dictionary = heap[i]
		heap[i] = heap[child]
		heap[child] = swap
		i = child
	return top


static func node_key(system_id: String, cell: int) -> String:
	# 避免星系名本身带分隔符导致键冲突。
	return JSON.stringify([system_id, cell])


## 项目适配入口：不 preload 项目类，便于把本文件单独阅读/搬运。
## profile = {prep, move, landing, jump}，由现有 _dev_* 的读数构成。
## land_multiplier(from_cell, to_cell, cell_count) -> float
## can_capture(system_id, gate_cell, faction) -> bool
## gate_kind 由调用方传入 BoardTypes.CellKind.GATE。
## 本例把所有格保留为节点，星系内直达；不是完整 HPA* 实现。
func configure_from_board(
	board_map: Object, diplomacy: Dictionary, faction: int,
	profile: Dictionary, gate_kind: int,
	land_multiplier: Callable, can_capture: Callable, revision: int,
	jump_scale: Callable = Callable()
) -> bool:
	_valid = false
	for name in ["prep", "move", "landing", "jump"]:
		if not profile.has(name):
			return false
		var value := float(profile[name])
		if not is_finite(value) or value < 0.0:
			return false
	if not land_multiplier.is_valid() or not can_capture.is_valid():
		return false
	var nodes: Array = []
	var edges: Array = []
	var systems: Dictionary = board_map.systems
	var ids: Array = systems.keys()
	ids.sort()
	for sid_value in ids:
		var sid := str(sid_value)
		var cells: Array = systems[sid]["cells"]
		for source in cells:
			var from_cell := int(source["index"])
			var source_key := node_key(sid, from_cell)
			nodes.append(source_key)
			# 项目当前同系可任意格直达，所以不能套矩形网格邻接。
			for target in cells:
				var to_cell := int(target["index"])
				if to_cell == from_cell:
					continue
				var mul := float(land_multiplier.call(from_cell, to_cell, cells.size()))
				if not is_finite(mul) or mul < 0.0:
					return false
				var cost := float(profile["prep"]) + float(profile["move"]) + float(profile["landing"]) * mul
				edges.append({
					"from": source_key, "to": node_key(sid, to_cell), "cost": cost,
					"step": {"kind": "intra", "sys": sid, "from": from_cell,
						"to": to_cell, "duration": cost},
				})
			if int(source["kind"]) != gate_kind:
				continue
			var target_sys := str(source.get("gate_to", ""))
			if not systems.has(target_sys):
				continue
			var landing := -1
			for opposite in systems[target_sys]["cells"]:
				if int(opposite["kind"]) == gate_kind and str(opposite.get("gate_to", "")) == sid:
					landing = int(opposite["index"])
					break  # 与当前地图一致：一对星系之间只取一扇配对门。
			if landing < 0:
				continue
			var is_open := bool(board_map.can_pass_gate(sid, from_cell, faction, diplomacy))
			var may_capture := false
			if not is_open:
				may_capture = bool(can_capture.call(sid, from_cell, faction))
			var jump_cost := float(profile["jump"]) + float(profile["landing"])
			var scale := 1.0
			if jump_scale.is_valid():
				scale = float(jump_scale.call(sid, target_sys))
				if not is_finite(scale) or scale <= 0.0:
					scale = 1.0
			edges.append({
				"from": source_key, "to": node_key(target_sys, landing), "cost": jump_cost * scale,
				"requires_capture": not is_open, "capturable": may_capture,
				"step": {"kind": "jump", "sys": sid, "from": from_cell,
					"to_sys": target_sys, "to": landing, "duration": jump_cost},
			})
	return configure(nodes, edges, revision)
