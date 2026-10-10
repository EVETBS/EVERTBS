extends Node3D
class_name BoardStarmapView

var map: BoardMapModel
var diplomacy: Dictionary
var viewer = 1
var units_ref: Array = []
var transit_gates: Dictionary = {}
var label_root: Node3D
var icon_root: Node3D
var pilots_ref: Array = []
var cell_pick_root: Node3D
var link_cam: Camera3D
## visual_scale per system id (smoothed)
var visual_scales: Dictionary = {}

@onready var mesh_inst: MeshInstance3D = $Mesh

var SECTOR_ICON: Dictionary = {
	1: "res://assets/ui/sector/stargate.png",
	2: "res://assets/ui/sector/resource.png",
	3: "res://assets/ui/sector/station.png",
	4: "res://assets/ui/sector/sov.png",
}

const ICON_REF_DIST := 60.0
const ICON_BASE_PIXEL := 0.072
const RIM_THICK := 0.70  # doubled from 0.35


# region agent log
func _agent_dbg(hid: String, loc: String, msg: String, data: Dictionary = {}) -> void:
	var path := "h:/debug-455fdd.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var payload := {
		"sessionId": "455fdd",
		"hypothesisId": hid,
		"location": loc,
		"message": msg,
		"data": data,
		"timestamp": Time.get_ticks_msec()
	}
	f.store_line(JSON.stringify(payload))
	f.close()
# endregion

func setup(m: BoardMapModel, dipl: Dictionary, viewer_fac: int) -> void:
	map = m
	diplomacy = dipl
	viewer = viewer_fac
	if label_root == null:
		label_root = Node3D.new()
		label_root.name = "ResourceLabels"
		add_child(label_root)
	if icon_root == null:
		icon_root = Node3D.new()
		icon_root.name = "SectorIcons"
		add_child(icon_root)
	if cell_pick_root == null:
		cell_pick_root = Node3D.new()
		cell_pick_root.name = "CellPick"
		add_child(cell_pick_root)
	for sid in map.systems.keys():
		visual_scales[sid] = float(map.systems[sid].get("scale", 1.0))
	rebuild()

func set_units(u: Array) -> void:
	units_ref = u

func set_camera(c: Camera3D) -> void:
	link_cam = c

func tick_smooth_scales(delta: float) -> bool:
	if map == null:
		return false
	var moved = false
	for sid in map.systems.keys():
		var target = float(map.systems[sid].get("scale", 1.0))
		var cur = float(visual_scales.get(sid, target))
		# Smooth approach — avoid 1-frame snap; ~0.55s settle for Δ0.38
		# Constant approach so enter/leave never snaps or yo-yos
		var nxt = move_toward(cur, target, delta * 0.75)
		if absf(target - nxt) < 0.0008:
			nxt = target
		if absf(nxt - cur) > 0.0005:
			moved = true
		visual_scales[sid] = nxt
		## Keep map.cell_world_pos aligned with drawn ring.
		map.systems[sid]["visual_scale"] = nxt
	if moved:
		tick_icon_edge_follow()
	return moved

func tick_icon_edge_follow() -> void:
	## Keep outer sector icons/labels glued to ring edge during scale lerp.
	if map == null:
		return
	for root in [icon_root, label_root]:
		if root == null:
			continue
		for node in root.get_children():
			if not node.has_meta("edge_sid"):
				continue
			var sid: String = str(node.get_meta("edge_sid"))
			if not map.systems.has(sid):
				continue
			var a: float = float(node.get_meta("edge_ang", 0.0))
			var pad: float = float(node.get_meta("edge_pad", 3.2))
			var y: float = float(node.get_meta("edge_y", 0.55))
			var sc = visual_scale_of(sid)
			var outer: float = float(map.layout.get("ring_outer", 26)) * sc
			var center: Vector3 = map.systems[sid]["center"]
			(node as Node3D).position = center + Vector3(sin(a) * (outer + pad), y, -cos(a) * (outer + pad))

func visual_scale_of(sid: String) -> float:
	return float(visual_scales.get(sid, map.systems[sid].get("scale", 1.0) if map and map.systems.has(sid) else 1.0))

func gate_outer_point(sys_id: String, to_id: String) -> Vector3:
	var sys: Dictionary = map.systems[sys_id]
	var center: Vector3 = sys["center"]
	var sys_scale: float = visual_scale_of(sys_id)
	var outer: float = float(map.layout.get("ring_outer", 26)) * sys_scale
	var ang = 0.0
	var found = false
	for c in sys["cells"]:
		if int(c["kind"]) == BoardTypes.CellKind.GATE and str(c["gate_to"]) == to_id:
			ang = float(c["angle_center"])
			found = true
			break
	if not found and map.systems.has(to_id):
		var other: Vector3 = map.systems[to_id]["center"]
		var dir = other - center
		ang = atan2(dir.x, -dir.z)
	return center + Vector3(sin(ang) * (outer + 0.4), 0.05, -cos(ang) * (outer + 0.4))

func rebuild() -> void:
	if map == null:
		return
	rebuild_labels(pilots_ref)
	_rebuild_sector_icons()
	_rebuild_system_markers()
	_rebuild_cell_pick()
	rebuild_mesh_only()

func rebuild_mesh_only() -> void:
	## Geometry only — avoids icon flicker from queue_free every capture tick
	if map == null:
		return
	if mesh_inst == null:
		mesh_inst = get_node_or_null("Mesh") as MeshInstance3D
		if mesh_inst == null:
			push_warning("starmap_view: Mesh node missing; remesh skipped")
			return
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sid in map.systems.keys():
		_draw_system(st, sid)
	_draw_links(st)
	mesh_inst.mesh = st.commit()
	# #region agent log
	if not has_meta("_dbg_mesh"):
		set_meta("_dbg_mesh", true)
		_agent_dbg("S1", "starmap.rebuild_mesh_only", "mesh_only", {"runId": "post-fix"})
	# #endregion

func _rel(owner_fac: int) -> String:
	if owner_fac == 0:
		return "unowned"
	var rels: Dictionary = diplomacy.get("relations", {}).get(str(viewer), {})
	return str(rels.get(str(owner_fac), "hostile"))

func _owner_color(owner_fac: int) -> Color:
	return BoardTypes.relation_color(_rel(owner_fac))

func _draw_system(st: SurfaceTool, sid: String) -> void:
	var sys: Dictionary = map.systems[sid]
	var center: Vector3 = sys["center"]
	var sys_scale: float = visual_scale_of(sid)
	var inner: float = float(map.layout.get("ring_inner", 12)) * sys_scale
	var outer: float = float(map.layout.get("ring_outer", 26)) * sys_scale
	for c in sys["cells"]:
		var a0: float = float(c["angle_center"]) - float(c["angle_half"])
		var a1: float = float(c["angle_center"]) + float(c["angle_half"])
		var kind: int = c["kind"]
		var base = _kind_color(kind)
		var owner_fac = int(c["owner"])
		var capturing = int(c.get("capturing", 0))
		# Rim progress color = capturer (design); idle rim = owner or white
		var edge = Color(1, 1, 1, 1)
		if kind != BoardTypes.CellKind.EMPTY:
			if capturing != 0:
				edge = _owner_color(capturing)
			elif owner_fac != 0:
				edge = _owner_color(owner_fac)
			else:
				edge = Color(1, 1, 1, 1)
		if c.get("bubble", false):
			var t: float = float(c.get("bubble_t", 0.0))
			var breath = 0.35 + 0.65 * (0.5 + 0.5 * sin(t / BoardTypes.BUBBLE_BREATH_S * TAU))
			base = base.lightened(0.25 + breath * 0.35)
			base = Color(base.r, minf(1.0, base.g + 0.25), minf(1.0, base.b + 0.45), base.a)
			edge = Color(0.35, 0.85, 1.0, 1.0)
		# Transparent separator = real angular gap through fill AND outer rim
		var gap = 0.022
		var ga0 = a0 + gap
		var ga1 = a1 - gap
		if ga1 > ga0 + 0.01:
			_fan(st, center, inner, outer, ga0, ga1, base, edge, float(c["work"]))

func _kind_color(kind: int) -> Color:
	# Solid opaque board colors — no ambient shading dependence
	match kind:
		BoardTypes.CellKind.GATE:
			return Color(0.22, 0.38, 0.82, 1.0)
		BoardTypes.CellKind.RESOURCE:
			return Color(0.22, 0.65, 0.28, 1.0)
		BoardTypes.CellKind.STATION:
			return Color(0.82, 0.72, 0.18, 1.0)
		BoardTypes.CellKind.SOV:
			return Color(0.78, 0.18, 0.18, 1.0)
		_:
			return Color(0.55, 0.55, 0.58, 1.0)

func _fan(st: SurfaceTool, center: Vector3, inner: float, outer: float, a0: float, a1: float, fill: Color, edge: Color, work: float) -> void:
	var steps = maxi(4, int((a1 - a0) / 0.08))
	# Outer fill more opaque; center fades (radial transparent gradient)
	var c_out = Color(fill.r, fill.g, fill.b, minf(0.7, 0.70))
	var c_in = Color(fill.r * 0.55, fill.g * 0.55, fill.b * 0.55, minf(0.7, 0.28))
	# #region agent log
	if not has_meta("_dbg_fan"):
		set_meta("_dbg_fan", true)
		_agent_dbg("H9", "starmap._fan", "fan_mode", {"radial_fade": true, "rim_work": true, "work": work, "runId": "post-fix"})
	# #endregion
	for i in steps:
		var t0 = float(i) / float(steps)
		var t1 = float(i + 1) / float(steps)
		var b0 = lerpf(a0, a1, t0)
		var b1 = lerpf(a0, a1, t1)
		_quad(st, center, outer, inner, b0, b1, c_out, c_in)
		# Capture rim: from mid arc outward, solid capturer/owner chunks
		var mid_t = (t0 + t1) * 0.5
		var spread = (BoardTypes.WORK_MAX - work) / BoardTypes.WORK_MAX
		var from_mid = absf(mid_t - 0.5) * 2.0
		var rim: Color
		if work >= BoardTypes.WORK_MAX - 0.01:
			# fully topped: whole rim = current owner/edge color
			rim = Color(edge.r, edge.g, edge.b, 1.0)
		elif from_mid <= spread:
			rim = Color(edge.r, edge.g, edge.b, 1.0)
		else:
			rim = Color(1, 1, 1, 1)
		_rim(st, center, outer, b0, b1, rim)

func _quad(st: SurfaceTool, center: Vector3, r0: float, r1: float, a0: float, a1: float, c0: Color, c1: Color) -> void:
	var p00 = center + Vector3(sin(a0) * r0, 0.02, -cos(a0) * r0)
	var p10 = center + Vector3(sin(a1) * r0, 0.02, -cos(a1) * r0)
	var p01 = center + Vector3(sin(a0) * r1, 0.02, -cos(a0) * r1)
	var p11 = center + Vector3(sin(a1) * r1, 0.02, -cos(a1) * r1)
	_tri(st, p00, p10, p11, c0, c0, c1)
	_tri(st, p00, p11, p01, c0, c1, c1)

func _rim(st: SurfaceTool, center: Vector3, r: float, a0: float, a1: float, col: Color) -> void:
	var r1 = r + RIM_THICK
	var solid = Color(col.r, col.g, col.b, 1.0)
	_quad(st, center, r1, r, a0, a1, solid, solid)

func _draw_separator(_st: SurfaceTool, _center: Vector3, _r0: float, _r1: float, _ang: float) -> void:
	# Separators are transparent gaps in _draw_system (no colored bars)
	# #region agent log
	if not has_meta("_dbg_sep"):
		set_meta("_dbg_sep", true)
		_agent_dbg("H7", "starmap._draw_separator", "sep_gap", {"mode": "angular_gap", "runId": "post-fix"})
	# #endregion
	pass

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)

func _draw_links(st: SurfaceTool) -> void:
	for sid in map.systems.keys():
		for link in map.systems[sid]["links"]:
			_draw_dir_arrow(st, sid, str(link))

func _draw_dir_arrow(st: SurfaceTool, from_id: String, to_id: String) -> void:
	var a: Vector3 = gate_outer_point(from_id, to_id)
	var b: Vector3 = gate_outer_point(to_id, from_id)
	var gate_i = -1
	var owner_fac = 0
	var work_v = 0.0
	for c in map.systems[from_id]["cells"]:
		if int(c["kind"]) == BoardTypes.CellKind.GATE and str(c["gate_to"]) == to_id:
			gate_i = int(c["index"])
			owner_fac = int(c["owner"])
			work_v = float(c.get("work", 0))
			break
	var col = _owner_color(owner_fac) if owner_fac != 0 else Color(1, 1, 1, 1)
	var can = gate_i >= 0 and map.can_pass_gate(from_id, gate_i, viewer, diplomacy)
	var transit = transit_gates.has("%s:%d" % [from_id, gate_i])
	var owned = owner_fac != 0
	# Occupied gates: solid (even hostile). Unowned: dashed+dim unless transit.
	if owned or can or transit:
		col = Color(col.r, col.g, col.b, 0.95 if (can or transit) else 0.75)
	else:
		col = Color(col.r, col.g, col.b, 0.28)
	# #region agent log
	if owner_fac != 0 and not has_meta("_dbg_link_%s_%s" % [from_id, to_id]):
		set_meta("_dbg_link_%s_%s" % [from_id, to_id], true)
		_agent_dbg("H8", "starmap._draw_dir_arrow", "link_style", {
			"from": from_id, "to": to_id, "owner": owner_fac, "can": can, "work": work_v, "dashed": true
		})
	# #endregion
	var tip: Vector3 = a.lerp(b, 0.72)
	tip.y = 0.05
	var use_solid = owned or can or transit
	# #region agent log
	if owner_fac != 0 and not has_meta("_dbg_link_draw_%s_%s" % [from_id, to_id]):
		set_meta("_dbg_link_draw_%s_%s" % [from_id, to_id], true)
		_agent_dbg("H8", "starmap._draw_dir_arrow", "link_draw", {
			"from": from_id, "to": to_id, "owner": owner_fac, "can": can, "solid": use_solid
		})
	# #endregion
	if use_solid:
		_solid_line(st, a, tip, col)
	else:
		_dashed_line(st, a, tip, col)
	var dir = (tip - a).normalized()
	var side = Vector3(-dir.z, 0, dir.x) * 2.0
	_tri(st, tip, tip - dir * 3.0 + side, tip - dir * 3.0 - side, col, col, col)

func _solid_line(st: SurfaceTool, a: Vector3, b: Vector3, col: Color) -> void:
	var side = (b - a).cross(Vector3.UP).normalized() * 0.28
	if side.length_squared() < 0.0001:
		side = Vector3(0.28, 0, 0)
	_tri(st, a + side, b + side, b - side, col, col, col)
	_tri(st, a + side, b - side, a - side, col, col, col)

func _dashed_line(st: SurfaceTool, a: Vector3, b: Vector3, col: Color) -> void:
	var n = 12
	for i in n:
		if i % 2 == 1:
			continue
		var p0 = a.lerp(b, float(i) / float(n))
		var p1 = a.lerp(b, float(i + 1) / float(n))
		var side = (b - a).cross(Vector3.UP).normalized() * 0.25
		_tri(st, p0 + side, p1 + side, p1 - side, col, col, col)
		_tri(st, p0 + side, p1 - side, p0 - side, col, col, col)

func _billboard_sprite(tex_path: String, pos: Vector3, pixel: float = ICON_BASE_PIXEL) -> Sprite3D:
	var spr = Sprite3D.new()
	if ResourceLoader.exists(tex_path):
		spr.texture = load(tex_path)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.double_sided = true
	spr.no_depth_test = true
	spr.transparent = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	spr.pixel_size = pixel
	spr.position = pos
	spr.set_meta("base_pixel", pixel)
	spr.set_meta("screen_const", true)
	return spr

func _billboard_label(text: String, pos: Vector3, size: int = 84, col: Color = Color(0.95, 0.95, 1.0)) -> Label3D:
	var lab = Label3D.new()
	lab.text = text
	lab.font_size = size
	lab.modulate = col
	lab.outline_size = 2
	lab.outline_modulate = Color(0.04, 0.05, 0.08, 1.0)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = pos
	lab.set_meta("base_font", size)
	lab.set_meta("screen_const", true)
	return lab

func tick_screen_const_icons() -> void:
	if link_cam == null or icon_root == null:
		return
	for c in icon_root.get_children():
		_apply_screen_const(c)
	if label_root:
		for c2 in label_root.get_children():
			_apply_screen_const(c2)

func _apply_screen_const(node: Node) -> void:
	if not node.has_meta("screen_const"):
		return
	var dist = link_cam.global_position.distance_to((node as Node3D).global_position)
	var sc = clampf(dist / ICON_REF_DIST, 0.65, 2.4)
	if node is Sprite3D:
		var base_p = float(node.get_meta("base_pixel", ICON_BASE_PIXEL))
		(node as Sprite3D).pixel_size = base_p * sc
	elif node is Label3D:
		var base_f = int(node.get_meta("base_font", 84))
		(node as Label3D).font_size = int(round(float(base_f) * sc))

func _rebuild_sector_icons() -> void:
	if icon_root == null or map == null:
		return
	for c in icon_root.get_children():
		c.queue_free()
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		var sys_scale: float = visual_scale_of(sid)
		var outer: float = float(map.layout.get("ring_outer", 26)) * sys_scale
		for cell in sys["cells"]:
			var kind: int = int(cell["kind"])
			if not SECTOR_ICON.has(kind):
				continue
			var a: float = float(cell["angle_center"])
			var r: float = outer + 3.2
			var pos: Vector3 = sys["center"] + Vector3(sin(a) * r, 0.55, -cos(a) * r)
			var spr = _billboard_sprite(SECTOR_ICON[kind], pos, ICON_BASE_PIXEL)
			spr.set_meta("edge_sid", sid)
			spr.set_meta("edge_ang", a)
			spr.set_meta("edge_pad", 3.2)
			spr.set_meta("edge_y", 0.55)
			icon_root.add_child(spr)

func _rebuild_system_markers() -> void:
	if icon_root == null or map == null:
		return
	const STATION_TEX := "res://assets/ui/sector/station.png"
	const GEAR_TEX := "res://assets/ui/sector/gear.png"
	const RESOURCE_FALLBACK := "res://assets/ui/sector/resource.png"
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		var center: Vector3 = sys["center"]
		var kind: String = str(sys.get("kind", "station_system"))
		if kind == "station_system":
			var tex_path = STATION_TEX
			if ResourceLoader.exists(tex_path):
				var spr = _billboard_sprite(tex_path, center + Vector3(0, 0.35, 0), ICON_BASE_PIXEL * 1.85)
				spr.set_meta("system_marker", true)
				icon_root.add_child(spr)
			else:
				_add_system_sphere_marker(center)
		elif kind == "resource_system":
			var gear_path = GEAR_TEX if ResourceLoader.exists(GEAR_TEX) else RESOURCE_FALLBACK
			if ResourceLoader.exists(gear_path):
				var spr2 = _billboard_sprite(gear_path, center + Vector3(0, 0.35, 0), ICON_BASE_PIXEL * 1.35)
				spr2.set_meta("system_marker", true)
				icon_root.add_child(spr2)
			else:
				_add_system_sphere_marker(center)
		else:
			_add_system_sphere_marker(center)
		icon_root.add_child(_billboard_label(str(sys.get("name", sid)), center + Vector3(0, 2.2, 0), 64))

func _add_system_sphere_marker(center: Vector3) -> void:
	var dot = MeshInstance3D.new()
	var sph = SphereMesh.new()
	sph.radius = 0.85
	sph.height = 1.7
	dot.mesh = sph
	var dmat = StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(0.85, 0.9, 1.0, 0.9)
	dot.material_override = dmat
	dot.position = center + Vector3(0, 0.2, 0)
	dot.set_meta("system_marker", true)
	icon_root.add_child(dot)

func _rebuild_cell_pick() -> void:
	if cell_pick_root == null or map == null:
		return
	for c in cell_pick_root.get_children():
		c.queue_free()
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		var sys_scale: float = visual_scale_of(sid)
		var inner: float = float(map.layout.get("ring_inner", 12)) * sys_scale
		var outer: float = float(map.layout.get("ring_outer", 26)) * sys_scale
		var mid_r = (inner + outer) * 0.5
		var depth = maxf(outer - inner, 1.0)
		for cell in sys["cells"]:
			var a: float = float(cell["angle_center"])
			var half: float = float(cell["angle_half"])
			var arc = mid_r * half * 2.0
			var body = StaticBody3D.new()
			body.collision_layer = 2
			body.collision_mask = 0
			body.set_meta("sys", sid)
			body.set_meta("cell", int(cell["index"]))
			var col = CollisionShape3D.new()
			var box = BoxShape3D.new()
			box.size = Vector3(maxf(arc, 2.0), 0.6, depth)
			col.shape = box
			body.add_child(col)
			body.position = sys["center"] + Vector3(sin(a) * mid_r, 0.05, -cos(a) * mid_r)
			body.rotation.y = a
			cell_pick_root.add_child(body)

func rebuild_labels(pilots: Array) -> void:
	pilots_ref = pilots
	if label_root == null:
		return
	for c in label_root.get_children():
		c.queue_free()
	if map == null:
		return
	var name_by_id: Dictionary = {}
	for p in pilots:
		name_by_id[str(p["id"])] = str(p.get("name", ""))
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		var sys_scale: float = visual_scale_of(sid)
		var outer: float = float(map.layout.get("ring_outer", 26)) * sys_scale
		for cell in sys["cells"]:
			if int(cell["kind"]) != BoardTypes.CellKind.RESOURCE:
				continue
			var pid: String = str(cell.get("assigned_pilot_id", ""))
			if pid == "" or not name_by_id.has(pid):
				continue
			var a: float = float(cell["angle_center"])
			var pos: Vector3 = sys["center"] + Vector3(sin(a) * (outer + 5.0), 0.7, -cos(a) * (outer + 5.0))
			var lab = _billboard_label(str(name_by_id[pid]), pos, 44, Color(0.85, 1.0, 0.85, 1.0))
			lab.set_meta("edge_sid", sid)
			lab.set_meta("edge_ang", a)
			lab.set_meta("edge_pad", 5.0)
			lab.set_meta("edge_y", 0.7)
			label_root.add_child(lab)
