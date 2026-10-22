extends Node3D
class_name BoardUnitOverhead

## EveAC-aligned annulus HP: trail lag, heal green, black=non-regen only, enemy mirror, tonnage overlays.

const REF_DIST := 48.0
## BoardCamera DIST_MAX=220 → need ≥220/48≈4.58 so far zoom keeps screen size (was clamped 2.6).
const SC_MIN := 0.55
const SC_MAX := 5.0
## EveAC ShipHealthBar ratios (UI_ICONS §6.1): icon 0.36, bg×1.5, tag 0.1104, offset icon×0.5.
const BADGE_WU := 0.58
const OVERLAY_BG_WU := BADGE_WU * 1.5
const OVERLAY_TAG_WU := BADGE_WU * 0.46 * (2.0 / 3.0)
const OVERLAY_TAG_OFF := BADGE_WU * 0.5
const TON_PIXEL_FALLBACK := 0.018125 ## BADGE_WU/32; real size from tex width
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
const COL_CD := Color(1.0, 1.0, 1.0, 0.92)
## Screen px for outer attack-ready bar (TACTICAL_TOPDOWN).
static var cd_bar_px: float = 20.0
const CD_PX_WU := 0.005
const CD_GAP := 0.02
const SEGS_CD := 36
const TRAIL_HOLD_S := 0.5
const TRAIL_RATIO_PER_S := 0.5
const GREEN_HOLD_S := 0.5
const GREEN_FADE_S := 1.0
## Name wraps when wider than HP ring diameter * this factor.
const NAME_WRAP_MUL := 1.2
const NAME_FONT_PATH := "res://assets/fonts/simhei.ttf"
## Tactical nameplate only (战场视角 uses face_camera dist scale — never font_scale).
const TACTICAL_SC := 7.7
const TACTICAL_REF_DIST := 560.0
static var font_scale: float = 7.7
## Extra world lift = one nameplate height (local, before node scale).
const NAMEPLATE_LIFT := BADGE_WU * NAME_WRAP_MUL
## Battle-view (orbit) nameplate Y above ship anchor — baked (TACTICAL_TOPDOWN).
static var battle_nameplate_y: float = (3.6 + NAMEPLATE_LIFT) * 2.0
var _compact_icon_only := false
var _show_faction_badge := true

var _wrap_text := ""
var _vis_stamp := ""
var _cd_stamp := ""
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
var _sel_glow: MeshInstance3D
var _sel_highlight := false
var _cd_mi: MeshInstance3D
var _cd_ratio := -1.0
var hp_batched := true
func _ready() -> void:
	name_lab = Label3D.new()
	name_lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	name_lab.font_size = 96
	if ResourceLoader.exists(NAME_FONT_PATH):
		name_lab.font = load(NAME_FONT_PATH) as Font
	# Contrast 1px edge (outermost stroke), not a thick halo
	name_lab.outline_size = 2
	name_lab.outline_modulate = Color(0.05, 0.05, 0.08, 1.0)
	name_lab.modulate = _title_col
	name_lab.position = Vector3(0, -1.55, 0.02)
	name_lab.rotation_degrees = Vector3(0, 180, 0)
	name_lab.no_depth_test = true
	name_lab.render_priority = 25
	name_lab.extra_cull_margin = 80.0
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(name_lab)

	overlay_bg = Sprite3D.new()
	overlay_bg.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	overlay_bg.pixel_size = OVERLAY_BG_WU / 64.0
	overlay_bg.position = Vector3(0, 0, 0.03)
	overlay_bg.rotation_degrees = Vector3(0, 180, 0)
	overlay_bg.no_depth_test = true
	overlay_bg.render_priority = 22
	overlay_bg.centered = true
	overlay_bg.transparent = true
	add_child(overlay_bg)

	ton_spr = Sprite3D.new()
	ton_spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ton_spr.pixel_size = TON_PIXEL_FALLBACK
	ton_spr.position = Vector3(0, 0, 0.05)
	ton_spr.rotation_degrees = Vector3(0, 180, 0)
	ton_spr.no_depth_test = true
	ton_spr.render_priority = 24
	ton_spr.centered = true
	ton_spr.transparent = true
	add_child(ton_spr)

	overlay_tag = Sprite3D.new()
	overlay_tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	overlay_tag.pixel_size = OVERLAY_TAG_WU / 16.0
	## EveAC: (-OFFSET, badge_y - OFFSET). With Y=180 face-camera, -X is viewer-right (was +X = reversed).
	overlay_tag.position = Vector3(-OVERLAY_TAG_OFF, -OVERLAY_TAG_OFF, 0.06)
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
	## Same layer as the HP rings. no_depth_test / a higher priority paints a white stroke over ships.
	_cd_mi = _mk_ring_mi(COL_CD, 8)
	_cd_mi.name = "AtkCd"
	var cd_mat := _cd_mi.material_override as StandardMaterial3D
	cd_mat.no_depth_test = false
	cd_mat.render_priority = 8

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

func _wu_pixel(tex: Texture2D, world: float, fallback: float) -> float:
	if tex == null:
		return fallback
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	if longest < 1.0:
		return fallback
	return world / longest

func set_tonnage_icon(tex: Texture2D) -> void:
	ton_spr.texture = tex
	ton_spr.visible = tex != null
	## EveAC: BADGE_WORLD_SIZE / longest side (32px → 0.01125), not fixed 0.024.
	ton_spr.pixel_size = _wu_pixel(tex, BADGE_WU, TON_PIXEL_FALLBACK)

func set_tonnage_overlays(bg: Texture2D, badge: Texture2D) -> void:
	overlay_bg.texture = bg
	overlay_bg.visible = bg != null
	overlay_bg.pixel_size = _wu_pixel(bg, OVERLAY_BG_WU, OVERLAY_BG_WU / 40.0)
	overlay_tag.texture = badge
	overlay_tag.visible = badge != null
	overlay_tag.pixel_size = _wu_pixel(badge, OVERLAY_TAG_WU, OVERLAY_TAG_WU / 16.0)
	## Match EveAC bottom-right after face-camera yaw (see _ready).
	overlay_tag.position = Vector3(-OVERLAY_TAG_OFF, -OVERLAY_TAG_OFF, 0.06)

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

func set_compact_icon_only(on: bool) -> void:
	if on != _compact_icon_only:
		_vis_stamp = ""
		_cd_stamp = ""
	_compact_icon_only = on
	_apply_compact_visibility()

func set_show_faction_badge(on: bool) -> void:
	_show_faction_badge = on
	_apply_compact_visibility()

func _apply_compact_visibility() -> void:
	if name_lab:
		name_lab.visible = not _compact_icon_only
	if _compact_icon_only:
		for mi in _fills:
			if mi:
				mi.visible = false
		for mi2 in _blacks:
			if mi2:
				mi2.visible = false
		for mi3 in _trails:
			if mi3:
				mi3.visible = false
		for batches in _green_batches:
			for d in batches:
				var gmi: MeshInstance3D = d.get("mesh")
				if gmi:
					gmi.visible = false
		if overlay_bg:
			overlay_bg.visible = overlay_bg.texture != null
		if overlay_tag:
			overlay_tag.visible = _show_faction_badge and overlay_tag.texture != null
		if _cd_mi:
			_cd_mi.visible = false
		if _sel_glow:
			_sel_glow.visible = _sel_highlight
	else:
		if overlay_bg:
			overlay_bg.visible = overlay_bg.texture != null
		if overlay_tag:
			overlay_tag.visible = _show_faction_badge and overlay_tag.texture != null
	if ton_spr:
		ton_spr.visible = ton_spr.texture != null
	if not _compact_icon_only:
		_apply_visuals()
		_apply_cd_visual()

func set_enemy_mirror(enemy: bool) -> void:
	if enemy == _enemy_mirrored and _sector_a0.size() == 4:
		return
	_vis_stamp = ""
	_cd_stamp = ""
	_rebuild_sectors(enemy)
	_layer_inited = false

func set_alive_view(on: bool) -> void:
	_alive_view = on
	visible = on

func _hide_local_hp_rings() -> void:
	for mi in _fills:
		if mi:
			mi.visible = false
	for mi2 in _blacks:
		if mi2:
			mi2.visible = false
	for mi3 in _trails:
		if mi3:
			mi3.visible = false
	if _cd_mi:
		_cd_mi.visible = false


func update_view(title: String, s: float, a: float, h: float, max_s: float, max_a: float, max_h: float, pris_s: float, pris_a: float, pris_h: float, cap: float = -1.0, max_cap: float = 1.0, atk_cd_ratio: float = -1.0) -> void:
	if not _alive_view:
		visible = false
		return
	visible = true
	if name_lab.text != title:
		name_lab.text = title
	_apply_name_wrap()
	if hp_batched:
		_hide_local_hp_rings()
		return
	_sync_layer(0, s, max_s, pris_s)
	_sync_layer(1, a, max_a, pris_a)
	_sync_layer(2, h, max_h, pris_h)
	if cap >= 0.0:
		_sync_layer(3, cap, max_cap, max_cap)
	_cd_ratio = atk_cd_ratio
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
	if _compact_icon_only:
		_apply_compact_visibility()
		return
	## Rebuild annulus meshes only when quantized HP/cap/trail changed (many plates were hitching).
	var stamp := ""
	for i in 4:
		var batches: Array = _green_batches[i]
		var age_q := 0
		if not batches.is_empty():
			age_q = int(float(batches[0].get("age", 0.0)) * 8.0)
		stamp += "%d,%d,%d,%d,%d|" % [
			int(_fill_ratio[i] * 48.0), int(_trail_ratio[i] * 48.0),
			int(_black_frac[i] * 48.0), batches.size(), age_q
		]
	if stamp == _vis_stamp:
		return
	_vis_stamp = stamp
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
	_apply_cd_visual()

func _cd_thick() -> float:
	## Keep ~cd_bar_px on screen despite tactical/battle node scale.
	var sc := maxf(scale.x, 0.001)
	return (clampf(cd_bar_px, 1.0, 32.0) * CD_PX_WU) / sc

func _apply_cd_visual() -> void:
	if _compact_icon_only:
		if _cd_mi:
			_cd_mi.visible = false
		return
	if _cd_mi == null:
		return
	if _cd_ratio < 0.0:
		_cd_mi.visible = false
		_cd_stamp = "off"
		return
	var thick := _cd_thick()
	var cd_key := "%d:%d:%d" % [int(_cd_ratio * 32.0), int(thick * 100.0), 1 if _enemy_mirrored else 0]
	if cd_key == _cd_stamp:
		return
	_cd_stamp = cd_key
	var a0: float
	var a1: float
	if _enemy_mirrored:
		a0 = minf(ENEMY_HP_A0, ENEMY_CAP_A0)
		a1 = maxf(ENEMY_HP_A1, ENEMY_CAP_A1)
	else:
		a0 = HP_A0
		a1 = CAP_A1
	var r0 := RING_OUTER + CD_GAP
	var r1 := r0 + thick
	var fr := clampf(_cd_ratio, 0.0, 1.0)
	if fr <= 0.001:
		_cd_mi.visible = false
		return
	var tip := lerpf(a0, a1, fr)
	_cd_mi.visible = true
	_cd_mi.mesh = _annulus(r0, r1, a0, tip, SEGS_CD)
	(_cd_mi.material_override as BaseMaterial3D).albedo_color = COL_CD

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

func _bar_local_diameter() -> float:
	## Outer HP ring diameter in overhead-local units (Label3D shares this space).
	return RING_OUTER * 2.0

func _apply_name_wrap() -> void:
	if name_lab == null:
		return
	if name_lab.text == _wrap_text:
		return
	_wrap_text = name_lab.text
	#（名字超过铭牌 1.2 倍就换行）26.10.22 13:34 s
	var px: float = maxf(name_lab.pixel_size, 0.0001)
	var limit_px: float = (_bar_local_diameter() * NAME_WRAP_MUL) / px
	var font: Font = name_lab.font
	if font == null:
		font = ThemeDB.fallback_font
	var text_px: float = 0.0
	if font != null and name_lab.text != "":
		text_px = font.get_string_size(
			name_lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_lab.font_size
		).x
	if text_px > limit_px + 0.5 and limit_px > 1.0:
		name_lab.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		name_lab.width = limit_px
	else:
		name_lab.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_lab.width = 0.0
	#（名字超过铭牌 1.2 倍就换行）26.10.22 13:34 e

func set_selected_highlight(on: bool) -> void:
	## Tactical-only yellow halo a=0.05. No ring/line.
	_sel_highlight = on
	if not on:
		if _sel_glow and is_instance_valid(_sel_glow):
			_sel_glow.visible = false
		return
	if _sel_glow == null or not is_instance_valid(_sel_glow):
		_sel_glow = MeshInstance3D.new()
		_sel_glow.name = "SelectGlow"
		var sph := SphereMesh.new()
		sph.radius = OVERLAY_BG_WU * 1.35
		sph.height = sph.radius * 2.0
		_sel_glow.mesh = sph
		var gmat := StandardMaterial3D.new()
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat.albedo_color = Color(1.0, 0.92, 0.35, 0.05)
		gmat.no_depth_test = true
		gmat.disable_receive_shadows = true
		gmat.render_priority = 20
		_sel_glow.material_override = gmat
		_sel_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sel_glow.position = Vector3(0, 0, -0.02)
		add_child(_sel_glow)
	elif _sel_glow.material_override is StandardMaterial3D:
		(_sel_glow.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.92, 0.35, 0.05)
	_sel_glow.visible = true


static func icon_circum_radius_world() -> float:
	## Circumscribed-circle radius of square tonnage icon (TACTICAL_TOPDOWN VFX width).
	var side := BADGE_WU * maxf(font_scale, 0.01)
	return side * 0.5 * sqrt(2.0)

func tactical_name_world_width() -> float:
	return tactical_plate_world_size().x


func tactical_plate_world_size() -> Vector2:
	## Wrapped plate in world units (node scale included). Width stops at 1.2× ring.
	var fs := maxf(font_scale, 0.01)
	var ring := _bar_local_diameter()
	var limit := ring * NAME_WRAP_MUL
	var text_local := 0.0
	var lines := 1
	if not _compact_icon_only and name_lab != null and name_lab.text != "":
		var font: Font = name_lab.font
		if font == null:
			font = ThemeDB.fallback_font
		if font != null:
			var px := font.get_string_size(name_lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_lab.font_size).x
			text_local = px * maxf(name_lab.pixel_size, 0.0001)
			if text_local > limit and limit > 0.01:
				lines = maxi(int(ceili(text_local / limit)), 1)
				text_local = limit
	var local_w := maxf(ring, text_local)
	var line_h := 0.48
	if name_lab != null:
		line_h = float(name_lab.font_size) * maxf(name_lab.pixel_size, 0.0001)
	var name_y := 1.55
	if name_lab != null:
		name_y = absf(name_lab.position.y)
	var local_h := name_y + line_h * (float(lines) * 0.5 + 0.35) + ring * 0.5
	return Vector2(local_w, local_h) * fs


func place_tactical(cam: Camera3D, world_pos: Vector3) -> void:
	## Screen-parallel under nadir (follow cam yaw/roll); fixed world scale.
	if not _alive_view:
		return
	_cam = cam
	global_position = world_pos
	if cam and global_position.distance_squared_to(cam.global_position) > 0.0001:
		var up: Vector3 = cam.global_transform.basis.y
		if up.length_squared() < 0.0001:
			up = Vector3(0.0, 0.0, -1.0)
		look_at(cam.global_position, up)
	scale = Vector3.ONE * font_scale
	_apply_name_wrap()
	_apply_cd_visual()

func face_camera(cam: Camera3D, world_anchor: Vector3) -> void:
	## 战场视角: distance scale only — never inherit tactical font_scale.
	## Clear tactical select glow (highlight is tactical-only).
	set_selected_highlight(false)
	if cam == null or not _alive_view:
		return
	_cam = cam
	var toward = cam.global_position - world_anchor
	if toward.length_squared() < 0.0001:
		toward = Vector3.FORWARD
	else:
		toward = toward.normalized()
	var bind_y: float = battle_nameplate_y
	global_position = world_anchor + Vector3.UP * bind_y + toward * 0.35
	look_at(cam.global_position, Vector3.UP)
	var dist = cam.global_position.distance_to(global_position)
	var sc = clampf(dist / REF_DIST, SC_MIN, SC_MAX)
	scale = Vector3.ONE * sc
	_apply_name_wrap()
	_apply_cd_visual()
