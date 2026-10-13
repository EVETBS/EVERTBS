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
	var link_n := (sys.get("links", []) as Array).size()
	## 12 cells keep at most 11 gates plus 1 sovereignty. The system stays on the map.
	if link_n >= n:
		push_error("星系 %s 连向 %d 条，%d 格最多 %d 条连线加 1 格主权" % [str(sys.get("id", "")), link_n, n, maxi(n - 1, 0)])
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
			"bubble_remain": 0.0,
			"assigned_pilot_id": "",
			"last_assignee": "",
			"auto_assigned": false,
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
	# 3) 2 resource + 1 sov when the empties can hold them (and a station, on station systems).
	#    Shorter remainder: sovereignty first, then resource / station / empty.
	var empties: Array = []
	for i in n:
		if cells[i]["kind"] == BoardTypes.CellKind.EMPTY:
			empties.append(i)
	_shuffle_det(empties, local_rng)
	var kind: String = sys.get("kind", "station_system")
	var need := 3
	if kind == "station_system":
		need = 4
	if empties.size() >= need:
		var pick = 0
		for _k in 2:
			if pick >= empties.size():
				break
			cells[empties[pick]]["kind"] = BoardTypes.CellKind.RESOURCE
			pick += 1
		if pick < empties.size():
			cells[empties[pick]]["kind"] = BoardTypes.CellKind.SOV
			pick += 1
		var remain: Array = []
		for i in n:
			if cells[i]["kind"] == BoardTypes.CellKind.EMPTY:
				remain.append(i)
		_shuffle_det(remain, local_rng)
		if kind == "station_system":
			if not remain.is_empty():
				cells[remain[0]]["kind"] = BoardTypes.CellKind.STATION
				remain.remove_at(0)
		elif kind == "resource_system":
			for i in remain:
				cells[i]["kind"] = BoardTypes.CellKind.RESOURCE
			remain.clear()
	elif not empties.is_empty():
		cells[empties[0]]["kind"] = BoardTypes.CellKind.SOV
		var rest: Array = []
		for ei in range(1, empties.size()):
			rest.append(empties[ei])
		_shuffle_det(rest, local_rng)
		var rp := 0
		for _rk in 2:
			if rp >= rest.size():
				break
			cells[rest[rp]]["kind"] = BoardTypes.CellKind.RESOURCE
			rp += 1
		var tail: Array = []
		for ti in range(rp, rest.size()):
			tail.append(rest[ti])
		if kind == "station_system":
			if not tail.is_empty():
				cells[tail[0]]["kind"] = BoardTypes.CellKind.STATION
		elif kind == "resource_system":
			for ti in tail:
				cells[ti]["kind"] = BoardTypes.CellKind.RESOURCE
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

func _cell_min_span_rad(cell: Dictionary) -> float:
	## Gate wedges never thinner than 30° (BOARD_AND_INPUT).
	if int(cell.get("kind", -1)) == BoardTypes.CellKind.GATE:
		return deg_to_rad(30.0)
	return deg_to_rad(8.0)

func _compute_spans(cells: Array) -> PackedFloat32Array:
	var n = cells.size()
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(n)
	var mins: PackedFloat32Array = PackedFloat32Array()
	mins.resize(n)
	var total := 0.0
	for i in n:
		var w = maxf(float(cells[i].get("weight", 1.0)), 0.01)
		raw[i] = w
		mins[i] = _cell_min_span_rad(cells[i])
		total += w
	if total <= 0.0:
		total = float(n)
	var max_span = deg_to_rad(120.0)
	var spans: PackedFloat32Array = PackedFloat32Array()
	spans.resize(n)
	for i in n:
		spans[i] = TAU * raw[i] / total
	for _iter in 12:
		var locked := 0.0
		var free_w := 0.0
		var free_i: Array = []
		for i in n:
			var lo := float(mins[i])
			if spans[i] <= lo + 1e-5:
				spans[i] = lo
				locked += lo
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
			var lo2 := float(mins[i])
			var s = remain * raw[i] / free_w
			var c = clampf(s, lo2, max_span)
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
			## Re-enforce per-cell mins after normalize (gates stay ≥30°).
			for i in n:
				spans[i] = maxf(spans[i], float(mins[i]))
			var sum2 := 0.0
			for i in n:
				sum2 += spans[i]
			if sum2 > TAU + 1e-4:
				## Shrink non-floor cells proportionally.
				var floor_sum := 0.0
				var flex := 0.0
				for i in n:
					if spans[i] <= float(mins[i]) + 1e-5:
						floor_sum += spans[i]
					else:
						flex += spans[i]
				var room := maxf(TAU - floor_sum, 0.0)
				if flex > 1e-6 and room >= 0.0:
					var fk := room / flex
					for i in n:
						if spans[i] > float(mins[i]) + 1e-5:
							spans[i] *= fk
		if not changed:
			break
	# #region agent log
	var path := "H:/debug-59aff0.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f and Engine.get_process_frames() % 120 == 0:
		var gate_spans: Array = []
		for i in n:
			if int(cells[i].get("kind", -1)) == BoardTypes.CellKind.GATE:
				gate_spans.append(snappedf(rad_to_deg(spans[i]), 0.1))
		f.seek_end()
		f.store_line(JSON.stringify({
			"sessionId": "59aff0", "hypothesisId": "GATE",
			"location": "map_model._compute_spans", "message": "gate_min30",
			"data": {"gates_deg": gate_spans, "runId": "gate-arc"},
			"timestamp": Time.get_ticks_msec()
		}))
		f.close()
	# #endregion
	return spans

func _apply_weighted_phase(sys_id: String) -> bool:
	## Write soft targets only — draw/pos lerp in tick_smooth_arcs (BH-35).
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
		var th = float(cells[i].get("target_half", cells[i].get("angle_half", half)))
		var tc = float(cells[i].get("target_center", cells[i].get("angle_center", center)))
		## Only commit targets when they move enough — keeps 200ms 补间 end-point stable.
		if absf(th - half) > 0.012 or absf(_angle_delta(tc, center)) > 0.012:
			changed = true
			cells[i]["target_half"] = half
			cells[i]["target_center"] = center
		elif not cells[i].has("target_half"):
			cells[i]["target_half"] = half
			cells[i]["target_center"] = center
		if not cells[i].has("angle_half"):
			cells[i]["angle_half"] = half
			cells[i]["angle_center"] = center
		cells[i]["ring_start_locked"] = true
		a += span
	systems[sys_id]["cells"] = cells
	return changed

func _apply_ring_phase(sys_id: String) -> void:
	_apply_weighted_phase(sys_id)
	## Hard snap visual = target (setup / bias lock).
	var keys: Array = []
	var spans: Array = []
	for c in systems[sys_id]["cells"]:
		c["angle_half"] = float(c.get("target_half", c.get("angle_half", 0.0)))
		c["angle_center"] = float(c.get("target_center", c.get("angle_center", 0.0)))
		keys.append(fposmod(float(c["angle_center"]) - float(c["angle_half"]), TAU))
		spans.append(float(c["angle_half"]) * 2.0)
	systems[sys_id]["key_ang"] = keys
	systems[sys_id]["span_from"] = spans.duplicate()
	systems[sys_id]["span_to"] = spans.duplicate()
	systems[sys_id]["arc_tween_t"] = 1.0
	systems[sys_id]["arc_retarget_lock"] = 0.0

func tick_smooth_arcs(delta: float) -> bool:
	## Span tween from locked ring_phase — cell index order never crosses (BH-23).
	var moved := false
	const ARC_TWEEN_DUR := 0.35
	const RETARGET_EPS := 0.022 ## ~1.25 deg span chatter
	const HUGE_JUMP := 0.12
	for sid in systems.keys():
		var cells: Array = systems[sid]["cells"]
		var n: int = cells.size()
		if n < 2:
			continue
		var phase := float(systems[sid].get("ring_phase", 0.0))
		var desired: PackedFloat32Array = PackedFloat32Array()
		desired.resize(n)
		for i in n:
			desired[i] = maxf(float(cells[i].get("target_half", cells[i].get("angle_half", PI / float(n)))) * 2.0, 0.001)
		## Normalize desired to TAU (clamp artifacts).
		var dsum := 0.0
		for i in n:
			dsum += desired[i]
		if dsum > 1e-6:
			var dk := TAU / dsum
			for i in n:
				desired[i] *= dk
		var to_sp: Array = systems[sid].get("span_to", []) as Array
		var max_d := 0.0
		var need_retarget := to_sp.size() != n
		if not need_retarget:
			for i in n:
				var d := absf(desired[i] - float(to_sp[i]))
				max_d = maxf(max_d, d)
				if d > RETARGET_EPS:
					need_retarget = true
		var lock := float(systems[sid].get("arc_retarget_lock", 0.0))
		lock = maxf(0.0, lock - delta)
		systems[sid]["arc_retarget_lock"] = lock
		var from_sp: Array = systems[sid].get("span_from", []) as Array
		if need_retarget:
			if lock <= 0.0 or max_d >= HUGE_JUMP:
				## Capture current displayed spans as from.
				from_sp = []
				for i in n:
					from_sp.append(maxf(float(cells[i].get("angle_half", PI / float(n))) * 2.0, 0.001))
				var fsum := 0.0
				for i in n:
					fsum += float(from_sp[i])
				if fsum > 1e-6:
					var fk := TAU / fsum
					for i in n:
						from_sp[i] = float(from_sp[i]) * fk
				var to_arr: Array = []
				for i in n:
					to_arr.append(desired[i])
				systems[sid]["span_from"] = from_sp
				systems[sid]["span_to"] = to_arr
				systems[sid]["arc_tween_t"] = 0.0
				systems[sid]["arc_retarget_lock"] = ARC_TWEEN_DUR
				to_sp = to_arr
			else:
				var to_arr2: Array = []
				for i in n:
					to_arr2.append(desired[i])
				systems[sid]["span_to"] = to_arr2
				to_sp = to_arr2
		if from_sp.size() != n:
			from_sp = []
			for i in n:
				from_sp.append(float(to_sp[i]) if i < to_sp.size() else desired[i])
			systems[sid]["span_from"] = from_sp
		var t: float = float(systems[sid].get("arc_tween_t", 1.0))
		var spans: PackedFloat32Array = PackedFloat32Array()
		spans.resize(n)
		if t < 1.0:
			t = minf(1.0, t + delta / ARC_TWEEN_DUR)
			systems[sid]["arc_tween_t"] = t
			var u := t * t * (3.0 - 2.0 * t)
			for i in n:
				spans[i] = lerpf(float(from_sp[i]), float(to_sp[i]), u)
			moved = true
		else:
			for i in n:
				spans[i] = float(to_sp[i]) if i < to_sp.size() else float(desired[i])
		## Keep sum exactly TAU after lerp, then rebuild keys from locked phase.
		var ssum := 0.0
		for i in n:
			ssum += spans[i]
		if ssum > 1e-6:
			var sk := TAU / ssum
			for i in n:
				spans[i] *= sk
		var keys: Array = []
		keys.resize(n)
		var a := phase
		for i in n:
			keys[i] = fposmod(a, TAU)
			cells[i]["angle_half"] = spans[i] * 0.5
			cells[i]["angle_center"] = fposmod(a + spans[i] * 0.5, TAU)
			a += spans[i]
		systems[sid]["key_ang"] = keys
		systems[sid]["cells"] = cells
		# #region agent log
		if moved and Engine.get_process_frames() % 45 == 0:
			var path := "H:/debug-59aff0.log"
			var f := FileAccess.open(path, FileAccess.READ_WRITE)
			if f == null:
				f = FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.seek_end()
				f.store_line(JSON.stringify({
					"sessionId": "59aff0", "hypothesisId": "BH23",
					"location": "map_model.tick_smooth_arcs",
					"message": "span_rebuild",
					"data": {
						"sid": str(sid), "phase": phase,
						"k0": keys[0], "k1": keys[1] if n > 1 else -1.0,
						"runId": "arc-order"
					},
					"timestamp": Time.get_ticks_msec()
				}))
				f.close()
		# #endregion
	return moved

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

func tick_ring_align(_delta: float) -> bool:
	## BH-23: ring_phase locked at setup (identity+bias). Never mean-align / spin.
	return false

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
