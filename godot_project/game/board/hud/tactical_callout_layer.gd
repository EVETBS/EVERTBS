extends Node3D
class_name TacticalCalloutLayer
## Per occupied cell: screen-aligned rect + leader; slots follow tactical_yaw.

const COLS := 6
## Slot world size per font_scale unit (calibrated to prior SLOT@SC=5.0625).
const SLOT_W0 := 4.15  ## minimum slot; widened to the wrapped plate
const SLOT_H0 := 4.40
const FRAME_PAD0 := 0.178
const RING_GAP := 3.2
const HORIZ_LEN0 := 0.79
const TWEEN_S := 0.20
## Frame / slot ease when the box moves, flips side, or yaw changes.
const SLIDE_TAU := 0.16
const PICK_LAYER := 2
const RELAX_ITERS := 12
const RELAX_GAP := 1.2

var font_scale: float = 7.7
## unit id -> Vector2 world size of the wrapped tactical nameplate.
var plate_size_fn: Callable = Callable()
## Matches BoardCamera.tactical_yaw — frame/slots stay screen-parallel.
var view_yaw: float = 0.0
var _map: BoardMapModel
var _starmap: Node
var _active := false
var _cells: Dictionary = {}
var _oh_tween: Dictionary = {}

func _screen_right() -> Vector3:
	return Vector3(cos(view_yaw), 0.0, sin(view_yaw))

func _screen_up() -> Vector3:
	## Same as BoardCamera nadir up (screen-up on XZ).
	return Vector3(sin(view_yaw), 0.0, -cos(view_yaw))

func setup(map: BoardMapModel, starmap: Node) -> void:
	_map = map
	_starmap = starmap

func set_active(on: bool) -> void:
	_active = on
	visible = on
	if not on:
		_clear_all()

func _clear_all() -> void:
	for k in _cells.keys():
		_free_cell(str(k))
	_cells.clear()
	_oh_tween.clear()

func _free_cell(key: String) -> void:
	if not _cells.has(key):
		return
	var d: Dictionary = _cells[key]
	var fr: Node = d.get("frame")
	if fr and is_instance_valid(fr):
		fr.queue_free()
	var ln: Node = d.get("line")
	if ln and is_instance_valid(ln):
		ln.queue_free()
	_cells.erase(key)

func sync_occupied(units: Array, claimants_fn: Callable, delta: float) -> void:
	if not _active or _map == null:
		return
	var want: Dictionary = {}
	## TACTICAL_TOPDOWN §9: INVULN stays on departure; LANDING/IDLE/PREP use settled cell.
	for u in units:
		if not u.get("alive", false):
			continue
		var sid := str(u.get("sys", ""))
		var cell := int(u.get("cell", -1))
		var ph := int(u.get("phase", 0))
		if ph == BoardTypes.MovePhase.INVULN:
			sid = str(u.get("from_sys", sid))
			cell = int(u.get("from_cell", cell))
		## LANDING already has sys/cell = dest; IDLE/PREP = current.
		if sid == "" or cell < 0:
			continue
		var ck := "%s:%d" % [sid, cell]
		if not want.has(ck):
			want[ck] = []
		var arr: Array = want[ck]
		var uid := str(u["id"])
		if not arr.has(uid):
			arr.append(uid)
	## Prefer claimants order (enter-cell time) when it lists the same occupants.
	if claimants_fn.is_valid():
		for k2 in want.keys():
			var parts: PackedStringArray = str(k2).split(":")
			if parts.size() < 2:
				continue
			var ids: Array = claimants_fn.call(str(parts[0]), int(parts[1]))
			if ids is Array and not ids.is_empty():
				## Merge: claimants first (already enter-time sorted), then extras.
				var merged: Array = []
				for id0 in ids:
					var s0 := str(id0)
					if want[k2].has(s0) and not merged.has(s0):
						merged.append(s0)
				for id1 in want[k2]:
					var s1 := str(id1)
					if not merged.has(s1):
						merged.append(s1)
				want[k2] = merged
	# #region agent log
	if Engine.get_process_frames() % 60 == 0 and not want.is_empty():
		var _lp := "H:/debug-59aff0.log"
		var _lf := FileAccess.open(_lp, FileAccess.READ_WRITE)
		if _lf == null:
			_lf = FileAccess.open(_lp, FileAccess.WRITE)
		if _lf:
			_lf.seek_end()
			var sample_k := str(want.keys()[0])
			_lf.store_line(JSON.stringify({
				"sessionId": "59aff0", "hypothesisId": "CO",
				"location": "tactical_callout_layer.sync_occupied",
				"message": "slot_order",
				"data": {"key": sample_k, "ids": want[sample_k], "runId": "callout-order"},
				"timestamp": Time.get_ticks_msec()
			}))
			_lf.close()
	# #endregion
	for old_k in _cells.keys():
		if not want.has(old_k):
			_free_cell(str(old_k))
	for k3 in want.keys():
		var ids3: Array = want[k3]
		if ids3.is_empty():
			continue
		_ensure_cell(str(k3), ids3)
	_resolve_callout_sides()
	_spread_pie_columns()
	_relax_callouts()
	_present_callouts(delta)
	_tick_tweens(delta)

func _ensure_cell(key: String, unit_ids: Array) -> void:
	if unit_ids.is_empty():
		return
	var parts := key.split(":")
	if parts.size() < 2 or _map == null or not _map.systems.has(parts[0]):
		return
	var sid := str(parts[0])
	var cell := int(parts[1])
	var sysd: Dictionary = _map.systems[sid]
	var cells: Array = sysd["cells"]
	if cell < 0 or cell >= cells.size():
		return
	var c: Dictionary = cells[cell]
	var center: Vector3 = sysd["center"]
	var sc := 1.0
	if _starmap and _starmap.has_method("visual_scale_of"):
		sc = float(_starmap.visual_scale_of(sid))
	else:
		sc = float(sysd.get("visual_scale", sysd.get("scale", 1.0)))
	var r_out := float(_map.layout.get("ring_outer", 26)) * sc
	var ang := float(c.get("angle_center", 0.0))
	var radial := Vector3(sin(ang), 0.0, -cos(ang))
	var cell_pos := center + radial * (r_out * 0.72) + Vector3(0.0, 0.08, 0.0)
	var n := unit_ids.size()
	var ncols := mini(COLS, n)
	var nrows := int(ceili(float(n) / float(ncols)))
	var fs := maxf(font_scale, 0.25)
	var slot_w := SLOT_W0 * fs
	var slot_h := SLOT_H0 * fs
	#（callout 框包住换行后的铭牌）26.10.22 13:34 s
	if plate_size_fn.is_valid():
		var widest := 0.0
		var tallest := 0.0
		for uid_w in unit_ids:
			var got: Variant = plate_size_fn.call(str(uid_w))
			if got is Vector2:
				var sz: Vector2 = got
				widest = maxf(widest, sz.x)
				tallest = maxf(tallest, sz.y)
		if widest > 0.0:
			slot_w = maxf(slot_w, widest + 0.35 * fs)
		if tallest > 0.0:
			slot_h = maxf(slot_h, tallest + 0.35 * fs)
	#（callout 框包住换行后的铭牌）26.10.22 13:34 e
	var frame_pad := FRAME_PAD0 * fs
	var horiz_len := HORIZ_LEN0 * fs
	var box_w := float(ncols) * slot_w + frame_pad * 2.0
	var box_h := float(nrows) * slot_h + frame_pad * 2.0
	var half_x := box_w * 0.5
	var half_z := box_h * 0.5
	var s_right := _screen_right()
	## Prefer previous side for stability; else natural outer side.
	var side := float(_cells[key]["side"]) if _cells.has(key) and _cells[key].has("side") \
			else (1.0 if radial.dot(s_right) >= 0.0 else -1.0)
	if not _cells.has(key):
		var fr := Node3D.new()
		fr.name = "Frame_%s" % key.replace(":", "_")
		add_child(fr)
		var box := MeshInstance3D.new()
		box.name = "Box"
		var qm := QuadMesh.new()
		qm.size = Vector2(box_w, box_h)
		box.mesh = qm
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.albedo_color = Color(0.08, 0.1, 0.14, 0.72)
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.no_depth_test = true
		box.material_override = bm
		box.rotation_degrees = Vector3(-90, 0, 0)
		fr.add_child(box)
		var border := MeshInstance3D.new()
		border.name = "Border"
		border.mesh = _make_rect_outline(box_w, box_h)
		var bom := StandardMaterial3D.new()
		bom.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bom.albedo_color = Color(0.75, 0.8, 0.9, 0.95)
		bom.no_depth_test = true
		border.material_override = bom
		fr.add_child(border)
		var line := MeshInstance3D.new()
		line.name = "Leader_%s" % key.replace(":", "_")
		add_child(line)
		_cells[key] = {
			"frame": fr, "line": line, "box": box, "border": border, "unit_ids": [],
			"ncols": ncols, "nrows": nrows, "box_w": box_w, "box_h": box_h
		}
	var d: Dictionary = _cells[key]
	d["unit_ids"] = unit_ids
	d["ncols"] = ncols
	d["nrows"] = nrows
	var size_changed := absf(float(d.get("box_w", 0.0)) - box_w) > 0.01 \
			or absf(float(d.get("box_h", 0.0)) - box_h) > 0.01
	d["box_w"] = box_w
	d["box_h"] = box_h
	d["half_z"] = half_z
	d["sid"] = sid
	d["cell"] = cell
	d["center"] = center
	d["cell_pos"] = cell_pos
	d["horiz_len"] = horiz_len
	d["half_x"] = half_x
	d["r_out"] = r_out
	d["radial"] = radial
	d["ang"] = ang
	_apply_cell_side(key, side, size_changed)

func _frame_pos_for_side(d: Dictionary, side: float) -> Vector3:
	var center: Vector3 = d.get("center", Vector3.ZERO)
	var radial: Vector3 = d.get("radial", Vector3.FORWARD)
	var r_out := float(d.get("r_out", 26.0))
	var half_x := float(d.get("half_x", 4.0))
	var half_z := float(d.get("half_z", float(d.get("box_h", 8.0)) * 0.5))
	var horiz_len := float(d.get("horiz_len", 4.0))
	var s_right := _screen_right()
	return center + radial * (r_out + RING_GAP + half_z * 0.15) \
			+ s_right * (side * (half_x + horiz_len + r_out * 0.15)) \
			+ Vector3(0.0, 0.12, 0.0)

func _apply_cell_side(key: String, side: float, size_changed: bool = false) -> void:
	if not _cells.has(key):
		return
	var d: Dictionary = _cells[key]
	var frame_pos := _frame_pos_for_side(d, side)
	var box_w := float(d.get("box_w", 8.0))
	var box_h := float(d.get("box_h", 8.0))
	d["side"] = side
	d["frame_pos"] = frame_pos
	d["target_pos"] = frame_pos
	d["target_yaw"] = -view_yaw
	var box2: MeshInstance3D = d.get("box")
	if box2 and box2.mesh is QuadMesh:
		(box2.mesh as QuadMesh).size = Vector2(box_w, box_h)
	var border2: MeshInstance3D = d.get("border")
	if border2 and size_changed:
		border2.mesh = _make_rect_outline(box_w, box_h)

func _callout_overlap_area(c1: Vector3, hx1: float, hz1: float, c2: Vector3, hx2: float, hz2: float) -> float:
	var sr := _screen_right()
	var su := _screen_up()
	var delta := c2 - c1
	var dr := absf(delta.dot(sr))
	var du := absf(delta.dot(su))
	var orr := (hx1 + hx2) - dr
	var ou := (hz1 + hz2) - du
	if orr <= 0.0 or ou <= 0.0:
		return 0.0
	return orr * ou

func _side_score(key: String, side: float) -> float:
	## Lower is better. Callout↔callout overlap ≫ board/ring penalty (TACTICAL_TOPDOWN §10).
	if not _cells.has(key):
		return 1.0e12
	var d: Dictionary = _cells[key]
	var fp := _frame_pos_for_side(d, side)
	var hx := float(d.get("half_x", 4.0))
	var hz := float(d.get("half_z", float(d.get("box_h", 8.0)) * 0.5))
	var overlap := 0.0
	for ok in _cells.keys():
		if str(ok) == key:
			continue
		var od: Dictionary = _cells[ok]
		var ofr: Node3D = od.get("frame")
		if ofr == null or not is_instance_valid(ofr):
			continue
		var oc: Vector3 = od.get("target_pos", ofr.global_position)
		var ohx := float(od.get("half_x", 4.0))
		var ohz := float(od.get("half_z", float(od.get("box_h", 8.0)) * 0.5))
		overlap += _callout_overlap_area(fp, hx, hz, oc, ohx, ohz)
	var board := _frame_penalty(str(d.get("sid", "")), fp, hx, hz)
	## Prefer natural outer side slightly.
	var radial: Vector3 = d.get("radial", Vector3.FORWARD)
	var natural := 1.0 if radial.dot(_screen_right()) >= 0.0 else -1.0
	var flip_cost := 0.0 if is_equal_approx(side, natural) else 2.0
	return overlap * 1000.0 + board * 1.0 + flip_cost

func _resolve_callout_sides() -> void:
	## Try flip each frame to the other screen side when it reduces score.
	var keys: Array = _cells.keys()
	keys.sort() ## stable order
	for _pass in range(2):
		var any_flip := false
		for k in keys:
			var key := str(k)
			if not _cells.has(key):
				continue
			var cur := float(_cells[key].get("side", 1.0))
			var alt := -cur
			var s_cur := _side_score(key, cur)
			var s_alt := _side_score(key, alt)
			## Flip only if clearly better (overlap/board), keep hysteresis.
			if s_alt + 0.5 < s_cur:
				_apply_cell_side(key, alt, false)
				any_flip = true
		if not any_flip:
			break




func _clamp_keep_side(center: Vector3, fp: Vector3, max_d: float, side: float, min_x: float) -> Vector3:
	var flat := Vector3(fp.x - center.x, 0.0, fp.z - center.z)
	if side > 0.0:
		flat.x = maxf(flat.x, min_x)
	else:
		flat.x = minf(flat.x, -min_x)
	var dlen := flat.length()
	if dlen > max_d and dlen > 0.001:
		flat *= max_d / dlen
	return Vector3(center.x + flat.x, 0.12, center.z + flat.z)


func _pie_leader_pts(slice_pos: Vector3, attach: Vector3, side: float, horiz_len: float) -> Array:
	## Horizontal stub along screen-right (not world +X).
	var elbow := attach - _screen_right() * (side * horiz_len)
	elbow.y = 0.1
	return [slice_pos, elbow, attach]


func _spread_pie_columns() -> void:
	## Stack along screen-up so columns stay screen-vertical after yaw.
	var s_up := _screen_up()
	var s_right := _screen_right()
	var groups: Dictionary = {}
	for k in _cells.keys():
		var d: Dictionary = _cells[k]
		if d.get("frame") == null:
			continue
		var gk := "%s:%d" % [str(d.get("sid", "")), 1 if float(d.get("side", 1.0)) > 0.0 else 0]
		if not groups.has(gk):
			groups[gk] = []
		(groups[gk] as Array).append(k)
	for gk in groups.keys():
		var keys: Array = groups[gk]
		if keys.size() < 2:
			continue
		keys.sort_custom(func(a, b):
			var pa: Vector3 = _cells[a].get("target_pos", Vector3.ZERO)
			var pb: Vector3 = _cells[b].get("target_pos", Vector3.ZERO)
			return pa.dot(s_up) < pb.dot(s_up)
		)
		var gap := 1.6
		var along: Array = []
		var cursor := -1.0e9
		for k2 in keys:
			var p2: Vector3 = _cells[k2].get("target_pos", Vector3.ZERO)
			var h := float(_cells[k2].get("box_h", 8.0))
			var t := p2.dot(s_up)
			if t < cursor:
				t = cursor
			along.append(t)
			cursor = t + h + gap
		var pA: Vector3 = _cells[keys[0]].get("target_pos", Vector3.ZERO)
		var pB: Vector3 = _cells[keys[keys.size() - 1]].get("target_pos", Vector3.ZERO)
		var old_mid := (pA.dot(s_up) + pB.dot(s_up)) * 0.5
		var new_mid := (float(along[0]) + float(along[along.size() - 1])) * 0.5
		var shift := old_mid - new_mid
		for i in keys.size():
			var d3: Dictionary = _cells[keys[i]]
			var p: Vector3 = d3.get("target_pos", Vector3.ZERO)
			var right_amt := p.dot(s_right)
			var t3 := float(along[i]) + shift
			p = s_right * right_amt + s_up * t3
			p.y = 0.12
			d3["target_pos"] = p
			d3["frame_pos"] = p


func _count_callout_hits(keys: Array, pos: Dictionary) -> Vector2i:
	## x = box↔box overlaps, y = box↔ring overlaps.
	var sr := _screen_right()
	var su := _screen_up()
	var bb := 0
	var br := 0
	for i in keys.size():
		var a: Dictionary = _cells[keys[i]]
		var pa: Vector3 = pos[keys[i]]
		for j in range(i + 1, keys.size()):
			var b: Dictionary = _cells[keys[j]]
			var dl: Vector3 = (pos[keys[j]] as Vector3) - pa
			if absf(dl.dot(sr)) < float(a["half_x"]) + float(b["half_x"]) \
					and absf(dl.dot(su)) < float(a["half_z"]) + float(b["half_z"]):
				bb += 1
		for osid in _map.systems.keys():
			var oc: Vector3 = _map.systems[osid]["center"]
			var cl := _box_closest(pa, float(a["half_x"]), float(a["half_z"]), oc, sr, su)
			if Vector2(cl.x - oc.x, cl.z - oc.z).length() < _sys_radius(str(osid)):
				br += 1
	return Vector2i(bb, br)

func _box_closest(fp: Vector3, hx: float, hz: float, p: Vector3, sr: Vector3, su: Vector3) -> Vector3:
	## Closest point of the screen-axis box (center fp) to p, on the board plane.
	var d := Vector3(p.x - fp.x, 0.0, p.z - fp.z)
	var lx := clampf(d.dot(sr), -hx, hx)
	var lz := clampf(d.dot(su), -hz, hz)
	return Vector3(fp.x, 0.0, fp.z) + sr * lx + su * lz

func _relax_callouts() -> void:
	## Push boxes apart along the shallower screen axis; push boxes out of system rings.
	## Recomputed each frame from the side/stack anchors, so it never drifts.
	var keys: Array = []
	for k in _cells.keys():
		var dk: Dictionary = _cells[k]
		if dk.get("frame") != null and dk.has("target_pos"):
			keys.append(k)
	if keys.is_empty():
		return
	keys.sort()
	var sr := _screen_right()
	var su := _screen_up()
	var pos: Dictionary = {}
	for k0 in keys:
		pos[k0] = _cells[k0]["target_pos"]
	var before := _count_callout_hits(keys, pos)
	for _it in RELAX_ITERS:
		var moved := false
		for i in keys.size():
			var a: Dictionary = _cells[keys[i]]
			var hxa := float(a["half_x"]) + RELAX_GAP * 0.5
			var hza := float(a["half_z"]) + RELAX_GAP * 0.5
			for j in range(i + 1, keys.size()):
				var b: Dictionary = _cells[keys[j]]
				var pa: Vector3 = pos[keys[i]]
				var pb: Vector3 = pos[keys[j]]
				var dl := pb - pa
				var dr := dl.dot(sr)
				var du := dl.dot(su)
				var o_r := hxa + float(b["half_x"]) + RELAX_GAP * 0.5 - absf(dr)
				var o_u := hza + float(b["half_z"]) + RELAX_GAP * 0.5 - absf(du)
				if o_r <= 0.0 or o_u <= 0.0:
					continue
				var push: Vector3
				if o_u <= o_r:
					push = su * ((1.0 if du >= 0.0 else -1.0) * o_u * 0.5)
				else:
					push = sr * ((1.0 if dr >= 0.0 else -1.0) * o_r * 0.5)
				pos[keys[i]] = pa - push
				pos[keys[j]] = pb + push
				moved = true
		for k2 in keys:
			var d2: Dictionary = _cells[k2]
			var hx := float(d2["half_x"])
			var hz := float(d2["half_z"])
			for osid in _map.systems.keys():
				var oc: Vector3 = _map.systems[osid]["center"]
				var rad := _sys_radius(str(osid)) + RELAX_GAP
				var fp: Vector3 = pos[k2]
				var cl := _box_closest(fp, hx, hz, oc, sr, su)
				var out := Vector3(cl.x - oc.x, 0.0, cl.z - oc.z)
				var dist := out.length()
				if dist >= rad:
					continue
				if dist < 0.001:
					out = Vector3(fp.x - oc.x, 0.0, fp.z - oc.z)
					if out.length_squared() < 0.0001:
						out = sr
				pos[k2] = fp + out.normalized() * (rad - dist)
				moved = true
		if not moved:
			break
	for k3 in keys:
		var p: Vector3 = pos[k3]
		p.y = 0.12
		_cells[k3]["target_pos"] = p
		_cells[k3]["frame_pos"] = p
	# #region agent log
	if Engine.get_process_frames() % 120 == 0:
		var after := _count_callout_hits(keys, pos)
		var _lf := FileAccess.open("H:/debug-59aff0.log", FileAccess.READ_WRITE)
		if _lf == null:
			_lf = FileAccess.open("H:/debug-59aff0.log", FileAccess.WRITE)
		if _lf:
			_lf.seek_end()
			_lf.store_line(JSON.stringify({
				"sessionId": "59aff0", "hypothesisId": "CO", "location": "tactical_callout_layer._relax_callouts",
				"message": "relax", "data": {"n": keys.size(), "box_before": before.x, "ring_before": before.y,
					"box_after": after.x, "ring_after": after.y, "runId": "post-fix"},
				"timestamp": Time.get_ticks_msec()
			}))
			_lf.close()
	# #endregion

func _clamp_sys_dist(center: Vector3, fp: Vector3, max_d: float) -> Vector3:
	var flat := Vector3(fp.x - center.x, 0.0, fp.z - center.z)
	var dlen := flat.length()
	if dlen < 0.001:
		return Vector3(center.x, 0.12, center.z + max_d)
	if dlen <= max_d:
		return Vector3(fp.x, 0.12, fp.z)
	flat *= max_d / dlen
	return Vector3(center.x + flat.x, 0.12, center.z + flat.z)


func _iso_leader_pts(a: Vector3, b: Vector3) -> Array:
	## Visible A->C->B; BC horizontal; |AC|=|BC| (isosceles 腰); hide direct A-B.
	var dx := a.x - b.x
	var dz := a.z - b.z
	var c: Vector3
	if absf(dx) >= absf(dz) and absf(dx) > 0.05:
		var t := (dx * dx + dz * dz) / (2.0 * dx)
		c = Vector3(b.x + t, 0.1, b.z)
	elif absf(dz) > 0.05:
		var t2 := (dx * dx + dz * dz) / (2.0 * dz)
		c = Vector3(b.x, 0.1, b.z + t2)
	else:
		## Degenerate: short horizontal stub.
		c = Vector3(b.x + HORIZ_LEN0 * maxf(font_scale, 0.25), 0.1, b.z)
	return [a, c, b]


func _sys_radius(sid: String) -> float:
	if _map == null or not _map.systems.has(sid):
		return 26.0
	var sysd: Dictionary = _map.systems[sid]
	var sc := 1.0
	if _starmap and _starmap.has_method('visual_scale_of'):
		sc = float(_starmap.visual_scale_of(sid))
	else:
		sc = float(sysd.get('visual_scale', sysd.get('scale', 1.0)))
	return float(_map.layout.get('ring_outer', 26)) * sc


func _aabb_disk_penalty(fp: Vector3, half_x: float, half_z: float, oc: Vector3, rad: float) -> float:
	var cx := clampf(oc.x, fp.x - half_x, fp.x + half_x)
	var cz := clampf(oc.z, fp.z - half_z, fp.z + half_z)
	var d := Vector2(oc.x - cx, oc.z - cz).length()
	if d >= rad:
		return maxf(0.0, rad + 6.0 - d) * 0.15
	return (rad - d) * (rad - d) + 40.0


func _frame_penalty(self_sid: String, fp: Vector3, half_x: float, half_z: float) -> float:
	var pen := 0.0
	for osid in _map.systems.keys():
		var oid := str(osid)
		var oc: Vector3 = _map.systems[oid]['center']
		var rad := _sys_radius(oid)
		var w := 0.35 if oid == self_sid else 1.0
		pen += _aabb_disk_penalty(fp, half_x, half_z, oc, rad) * w
	return pen


func _pick_frame_away(self_sid: String, base_fp: Vector3, radial: Vector3, half_x: float, half_z: float, tip: Vector3) -> Dictionary:
	var tangent := Vector3(-radial.z, 0.0, radial.x)
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.RIGHT
	else:
		tangent = tangent.normalized()
	var away := Vector3.RIGHT
	var best_d2 := 1.0e12
	var self_c: Vector3 = _map.systems[self_sid]['center']
	for osid in _map.systems.keys():
		var oid := str(osid)
		if oid == self_sid:
			continue
		var oc: Vector3 = _map.systems[oid]['center']
		var d2 := self_c.distance_squared_to(oc)
		if d2 < best_d2 and d2 > 0.01:
			best_d2 = d2
			away = Vector3(self_c.x - oc.x, 0.0, self_c.z - oc.z)
	if away.length_squared() < 0.0001:
		away = Vector3(-radial.x, 0.0, -radial.z)
	## Flip lateral bias (框横向方向反了).
	away = (-away).normalized()
	var lat_sign := signf(away.x)
	if is_zero_approx(lat_sign):
		lat_sign = -1.0 if away.z >= 0.0 else 1.0
	var step := maxf(half_x + HORIZ_LEN0 * maxf(font_scale, 0.25), 8.0)
	var cands: Array = [Vector3.ZERO]
	for k in [1.0, -1.0, 2.0, -2.0, 3.0, -3.0]:
		cands.append(tangent * (k * step))
		cands.append(Vector3(k * step * lat_sign, 0.0, 0.0))
		cands.append(radial * (absf(k) * step * 0.35) + tangent * (k * step * 0.5))
	var best_pos := base_fp
	var best_pen := _frame_penalty(self_sid, base_fp, half_x, half_z)
	var best_lat := lat_sign
	for off in cands:
		var fp: Vector3 = base_fp + off
		var pen := _frame_penalty(self_sid, fp, half_x, half_z)
		var align := Vector3(off.x, 0.0, off.z).dot(away)
		pen -= align * 0.05
		if pen < best_pen - 0.01:
			best_pen = pen
			best_pos = fp
			if absf(off.x) > 0.01:
				best_lat = signf(off.x)
	# #region agent log
	if Engine.get_process_frames() % 90 == 0:
		var _lp := 'H:/debug-59aff0.log'
		var _lf := FileAccess.open(_lp, FileAccess.READ_WRITE)
		if _lf == null:
			_lf = FileAccess.open(_lp, FileAccess.WRITE)
		if _lf:
			_lf.seek_end()
			_lf.store_line(JSON.stringify({
				'sessionId': '59aff0', 'hypothesisId': 'H_AVOID',
				'location': 'tactical_callout_layer._pick_frame_away',
				'message': 'avoid_pick',
				'data': {
					'sid': self_sid, 'base_pen': _frame_penalty(self_sid, base_fp, half_x, half_z),
					'best_pen': best_pen, 'dx': best_pos.x - base_fp.x, 'dz': best_pos.z - base_fp.z,
					'lat_sign': best_lat, 'away_x': away.x, 'ex': tip.x, 'runId': 'post-fix'
				},
				'timestamp': Time.get_ticks_msec()
			}))
			_lf.close()
	# #endregion
	return {'pos': best_pos, 'pen': best_pen, 'lat_sign': best_lat}


func _slot_world(frame_pos: Vector3, slot: int, ncols: int, nrows: int, box_w: float, box_h: float) -> Vector3:
	return _slot_world_axes(frame_pos, slot, ncols, nrows, box_w, box_h, _screen_right(), _screen_up())

func _slot_world_axes(frame_pos: Vector3, slot: int, ncols: int, nrows: int, box_w: float, box_h: float, s_right: Vector3, s_up: Vector3) -> Vector3:
	var col := int(slot % ncols)
	var row := int(floor(float(slot) / float(ncols)))
	var ox := (float(col) + 0.5) / float(ncols) - 0.5
	var oz := (float(row) + 0.5) / float(nrows) - 0.5
	var pad := FRAME_PAD0 * maxf(font_scale, 0.25)
	## Offsets in the frame's current screen axes so plates stay inside the yawed box.
	return frame_pos \
			+ s_right * (ox * (box_w - pad)) \
			+ s_up * (oz * (box_h - pad)) \
			+ Vector3(0.0, 0.35, 0.0)

func _present_callouts(delta: float) -> void:
	var k := 1.0 - exp(-maxf(delta, 0.0) / SLIDE_TAU)
	for key in _cells.keys():
		var d: Dictionary = _cells[key]
		var target: Vector3 = d.get("target_pos", Vector3.ZERO)
		var tyaw := float(d.get("target_yaw", -view_yaw))
		var shown: Vector3
		var syaw: float
		if not bool(d.get("shown_ready", false)):
			shown = target
			syaw = tyaw
			d["shown_ready"] = true
		else:
			shown = (d["shown_pos"] as Vector3).lerp(target, k)
			syaw = lerp_angle(float(d.get("shown_yaw", tyaw)), tyaw, k)
			if shown.distance_squared_to(target) < 0.0004 and absf(angle_difference(syaw, tyaw)) < 0.01:
				shown = target
				syaw = tyaw
		d["shown_pos"] = shown
		d["shown_yaw"] = syaw
		var fr: Node3D = d.get("frame")
		if fr == null or not is_instance_valid(fr):
			continue
		fr.global_position = shown
		fr.rotation = Vector3(0.0, syaw, 0.0)
		var vy := -syaw
		var s_right := Vector3(cos(vy), 0.0, sin(vy))
		var s_up := Vector3(sin(vy), 0.0, -cos(vy))
		var side := float(d.get("side", 1.0))
		var half_x := float(d.get("half_x", 4.0))
		var attach := shown - s_right * (side * half_x)
		attach.y = 0.1
		var cell_pos: Vector3 = d.get("cell_pos", shown)
		var elbow := attach - s_right * (side * float(d.get("horiz_len", 4.0)))
		elbow.y = 0.1
		_rebuild_leader_poly(d.get("line") as MeshInstance3D, [cell_pos, elbow, attach])
		var ids: Array = d.get("unit_ids", [])
		var ncols := int(d.get("ncols", 1))
		var nrows := int(d.get("nrows", 1))
		var bw := float(d.get("box_w", 8.0))
		var bh := float(d.get("box_h", 8.0))
		var slots: Dictionary = {}
		for si in ids.size():
			slots[str(ids[si])] = _slot_world_axes(shown, si, ncols, nrows, bw, bh, s_right, s_up)
		d["slots"] = slots

func hit_frame(cam: Camera3D, screen: Vector2) -> Dictionary:
	if not _active or cam == null:
		return {}
	var best: Dictionary = {}
	var best_d := 1.0e20
	for _key in _cells.keys():
		var d: Dictionary = _cells[_key]
		var shown: Vector3 = d.get("shown_pos", Vector3.ZERO)
		var syaw := float(d.get("shown_yaw", -view_yaw))
		var vy := -syaw
		var s_right := Vector3(cos(vy), 0.0, sin(vy))
		var s_up := Vector3(sin(vy), 0.0, -cos(vy))
		var hx := float(d.get("half_x", 4.0))
		var hz := float(d.get("half_z", 4.0))
		var corners: Array[Vector3] = [
			shown + s_right * hx + s_up * hz,
			shown + s_right * hx - s_up * hz,
			shown - s_right * hx + s_up * hz,
			shown - s_right * hx - s_up * hz,
		]
		var min_p := Vector2(1.0e9, 1.0e9)
		var max_p := Vector2(-1.0e9, -1.0e9)
		var ok := true
		for c in corners:
			if cam.is_position_behind(c):
				ok = false
				break
			var sp: Vector2 = cam.unproject_position(c)
			min_p.x = minf(min_p.x, sp.x)
			min_p.y = minf(min_p.y, sp.y)
			max_p.x = maxf(max_p.x, sp.x)
			max_p.y = maxf(max_p.y, sp.y)
		if not ok:
			continue
		if screen.x < min_p.x or screen.x > max_p.x or screen.y < min_p.y or screen.y > max_p.y:
			continue
		var center := (min_p + max_p) * 0.5
		var dist := screen.distance_squared_to(center)
		if dist < best_d:
			best_d = dist
			best = {
				"sys": str(d.get("sid", "")),
				"cell": int(d.get("cell", -1)),
				"unit_ids": (d.get("unit_ids", []) as Array).duplicate(),
			}
	return best


func has_slot(unit_id: String, sys: String, cell: int) -> bool:
	var key := "%s:%d" % [sys, cell]
	if not _cells.has(key):
		return false
	var slots: Dictionary = _cells[key].get("slots", {})
	return slots.has(unit_id)


func slot_pos_for(unit_id: String, sys: String, cell: int) -> Vector3:
	var key := "%s:%d" % [sys, cell]
	if not _cells.has(key):
		return Vector3.ZERO
	var d: Dictionary = _cells[key]
	var slots: Dictionary = d.get("slots", {})
	if slots.has(unit_id):
		return slots[unit_id]
	return d["frame"].global_position if d.get("frame") else Vector3.ZERO

func snap_overhead(unit_id: String, to: Vector3) -> void:
	_oh_tween[unit_id] = {"from": to, "to": to, "t": 1.0}

func begin_or_retarget_tween(unit_id: String, target: Vector3) -> void:
	var cur := Vector3.ZERO
	if _oh_tween.has(unit_id):
		var prev: Dictionary = _oh_tween[unit_id]
		var t0 := clampf(float(prev.get("t", 1.0)), 0.0, 1.0)
		cur = Vector3(prev["from"]).lerp(Vector3(prev["to"]), t0)
	_oh_tween[unit_id] = {"from": cur if cur != Vector3.ZERO else target, "to": target, "t": 0.0}

func set_tween(unit_id: String, from: Vector3, to: Vector3, reset_t: bool = true) -> void:
	_oh_tween[unit_id] = {
		"from": from, "to": to, "t": 0.0 if reset_t else float(_oh_tween.get(unit_id, {}).get("t", 0.0))
	}

func update_tween_target(unit_id: String, to: Vector3) -> void:
	if _oh_tween.has(unit_id):
		var tw: Dictionary = _oh_tween[unit_id]
		if float(tw.get("t", 0.0)) >= 1.0:
			tw["from"] = to
			tw["to"] = to
		else:
			tw["to"] = to
	else:
		_oh_tween[unit_id] = {"from": to, "to": to, "t": 1.0}

func overhead_world_pos(unit_id: String, fallback: Vector3) -> Vector3:
	if not _oh_tween.has(unit_id):
		return fallback
	var d: Dictionary = _oh_tween[unit_id]
	var t := clampf(float(d.get("t", 1.0)), 0.0, 1.0)
	return Vector3(d["from"]).lerp(Vector3(d["to"]), t)

func _tick_tweens(delta: float) -> void:
	for uid in _oh_tween.keys():
		var d: Dictionary = _oh_tween[uid]
		d["t"] = minf(1.0, float(d.get("t", 0.0)) + delta / TWEEN_S)

func ensure_pick_body(parent: Node3D, unit_id: String) -> void:
	if parent == null:
		return
	var existing = parent.get_node_or_null("TacticalPick")
	if existing:
		existing.set_meta("unit_id", unit_id)
		return
	var body := StaticBody3D.new()
	body.name = "TacticalPick"
	body.collision_layer = 0
	body.set_collision_layer_value(PICK_LAYER, true)
	body.collision_mask = 0
	body.set_meta("unit_id", unit_id)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5.5, 0.5, 5.5)
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)

func _rebuild_leader_poly(mi: MeshInstance3D, pts: Array) -> void:
	if mi == null or pts.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in range(pts.size() - 1):
		st.add_vertex(pts[i] as Vector3)
		st.add_vertex(pts[i + 1] as Vector3)
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 0.75, 0.85, 0.85)
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _make_rect_outline(w: float, h: float) -> ArrayMesh:
	var hw := w * 0.5
	var hh := h * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var pts = [
		Vector3(-hw, 0.02, -hh), Vector3(hw, 0.02, -hh),
		Vector3(hw, 0.02, -hh), Vector3(hw, 0.02, hh),
		Vector3(hw, 0.02, hh), Vector3(-hw, 0.02, hh),
		Vector3(-hw, 0.02, hh), Vector3(-hw, 0.02, -hh),
	]
	for p in pts:
		st.add_vertex(p)
	return st.commit()
