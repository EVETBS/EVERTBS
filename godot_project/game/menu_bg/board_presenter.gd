extends RefCounted
class_name BoardPresenter

## Trial-board rings, sector icons, and gate-to-gate links (starmap_view parity).

const RING_IN := 12.0
const RING_OUT := 26.0
const RIM_THICK := 0.64
const SEGS := 256
const TEX_W := 256
const SEAM_PX := 3
const ICON_R := 26.0 + 3.2
## Match empty_system_scale: systems with no ships draw at this size.
const EMPTY_SYSTEM_SCALE := 0.62

const ICON_GATE := "res://assets/ui/sector/stargate.png"
const ICON_RES := "res://assets/ui/sector/resource.png"
const ICON_STATION := "res://assets/ui/sector/station.png"
const ICON_SOV := "res://assets/ui/sector/sov.png"
const ICON_GEAR := "res://assets/ui/sector/gear.png"

var _map: BigmapFromStarfield
var _rings: Node3D
var _icons: Node3D
var _links: Node3D
var _sids: Array = []
var _idx := 0
var _annulus: ArrayMesh
var _rim: ArrayMesh
var _link_pairs: Array = []
var _shaft_mm: MultiMesh
var _tip_mm: MultiMesh
var _visible_ids: Dictionary = {}
var _pairs_by_sid: Dictionary = {}
var _visual_scale: Dictionary = {}


func begin(map: BigmapFromStarfield, rings: Node3D, icons: Node3D, links: Node3D) -> void:
	_map = map
	_rings = rings
	_icons = icons
	_links = links
	_sids = map.systems.keys()
	_sids.sort()
	_idx = 0
	_annulus = _build_annulus(SEGS)
	_rim = _build_rim(SEGS)
	for c in rings.get_children():
		c.queue_free()
	for c in icons.get_children():
		c.queue_free()
	for c in links.get_children():
		c.queue_free()


func progress() -> float:
	if _sids.is_empty():
		return 1.0
	return clampf(float(_idx) / float(_sids.size()), 0.0, 1.0)


func step_rings(budget: int = 24) -> bool:
	if _map == null:
		return true
	var end := mini(_idx + maxi(budget, 1), _sids.size())
	while _idx < end:
		_add_ring(str(_sids[_idx]))
		_idx += 1
	return _idx >= _sids.size()


func build_icons_and_links() -> void:
	_build_icons()
	_build_links()


func _gate_target_visible(_sid: String, cell: Dictionary) -> bool:
	## Drop a gate only when it has no real far system. A target outside the shot
	## still keeps its icon: the link is drawn out of frame (MENU_BACKDROP §3).
	var to_id := str(cell.get("gate_to", ""))
	if to_id.is_empty() or _map == null or not _map.systems.has(to_id):
		return false
	return true


func _link_reaches_shot(a_id: String, b_id: String) -> bool:
	if _visible_ids.is_empty():
		return true
	return _visible_ids.has(a_id) or _visible_ids.has(b_id)


func _effective_kind(sid: String, cell: Dictionary) -> int:
	var kind := int(cell.get("kind", 0))
	if kind == BoardKinds.CellKind.GATE and not _gate_target_visible(sid, cell):
		return BoardKinds.CellKind.EMPTY
	return kind


func _add_ring(sid: String) -> void:
	var sys: Dictionary = _map.systems[sid]
	var cells: Array = sys["cells"]
	var n: int = mini(cells.size(), 12)
	var img := Image.create(TEX_W, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var keys := PackedFloat32Array()
	keys.resize(n)
	var fills := PackedColorArray()
	fills.resize(n)
	var edges := PackedColorArray()
	edges.resize(n)
	var works := PackedFloat32Array()
	works.resize(n)
	for i in n:
		var c: Dictionary = cells[i]
		var half := float(c.get("angle_half", PI / float(n)))
		keys[i] = fposmod(float(c.get("angle_center", 0.0)) - half, TAU)
		var kind := _effective_kind(sid, c)
		var base := _kind_color(kind)
		var edge := Color(1, 1, 1, 1)
		var owner_fac := int(c.get("owner", 0))
		var capturing := int(c.get("capturing", 0))
		if kind != BoardKinds.CellKind.EMPTY:
			if capturing != 0:
				edge = _map.owner_color(capturing)
			elif owner_fac != 0:
				edge = _map.owner_color(owner_fac)
		fills[i] = Color(base.r, base.g, base.b, 0.70)
		edges[i] = edge
		works[i] = clampf(float(c.get("work", BoardKinds.WORK_MAX)) / BoardKinds.WORK_MAX, 0.0, 1.0)
	_paint_sector_tex(img, keys, n, fills, edges, works)
	var tex := ImageTexture.create_from_image(img)
	var root := Node3D.new()
	root.name = sid
	root.set_meta("sector_tex", tex)
	var center: Vector3 = sys["center"]
	root.position = Vector3(center.x, 0.0, center.z)
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	fill.mesh = _annulus
	fill.material_override = _ring_mat(tex, 0.25, true)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = _rim
	rim.material_override = _ring_mat(tex, 0.75, false)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rim)
	_rings.add_child(root)


func _paint_sector_tex(img: Image, keys: PackedFloat32Array, n: int, fills: PackedColorArray, edges: PackedColorArray, works: PackedFloat32Array) -> void:
	var w := img.get_width()
	for x in w:
		var ang := (float(x) + 0.5) / float(w) * TAU
		var ci := _cell_at_angle(ang, keys, n)
		var a0 := float(keys[ci])
		var span := fposmod(float(keys[(ci + 1) % n]) - a0, TAU)
		var rel := fposmod(ang - a0, TAU)
		var fill: Color = fills[ci]
		var edge: Color = edges[ci]
		var arc_t := rel / maxf(span, 0.001)
		var wn := float(works[ci])
		var spread := 1.0 - wn
		var from_mid := absf(arc_t - 0.5) * 2.0
		if wn < 0.999 and from_mid > spread:
			edge = Color(1, 1, 1, 1)
		edge.a = 1.0
		img.set_pixel(x, 0, fill)
		img.set_pixel(x, 1, edge)
	for i in n:
		var kx := int(floor(fposmod(float(keys[i]), TAU) / TAU * float(w)))
		for dx in range(-SEAM_PX + 1, SEAM_PX):
			var xx := posmod(kx + dx, w)
			img.set_pixel(xx, 0, Color(0, 0, 0, 0))
			img.set_pixel(xx, 1, Color(0, 0, 0, 0))


func _cell_at_angle(ang: float, keys: PackedFloat32Array, n: int) -> int:
	for i in n:
		var a0 := float(keys[i])
		var span := fposmod(float(keys[(i + 1) % n]) - a0, TAU)
		var rel := fposmod(ang - a0, TAU)
		if rel <= span + 0.0001:
			return i
	return 0


func _ring_mat(tex: Texture2D, row_v: float, fade_inner: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.vertex_color_use_as_albedo = fade_inner
	mat.uv1_scale = Vector3(1.0, 0.001, 1.0)
	mat.uv1_offset = Vector3(0.0, row_v, 0.0)
	return mat


func _build_annulus(segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c_out := Color(1, 1, 1, 0.85)
	var c_in := Color(1, 1, 1, 0.0)
	for i in segs:
		var u0 := float(i) / float(segs)
		var u1 := float(i + 1) / float(segs)
		var a0 := u0 * TAU
		var a1 := u1 * TAU
		var p00 := Vector3(sin(a0) * RING_OUT, 0.02, -cos(a0) * RING_OUT)
		var p10 := Vector3(sin(a1) * RING_OUT, 0.02, -cos(a1) * RING_OUT)
		var p01 := Vector3(sin(a0) * RING_IN, 0.02, -cos(a0) * RING_IN)
		var p11 := Vector3(sin(a1) * RING_IN, 0.02, -cos(a1) * RING_IN)
		_tri(st, p00, Vector2(u0, 1.0), c_out, p10, Vector2(u1, 1.0), c_out, p11, Vector2(u1, 0.0), c_in)
		_tri(st, p00, Vector2(u0, 1.0), c_out, p11, Vector2(u1, 0.0), c_in, p01, Vector2(u0, 0.0), c_in)
	st.generate_normals()
	return st.commit()


func _build_rim(segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r0 := RING_OUT
	var r1 := RING_OUT + RIM_THICK
	var col := Color(1, 1, 1, 1)
	for i in segs:
		var u0 := float(i) / float(segs)
		var u1 := float(i + 1) / float(segs)
		var a0 := u0 * TAU
		var a1 := u1 * TAU
		var p00 := Vector3(sin(a0) * r1, 0.03, -cos(a0) * r1)
		var p10 := Vector3(sin(a1) * r1, 0.03, -cos(a1) * r1)
		var p01 := Vector3(sin(a0) * r0, 0.03, -cos(a0) * r0)
		var p11 := Vector3(sin(a1) * r0, 0.03, -cos(a1) * r0)
		_tri(st, p00, Vector2(u0, 1.0), col, p10, Vector2(u1, 1.0), col, p11, Vector2(u1, 0.0), col)
		_tri(st, p00, Vector2(u0, 1.0), col, p11, Vector2(u1, 0.0), col, p01, Vector2(u0, 0.0), col)
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, uva: Vector2, ca: Color, b: Vector3, uvb: Vector2, cb: Color, c: Vector3, uvc: Vector2, cc: Color) -> void:
	st.set_uv(uva)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_uv(uvb)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_uv(uvc)
	st.set_color(cc)
	st.add_vertex(c)


func _kind_color(kind: int) -> Color:
	match kind:
		BoardKinds.CellKind.GATE:
			return Color(0.22, 0.38, 0.82, 1.0)
		BoardKinds.CellKind.RESOURCE:
			return Color(0.22, 0.65, 0.28, 1.0)
		BoardKinds.CellKind.STATION:
			return Color(0.82, 0.72, 0.18, 1.0)
		BoardKinds.CellKind.SOV:
			return Color(0.78, 0.18, 0.18, 1.0)
		_:
			return Color(0.55, 0.55, 0.58, 1.0)


func _icon_path(kind: int) -> String:
	match kind:
		BoardKinds.CellKind.GATE:
			return ICON_GATE
		BoardKinds.CellKind.RESOURCE:
			return ICON_RES
		BoardKinds.CellKind.STATION:
			return ICON_STATION
		BoardKinds.CellKind.SOV:
			return ICON_SOV
		_:
			return ""


func _build_icons() -> void:
	## Match starmap_view: Sprite3D + BILLBOARD_ENABLED so icons face the camera.
	## One holder per system so the skirmish can hide systems outside the shot.
	for sid in _map.systems.keys():
		var holder := Node3D.new()
		holder.name = str(sid)
		_icons.add_child(holder)
		var sys: Dictionary = _map.systems[sid]
		var center: Vector3 = sys["center"]
		var skind: String = str(sys.get("kind", ""))
		if skind == "station_system":
			_add_billboard_icon(ICON_STATION, center + Vector3(0, 0.55, 0), 3.6, holder)
		elif skind == "resource_system":
			_add_billboard_icon(ICON_GEAR, center + Vector3(0, 0.55, 0), 1.7, holder)
		else:
			_add_dot_marker(center, holder)
		var cells: Array = sys["cells"]
		for ci in cells.size():
			var c: Dictionary = cells[ci]
			var kind := _effective_kind(str(sid), c)
			var path := _icon_path(kind)
			if path == "":
				continue
			var ang := float(c.get("angle_center", 0.0))
			var pos := center + Vector3(sin(ang) * ICON_R, 0.6, -cos(ang) * ICON_R)
			var spr := _add_billboard_icon(path, pos, 2.2, holder)
			if spr:
				spr.set_meta("cell_i", ci)
				spr.set_meta("base_kind", int(c.get("kind", 0)))


func _add_billboard_icon(path: String, pos: Vector3, world_size: float, parent: Node3D = null) -> Sprite3D:
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.double_sided = true
	spr.no_depth_test = true
	spr.transparent = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	var tw := float(tex.get_width()) if tex else 64.0
	spr.pixel_size = world_size / maxf(tw, 1.0)
	spr.position = pos
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else _icons).add_child(spr)
	return spr



func _add_dot_marker(center: Vector3, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Dot"
	var sph := SphereMesh.new()
	sph.radius = 0.85
	sph.height = 1.7
	sph.radial_segments = 10
	sph.rings = 6
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.78, 0.8, 0.84, 1.0)
	mat.no_depth_test = true
	mi.material_override = mat
	mi.position = center + Vector3(0, 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else _icons).add_child(mi)


func gate_outer_point(from_id: String, to_id: String) -> Vector3:
	var sys: Dictionary = _map.systems[from_id]
	var center: Vector3 = sys["center"]
	var ang := 0.0
	var found := false
	for c in sys["cells"]:
		if int(c.get("kind", -1)) == BoardKinds.CellKind.GATE and str(c.get("gate_to", "")) == to_id:
			ang = float(c.get("angle_center", 0.0))
			found = true
			break
	if not found and _map.systems.has(to_id):
		var other: Vector3 = _map.systems[to_id]["center"]
		var dirv := other - center
		ang = atan2(dirv.x, -dirv.z)
	var outer := (RING_OUT + 0.4) * visual_scale_of(from_id)
	return center + Vector3(sin(ang) * outer, 0.08, -cos(ang) * outer)


func visual_scale_of(sid: String) -> float:
	return float(_visual_scale.get(sid, 1.0))


func apply_visual_scale(sid: String, scale: float) -> void:
	## Ring, rim icons, and gate endpoints share one XZ scale (match visual_scale).
	var s := clampf(scale, EMPTY_SYSTEM_SCALE, 1.0)
	if _visual_scale.has(sid) and absf(visual_scale_of(sid) - s) < 0.0008:
		return
	_visual_scale[sid] = s
	var ring := _rings.get_node_or_null(NodePath(sid)) as Node3D
	if ring:
		ring.scale = Vector3(s, 1.0, s)
	_place_cell_icons(sid)
	if _shaft_mm == null or _tip_mm == null:
		return
	for i in (_pairs_by_sid.get(sid, PackedInt32Array()) as PackedInt32Array):
		var p: Dictionary = _link_pairs[i]
		_write_link(i, _link_reaches_shot(str(p["a"]), str(p["b"])))


func _place_cell_icons(sid: String) -> void:
	var holder := _icons.get_node_or_null(NodePath(sid)) as Node3D
	if holder == null or not _map.systems.has(sid):
		return
	var center: Vector3 = _map.systems[sid]["center"]
	var cells: Array = _map.systems[sid]["cells"]
	var radius := ICON_R * visual_scale_of(sid)
	for spr in holder.get_children():
		if not spr.has_meta("cell_i"):
			continue
		var ci := int(spr.get_meta("cell_i"))
		if ci < 0 or ci >= cells.size():
			continue
		var ang := float(cells[ci].get("angle_center", 0.0))
		(spr as Node3D).position = center + Vector3(sin(ang) * radius, 0.6, -cos(ang) * radius)


func _build_links() -> void:
	var pairs: Array = []
	var seen: Dictionary = {}
	for sid in _map.systems.keys():
		for link in _map.systems[sid]["links"]:
			var a_id := str(sid)
			var b_id := str(link)
			var key := a_id + ">" + b_id
			if seen.has(key):
				continue
			seen[key] = true
			if not _map.systems.has(b_id):
				continue
			pairs.append({"a": a_id, "b": b_id})
	var shaft_mm := MultiMesh.new()
	shaft_mm.transform_format = MultiMesh.TRANSFORM_3D
	shaft_mm.use_colors = true
	shaft_mm.mesh = _unit_shaft()
	shaft_mm.instance_count = pairs.size()
	_shaft_mm = shaft_mm
	var tip_mm := MultiMesh.new()
	tip_mm.transform_format = MultiMesh.TRANSFORM_3D
	tip_mm.use_colors = true
	tip_mm.mesh = _unit_tip()
	tip_mm.instance_count = pairs.size()
	_tip_mm = tip_mm
	_link_pairs = pairs
	_pairs_by_sid.clear()
	for pi in pairs.size():
		for end in ["a", "b"]:
			var s := str(pairs[pi][end])
			## PackedInt32Array is a value type: append on a cast copy is discarded
			## unless written back — empty index left sync_system unable to move links.
			var idxs: PackedInt32Array = _pairs_by_sid.get(s, PackedInt32Array())
			idxs.append(pi)
			_pairs_by_sid[s] = idxs
	for i in pairs.size():
		_write_link(i, true)
	var shaft_mi := MultiMeshInstance3D.new()
	shaft_mi.name = "LinkShafts"
	shaft_mi.multimesh = shaft_mm
	shaft_mi.material_override = _link_mat()
	shaft_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_links.add_child(shaft_mi)
	var tip_mi := MultiMeshInstance3D.new()
	tip_mi.name = "LinkTips"
	tip_mi.multimesh = tip_mm
	tip_mi.material_override = _link_mat()
	tip_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_links.add_child(tip_mi)


func _link_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	return mat


func _unit_shaft() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(1, 1, 1, 1)
	_tri(st, Vector3(0, 0, -0.5), Vector2(0, 0), col, Vector3(1, 0, -0.5), Vector2(1, 0), col, Vector3(1, 0, 0.5), Vector2(1, 1), col)
	_tri(st, Vector3(0, 0, -0.5), Vector2(0, 0), col, Vector3(1, 0, 0.5), Vector2(1, 1), col, Vector3(0, 0, 0.5), Vector2(0, 1), col)
	return st.commit()


func _unit_tip() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(1, 1, 1, 1)
	_tri(st, Vector3(0, 0, -0.5), Vector2(0, 0), col, Vector3(1, 0, 0), Vector2(1, 0.5), col, Vector3(0, 0, 0.5), Vector2(0, 1), col)
	return st.commit()


func repaint_system(sid: String) -> void:
	var root := _rings.get_node_or_null(NodePath(str(sid))) as Node3D
	if root == null or not _map.systems.has(sid):
		return
	var sys: Dictionary = _map.systems[sid]
	var cells: Array = sys["cells"]
	var n: int = mini(cells.size(), 12)
	var img := Image.create(TEX_W, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var keys := PackedFloat32Array()
	keys.resize(n)
	var fills := PackedColorArray()
	fills.resize(n)
	var edges := PackedColorArray()
	edges.resize(n)
	var works := PackedFloat32Array()
	works.resize(n)
	for i in n:
		var c: Dictionary = cells[i]
		var half := float(c.get("angle_half", PI / float(n)))
		keys[i] = fposmod(float(c.get("angle_center", 0.0)) - half, TAU)
		var kind := _effective_kind(sid, c)
		var base := _kind_color(kind)
		var edge := Color(1, 1, 1, 1)
		var owner_fac := int(c.get("owner", 0))
		var capturing := int(c.get("capturing", 0))
		if kind != BoardKinds.CellKind.EMPTY:
			if capturing != 0:
				edge = _map.owner_color(capturing)
			elif owner_fac != 0:
				edge = _map.owner_color(owner_fac)
		fills[i] = Color(base.r, base.g, base.b, 0.70)
		edges[i] = edge
		works[i] = clampf(float(c.get("work", BoardKinds.WORK_MAX)) / BoardKinds.WORK_MAX, 0.0, 1.0)
	_paint_sector_tex(img, keys, n, fills, edges, works)
	## Fill and Rim share one texture; update() reuses its GPU allocation.
	var tex: ImageTexture = root.get_meta("sector_tex", null)
	if tex != null:
		tex.update(img)
		return
	tex = ImageTexture.create_from_image(img)
	root.set_meta("sector_tex", tex)
	for child in root.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.material_override == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat:
			mat.albedo_texture = tex


func _sync_cell_icon_visibility(sid: String) -> void:
	var holder := _icons.get_node_or_null(NodePath(sid)) as Node3D
	if holder == null or not _map.systems.has(sid):
		return
	var cells: Array = _map.systems[sid]["cells"]
	for spr in holder.get_children():
		if not spr.has_meta("cell_i"):
			continue
		var ci := int(spr.get_meta("cell_i"))
		if ci < 0 or ci >= cells.size():
			continue
		## Gate demoted to empty → hide stargate icon; other kinds stay.
		var base_kind := int(spr.get_meta("base_kind", cells[ci].get("kind", 0)))
		if base_kind == BoardKinds.CellKind.GATE:
			(spr as Node3D).visible = _gate_target_visible(sid, cells[ci])
		else:
			(spr as Node3D).visible = true


func set_visible_systems(ids: Dictionary) -> void:
	_visible_ids = ids
	var orphan_gates := 0
	var shown_gates := 0
	for c in _rings.get_children():
		c.visible = ids.has(str(c.name))
	for c in _icons.get_children():
		c.visible = ids.has(str(c.name))
	for sid in ids.keys():
		var s := str(sid)
		if not _map.systems.has(s):
			continue
		for cell in _map.systems[s]["cells"]:
			if int(cell.get("kind", -1)) != BoardKinds.CellKind.GATE:
				continue
			if _gate_target_visible(s, cell):
				shown_gates += 1
			else:
				orphan_gates += 1
		repaint_system(s)
		_sync_cell_icon_visibility(s)
	# #region agent log
	DebugSessionLog.append("BG", "board_presenter.set_visible_systems", "gate_cull", {
		"visible_sys": ids.size(), "shown_gates": shown_gates,
		"demoted_orphan_gates": orphan_gates, "runId": "pre-fix"
	})
	# #endregion
	if _shaft_mm == null or _tip_mm == null:
		return
	for i in _link_pairs.size():
		var p: Dictionary = _link_pairs[i]
		_write_link(i, _link_reaches_shot(str(p["a"]), str(p["b"])))


## Arc widths or owners of one system changed: repaint wedges, slide cell icons, re-aim its gate links.
func sync_system(sid: String) -> void:
	repaint_system(sid)
	_sync_cell_icon_visibility(sid)
	_place_cell_icons(sid)
	if _shaft_mm == null or _tip_mm == null:
		return
	var link_idxs: PackedInt32Array = _pairs_by_sid.get(sid, PackedInt32Array())
	for i in link_idxs:
		var p: Dictionary = _link_pairs[i]
		_write_link(i, _link_reaches_shot(str(p["a"]), str(p["b"])))


func _write_link(i: int, show: bool) -> void:
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
	if not show:
		_shaft_mm.set_instance_transform(i, hidden)
		_tip_mm.set_instance_transform(i, hidden)
		return
	var p: Dictionary = _link_pairs[i]
	var a_id := str(p["a"])
	var b_id := str(p["b"])
	var a := gate_outer_point(a_id, b_id)
	var b := gate_outer_point(b_id, a_id)
	var owner := 0
	for c in _map.systems[a_id]["cells"]:
		if int(c.get("kind", -1)) == BoardKinds.CellKind.GATE and str(c.get("gate_to", "")) == b_id:
			owner = int(c.get("owner", 0))
			break
	var col := _map.owner_color(owner) if owner != 0 else Color(1, 1, 1, 1)
	col.a = 0.92 if owner != 0 else 0.28
	var tip: Vector3 = a.lerp(b, 0.72)
	var dirv := tip - a
	var seg := dirv.length()
	if seg < 0.001:
		_shaft_mm.set_instance_transform(i, hidden)
		_tip_mm.set_instance_transform(i, hidden)
		return
	dirv /= seg
	var side := Vector3(-dirv.z, 0, dirv.x)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var sb := Basis()
	sb.x = dirv * seg
	sb.y = Vector3.UP
	sb.z = side * 0.56
	_shaft_mm.set_instance_transform(i, Transform3D(sb, a))
	_shaft_mm.set_instance_color(i, col)
	var tip_len := 3.0
	var tb := Basis()
	tb.x = dirv * tip_len
	tb.y = Vector3.UP
	tb.z = side * 2.0
	var origin: Vector3 = tip - dirv * tip_len
	origin.y = 0.09
	_tip_mm.set_instance_transform(i, Transform3D(tb, origin))
	_tip_mm.set_instance_color(i, col)


func cell_world_pos(sid: String, cell_i: int, radius: float = 19.0) -> Vector3:
	var sys: Dictionary = _map.systems[sid]
	var center: Vector3 = sys["center"]
	var cells: Array = sys["cells"]
	var ang := 0.0
	if cell_i >= 0 and cell_i < cells.size():
		ang = float(cells[cell_i].get("angle_center", 0.0))
	return center + Vector3(sin(ang) * radius, 0.9, -cos(ang) * radius)
