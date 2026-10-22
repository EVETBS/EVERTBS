extends Control
class_name MpCampaignRoom
## Translucent custom-campaign room. Solo campaign UI is a different scene and stays as it is.

signal closed

const DEPUTIES: Array = [
	["yang", "\u7f8a"],
	["six", "6"],
	["chuang", "\u521b"],
	["bei", "\u72c8"],
	["i", "I"],
]
const SCALES: Array[int] = [10, 15, 20, 40, 60]
const STAR_OPTS: Array[int] = [12, 16, 20, 24, 30, 40, 50]
const STOCK_LAYOUT := "res://data/board/layout.json"
const RatioSliderScr := preload("res://game/ui/ratio_dual_slider.gd")
const RosterTemplatesScr := preload("res://game/board/pilots/roster_templates.gd")

var net: MpCampaignNet
var _map_view: Control
var _chat_log: RichTextLabel
var _status: Label
var _members_box: GridContainer
var _ai_box: VBoxContainer
var _ready_box: BaseButton
var _fog: CheckBox
var _scale_row: HBoxContainer
var _deputy: OptionButton
var _limit: SpinBox
var _goal: SpinBox
var _star_row: HBoxContainer
var _stock_list: ItemList
var _gen_panel: Control
var _ratio
var _map_mode := "stock"
var _stock_layouts: Array = []
var _selected_stock := STOCK_LAYOUT
var _star_count := 20
var _lane_density := 1.0
var _avg_spacing := 120.0
var _station_pct := 35.0
var _resource_pct := 25.0
var _filling := false
var _sync_pending := false
var _slider_drag := 0


func setup(session: MpCampaignNet) -> void:
	net = session
	if not net.room_updated.is_connected(_rebuild):
		net.room_updated.connect(_rebuild)
	if not net.chat_received.is_connected(_on_chat):
		net.chat_received.connect(_on_chat)
	if not net.failed.is_connected(_on_fail):
		net.failed.connect(_on_fail)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.14, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24
	panel.offset_top = 24
	panel.offset_right = -24
	panel.offset_bottom = -24
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.15)
	sb.border_color = Color(0.75, 0.78, 0.82, 0.45)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var left := VBoxContainer.new()
	left.anchor_right = 0.56
	left.anchor_bottom = 1.0
	left.offset_left = 12
	left.offset_top = 12
	left.offset_right = -8
	left.offset_bottom = -12
	left.add_theme_constant_override("separation", 8)
	panel.add_child(left)
	var top := Button.new()
	top.text = "配置团员"
	top.pressed.connect(_open_members)
	left.add_child(top)
	_scan_stock_layouts()
	_add_map_controls(left)
	_scale_row = HBoxContainer.new()
	_scale_row.add_theme_constant_override("separation", 6)
	for n in SCALES:
		var scale_btn := Button.new()
		scale_btn.text = str(n)
		scale_btn.toggle_mode = true
		scale_btn.pressed.connect(_on_scale_btn.bind(n))
		_touch_target(scale_btn)
		_scale_row.add_child(scale_btn)
	left.add_child(_scale_row)
	_fog = CheckBox.new()
	_fog.text = "战争迷雾"
	_fog.toggled.connect(_on_fog)
	left.add_child(_fog)
	var modes := HBoxContainer.new()
	left.add_child(modes)
	for spec in [["gu_dou", "蛊斗"], ["hua_di", "画地"], ["jian_mie", "歼灭"]]:
		var cb := CheckBox.new()
		cb.text = spec[1]
		cb.set_meta("mode", spec[0])
		cb.toggled.connect(_on_mode.bind(spec[0], cb))
		modes.add_child(cb)
	var rules := HBoxContainer.new()
	left.add_child(rules)
	rules.add_child(_lab("时限分"))
	_limit = SpinBox.new()
	_limit.min_value = 10
	_limit.max_value = 240
	_limit.step = 5
	_limit.value = 90
	_limit.value_changed.connect(_on_limit)
	rules.add_child(_limit)
	rules.add_child(_lab("歼灭数"))
	_goal = SpinBox.new()
	_goal.min_value = 10
	_goal.max_value = 1000
	_goal.step = 1
	_goal.value = 50
	_goal.value_changed.connect(_on_goal)
	rules.add_child(_goal)
	_members_box = GridContainer.new()
	_members_box.columns = 2
	_members_box.add_theme_constant_override("h_separation", 12)
	_members_box.add_theme_constant_override("v_separation", 6)
	left.add_child(_members_box)
	_ai_box = VBoxContainer.new()
	left.add_child(_ai_box)
	var line1 := Label.new()
	line1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line1.text = "上面内容仅房主有权限调整，房客操作后会变成调整建议打到房间内公屏上"
	left.add_child(line1)
	var line2 := Label.new()
	line2.text = "所有人准备后自动开始游戏"
	left.add_child(line2)
	var dep_row := HBoxContainer.new()
	left.add_child(dep_row)
	dep_row.add_child(_lab("副指挥"))
	_deputy = OptionButton.new()
	for i2 in range(DEPUTIES.size()):
		_deputy.add_item(str(DEPUTIES[i2][1]), i2)
	_deputy.item_selected.connect(_on_deputy)
	_touch_target(_deputy)
	dep_row.add_child(_deputy)
	_ready_box = _make_ready_button()
	add_child(_ready_box)
	var add_ai := Button.new()
	add_ai.text = "加人机"
	add_ai.pressed.connect(_on_add_ai)
	left.add_child(add_ai)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(_on_back)
	left.add_child(back)
	_map_view = (load("res://scripts/ui/campaign_starmap_preview.gd") as GDScript).new()
	_map_view.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_map_view.anchor_left = 0.60
	_map_view.anchor_top = 0.04
	_map_view.anchor_right = 0.98
	_map_view.anchor_bottom = 0.48
	_map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_map_view)
	var chat_panel := VBoxContainer.new()
	chat_panel.anchor_left = 0.60
	chat_panel.anchor_top = 0.50
	chat_panel.anchor_right = 0.98
	chat_panel.anchor_bottom = 0.96
	panel.add_child(chat_panel)
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = false
	_chat_log.scroll_following = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.text = ""
	chat_panel.add_child(_chat_log)
	var chat_edit := LineEdit.new()
	chat_edit.placeholder_text = "输入文字，回车发送"
	chat_edit.text_submitted.connect(_on_chat_submit)
	chat_panel.add_child(chat_edit)
	_rebuild()
	if net.is_host and (net.room.get("layout", {}) as Dictionary).is_empty():
		_apply_stock_map(_selected_stock)


func _process(_delta: float) -> void:
	if _sync_pending and not _ui_busy():
		_sync_pending = false
		_apply_room()


func _scan_stock_layouts() -> void:
	_stock_layouts = [{"path": STOCK_LAYOUT, "name": "试验局七系"}]
	var pool_dir := "res://data/board/pool"
	var extras: Array = [
		{"path": pool_dir + "/tour_duel_midpoint.json", "fallback": "双人锦标赛标准图 中点"},
		{"path": pool_dir + "/tour_trio_crowded.json", "fallback": "三人锦标赛标准图 拥挤"},
		{"path": pool_dir + "/tour_duel_four_sides.json", "fallback": "双人人锦标赛标准图 四面"},
	]
	for item in extras:
		var path := str(item["path"])
		if not FileAccess.file_exists(path):
			continue
		var display := str(item["fallback"])
		var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(raw) == TYPE_DICTIONARY:
			var nm := str(raw.get("map_name", raw.get("name", "")))
			if not nm.is_empty():
				display = nm
		_stock_layouts.append({"path": path, "name": display})


func _add_map_controls(left: VBoxContainer) -> void:
	var mode_row := HBoxContainer.new()
	left.add_child(mode_row)
	var stock_btn := Button.new()
	stock_btn.text = "现有地图"
	stock_btn.toggle_mode = true
	stock_btn.button_pressed = true
	mode_row.add_child(stock_btn)
	var rand_btn := Button.new()
	rand_btn.text = "随机生成"
	rand_btn.toggle_mode = true
	mode_row.add_child(rand_btn)
	_stock_list = ItemList.new()
	_stock_list.custom_minimum_size = Vector2(280, 96)
	for item in _stock_layouts:
		_stock_list.add_item(str(item["name"]))
	_stock_list.select(0)
	_stock_list.item_selected.connect(_on_stock_picked)
	left.add_child(_stock_list)
	(preload("res://game/ui/drag_scroll.gd") as GDScript).attach(_stock_list)
	_gen_panel = _build_gen_panel()
	_gen_panel.visible = false
	left.add_child(_gen_panel)
	stock_btn.pressed.connect(func() -> void:
		stock_btn.set_pressed_no_signal(_map_mode != "random")
		rand_btn.set_pressed_no_signal(_map_mode == "random")
		_host_edit("现有地图", _stock_name(_selected_stock), func() -> void:
			_map_mode = "stock"
			stock_btn.set_pressed_no_signal(true)
			rand_btn.set_pressed_no_signal(false)
			_stock_list.visible = true
			_gen_panel.visible = false
			_apply_stock_map(_selected_stock)
		)
	)
	rand_btn.pressed.connect(func() -> void:
		stock_btn.set_pressed_no_signal(_map_mode != "random")
		rand_btn.set_pressed_no_signal(_map_mode == "random")
		_host_edit("随机生成", "开", func() -> void:
			_map_mode = "random"
			stock_btn.set_pressed_no_signal(false)
			rand_btn.set_pressed_no_signal(true)
			_stock_list.visible = false
			_gen_panel.visible = true
			_regen_random()
		)
	)


func _build_gen_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_star_row = HBoxContainer.new()
	box.add_child(_star_row)
	_star_row.add_child(_lab("星系数"))
	for n in STAR_OPTS:
		var b := Button.new()
		b.text = str(n)
		b.toggle_mode = true
		b.button_pressed = n == _star_count
		b.pressed.connect(_on_star_btn.bind(n))
		_touch_target(b)
		_star_row.add_child(b)
	box.add_child(_slider_row("跳桥密度", 0.25, 3.0, 0.05, _lane_density, "跳桥密度", func(v: float) -> void:
		_lane_density = v
		_regen_random()
	))
	box.add_child(_slider_row("平均间距", 60.0, 200.0, 1.0, _avg_spacing, "平均间距", func(v: float) -> void:
		_avg_spacing = v
		_regen_random()
	))
	_ratio = RatioSliderScr.new()
	_ratio.set_ratio(_station_pct, _resource_pct)
	_ratio.set_meta("before_station", _station_pct)
	_ratio.set_meta("before_resource", _resource_pct)
	_ratio.ratio_changed.connect(func(station: float, resource: float) -> void:
		if not bool(_ratio.get_meta("dragging_seen", false)):
			_ratio.set_meta("before_station", _station_pct)
			_ratio.set_meta("before_resource", _resource_pct)
			_ratio.set_meta("dragging_seen", true)
		_slider_drag = 1
		_station_pct = station
		_resource_pct = resource
	)
	_ratio.drag_finished.connect(func(station: float, resource: float) -> void:
		_slider_drag = 0
		_ratio.set_meta("dragging_seen", false)
		var normal := 100.0 - station - resource
		var before_s := float(_ratio.get_meta("before_station", _station_pct))
		var before_r := float(_ratio.get_meta("before_resource", _resource_pct))
		#（数值没变不重生成，房客滑块回到原值）26.10.23 00:24 s
		if is_equal_approx(station, before_s) and is_equal_approx(resource, before_r):
			_ratio.set_ratio(before_s, before_r)
			return
		if not net.is_host:
			_station_pct = before_s
			_resource_pct = before_r
			_ratio.set_ratio(before_s, before_r)
		#（数值没变不重生成，房客滑块回到原值）26.10.23 00:24 e
		#（房客改地图只发公屏建议）26.10.22 15:20 s
		_host_edit("星系比例", "空间站 %.0f%%，资源 %.0f%%，普通 %.0f%%" % [station, resource, normal], func() -> void:
			_station_pct = station
			_resource_pct = resource
			_regen_random()
		)
		#（房客改地图只发公屏建议）26.10.22 15:20 e
	)
	_touch_target(_ratio)
	box.add_child(_ratio)
	var regen := Button.new()
	regen.text = "重新生成"
	regen.pressed.connect(func() -> void:
		_host_edit("重新生成", "再随机一次", _regen_random)
	)
	box.add_child(regen)
	return box


func _slider_row(title: String, lo: float, hi: float, step: float, value: float, item: String, apply: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_lab(title))
	var slider := _make_slider(lo, hi, step, value)
	row.add_child(slider)
	_bind_commit_slider(slider, item, func(v: float) -> void:
		apply.call(v)
	)
	return row


func _make_slider(lo: float, hi: float, step: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(160, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_touch_target(slider)
	return slider


func _bind_commit_slider(slider: HSlider, item: String, apply: Callable) -> void:
	slider.set_meta("before", slider.value)
	slider.set_meta("drag", 0)
	slider.drag_started.connect(func() -> void:
		_slider_drag += 1
		slider.set_meta("drag", 1)
		slider.set_meta("before", slider.value)
	)
	slider.drag_ended.connect(func(changed: bool) -> void:
		_slider_drag = maxi(_slider_drag - 1, 0)
		slider.set_meta("drag", 0)
		var shown := slider.value
		var before := float(slider.get_meta("before", shown))
		#（数值没变不重生成，房客滑块回到原值）26.10.23 00:24 s
		if not changed or is_equal_approx(shown, before):
			if not net.is_host:
				slider.set_value_no_signal(before)
			return
		#（数值没变不重生成，房客滑块回到原值）26.10.23 00:24 e
		_commit_gen_slider(slider, item, shown, before, apply)
	)
	slider.value_changed.connect(func(v: float) -> void:
		if int(slider.get_meta("drag", 0)) == 1:
			return
		var before := float(slider.get_meta("before", v))
		if is_equal_approx(v, before):
			return
		_commit_gen_slider(slider, item, v, before, apply)
	)


func _commit_gen_slider(slider: HSlider, item: String, shown: float, before: float, apply: Callable) -> void:
	#（房客改地图只发公屏建议）26.10.22 15:20 s
	_host_edit(item, _suggest_number(item, shown), func() -> void:
		apply.call(shown)
	)
	if net.is_host:
		slider.set_meta("before", shown)
	else:
		slider.set_value_no_signal(before)
	#（房客改地图只发公屏建议）26.10.22 15:20 e


func _suggest_number(item: String, shown: float) -> String:
	if item == "空间站占比" or item == "资源占比":
		return "%.0f%%" % shown
	if item == "平均间距":
		return "%.0f" % shown
	return "%.2f" % shown


func _on_star_btn(n: int) -> void:
	if _filling:
		return
	_sync_star_buttons()
	_host_edit("星系数", str(n), func() -> void:
		_star_count = n
		_sync_star_buttons()
		_regen_random()
	)


func _sync_star_buttons() -> void:
	if _star_row == null:
		return
	for c in _star_row.get_children():
		if c is Button:
			(c as Button).set_pressed_no_signal((c as Button).text == str(_star_count))


func _stock_name(path: String) -> String:
	for item in _stock_layouts:
		if str(item["path"]) == path:
			return str(item["name"])
	return "现有地图"


func _on_stock_picked(i: int) -> void:
	if _filling or i < 0 or i >= _stock_layouts.size():
		return
	var path := str(_stock_layouts[i]["path"])
	var name := str(_stock_layouts[i]["name"])
	_select_stock_row(_selected_stock)
	_host_edit("现有地图", name, func() -> void:
		_selected_stock = path
		_select_stock_row(path)
		_apply_stock_map(path)
	)


func _select_stock_row(path: String) -> void:
	if _stock_list == null:
		return
	for i in range(_stock_layouts.size()):
		if str(_stock_layouts[i]["path"]) == path:
			_filling = true
			_stock_list.select(i)
			_filling = false
			return


func _apply_stock_map(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return
	net.submit_intent("map", {"layout": raw})


func _regen_random() -> void:
	var layout: Dictionary = ProceduralStarmap.generate({
		"star_count": _star_count,
		"lane_density": _lane_density,
		"avg_spacing": _avg_spacing,
		"station_frac": _station_pct / 100.0,
		"resource_frac": _resource_pct / 100.0,
		"faction_count": _wanted_factions(),
		"seed": randi(),
	})
	net.submit_intent("map", {"layout": layout})


func _bind_slider(slider: HSlider) -> void:
	slider.drag_started.connect(func() -> void: _slider_drag += 1)
	slider.drag_ended.connect(func(_changed: bool) -> void: _slider_drag = maxi(_slider_drag - 1, 0))


func _touch_target(node: Control) -> void:
	if OS.get_name() != "Android" and not OS.has_feature("mobile"):
		return
	var sz := node.custom_minimum_size
	sz.y = maxf(sz.y, 48.0)
	node.custom_minimum_size = sz


func _lab(txt: String) -> Label:
	var lab := Label.new()
	lab.text = txt
	return lab


func _host_edit(item: String, value: String, apply: Callable) -> void:
	if net.is_host:
		apply.call()
	else:
		net.say_verbatim("[全体] %s：希望把%s调整为%s" % [net.local_nick, item, _pretty_suggest(item, value)], "all", 0)
		_rebuild()


func _pretty_suggest(item: String, value: String) -> String:
	var shown := value.strip_edges()
	if shown.contains("lambda") or shown.contains("GDScript") or shown.begins_with("<") or shown.contains("res://") or shown.contains("@"):
		shown = item
	if item == "胜负模式":
		var parts: PackedStringArray = []
		for bit in shown.split(",", false):
			var key := bit.strip_edges()
			match key:
				"gu_dou":
					parts.append("蛊斗")
				"hua_di":
					parts.append("画地")
				"jian_mie":
					parts.append("歼灭")
				_:
					parts.append(key)
		return "、".join(parts)
	if item == "人机副指挥" or item == "副指挥":
		for row in DEPUTIES:
			if str(row[0]) == shown:
				return str(row[1])
		return shown
	if item == "席位":
		return _seat_label(shown)
	return shown


func _seat_label(seat: String) -> String:
	if seat == "spectate" or seat == "":
		return "观战" if seat == "spectate" else seat
	var layout: Dictionary = net.room.get("layout", {})
	for s_v in layout.get("systems", []):
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		if str((s_v as Dictionary).get("id", "")) != seat:
			continue
		var nm := str((s_v as Dictionary).get("name", "")).strip_edges()
		return nm if nm != "" else seat
	return seat


func _make_ready_button() -> Button:
	var btn := Button.new()
	btn.name = "ReadyBtn"
	btn.toggle_mode = true
	btn.text = "准备"
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	btn.offset_left = -140.0
	btn.offset_right = 140.0
	btn.offset_top = -96.0
	btn.offset_bottom = -16.0
	btn.custom_minimum_size = Vector2(280, 64)
	btn.add_theme_font_size_override("font_size", 32)
	btn.z_index = 30
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.16, 0.22, 0.4)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.24, 0.32, 0.4)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.2, 0.42, 0.28, 0.4)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.toggled.connect(_on_ready)
	return btn


func _wanted_factions() -> int:
	var n := 0
	for m_v in net.room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		if str((m_v as Dictionary).get("seat", "")) == "spectate":
			continue
		n += 1
	return clampi(maxi(n, 2), 2, 8)


func _on_limit(v: float) -> void:
	if _filling:
		return
	_host_edit("时限", str(int(v)), func() -> void:
		net.submit_intent("rules", {"limit_s": int(v) * 60})
	)


func _on_goal(v: float) -> void:
	if _filling:
		return
	_host_edit("歼灭数", str(int(v)), func() -> void:
		net.submit_intent("rules", {"annihilate": int(v)})
	)


func _on_scale_btn(n: int) -> void:
	if _filling:
		return
	_sync_scale_buttons(n)
	_host_edit("规模", str(n), func() -> void:
		#（房间规模写回主菜单当前档）26.10.22 22:10 s
		RosterTemplatesScr.set_active_size(n)
		#（房间规模写回主菜单当前档）26.10.22 22:10 e
		net.submit_intent("rules", {"scale": n})
	)


func _sync_scale_buttons(n: int) -> void:
	if _scale_row == null:
		return
	for c in _scale_row.get_children():
		if c is Button:
			(c as Button).set_pressed_no_signal((c as Button).text == str(n))


func _on_fog(on: bool) -> void:
	if _filling:
		return
	_host_edit("战争迷雾", "开" if on else "关", func() -> void:
		net.submit_intent("rules", {"fog": on})
	)


func _on_mode(on: bool, id: String, _cb: CheckBox) -> void:
	if _filling:
		return
	var modes: Array = (net.room.get("modes", []) as Array).duplicate()
	if on and not modes.has(id):
		modes.append(id)
	if not on:
		modes.erase(id)
	if modes.is_empty():
		modes.append("hua_di")
	var mode_ids := PackedStringArray()
	for mid in modes:
		mode_ids.append(str(mid))
	_host_edit("胜负模式", ",".join(mode_ids), func() -> void:
		net.submit_intent("rules", {"modes": modes})
	)


func _on_deputy(idx: int) -> void:
	if _filling:
		return
	var id := str(DEPUTIES[idx][0])
	net.submit_intent("deputy", {"id": id})


func _on_ready(on: bool) -> void:
	if _filling:
		return
	if on:
		var pilots: Array = net.build_local_roster(int(net.room.get("scale", 20)))
		net.submit_intent("roster", {"pilots": pilots, "crew": net.crew_for_roster(pilots)})
	net.submit_intent("ready", {"on": on})


func _on_add_ai() -> void:
	if net.is_host:
		net.submit_intent("add_ai", {"deputy": "yang"})
	else:
		net.submit_intent("suggest", {"item": "人机席", "value": "增加一席"})


func _on_seat(which: int, peer_id: int, ai_index: int, opt: OptionButton) -> void:
	if _filling:
		return
	var seat := str(opt.get_item_metadata(which))
	var mine := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	if net.is_host or (ai_index <= 0 and peer_id == mine):
		net.submit_intent("seat", {"peer": peer_id, "ai": ai_index, "seat": seat})
	else:
		net.submit_intent("suggest", {"item": "席位", "value": _seat_label(seat)})


func _on_urge(peer_id: int) -> void:
	net.submit_intent("urge", {"peer": peer_id})


func _on_ai_deputy(idx: int, ai_index: int) -> void:
	if _filling:
		return
	if not net.is_host:
		net.submit_intent("suggest", {"item": "人机副指挥", "value": str(DEPUTIES[idx][1])})
		return
	var row: Dictionary = net._member_ai(ai_index)
	if row.is_empty():
		return
	row["deputy"] = str(DEPUTIES[idx][0])
	net.room_updated.emit()


func _open_members() -> void:
	var conf := (load("res://game/member_config_overlay.gd") as GDScript).new() as Control
	conf.set_meta("mp_room", true)
	conf.set_meta("mp_scale", int(net.room.get("scale", 20)))
	conf.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	conf.z_index = 40
	add_child(conf)
	#（改名单先撤销准备）26.10.22 21:40 s
	net.submit_intent("ready", {"on": false})
	#（改名单先撤销准备）26.10.22 21:40 e
	if conf.has_signal("size_selected"):
		conf.size_selected.connect(func(n: int) -> void:
			_on_scale_btn(n)
		)
	if conf.has_signal("closed"):
		conf.closed.connect(func() -> void:
			var pilots: Array = net.build_local_roster(int(net.room.get("scale", 20)))
			net.submit_intent("roster", {"pilots": pilots, "crew": net.crew_for_roster(pilots)})
			if is_instance_valid(conf):
				conf.queue_free()
		)


func _on_chat_submit(text: String) -> void:
	var body := text.strip_edges()
	if body == "":
		return
	net.say_verbatim("[全体] %s：%s" % [net.local_nick, body], "all", 0)
	var edit := _chat_log.get_parent().get_child(_chat_log.get_parent().get_child_count() - 1) as LineEdit
	if edit:
		edit.text = ""


func _on_chat(text: String, _scope: String, _faction: int) -> void:
	_chat_log.text += text + "\n"


func _on_fail(msg: String) -> void:
	_status.text = msg


func _on_back() -> void:
	net.disconnect_room()
	closed.emit()
	queue_free()


func _ui_busy() -> bool:
	if _slider_drag > 0 or (_ratio != null and _ratio.dragging):
		return true
	#（聊天和数字框不再挡住整个房间刷新）26.10.23 00:24 s
	#（聊天和数字框不再挡住整个房间刷新）26.10.23 00:24 e
	var stack: Array = [self]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		if node is OptionButton and (node as OptionButton).get_popup().visible:
			return true
		for child in node.get_children():
			stack.append(child)
	return false


func _rebuild() -> void:
	if net == null:
		return
	if _ui_busy():
		_sync_pending = true
		DebugSessionLog.append("UI", "mp_campaign_room._rebuild", "deferred", {"runId": "handtune"})
		return
	_apply_room()


func _apply_room() -> void:
	if net == null:
		return
	_filling = true
	var scale := int(net.room.get("scale", 20))
	_sync_scale_buttons(scale)
	_fog.set_pressed_no_signal(bool(net.room.get("fog", false)))
	var focus: Control = null
	if get_viewport() != null:
		focus = get_viewport().gui_get_focus_owner()
	#（正在改的那一格先保持）26.10.23 00:24 s
	if focus != _limit:
		_limit.set_value_no_signal(clampi(maxi(int(net.room.get("limit_s", 5400)) / 60, 10), 10, 240))
	if focus != _goal:
		_goal.set_value_no_signal(clampi(int(net.room.get("annihilate", 50)), 10, 1000))
	#（正在改的那一格先保持）26.10.23 00:24 e
	var modes: Array = net.room.get("modes", [])
	var left := _scale_row.get_parent() if _scale_row != null else self
	for node in left.get_children():
		if node is HBoxContainer:
			for cb_v in (node as HBoxContainer).get_children():
				if cb_v is CheckBox and (cb_v as CheckBox).has_meta("mode"):
					var id := str((cb_v as CheckBox).get_meta("mode"))
					(cb_v as CheckBox).set_pressed_no_signal(modes.has(id))
	for i2 in range(DEPUTIES.size()):
		var me := net._member(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1)
		if str(me.get("deputy", "yang")) == str(DEPUTIES[i2][0]) and _deputy.selected != i2:
			_deputy.select(i2)
	var spectate := str(net._member(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1).get("seat", "")) == "spectate"
	_ready_box.disabled = spectate
	_ready_box.set_pressed_no_signal(bool(net._member(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1).get("ready", false)))
	_fill_members()
	var layout: Dictionary = net.room.get("layout", {})
	var births: Dictionary = {}
	for m_v in net.room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var fac := int((m_v as Dictionary).get("faction", 0))
		if fac > 0:
			births[fac] = str((m_v as Dictionary).get("seat", ""))
	if _map_view.has_method("set_layout"):
		_map_view.call("set_layout", layout, births)
	var bad := false
	for m2_v in net.room.get("members", []):
		if typeof(m2_v) != TYPE_DICTIONARY:
			continue
		var h := str((m2_v as Dictionary).get("hash", ""))
		if h != "" and h != str(net.room.get("hash", net.rules_hash)):
			bad = true
	_status.text = "内容不一致，不能开始" if bad else net.invite_text()
	for child in get_children():
		if child.has_meta("mp_scale"):
			child.set_meta("mp_scale", scale)
			if child.has_method("_refresh_status"):
				child.call("_refresh_status")
	_filling = false


func _fill_members() -> void:
	for c in _members_box.get_children():
		c.queue_free()
	for c2 in _ai_box.get_children():
		c2.queue_free()
	var stations: Array = net._station_ids(net.room.get("layout", {}))
	for m_v in net.room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if bool(m.get("ai", false)):
			_ai_box.add_child(_member_row(m, stations))
		else:
			_members_box.add_child(_member_row(m, stations))


func _member_row(m: Dictionary, stations: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name := Label.new()
	var tag := "观战" if str(m.get("seat", "")) == "spectate" else "势力%d" % int(m.get("faction", 0))
	name.text = "%s（%s）" % [str(m.get("nick", "")), tag]
	name.custom_minimum_size = Vector2(140, 0)
	row.add_child(name)
	var opt := OptionButton.new()
	opt.add_item("观战", 0)
	opt.set_item_metadata(0, "spectate")
	var sel := 0
	for i in range(stations.size()):
		opt.add_item(_seat_label(str(stations[i])), i + 1)
		opt.set_item_metadata(i + 1, str(stations[i]))
		if str(stations[i]) == str(m.get("seat", "")):
			sel = i + 1
	if str(m.get("seat", "")) == "spectate":
		sel = 0
	opt.select(sel)
	var peer_id := int(m.get("peer", 0))
	var ai_index := int(m.get("ai_index", 0))
	opt.item_selected.connect(_on_seat.bind(peer_id, ai_index, opt))
	_touch_target(opt)
	row.add_child(opt)
	if not bool(m.get("ai", false)) and not bool(m.get("ready", false)) and str(m.get("seat", "")) != "spectate":
		var urge := Button.new()
		urge.text = "催促准备"
		urge.pressed.connect(_on_urge.bind(peer_id))
		row.add_child(urge)
	if bool(m.get("ai", false)):
		var dep := OptionButton.new()
		for i2 in range(DEPUTIES.size()):
			dep.add_item(str(DEPUTIES[i2][1]), i2)
			if str(DEPUTIES[i2][0]) == str(m.get("deputy", "yang")):
				dep.select(i2)
		dep.item_selected.connect(_on_ai_deputy.bind(ai_index))
		_touch_target(dep)
		row.add_child(dep)
	return row
