extends RefCounted
class_name BoardRingsBuilder

const RING_INNER := 3.2
const RING_OUTER := 7.2
const SEGS := 96
const TEX_W := 48

var _shared_annulus: ArrayMesh
var _sids: Array = []
var _map: BigmapFromStarfield
var _parent: Node3D
var _idx := 0


func begin(map: BigmapFromStarfield, parent: Node3D) -> void:
	_map = map
	_parent = parent
	_sids = map.systems.keys()
	_sids.sort()
	_idx = 0
	_shared_annulus = _build_annulus(SEGS)
	for c in parent.get_children():
		c.queue_free()


func progress() -> float:
	if _sids.is_empty():
		return 1.0
	return clampf(float(_idx) / float(_sids.size()), 0.0, 1.0)


func is_done() -> bool:
	return _idx >= _sids.size()


func step(budget: int = 24) -> bool:
	if _map == null or _parent == null:
		return true
	var end := mini(_idx + maxi(budget, 1), _sids.size())
	while _idx < end:
		_add_system(str(_sids[_idx]))
		_idx += 1
	return _idx >= _sids.size()


func _add_system(sid: String) -> void:
	var sys: Dictionary = _map.systems[sid]
	var center: Vector3 = sys["center"]
	var cells: Array = sys["cells"]
	var n := cells.size()
	if n <= 0:
		return
	var phase := _ring_phase(sys)
	var img := Image.create(TEX_W, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in TEX_W:
		var u := (float(x) + 0.5) / float(TEX_W)
		var ang := fposmod(u * TAU - phase, TAU)
		var cell_i := int(floor(ang / TAU * float(n))) % n
		var kind := int(cells[cell_i].get("kind", 0))
		var col := _kind_color(kind)
		if kind == BoardKinds.CellKind.EMPTY:
			col.a = 0.18
		else:
			col.a = 0.55
		img.set_pixel(x, 0, col)
		var rim := col
		rim.a = mini(col.a + 0.25, 0.85)
		img.set_pixel(x, 1, rim)
	var tex := ImageTexture.create_from_image(img)
	var fill := MeshInstance3D.new()
	fill.name = "Ring_%s" % sid
	fill.mesh = _shared_annulus
	var sm := ShaderMaterial.new()
	sm.shader = load("res://game/menu_bg/shaders/board_ring.gdshader")
	sm.set_shader_parameter("sector_tex", tex)
	sm.set_shader_parameter("row_v", 0.25)
	sm.set_shader_parameter("fade_inner", 1.0)
	fill.material_override = sm
	fill.position = Vector3(center.x, 0.04, center.z)
	var sc := RING_OUTER / 26.0
	fill.scale = Vector3(sc, 1.0, sc)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parent.add_child(fill)
	var seams := MeshInstance3D.new()
	seams.name = "Seams_%s" % sid
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var r0 := RING_INNER
	var r1 := RING_OUTER
	for i in n:
		var a := phase + float(i) / float(n) * TAU
		var sx := sin(a)
		var cz := -cos(a)
		st.set_color(Color(0.9, 0.92, 0.95, 0.35))
		st.add_vertex(Vector3(sx * r0, 0.06, cz * r0))
		st.add_vertex(Vector3(sx * r1, 0.06, cz * r1))
	seams.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	seams.material_override = mat
	seams.position = Vector3(center.x, 0.0, center.z)
	seams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parent.add_child(seams)


func _ring_phase(sys: Dictionary) -> float:
	var links: Array = sys.get("links", [])
	if links.is_empty() or _map == null:
		return 0.0
	var n := (sys.get("cells", []) as Array).size()
	if n <= 0:
		return 0.0
	var to_id := str(links[0])
	if not _map.systems.has(to_id):
		return 0.0
	var c0: Vector3 = sys["center"]
	var c1: Vector3 = _map.systems[to_id]["center"]
	var dir := c1 - c0
	var bearing := atan2(dir.x, -dir.z)
	if bearing < 0.0:
		bearing += TAU
	var half := PI / float(n)
	return fposmod(bearing - half, TAU)


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


func _build_annulus(segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_in := 12.0
	var r_out := 26.0
	var c_out := Color(1, 1, 1, 0.85)
	var c_in := Color(1, 1, 1, 0.0)
	for i in segs:
		var u0 := float(i) / float(segs)
		var u1 := float(i + 1) / float(segs)
		var a0 := u0 * TAU
		var a1 := u1 * TAU
		var p00 := Vector3(sin(a0) * r_out, 0.02, -cos(a0) * r_out)
		var p10 := Vector3(sin(a1) * r_out, 0.02, -cos(a1) * r_out)
		var p01 := Vector3(sin(a0) * r_in, 0.02, -cos(a0) * r_in)
		var p11 := Vector3(sin(a1) * r_in, 0.02, -cos(a1) * r_in)
		_tri(st, p00, Vector2(u0, 1.0), c_out, p10, Vector2(u1, 1.0), c_out, p11, Vector2(u1, 0.0), c_in)
		_tri(st, p00, Vector2(u0, 1.0), c_out, p11, Vector2(u1, 0.0), c_in, p01, Vector2(u0, 0.0), c_in)
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
