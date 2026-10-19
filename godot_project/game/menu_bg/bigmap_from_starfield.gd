extends RefCounted
class_name BigmapFromStarfield

## Load annot_complete starfield JSON → systems + 12-cell board gen (map_model parity).

const CELL_COUNT := 12
const PX_SCALE := 16.0
## Filled at load so min linked center distance >= RING_OUT*2 + 1.5*(RING_OUT*2).
var map_scale := 1.0
const VIEWER_FAC := 1
const ALLY_FAC := 2
const HOSTILE_FAC := 3
const HOSTILE2_FAC := 4

var systems: Dictionary = {} ## sid -> {id,name,center,links,kind,cells}
var edges: Array = [] ## {a,b}
var bounds_min := Vector2.ZERO
var bounds_max := Vector2.ZERO
var viewer_faction := VIEWER_FAC


func load_annot(path: String, paint_seed: int = 0) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open map JSON: %s" % path)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Bad map JSON root")
		return
	var nodes: Array = data.get("nodes", [])
	var raw_edges: Array = data.get("edges", [])
	var cx := 4096.0
	var cy := 4096.0
	if data.has("center") and data["center"] is Array and data["center"].size() >= 2:
		cx = float(data["center"][0])
		cy = float(data["center"][1])

	var by_id: Dictionary = {}
	var layout_systems: Array = []
	for n in nodes:
		var nid := str(int(n.get("id", 0)))
		var x := (float(n.get("x", 0.0)) - cx) / PX_SCALE
		## Image +Y → world +Z (north along −Z uses bearing atan2(x,-z) later).
		var z := (float(n.get("y", 0.0)) - cy) / PX_SCALE
		var kind := _node_kind(n)
		var entry := {
			"id": nid,
			"name": str(n.get("name", nid)),
			"pos": [x, z],
			"links": [],
			"kind": kind,
		}
		layout_systems.append(entry)
		by_id[nid] = entry

	edges.clear()
	for e in raw_edges:
		var a := str(int(e.get("a", -1)))
		var b := str(int(e.get("b", -1)))
		if not by_id.has(a) or not by_id.has(b):
			continue
		if not (by_id[a]["links"] as Array).has(b):
			(by_id[a]["links"] as Array).append(b)
		if not (by_id[b]["links"] as Array).has(a):
			(by_id[b]["links"] as Array).append(a)
		edges.append({"a": a, "b": b})

	systems.clear()
	bounds_min = Vector2(INF, INF)
	bounds_max = Vector2(-INF, -INF)
	for s in layout_systems:
		var sid: String = s["id"]
		var pos: Array = s["pos"]
		var center := Vector3(float(pos[0]), 0.0, float(pos[1]))
		bounds_min.x = minf(bounds_min.x, center.x)
		bounds_min.y = minf(bounds_min.y, center.z)
		bounds_max.x = maxf(bounds_max.x, center.x)
		bounds_max.y = maxf(bounds_max.y, center.z)
		var cells := _generate_cells(s, layout_systems)
		systems[sid] = {
			"id": sid,
			"name": s.get("name", sid),
			"center": center,
			"links": s.get("links", []),
			"kind": s.get("kind", "normal_system"),
			"cells": cells,
		}

	_apply_min_spacing()
	_paint_sov_random(paint_seed)
	_lock_ring_angles()
	_preview_partial_work()


func _node_kind(n: Dictionary) -> String:
	if bool(n.get("has_station", false)) or str(n.get("kind", "")) == "station":
		return "station_system"
	if bool(n.get("is_resource", false)) or str(n.get("kind", "")) == "resource":
		return "resource_system"
	return "normal_system"


func _generate_cells(sys: Dictionary, layout_systems: Array) -> Array:
	var n: int = CELL_COUNT
	var link_n := (sys.get("links", []) as Array).size()
	if link_n >= n:
		push_error("星系 %s 连向 %d 条，%d 格最多 %d 条连线加 1 格主权" % [
			str(sys.get("id", "")), link_n, n, maxi(n - 1, 0)
		])
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = hash(str(sys.get("id", "")))
	var cells: Array = []
	for i in n:
		cells.append({
			"index": i,
			"kind": BoardKinds.CellKind.EMPTY,
			"gate_to": "",
			"owner": 0,
			"work": BoardKinds.WORK_MAX,
		})
	var center := Vector3(float(sys["pos"][0]), 0, float(sys["pos"][1]))
	var used: Dictionary = {}
	var gate_specs: Array = []
	for link_id in sys.get("links", []):
		var other: Dictionary = {}
		for os in layout_systems:
			if os["id"] == link_id:
				other = os
				break
		if other.is_empty():
			continue
		var opos: Array = other["pos"]
		var dir := Vector3(float(opos[0]), 0, float(opos[1])) - center
		var bearing := atan2(dir.x, -dir.z)
		if bearing < 0.0:
			bearing += TAU
		gate_specs.append({"to": link_id, "bearing": bearing})
	gate_specs.sort_custom(func(a, b): return float(a["bearing"]) < float(b["bearing"]))
	for g in gate_specs:
		var best_i := -1
		var best_d := 999.0
		for i in n:
			if used.has(i):
				continue
			var mid := i * TAU / float(n)
			var d := absf(mid - float(g["bearing"]))
			d = mini(d, TAU - d)
			if d < best_d:
				best_d = d
				best_i = i
		if best_i < 0:
			continue
		used[best_i] = true
		cells[best_i]["kind"] = BoardKinds.CellKind.GATE
		cells[best_i]["gate_to"] = g["to"]

	var empties: Array = []
	for i in n:
		if int(cells[i]["kind"]) == BoardKinds.CellKind.EMPTY:
			empties.append(i)
	_shuffle_det(empties, local_rng)
	var kind: String = sys.get("kind", "station_system")
	var need := 3
	if kind == "station_system":
		need = 4
	if empties.size() >= need:
		var pick := 0
		for _k in 2:
			if pick >= empties.size():
				break
			cells[empties[pick]]["kind"] = BoardKinds.CellKind.RESOURCE
			pick += 1
		if pick < empties.size():
			cells[empties[pick]]["kind"] = BoardKinds.CellKind.SOV
			pick += 1
		var remain: Array = []
		for i in n:
			if int(cells[i]["kind"]) == BoardKinds.CellKind.EMPTY:
				remain.append(i)
		_shuffle_det(remain, local_rng)
		if kind == "station_system":
			if not remain.is_empty():
				cells[remain[0]]["kind"] = BoardKinds.CellKind.STATION
		elif kind == "resource_system":
			for i in remain:
				cells[i]["kind"] = BoardKinds.CellKind.RESOURCE
	elif not empties.is_empty():
		cells[empties[0]]["kind"] = BoardKinds.CellKind.SOV
		var rest: Array = []
		for ei in range(1, empties.size()):
			rest.append(empties[ei])
		_shuffle_det(rest, local_rng)
		var rp := 0
		for _rk in 2:
			if rp >= rest.size():
				break
			cells[rest[rp]]["kind"] = BoardKinds.CellKind.RESOURCE
			rp += 1
		var tail: Array = []
		for ti in range(rp, rest.size()):
			tail.append(rest[ti])
		if kind == "station_system":
			if not tail.is_empty():
				cells[tail[0]]["kind"] = BoardKinds.CellKind.STATION
		elif kind == "resource_system":
			for ti in tail:
				cells[ti]["kind"] = BoardKinds.CellKind.RESOURCE
	return cells


func _paint_sov_random(paint_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	if paint_seed == 0:
		rng.randomize()
	else:
		rng.seed = paint_seed
	var pool: Array = [VIEWER_FAC, ALLY_FAC, HOSTILE_FAC, HOSTILE2_FAC]
	for sid in systems.keys():
		var cells: Array = systems[sid]["cells"]
		for c in cells:
			if int(c.get("kind", -1)) != BoardKinds.CellKind.SOV:
				continue
			## ~12% unowned white/no fill
			if rng.randf() < 0.12:
				c["owner"] = 0
			else:
				c["owner"] = int(pool[rng.randi_range(0, pool.size() - 1)])


func sov_owner_of(sid: String) -> int:
	if not systems.has(sid):
		return 0
	for c in systems[sid]["cells"]:
		if int(c.get("kind", -1)) != BoardKinds.CellKind.SOV:
			continue
		return int(c.get("owner", 0))
	return 0


func owner_color(owner_fac: int) -> Color:
	if owner_fac == 0:
		return Color(0.25, 0.85, 0.35, 1.0)  ## unused for fill; sites with owner 0 are skipped
	var rel := "hostile"
	if owner_fac == viewer_faction:
		rel = "self"
	elif owner_fac == ALLY_FAC:
		rel = "ally"
	return BoardKinds.relation_color(rel)




func _apply_min_spacing() -> void:
	## BoardPresenter RING_OUT=26. Min center distance = 1.5 * galaxy-circle diameter (3R).
	## Rim gap = 0.5 * diameter (circles clearly separated, not 1.5-diameter air gap).
	const RING_OUT := 26.0
	var need := RING_OUT * 2.0 * 1.5
	var min_d := 1.0e20
	for e in edges:
		var a := str(e["a"])
		var b := str(e["b"])
		if not systems.has(a) or not systems.has(b):
			continue
		var ca: Vector3 = systems[a]["center"]
		var cb: Vector3 = systems[b]["center"]
		min_d = minf(min_d, ca.distance_to(cb))
	if min_d < 0.001:
		push_error("bigmap spacing: no usable linked edge distance")
		map_scale = 1.0
		_refresh_bounds()
		return
	if min_d >= need:
		map_scale = 1.0
		_refresh_bounds()
		print("bigmap spacing ok without scale min_edge=", min_d, " need=", need)
		return
	map_scale = need / min_d
	for sid in systems.keys():
		var c: Vector3 = systems[sid]["center"]
		systems[sid]["center"] = c * map_scale
	_refresh_bounds()
	print("bigmap spacing map_scale=", map_scale, " min_edge=", min_d, " need=", need)


func _refresh_bounds() -> void:
	bounds_min = Vector2(INF, INF)
	bounds_max = Vector2(-INF, -INF)
	for sid in systems.keys():
		var c: Vector3 = systems[sid]["center"]
		bounds_min.x = minf(bounds_min.x, c.x)
		bounds_min.y = minf(bounds_min.y, c.z)
		bounds_max.x = maxf(bounds_max.x, c.x)
		bounds_max.y = maxf(bounds_max.y, c.z)


func _lock_ring_angles() -> void:
	var n := CELL_COUNT
	var step := TAU / float(n)
	var half := step * 0.5
	for sid in systems.keys():
		var sys: Dictionary = systems[sid]
		var cells: Array = sys["cells"]
		var center: Vector3 = sys["center"]
		var sx := 0.0
		var sy := 0.0
		var count := 0
		for c in cells:
			if int(c.get("kind", -1)) != BoardKinds.CellKind.GATE:
				continue
			var to_id := str(c.get("gate_to", ""))
			if to_id == "" or not systems.has(to_id):
				continue
			var other: Vector3 = systems[to_id]["center"]
			var dirv := other - center
			var bearing := atan2(dirv.x, -dirv.z)
			if bearing < 0.0:
				bearing += TAU
			var ideal := bearing - float(c.get("index", 0)) * step - half
			sx += cos(ideal)
			sy += sin(ideal)
			count += 1
		var phase := 0.0
		if count > 0:
			phase = atan2(sy, sx)
		sys["ring_phase"] = phase
		for c2 in cells:
			var i := int(c2.get("index", 0))
			c2["angle_center"] = fposmod(phase + float(i) * step + half, TAU)
			c2["angle_half"] = half


func _preview_partial_work() -> void:
	for sid in systems.keys():
		for c in systems[sid]["cells"]:
			if int(c.get("kind", -1)) != BoardKinds.CellKind.SOV:
				continue
			c["work"] = BoardKinds.WORK_MAX * 0.42


func _shuffle_det(arr: Array, r: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
