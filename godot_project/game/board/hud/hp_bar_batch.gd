extends Control
class_name BoardHpBarBatch
## Screen-space HP rings aligned to the tonnage icon (old BoardUnitOverhead geometry).

const STEP_S := 0.05
const STEP_A := 0.04
const STEP_H := 0.02
const STEP_C := 0.04
const HIDE_S := 2.0
const BADGE_WU := 0.58
const OVERLAY_BG_WU := BADGE_WU * 1.5
const RING_DIAMETER_SCALE := 1.5
const RING_BAND_SCALE := 0.75
const RING_INNER := OVERLAY_BG_WU * 0.78 * RING_DIAMETER_SCALE
const RING_OUTER := RING_INNER + OVERLAY_BG_WU * (1.42 - 0.78) * RING_DIAMETER_SCALE * RING_BAND_SCALE
const RING_HP_GAP_FRAC := 0.16
const RING_SEAM := 0.06981317
const HP_A0 := -0.785398
const HP_A1 := 2.356194 - RING_SEAM * 0.5
const CAP_A0 := 2.356194 + RING_SEAM * 0.5
const CAP_A1 := 3.926991
const ENEMY_HP_A0 := 0.785398 + RING_SEAM * 0.5
const ENEMY_HP_A1 := 3.926991
const ENEMY_CAP_A0 := -0.785398 + RING_SEAM * 0.5
const ENEMY_CAP_A1 := 0.785398 - RING_SEAM * 0.5
const COL_S := Color(0.25, 0.55, 1.0, 0.95)
const COL_A := Color(0.95, 0.82, 0.2, 0.95)
const COL_H := Color(0.9, 0.22, 0.2, 0.95)
const COL_CAP := Color(0.2, 0.9, 0.85, 0.25)
const COL_BLACK := Color(0.02, 0.02, 0.03, 0.92)

var _rows: Array = []


static func quantize(v: float, mx: float, step: float) -> float:
	if mx <= 0.001:
		return 0.0
	var r := clampf(v / mx, 0.0, 1.0)
	return floorf(r / step) * step


func sync_units(cam: Camera3D, units: Array, selection: Array, always_full: bool, wall_dt: float, starmap: bool, unit_nodes: Dictionary = {}, hostiles: Dictionary = {}) -> void:
	_rows.clear()
	if starmap or cam == null:
		queue_redraw()
		return
	var sel: Dictionary = {}
	for s in selection:
		sel[str(s)] = true
	for u in units:
		if typeof(u) != TYPE_DICTIONARY or not bool(u.get("alive", false)):
			continue
		var uid := str(u.get("id", ""))
		var inst: Dictionary = u.get("inst", {})
		if inst.is_empty():
			continue
		var qs := quantize(float(inst.get("shield", 0)), float(inst.get("max_s", 1)), STEP_S)
		var qa := quantize(float(inst.get("armor", 0)), float(inst.get("max_a", 1)), STEP_A)
		var qh := quantize(float(inst.get("structure", 0)), float(inst.get("max_h", 1)), STEP_H)
		var qc := quantize(float(inst.get("cap", 0)), float(inst.get("max_cap", 1)), STEP_C)
		var stamp := "%s|%s|%s|%s" % [qs, qa, qh, qc]
		var prev := str(u.get("_hp_q", ""))
		if prev == "":
			u["_hp_q"] = stamp
			u["_hp_change_t"] = 99.0
		elif stamp != prev:
			u["_hp_q"] = stamp
			u["_hp_change_t"] = 0.0
		else:
			u["_hp_change_t"] = float(u.get("_hp_change_t", 99.0)) + wall_dt
		var selected := sel.has(uid)
		var show := always_full or selected or float(u.get("_hp_change_t", 99.0)) < HIDE_S
		if not show:
			continue
		var n: Node3D = unit_nodes.get(uid) as Node3D
		if n == null:
			continue
		var oh := n.get_node_or_null("Overhead") as Node3D
		if oh == null or not oh.visible:
			continue
		var ts := oh.get("ton_spr") as Node3D
		var center_w: Vector3 = ts.global_position if ts != null else oh.global_position
		if cam.is_position_behind(center_w):
			continue
		var sp := cam.unproject_position(center_w)
		if sp.x < -80.0 or sp.y < -80.0 or sp.x > size.x + 80.0 or sp.y > size.y + 80.0:
			continue
		var half_icon := BADGE_WU * 0.5
		if ts != null:
			var tex = ts.get("texture")
			var ps := float(ts.get("pixel_size"))
			if tex != null and ps > 0.0:
				var longest := float(maxi(int(tex.get_width()), int(tex.get_height())))
				if longest > 0.0:
					half_icon = longest * ps * 0.5
		var space: Node3D = ts if ts != null else oh
		var icon_edge: Vector3 = space.to_global(Vector3(half_icon, 0.0, 0.0))
		var icon_px := sp.distance_to(cam.unproject_position(icon_edge))
		if icon_px < 1.0:
			continue
		var px_wu := icon_px / maxf(half_icon, 0.001)
		var max_s := float(inst.get("max_s", 1))
		var max_a := float(inst.get("max_a", 1))
		var max_h := float(inst.get("max_h", 1))
		var pris_s := float(inst.get("pristine_s", max_s))
		var pris_a := float(inst.get("pristine_a", max_a))
		var pris_h := float(inst.get("pristine_h", max_h))
		_rows.append({
			"p": sp,
			"px": px_wu,
			"s": qs,
			"a": qa,
			"h": qh,
			"c": qc,
			"bs": clampf(1.0 - max_s / maxf(pris_s, 0.001), 0.0, 1.0),
			"ba": clampf(1.0 - max_a / maxf(pris_a, 0.001), 0.0, 1.0),
			"bh": clampf(1.0 - max_h / maxf(pris_h, 0.001), 0.0, 1.0),
			"enemy": hostiles.has(uid),
		})
	queue_redraw()


func _draw() -> void:
	for row in _rows:
		var c: Vector2 = row["p"]
		var px: float = float(row["px"])
		var enemy: bool = bool(row["enemy"])
		var span := RING_OUTER - RING_INNER
		var band := span / (3.0 + RING_HP_GAP_FRAC * 2.0)
		var gap := band * RING_HP_GAP_FRAC
		var fills := [float(row["s"]), float(row["a"]), float(row["h"])]
		var blacks := [float(row["bs"]), float(row["ba"]), float(row["bh"])]
		var cols := [COL_S, COL_A, COL_H]
		var a0 := ENEMY_HP_A0 if enemy else HP_A0
		var a1 := ENEMY_HP_A1 if enemy else HP_A1
		for i in 3:
			var r0 := (RING_INNER + float(i) * (band + gap)) * px
			var r1 := r0 + band * px
			_hp_band(c, r0, r1, a0, a1, fills[i], blacks[i], cols[i])
		var ca0 := ENEMY_CAP_A0 if enemy else CAP_A0
		var ca1 := ENEMY_CAP_A1 if enemy else CAP_A1
		_cap_band(c, RING_INNER * px, RING_OUTER * px, ca0, ca1, float(row["c"]), COL_CAP)


func _hp_band(c: Vector2, r0: float, r1: float, a0: float, a1: float, fill: float, black: float, col: Color) -> void:
	if r1 - r0 < 0.8:
		return
	var mid := (r0 + r1) * 0.5
	var w := maxf(r1 - r0, 1.2)
	var a0_eff := a0
	var bf := clampf(black, 0.0, 1.0)
	if bf > 0.001:
		var black_a1 := lerpf(a0, a1, bf)
		_stroke(c, mid, a0, black_a1, COL_BLACK, w, 16)
		a0_eff = black_a1
	var fr := clampf(fill, 0.0, 1.0)
	if fr <= 0.001:
		return
	var fa0 := lerpf(a1, a0_eff, fr)
	_stroke(c, mid, fa0, a1, col, w, 20)


func _cap_band(c: Vector2, r0: float, r1: float, a0: float, a1: float, fill: float, col: Color) -> void:
	if r1 - r0 < 0.8:
		return
	var fr := clampf(fill, 0.0, 1.0)
	if fr <= 0.001:
		return
	var mid := (r0 + r1) * 0.5
	var w := maxf(r1 - r0, 1.2)
	var tip := lerpf(a0, a1, fr)
	_stroke(c, mid, a0, tip, col, w, 12)


func _stroke(c: Vector2, mid: float, a0: float, a1: float, col: Color, w: float, segs: int) -> void:
	## 3D rings live in Overhead XY: (cos a, sin a). Facing camera, canvas Y is down so angles negate.
	draw_arc(c, mid, -a0, -a1, segs, col, w, true)
