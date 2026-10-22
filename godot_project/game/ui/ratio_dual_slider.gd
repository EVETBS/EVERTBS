extends Control
class_name RatioDualSlider
## One track, two thumbs. Left = station systems, middle = resource, right = normal.

signal ratio_changed(station_pct: float, resource_pct: float)
signal drag_finished(station_pct: float, resource_pct: float)

var station_pct := 35.0
var resource_pct := 25.0
var dragging := false
var _which := 0


func _ready() -> void:
	custom_minimum_size = Vector2(280, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_ratio(station: float, resource: float) -> void:
	station_pct = clampf(station, 0.0, 100.0)
	resource_pct = clampf(resource, 0.0, 100.0 - station_pct)
	queue_redraw()


func _notification(what: int) -> void:
	if not dragging:
		return
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		dragging = false
		_which = 0
		drag_finished.emit(station_pct, resource_pct)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_which = _nearest(mb.position.x)
			dragging = true
			_move_to(mb.position.x)
		else:
			dragging = false
			_which = 0
			drag_finished.emit(station_pct, resource_pct)
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		_move_to((event as InputEventMouseMotion).position.x)
		accept_event()


func _nearest(x: float) -> int:
	var a := _x_of(station_pct)
	var b := _x_of(station_pct + resource_pct)
	return 1 if absf(x - a) <= absf(x - b) else 2


func _move_to(x: float) -> void:
	var pct := clampf(x / maxf(size.x, 1.0) * 100.0, 0.0, 100.0)
	var end := station_pct + resource_pct
	if _which == 1:
		station_pct = clampf(pct, 0.0, end)
		resource_pct = end - station_pct
	else:
		end = clampf(pct, station_pct, 100.0)
		resource_pct = end - station_pct
	queue_redraw()
	ratio_changed.emit(station_pct, resource_pct)


func _x_of(pct: float) -> float:
	return clampf(pct, 0.0, 100.0) / 100.0 * size.x


func _draw() -> void:
	var normal := 100.0 - station_pct - resource_pct
	draw_string(ThemeDB.fallback_font, Vector2(0, 16), "空间站 %.0f%%   资源 %.0f%%   普通 %.0f%%" % [station_pct, resource_pct, normal], HORIZONTAL_ALIGNMENT_LEFT, size.x, 14, Color(0.9, 0.92, 0.94))
	var y := 40.0
	var x1 := _x_of(station_pct)
	var x2 := _x_of(station_pct + resource_pct)
	draw_line(Vector2(0, y), Vector2(x1, y), Color(0.45, 0.72, 0.95), 8.0)
	draw_line(Vector2(x1, y), Vector2(x2, y), Color(0.95, 0.72, 0.35), 8.0)
	draw_line(Vector2(x2, y), Vector2(size.x, y), Color(0.55, 0.58, 0.62), 8.0)
	draw_circle(Vector2(x1, y), 9.0, Color(0.85, 0.9, 0.95))
	draw_circle(Vector2(x2, y), 9.0, Color(0.95, 0.9, 0.75))
