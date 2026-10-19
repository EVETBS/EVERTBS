extends Control
## EVE战棋主菜单 — 蓝平行四边形 + 白线展开（UI_AND_SHELL §0）

const _ParaBtn: Script = preload("res://scripts/ui/menu_parallelogram_button.gd")
const _BranchReveal: Script = preload("res://scripts/ui/menu_branch_reveal.gd")
const _LobbyPanel: Script = preload("res://scripts/ui/nullsec_lobby_panel.gd")
const _BoardSave: Script = preload("res://scripts/save/board_save.gd")
const DevWindowScr := preload("res://game/dev_options_window.gd")

const TITLE_TEXT := "EVE战棋"
const DECLARE_TEXT := "EVE以及其相关之图标/设计均属CCP所有.\n本作为非商业玩家二创。"
const BRANCH_PLAY := "play"
const BRANCH_SOLO := "solo"
const BRANCH_ONLINE := "online"
const BRANCH_OPTIONS := "options"
const _SECONDARY_BG := Color(0.12, 0.28, 0.55, 0.42)
const _SECONDARY_BORDER := Color(0.55, 0.75, 1.0, 0.40)

var _branch_open: String = ""
var _play_mode_open: String = ""
var _branch_reveal: RefCounted = _BranchReveal.new() as RefCounted
var _play_mode_reveal: RefCounted = _BranchReveal.new() as RefCounted
var _tertiary_reveal: RefCounted = _BranchReveal.new() as RefCounted
var _primary_btns: Dictionary = {}
var _secondary_hosts: Dictionary = {}
var _btn_box: VBoxContainer
var _title: Label
var _footer: VBoxContainer
var _announce: TextureRect
var _announce_texs: Array[Texture2D] = []
var _announce_i: int = 0
var _nullsec_lobby: Control
var _settings_panel: Control
var _dev_window: Window
var _load_tertiary_host: Control
var _load_tertiary_open: bool = false
var _stub_dlg: AcceptDialog
var _overlay: Control
var _chrome_offscreen := false
var _btn_load: Button
var _load_list: VBoxContainer
var _dbg_layout_once: bool = false
var _static_bg: Control
var _dyn_host: SubViewportContainer
var _dyn_viewport: SubViewport
var _menu_bg_dynamic: bool = false


func _ready() -> void:
	# #region agent log
	_play_mode_reveal.set("on_slide_step", Callable(self, "_on_play_mode_slide_step"))
	_tertiary_reveal.set("on_slide_step", Callable(self, "_on_tertiary_slide_step"))
	# #endregion
	_build()
	_android_handtune()
	_apply_menu_bg(PlayerSettings.get_menu_bg_dynamic())
	_start_announce_cycle()


func _process(_dt: float) -> void:
	_layout()


func _android_handtune() -> void:
	if OS.get_name() != "Android" and not OS.has_feature("mobile"):
		return
	var vp := get_viewport().get_visible_rect().size
	var ip := LanAffinity.best_local_ipv4()
	DebugSessionLog.append("AND", "main_menu._android_handtune", "boot", {
		"os": OS.get_name(),
		"emu": LanBeacon.is_android_emulator(),
		"w": vp.x,
		"h": vp.y,
		"dpi": DisplayServer.screen_get_dpi(),
		"ip": ip,
		"runId": "handtune",
	})
	var lab := Label.new()
	lab.name = "HandTune"
	lab.text = "手调 %dx%d  %s" % [int(vp.x), int(vp.y), ip]
	lab.position = Vector2(12, 8)
	lab.z_index = 50
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lab)


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := TextureRect.new()
	bg.name = "BG"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.texture = UiAssets.tex(UiAssets.MAIN_BG)
	if bg.texture == null:
		var fallback := ColorRect.new()
		fallback.name = "BG"
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.color = Color(0.04, 0.05, 0.08, 1)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fallback)
		_static_bg = fallback
	else:
		add_child(bg)
		_static_bg = bg
	_dyn_host = SubViewportContainer.new()
	_dyn_host.name = "DynamicBg"
	_dyn_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dyn_host.stretch = true
	_dyn_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dyn_host.visible = false
	_dyn_viewport = SubViewport.new()
	_dyn_viewport.name = "MenuBgViewport"
	_dyn_viewport.own_world_3d = true
	_dyn_viewport.handle_input_locally = false
	_dyn_viewport.audio_listener_enable_3d = false
	_dyn_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_dyn_host.add_child(_dyn_viewport)
	add_child(_dyn_host)
	move_child(_dyn_host, 0)
	if _static_bg:
		move_child(_static_bg, 0)
	_title = Label.new()
	_title.text = TITLE_TEXT
	_title.add_theme_font_size_override("font_size", 42)
	_title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title.add_theme_constant_override("outline_size", 4)
	add_child(_title)
	_btn_box = VBoxContainer.new()
	_btn_box.name = "Buttons"
	_btn_box.add_theme_constant_override("separation", 20)
	_btn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_btn_box)
	_nullsec_lobby = _LobbyPanel.new()
	_add_branch_row(BRANCH_PLAY, "开始游戏", _build_play_secondary)
	_add_branch_row(BRANCH_OPTIONS, "选项", _build_options_secondary)
	_footer = VBoxContainer.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer)
	var declare := Label.new()
	declare.text = DECLARE_TEXT
	declare.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	declare.add_theme_font_size_override("font_size", 12)
	declare.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	declare.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	declare.add_theme_constant_override("outline_size", 2)
	_footer.add_child(declare)
	var ver := Label.new()
	ver.text = "游戏版本: %s" % _content_version()
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	ver.add_theme_constant_override("outline_size", 2)
	_footer.add_child(ver)
	_announce = TextureRect.new()
	_announce.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_announce.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_announce.z_index = 8
	_announce_texs = UiAssets.announcement_textures()
	if _announce_texs.size() > 0:
		_announce.texture = _announce_texs[0]
	else:
		_announce.visible = false
	add_child(_announce)
	_settings_panel = _build_settings_panel()
	_settings_panel.visible = false
	add_child(_settings_panel)
	_stub_dlg = AcceptDialog.new()
	_stub_dlg.title = "提示"
	_stub_dlg.dialog_text = "功能未实装"
	add_child(_stub_dlg)


func _content_version() -> String:
	var ds = get_node_or_null("/root/DataStore")
	if ds != null and "content_version" in ds:
		return str(ds.content_version)
	return "local"


func _menu_btn(text: String, cb: Callable) -> Button:
	var b: Button = _ParaBtn.new() as Button
	b.text = text
	b.custom_minimum_size = Vector2(200, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiAssets.apply_button_font(b, 22)
	b.pressed.connect(cb)
	return b


func _add_branch_row(id: String, primary_text: String, build_secondary: Callable, attach_to: Control = null) -> void:
	var row := Control.new()
	row.name = "Branch_%s" % id
	row.custom_minimum_size = Vector2(200, 56)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var primary: Button = _menu_btn(primary_text, func() -> void: _on_primary(id))
	primary.name = "Primary_%s" % id
	row.add_child(primary)
	_primary_btns[id] = primary
	var host := Control.new()
	## Must be Secondary_* so parent mindmap does not descend into nested content (EveAC).
	host.name = "Secondary_%s" % id
	host.visible = false
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.z_index = 4
	var secondary: Control = build_secondary.call() as Control
	secondary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(secondary)
	row.add_child(host)
	_secondary_hosts[id] = host
	if attach_to != null:
		attach_to.add_child(row)
	else:
		_btn_box.add_child(row)


func _on_primary(id: String) -> void:
	if id == BRANCH_SOLO or id == BRANCH_ONLINE:
		_toggle_play_mode(id)
	else:
		_toggle_branch(id)


func _build_play_secondary() -> Control:
	var root := Control.new()
	root.name = "PlaySecondaryRoot"
	root.clip_contents = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.name = "PlayCol"
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	_add_branch_row(BRANCH_SOLO, "单机模式", _build_solo_secondary, col)
	_add_branch_row(BRANCH_ONLINE, "联机模式", _build_online_secondary, col)
	col.add_child(_menu_btn("新手教程", _stub))
	col.add_child(_menu_btn("配置团员", _open_member_config))
	return root


func _build_solo_secondary() -> Control:
	var root := Control.new()
	root.clip_contents = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	box.add_child(_menu_btn("自定义战役", _open_campaign_overlay))
	_btn_load = _menu_btn("读取存档", _on_load_open)
	_btn_load.name = "BtnLoad"
	box.add_child(_btn_load)
	_load_tertiary_host = Control.new()
	_load_tertiary_host.name = "LoadTertiary"
	_load_tertiary_host.visible = false
	_load_tertiary_host.z_index = 8
	_load_tertiary_host.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_load_tertiary_host)
	var scroll := ScrollContainer.new()
	scroll.name = "LoadScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_load_list = VBoxContainer.new()
	_load_list.name = "LoadList"
	_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_load_list)
	var chrome := _make_secondary_chrome(scroll)
	chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_tertiary_host.add_child(chrome)
	return root


func _build_online_secondary() -> Control:
	var root := Control.new()
	root.clip_contents = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := _make_secondary_chrome(_nullsec_lobby)
	chrome.set_anchors_preset(Control.PRESET_TOP_LEFT)
	chrome.custom_minimum_size = Vector2(420, 420)
	chrome.size = Vector2(420, 420)
	root.add_child(chrome)
	if _nullsec_lobby.has_signal("request_match_public"):
		_nullsec_lobby.request_match_public.connect(_on_mp_match)
		_nullsec_lobby.request_host_room.connect(_on_mp_host)
		_nullsec_lobby.request_join_share.connect(_on_mp_join)
		_nullsec_lobby.request_restore_room.connect(_on_mp_restore)
	return root


func _build_options_secondary() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	box.add_child(_menu_btn("mod导入", _stub))
	box.add_child(_menu_btn("图鉴", _open_codex_overlay))
	box.add_child(_menu_btn("设置", _on_settings_open))
	return root


func _make_secondary_chrome(content: Control) -> Control:
	var root := Control.new()
	root.name = "SecondaryChrome"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = _SECONDARY_BG
	sb.border_color = _SECONDARY_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	bg.add_theme_stylebox_override("panel", sb)
	root.add_child(bg)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	root.add_child(pad)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(content)
	return root


func _toggle_branch(id: String) -> void:
	_settings_panel.visible = false
	_collapse_tertiary_load()
	_branch_reveal.call("abort")
	_play_mode_reveal.call("abort")
	if _branch_open == id:
		_collapse_all_secondaries()
		_branch_open = ""
		_play_mode_open = ""
		return
	_collapse_all_secondaries()
	_branch_open = id
	_play_mode_open = ""
	var host: Control = _secondary_hosts.get(id) as Control
	var primary: Control = _primary_btns.get(id) as Control
	if host == null or primary == null:
		return
	host.visible = true
	_apply_host_sizes()
	await get_tree().process_frame
	_apply_host_sizes()
	_branch_reveal.call("play", get_tree(), primary, host, _SECONDARY_BG)


func _toggle_play_mode(id: String) -> void:
	if _branch_open != BRANCH_PLAY:
		await _toggle_branch(BRANCH_PLAY)
	_collapse_tertiary_load()
	_play_mode_reveal.call("abort")
	if _play_mode_open == id:
		_collapse_play_mode_hosts()
		_play_mode_open = ""
		return
	_collapse_play_mode_hosts()
	_play_mode_open = id
	var host: Control = _secondary_hosts.get(id) as Control
	var primary: Control = _primary_btns.get(id) as Control
	if host == null or primary == null:
		return
	host.visible = true
	_apply_host_sizes()
	await get_tree().process_frame
	_apply_host_sizes()
	_play_mode_reveal.call("play", get_tree(), primary, host, _SECONDARY_BG)


func _collapse_play_mode_hosts() -> void:
	for mid: String in [BRANCH_SOLO, BRANCH_ONLINE]:
		var h: Control = _secondary_hosts.get(mid) as Control
		if h:
			h.visible = false
		var p: Control = _primary_btns.get(mid) as Control
		if p:
			p.modulate = Color.WHITE
			if p.has_method("set_slide_offset_px"):
				p.call("set_slide_offset_px", 0.0)


func _collapse_all_secondaries() -> void:
	_branch_reveal.call("abort")
	_play_mode_reveal.call("abort")
	_collapse_tertiary_load()
	_collapse_play_mode_hosts()
	for id: String in [BRANCH_PLAY, BRANCH_OPTIONS]:
		var h: Control = _secondary_hosts.get(id) as Control
		if h:
			h.visible = false
		var p: Control = _primary_btns.get(id) as Control
		if p:
			p.modulate = Color.WHITE
			if p.has_method("set_slide_offset_px"):
				p.call("set_slide_offset_px", 0.0)


func _collapse_tertiary_load() -> void:
	_tertiary_reveal.call("abort")
	_load_tertiary_open = false
	if _load_tertiary_host:
		_load_tertiary_host.visible = false


func _layout_load_tertiary() -> void:
	if _load_tertiary_host == null or _btn_load == null:
		return
	var parent: Control = _load_tertiary_host.get_parent() as Control
	if parent == null:
		return
	var local: Vector2 = parent.get_global_transform_with_canvas().affine_inverse() * _btn_load.global_position
	_load_tertiary_host.position = Vector2(local.x + _btn_load.size.x + 36.0, local.y)
	_load_tertiary_host.size = Vector2(520, 280)


func _on_load_open() -> void:
	if _load_tertiary_open:
		_collapse_tertiary_load()
		if _play_mode_reveal.has_method("relayout_open_link"):
			_play_mode_reveal.call("relayout_open_link")
		return
	_refresh_load_list()
	_load_tertiary_open = true
	_load_tertiary_host.visible = true
	_layout_load_tertiary()
	await get_tree().process_frame
	_layout_load_tertiary()
	if _btn_load:
		_tertiary_reveal.call("play", get_tree(), _btn_load, _load_tertiary_host, _SECONDARY_BG)


func _refresh_load_list() -> void:
	if _load_list == null:
		return
	for c in _load_list.get_children():
		c.queue_free()
	var slots: Array = _BoardSave.call("list_slots") as Array
	# #region agent log
	var ids: Array = []
	for s0 in slots:
		if typeof(s0) == TYPE_DICTIONARY:
			ids.append(str(s0.get("id", "")))
	_dbg59("E", "load_list_refresh", {"n": slots.size(), "ids": ids})
	# #endregion
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "暂无存档"
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		_load_list.add_child(empty)
		var eof0 := Label.new()
		eof0.text = "到头了"
		eof0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		eof0.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9, 0.75))
		_load_list.add_child(eof0)
		return
	var title := Label.new()
	title.text = "存档列表"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_load_list.add_child(title)
	for s in slots:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sid := str(s.get("id", ""))
		var slot_name := str(s.get("name", sid))
		var updated := str(s.get("updated_at", ""))
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 52)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		## Parallelogram plate: click loads; name + timestamp overlaid (EveAC style).
		var plate := Control.new()
		plate.custom_minimum_size = Vector2(300, 48)
		plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bar: Button = _ParaBtn.new() as Button
		bar.text = ""
		bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.pressed.connect(_on_load_slot.bind(sid))
		plate.add_child(bar)
		var labels := HBoxContainer.new()
		labels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		labels.offset_left = 16
		labels.offset_right = -16
		labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.text = slot_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		name_lbl.add_theme_constant_override("outline_size", 2)
		name_lbl.add_theme_font_size_override("font_size", 16)
		labels.add_child(name_lbl)
		var time_lbl := Label.new()
		time_lbl.text = updated if updated != "" else "—"
		time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		time_lbl.custom_minimum_size = Vector2(140, 0)
		time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		time_lbl.add_theme_color_override("font_color", Color(0.82, 0.86, 0.94, 0.95))
		time_lbl.add_theme_font_size_override("font_size", 12)
		labels.add_child(time_lbl)
		plate.add_child(labels)
		row.add_child(plate)
		var load_btn: Button = _ParaBtn.new() as Button
		load_btn.text = "加载"
		load_btn.custom_minimum_size = Vector2(72, 36)
		load_btn.pressed.connect(_on_load_slot.bind(sid))
		row.add_child(load_btn)
		var del_btn: Button = _ParaBtn.new() as Button
		del_btn.text = "删除"
		del_btn.custom_minimum_size = Vector2(64, 36)
		del_btn.pressed.connect(_on_delete_slot.bind(sid, slot_name))
		row.add_child(del_btn)
		_load_list.add_child(row)
	var eof := Label.new()
	eof.text = "到头了"
	eof.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eof.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9, 0.75))
	eof.add_theme_font_size_override("font_size", 12)
	_load_list.add_child(eof)


func _on_load_slot(slot_id: String) -> void:
	var r: Dictionary = _BoardSave.call("load_slot", slot_id) as Dictionary
	# #region agent log
	_dbg59("E", "load_slot", {"id": slot_id, "ok": bool(r.get("ok", false)), "layout": str(r.get("layout", ""))})
	# #endregion
	if not bool(r.get("ok", false)):
		_stub()
		return
	get_tree().change_scene_to_file(str(r.get("scene", "res://game/board_test.tscn")))


func _on_delete_slot(slot_id: String, display_name: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "删除存档"
	dlg.dialog_text = "确定删除「%s」？此操作不可恢复。" % display_name
	dlg.ok_button_text = "删除"
	dlg.cancel_button_text = "取消"
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		_BoardSave.call("delete_slot", slot_id)
		_refresh_load_list()
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.close_requested.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered()


func _open_campaign_overlay() -> void:
	var camp := (load("res://game/custom_campaign.gd") as GDScript).new() as Control
	camp.set("embedded", true)
	if camp.has_signal("closed"):
		camp.closed.connect(_close_overlay)
	_open_overlay(camp)


func _open_codex_overlay() -> void:
	var codex := (load("res://game/codex_overlay.gd") as GDScript).new() as Control
	if codex.has_signal("closed"):
		codex.closed.connect(_close_overlay)
	_open_overlay(codex)



func _open_member_config() -> void:
	var conf := (load("res://game/member_config_overlay.gd") as GDScript).new() as Control
	if conf.has_signal("closed"):
		conf.closed.connect(_close_overlay)
	_open_overlay(conf)

func _open_overlay(node: Control) -> void:
	_close_overlay()
	_chrome_offscreen = true
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.z_index = 30
	add_child(node)
	_overlay = node


func _close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		if _overlay.get_parent() == self:
			remove_child(_overlay)
		_overlay.queue_free()
	_overlay = null
	_chrome_offscreen = false


func _mp_session() -> MpCampaignNet:
	var gs := get_node_or_null("/root/GameSession")
	if gs == null:
		return null
	var existing := gs.get_node_or_null("MpCampaignNet")
	if existing is MpCampaignNet:
		return existing
	var created := MpCampaignNet.new()
	created.name = "MpCampaignNet"
	gs.add_child(created)
	created.joined.connect(_open_mp_room)
	created.failed.connect(_on_mp_failed)
	return created


func _open_mp_room() -> void:
	var net := _mp_session()
	if net == null:
		return
	if _overlay != null and _overlay is MpCampaignRoom:
		return
	var room := MpCampaignRoom.new()
	room.setup(net)
	if room.has_signal("closed"):
		room.closed.connect(_close_overlay)
	_open_overlay(room)


func _on_mp_failed(msg: String) -> void:
	if _nullsec_lobby != null and _nullsec_lobby.has_method("set_status"):
		_nullsec_lobby.call("set_status", msg)


func _on_mp_host(password: String) -> void:
	var net := _mp_session()
	if net == null or _nullsec_lobby == null:
		return
	var err := net.host_room(str(_nullsec_lobby.call("sanitized_nick")), password)
	if err != OK:
		_on_mp_failed("开房失败")
		return
	_open_mp_room()


func _on_mp_join(share: String) -> void:
	var net := _mp_session()
	if net == null or _nullsec_lobby == null:
		return
	net.join_share(share, str(_nullsec_lobby.call("sanitized_nick")))


func _on_mp_match() -> void:
	var net := _mp_session()
	if net == null or _nullsec_lobby == null:
		return
	var ignore := false
	if _nullsec_lobby.has_method("ignore_in_match"):
		ignore = bool(_nullsec_lobby.call("ignore_in_match"))
	net.match_public(str(_nullsec_lobby.call("sanitized_nick")), ignore)


func _on_mp_restore() -> void:
	var net := _mp_session()
	if net == null or _nullsec_lobby == null:
		return
	net.restore_room(str(_nullsec_lobby.call("sanitized_nick")))


func _stub(_a: Variant = null) -> void:
	_stub_dlg.dialog_text = "功能未实装"
	_stub_dlg.popup_centered()


func _on_settings_open() -> void:
	_collapse_all_secondaries()
	_branch_open = ""
	_settings_panel.visible = true
	_rebuild_settings()
	# #region agent log
	_dbg59("B", "settings_open_links", {"mindmap": _count_named(self, "BranchMindmapLink"), "wipe": _count_named(self, "BranchRevealLine"), "settings": _settings_panel.visible})
	# #endregion


func _build_settings_panel() -> Control:
	var root := PanelContainer.new()
	root.name = "SettingsPanel"
	root.z_index = 20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	sb.border_color = Color(0.55, 0.6, 0.7, 0.9)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	root.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)
	return root


func _apply_menu_bg(dynamic: bool) -> void:
	_menu_bg_dynamic = dynamic
	if _static_bg:
		_static_bg.visible = not dynamic
	if _dyn_host == null:
		return
	_dyn_host.visible = dynamic
	if dynamic:
		_ensure_dyn_backdrop()
	else:
		_teardown_dyn_backdrop()


func _ensure_dyn_backdrop() -> void:
	if _dyn_viewport == null:
		return
	if _dyn_viewport.get_child_count() > 0:
		return
	var packed: PackedScene = load("res://game/menu_bg/menu_backdrop.tscn") as PackedScene
	if packed == null:
		push_error("menu_backdrop.tscn missing")
		return
	var node := packed.instantiate()
	_dyn_viewport.add_child(node)


func _teardown_dyn_backdrop() -> void:
	if _dyn_viewport == null:
		return
	for c in _dyn_viewport.get_children():
		if c.has_method("stop_backdrop"):
			c.call("stop_backdrop")
		c.queue_free()


func _rebuild_settings() -> void:
	var box: VBoxContainer = _settings_panel.get_node("Box") as VBoxContainer
	for c in box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_add_vol_row(box, "背景音乐大小", PlayerSettings.get_bgm(), func(v: float) -> void: PlayerSettings.set_bgm(v))
	_add_vol_row(box, "音效大小", PlayerSettings.get_sfx(), func(v: float) -> void: PlayerSettings.set_sfx(v))
	var bg_row := HBoxContainer.new()
	box.add_child(bg_row)
	var bg_lab := Label.new()
	bg_lab.text = "主界面动态背景"
	bg_row.add_child(bg_lab)
	var bg_chk := CheckButton.new()
	bg_chk.button_pressed = PlayerSettings.get_menu_bg_dynamic()
	bg_chk.text = "开" if bg_chk.button_pressed else "关"
	bg_chk.toggled.connect(func(on: bool) -> void:
		PlayerSettings.set_menu_bg_dynamic(on)
		bg_chk.text = "开" if on else "关"
		_apply_menu_bg(on)
	)
	bg_row.add_child(bg_chk)
	var plate_row := HBoxContainer.new()
	box.add_child(plate_row)
	var plate_lab := Label.new()
	plate_lab.text = "战场视角下时刻展示完整铭牌"
	plate_row.add_child(plate_lab)
	var plate_chk := CheckButton.new()
	plate_chk.button_pressed = PlayerSettings.get_full_plates()
	plate_chk.text = "开" if plate_chk.button_pressed else "关"
	plate_chk.toggled.connect(func(on: bool) -> void:
		PlayerSettings.set_full_plates(on)
		plate_chk.text = "开" if on else "关"
	)
	plate_row.add_child(plate_chk)
	_add_sensitivity_row(box)
	var dev_btn := Button.new()
	dev_btn.text = "开发者选项"
	dev_btn.pressed.connect(_open_dev_options)
	box.add_child(dev_btn)
	var export_dbg := Button.new()
	export_dbg.text = "导出 debug 日志"
	export_dbg.pressed.connect(_on_export_debug_log)
	box.add_child(export_dbg)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: _settings_panel.visible = false)
	box.add_child(close)


func _open_dev_options() -> void:
	if _dev_window == null or not is_instance_valid(_dev_window):
		_dev_window = DevWindowScr.new()
		add_child(_dev_window)
	_dev_window.present()
	DebugSessionLog.append("UI", "main_menu._open_dev_options", "click", {
		"control": "开发者选项",
		"surface": "main_menu_settings",
		"deputy_row": false,
		"dev_window_visible": _dev_window.visible,
		"runId": "grok-ui",
	})

func _on_export_debug_log() -> void:
	var res: Dictionary = DebugSessionLog.export_now()
	_stub_dlg.title = "导出 debug 日志"
	_stub_dlg.dialog_text = DebugSessionLog.format_result(res)
	_stub_dlg.popup_centered()
	# #region agent log
	_dbg59("EXP", "export_debug_log", {
		"ok": bool(res.get("ok", false)), "bytes": int(res.get("bytes", 0)),
		"lines": int(res.get("lines", 0)), "path": str(res.get("path", "")),
	})
	# #endregion


func _add_sensitivity_row(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var lab := Label.new()
	lab.text = "操作灵敏度"
	lab.custom_minimum_size = Vector2(160, 28)
	row.add_child(lab)
	var val := Label.new()
	val.custom_minimum_size = Vector2(48, 28)
	val.text = "%.1f" % PlayerSettings.get_op_sensitivity()
	var sl := HSlider.new()
	sl.min_value = 0.1
	sl.max_value = 10.0
	sl.step = 0.1
	sl.value = PlayerSettings.get_op_sensitivity()
	sl.custom_minimum_size = Vector2(180, 28)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v: float) -> void:
		var snapped := snappedf(v, 0.1)
		PlayerSettings.set_op_sensitivity(snapped)
		val.text = "%.1f" % snapped
	)
	row.add_child(sl)
	row.add_child(val)


func _add_vol_row(box: VBoxContainer, label: String, value: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var lab := Label.new()
	lab.text = label
	lab.custom_minimum_size = Vector2(160, 28)
	row.add_child(lab)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.01
	sl.value = value
	sl.custom_minimum_size = Vector2(180, 28)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(cb)
	row.add_child(sl)


func _apply_host_sizes() -> void:
	for id: String in _secondary_hosts.keys():
		var host: Control = _secondary_hosts[id] as Control
		var primary: Control = _primary_btns.get(id) as Control
		if host == null or primary == null or not host.visible:
			continue
		host.position = Vector2(primary.size.x + 100.0, 0.0)
		match id:
			BRANCH_ONLINE:
				host.size = Vector2(440, 460)
			BRANCH_SOLO:
				host.size = Vector2(240, 200)
			BRANCH_PLAY:
				host.size = Vector2(260, 320)
			_:
				host.size = Vector2(240, 160)


func _layout() -> void:
	var vp := get_viewport_rect().size
	var shift_x := vp.x if _chrome_offscreen else 0.0
	_title.position = Vector2(vp.x * 0.038 + shift_x, vp.y * 0.08)
	_title.size = Vector2(480, 56)
	_btn_box.position = Vector2(vp.x * 0.038 + shift_x, vp.y * 0.18)
	_btn_box.size = Vector2(220, 400)
	_footer.position = Vector2(vp.x * 0.038 + shift_x, vp.y * 0.82)
	# #region agent log
	if not _dbg_layout_once:
		_dbg_layout_once = true
		_dbg59("A", "footer_vs_left", {"footer_x": _footer.position.x, "title_x": _title.position.x, "btn_x": _btn_box.position.x, "vp_x": vp.x, "dx": _footer.position.x - _title.position.x})
	# #endregion
	_footer.size = Vector2(420, vp.y * 0.14)
	_announce.position = Vector2(vp.x * 0.62 + shift_x, vp.y * 0.68)
	_announce.size = Vector2(vp.x * 0.34, vp.y * 0.22)
	_settings_panel.position = Vector2(vp.x * 0.5 - 220, vp.y * 0.5 - 200)
	_settings_panel.size = Vector2(440, 400)


func _on_play_mode_slide_step() -> void:
	if _branch_reveal.has_method("relayout_open_link"):
		_branch_reveal.call("relayout_open_link")
	_dbg_slide_hook_only()


func _on_tertiary_slide_step() -> void:
	if _play_mode_reveal.has_method("relayout_open_link"):
		_play_mode_reveal.call("relayout_open_link")
	if _branch_reveal.has_method("relayout_open_link"):
		_branch_reveal.call("relayout_open_link")
	_dbg_slide_hook_only()


func _dbg_slide_hook_only() -> void:
	# #region agent log
	_dbg59("C", "slide_step_no_relayout", {"hook": "play_or_tertiary", "branch_link": _branch_reveal.get("_link") != null})
	# #endregion


func _count_named(n: Node, want: String) -> int:
	var c := 0
	if str(n.name) == want and not n.is_queued_for_deletion():
		c += 1
	for ch in n.get_children():
		if ch.is_queued_for_deletion():
			continue
		c += _count_named(ch, want)
	return c


func _dbg59(hyp: String, msg: String, data: Dictionary) -> void:
	# #region agent log
	DebugSessionLog.append(hyp, "main_menu.gd", msg, data)
	# #endregion


func _start_announce_cycle() -> void:
	if _announce_texs.size() <= 1:
		return
	var t := Timer.new()
	t.wait_time = 5.0
	t.autostart = true
	t.timeout.connect(func() -> void:
		_announce_i = (_announce_i + 1) % _announce_texs.size()
		_announce.texture = _announce_texs[_announce_i]
	)
	add_child(t)
