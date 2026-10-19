extends RefCounted
## Conservative per-cell site candidate lists for bigmap_territory_voronoi.gdshader.
## Bounds mirror the shader's three nearest-site loops, so results stay pixel-identical:
##   A list (loop on p):  sites within the max influence reach of the cell.
##   B list (loops on warped pw): sites that can be nearest, or nearest other-faction
##   site close enough to draw a junction stroke.

const LIST_TEX_W := 2048
const TARGET_CELL := 40.0
const MAX_DIM := 192
const EPS := 0.5
## Sum of |coefficients| in coast_noise / seam_noise.
const COAST_ABS_MAX := 1.5
const SEAM_ABS_MAX := 1.15


static func build(
	sites_pos: PackedVector4Array,
	nsite: int,
	mid: Vector3,
	size: Vector2,
	cluster_r: float,
	border_w: float,
	jagged: float,
	noise_scale: float,
	edge_base: float = 0.92
) -> Dictionary:
	if nsite <= 0:
		return {}
	var ns := maxf(noise_scale, 0.0001)
	var reach_max := cluster_r * maxf(0.82, edge_base + jagged * 0.18 * COAST_ABS_MAX)
	var warp_max := jagged * 28.0 / ns * SEAM_ABS_MAX * sqrt(2.0)
	var half_w := border_w * 0.5
	var aa := maxf(border_w * 0.08, 0.05)
	var stroke_extra := 2.0 * (half_w + aa)

	var gx := clampi(int(ceil(size.x / TARGET_CELL)), 1, MAX_DIM)
	var gy := clampi(int(ceil(size.y / TARGET_CELL)), 1, MAX_DIM)
	var cell := maxf(size.x / float(gx), size.y / float(gy))
	var origin := Vector2(mid.x - size.x * 0.5, mid.z - size.y * 0.5)

	var sx := PackedFloat32Array()
	var sz := PackedFloat32Array()
	sx.resize(nsite)
	sz.resize(nsite)
	for i in nsite:
		sx[i] = sites_pos[i].x
		sz[i] = sites_pos[i].z

	var bs := maxf(cell * 2.0, 32.0)
	var buckets: Dictionary = {}
	for i in nsite:
		var key := Vector2i(int(floor((sx[i] - origin.x) / bs)), int(floor((sz[i] - origin.y) / bs)))
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		(buckets[key] as PackedInt32Array).append(i)
	var bmax := Vector2i(int(ceil(size.x / bs)) + 1, int(ceil(size.y / bs)) + 1)

	var cell_img := Image.create(gx, gy, false, Image.FORMAT_RGBAF)
	var flat := PackedInt32Array()
	var max_a := 0
	var max_b := 0
	for cy in gy:
		for cx in gx:
			var c0 := origin + Vector2(float(cx), float(cy)) * cell - Vector2(EPS, EPS)
			var c1 := origin + Vector2(float(cx + 1), float(cy + 1)) * cell + Vector2(EPS, EPS)
			var a_list := _gather(buckets, bs, origin, sx, sz, c0, c1, reach_max + EPS)
			var w0 := c0 - Vector2(warp_max, warp_max)
			var w1 := c1 + Vector2(warp_max, warp_max)
			var near_i := _nearest(buckets, bs, origin, bmax, sx, sz, (w0 + w1) * 0.5)
			var m_hat := _max_dist(sx[near_i], sz[near_i], w0, w1)
			var b_list := _gather(buckets, bs, origin, sx, sz, w0, w1, m_hat + stroke_extra + EPS)
			var a_off := flat.size()
			flat.append_array(a_list)
			var b_off := flat.size()
			flat.append_array(b_list)
			max_a = maxi(max_a, a_list.size())
			max_b = maxi(max_b, b_list.size())
			cell_img.set_pixel(cx, cy, Color(float(a_off), float(a_list.size()), float(b_off), float(b_list.size())))

	var total := maxi(flat.size(), 1)
	var lh := int(ceil(float(total) / float(LIST_TEX_W)))
	var list_img := Image.create(LIST_TEX_W, maxi(lh, 1), false, Image.FORMAT_RF)
	for k in flat.size():
		list_img.set_pixel(k % LIST_TEX_W, k / LIST_TEX_W, Color(float(flat[k]), 0.0, 0.0, 1.0))
	return {
		"cell_img": cell_img,
		"list_img": list_img,
		"origin": origin,
		"cell": cell,
		"dims": Vector2i(gx, gy),
		"entries": flat.size(),
		"max_a": max_a,
		"max_b": max_b,
	}


static func apply_to(sm: ShaderMaterial, grid: Dictionary) -> void:
	if sm == null or grid.is_empty():
		return
	if not grid.has("cell_tex"):
		grid["cell_tex"] = ImageTexture.create_from_image(grid["cell_img"])
		grid["list_tex"] = ImageTexture.create_from_image(grid["list_img"])
	sm.set_shader_parameter("grid_cell_tex", grid["cell_tex"])
	sm.set_shader_parameter("grid_list_tex", grid["list_tex"])
	sm.set_shader_parameter("grid_origin", grid["origin"])
	sm.set_shader_parameter("grid_cell", grid["cell"])
	sm.set_shader_parameter("grid_dims", grid["dims"])
	sm.set_shader_parameter("grid_list_w", LIST_TEX_W)
	sm.set_shader_parameter("use_grid", 1)


static func _box_dist(px: float, pz: float, b0: Vector2, b1: Vector2) -> float:
	var dx := maxf(maxf(b0.x - px, 0.0), px - b1.x)
	var dz := maxf(maxf(b0.y - pz, 0.0), pz - b1.y)
	return sqrt(dx * dx + dz * dz)


static func _max_dist(px: float, pz: float, b0: Vector2, b1: Vector2) -> float:
	var dx := maxf(absf(px - b0.x), absf(px - b1.x))
	var dz := maxf(absf(pz - b0.y), absf(pz - b1.y))
	return sqrt(dx * dx + dz * dz)


static func _gather(
	_buckets: Dictionary, _bs: float, _origin: Vector2,
	sx: PackedFloat32Array, sz: PackedFloat32Array,
	b0: Vector2, b1: Vector2, radius: float
) -> PackedInt32Array:
	var out := PackedInt32Array()
	## nsite is capped at 512. Direct scanning avoids traversing huge empty
	## bucket rectangles when a conservative radius approaches the map span.
	for i in sx.size():
		if _box_dist(sx[i], sz[i], b0, b1) <= radius:
			out.append(i)
	return out


static func _nearest(
	_buckets: Dictionary, _bs: float, _origin: Vector2, _bmax: Vector2i,
	sx: PackedFloat32Array, sz: PackedFloat32Array, p: Vector2
) -> int:
	var best_i := 0
	var best_d := INF
	for i in sx.size():
		var d := Vector2(sx[i] - p.x, sz[i] - p.y).length_squared()
		if d < best_d:
			best_d = d
			best_i = i
	return best_i