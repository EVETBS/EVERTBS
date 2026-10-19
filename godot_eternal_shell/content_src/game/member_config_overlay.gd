extends Control
## Member roster config overlay (UI_AND_SHELL §0.5 · SHIPS §7.2).
## Four-column grid of ALL members; per member: 场上/场下, 首发, default ship.

signal closed

const MemberTableScr := preload("res://game/board/pilots/member_table.gd")
const RosterTemplatesScr := preload("res://game/board/pilots/roster_templates.gd")

const PANEL_BG := Color(0.08, 0.1, 0.14, 0.15)
const PANEL_BORDER := Color(0.7, 0.75, 0.82, 0.55)
const CELL_BG_OFF := Color(0.08, 0.1, 0.14, 0.18)
const CELL_BG_ON := Color(0.02, 0.03, 0.06, 0.62)
const CELL_BORDER := Color(0.7, 0.75, 0.82, 0.35)
const SIZES := [10, 15, 20, 40, 60]
const COLUMNS := 4

var _size: int = 20
var _onfield: Dictionary = {}  ## id -> true
var _starters: Dictionary = {}  ## id -> true
var _members: Dictionary = {}
var _member_order: PackedStringArray = PackedStringArray()
var _ship_defs: Dictionary = {}
var _grid: GridContainer
var _status: Label


func _ready() -> void:
	_load_data()
	_build()
	_select_size(20)


func _load_data() -> void:
	_members.clear()
	_member_order = PackedStringArray()
	for row in MemberTableScr.load_merged():
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var mid := str(row.get("id", ""))
		_members[mid] = row
		_member_order.append(mid)
	_ship_defs.clear()
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/board/ships.json"))
	if typeof(raw) == TYPE_DICTIONARY:
		for s in raw.get("ships", []):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			if bool(s.get("npc_hull", false)):
				continue
			_ship_defs[str(s.get("id", ""))] = s


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(PANEL_BG, PANEL_BORDER))
	margin.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	var title := Label.new()
	title.text = "配置团员"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	head.add_child(title)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(func() -> void:
		_persist()
		closed.emit()
		queue_free()
	)
	head.add_child(back)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	root.add_child(mode_row)
	mode_row.add_child(_lab("人数模式"))
	for n in SIZES:
		var b := Button.new()
		b.text = str(n)
		b.toggle_mode = true
		b.button_pressed = n == _size
		b.pressed.connect(_select_size.bind(n))
		b.set_meta("size_n", n)
		mode_row.add_child(b)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.85))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)


func _select_size(n: int) -> void:
	_persist()
	_size = n
	var e: Dictionary = RosterTemplatesScr.get_entry(n)
	_onfield.clear()
	_starters.clear()
	for mid in e["onfield"]:
		_onfield[str(mid)] = true
	for sid in e["starters"]:
		_starters[str(sid)] = true
	for c in get_children():
		_refresh_size_toggles(c)
	_rebuild_grid()
	_refresh_status()


func _refresh_size_toggles(node: Node) -> void:
	if node is Button and node.has_meta("size_n"):
		(node as Button).set_pressed_no_signal(int(node.get_meta("size_n")) == _size)
	for c in node.get_children():
		_refresh_size_toggles(c)


func _refresh_status() -> void:
	if _status == null:
		return
	var cap: int = RosterTemplatesScr.starter_cap(_size)
	var on_n := _onfield.size()
	var st_n := 0
	for sid in _starters.keys():
		if _onfield.has(sid):
			st_n += 1
	var parts: PackedStringArray = PackedStringArray()
	parts.append("模版 %d 人：场上 %d / %d" % [_size, on_n, _size])
	if on_n > _size:
		parts.append("（超额，进局时在场上随机抽 %d）" % _size)
	elif on_n < _size:
		parts.append("（不足，进局时场下随机补齐）")
	parts.append("  首发 %d / %d" % [st_n, cap])
	if st_n > cap:
		parts.append("（超额，进局时随机保留 %d）" % cap)
	parts.append("  首发第一艘船 1 秒造完")
	_status.text = "".join(parts)


func _display_order() -> PackedStringArray:
	## 场上且首发，其次场上，其余。同一档保持团员表原序。
	var starters := PackedStringArray()
	var fielded := PackedStringArray()
	var rest := PackedStringArray()
	for mid in _member_order:
		var on := _onfield.has(mid)
		if on and _starters.has(mid):
			starters.append(mid)
		elif on:
			fielded.append(mid)
		else:
			rest.append(mid)
	starters.append_array(fielded)
	starters.append_array(rest)
	return starters

func _rebuild_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var order := _display_order()
	var ids: Array = []
	for mid in order:
		_grid.add_child(_cell(str(mid)))
		ids.append(str(mid))
	DebugSessionLog.append("UI", "member_config_overlay._rebuild_grid", "order", {
		"control": "团员配置",
		"order": ids,
		"runId": "grok-ui",
	})


func _cell(mid: String) -> Control:
	var mem: Dictionary = _members.get(mid, {})
	var on := _onfield.has(mid)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(CELL_BG_ON if on else CELL_BG_OFF, CELL_BORDER, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(40, 40)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture = MemberTableScr.load_portrait(str(mem.get("portrait", "")), PackedStringArray([mid]))
	top.add_child(face)
	var name_lab := Label.new()
	name_lab.text = str(mem.get("name", mid))
	name_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lab.add_theme_color_override("font_color", Color.WHITE)
	top.add_child(name_lab)
	var field_btn := Button.new()
	field_btn.toggle_mode = true
	field_btn.button_pressed = on
	field_btn.text = "场上" if on else "场下"
	field_btn.toggled.connect(func(v: bool) -> void:
		if v:
			_onfield[mid] = true
		else:
			_onfield.erase(mid)
		_persist()
		_rebuild_grid()
		_refresh_status()
	)
	top.add_child(field_btn)
	var st_btn := Button.new()
	st_btn.toggle_mode = true
	var is_st := _starters.has(mid)
	st_btn.button_pressed = is_st
	st_btn.text = "首发" if is_st else "非首发"
	st_btn.disabled = not on
	st_btn.toggled.connect(func(v: bool) -> void:
		if v:
			_starters[mid] = true
		else:
			_starters.erase(mid)
		st_btn.text = "首发" if v else "非首发"
		_persist()
		_rebuild_grid()
		_refresh_status()
	)
	top.add_child(st_btn)
	var ship_row := HBoxContainer.new()
	ship_row.add_theme_constant_override("separation", 6)
	box.add_child(ship_row)
	ship_row.add_child(_lab("默认舰"))
	var ship_ob := OptionButton.new()
	ship_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var unlocked := _unlocked_ships(mem)
	var cur := str(mem.get("default_ship", ""))
	if cur == "" or cur not in unlocked:
		cur = str(unlocked[0]) if not unlocked.is_empty() else "gila_cc2"
	var ssel := 0
	for si in range(unlocked.size()):
		var sid: String = str(unlocked[si])
		var def: Dictionary = _ship_defs.get(sid, {})
		ship_ob.add_item(str(def.get("name", sid)), si)
		ship_ob.set_item_metadata(si, sid)
		if sid == cur:
			ssel = si
	ship_ob.select(ssel)
	ship_ob.item_selected.connect(func(ii: int) -> void:
		_set_default_ship(mid, str(ship_ob.get_item_metadata(ii)))
	)
	ship_row.add_child(ship_ob)
	return panel


func _unlocked_ships(mem: Dictionary) -> Array:
	var out: Array = []
	for sid in str(mem.get("ships", "")).split("|", false):
		var s := sid.strip_edges()
		if s != "" and _ship_defs.has(s):
			out.append(s)
	if out.is_empty():
		for k in _ship_defs.keys():
			out.append(str(k))
	return out


func _set_default_ship(member_id: String, ship_id: String) -> void:
	if member_id == "" or ship_id == "":
		return
	var rows: Array = MemberTableScr.load_merged()
	for i in range(rows.size()):
		if typeof(rows[i]) != TYPE_DICTIONARY:
			continue
		if str(rows[i].get("id", "")) != member_id:
			continue
		var row: Dictionary = (rows[i] as Dictionary).duplicate(true)
		row["default_ship"] = ship_id
		rows[i] = row
		_members[member_id] = row
		break
	MemberTableScr.write_rows(MemberTableScr._headers_of(rows), rows)
	_status.text = "已保存 %s 默认舰 → %s" % [member_id, ship_id]


func _persist() -> void:
	if _size <= 0:
		return
	var onfield := PackedStringArray()
	var starters := PackedStringArray()
	for mid in _member_order:
		if _onfield.has(str(mid)):
			onfield.append(str(mid))
		if _starters.has(str(mid)):
			starters.append(str(mid))
	RosterTemplatesScr.set_entry(_size, onfield, starters)


func _lab(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


func _style(bg: Color, border: Color, margin: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(margin)
	return sb
