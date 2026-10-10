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
		# Keep equal index angles — do NOT snap gate center to bearing (that warps/rotates ring)
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

func recompute_angles(sys_id: String, _occupants: Dictionary) -> void:
	## HARD RULE: occupancy / scale must never redistribute arcs or rotate the ring.
	## Equal sectors in fixed index order; ring_phase locked once at first call.
	if not systems.has(sys_id):
		return
	var cells: Array = systems[sys_id]["cells"]
	var n = cells.size()
	if n <= 0:
		return
	if not systems[sys_id].has("ring_phase"):
		var start0 = float(cells[0].get("angle_center", 0.0)) - float(cells[0].get("angle_half", PI / float(n)))
		systems[sys_id]["ring_phase"] = start0
	var phase = float(systems[sys_id]["ring_phase"])
	var step = TAU / float(n)
	var half = step * 0.5
	for i in n:
		cells[i]["angle_center"] = fposmod(phase + float(i) * step + half, TAU)
		cells[i]["angle_half"] = half
		cells[i]["ring_start_locked"] = true
	systems[sys_id]["cells"] = cells

func cell_world_pos(sys_id: String, cell_i: int, y: float = 0.0) -> Vector3:
	var sys: Dictionary = systems[sys_id]
	var c: Dictionary = sys["cells"][cell_i]
	var mid_r: float = (float(layout.get("ring_inner", 12)) + float(layout.get("ring_outer", 26))) * 0.5
	## Prefer smoothed visual_scale (written by starmap) over unsmoothed target scale.
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
