extends RefCounted
class_name TerritoryBaker

## Stepped CPU Voronoi Territory bake (no 8-site shader cap).
## Packed A: fill~0.25, border~1.0. Call begin_bake -> step_rows -> finish_bake.

const SiteGridScr := preload("res://game/menu_bg/territory_site_grid.gd")
const FILL_CODE := 0.25
const BORDER_CODE := 1.0
const EDGE_BASE := 0.88
const JAGGED := 0.16
const BORDER_W := 2.4

var _sites_x: PackedFloat32Array = PackedFloat32Array()
var _sites_z: PackedFloat32Array = PackedFloat32Array()
var _sites_r: PackedFloat32Array = PackedFloat32Array()
var _sites_g: PackedFloat32Array = PackedFloat32Array()
var _sites_b: PackedFloat32Array = PackedFloat32Array()
var _sites_fac: PackedFloat32Array = PackedFloat32Array()
var _site_count := 0
var _grid: Dictionary = {}
var _cell := 28.0
var _tex_size := 512
var _mid := Vector2.ZERO
var _size := Vector2.ZERO
var _half := Vector2.ZERO
var _origin := Vector2.ZERO
var _cluster_r := 0.0
var _inv := 0.0
var _buf: PackedByteArray = PackedByteArray()
var _row := 0
var _ready := false
var _map_scale := 1.0
var _border_w := BORDER_W
var _warp := JAGGED * 28.0
var _built_site_grid: Dictionary = {}


func begin_bake(map: BigmapFromStarfield, tex_size: int = 512) -> bool:
	_ready = false
	_row = 0
	_tex_size = maxi(tex_size, 64)
	_map_scale = maxf(1.0, float(map.map_scale))
	_border_w = BORDER_W * _map_scale
	_warp = JAGGED * 28.0 * _map_scale
	_sites_x = PackedFloat32Array()
	_sites_z = PackedFloat32Array()
	_sites_r = PackedFloat32Array()
	_sites_g = PackedFloat32Array()
	_sites_b = PackedFloat32Array()
	_sites_fac = PackedFloat32Array()
	var min_x := map.bounds_min.x
	var max_x := map.bounds_max.x
	var min_z := map.bounds_min.y
	var max_z := map.bounds_max.y
	for sid in map.systems.keys():
		var ow := map.sov_owner_of(str(sid))
		if ow == 0:
			continue
		var c: Vector3 = map.systems[sid]["center"]
		var col: Color = map.owner_color(ow)
		_sites_x.append(c.x)
		_sites_z.append(c.z)
		_sites_r.append(col.r)
		_sites_g.append(col.g)
		_sites_b.append(col.b)
		_sites_fac.append(float(ow))
	_site_count = _sites_x.size()
	if _site_count == 0:
		return false

	_mid = Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)
	_cluster_r = 0.0
	for i in _site_count:
		_cluster_r = maxf(_cluster_r, Vector2(_sites_x[i], _sites_z[i]).distance_to(_mid))
	_cluster_r = maxf(_cluster_r + 28.0 * _map_scale, 45.0 * _map_scale)
	var max_reach := _cluster_r * (EDGE_BASE + 1.5 * 2.6) + 40.0 * _map_scale
	var span_x := maxf(max_x - min_x, 40.0)
	var span_z := maxf(max_z - min_z, 40.0)
	_size = Vector2(
		maxf(span_x + 40.0, max_reach * 2.0),
		maxf(span_z + 40.0, max_reach * 2.0)
	)
	_half = _size * 0.5
	_origin = _mid - _half
	_inv = 1.0 / float(_tex_size)

	# Keep spatial hash coarse enough that ring=2 covers nearest sites after map_scale.
	_cell = maxf(28.0, 28.0 * maxf(1.0, float(map.map_scale)))
	_grid.clear()
	for i in _site_count:
		var key := _gk(Vector2(_sites_x[i], _sites_z[i]))
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		var arr: PackedInt32Array = _grid[key]
		arr.append(i)
		_grid[key] = arr

	_buf = PackedByteArray()
	_buf.resize(_tex_size * _tex_size * 4)
	_buf.fill(0)
	_ready = true
	return true


func progress() -> float:
	if not _ready or _tex_size <= 0:
		return 1.0
	return clampf(float(_row) / float(_tex_size), 0.0, 1.0)


func is_done() -> bool:
	return (not _ready) or _row >= _tex_size


## Process up to rows_budget scanlines. Returns true when finished.
func step_rows(rows_budget: int = 12) -> bool:
	if not _ready or _row >= _tex_size:
		return true
	var end_row := mini(_row + maxi(rows_budget, 1), _tex_size)
	var margin_x := maxf(_half.x - 6.0 * _map_scale, 1.0)
	var margin_z := maxf(_half.y - 6.0 * _map_scale, 1.0)
	var warp := _warp
	var border_w := _border_w
	while _row < end_row:
		var wz := _origin.y + (float(_row) + 0.5) * _inv * _size.y
		var row_off := _row * _tex_size * 4
		for px in _tex_size:
			var wx := _origin.x + (float(px) + 0.5) * _inv * _size.x
			var dx := absf(wx - _mid.x)
			var dz := absf(wz - _mid.y)
			if dx > margin_x or dz > margin_z:
				continue
			var from_x := wx - _mid.x
			var from_z := wz - _mid.y
			var ang := atan2(from_z, from_x)
			var ncoast := _coast_noise(wx, wz, ang)
			var reach := _cluster_r * (EDGE_BASE + JAGGED * 2.6 * ncoast)
			var bi0 := _nearest(wx, wz)
			if bi0 < 0:
				continue
			var best0 := _dist(wx, wz, bi0)
			if best0 > reach:
				continue
			var sn := _seam_noise(wx, wz)
			var sn2 := _seam_noise(wx + 23.0, wz - 11.0)
			var pwx := wx + warp * sn
			var pwz := wz + warp * sn2
			var bi := _nearest(pwx, pwz)
			if bi < 0:
				bi = bi0
			var best := _dist(pwx, pwz, bi)
			var fac := _sites_fac[bi]
			## Constant world-width junction: (d2-d1)/|n2-n1| < border_w/2
			var second_diff := 1.0e20
			var sjx := pwx
			var sjz := pwz
			var cand := _candidates(pwx, pwz, 2)
			for k in cand.size():
				var j: int = cand[k]
				if absf(_sites_fac[j] - fac) < 0.5:
					continue
				var d := _dist(pwx, pwz, j)
				if d < second_diff:
					second_diff = d
					sjx = _sites_x[j]
					sjz = _sites_z[j]
			var code := FILL_CODE
			var outer_edge := reach - best0
			if outer_edge < border_w * 1.4:
				code = maxf(code, 0.7)
			if outer_edge < border_w * 0.55:
				code = BORDER_CODE
			if second_diff < 1.0e19:
				var bx := _sites_x[bi]
				var bz := _sites_z[bi]
				var inv1 := 1.0 / maxf(best, 1.0e-4)
				var inv2 := 1.0 / maxf(second_diff, 1.0e-4)
				var n1x := (pwx - bx) * inv1
				var n1z := (pwz - bz) * inv1
				var n2x := (pwx - sjx) * inv2
				var n2z := (pwz - sjz) * inv2
				var grad := maxf(sqrt((n2x - n1x) * (n2x - n1x) + (n2z - n1z) * (n2z - n1z)), 1.0e-3)
				var dist_to_edge := (second_diff - best) / grad
				if dist_to_edge < border_w * 0.5:
					code = BORDER_CODE
				elif dist_to_edge < border_w * 0.5 + maxf(border_w * 0.08, 0.05):
					code = maxf(code, 0.7)
			var oi := row_off + px * 4
			_buf[oi] = int(clampf(_sites_r[bi] * 255.0, 0.0, 255.0))
			_buf[oi + 1] = int(clampf(_sites_g[bi] * 255.0, 0.0, 255.0))
			_buf[oi + 2] = int(clampf(_sites_b[bi] * 255.0, 0.0, 255.0))
			_buf[oi + 3] = int(clampf(code * 255.0, 0.0, 255.0))
		_row += 1
	return _row >= _tex_size


func finish_bake() -> Dictionary:
	if not _ready or _site_count == 0:
		return {}
	var img := Image.create_from_data(_tex_size, _tex_size, false, Image.FORMAT_RGBA8, _buf)
	var tex := ImageTexture.create_from_image(img)
	var out := {
		"texture": tex,
		"mid": Vector3(_mid.x, 0.02, _mid.y),
		"size": _size,
	}
	_ready = false
	return out


func make_dual_layers(parent: Node3D, bake_data: Dictionary, fill_a: float = 0.05, border_a: float = 0.2, raise_y: float = 0.45) -> void:
	if bake_data.is_empty():
		return
	var tex: Texture2D = bake_data["texture"]
	var mid: Vector3 = bake_data["mid"]
	var size: Vector2 = bake_data["size"]
	_add_layer(parent, "TerritoryFill", tex, mid, size, fill_a, border_a)
	_add_layer(parent, "TerritoryStrokeRaised", tex, mid + Vector3(0, raise_y, 0), size, 0.0, border_a)


func _add_layer(parent: Node3D, layer_name: String, tex: Texture2D, mid: Vector3, size: Vector2, fill_a: float, border_a: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = layer_name
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://game/menu_bg/shaders/bigmap_territory.gdshader")
	sm.set_shader_parameter("territory_tex", tex)
	sm.set_shader_parameter("fill_a", fill_a)
	sm.set_shader_parameter("border_a", border_a)
	mi.material_override = sm
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.position = mid
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _gk(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _cell), floori(p.y / _cell))


func _candidates(x: float, z: float, ring: int) -> PackedInt32Array:
	var g0 := Vector2i(floori(x / _cell), floori(z / _cell))
	var out := PackedInt32Array()
	for dy in range(-ring, ring + 1):
		for dx in range(-ring, ring + 1):
			var key := Vector2i(g0.x + dx, g0.y + dy)
			if not _grid.has(key):
				continue
			var arr: PackedInt32Array = _grid[key]
			for i in arr.size():
				out.append(arr[i])
	return out


func _nearest(x: float, z: float) -> int:
	var best_i := -1
	var best_d := 1.0e20
	var cand := _candidates(x, z, 2)
	if cand.is_empty():
		cand = _candidates(x, z, 4)
	if cand.is_empty():
		for i in _site_count:
			var d := _dist(x, z, i)
			if d < best_d:
				best_d = d
				best_i = i
		return best_i
	for k in cand.size():
		var i: int = cand[k]
		var d := _dist(x, z, i)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _dist(x: float, z: float, i: int) -> float:
	var dx := x - _sites_x[i]
	var dz := z - _sites_z[i]
	return sqrt(dx * dx + dz * dz)


func _coast_noise(x: float, z: float, ang: float) -> float:
	return sin(ang * 5.0) * 0.45 + sin(ang * 11.0 + 1.7) * 0.30 + sin(ang * 3.0 - 0.4) * 0.25 \
		+ sin(ang * 17.0 + 2.1) * 0.15 \
		+ sin(x * 0.08 + z * 0.11) * 0.20 + sin(x * 0.19 - z * 0.07 + 0.9) * 0.15


func _seam_noise(x: float, z: float) -> float:
	return sin(x * 0.22 + z * 0.17) * 0.40 \
		+ sin(x * 0.41 - z * 0.29 + 1.1) * 0.30 \
		+ sin((x + z) * 0.33 + 2.4) * 0.20 \
		+ sin(x * 0.09 - z * 0.48 + 0.6) * 0.25


## Runtime function/vector Voronoi fill + closed-face fill + influence outside.
func build_vector_dual_layers(
	parent: Node3D,
	map: BigmapFromStarfield,
	fill_a: float = 0.05,
	border_a: float = 0.2,
	raise_y: float = 0.45,
	jagged: float = 0.42,
	defer_grid: bool = false
) -> void:
	if parent == null or map == null:
		return
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()

	var sites_pos := PackedVector4Array()
	var sites_col := PackedVector4Array()
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	## Bounds from ALL systems so closed faces are not clipped.
	for sid in map.systems.keys():
		var c: Vector3 = map.systems[sid]["center"]
		min_x = minf(min_x, c.x)
		max_x = maxf(max_x, c.x)
		min_z = minf(min_z, c.z)
		max_z = maxf(max_z, c.z)
	var site_sids: PackedStringArray = PackedStringArray()
	for sid in map.systems.keys():
		## Include unowned SOV systems so later ownership can recolor without rebake.
		var has_sov := false
		for cell in map.systems[sid]["cells"]:
			if int(cell.get("kind", -1)) == BoardKinds.CellKind.SOV:
				has_sov = true
				break
		if not has_sov:
			continue
		var ow := map.sov_owner_of(str(sid))
		var c: Vector3 = map.systems[sid]["center"]
		var col: Color = _sov_fill_color(map, ow)
		sites_pos.append(Vector4(c.x, 0.0, c.z, float(ow)))
		sites_col.append(Vector4(col.r, col.g, col.b, col.a))
		site_sids.append(str(sid))
	var nsite := sites_pos.size()
	if nsite <= 0:
		push_warning("territory vector: no SOV sites")
		return
	nsite = mini(nsite, 512)
	if site_sids.size() > nsite:
		site_sids = site_sids.slice(0, nsite)
	parent.set_meta("territory_site_sids", site_sids)

	var mid := Vector3((min_x + max_x) * 0.5, 0.02, (min_z + max_z) * 0.5)
	var map_scale := maxf(1.0, float(map.map_scale))
	const RING_OUT := 26.0
	var nn_sum := 0.0
	var nn_n := 0
	for i in nsite:
		var sp: Vector4 = sites_pos[i]
		var best_nn := 1.0e20
		for j in nsite:
			if i == j:
				continue
			var sq: Vector4 = sites_pos[j]
			best_nn = minf(best_nn, Vector2(sp.x - sq.x, sp.z - sq.z).length())
		if best_nn < 1.0e19:
			nn_sum += best_nn
			nn_n += 1
	var nn_avg := nn_sum / float(maxi(nn_n, 1))
	## Influence only OUTSIDE closed faces (2× prior radius).
	var site_r := clampf(nn_avg * 0.58, RING_OUT * 1.35, RING_OUT * 3.5) * 2.0
	var span_x := maxf(max_x - min_x, 40.0)
	var span_z := maxf(max_z - min_z, 40.0)
	var pad := site_r * 2.2 + 20.0
	var size := Vector2(span_x + pad * 2.0, span_z + pad * 2.0)

	var pos_img := Image.create(nsite, 1, false, Image.FORMAT_RGBAF)
	var col_img := Image.create(nsite, 1, false, Image.FORMAT_RGBAF)
	for i in nsite:
		var sp: Vector4 = sites_pos[i]
		var sc: Vector4 = sites_col[i]
		pos_img.set_pixel(i, 0, Color(sp.x, sp.y, sp.z, sp.w))
		col_img.set_pixel(i, 0, Color(sc.x, sc.y, sc.z, sc.w))
	var pos_tex := ImageTexture.create_from_image(pos_img)
	var col_tex := ImageTexture.create_from_image(col_img)

	var border_w := 0.22 * map_scale
	var faces: Array = _find_bounded_link_faces(map)
	print("territory closed faces=", faces.size(), " baking mask...")
	var mask_tex := _bake_closed_face_mask(faces, mid, size, border_w)
	var noise_scale := 1.0 / map_scale
	var t_grid := Time.get_ticks_msec()
	var grid: Dictionary = {}
	var grid_args := {
		"sites_pos": sites_pos,
		"nsite": nsite,
		"mid": mid,
		"size": size,
		"site_r": site_r,
		"border_w": border_w,
		"jagged": jagged,
		"noise_scale": noise_scale,
	}
	if defer_grid:
		parent.set_meta("territory_grid_args", grid_args)
	else:
		grid = SiteGridScr.build(
			sites_pos, nsite, mid, size, site_r, border_w, jagged, noise_scale
		)
	var grid_ms := Time.get_ticks_msec() - t_grid
	_add_vector_layer(
		parent, "TerritoryFill", pos_tex, col_tex, nsite, mid, size,
		site_r, border_w, jagged, fill_a, border_a, noise_scale, mask_tex, grid
	)
	_add_vector_layer(
		parent, "TerritoryStrokeRaised", pos_tex, col_tex, nsite,
		mid + Vector3(0.0, raise_y, 0.0), size,
		site_r, border_w, jagged, 0.0, border_a, noise_scale, mask_tex, grid
	)
	parent.set_meta("territory_col_tex", col_tex)
	parent.set_meta("territory_col_img", col_img)
	parent.set_meta("territory_pos_tex", pos_tex)
	parent.set_meta("territory_pos_img", pos_img)
	print(
		"territory closed+influence sites=", nsite,
		" faces=", faces.size(), " nn_avg=", nn_avg, " site_r=", site_r,
		" border_w=", border_w, " raise_y=", raise_y,
		" grid=", grid.get("dims", Vector2i.ZERO), " entries=", grid.get("entries", 0),
		" max_a=", grid.get("max_a", 0), " max_b=", grid.get("max_b", 0), " grid_ms=", grid_ms
	)


static func _sov_fill_color(map: BigmapFromStarfield, ow: int) -> Color:
	if ow == 0:
		## Unowned: gray-white (STARMAP §6); do not use owner_color(0) green placeholder.
		return Color(0.62, 0.62, 0.65, 1.0)
	return map.owner_color(ow)


func build_site_grid(args: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	_built_site_grid = SiteGridScr.build(
		args["sites_pos"], args["nsite"], args["mid"], args["size"],
		args["site_r"], args["border_w"], args["jagged"], args["noise_scale"]
	)
	_built_site_grid["grid_ms"] = Time.get_ticks_msec() - started


func take_site_grid() -> Dictionary:
	var result := _built_site_grid
	_built_site_grid = {}
	return result


func apply_site_grid(parent: Node3D, grid: Dictionary) -> void:
	if parent == null or grid.is_empty():
		return
	for layer_name in ["TerritoryFill", "TerritoryStrokeRaised"]:
		var layer := parent.get_node_or_null(layer_name) as MeshInstance3D
		if layer == null:
			continue
		var sm := layer.material_override as ShaderMaterial
		SiteGridScr.apply_to(sm, grid)
	print(
		"territory async grid=", grid.get("dims", Vector2i.ZERO),
		" entries=", grid.get("entries", 0),
		" max_a=", grid.get("max_a", 0), " max_b=", grid.get("max_b", 0),
		" grid_ms=", grid.get("grid_ms", 0)
	)


static func sync_site_colors(parent: Node3D, map: BigmapFromStarfield) -> int:
	## Push current SOV owners into site_col_tex on both territory layers. Returns updated site count.
	if parent == null or map == null or not parent.has_meta("territory_site_sids"):
		return 0
	var sids: PackedStringArray = parent.get_meta("territory_site_sids")
	var n := sids.size()
	if n <= 0:
		return 0
	var col_img: Image = parent.get_meta("territory_col_img", null)
	var col_tex: ImageTexture = parent.get_meta("territory_col_tex", null)
	var pos_img: Image = parent.get_meta("territory_pos_img", null)
	var pos_tex: ImageTexture = parent.get_meta("territory_pos_tex", null)
	if (
		col_img == null or col_tex == null or col_img.get_width() != n
		or pos_img == null or pos_tex == null or pos_img.get_width() != n
	):
		return 0
	for i in n:
		var ow := map.sov_owner_of(str(sids[i]))
		col_img.set_pixel(i, 0, _sov_fill_color(map, ow))
		var pos := pos_img.get_pixel(i, 0)
		pos.a = float(ow)
		pos_img.set_pixel(i, 0, pos)
	## Both layers share this texture; update() keeps the GPU allocation.
	col_tex.update(col_img)
	pos_tex.update(pos_img)
	return 2


func _link_adj_sorted(map: BigmapFromStarfield) -> Dictionary:
	var adj: Dictionary = {}
	for sid in map.systems.keys():
		var s := str(sid)
		if not adj.has(s):
			adj[s] = []
		for link in map.systems[sid]["links"]:
			var to_id := str(link)
			if to_id == "" or not map.systems.has(to_id):
				continue
			if not (adj[s] as Array).has(to_id):
				(adj[s] as Array).append(to_id)
			if not adj.has(to_id):
				adj[to_id] = []
			if not (adj[to_id] as Array).has(s):
				(adj[to_id] as Array).append(s)
	## Sort neighbors CCW by atan2(dx, dz) around each node.
	for s in adj.keys():
		var c: Vector3 = map.systems[s]["center"]
		var neigh: Array = adj[s]
		neigh.sort_custom(func(a, b):
			var ca: Vector3 = map.systems[str(a)]["center"]
			var cb: Vector3 = map.systems[str(b)]["center"]
			return atan2(ca.x - c.x, ca.z - c.z) < atan2(cb.x - c.x, cb.z - c.z)
		)
		adj[s] = neigh
	return adj


func _find_bounded_link_faces(map: BigmapFromStarfield) -> Array:
	## Planar face walk on star-gate links. Each item: PackedVector2Array polygon (XZ).
	var adj: Dictionary = _link_adj_sorted(map)
	var used: Dictionary = {}
	var faces_nodes: Array = []
	for a0 in adj.keys():
		var a := str(a0)
		for b0 in adj[a]:
			var b := str(b0)
			var dkey := "%s>%s" % [a, b]
			if used.has(dkey):
				continue
			var path: Array = [a]
			var prev := a
			var cur := b
			var ok := true
			var guard := 0
			while cur != a:
				used["%s>%s" % [prev, cur]] = true
				path.append(cur)
				var neigh: Array = adj.get(cur, [])
				if neigh.is_empty():
					ok = false
					break
				var idx := neigh.find(prev)
				if idx < 0:
					ok = false
					break
				## Next CCW neighbor after incoming prev (previous index in CCW-sorted list).
				var nidx := (idx - 1 + neigh.size()) % neigh.size()
				var nxt := str(neigh[nidx])
				prev = cur
				cur = nxt
				guard += 1
				if guard > 96 or path.size() > 96:
					ok = false
					break
			if not ok or path.size() < 3:
				continue
			used["%s>%s" % [prev, cur]] = true
			faces_nodes.append(path)
	## Convert to polygons; drop exterior (largest |area|).
	var polys: Array = []
	var areas: Array = []
	var max_abs := -1.0
	var max_i := -1
	for fi in faces_nodes.size():
		var nodes: Array = faces_nodes[fi]
		var poly := PackedVector2Array()
		poly.resize(nodes.size())
		for i in nodes.size():
			var c: Vector3 = map.systems[str(nodes[i])]["center"]
			poly[i] = Vector2(c.x, c.z)
		var area := _poly_signed_area(poly)
		polys.append(poly)
		areas.append(area)
		if absf(area) > max_abs:
			max_abs = absf(area)
			max_i = fi
	var out: Array = []
	for i in polys.size():
		if i == max_i:
			continue
		if absf(float(areas[i])) < 4.0:
			continue
		out.append(polys[i])
	return out


func _poly_signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % n]
		a += p0.x * p1.y - p1.x * p0.y
	return a * 0.5


func _point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var yi: float = poly[i].y
		var yj: float = poly[j].y
		var xi: float = poly[i].x
		var xj: float = poly[j].x
		if ((yi > p.y) != (yj > p.y)) and (p.x < (xj - xi) * (p.y - yi) / (yj - yi + 1e-20) + xi):
			inside = not inside
		j = i
	return inside


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var lab2 := ab.length_squared()
	if lab2 < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / lab2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _bake_closed_face_mask(
	faces: Array, mid: Vector3, size: Vector2, border_w: float
) -> ImageTexture:
	## Fast path: triangulate fill for R; stamp edge bands for G (void-edge distance).
	var tex_n := 384
	var img := Image.create(tex_n, tex_n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 1, 0, 1))
	if faces.is_empty():
		return ImageTexture.create_from_image(img)
	var origin := Vector2(mid.x - size.x * 0.5, mid.z - size.y * 0.5)
	var sx := size.x / float(tex_n)
	var sz := size.y / float(tex_n)
	var pack := 256.0
	var search_r := maxf(border_w * 4.0, 8.0)
	var edges: Array = []

	for face in faces:
		var poly: PackedVector2Array = face
		var n := poly.size()
		for i in n:
			edges.append([poly[i], poly[(i + 1) % n]])
		var tris: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			## Fallback: point sample bbox.
			var bbmin := Vector2(INF, INF)
			var bbmax := Vector2(-INF, -INF)
			for i in n:
				bbmin = bbmin.min(poly[i])
				bbmax = bbmax.max(poly[i])
			var x0 := clampi(int(floor((bbmin.x - origin.x) / sx)), 0, tex_n - 1)
			var x1 := clampi(int(ceil((bbmax.x - origin.x) / sx)), 0, tex_n - 1)
			var y0 := clampi(int(floor((bbmin.y - origin.y) / sz)), 0, tex_n - 1)
			var y1 := clampi(int(ceil((bbmax.y - origin.y) / sz)), 0, tex_n - 1)
			for py in range(y0, y1 + 1):
				var wz := origin.y + (float(py) + 0.5) * sz
				for px in range(x0, x1 + 1):
					var wx := origin.x + (float(px) + 0.5) * sx
					if _point_in_poly(Vector2(wx, wz), poly):
						var old := img.get_pixel(px, py)
						img.set_pixel(px, py, Color(1.0, old.g, 0.0, 1.0))
			continue
		var ti := 0
		while ti + 2 < tris.size():
			var a: Vector2 = poly[tris[ti]]
			var b: Vector2 = poly[tris[ti + 1]]
			var c: Vector2 = poly[tris[ti + 2]]
			ti += 3
			var bbmin := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
			var bbmax := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
			var x0 := clampi(int(floor((bbmin.x - origin.x) / sx)), 0, tex_n - 1)
			var x1 := clampi(int(ceil((bbmax.x - origin.x) / sx)), 0, tex_n - 1)
			var y0 := clampi(int(floor((bbmin.y - origin.y) / sz)), 0, tex_n - 1)
			var y1 := clampi(int(ceil((bbmax.y - origin.y) / sz)), 0, tex_n - 1)
			for py in range(y0, y1 + 1):
				var wz := origin.y + (float(py) + 0.5) * sz
				for px in range(x0, x1 + 1):
					var wx := origin.x + (float(px) + 0.5) * sx
					if Geometry2D.point_is_inside_triangle(Vector2(wx, wz), a, b, c):
						var old := img.get_pixel(px, py)
						img.set_pixel(px, py, Color(1.0, old.g, 0.0, 1.0))

	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var bbmin := Vector2(minf(a.x, b.x) - search_r, minf(a.y, b.y) - search_r)
		var bbmax := Vector2(maxf(a.x, b.x) + search_r, maxf(a.y, b.y) + search_r)
		var x0 := clampi(int(floor((bbmin.x - origin.x) / sx)), 0, tex_n - 1)
		var x1 := clampi(int(ceil((bbmax.x - origin.x) / sx)), 0, tex_n - 1)
		var y0 := clampi(int(floor((bbmin.y - origin.y) / sz)), 0, tex_n - 1)
		var y1 := clampi(int(ceil((bbmax.y - origin.y) / sz)), 0, tex_n - 1)
		for py in range(y0, y1 + 1):
			var wz := origin.y + (float(py) + 0.5) * sz
			for px in range(x0, x1 + 1):
				var wx := origin.x + (float(px) + 0.5) * sx
				var d := _dist_to_segment(Vector2(wx, wz), a, b)
				if d > search_r:
					continue
				var old := img.get_pixel(px, py)
				var g := minf(old.g, clampf(d / pack, 0.0, 1.0))
				img.set_pixel(px, py, Color(old.r, g, 0.0, 1.0))

	return ImageTexture.create_from_image(img)


func _build_faction_voronoi_segments(
	sites_pos: PackedVector4Array, nsite: int, jagged: float, noise_scale: float
) -> Array:
	## Each item: {pts: PackedVector2Array, fac: float} curved with shader seam/coast noise.
	var out: Array = []
	var pts := PackedVector2Array()
	pts.resize(nsite)
	for i in nsite:
		var sp: Vector4 = sites_pos[i]
		pts[i] = Vector2(sp.x, sp.z)
	for i in nsite:
		var si: Vector4 = sites_pos[i]
		var pi: Vector2 = pts[i]
		for j in range(i + 1, nsite):
			var sj: Vector4 = sites_pos[j]
			if absf(si.w - sj.w) < 0.5:
				continue
			var pj: Vector2 = pts[j]
			var ab := pj - pi
			var lab := ab.length()
			if lab < 0.05 or lab > 900.0:
				continue
			var midp := (pi + pj) * 0.5
			if not _voronoi_edge_point(midp, pi, pj, pts, nsite):
				continue
			var dir := Vector2(-ab.y, ab.x) / lab
			var tmax := lab * 3.0
			var t0 := _bisector_extent(midp, -dir, pi, pj, pts, nsite, tmax)
			var t1 := _bisector_extent(midp, dir, pi, pj, pts, nsite, tmax)
			if t0 + t1 < maxf(0.5, lab * 0.02):
				continue
			var curve := _shader_curve_polyline(midp - dir * t0, midp + dir * t1, jagged, noise_scale)
			if curve.size() < 2:
				continue
			out.append({"pts": curve, "fac": si.w})
	return out


func _shader_curve_polyline(p0: Vector2, p1: Vector2, jagged: float, noise_scale: float) -> PackedVector2Array:
	var ns := maxf(noise_scale, 0.0001)
	var ab := p1 - p0
	var lab := ab.length()
	if lab < 0.001:
		return PackedVector2Array()
	var dir := ab / lab
	var nrm := Vector2(-dir.y, dir.x)
	var warp := jagged * 28.0 / ns
	var steps := clampi(int(ceili(lab / maxf(6.0 / ns, 2.0))), 8, 48)
	var out := PackedVector2Array()
	out.resize(steps + 1)
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := p0.lerp(p1, t)
		var pn := p * ns
		var sn := _curve_seam_noise(pn)
		var sn2 := _curve_seam_noise(pn + Vector2(23.0, -11.0))
		var ang := atan2(p.y, p.x)
		var nedge := _curve_seam_noise(pn * 1.15) * 0.65 + _curve_coast_noise(pn * 1.3, ang + 0.7) * 0.35
		var w := Vector2(sn, sn2) * warp
		var wobble := jagged * (16.0 / ns) * nedge
		out[i] = p + nrm * (nrm.dot(w) + wobble * 0.35) + dir * (dir.dot(w) * 0.35)
	return out


func _curve_coast_noise(p: Vector2, ang: float) -> float:
	return (
		sin(ang * 5.0) * 0.45 + sin(ang * 11.0 + 1.7) * 0.30 + sin(ang * 3.0 - 0.4) * 0.25
		+ sin(ang * 17.0 + 2.1) * 0.15
		+ sin(p.x * 0.08 + p.y * 0.11) * 0.20 + sin(p.x * 0.19 - p.y * 0.07 + 0.9) * 0.15
	)


func _curve_seam_noise(p: Vector2) -> float:
	return (
		sin(p.x * 0.22 + p.y * 0.17) * 0.40
		+ sin(p.x * 0.41 - p.y * 0.29 + 1.1) * 0.30
		+ sin((p.x + p.y) * 0.33 + 2.4) * 0.20
		+ sin(p.x * 0.09 - p.y * 0.48 + 0.6) * 0.25
	)


func _bisector_extent(
	mid: Vector2, dir: Vector2, a: Vector2, b: Vector2, pts: PackedVector2Array, nsite: int, tmax: float
) -> float:
	if _voronoi_edge_point(mid + dir * tmax, a, b, pts, nsite):
		return tmax
	var lo := 0.0
	var hi := tmax
	for _k in 20:
		var mt := (lo + hi) * 0.5
		if _voronoi_edge_point(mid + dir * mt, a, b, pts, nsite):
			lo = mt
		else:
			hi = mt
	return lo


func _voronoi_edge_point(p: Vector2, a: Vector2, b: Vector2, pts: PackedVector2Array, nsite: int) -> bool:
	var d := p.distance_to(a)
	## On the perpendicular bisector d~dist(p,b); reject if a third site is closer.
	for k in nsite:
		var s: Vector2 = pts[k]
		if s.distance_squared_to(a) < 1e-6 or s.distance_squared_to(b) < 1e-6:
			continue
		if p.distance_to(s) < d - 0.02:
			return false
	return true


func _add_border_line_layer(
	parent: Node3D,
	layer_name: String,
	segs: Array,
	sites_col: PackedVector4Array,
	sites_pos: PackedVector4Array,
	line_w: float,
	y: float,
	border_a: float
) -> void:
	if segs.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := line_w * 0.5
	for seg in segs:
		var poly: PackedVector2Array = seg["pts"]
		if poly.size() < 2:
			continue
		var fac := float(seg["fac"])
		var col := Color(0.55, 0.72, 0.95, border_a)
		for i in sites_pos.size():
			if absf(float(sites_pos[i].w) - fac) < 0.5:
				var sc: Vector4 = sites_col[i]
				col = Color(sc.x, sc.y, sc.z, border_a)
				break
		for k in poly.size() - 1:
			var a: Vector2 = poly[k]
			var b: Vector2 = poly[k + 1]
			var ab := b - a
			var lab := ab.length()
			if lab < 0.001:
				continue
			var dir := ab / lab
			var nrm := Vector2(-dir.y, dir.x)
			var a0 := a + nrm * hw
			var a1 := a - nrm * hw
			var b0 := b + nrm * hw
			var b1 := b - nrm * hw
			_border_tri(st, Vector3(a0.x, y, a0.y), Vector3(b0.x, y, b0.y), Vector3(b1.x, y, b1.y), col)
			_border_tri(st, Vector3(a0.x, y, a0.y), Vector3(b1.x, y, b1.y), Vector3(a1.x, y, a1.y), col)
	var mi := MeshInstance3D.new()
	mi.name = layer_name
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _border_tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(p0)
	st.set_color(col)
	st.add_vertex(p1)
	st.set_color(col)
	st.add_vertex(p2)


func _add_vector_layer(
	parent: Node3D,
	layer_name: String,
	pos_tex: Texture2D,
	col_tex: Texture2D,
	nsite: int,
	mid: Vector3,
	size: Vector2,
	cluster_r: float,
	border_w: float,
	jagged: float,
	fill_a: float,
	border_a: float,
	noise_scale: float = 1.0,
	closed_mask: Texture2D = null,
	grid: Dictionary = {}
) -> void:
	var mi := MeshInstance3D.new()
	mi.name = layer_name
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://game/menu_bg/shaders/bigmap_territory_voronoi.gdshader")
	SiteGridScr.apply_to(sm, grid)
	sm.set_shader_parameter("site_pos_tex", pos_tex)
	sm.set_shader_parameter("site_col_tex", col_tex)
	sm.set_shader_parameter("site_count", nsite)
	sm.set_shader_parameter("cluster_center", Vector4(mid.x, 0.0, mid.z, 0.0))
	sm.set_shader_parameter("cluster_r", cluster_r)
	sm.set_shader_parameter("fill_a", fill_a)
	sm.set_shader_parameter("border_a", border_a)
	sm.set_shader_parameter("border_w", border_w)
	sm.set_shader_parameter("jagged", jagged)
	sm.set_shader_parameter("edge_base", 0.92)
	sm.set_shader_parameter("quad_half", Vector2(size.x * 0.5, size.y * 0.5))
	sm.set_shader_parameter("noise_scale", noise_scale)
	if closed_mask != null:
		sm.set_shader_parameter("closed_mask_tex", closed_mask)
		sm.set_shader_parameter("use_closed_mask", 1)
	else:
		sm.set_shader_parameter("use_closed_mask", 0)
	mi.material_override = sm
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.position = mid
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
