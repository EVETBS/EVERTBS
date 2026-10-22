extends Control
## Top-right custom-campaign starmap sketch (systems + links).

var _layout: Dictionary = {}
var _birth: Dictionary = {}  ## faction -> system id

const COL_STATION := Color(0.45, 0.75, 1.0, 0.95)
const COL_RESOURCE := Color(0.95, 0.78, 0.35, 0.95)
const COL_NORMAL := Color(0.7, 0.75, 0.82, 0.85)
const COL_BIRTH := Color(0.35, 1.0, 0.55, 1.0)
const COL_LINK := Color(0.75, 0.85, 1.0, 0.45)
const COL_BG := Color(0.08, 0.1, 0.14, 0.5)
const COL_BORDER := Color(0.7, 0.75, 0.82, 0.55)
## Same sector icons as the in-match starmap (STARMAP §4 / UI_AND_SHELL §0.2).
const STATION_TEX := "res://assets/ui/sector/station.png"
const GEAR_TEX := "res://assets/ui/sector/gear.png"
const RESOURCE_TEX := "res://assets/ui/sector/resource.png"
const ICON_PX := 22.0

var _tex_cache: Dictionary = {}


func set_layout(layout: Dictionary, birth_picks: Dictionary = {}) -> void:
	_layout = layout if layout != null else {}
	_birth = birth_picks if birth_picks != null else {}
	queue_redraw()


func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[path] = t
	return t


func _draw_icon(center: Vector2, kind: String, col: Color) -> void:
	var t: Texture2D = null
	if kind == "station_system":
		t = _tex(STATION_TEX)
	elif kind == "resource_system":
		t = _tex(GEAR_TEX)
		if t == null:
			t = _tex(RESOURCE_TEX)
	if t == null:
		draw_circle(center, 4.0 if kind == "normal" else 6.0, col)
		return
	var sz := Vector2(ICON_PX, ICON_PX)
	draw_texture_rect(t, Rect2(center - sz * 0.5, sz), false, col)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, COL_BG, true)
	draw_rect(r, COL_BORDER, false, 1.0)
	var systems: Array = _layout.get("systems", [])
	if systems.is_empty():
		var tip := "星图预览"
		draw_string(ThemeDB.fallback_font, Vector2(12, 28), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.7))
		return
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	var pts: Dictionary = {}
	for s in systems:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var pos: Array = s.get("pos", [0.0, 0.0])
		var p := Vector2(float(pos[0]), float(pos[1] if pos.size() > 1 else 0.0))
		pts[str(s.get("id", ""))] = {"p": p, "kind": str(s.get("kind", "normal")), "name": str(s.get("name", s.get("id", ""))), "links": s.get("links", [])}
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	var pad := 28.0
	var span := max_p - min_p
	if span.x < 1.0:
		span.x = 1.0
	if span.y < 1.0:
		span.y = 1.0
	var inner := r.grow(-pad)
	var scale := minf(inner.size.x / span.x, inner.size.y / span.y)
	var origin := inner.position + (inner.size - span * scale) * 0.5
	var screen: Dictionary = {}
	for id in pts.keys():
		var raw: Vector2 = pts[id]["p"]
		screen[id] = origin + Vector2((raw.x - min_p.x) * scale, (raw.y - min_p.y) * scale)
	var drawn_e: Dictionary = {}
	for id in pts.keys():
		var a: Vector2 = screen[id]
		for lid in pts[id]["links"]:
			var bid := str(lid)
			if not screen.has(bid):
				continue
			var key := "%s|%s" % [id, bid] if id < bid else "%s|%s" % [bid, id]
			if drawn_e.has(key):
				continue
			drawn_e[key] = true
			draw_line(a, screen[bid], COL_LINK, 1.5, true)
	var birth_ids: Dictionary = {}
	for k in _birth.keys():
		birth_ids[str(_birth[k])] = true
	for id in pts.keys():
		var kind: String = pts[id]["kind"]
		var col := COL_NORMAL
		if kind == "station_system":
			col = COL_STATION
		elif kind == "resource_system":
			col = COL_RESOURCE
		if birth_ids.has(id):
			draw_arc(screen[id], ICON_PX * 0.75, 0.0, TAU, 32, COL_BIRTH, 2.0, true)
		_draw_icon(screen[id], kind, col)
	draw_string(ThemeDB.fallback_font, Vector2(12, 22), "星图预览", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))
	var legend := "站=站标  资=齿轮  普=灰点  出生=绿圈"
	draw_string(ThemeDB.fallback_font, Vector2(12, size.y - 10), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.65))
