extends Control
## Custom SR member editor. Closing saves a draft. Confirm writes the member table.

signal closed

const MemberTableScr := preload("res://game/board/pilots/member_table.gd")
const CrewRankScr := preload("res://game/board/pilots/crew_rank.gd")
const Pack := preload("res://game/board/pilots/custom_member_pack.gd")

var _row: Dictionary = {}
var _sliders: Dictionary = {}
var _pct_labs: Dictionary = {}
var _warn: Label
var _list: ItemList
var _editor: Control
var _broke_once: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.1, 0.14, 0.15)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "自定义团员"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(_close_draft)
	head.add_child(back)
	var make := Button.new()
	make.text = "新建"
	make.pressed.connect(_new_row)
	head.add_child(make)
	var confirm := Button.new()
	confirm.text = "确认完成编辑"
	confirm.pressed.connect(_confirm)
	head.add_child(confirm)
	var export_b := Button.new()
	export_b.text = "导出压缩包"
	export_b.pressed.connect(_export)
	head.add_child(export_b)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 120)
	_list.item_selected.connect(_on_pick)
	root.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_editor = VBoxContainer.new()
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_editor)
	_warn = Label.new()
	_warn.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
	root.add_child(_warn)
	_refresh_list()
	_new_row()


func _refresh_list() -> void:
	_list.clear()
	for d in Pack.list_drafts():
		_list.add_item("未完成 %s %s" % [d.get("id", ""), d.get("name", "")])
		_list.set_item_metadata(_list.item_count - 1, d)
	for row in MemberTableScr.load_merged():
		if str(row.get("rank", "")).to_upper() != "SR":
			continue
		if MemberTableScr.is_builtin(str(row.get("id", ""))):
			continue
		_list.add_item("%s %s" % [row.get("id", ""), row.get("name", "")])
		_list.set_item_metadata(_list.item_count - 1, row)


func _on_pick(idx: int) -> void:
	_capture()
	var row = _list.get_item_metadata(idx)
	if typeof(row) == TYPE_DICTIONARY:
		_row = (row as Dictionary).duplicate(true)
		_fill_editor()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			for k in _sliders.keys():
				(_sliders[k] as HSlider).editable = true


func _new_row() -> void:
	var mid := Pack.alloc_local_id()
	if mid == "":
		_warn.text = CustomMemberPack.last_error
		_warn.modulate.a = 1.0
		return
	_row = {
		"id": mid,
		"name": "",
		"portrait": "",
		"bio": "",
		"rank": "SR",
		"bonus": "",
		"ships": "|".join(CrewRankScr.playable_ship_ids()),
		"default_ship": "gila_cc2",
		"pref_eq": MemberTableScr.DEFAULT_PREF,
	}
	_fill_editor()


func _fill_editor() -> void:
	for c in _editor.get_children():
		c.queue_free()
	_sliders.clear()
	_pct_labs.clear()
	_broke_once.clear()
	_editor.add_child(_labeled("名字", str(_row.get("name", "")), "name"))
	var hint := Label.new()
	hint.text = "记得在末尾留上作者名字。"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_editor.add_child(hint)
	var face := Button.new()
	face.text = "选择头像"
	face.pressed.connect(_pick_portrait)
	_editor.add_child(face)
	_editor.add_child(_labeled("背景", str(_row.get("bio", "")), "bio"))
	_editor.add_child(hint.duplicate())
	var parsed := _parse_bonus(str(_row.get("bonus", "")))
	for key in CrewRankScr.EFFECT_KEYS:
		var line := HBoxContainer.new()
		var lab := Label.new()
		lab.custom_minimum_size = Vector2(140, 0)
		lab.text = str(CrewRankScr.BONUS_LABELS.get(key, key))
		line.add_child(lab)
		var slider := HSlider.new()
		slider.min_value = -50
		slider.max_value = 50
		slider.step = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pct := 0.0
		if parsed.has(key):
			pct = (float(parsed[key]) - 1.0) * 100.0
		slider.value = clampf(pct, -50, 50)
		slider.value_changed.connect(_on_slider.bind(key, slider))
		line.add_child(slider)
		var num := Label.new()
		num.text = "%d%%" % int(slider.value)
		slider.value_changed.connect(func(_v: float) -> void: _sync_pct())
		line.add_child(num)
		_pct_labs[key] = num
		_editor.add_child(line)
		_sliders[key] = slider


func _labeled(title: String, value: String, field: String) -> Control:
	var box := VBoxContainer.new()
	var lab := Label.new()
	lab.text = title
	box.add_child(lab)
	if field == "bio":
		var page := TextEdit.new()
		page.custom_minimum_size = Vector2(320, 160)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		page.placeholder_text = "可以写一大段背景。"
		page.text = value
		page.text_changed.connect(func() -> void: _row[field] = page.text)
		box.add_child(page)
	else:
		var edit := LineEdit.new()
		edit.text = value
		edit.text_changed.connect(func(t: String) -> void: _row[field] = t)
		box.add_child(edit)
	var pic := Button.new()
	pic.text = "插入图片"
	pic.pressed.connect(_pick_side.bind(field))
	box.add_child(pic)
	_row[field] = value
	return box


func _sync_pct() -> void:
	for k in _sliders.keys():
		if _pct_labs.has(k):
			(_pct_labs[k] as Label).text = "%d%%" % int((_sliders[k] as HSlider).value)


func _on_slider(v: float, key: String, slider: HSlider) -> void:
	var others := 0.0
	for k in _sliders.keys():
		if str(k) == key:
			continue
		others += absf(float(_sliders[k].value))
	if absf(v) + others <= 50.0 + 0.01:
		_broke_once.erase(key)
		return
	if not _broke_once.has(key):
		_broke_once[key] = true
		var allow := maxf(0.0, 50.0 - others)
		slider.set_value_no_signal(signf(v) * allow)
		slider.editable = false
		_sync_pct()
		_flash_warn()
		return
	var need := absf(v) + others - 50.0
	var donors: Array = []
	for k2 in _sliders.keys():
		if str(k2) == key:
			continue
		if absf(float(_sliders[k2].value)) > 0.01:
			donors.append(k2)
	if donors.is_empty():
		slider.set_value_no_signal(signf(v) * maxf(0.0, 50.0 - others))
		return
	var share := need / float(donors.size())
	var left := need
	for k3 in donors:
		var cur := float(_sliders[k3].value)
		var cut := minf(absf(cur), share if left > share else left)
		var nxt := cur - signf(cur) * cut
		_sliders[k3].set_value_no_signal(nxt)
		left -= cut
	if left > 0.1:
		slider.set_value_no_signal(signf(v) * maxf(0.0, absf(v) - left))
	_sync_pct()


func _flash_warn() -> void:
	_warn.text = "加成绝对值相加不能超过%50"
	var tw := create_tween()
	_warn.modulate.a = 1.0
	tw.tween_property(_warn, "modulate:a", 0.15, 0.15)
	tw.tween_property(_warn, "modulate:a", 1.0, 0.15)
	tw.tween_property(_warn, "modulate:a", 0.15, 0.15)
	tw.tween_property(_warn, "modulate:a", 1.0, 0.15)


func _capture() -> void:
	if _row.is_empty():
		return
	var parts: PackedStringArray = PackedStringArray()
	for key in _sliders.keys():
		var pct := int(_sliders[key].value)
		if pct == 0:
			continue
		parts.append("%s=%s" % [str(key), str(1.0 + float(pct) / 100.0)])
	_row["bonus"] = "|".join(parts)
	_row["rank"] = "SR"


func _close_draft() -> void:
	_capture()
	Pack.save_draft(_row)
	closed.emit()
	queue_free()


func _confirm() -> void:
	_capture()
	var why := Pack.confirm_row(_row)
	if why != "":
		_warn.text = why
		_warn.modulate.a = 1.0
		return
	closed.emit()
	queue_free()


func _export() -> void:
	_capture()
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.zip"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		Pack.export_zip(_row, path)
		dialog.queue_free()
	)
	dialog.popup_centered_ratio(0.6)


func _pick_portrait() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.gif"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var bytes := FileAccess.get_file_as_bytes(path)
		var mime := "image/png"
		if path.ends_with(".gif"):
			mime = "image/gif"
		elif path.ends_with(".jpg") or path.ends_with(".jpeg"):
			mime = "image/jpeg"
		elif path.ends_with(".webp"):
			mime = "image/webp"
		var scaled: Dictionary = Pack.scale_image_bytes(bytes, mime)
		if str(scaled.get("error", "")) != "":
			_warn.text = str(scaled.get("error", ""))
			_warn.modulate.a = 1.0
			dialog.queue_free()
			return
		if str(scaled.get("anim_path", "")) != "":
			_row["portrait"] = str(scaled.get("anim_path", ""))
			_row["portrait_mime"] = str(scaled.get("mime", ""))
			_row.erase("portrait_b64")
		else:
			_row["portrait_b64"] = Marshalls.raw_to_base64(scaled.get("bytes", PackedByteArray()))
			_row["portrait_mime"] = str(scaled.get("mime", mime))
		dialog.queue_free()
	)
	dialog.popup_centered_ratio(0.6)


func _pick_side(field: String) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.gif"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var bytes := FileAccess.get_file_as_bytes(path)
		var mime := "image/png"
		if path.ends_with(".gif"):
			mime = "image/gif"
		elif path.ends_with(".jpg") or path.ends_with(".jpeg"):
			mime = "image/jpeg"
		elif path.ends_with(".webp"):
			mime = "image/webp"
		var scaled: Dictionary = Pack.scale_image_bytes(bytes, mime)
		if str(scaled.get("error", "")) != "":
			_warn.text = str(scaled.get("error", ""))
			_warn.modulate.a = 1.0
			dialog.queue_free()
			return
		var b64_key := "name_media_b64" if field == "name" else "bio_media_b64"
		var mime_key := "name_media_mime" if field == "name" else "bio_media_mime"
		var path_key := "name_media" if field == "name" else "bio_media"
		if str(scaled.get("anim_path", "")) != "":
			_row[path_key] = str(scaled.get("anim_path", ""))
			_row[mime_key] = str(scaled.get("mime", ""))
			_row.erase(b64_key)
		else:
			_row[b64_key] = Marshalls.raw_to_base64(scaled.get("bytes", PackedByteArray()))
			_row[mime_key] = str(scaled.get("mime", mime))
		dialog.queue_free()
	)
	dialog.popup_centered_ratio(0.6)


func _parse_bonus(raw: String) -> Dictionary:
	var out := {}
	for part in raw.split("|", false):
		var cut := part.find("=")
		if cut <= 0:
			continue
		out[part.substr(0, cut)] = part.substr(cut + 1)
	return out
