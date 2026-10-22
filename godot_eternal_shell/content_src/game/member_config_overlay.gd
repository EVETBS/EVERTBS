extends Control
## Member roster config overlay (UI_AND_SHELL §0.5 · SHIPS §7.2).
## Four-column grid of ALL members; per member: 场上/场下, 首发, default ship.

signal closed
signal size_selected(n: int)

const MemberTableScr := preload("res://game/board/pilots/member_table.gd")
const RosterTemplatesScr := preload("res://game/board/pilots/roster_templates.gd")
const EquipIconScr := preload("res://game/board/equip_icon.gd")
const DragScrollScr := preload("res://game/ui/drag_scroll.gd")

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
var _equip: Dictionary = {}
var _grid: GridContainer
var _status: Label
var _loaded := false


func _ready() -> void:
	_load_data()
	_build()
	var n := RosterTemplatesScr.active_size()
	if has_meta("mp_scale"):
		var room_n := int(get_meta("mp_scale"))
		if RosterTemplatesScr.SIZES.has(room_n):
			n = room_n
	_select_size(n)


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
	_equip.clear()
	var eq_raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/board/equipment.json"))
	if typeof(eq_raw) == TYPE_DICTIONARY:
		for k in (eq_raw as Dictionary).keys():
			var item = eq_raw[k]
			if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) != "":
				_equip[str(item.get("id", ""))] = item


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
		_remember_and_close()
	)
	head.add_child(back)
	#（单机才改自己的势力名称）26.10.22 11:25 s
	if not has_meta("mp_room"):
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 8)
		root.add_child(name_row)
		name_row.add_child(_lab("修改自己的势力名称"))
		var name_edit := LineEdit.new()
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.placeholder_text = "单机对局里显示的势力名"
		name_edit.text = _read_faction_name()
		name_edit.text_changed.connect(_write_faction_name)
		name_row.add_child(name_edit)
	#（单机才改自己的势力名称）26.10.22 11:25 e
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
	DragScrollScr.attach(scroll)


func _select_size(n: int) -> void:
	#（未加载的空名单不能写进 20 人档）26.10.22 21:40 s
	var switching := _loaded
	if _loaded:
		_persist()
	#（未加载的空名单不能写进 20 人档）26.10.22 21:40 e
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
	_sync_grid()
	_loaded = true
	_refresh_status()
	#（房间人数和主菜单当前档是同一份）26.10.22 22:10 s
	if switching and has_meta("mp_room"):
		size_selected.emit(n)
	#（房间人数和主菜单当前档是同一份）26.10.22 22:10 e


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
	if has_meta("mp_room"):
		var match_n := int(get_meta("mp_scale", _size))
		if match_n == _size:
			parts.append("  本局使用 %d 人档" % match_n)
		else:
			parts.append("  正在编辑 %d 人档，本局仍是 %d 人" % [_size, match_n])
	_status.text = "".join(parts)


func _display_order() -> PackedStringArray:
	## 首发，上场自定义，上场默认，不上场自定义，不上场默认。同一档保持团员表原序。
	var builtin_ids := MemberTableScr.builtin_ids()
	var starters := PackedStringArray()
	var field_custom := PackedStringArray()
	var field_default := PackedStringArray()
	var bench_custom := PackedStringArray()
	var bench_default := PackedStringArray()
	for mid in _member_order:
		var on := _onfield.has(mid)
		var custom := not builtin_ids.has(mid)
		if on and _starters.has(mid):
			starters.append(mid)
		elif on and custom:
			field_custom.append(mid)
		elif on:
			field_default.append(mid)
		elif custom:
			bench_custom.append(mid)
		else:
			bench_default.append(mid)
	var out := starters
	out.append_array(field_custom)
	out.append_array(field_default)
	out.append_array(bench_custom)
	out.append_array(bench_default)
	return out


func _rebuild_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for mid in _display_order():
		_grid.add_child(_cell(str(mid)))


func _sync_grid() -> void:
	var order := _display_order()
	var have: Dictionary = {}
	for c in _grid.get_children():
		var key := str(c.name)
		if key.begins_with("Cell_"):
			have[key.trim_prefix("Cell_")] = c
	if have.size() != order.size():
		_rebuild_grid()
		return
	for i in range(order.size()):
		var mid := str(order[i])
		var cell: Control = have.get(mid, null)
		if cell == null:
			_rebuild_grid()
			return
		_apply_cell_state(cell, mid)
		_grid.move_child(cell, i)


func _apply_cell_state(panel: Control, mid: String) -> void:
	var on := _onfield.has(mid)
	panel.add_theme_stylebox_override("panel", _style(CELL_BG_ON if on else CELL_BG_OFF, CELL_BORDER, 8))
	var field_btn := panel.find_child("FieldBtn", true, false) as Button
	if field_btn:
		field_btn.set_pressed_no_signal(on)
		field_btn.text = "场上" if on else "场下"
	var st_btn := panel.find_child("StarterBtn", true, false) as Button
	var is_st := _starters.has(mid)
	if st_btn:
		st_btn.set_pressed_no_signal(is_st)
		st_btn.text = "首发" if is_st else "非首发"
		st_btn.disabled = not on


func _cell(mid: String) -> Control:
	var mem: Dictionary = _members.get(mid, {})
	var on := _onfield.has(mid)
	var panel := PanelContainer.new()
	panel.name = "Cell_%s" % mid
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
	name_lab.size_flags_horizontal = Control.SIZE_SHRINK_END
	name_lab.add_theme_color_override("font_color", Color.WHITE)
	top.add_child(name_lab)
	var prefs := MemberTableScr.pref_list(mem)
	for i in 4:
		var eid := str(prefs[i]) if i < prefs.size() else ""
		top.add_child(_pref_button(mid, i, eid))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	if not MemberTableScr.is_builtin(mid):
		var fire := Button.new()
		fire.text = "解雇"
		fire.pressed.connect(_ask_dismiss.bind(mid, str(mem.get("name", mid))))
		top.add_child(fire)
	var field_btn := Button.new()
	field_btn.name = "FieldBtn"
	field_btn.toggle_mode = true
	field_btn.button_pressed = on
	field_btn.text = "场上" if on else "场下"
	field_btn.toggled.connect(func(v: bool) -> void:
		if v:
			_onfield[mid] = true
		else:
			_onfield.erase(mid)
		_persist()
		_sync_grid()
		_refresh_status()
	)
	top.add_child(field_btn)
	var st_btn := Button.new()
	st_btn.name = "StarterBtn"
	st_btn.toggle_mode = true
	var is_st := _starters.has(mid)
	st_btn.button_pressed = is_st
	st_btn.text = "首发" if is_st else "非首发"
	st_btn.disabled = not on
	st_btn.toggled.connect(func(v: bool) -> void:
		#（场下不能被手势误开成首发）26.10.23 00:24 s
		if v and not _onfield.has(mid):
			st_btn.set_pressed_no_signal(false)
			return
		#（场下不能被手势误开成首发）26.10.23 00:24 e
		if v:
			_starters[mid] = true
		else:
			_starters.erase(mid)
		_persist()
		_sync_grid()
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
	var stored := str(mem.get("default_ship", ""))
	var cur := stored
	#（无效默认舰写回列表里的第一艘）26.10.22 21:40 s
	if cur == "" or cur not in unlocked:
		cur = str(unlocked[0]) if not unlocked.is_empty() else "gila_cc2"
		if cur != "" and cur != stored:
			_set_default_ship(mid, cur)
	#（无效默认舰写回列表里的第一艘）26.10.22 21:40 e
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
	out.sort_custom(func(a, b) -> bool:
		var da: Dictionary = _ship_defs.get(str(a), {})
		var db: Dictionary = _ship_defs.get(str(b), {})
		var wa := BoardTypes.tonnage_weight(str(da.get("tonnage", "")))
		var wb := BoardTypes.tonnage_weight(str(db.get("tonnage", "")))
		if wa != wb:
			return wa > wb
		return str(da.get("name", a)) < str(db.get("name", b))
	)
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


func _remember_and_close() -> void:
	_persist()
	closed.emit()
	queue_free()


func _exit_tree() -> void:
	## Any close path writes the current size once for the next match.
	if _loaded:
		_persist()


func _persist() -> void:
	if not _loaded or _size <= 0:
		return
	var onfield := PackedStringArray()
	var starters := PackedStringArray()
	for mid in _member_order:
		if _onfield.has(str(mid)):
			onfield.append(str(mid))
		if _starters.has(str(mid)):
			starters.append(str(mid))
	RosterTemplatesScr.set_entry(_size, onfield, starters)


func _pref_button(mid: String, index: int, eid: String) -> Button:
	var btn := Button.new()
	btn.name = "Pref_%s_%d" % [mid, index]
	btn.custom_minimum_size = Vector2(36, 36)
	btn.pressed.connect(_pick_pref.bind(mid, index))
	var eq: Dictionary = _equip.get(eid, {})
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if eid != "":
		icon.texture = EquipIconScr.for_row(eq)
	btn.add_child(icon)
	var size_s := str(eq.get("size", "")).to_lower()
	if size_s != "" and not bool(eq.get("implant", false)):
		var badge := TextureRect.new()
		badge.custom_minimum_size = Vector2(12, 12)
		badge.position = Vector2(22, 2)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bpath := "res://assets/ui/sprites/equipment_size_badges/size_%s.png" % size_s
		if ResourceLoader.exists(bpath):
			badge.texture = load(bpath)
		btn.add_child(badge)
	return btn


func _pref_blocked(eid: String, eq: Dictionary) -> bool:
	if bool(eq.get("implant", false)) or eid.begins_with("implant_"):
		return true
	if bool(eq.get("parked", false)) or str(eq.get("size", "")) == "XL":
		return true
	var kind := str(eq.get("kind", ""))
	#（偏好装备不含远程维修）26.10.22 11:25 s
	if kind in ["remote_armor", "remote_shield"] or eid.begins_with("weapon_remote_"):
		return true
	#（偏好装备不含远程维修）26.10.22 11:25 e
	if kind in ["weapon", "missile", "pd", "command_burst", "guard_shield", "guard_armor", "no_max_loss", "pd_repair_max_loss"]:
		return true
	if eid.begins_with("weapon_") or eid.begins_with("pd_") or eid.begins_with("command_burst_"):
		return true
	if eid in ["bubble", "interdiction", "shield_field", "armor_link"]:
		return true
	if eid.contains("sleeper"):
		return true
	return false


func _pick_pref(mid: String, index: int) -> void:
	#（偏好装备单用拖动翻页，不用点不开的弹出菜单）26.10.22 16:25 s
	var old := get_node_or_null("PrefSheet")
	if old:
		old.queue_free()
	var sheet := PanelContainer.new()
	sheet.name = "PrefSheet"
	sheet.z_index = 40
	sheet.set_anchors_preset(Control.PRESET_CENTER)
	sheet.custom_minimum_size = Vector2(420, 480)
	sheet.position = Vector2(80, 40)
	add_child(sheet)
	var box := VBoxContainer.new()
	sheet.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "偏好装备"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(sheet.queue_free)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	DragScrollScr.attach(scroll)
	var empty := Button.new()
	empty.text = "空"
	empty.alignment = HORIZONTAL_ALIGNMENT_LEFT
	empty.pressed.connect(func() -> void:
		_set_pref(mid, index, "")
		sheet.queue_free()
	)
	list.add_child(empty)
	for eid in _equip.keys():
		var eq: Dictionary = _equip[eid]
		if _pref_blocked(str(eid), eq):
			continue
		var b := Button.new()
		b.text = str(eq.get("name", eid))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_set_pref.bind(mid, index, str(eid)))
		b.pressed.connect(sheet.queue_free)
		list.add_child(b)
	#（偏好装备单用拖动翻页，不用点不开的弹出菜单）26.10.22 16:25 e


func _set_pref(mid: String, index: int, eid: String) -> void:
	var rows: Array = MemberTableScr.load_merged()
	for i in range(rows.size()):
		if str(rows[i].get("id", "")) != mid:
			continue
		var row: Dictionary = (rows[i] as Dictionary).duplicate(true)
		var prefs := MemberTableScr.pref_list(row)
		var arr: Array = []
		for p in prefs:
			arr.append(str(p))
		while arr.size() < 4:
			arr.append("")
		arr[index] = eid
		row["pref_eq"] = "|".join(PackedStringArray(arr))
		rows[i] = row
		_members[mid] = row
		break
	MemberTableScr.write_rows(MemberTableScr._headers_of(rows), rows)
	_refresh_pref_button(mid, index, eid)


func _refresh_pref_button(mid: String, index: int, eid: String) -> void:
	var old := _grid.find_child("Pref_%s_%d" % [mid, index], true, false) as Button
	if old == null or old.get_parent() == null:
		return
	var parent := old.get_parent()
	var at := old.get_index()
	parent.remove_child(old)
	old.free()
	parent.add_child(_pref_button(mid, index, eid))
	parent.move_child(parent.get_child(parent.get_child_count() - 1), at)


func _ask_dismiss(mid: String, name: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "解雇 %s？" % name
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		if MemberTableScr.dismiss(mid):
			_onfield.erase(mid)
			_starters.erase(mid)
			_scrub_templates(mid)
			_persist()
			_load_data()
			_rebuild_grid()
			_status.text = "已解雇 %s" % name
		dlg.queue_free()
	)
	dlg.popup_centered()


func _scrub_templates(mid: String) -> void:
	var doc := RosterTemplatesScr.load_all()
	var templates: Dictionary = doc.get("templates", {})
	for key in templates.keys():
		var entry = templates[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		for field in ["onfield", "starters"]:
			var kept: Array = []
			for item in entry.get(field, []):
				if str(item) != mid:
					kept.append(item)
			entry[field] = kept
		templates[key] = entry
	doc["templates"] = templates
	RosterTemplatesScr.save_all(doc)


func _menu_icon(eq: Dictionary) -> Texture2D:
	var base := EquipIconScr.for_row(eq)
	if base == null:
		return null
	var size_s := str(eq.get("size", "")).to_lower()
	if size_s == "" or bool(eq.get("implant", false)):
		return base
	var bpath := "res://assets/ui/sprites/equipment_size_badges/size_%s.png" % size_s
	if not ResourceLoader.exists(bpath):
		return base
	var img := base.get_image()
	var badge := load(bpath) as Texture2D
	if img == null or badge == null:
		return base
	img = img.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var bi := badge.get_image()
	if bi == null:
		return base
	bi = bi.duplicate()
	if bi.get_format() != Image.FORMAT_RGBA8:
		bi.convert(Image.FORMAT_RGBA8)
	var bw := mini(img.get_width(), maxi(8, int(img.get_width() / 3)))
	bi.resize(bw, bw, Image.INTERPOLATE_NEAREST)
	img.blend_rect(bi, Rect2i(0, 0, bw, bw), Vector2i(img.get_width() - bw, 0))
	return ImageTexture.create_from_image(img)


func _faction_name_path() -> String:
	return "user://content_runtime/data/board/local_faction_name.txt"


func _read_faction_name() -> String:
	var path := _faction_name_path()
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges()


func _write_faction_name(text: String) -> void:
	var path := _faction_name_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text.strip_edges())


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
