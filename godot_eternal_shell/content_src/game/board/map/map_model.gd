extends RefCounted
class_name BoardMapModel

var layout: Dictionary = {}
var systems: Dictionary = {}
var capture_dirty := false # id -> SystemData dict
var rng = RandomNumberGenerator.new()

func load_layout(path: String) -> void:
	var f = FileAccess.open(path, FileAccess.READ)
	layout = JSON.parse_string(f.get_as_text())
	rng.randomize()
	_build_systems()

func _build_systems() -> void:
	systems.clear()
	for s in layout.get("systems", []):
		var sid: String = s["id"]
		var pos: Array = s["pos"]
		var center = Vector3(float(pos[0]), 0.0, float(pos[1]))
		var cells = _generate_cells(s)
		systems[sid] = {
			"id": sid,
			"name": s.get("name", sid),
			"center": center,
			"links": s.get("links", []),
			"kind": s.get("kind", "station_system"),
			"cells": cells,
			"scale": 1.0,
		}
	_apply_opening_stations()

func _generate_cells(sys: Dictionary) -> Array:
	var n: int = int(layout.get("cell_count", 12))
	# deterministic per system so opening spawn points stay stable
	var local_rng = RandomNumberGenerator.new()
	local_rng.seed = hash(str(sys.get("id", "")))
	var cells: Array = []
	for i in n:
		cells.append({
			"index": i,
			"kind": BoardTypes.CellKind.EMPTY,
			"gate_to": "",
			"owner": 0,
			"work": BoardTypes.WORK_MAX,
			"angle_center": i * TAU / float(n),
			"angle_half": PI / float(n),
			"weight": 1.0,
			"bubble": false,
			"bubble_t": 0.0,
			"assigned_pilot_id": "",
			"last_assignee": "",
		})
	# 1) gates by link bearing
	var center = Vector3(float(sys["pos"][0]), 0, float(sys["pos"][1]))
	var used: Dictionary = {}
	var gate_specs: Array = []
	for link_id in sys.get("links", []):
		var other: Dictionary = {}
		for os in layout.get("systems", []):
			if os["id"] == link_id:
				other = os
				break
		if other.is_empty():
			continue
		var opos: Array = other["pos"]
		var dir = Vector3(float(opos[0]), 0, float(opos[1])) - center
		var bearing = atan2(dir.x, -dir.z) # 0 = -Z north
		if bearing < 0.0:
			bearing += TAU
		gate_specs.append({"to": link_id, "bearing": bearing})
	gate_specs.sort_custom(func(a, b): return a["bearing"] < b["bearing"])
	for g in gate_specs:
		var best_i = -1
		var best_d = 999.0
		for i in n:
			if used.has(i):
				continue
			var mid = i * TAU / float(n)
			var d = abs(mid - g["bearing"])
			d = mini(d, TAU - d)
			if d < best_d:
				best_d = d
				best_i = i
		if best_i < 0:
			continue
		used[best_i] = true
		cells[best_i]["kind"] = BoardTypes.CellKind.GATE
		cells[best_i]["gate_to"] = g["to"]
	# 2) rest already EMPTY
	# 3) pick 2 resource + 1 sov from empties
	var empties: Array = []
	for i in n:
		if cells[i]["kind"] == BoardTypes.CellKind.EMPTY:
			empties.append(i)
	_shuffle_det(empties, local_rng)
	var pick = 0
	for _k in 2:
		if pick >= empties.size():
			break
		cells[empties[pick]]["kind"] = BoardTypes.CellKind.RESOURCE
		pick += 1
	if pick < empties.size():
		cells[empties[pick]]["kind"] = BoardTypes.CellKind.SOV
		pick += 1
	# remaining empties after step 3
	var remain: Array = []
	for i in n:
		if cells[i]["kind"] == BoardTypes.CellKind.EMPTY:
			remain.append(i)
	_shuffle_det(remain, local_rng)
	var kind: String = sys.get("kind", "station_system")
	if kind == "station_system":
		if not remain.is_empty():
			cells[remain[0]]["kind"] = BoardTypes.CellKind.STATION
			remain.remove_at(0)
	elif kind == "resource_system":
		for i in remain:
			cells[i]["kind"] = BoardTypes.CellKind.RESOURCE
		remain.clear()
	return cells

func _apply_opening_stations() -> void:
	var own: Dictionary = layout.get("opening_stations", {})
	for sid in own.keys():
		if not systems.has(sid):
			continue
		for c in systems[sid]["cells"]:
			if c["kind"] == BoardTypes.CellKind.STATION:
				c["owner"] = int(own[sid])
				c["work"] = BoardTypes.WORK_MAX

func find_cell_of_kind(sys_id: String, kind: int, gate_to: String = "") -> int:
	if not systems.has(sys_id):
		return -1
	var cells: Array = systems[sys_id]["cells"]
	var candidates: Array = []
	for c in cells:
		if int(c["kind"]) != kind:
			continue
		if kind == BoardTypes.CellKind.GATE and gate_to != "" and str(c["gate_to"]) != gate_to:
			continue
		candidates.append(int(c["index"]))
	if candidates.is_empty():
		return -1
	return int(candidates[rng.randi() % candidates.size()])

func station_cell(sys_id: String) -> int:
	return find_cell_of_kind(sys_id, BoardTypes.CellKind.STATION)

func recompute_angles(sys_id: String, _occupants: Dictionary = {}) -> bool:
	## Arc widths from cell.weight (base 1 + ships); index order fixed; ring_phase rotates whole ring.
	if not systems.has(sys_id):
		return false
	var cells: Array = systems[sys_id]["cells"]
	var n = cells.size()
	if n <= 0:
		return false
	if not systems[sys_id].has("ring_phase"):
		var start0 = float(cells[0].get("angle_center", 0.0)) - float(cells[0].get("angle_half", PI / float(n)))
		systems[sys_id]["ring_phase"] = start0
	return _apply_weighted_phase(sys_id)

func _compute_spans(cells: Array) -> PackedFloat32Array:
	var n = cells.size()
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(n)
	var total := 0.0
	for i in n:
		var w = maxf(float(cells[i].get("weight", 1.0)), 0.01)
		raw[i] = w
		total += w
	if total <= 0.0:
		total = float(n)
	var min_span = deg_to_rad(8.0)
	var max_span = deg_to_rad(120.0)
	var spans: PackedFloat32Array = PackedFloat32Array()
	spans.resize(n)
	for i in n:
		spans[i] = TAU * raw[i] / total
	for _iter in 10:
		var locked := 0.0
		var free_w := 0.0
		var free_i: Array = []
		for i in n:
			if spans[i] <= min_span + 1e-5:
				spans[i] = min_span
				locked += min_span
			elif spans[i] >= max_span - 1e-5:
				spans[i] = max_span
				locked += max_span
			else:
				free_i.append(i)
				free_w += raw[i]
		var remain = TAU - locked
		if free_i.is_empty() or remain <= 1e-6 or free_w <= 1e-6:
			break
		var changed = false
		for i in free_i:
			var s = remain * raw[i] / free_w
			var c = clampf(s, min_span, max_span)
			if absf(c - spans[i]) > 1e-5:
				changed = true
			spans[i] = c
		var sum_s := 0.0
		for i in n:
			sum_s += spans[i]
		if sum_s > 1e-6:
			var k = TAU / sum_s
			for i in n:
				spans[i] *= k
		if not changed:
			break
	return spans

func _apply_weighted_phase(sys_id: String) -> bool:
	var cells: Array = systems[sys_id]["cells"]
	var n = cells.size()
	var spans = _compute_spans(cells)
	var phase = float(systems[sys_id].get("ring_phase", 0.0))
	var changed = false
	var a = phase
	for i in n:
		var span = spans[i]
		var half = span * 0.5
		var center = fposmod(a + half, TAU)
		if absf(float(cells[i].get("angle_half", 0.0)) - half) > 0.0005 \
			or absf(_angle_delta(float(cells[i].get("angle_center", 0.0)), center)) > 0.0005:
			changed = true
		cells[i]["angle_half"] = half
		cells[i]["angle_center"] = center
		cells[i]["ring_start_locked"] = true
		a += span
	systems[sys_id]["cells"] = cells
	return changed

func _apply_ring_phase(sys_id: String) -> void:
	_apply_weighted_phase(sys_id)

func _angle_delta(a: float, b: float) -> float:
	var d = fposmod(a - b + PI, TAU) - PI
	return d

func desired_ring_phase(sys_id: String) -> float:
	## Gate alignment uses EQUAL index spans only — weighted arcs must not spin the ring
	## (occupancy fattening neighbors was shifting phase by ~60° / 2 cells).
	if not systems.has(sys_id):
		return 0.0
	var sys: Dictionary = systems[sys_id]
	var cells: Array = sys["cells"]
	var n = cells.size()
	if n <= 0:
		return float(sys.get("ring_phase", 0.0))
	var step = TAU / float(n)
	var half = step * 0.5
	var center: Vector3 = sys["center"]
	var sx := 0.0
	var sy := 0.0
	var count := 0
	for i in n:
		var c: Dictionary = cells[i]
		if int(c["kind"]) != BoardTypes.CellKind.GATE:
			continue
		var to_id: String = str(c.get("gate_to", ""))
		if to_id == "" or not systems.has(to_id):
			continue
		var other: Vector3 = systems[to_id]["center"]
		var dir = other - center
		var bearing = atan2(dir.x, -dir.z)
		if bearing < 0.0:
			bearing += TAU
		## Equal layout: phase + i*step + half = bearing
		var ideal = bearing - float(i) * step - half
		sx += cos(ideal)
		sy += sin(ideal)
		count += 1
	if count <= 0:
		return float(sys.get("ring_phase", 0.0))
	return fposmod(atan2(sy, sx), TAU)

func tick_ring_align(delta: float) -> bool:
	var moved := false
	var rate := 1.2 ## rad/s
	for sid in systems.keys():
		var want := desired_ring_phase(str(sid))
		var cur := float(systems[sid].get("ring_phase", want))
		var err := _angle_delta(want, cur)
		if absf(err) < 0.0005:
			if absf(err) > 0.00005:
				systems[sid]["ring_phase"] = want
				_apply_ring_phase(str(sid))
				moved = true
			continue
		var step = clampf(err, -rate * delta, rate * delta)
		systems[sid]["ring_phase"] = fposmod(cur + step, TAU)
		_apply_ring_phase(str(sid))
		moved = true
	return moved

func cell_world_pos(sys_id: String, cell_i: int, y: float = 0.0) -> Vector3:
	var sys: Dictionary = systems[sys_id]
	var c: Dictionary = sys["cells"][cell_i]
	var mid_r: float = (float(layout.get("ring_inner", 12)) + float(layout.get("ring_outer", 26))) * 0.5
	var sc: float = float(sys.get("visual_scale", sys.get("scale", 1.0)))
	mid_r *= sc
	var a: float = c["angle_center"]
	var local = Vector3(sin(a) * mid_r, y, -cos(a) * mid_r)
	return sys["center"] + local

func can_pass_gate(sys_id: String, cell_i: int, faction: int, diplomacy: Dictionary) -> bool:
	var c: Dictionary = systems[sys_id]["cells"][cell_i]
	if int(c["kind"]) != BoardTypes.CellKind.GATE:
		return false
	var owner = int(c["owner"])
	if owner == 0:
		return false
	if owner == faction:
		return true
	var rels: Dictionary = diplomacy.get("relations", {})
	var mine: Dictionary = rels.get(str(faction), {})
	return str(mine.get(str(owner), "hostile")) == "ally"


func _shuffle_det(arr: Array, r: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j = r.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
