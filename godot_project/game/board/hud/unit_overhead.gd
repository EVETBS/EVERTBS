extends Node3D
class_name BoardUnitOverhead

## EveAC-aligned annulus HP: trail lag, heal green, black=non-regen only, enemy mirror, tonnage overlays.

const REF_DIST := 48.0
const BADGE_WU := 0.36
const OVERLAY_BG_WU := BADGE_WU * 1.5
const OVERLAY_TAG_WU := BADGE_WU * 0.46 * (2.0 / 3.0)
const OVERLAY_TAG_OFF := BADGE_WU * 0.5
const TON_PIXEL := 0.024
const RING_DIAMETER_SCALE := 1.5
const RING_BAND_SCALE := 0.75
const RING_INNER := OVERLAY_BG_WU * 0.78 * RING_DIAMETER_SCALE
const RING_OUTER := RING_INNER + OVERLAY_BG_WU * (1.42 - 0.78) * RING_DIAMETER_SCALE * RING_BAND_SCALE
const RING_HP_GAP_FRAC := 0.16
const RING_SEAM := deg_to_rad(4.0)
const HP_A0 := deg_to_rad(-45.0)
const HP_A1 := deg_to_rad(135.0) - RING_SEAM * 0.5
const CAP_A0 := deg_to_rad(135.0) + RING_SEAM * 0.5
const CAP_A1 := deg_to_rad(225.0)
const ENEMY_HP_A0 := deg_to_rad(45.0) + RING_SEAM * 0.5
const ENEMY_HP_A1 := deg_to_rad(225.0)
const ENEMY_CAP_A0 := deg_to_rad(-45.0) + RING_SEAM * 0.5
const ENEMY_CAP_A1 := deg_to_rad(45.0) - RING_SEAM * 0.5
const SEGS_HP := 28
const SEGS_CAP := 16

const COL_S := Color(0.25, 0.55, 1.0, 0.95)
const COL_A := Color(0.95, 0.82, 0.2, 0.95)
const COL_H := Color(0.9, 0.22, 0.2, 0.95)
const COL_CAP := Color(0.2, 0.9, 0.85, 0.25)
const COL_BLACK := Color(0.02, 0.02, 0.03, 0.92)
const COL_TRAIL := Color(0.35, 0.05, 0.06, 0.85)
const COL_GREEN := Color(0.15, 0.95, 0.45, 1.0)
const TRAIL_HOLD_S := 0.5
const TRAIL_RATIO_PER_S := 0.5
const GREEN_HOLD_S := 0.5
const GREEN_FADE_S := 1.0

var name_lab: Label3D
var ton_spr: Sprite3D
var overlay_bg: Sprite3D
var overlay_tag: Sprite3D
var _fills: Array = []
var _blacks: Array = []
var _trails: Array = []
var _sector_a0: PackedFloat32Array = PackedFloat32Array()
var _sector_a1: PackedFloat32Array = PackedFloat32Array()
var _sector_r0: PackedFloat32Array = PackedFloat32Array()
var _sector_r1: PackedFloat32Array = PackedFloat32Array()
var _fill_ratio: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
var _trail_ratio: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
var _trail_hold: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
var _black_frac: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
var _prev_cur: PackedFloat32Array = PackedFloat32Array([-1, -1, -1, -1])
var _prev_max: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
var _green_batches: Array = [[], [], [], []]
var _layer_inited := false
var _enemy_mirrored := false
var _alive_view := true
var _cam: Camera3D
var _title_col := Color(0.95, 0.95, 1.0, 1.0)

func _ready() -> void:
	name_lab = Label3D.new()
	name_lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	name_lab.font_size = 96
	# Contrast 1px edge (outermost stroke), not a thick halo
	name_lab.outline_size = 2
	name_lab.outline_modulate = Color(0.05, 0.05, 0.08, 1.0)
	name_lab.modulate = _title_col
	name_lab.position = Vector3(0, -1.55, 0.02)
	name_lab.rotation_degrees = Vector3(0, 180, 0)
	name_lab.no_depth_test = true
	name_lab.render_priority = 25
	add_child(name_lab)

	overlay_bg = Sprite3D.new()
	overlay_bg.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	overlay_bg.pixel_size = OVERLAY_BG_WU / 64.0
	overlay_bg.position = Vector3(0, 0.35, 0.03)
	overlay_bg.rotation_degrees = Vector3(0, 180, 0)
	overlay_bg.no_depth_test = true
	overlay_bg.render_priority = 22
	overlay_bg.centered = true
	overlay_bg.transparent = true
	add_child(overlay_bg)

	ton_spr = Sprite3D.new()
	ton_spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ton_spr.pixel_size = TON_PIXEL
	ton_spr.position = Vector3(0, 0.35, 0.05)
	ton_spr.rotation_degrees = Vector3(0, 180, 0)
	ton_spr.no_depth_test = true
	ton_spr.render_priority = 24
	ton_spr.centered = true
	ton_spr.transparent = true
	add_child(ton_spr)

	overlay_tag = Sprite3D.new()
	overlay_tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	overlay_tag.pixel_size = OVERLAY_TAG_WU / 32.0
	overlay_tag.position = Vector3(OVERLAY_TAG_OFF, 0.35 + OVERLAY_TAG_OFF, 0.06)
	overlay_tag.rotation_degrees = Vector3(0, 180, 0)
	overlay_tag.no_depth_test = true
	overlay_tag.render_priority = 26
	overlay_tag.centered = true
	overlay_tag.transparent = true
	add_child(overlay_tag)

	_rebuild_sectors(false)
	for i in 4:
		_blacks.append(_mk_ring_mi(COL_BLACK, 9))
		_trails.append(_mk_ring_mi(COL_TRAIL, 10))
		var col = COL_S if i == 0 else (COL_A if i == 1 else (COL_H if i == 2 else COL_CAP))
		_fills.append(_mk_ring_mi(col, 12))

func _rebuild_sectors(enemy: bool) -> void:
	_enemy_mirrored = enemy
	_sector_a0 = PackedFloat32Array()
	_sector_a1 = PackedFloat32Array()
	_sector_r0 = PackedFloat32Array()
	_sector_r1 = PackedFloat32Array()
	var span = RING_OUTER - RING_INNER
	var band = span / (3.0 + RING_HP_GAP_FRAC * 2.0)
	var gap = band * RING_HP_GAP_FRAC
	for i in 3:
		var r0 = RING_INNER + float(i) * (band + gap)
		_sector_r0.append(r0)
		_sector_r1.append(r0 + band)
		if enemy:
			_sector_a0.append(ENEMY_HP_A0)
			_sector_a1.append(ENEMY_HP_A1)
		else:
			_sector_a0.append(HP_A0)
			_sector_a1.append(HP_A1)
	# cap shares outer stack thickness
	_sector_r0.append(RING_INNER)
	_sector_r1.append(RING_OUTER)
	if enemy:
		_sector_a0.append(ENEMY_CAP_A0)
		_sector_a1.append(ENEMY_CAP_A1)
	else:
		_sector_a0.append(CAP_A0)
		_sector_a1.append(CAP_A1)

func _mk_ring_mi(col: Color, prio: int) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = _annulus(1.0, 1.01, 0.0, 0.01, 4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = prio
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	return mi

func _annulus(r0: float, r1: float, a0: float, a1: float, segs: int) -> ArrayMesh:
	if a1 <= a0:
		a1 = a0 + 0.0001
	var n = maxi(segs, 2)
	var verts = PackedVector3Array()
	var norms = PackedVector3Array()
	var indices = PackedInt32Array()
	for i in range(n + 1):
		var t = float(i) / float(n)
		var a = lerpf(a0, a1, t)
		var ca = cos(a)
		var sa = sin(a)
		verts.append(Vector3(r0 * ca, r0 * sa, 0.0))
		verts.append(Vector3(r1 * ca, r1 * sa, 0.0))
		norms.append(Vector3(0, 0, 1))
		norms.append(Vector3(0, 0, 1))
	for i in range(n):
		var b = i * 2
		indices.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func set_tonnage_icon(tex: Texture2D) -> void:
	ton_spr.texture = tex
	ton_spr.visible = tex != null
	ton_spr.pixel_size = TON_PIXEL

func set_tonnage_overlays(bg: Texture2D, badge: Texture2D) -> void:
	overlay_bg.texture = bg
	overlay_bg.visible = bg != null
	if bg:
		var sz = maxf(float(bg.get_width()), 1.0)
		overlay_bg.pixel_size = OVERLAY_BG_WU / sz
	overlay_tag.texture = badge
	overlay_tag.visible = badge != null
	if badge:
		var sz2 = maxf(float(badge.get_width()), 1.0)
		overlay_tag.pixel_size = OVERLAY_TAG_WU / sz2

func set_faction_badge(_col: Color) -> void:
	# Legacy solid badge unused when overlays present; keep tag tint soft
	if overlay_tag and overlay_tag.texture == null:
		pass
	_title_col = Color(0.95, 0.95, 1.0, 1.0)
	if name_lab:
		name_lab.modulate = _title_col
		# Contrast outline vs fill
		var lum = _title_col.r * 0.3 + _title_col.g * 0.59 + _title_col.b * 0.11
		name_lab.outline_modulate = Color(0.05, 0.05, 0.08, 1.0) if lum > 0.45 else Color(0.95, 0.95, 0.98, 1.0)

func set_enemy_mirror(enemy: bool) -> void:
	if enemy == _enemy_mirrored and _sector_a0.size() == 4:
		return
	_rebuild_sectors(enemy)
	_layer_inited = false

func set_alive_view(on: bool) -> void:
	_alive_view = on
	visible = on

func update_view(title: String, s: float, a: float, h: float, max_s: float, max_a: float, max_h: float, pris_s: float, pris_a: float, pris_h: float, cap: float = -1.0, max_cap: float = 1.0) -> void:
	if not _alive_view:
		visible = false
		return
	visible = true
	if name_lab.text != title:
		name_lab.text = title
	_sync_layer(0, s, max_s, pris_s)
	_sync_layer(1, a, max_a, pris_a)
	_sync_layer(2, h, max_h, pris_h)
	if cap >= 0.0:
		_sync_layer(3, cap, max_cap, max_cap)
	_apply_visuals()
	_layer_inited = true

func _sync_layer(i: int, cur: float, cur_max: float, pristine: float) -> void:
	var pmax = maxf(pristine, 0.001)
	var usable = clampf(cur_max / pmax, 0.0, 1.0)
	# black = permanently lost (beyond current max toward pristine)
	_black_frac[i] = clampf(1.0 - usable, 0.0, 1.0)
	var safe_cur = clampf(cur, 0.0, maxf(cur_max, 0.0))
	var new_r = 0.0 if cur_max <= 0.0 else clampf(safe_cur / maxf(cur_max, 0.001), 0.0, 1.0)
	var old_r = _fill_ratio[i]
	var old_cur = _prev_cur[i]
	if not _layer_inited or old_cur < 0.0:
		_fill_ratio[i] = new_r
		_trail_ratio[i] = new_r
		_trail_hold[i] = 0.0
		_prev_cur[i] = safe_cur
		_prev_max[i] = cur_max
		return
	var dcur = safe_cur - old_cur
	if dcur > maxf(0.5, cur_max * 0.0005) and i < 3:
		_push_green(i, dcur, clampf(dcur / maxf(cur_max, 0.001), 0.0, 1.0))
	elif dcur < -0.05:
		_consume_green(i, -dcur)
	if i < 3:
		if new_r < old_r - 0.0005:
			if _trail_hold[i] <= 0.0 and absf(_trail_ratio[i] - old_r) <= 0.002:
				_trail_hold[i] = TRAIL_HOLD_S
			_trail_ratio[i] = maxf(_trail_ratio[i], old_r)
		elif new_r > old_r + 0.0005:
			_trail_ratio[i] = new_r
			_trail_hold[i] = 0.0
	else:
		_trail_ratio[i] = new_r
		_trail_hold[i] = 0.0
	_fill_ratio[i] = new_r
	_prev_cur[i] = safe_cur
	_prev_max[i] = cur_max

func _push_green(idx: int, amount: float, frac: float) -> void:
	var mi = _mk_ring_mi(COL_GREEN, 14)
	_green_batches[idx].append({"mesh": mi, "amount": amount, "frac": frac, "age": 0.0})

func _consume_green(idx: int, amount: float) -> void:
	var left = amount
	var batches: Array = _green_batches[idx]
	while left > 0.05 and not batches.is_empty():
		var d: Dictionary = batches[0]
		var amt = float(d.get("amount", 0.0))
		if amt <= left + 0.05:
			left -= amt
			var mi = d.get("mesh")
			if mi and is_instance_valid(mi):
				mi.queue_free()
			batches.remove_at(0)
		else:
			d["amount"] = amt - left
			d["frac"] = clampf(float(d["amount"]) / maxf(_prev_max[idx], 0.001), 0.0, 1.0)
			left = 0.0

func _process(delta: float) -> void:
	if not _alive_view:
		return
	var dirty = false
	for i in 3:
		if _trail_hold[i] > 0.0:
			_trail_hold[i] = maxf(0.0, _trail_hold[i] - delta)
			dirty = true
		elif _trail_ratio[i] > _fill_ratio[i] + 0.0005:
			_trail_ratio[i] = maxf(_fill_ratio[i], _trail_ratio[i] - TRAIL_RATIO_PER_S * delta)
			dirty = true
		var batches: Array = _green_batches[i]
		var j = 0
		while j < batches.size():
			var d: Dictionary = batches[j]
			d["age"] = float(d.get("age", 0.0)) + delta
			if float(d["age"]) > GREEN_HOLD_S + GREEN_FADE_S:
				var mi = d.get("mesh")
				if mi and is_instance_valid(mi):
					mi.queue_free()
				batches.remove_at(j)
				dirty = true
			else:
				j += 1
				dirty = true
	if dirty:
		_apply_visuals()

func _hp_fill_angles(a0_eff: float, a1: float, ratio: float) -> Vector2:
	var r: float = clampf(ratio, 0.0, 1.0)
	if r <= 0.001:
		return Vector2(a1, a1)
	return Vector2(lerpf(a1, a0_eff, r), a1)

func _cap_fill_angles(a0: float, a1: float, ratio: float) -> Vector2:
	var tip = lerpf(a0, a1, clampf(ratio, 0.0, 1.0))
	return Vector2(a0, tip)

func _apply_visuals() -> void:
	for i in 4:
		var a0 = _sector_a0[i]
		var a1 = _sector_a1[i]
		var r0 = _sector_r0[i]
		var r1 = _sector_r1[i]
		var segs = SEGS_CAP if i == 3 else SEGS_HP
		var bf = clampf(_black_frac[i], 0.0, 1.0)
		# Non-regen black at the empty end of the arc
		if i < 3 and bf > 0.001:
			var black_a1 = lerpf(a0, a1, bf)
			_blacks[i].visible = true
			_blacks[i].mesh = _annulus(r0, r1, a0, black_a1, segs)
			var a0_eff = black_a1
			var fr = _fill_ratio[i]
			var trail_r = _trail_ratio[i]
			var fill_ang = _hp_fill_angles(a0_eff, a1, fr)
			var trail_ang = _hp_fill_angles(a0_eff, a1, trail_r)
			if trail_r > fr + 0.001:
				_trails[i].visible = true
				_trails[i].mesh = _annulus(r0, r1, trail_ang.x, trail_ang.y, segs)
				(_trails[i].material_override as BaseMaterial3D).albedo_color = COL_TRAIL
			else:
				_trails[i].visible = false
			if fr <= 0.001:
				_fills[i].visible = false
			else:
				_fills[i].visible = true
				_fills[i].mesh = _annulus(r0, r1, fill_ang.x, fill_ang.y, segs)
			_apply_greens(i, a0_eff, a1, fill_ang)
		elif i < 3:
			_blacks[i].visible = false
			var fr2 = _fill_ratio[i]
			var trail_r2 = _trail_ratio[i]
			var fill_ang2 = _hp_fill_angles(a0, a1, fr2)
			var trail_ang2 = _hp_fill_angles(a0, a1, trail_r2)
			if trail_r2 > fr2 + 0.001:
				_trails[i].visible = true
				_trails[i].mesh = _annulus(r0, r1, trail_ang2.x, trail_ang2.y, segs)
			else:
				_trails[i].visible = false
			if fr2 <= 0.001:
				_fills[i].visible = false
			else:
				_fills[i].visible = true
				_fills[i].mesh = _annulus(r0, r1, fill_ang2.x, fill_ang2.y, segs)
			_apply_greens(i, a0, a1, fill_ang2)
		else:
			_blacks[i].visible = false
			_trails[i].visible = false
			var fr3 = _fill_ratio[i]
			var fang = _cap_fill_angles(a0, a1, fr3)
			if fr3 <= 0.001:
				_fills[i].visible = false
			else:
				_fills[i].visible = true
				_fills[i].mesh = _annulus(r0, r1, fang.x, fang.y, segs)

func _apply_greens(idx: int, a0_eff: float, a1: float, fill_ang: Vector2) -> void:
	var batches: Array = _green_batches[idx]
	var r0 = _sector_r0[idx]
	var r1 = _sector_r1[idx]
	var segs = SEGS_HP
	var span = a1 - a0_eff
	var remain = clampf(_fill_ratio[idx], 0.0, 1.0)
	var cursor = fill_ang.x
	for i in range(batches.size() - 1, -1, -1):
		var d: Dictionary = batches[i]
		var mi: MeshInstance3D = d.get("mesh")
		if mi == null or not is_instance_valid(mi):
			continue
		if remain <= 0.0005 or cursor >= fill_ang.y - 0.0005:
			mi.visible = false
			continue
		var frac = minf(float(d.get("frac", 0.0)), remain)
		remain -= frac
		var w = span * frac
		w = minf(w, fill_ang.y - cursor)
		if w <= 0.001:
			mi.visible = false
			continue
		var age = float(d.get("age", 0.0))
		var a = 1.0
		if age > GREEN_HOLD_S:
			a = clampf(1.0 - (age - GREEN_HOLD_S) / GREEN_FADE_S, 0.0, 1.0)
		var col = COL_GREEN
		col.a = a
		(mi.material_override as BaseMaterial3D).albedo_color = col
		mi.visible = true
		mi.mesh = _annulus(r0, r1, cursor, cursor + w, segs)
		cursor += w

func face_camera(cam: Camera3D, world_anchor: Vector3) -> void:
	if cam == null or not _alive_view:
		return
	_cam = cam
	var toward = cam.global_position - world_anchor
	if toward.length_squared() < 0.0001:
		toward = Vector3.FORWARD
	else:
		toward = toward.normalized()
	global_position = world_anchor + Vector3.UP * 3.6 + toward * 0.35
	look_at(cam.global_position, Vector3.UP)
	var dist = cam.global_position.distance_to(global_position)
	var sc = clampf(dist / REF_DIST, 0.7, 2.6)
	scale = Vector3.ONE * sc
