extends Control
## Custom campaign prep — translucent overlay on the main menu (UI_AND_SHELL §0.2).

signal closed

var embedded := false

const _MapPreviewScr: Script = preload("res://scripts/ui/campaign_starmap_preview.gd")
const RosterTemplatesScr := preload("res://game/board/pilots/roster_templates.gd")
const MemberTableScr := preload("res://game/board/pilots/member_table.gd")

const PANEL_BG := Color(0.08, 0.1, 0.14, 0.15)
const PANEL_BORDER := Color(0.7, 0.75, 0.82, 0.55)
const SCALE_OPTS := [10, 15, 20, 40, 60]
const STAR_OPTS := [12, 16, 20, 24, 30, 40, 50]
const BOOT_PATH := "user://board_boot.json"
const CUSTOM_LAYOUT_PATH := "user://custom_layout.json"
const PREFS_PATH := "user://custom_campaign_prefs.json"
const BOARD_SCENE := "res://game/board_test.tscn"
const MENU_SCENE := "res://game/main_menu.tscn"
const STOCK_LAYOUT := "res://data/board/layout.json"

var _faction_count: int = 3
var _scale: int = 20
var _map_mode: String = "stock"  # stock | random
var _stock_layouts: Array = []
var _selected_stock: String = STOCK_LAYOUT
var _station_pct: float = 35.0
var _resource_pct: float = 35.0
var _star_count: int = 20
var _lane_density: float = 1.0
var _avg_spacing: float = 120.0
var _seed: int = 0
var _preview_layout: Dictionary = {}
var _birth_picks: Dictionary = {}  # faction -> system id
var _deputy_picks: Dictionary = {}  # faction -> deputy id (yang | chuang)
var _auto_spacing: bool = true  # STARMAP §4.2
var _ship_ids: Array = []
var _mode_gu_dou: bool = false
var _mode_hua_di: bool = true
var _mode_jian_mie: bool = false
var _fog_on: bool = false
var _annihilate_goal: int = 50
var _limit_hours: int = 1
var _limit_minutes: int = 30

const DEPUTY_OPTS := [["yang", "\u7f8a"], ["six", "6"], ["chuang", "\u521b"], ["bei", "\u72c8"], ["i", "I"]]
const AUTO_SPACING_RADIUS_MUL := 3.0
const MINUTE_OPTS := [0, 10, 20, 30, 40, 50]

var _root_box: VBoxContainer
var _status: Label
var _start_btn: Button
var _preview_list: ItemList
var _birth_box: VBoxContainer
var _ratio: RatioDualSlider
var _gen_panel: Control
var _map_view: Control
var _annihilate_spin: SpinBox
var _hours_opt: OptionButton
var _mins_opt: OptionButton


func _ready() -> void:
	_load_ships()
	_scan_stock_layouts()
	_load_prefs()
	_build()
	_refresh_preview_from_mode()


func _load_ships() -> void:
	_ship_ids.clear()
	var path := "res://data/board/ships.json"
	if not FileAccess.file_exists(path):
		_ship_ids = ["jdl_haiyan"]
		return
	var raw := JSON.parse_string(FileAccess.get_file_as_string(path))
	var arr: Array = []
	if typeof(raw) == TYPE_DICTIONARY:
		arr = raw.get("ships", [])
	elif typeof(raw) == TYPE_ARRAY:
		arr = raw
	for s in arr:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if bool(s.get("npc_hull", false)):
			continue
		_ship_ids.append(str(s.get("id", "")))
	if _ship_ids.is_empty():
		_ship_ids = ["jdl_haiyan"]


func _scan_stock_layouts() -> void:
	_stock_layouts = [{
		"path": STOCK_LAYOUT,
		"name": "试验局七系",
	}]
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


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	return sb


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if embedded:
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		var bg := TextureRect.new()
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.texture = UiAssets.tex(UiAssets.MAIN_BG)
		if bg.texture == null:
			var c := ColorRect.new()
			c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			c.color = Color(0.04, 0.05, 0.08, 1)
			add_child(c)
		else:
			add_child(bg)
	## Left prep column + top-right starmap preview.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.anchor_right = 0.58
	scroll.offset_right = -8
	add_child(scroll)
	(preload("res://game/ui/drag_scroll.gd") as GDScript).attach(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margin)
	_root_box = VBoxContainer.new()
	_root_box.add_theme_constant_override("separation", 12)
	_root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_root_box)
	var title := Label.new()
	title.text = "自定义战役"
	title.add_theme_font_size_override("font_size", 28)
	_root_box.add_child(title)
	_root_box.add_child(_section_factions())
	_root_box.add_child(_section_modes())
	_root_box.add_child(_section_map())
	_root_box.add_child(_section_birth())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root_box.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_root_box.add_child(row)
	var back := Button.new()
	back.text = "返回主菜单"
	back.pressed.connect(_on_back)
	row.add_child(back)
	_start_btn = Button.new()
	_start_btn.text = "开始战役"
	_start_btn.pressed.connect(_on_start)
	row.add_child(_start_btn)
	_map_view = _MapPreviewScr.new() as Control
	_map_view.name = "StarmapPreview"
	_map_view.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_map_view.anchor_left = 0.60
	_map_view.anchor_top = 0.04
	_map_view.anchor_right = 0.985
	_map_view.anchor_bottom = 0.52
	_map_view.offset_left = 0
	_map_view.offset_top = 0
	_map_view.offset_right = 0
	_map_view.offset_bottom = 0
	_map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_view)
	_update_start_enabled()


func _wrap_panel(inner: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style())
	p.add_child(inner)
	return p


func _section_factions() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var h := Label.new()
	h.text = "对局人数与规模"
	h.add_theme_font_size_override("font_size", 18)
	box.add_child(h)
	var fr := HBoxContainer.new()
	box.add_child(fr)
	fr.add_child(_lab("玩家势力"))
	var fs := SpinBox.new()
	fs.min_value = 2
	fs.max_value = 8
	fs.value = _faction_count
	fs.value_changed.connect(func(v: float) -> void:
		_faction_count = int(v)
		_clamp_factions_to_stations()
		_reset_birth_picks()
		_rebuild_birth_ui()
		_update_start_enabled()
		_save_prefs()
	)
	fr.add_child(fs)
	var sr := HBoxContainer.new()
	box.add_child(sr)
	sr.add_child(_lab("对局规模（每方团员）"))
	for n in SCALE_OPTS:
		var b := Button.new()
		b.text = str(n)
		b.toggle_mode = true
		b.button_pressed = (n == _scale)
		b.pressed.connect(func() -> void:
			_scale = n
			for c in sr.get_children():
				if c is Button:
					(c as Button).button_pressed = (c.text == str(_scale))
			_save_prefs()
		)
		sr.add_child(b)
	return _wrap_panel(box)


func _section_modes() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var h := Label.new()
	h.text = "胜负模式（可多选；先达成任一条件即胜）"
	h.add_theme_font_size_override("font_size", 18)
	box.add_child(h)
	var mr := HBoxContainer.new()
	mr.add_theme_constant_override("separation", 12)
	box.add_child(mr)
	var cb_g := CheckBox.new()
	cb_g.text = "蛊斗"
	cb_g.button_pressed = _mode_gu_dou
	cb_g.toggled.connect(func(v: bool) -> void:
		_mode_gu_dou = v
		_ensure_one_mode()
		_save_prefs()
	)
	mr.add_child(cb_g)
	var cb_h := CheckBox.new()
	cb_h.text = "画地"
	cb_h.button_pressed = _mode_hua_di
	cb_h.toggled.connect(func(v: bool) -> void:
		_mode_hua_di = v
		_ensure_one_mode()
		_save_prefs()
	)
	mr.add_child(cb_h)
	var cb_j := CheckBox.new()
	cb_j.text = "歼灭"
	cb_j.button_pressed = _mode_jian_mie
	cb_j.toggled.connect(func(v: bool) -> void:
		_mode_jian_mie = v
		if _annihilate_spin:
			_annihilate_spin.editable = v
		_ensure_one_mode()
		_save_prefs()
	)
	mr.add_child(cb_j)
	var cb_fog := CheckBox.new()
	cb_fog.text = "战争迷雾"
	cb_fog.button_pressed = _fog_on
	cb_fog.toggled.connect(func(v: bool) -> void:
		_fog_on = v
		_save_prefs()
	)
	mr.add_child(cb_fog)
	mr.add_child(_lab("歼灭目标"))
	_annihilate_spin = SpinBox.new()
	_annihilate_spin.min_value = 10
	_annihilate_spin.max_value = 1000
	_annihilate_spin.step = 1
	_annihilate_spin.value = _annihilate_goal
	_annihilate_spin.editable = _mode_jian_mie
	_annihilate_spin.value_changed.connect(func(v: float) -> void:
		_annihilate_goal = clampi(int(v), 10, 1000)
		_save_prefs()
	)
	mr.add_child(_annihilate_spin)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 8)
	box.add_child(tr)
	tr.add_child(_lab("时限（仅画地结算）"))
	_hours_opt = OptionButton.new()
	for hr in range(0, 25):
		_hours_opt.add_item("%d 小时" % hr, hr)
	_hours_opt.select(clampi(_limit_hours, 0, 24))
	_hours_opt.item_selected.connect(func(idx: int) -> void:
		_limit_hours = idx
		_clamp_limit()
		_sync_limit_menus()
		_save_prefs()
	)
	tr.add_child(_hours_opt)
	_mins_opt = OptionButton.new()
	for mi in range(MINUTE_OPTS.size()):
		_mins_opt.add_item("%d 分" % MINUTE_OPTS[mi], mi)
		if MINUTE_OPTS[mi] == _limit_minutes:
			_mins_opt.select(mi)
	_mins_opt.item_selected.connect(func(idx: int) -> void:
		_limit_minutes = int(MINUTE_OPTS[idx])
		_clamp_limit()
		_sync_limit_menus()
		_save_prefs()
	)
	tr.add_child(_mins_opt)
	_clamp_limit()
	_sync_limit_menus()
	return _wrap_panel(box)


func _ensure_one_mode() -> void:
	if not _mode_gu_dou and not _mode_hua_di and not _mode_jian_mie:
		_mode_hua_di = true


func _match_limit_s() -> int:
	return _limit_hours * 3600 + _limit_minutes * 60


func _clamp_limit() -> void:
	var s := _match_limit_s()
	if s < 600:
		_limit_hours = 0
		_limit_minutes = 10
	elif s > 86400:
		_limit_hours = 24
		_limit_minutes = 0


func _sync_limit_menus() -> void:
	if _hours_opt:
		_hours_opt.select(clampi(_limit_hours, 0, 24))
	if _mins_opt:
		var want := _limit_minutes
		for i in range(MINUTE_OPTS.size()):
			if MINUTE_OPTS[i] == want:
				_mins_opt.select(i)
				break


func _selected_modes() -> Array:
	var out: Array = []
	if _mode_gu_dou:
		out.append("gu_dou")
	if _mode_hua_di:
		out.append("hua_di")
	if _mode_jian_mie:
		out.append("jian_mie")
	if out.is_empty():
		out.append("hua_di")
	return out


func _load_prefs() -> void:
	if not FileAccess.file_exists(PREFS_PATH):
		return
	var raw = JSON.parse_string(FileAccess.get_file_as_string(PREFS_PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var d: Dictionary = raw
	_faction_count = clampi(int(d.get("faction_count", _faction_count)), 2, 8)
	_scale = int(d.get("scale", _scale))
	if not SCALE_OPTS.has(_scale):
		_scale = 20
	_map_mode = str(d.get("map_mode", _map_mode))
	_selected_stock = str(d.get("selected_stock", _selected_stock))
	_station_pct = float(d.get("station_pct", _station_pct))
	_resource_pct = float(d.get("resource_pct", _resource_pct))
	_star_count = int(d.get("star_count", _star_count))
	_lane_density = float(d.get("lane_density", _lane_density))
	_avg_spacing = float(d.get("avg_spacing", _avg_spacing))
	_auto_spacing = bool(d.get("auto_spacing", _auto_spacing))
	_mode_gu_dou = bool(d.get("mode_gu_dou", _mode_gu_dou))
	_mode_hua_di = bool(d.get("mode_hua_di", _mode_hua_di))
	_mode_jian_mie = bool(d.get("mode_jian_mie", _mode_jian_mie))
	_fog_on = bool(d.get("fog_of_war", _fog_on))
	_annihilate_goal = clampi(int(d.get("annihilate_goal", _annihilate_goal)), 10, 1000)
	_limit_hours = clampi(int(d.get("limit_hours", _limit_hours)), 0, 24)
	_limit_minutes = int(d.get("limit_minutes", _limit_minutes))
	if not MINUTE_OPTS.has(_limit_minutes):
		_limit_minutes = 30
	_clamp_limit()
	_ensure_one_mode()
	var deps = d.get("deputies", {})
	if typeof(deps) == TYPE_DICTIONARY:
		_deputy_picks.clear()
		for k in deps.keys():
			_deputy_picks[int(k)] = str(deps[k])


func _save_prefs() -> void:
	var deps: Dictionary = {}
	for fac in range(1, _faction_count + 1):
		deps[str(fac)] = str(_deputy_picks.get(fac, "chuang" if fac == 2 else "yang"))
	var data := {
		"faction_count": _faction_count,
		"scale": _scale,
		"map_mode": _map_mode,
		"selected_stock": _selected_stock,
		"station_pct": _station_pct,
		"resource_pct": _resource_pct,
		"star_count": _star_count,
		"lane_density": _lane_density,
		"avg_spacing": _avg_spacing,
		"auto_spacing": _auto_spacing,
		"mode_gu_dou": _mode_gu_dou,
		"mode_hua_di": _mode_hua_di,
		"mode_jian_mie": _mode_jian_mie,
		"annihilate_goal": _annihilate_goal,
		"limit_hours": _limit_hours,
		"limit_minutes": _limit_minutes,
		"fog_of_war": _fog_on,
		"deputies": deps,
	}
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func _section_map() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var h := Label.new()
	h.text = "地图"
	h.add_theme_font_size_override("font_size", 18)
	box.add_child(h)
	var mode_row := HBoxContainer.new()
	box.add_child(mode_row)
	var stock_btn := Button.new()
	stock_btn.text = "现有地图"
	stock_btn.toggle_mode = true
	stock_btn.button_pressed = true
	var rand_btn := Button.new()
	rand_btn.text = "随机生成"
	rand_btn.toggle_mode = true
	mode_row.add_child(stock_btn)
	mode_row.add_child(rand_btn)
	var stock_list := ItemList.new()
	stock_list.custom_minimum_size = Vector2(320, 140)
	for item in _stock_layouts:
		stock_list.add_item(str(item["name"]))
	stock_list.select(0)
	stock_list.item_selected.connect(func(i: int) -> void:
		_selected_stock = str(_stock_layouts[i]["path"])
		_refresh_preview_from_mode()
		_save_prefs()
	)
	## Restore stock selection index from prefs.
	for si in range(_stock_layouts.size()):
		if str(_stock_layouts[si]["path"]) == _selected_stock:
			stock_list.select(si)
			break
	box.add_child(stock_list)
	(preload("res://game/ui/drag_scroll.gd") as GDScript).attach(stock_list)
	_gen_panel = _build_gen_panel()
	_gen_panel.visible = false
	box.add_child(_gen_panel)
	stock_btn.button_pressed = (_map_mode != "random")
	rand_btn.button_pressed = (_map_mode == "random")
	stock_list.visible = (_map_mode != "random")
	_gen_panel.visible = (_map_mode == "random")
	stock_btn.pressed.connect(func() -> void:
		_map_mode = "stock"
		stock_btn.button_pressed = true
		rand_btn.button_pressed = false
		stock_list.visible = true
		_gen_panel.visible = false
		_refresh_preview_from_mode()
		_save_prefs()
	)
	rand_btn.pressed.connect(func() -> void:
		_map_mode = "random"
		stock_btn.button_pressed = false
		rand_btn.button_pressed = true
		stock_list.visible = false
		_gen_panel.visible = true
		_regen()
		_save_prefs()
	)
	var sp_row := HBoxContainer.new()
	sp_row.add_theme_constant_override("separation", 8)
	box.add_child(sp_row)
	var sp_btn := CheckButton.new()
	sp_btn.text = "星系间距自动优化（最近两系 = 3.0 × 完全展开半径）"
	sp_btn.button_pressed = _auto_spacing
	sp_btn.toggled.connect(func(v: bool) -> void:
		_auto_spacing = v
		_update_start_enabled()
		_save_prefs()
	)
	sp_row.add_child(sp_btn)
	_preview_list = ItemList.new()
	_preview_list.custom_minimum_size = Vector2(480, 180)
	box.add_child(_lab("预览（星系 / 类型 / 连线数）"))
	box.add_child(_preview_list)
	(preload("res://game/ui/drag_scroll.gd") as GDScript).attach(_preview_list)
	return _wrap_panel(box)


func _build_gen_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var sc := HBoxContainer.new()
	box.add_child(sc)
	sc.add_child(_lab("星系数"))
	for n in STAR_OPTS:
		var b := Button.new()
		b.text = str(n)
		b.toggle_mode = true
		b.button_pressed = (n == _star_count)
		b.pressed.connect(func() -> void:
			_star_count = n
			for c in sc.get_children():
				if c is Button:
					(c as Button).button_pressed = (c.text == str(_star_count))
			_regen()
		)
		sc.add_child(b)
	var dens := HBoxContainer.new()
	box.add_child(dens)
	dens.add_child(_lab("跳桥密度"))
	var dens_sl := HSlider.new()
	dens_sl.min_value = 0.25
	dens_sl.max_value = 3.0
	dens_sl.step = 0.05
	dens_sl.value = _lane_density
	dens_sl.custom_minimum_size = Vector2(200, 24)
	dens_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dens_sl.value_changed.connect(func(v: float) -> void:
		_lane_density = v
		_regen()
	)
	dens.add_child(dens_sl)
	var sp := HBoxContainer.new()
	box.add_child(sp)
	sp.add_child(_lab("平均间距"))
	var sp_sl := HSlider.new()
	sp_sl.min_value = 60.0
	sp_sl.max_value = 200.0
	sp_sl.step = 1.0
	sp_sl.value = _avg_spacing
	sp_sl.custom_minimum_size = Vector2(200, 24)
	sp_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp_sl.value_changed.connect(func(v: float) -> void:
		_avg_spacing = v
		_regen()
	)
	sp.add_child(sp_sl)
	_ratio = RatioDualSlider.new()
	_ratio.set_ratio(_station_pct, _resource_pct)
	_ratio.drag_finished.connect(func(station: float, resource: float) -> void:
		_station_pct = station
		_resource_pct = resource
		_regen()
	)
	box.add_child(_ratio)
	var regen := Button.new()
	regen.text = "重新生成"
	regen.pressed.connect(_regen)
	box.add_child(regen)
	return box


func _section_birth() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var h := Label.new()
	h.text = "出生星系（仅空间站系；自动预填互相最远；旁选副指挥官）"
	h.add_theme_font_size_override("font_size", 18)
	box.add_child(h)
	_birth_box = VBoxContainer.new()
	_birth_box.add_theme_constant_override("separation", 6)
	box.add_child(_birth_box)
	return _wrap_panel(box)


func _lab(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _regen() -> void:
	_preview_layout = ProceduralStarmap.generate({
		"star_count": _star_count,
		"lane_density": _lane_density,
		"avg_spacing": _avg_spacing,
		"station_frac": _station_pct / 100.0,
		"resource_frac": _resource_pct / 100.0,
		"faction_count": _faction_count,
		"seed": _seed,
	})
	var _gen: Dictionary = _preview_layout.get("gen", {}) as Dictionary
	_seed = int(_gen.get("seed", _seed)) + 1
	_fill_preview(_preview_layout)
	_clamp_factions_to_stations()
	_reset_birth_picks()
	_rebuild_birth_ui()
	_update_start_enabled()


func _refresh_preview_from_mode() -> void:
	if _map_mode == "random":
		_regen()
		return
	var path := _selected_stock
	if not FileAccess.file_exists(path):
		_preview_layout = {}
		_preview_list.clear()
		_update_start_enabled()
		return
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	_preview_layout = raw if typeof(raw) == TYPE_DICTIONARY else {}
	_fill_preview(_preview_layout)
	_clamp_factions_to_stations()
	_reset_birth_picks()
	_rebuild_birth_ui()
	_update_start_enabled()


func _fill_preview(layout: Dictionary) -> void:
	_preview_list.clear()
	for s in layout.get("systems", []):
		var links: Array = s.get("links", [])
		_preview_list.add_item("%s | %s | 连线 %d" % [str(s.get("name", s.get("id"))), str(s.get("kind", "?")), links.size()])
	_refresh_map_view()


func _refresh_map_view() -> void:
	if _map_view != null and _map_view.has_method("set_layout"):
		_map_view.call("set_layout", _preview_layout, _birth_picks)


func _station_ids() -> Array:
	var out: Array = []
	for s in _preview_layout.get("systems", []):
		if str(s.get("kind", "")) == "station_system":
			out.append(str(s.get("id")))
	return out


func _clamp_factions_to_stations() -> void:
	var n := _station_ids().size()
	if n > 0 and _faction_count > n:
		_faction_count = n
		_status.text = "该图仅有 %d 个空间站系，势力数已限制为 %d。" % [n, n]


func _reset_birth_picks() -> void:
	_birth_picks.clear()
	_auto_fill_birth_picks()
	for f in range(1, _faction_count + 1):
		if not _deputy_picks.has(f):
			_deputy_picks[f] = "chuang" if f == 2 else "yang"
	_refresh_map_view()


func _sys_pos(sid: String) -> Vector2:
	for s in _preview_layout.get("systems", []):
		if str(s.get("id", "")) == sid:
			var pos: Array = s.get("pos", [0.0, 0.0])
			return Vector2(float(pos[0]), float(pos[1] if pos.size() > 1 else 0.0))
	return Vector2.ZERO


func _auto_fill_birth_picks() -> void:
	## UI_AND_SHELL §0.2: greedy farthest-point set over station systems.
	var stations := _station_ids()
	if stations.size() < _faction_count or _faction_count <= 0:
		return
	var chosen: Array = []
	if stations.size() == 1:
		chosen = [str(stations[0])]
	else:
		var best_d := -1.0
		var pair: Array = []
		for i in range(stations.size()):
			for j in range(i + 1, stations.size()):
				var d := _sys_pos(str(stations[i])).distance_to(_sys_pos(str(stations[j])))
				if d > best_d:
					best_d = d
					pair = [str(stations[i]), str(stations[j])]
		chosen = pair
	while chosen.size() < _faction_count:
		var best_sid := ""
		var best_min := -1.0
		for sid in stations:
			if chosen.has(str(sid)):
				continue
			var mn := INF
			for c in chosen:
				mn = minf(mn, _sys_pos(str(sid)).distance_to(_sys_pos(str(c))))
			if mn > best_min:
				best_min = mn
				best_sid = str(sid)
		if best_sid == "":
			break
		chosen.append(best_sid)
	for f in range(1, _faction_count + 1):
		if f - 1 < chosen.size():
			_birth_picks[f] = str(chosen[f - 1])


func _rebuild_birth_ui() -> void:
	for c in _birth_box.get_children():
		c.queue_free()
	var stations := _station_ids()
	for f in range(1, _faction_count + 1):
		var row := HBoxContainer.new()
		_birth_box.add_child(row)
		row.add_child(_lab("势力%d" % f))
		var opt := OptionButton.new()
		opt.add_item("（未选）", 0)
		var i := 1
		for sid in stations:
			var nm: String = sid
			for s in _preview_layout.get("systems", []):
				if str(s.get("id")) == sid:
					nm = str(s.get("name", sid))
					break
			opt.add_item(nm, i)
			opt.set_item_metadata(i, sid)
			i += 1
		var fac := f
		opt.item_selected.connect(func(idx: int) -> void:
			if idx <= 0:
				_birth_picks.erase(fac)
			else:
				var sid2: String = str(opt.get_item_metadata(idx))
				# enforce unique
				for k in _birth_picks.keys():
					if int(k) != fac and str(_birth_picks[k]) == sid2:
						_birth_picks.erase(k)
				_birth_picks[fac] = sid2
				_rebuild_birth_ui()
			_refresh_map_view()
			_update_start_enabled()
		)
		if _birth_picks.has(f):
			var want := str(_birth_picks[f])
			for j in range(opt.item_count):
				if j > 0 and str(opt.get_item_metadata(j)) == want:
					opt.select(j)
					break
		row.add_child(opt)
		row.add_child(_lab("副指挥官"))
		var dep := OptionButton.new()
		var cur_dep := str(_deputy_picks.get(f, "yang"))
		for di in range(DEPUTY_OPTS.size()):
			dep.add_item(str(DEPUTY_OPTS[di][1]), di)
			dep.set_item_metadata(di, str(DEPUTY_OPTS[di][0]))
			if str(DEPUTY_OPTS[di][0]) == cur_dep:
				dep.select(di)
		var fac_d := f
		dep.item_selected.connect(func(idx: int) -> void:
			_deputy_picks[fac_d] = str(dep.get_item_metadata(idx))
			_save_prefs()
		)
		row.add_child(dep)


func _birth_ok() -> bool:
	var stations := _station_ids()
	if stations.size() < _faction_count:
		return false
	if _birth_picks.size() < _faction_count:
		return false
	var used: Dictionary = {}
	for k in _birth_picks.keys():
		var sid := str(_birth_picks[k])
		if used.has(sid):
			return false
		used[sid] = true
	return true


func _update_start_enabled() -> void:
	var ok := _birth_ok() and not _preview_layout.is_empty()
	if _start_btn:
		_start_btn.disabled = not ok
	if _status:
		if _preview_layout.is_empty():
			_status.text = "请选择或生成地图。"
		elif _station_ids().size() < _faction_count:
			_status.text = "空间站系不足以容纳当前势力数。"
		elif not _birth_ok():
			_status.text = "请为每个玩家势力选择不重复的出生空间站系。"
		else:
			_status.text = "准备就绪。"


func _on_back() -> void:
	if embedded:
		closed.emit()
		queue_free()
		return
	get_tree().change_scene_to_file(MENU_SCENE)


func _clear_mp_residue() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for name in ["mp_campaign_live", "mp_campaign_tables.json", "mp_campaign_progress.json"]:
		if dir.file_exists(name):
			dir.remove(name)


func _on_start() -> void:
	# #region agent log
	DebugSessionLog.append("UI", "custom_campaign._on_start", "solo_start", {
		"runId": "post-fix", "hypothesisId": "SOLO", "birth": _birth_ok(),
	})
	# #endregion
	_clear_mp_residue()
	if not _birth_ok():
		return
	var layout: Dictionary = _preview_layout.duplicate(true)
	if _auto_spacing:
		_apply_auto_spacing(layout)
	var opening: Dictionary = {}
	for fac in _birth_picks.keys():
		opening[str(_birth_picks[fac])] = int(fac)
	layout["opening_stations"] = opening
	layout["viewer_faction"] = 1
	var deps: Dictionary = {}
	for fac2 in range(1, _faction_count + 1):
		deps[str(fac2)] = str(_deputy_picks.get(fac2, "chuang" if fac2 == 2 else "yang"))
	layout["deputies"] = deps
	layout["match_modes"] = _selected_modes()
	layout["match_limit_s"] = _match_limit_s()
	layout["annihilate_goal"] = _annihilate_goal
	layout["fog_of_war"] = _fog_on
	var ai_facs: Array = []
	for ai_fac in range(2, _faction_count + 1):
		ai_facs.append(ai_fac)
	layout["ai_factions"] = ai_facs
	layout["pilots"] = _build_pilots()
	layout["roster_applied"] = true
	_save_prefs()
	var f := FileAccess.open(CUSTOM_LAYOUT_PATH, FileAccess.WRITE)
	if f == null:
		_status.text = "无法写入自定义布局。"
		return
	f.store_string(JSON.stringify(layout))
	f.close()
	var boot := {"layout": CUSTOM_LAYOUT_PATH}
	var bf := FileAccess.open(BOOT_PATH, FileAccess.WRITE)
	if bf:
		bf.store_string(JSON.stringify(boot))
		bf.close()
	get_tree().change_scene_to_file(BOARD_SCENE)


func _apply_auto_spacing(layout: Dictionary) -> void:
	## STARMAP §4.2: uniform scale so nearest pair = 3.0 × fully-expanded ring_outer.
	var systems: Array = layout.get("systems", [])
	if systems.size() < 2:
		return
	var pts: Array = []
	var centroid := Vector2.ZERO
	for s in systems:
		var pos: Array = s.get("pos", [0.0, 0.0])
		var p := Vector2(float(pos[0]), float(pos[1] if pos.size() > 1 else 0.0))
		pts.append(p)
		centroid += p
	centroid /= float(pts.size())
	var d_min := INF
	for i in range(pts.size()):
		for j in range(i + 1, pts.size()):
			d_min = minf(d_min, (pts[i] as Vector2).distance_to(pts[j]))
	if d_min < 0.001 or d_min == INF:
		return
	var r_full := float(layout.get("ring_outer", 26.0))
	var k := (AUTO_SPACING_RADIUS_MUL * r_full) / d_min
	for i2 in range(systems.size()):
		var p2: Vector2 = centroid + ((pts[i2] as Vector2) - centroid) * k
		systems[i2]["pos"] = [snappedf(p2.x, 0.01), snappedf(p2.y, 0.01)]
	layout["auto_spacing_k"] = k


func _build_pilots() -> Array:
	## SHIPS §7.2: faction 1 uses the player template; AI factions draw independently.
	var members: Dictionary = {}
	for row in MemberTableScr.load_merged():
		if typeof(row) == TYPE_DICTIONARY:
			members[str(row.get("id", ""))] = row
	var r := RandomNumberGenerator.new()
	r.randomize()
	var out: Array = []
	for fac in range(1, _faction_count + 1):
		var home := str(_birth_picks.get(fac, ""))
		var is_ai := fac != 1
		var res: Dictionary = RosterTemplatesScr.resolve_ai(_scale, r) if is_ai else RosterTemplatesScr.resolve(_scale, r)
		var ids: PackedStringArray = res["ids"]
		var starters: Dictionary = res["starters"]
		for n in range(ids.size()):
			var mid := str(ids[n])
			var mem: Dictionary = members.get(mid, {})
			var ship_id := ""
			if is_ai and not _ship_ids.is_empty():
				ship_id = str(_ship_ids[r.randi_range(0, _ship_ids.size() - 1)])
			else:
				ship_id = str(mem.get("default_ship", "")).strip_edges()
			if ship_id == "":
				ship_id = str(_ship_ids[n % _ship_ids.size()]) if not _ship_ids.is_empty() else "gila_cc2"
			var nm := str(mem.get("name", "军团%d-%d" % [fac, n + 1]))
			out.append({
				"id": "f%d_p%d" % [fac, n + 1],
				"name": nm,
				"faction": fac,
				"home": home,
				"ship": ship_id,
				"member_id": mid,
				"cell_kind": "station",
				"starter": starters.has(mid),
			})
	DebugSessionLog.append("ROSTER", "custom_campaign._build_pilots", "built", {
		"scale": _scale, "factions": _faction_count, "pilots": out.size(), "runId": "roster-fill"
	})
	return out
