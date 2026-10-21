extends Window
## Full-screen balance editor. Pauses a live match and restores the previous pause on close.

const DevBalance := preload("res://game/board/dev_balance.gd")
const EquipIconScr := preload("res://game/board/equip_icon.gd")
const SHIP_ART := preload("res://art_modules/eve_ship_art/scripts/eve_ship_art_module.gd")
const TAB_NAMES := ["舰船血量", "舰船攻击力", "模型比例", "隐藏装备", "装备数值", "对局控制", "驾驶员增益"]
const SCALE_SPIN_W := 0.7
const SCALE_CELL_VIEW := Vector2(240, 170)
const SCALE_TRAIL_LIFE := 1.2
const SCALE_TRAIL_SPEED_MUL := 0.55
const SCALE_TRAIL_STAMP := 0.05
const SCALE_TRAIL_HALF_W := 0.09
const SCALE_EULER_STEP := 15.0
const AXIS_BTN_W := 28.0
const EQUIP_SPIN_W := 100.0

const TON_LABEL := {
	"frigate": "护卫",
	"destroyer": "驱逐",
	"cruiser": "巡洋",
	"battlecruiser": "战巡",
	"battleship": "战列",
}
const CAP_KINDS: Array[int] = [
	BoardTypes.CellKind.GATE,
	BoardTypes.CellKind.RESOURCE,
	BoardTypes.CellKind.STATION,
	BoardTypes.CellKind.SOV,
]
const CAP_LABEL := {
	BoardTypes.CellKind.GATE: "星门",
	BoardTypes.CellKind.RESOURCE: "资源",
	BoardTypes.CellKind.STATION: "空间站",
	BoardTypes.CellKind.SOV: "主权",
}

var _tabs: HBoxContainer
var _left: ItemList
var _right: VBoxContainer
var _tab := 0
var _ships: Array = []
var _equips: Array = []
var _chart: Array = []
var _equip_defs: Dictionary = {}
var _loading := false
var _scale_ships: Array = []
var _scale_cells: Array = []
var _scale_trail_mat: StandardMaterial3D = null
var _scale_gizmo_sphere: SphereMesh = null
var _scale_gizmo_ring: ArrayMesh = null

const _HP_COLORS := {
	"shield": Color(0.24, 0.65, 1.0, 0.94),
	"armor": Color(0.95, 0.73, 0.22, 0.94),
	"structure": Color(0.9, 0.3, 0.25, 0.94),
}
const _DPH_COLOR := Color(0.35, 0.75, 0.95, 0.94)
const _PD_PALETTE: Array[Color] = [
	Color(0.95, 0.45, 0.15, 0.94),
	Color(0.55, 0.85, 0.25, 0.94),
	Color(0.72, 0.38, 0.92, 0.94),
	Color(0.95, 0.78, 0.22, 0.94),
	Color(0.92, 0.32, 0.48, 0.94),
	Color(0.25, 0.82, 0.72, 0.94),
]

func _ready() -> void:
	title = "全局数据调整"
	borderless = false
	exclusive = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_requested.connect(_close)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 12)
	root.add_theme_constant_override("margin_right", 12)
	root.add_theme_constant_override("margin_top", 8)
	root.add_theme_constant_override("margin_bottom", 8)
	add_child(root)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(box)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	box.add_child(_tabs)
	for i in TAB_NAMES.size():
		var b := Button.new()
		b.text = TAB_NAMES[i]
		b.pressed.connect(_select_tab.bind(i))
		_tabs.add_child(b)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(_close)
	_tabs.add_child(close)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	box.add_child(split)
	_left = ItemList.new()
	_left.custom_minimum_size = Vector2(220, 0)
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.item_selected.connect(_on_left)
	split.add_child(_left)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("separation", 6)
	scroll.add_child(_right)

func present() -> void:
	DevBalance.load()
	_ships = DevBalance.playable_ships()
	_scale_ships = DevBalance.all_ships()
	_equips = DevBalance.secondary_equipment()
	var board = _board()
	if board != null and board.has_method("dev_pause_for_data"):
		board.dev_pause_for_data(true)
	var vp := Vector2i(get_tree().root.size)
	size = vp
	popup_centered()
	_select_tab(_tab)
	_log_ui("打开")

func _close() -> void:
	var board = _board()
	if board != null and board.has_method("dev_pause_for_data"):
		board.dev_pause_for_data(false)
	_clear_scale_previews()
	hide()
	_log_ui("关闭")

func _select_tab(i: int) -> void:
	_tab = i
	_left.visible = i == 3 or i == 4
	_fill_left()
	_fill_right()

func _fill_left() -> void:
	_left.clear()
	if _tab == 3:
		for s in _ships:
			_left.add_item("%s" % str(s.get("name", s.get("id", ""))))
	elif _tab == 4:
		_left.fixed_icon_size = Vector2(28, 28)
		var ei := 0
		for e in _equips:
			_left.add_item("%s" % str(e.get("name", e.get("id", ""))))
			_left.set_item_icon(ei, EquipIconScr.for_row(e))
			ei += 1
	if _tab != 4:
		_left.fixed_icon_size = Vector2.ZERO
	if _left.item_count > 0:
		_left.select(0)

func _on_left(_idx: int) -> void:
	_fill_right()

func _fill_right() -> void:
	_loading = true
	_chart.clear()
	_clear_scale_previews()
	for c in _right.get_children():
		_right.remove_child(c)
		c.free()
	match _tab:
		0:
			_fill_hp()
		1:
			_fill_dph()
		2:
			_fill_scale()
		3:
			_fill_hidden()
		4:
			_fill_equip()
		5:
			_fill_match()
		6:
			_note("目前没有驾驶员增益数据。")
	_loading = false
	_log_ui("页签")

func _fill_hp() -> void:
	for s in _sorted_ships():
		_add_hp_row(s)
	call_deferred("_refresh_chart")

func _add_hp_row(ship: Dictionary) -> void:
	var sid := str(ship.get("id", ""))
	var vals := _live_hp(sid, ship)
	var row := _chart_row(ship)
	var on_shield := func(v: float, ship_id: String) -> void:
		_store_hp(ship_id, "shield", v)
	var on_armor := func(v: float, ship_id: String) -> void:
		_store_hp(ship_id, "armor", v)
	var on_struct := func(v: float, ship_id: String) -> void:
		_store_hp(ship_id, "structure", v)
	row.add_child(_compact_spin("盾", float(vals["shield"]), on_shield.bind(sid)))
	row.add_child(_compact_spin("甲", float(vals["armor"]), on_armor.bind(sid)))
	row.add_child(_compact_spin("结构", float(vals["structure"]), on_struct.bind(sid)))
	var space := _bar_space()
	var layers := {}
	for key in ["shield", "armor", "structure"]:
		var rect := ColorRect.new()
		rect.color = _HP_COLORS[key]
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		space.add_child(rect)
		layers[key] = rect
	row.add_child(space)
	_chart.append({"kind": "hp", "sid": sid, "ship": ship, "space": space, "layers": layers})

func _fill_dph() -> void:
	var max_spins := 1
	for s0 in _sorted_ships():
		var seen0 := {}
		var n0 := 0
		for part0 in _attack_parts(s0):
			var eid0 := str(part0["eid"])
			if seen0.has(eid0):
				continue
			seen0[eid0] = true
			n0 += 1
		max_spins = maxi(max_spins, n0)
	var spin_w := float(max_spins) * EQUIP_SPIN_W + float(maxi(max_spins - 1, 0)) * 4.0
	for s in _sorted_ships():
		_add_dph_row(s, spin_w)
	call_deferred("_refresh_chart")

func _add_dph_row(ship: Dictionary, spin_w: float) -> void:
	var sid := str(ship.get("id", ""))
	var row := _chart_row(ship)
	var on_dph := func(v: float, ship_id: String) -> void:
		if _loading:
			return
		DevBalance.dph[ship_id] = v
		_commit_hidden()
		_refresh_chart()
	row.add_child(_compact_spin("dph", float(DevBalance.dph.get(sid, 1.0)), on_dph.bind(sid), 0.0, 100.0, 0.05))
	var spin_row := HBoxContainer.new()
	spin_row.add_theme_constant_override("separation", 4)
	spin_row.custom_minimum_size = Vector2(spin_w, 28)
	spin_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var space := _bar_space()
	var segs: Array = []
	var seen_eid := {}
	for part in _attack_parts(ship):
		var eid := str(part["eid"])
		var spin: SpinBox = null
		if not seen_eid.has(eid):
			seen_eid[eid] = true
			spin = _equip_spin(eid)
			spin_row.add_child(spin)
		var rect := _seg_rect(part["color"], str(part["name"]))
		space.add_child(rect)
		segs.append({
			"rect": rect,
			"eid": eid,
			"kind": str(part["kind"]),
			"pd_mul": float(part["pd_mul"]),
			"spin": spin,
		})
	row.add_child(spin_row)
	row.add_child(space)
	_chart.append({"kind": "dph", "sid": sid, "space": space, "segs": segs})

func _fill_scale() -> void:
	var legend := Label.new()
	legend.text = "橙点=炮口（SOF 炮位，特效发出）  黄点=中心（命中落点）  青圈=外接球赤道（未中切线擦过）"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_theme_color_override("font_color", Color(0.82, 0.88, 0.94, 0.92))
	_right.add_child(legend)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_child(grid)
	for s in _sorted_scale_ships():
		grid.add_child(_make_scale_cell(s))

func _sorted_scale_ships() -> Array:
	var rows: Array = _scale_ships.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var wa := BoardTypes.tonnage_weight(str(a.get("tonnage", "")))
		var wb := BoardTypes.tonnage_weight(str(b.get("tonnage", "")))
		if wa == wb:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return wa < wb
	)
	return rows

func _commit_scale(sid: String, value: float) -> void:
	DevBalance.set_model_scale(sid, value)
	DevBalance.save()
	_refit_scale_cell(sid)
	var board = _board()
	if board != null and board.has_method("dev_rescale_hull"):
		board.dev_rescale_hull(sid)
	for n in get_tree().get_nodes_in_group("evertbs_menu_skirmish"):
		if n.has_method("dev_rescale_hull"):
			n.dev_rescale_hull(sid)

func _chart_row(ship: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 36
	_right.add_child(row)
	row.add_child(_tonnage_icon(str(ship.get("tonnage", "frigate"))))
	var name_lab := Label.new()
	name_lab.text = str(ship.get("name", ship.get("id", "")))
	name_lab.custom_minimum_size = Vector2(120, 0)
	name_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_lab)
	return row

func _bar_space() -> Control:
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.custom_minimum_size = Vector2(80, 28)
	space.clip_contents = true
	space.resized.connect(_refresh_chart)
	return space

func _tonnage_icon(ton: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(28, 28)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var path := "res://assets/ui/sprites/tonnage/%s_32.png" % ton
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/sprites/tonnage/destroyer_32.png"
	if ResourceLoader.exists(path):
		rect.texture = load(path)
	return rect

func _sorted_ships() -> Array:
	var rows: Array = _ships.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var wa := BoardTypes.tonnage_weight(str(a.get("tonnage", "")))
		var wb := BoardTypes.tonnage_weight(str(b.get("tonnage", "")))
		if wa == wb:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return wa < wb
	)
	return rows

func _ensure_equip() -> void:
	if not _equip_defs.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/board/equipment.json"))
	if typeof(parsed) == TYPE_DICTIONARY:
		_equip_defs = parsed

func _hidden_blocked(sid: String, index: int) -> bool:
	return bool(DevBalance.hidden_off.get("%s|%d" % [sid, index], false))

func _attack_parts(ship: Dictionary) -> Array:
	## Bar length is actual output per second. Main guns share one color. Each PD mount is its own color.
	_ensure_equip()
	var sid := str(ship.get("id", ""))
	var hidden: Array = ship.get("fit", {}).get("hidden", [])
	var pd_mul := 1.0
	for i in hidden.size():
		var h = hidden[i]
		if typeof(h) != TYPE_DICTIONARY or _hidden_blocked(sid, i):
			continue
		if str(h.get("kind", "")) == "pd_damage_mul":
			pd_mul = float(h.get("value", 1.0))
	var parts: Array = []
	var pd_i := 0
	for i2 in hidden.size():
		var h2 = hidden[i2]
		if typeof(h2) != TYPE_DICTIONARY or _hidden_blocked(sid, i2):
			continue
		var kind := str(h2.get("kind", ""))
		var ref := str(h2.get("ref", ""))
		if ref == "":
			continue
		var eq := _live_eq(ref)
		var wname := str(eq.get("name", ref))
		if kind == "weapon":
			if _part_rate("weapon", eq, 1.0) <= 0.0:
				continue
			parts.append({
				"color": _DPH_COLOR,
				"name": wname,
				"eid": ref,
				"kind": "weapon",
				"pd_mul": 1.0,
			})
		elif kind == "pd":
			if _part_rate("pd", eq, pd_mul) <= 0.0:
				continue
			var n := maxi(int(h2.get("count", 1)), 1)
			for _g in n:
				parts.append({
					"color": _PD_PALETTE[pd_i % _PD_PALETTE.size()],
					"name": wname,
					"eid": ref,
					"kind": "pd",
					"pd_mul": pd_mul,
				})
				pd_i += 1
	return parts

func _live_eq(ref: String) -> Dictionary:
	_ensure_equip()
	var base = _equip_defs.get(ref, {})
	var out: Dictionary = base.duplicate(true) if typeof(base) == TYPE_DICTIONARY else {}
	var over: Dictionary = DevBalance.equip_num.get(ref, {})
	for k in over.keys():
		out[str(k)] = over[k]
	return out

func _part_rate(kind: String, eq: Dictionary, pd_mul: float) -> float:
	var cycle := maxf(float(eq.get("cycle_s", 4.0 if kind != "pd" else 1.4)), 0.001)
	if kind == "pd":
		return float(eq.get("damage", 0.0)) / cycle * pd_mul
	var raw := float(eq.get("damage_emp", 0))
	raw += float(eq.get("damage_thermal", 0))
	raw += float(eq.get("damage_kinetic", 0))
	raw += float(eq.get("damage_explosive", 0))
	raw += float(eq.get("heal_armor", 0))
	raw += float(eq.get("heal_shield", 0))
	return raw / cycle

func _equip_edit_value(eq: Dictionary) -> float:
	if eq.has("heal_armor") or eq.has("heal_shield"):
		return float(eq.get("heal_armor", 0)) + float(eq.get("heal_shield", 0))
	if eq.has("damage"):
		return float(eq.get("damage", 0))
	return float(eq.get("damage_emp", 0)) + float(eq.get("damage_thermal", 0)) + float(eq.get("damage_kinetic", 0)) + float(eq.get("damage_explosive", 0))

func _seg_rate(seg: Dictionary) -> float:
	return _part_rate(str(seg["kind"]), _live_eq(str(seg["eid"])), float(seg["pd_mul"]))

func _ship_output(segs: Array, dph_mul: float) -> float:
	var total := 0.0
	for seg in segs:
		total += _seg_rate(seg) * dph_mul
	return total

func _seg_rect(color: Color, wname: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.clip_contents = true
	var lab := Label.new()
	lab.text = wname
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.clip_text = true
	lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lab.offset_left = 4.0
	lab.offset_right = -4.0
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	lab.add_theme_constant_override("outline_size", 4)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	rect.add_child(lab)
	return rect

func _equip_spin(eid: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(EQUIP_SPIN_W, 28)
	spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spin.min_value = 0.0
	spin.max_value = 10000000.0
	spin.step = 0.1
	spin.set_value_no_signal(_equip_edit_value(_live_eq(eid)))
	var line := spin.get_line_edit()
	if line:
		line.custom_minimum_size = Vector2(64, 0)
		line.clip_contents = false
	var on_eq := func(v: float, equip_id: String) -> void:
		_store_equip_combat(equip_id, v)
	spin.value_changed.connect(on_eq.bind(eid))
	return spin

func _store_equip_combat(eid: String, value: float) -> void:
	if _loading:
		return
	_write_equip_combat(eid, value)
	_commit_hidden()
	_sync_equip_spins(eid, value)
	_refresh_chart()

func _sync_equip_spins(eid: String, value: float) -> void:
	for entry in _chart:
		if str(entry.get("kind", "")) != "dph":
			continue
		for seg in entry["segs"]:
			var spin = seg.get("spin")
			if spin != null and str(seg.get("eid", "")) == eid:
				spin.set_value_no_signal(value)

func _write_equip_combat(eid: String, value: float) -> void:
	var eq := _live_eq(eid)
	var bag: Dictionary = DevBalance.equip_num.get(eid, {})
	if typeof(bag) != TYPE_DICTIONARY:
		bag = {}
	else:
		bag = bag.duplicate()
	if eq.has("heal_armor") or eq.has("heal_shield"):
		var keys: Array[String] = []
		if eq.has("heal_armor"):
			keys.append("heal_armor")
		if eq.has("heal_shield"):
			keys.append("heal_shield")
		var old := 0.0
		for k in keys:
			old += float(eq.get(k, 0))
		if old <= 0.0:
			bag[keys[0]] = value
		else:
			var ratio := value / old
			for k2 in keys:
				bag[k2] = float(eq.get(k2, 0)) * ratio
	elif eq.has("damage"):
		bag["damage"] = value
	else:
		var dmg_keys: Array[String] = ["damage_emp", "damage_thermal", "damage_kinetic", "damage_explosive"]
		var old_d := 0.0
		for dk in dmg_keys:
			old_d += float(eq.get(dk, 0))
		if old_d <= 0.0:
			bag["damage_thermal"] = value
		else:
			var ratio_d := value / old_d
			for dk2 in dmg_keys:
				if float(eq.get(dk2, 0)) != 0.0:
					bag[dk2] = float(eq.get(dk2, 0)) * ratio_d
	DevBalance.equip_num[eid] = bag

func _live_hp(sid: String, ship: Dictionary) -> Dictionary:
	var stored: Dictionary = DevBalance.hp.get(sid, {})
	return {
		"shield": float(stored.get("shield", ship.get("shield", 1))),
		"armor": float(stored.get("armor", ship.get("armor", 1))),
		"structure": float(stored.get("structure", ship.get("structure", 1))),
	}

func _refresh_chart() -> void:
	if _tab == 0:
		var max_total := 1.0
		var totals: Dictionary = {}
		for entry in _chart:
			var sid := str(entry["sid"])
			var vals: Dictionary = _live_hp(sid, entry["ship"])
			var total := float(vals["shield"]) + float(vals["armor"]) + float(vals["structure"])
			totals[sid] = vals
			max_total = maxf(max_total, total)
		for entry2 in _chart:
			var sid2 := str(entry2["sid"])
			var vals2: Dictionary = totals[sid2]
			var total2 := float(vals2["shield"]) + float(vals2["armor"]) + float(vals2["structure"])
			var space: Control = entry2["space"]
			var width := space.size.x * total2 / max_total
			var y := 1.0
			var h := maxf(space.size.y - 2.0, 1.0)
			var x := 0.0
			var layers: Dictionary = entry2["layers"]
			for key in ["shield", "armor", "structure"]:
				var part := 0.0 if total2 <= 0.0 else width * float(vals2[key]) / total2
				var rect: ColorRect = layers[key]
				rect.position = Vector2(x, y)
				rect.size = Vector2(maxf(part, 0.0), h)
				x += part
	elif _tab == 1:
		var outs: Array[float] = []
		var max_out := 0.0
		for entry3 in _chart:
			var mul := float(DevBalance.dph.get(entry3["sid"], 1.0))
			var sum_o := _ship_output(entry3["segs"], mul)
			outs.append(sum_o)
			max_out = maxf(max_out, sum_o)
		if max_out <= 0.0:
			max_out = 1.0
		var ti := 0
		for entry4 in _chart:
			var mul2 := float(DevBalance.dph.get(entry4["sid"], 1.0))
			var space2: Control = entry4["space"]
			var ship_out: float = outs[ti]
			ti += 1
			var bar_w := space2.size.x * ship_out / max_out
			var h2 := maxf(space2.size.y - 2.0, 1.0)
			var x2 := 0.0
			for seg2 in entry4["segs"]:
				var piece := _seg_rate(seg2) * mul2
				var part_w := 0.0 if ship_out <= 0.0 else bar_w * piece / ship_out
				var rect2: ColorRect = seg2["rect"]
				rect2.position = Vector2(x2, 1)
				rect2.size = Vector2(maxf(part_w, 0.0), h2)
				x2 += part_w

func _store_hp(sid: String, key: String, value: float) -> void:
	if _loading:
		return
	var row: Dictionary = DevBalance.hp.get(sid, {})
	if row.is_empty():
		var s := _ship_by_id(sid)
		row = {
			"shield": float(s.get("shield", 1)),
			"armor": float(s.get("armor", 1)),
			"structure": float(s.get("structure", 1)),
		}
	row[key] = value
	DevBalance.hp[sid] = row
	_commit_hull(sid)
	_refresh_chart()

func _ship_by_id(sid: String) -> Dictionary:
	for s in _ships:
		if str(s.get("id", "")) == sid:
			return s
	return {}

func _fill_hidden() -> void:
	var s := _ship()
	if s.is_empty():
		return
	var sid := str(s.get("id", ""))
	var hidden: Array = _hidden_of(s)
	if hidden.is_empty():
		_note("这艘舰没有隐藏装备。")
		return
	for i in hidden.size():
		var h: Dictionary = hidden[i]
		var key := "%s|%d" % [sid, i]
		var chk := CheckButton.new()
		var ref := str(h.get("ref", ""))
		chk.text = str(h.get("kind", "")) + ((" " + ref) if ref != "" else "")
		chk.set_pressed_no_signal(not bool(DevBalance.hidden_off.get(key, false)))
		var toggled := func(on: bool, off_key: String) -> void:
			if _loading:
				return
			if on:
				DevBalance.hidden_off.erase(off_key)
			else:
				DevBalance.hidden_off[off_key] = true
			_commit_hidden()
		chk.toggled.connect(toggled.bind(key))
		_right.add_child(chk)

func _equip_field_locked(key: String) -> bool:
	## Image / type numbers stay display-only. Gameplay numbers stay editable.
	return key in [
		"id", "name", "icon", "kind", "fx", "desc",
		"pc_typeid", "ref_typeid", "type_id", "typeID", "icon_item_id",
	]


func _fill_equip() -> void:
	var e := _equip()
	if e.is_empty():
		return
	var eid := str(e.get("id", ""))
	var title := str(e.get("name", eid))
	var desc := str(e.get("desc", "")).strip_edges()
	if desc == "":
		var bits: PackedStringArray = PackedStringArray()
		for k in e.keys():
			var key := str(k)
			if _equip_field_locked(key):
				continue
			if typeof(e[k]) == TYPE_FLOAT or typeof(e[k]) == TYPE_INT:
				bits.append("%s %s" % [key, str(e[k])])
		desc = "，".join(bits) if not bits.is_empty() else title
	_note("%s\n%s" % [title, desc])
	var stored: Dictionary = DevBalance.equip_num.get(eid, {})
	for k in e.keys():
		var key := str(k)
		if _equip_field_locked(key):
			continue
		var raw = e[k]
		if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
			continue
		var cur := float(stored.get(key, raw))
		var changed := func(v: float, field: String, equip_id: String) -> void:
			if _loading:
				return
			var bag: Dictionary = DevBalance.equip_num.get(equip_id, {})
			bag[field] = v
			DevBalance.equip_num[equip_id] = bag
			_commit_hidden()
		_spin(key, cur, changed.bind(key, eid))

func _fill_match() -> void:
	DevBalance.ensure_defaults()
	_note("各吨位制造时间")
	for ton in DevBalance.TONS:
		var label := str(TON_LABEL.get(ton, ton))
		var on_build := func(v: float, ton_id: String) -> void:
			if _loading:
				return
			DevBalance.tonnage_build[ton_id] = v
			DevBalance.save()
		_spin(label, float(DevBalance.tonnage_build.get(ton, 1.0)), on_build.bind(ton), 0.1, 100000.0, 1.0)
	_note("各吨位占领作业值")
	for ton2 in DevBalance.TONS:
		var label2 := str(TON_LABEL.get(ton2, ton2))
		var on_work := func(v: float, ton_id: String) -> void:
			if _loading:
				return
			DevBalance.tonnage_work[ton_id] = v
			DevBalance.save()
		_spin(label2, float(DevBalance.tonnage_work.get(ton2, 1.0)), on_work.bind(ton2), 0.0, 100000.0, 0.25)
	_note("格子作业上限")
	for kind in CAP_KINDS:
		var cap_label := str(CAP_LABEL.get(kind, str(kind)))
		var on_cap := func(v: float, kind_id: int) -> void:
			if _loading:
				return
			DevBalance.work_caps[str(kind_id)] = v
			DevBalance.save()
			var board = _board()
			if board != null and board.has_method("dev_restamp_work"):
				board.dev_restamp_work()
		_spin(cap_label, DevBalance.work_cap(kind), on_cap.bind(kind), 1.0, 1000000.0, 10.0)
	_note("时间倍率")
	_scale_spin("跨格准备", "scale_prep")
	_scale_spin("同系跨格时间", "scale_move")
	_scale_spin("过星门时间", "scale_jump")
	_scale_spin("落地僵直", "scale_landing")
	_note("同系跨格落地僵直削减。跨 0 格 = 隔壁格。数字是倍率，0.10 = 10%。跨过 5 格用跨 5 格这一档。过星门不削减。")
	for arc_i in 6:
		var arc_label := "跨%d格" % arc_i
		var on_arc := func(v: float, skip: int) -> void:
			if _loading:
				return
			DevBalance.set_land_arc(skip, v)
			DevBalance.save()
			var board = _board()
			if board != null and board.has_method("dev_rescale_land_arc"):
				board.dev_rescale_land_arc()
		_spin(arc_label, DevBalance.land_arc_of(arc_i), on_arc.bind(arc_i), 0.0, 5.0, 0.01)

func _scale_spin(label: String, field: String) -> void:
	var cur := DevBalance.scale_of(field)
	var on_scale := func(v: float, which: String) -> void:
		if _loading:
			return
		DevBalance.set_scale(which, v)
		DevBalance.save()
		var board = _board()
		if board != null and board.has_method("dev_rescale_motion"):
			board.dev_rescale_motion()
	_spin(label, cur, on_scale.bind(field), 0.01, 100.0, 0.05)

func _commit_hull(sid: String) -> void:
	DevBalance.save()
	var board = _board()
	if board != null and board.has_method("dev_set_hull"):
		var row: Dictionary = DevBalance.hp[sid]
		board.dev_set_hull(sid, float(row["shield"]), float(row["armor"]), float(row["structure"]))
	else:
		DevBalance.save()

func _commit_hidden() -> void:
	DevBalance.save()
	var board = _board()
	if board != null and board.has_method("dev_reapply_fits"):
		board.dev_reapply_fits()

func _ship() -> Dictionary:
	var idx := _left.get_selected_items()
	if idx.is_empty() or idx[0] < 0 or idx[0] >= _ships.size():
		return {}
	return _ships[idx[0]]

func _equip() -> Dictionary:
	var idx := _left.get_selected_items()
	if idx.is_empty() or idx[0] < 0 or idx[0] >= _equips.size():
		return {}
	return _equips[idx[0]]

func _hidden_of(ship: Dictionary) -> Array:
	var sid := str(ship.get("id", ""))
	var fit: Dictionary = ship.get("fit", {})
	var hidden: Array = fit.get("hidden", []).duplicate(true)
	var found := false
	for h in hidden:
		if typeof(h) == TYPE_DICTIONARY and str(h.get("kind", "")) == "dph_mul":
			h["value"] = float(DevBalance.dph.get(sid, h.get("value", 1.0)))
			found = true
	if not found:
		hidden.append({"kind": "dph_mul", "value": float(DevBalance.dph.get(sid, 1.0))})
	return hidden

func _axis_btn(txt: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(AXIS_BTN_W, 28)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _nudge_euler(sid: String, axis: int, sign: int) -> void:
	if _loading:
		return
	var e := DevBalance.model_euler_of(sid)
	if axis == 0:
		e.x += SCALE_EULER_STEP * float(sign)
	elif axis == 1:
		e.y += SCALE_EULER_STEP * float(sign)
	else:
		e.z += SCALE_EULER_STEP * float(sign)
	DevBalance.set_model_euler(sid, e)
	DevBalance.save()
	_refit_scale_cell(sid)
	var board = _board()
	if board != null and board.has_method("dev_rescale_hull"):
		board.dev_rescale_hull(sid)
	for n in get_tree().get_nodes_in_group("evertbs_menu_skirmish"):
		if n.has_method("dev_rescale_hull"):
			n.dev_rescale_hull(sid)


func _compact_spin(label: String, value: float, on_change: Callable, min_v: float = 1.0, max_v: float = 10000000.0, step: float = 1.0) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var lab := Label.new()
	lab.text = label
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(lab)
	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(EQUIP_SPIN_W, 28)
	spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.set_value_no_signal(value)
	spin.value_changed.connect(on_change)
	box.add_child(spin)
	return box

func _spin(label: String, value: float, on_change: Callable, min_v: float = 1.0, max_v: float = 10000000.0, step: float = 1.0) -> void:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label
	lab.custom_minimum_size = Vector2(140, 0)
	row.add_child(lab)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.set_value_no_signal(value)
	spin.value_changed.connect(on_change)
	row.add_child(spin)
	_right.add_child(row)

func _note(text: String) -> void:
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right.add_child(lab)

func _make_scale_cell(ship: Dictionary) -> Control:
	var sid := str(ship.get("id", ""))
	var model_key := str(ship.get("model", sid))
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 6)
	var host := SubViewportContainer.new()
	host.stretch = true
	host.custom_minimum_size = SCALE_CELL_VIEW
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(host)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.size = Vector2i(int(SCALE_CELL_VIEW.x), int(SCALE_CELL_VIEW.y))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	host.add_child(vp)
	var env := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.04, 0.055, 0.08, 1)
	we.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.ambient_light_color = Color(0.55, 0.6, 0.7)
	we.ambient_light_energy = 0.35
	env.environment = we
	vp.add_child(env)
	var world := Node3D.new()
	vp.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, 35, 0)
	light.light_energy = 1.2
	world.add_child(light)
	var hull_d := BoardTypes.HULL_DIAMETER
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.current = true
	cam.position = Vector3(0.0, hull_d * 0.42, hull_d * 1.85)
	world.add_child(cam)
	cam.look_at(Vector3(0.0, hull_d * 0.08, 0.0), Vector3.UP)
	var holder := Node3D.new()
	holder.name = "ShipHolder"
	world.add_child(holder)
	var inst: Node3D = null
	var ship_d := DevBalance.hull_diameter(sid)
	if SHIP_ART.has_model(model_key):
		inst = SHIP_ART.spawn_model(holder, model_key, ship_d, sid)
	if inst == null:
		inst = SHIP_ART.make_fallback_sphere(ship_d * 0.18, "Model")
		holder.add_child(inst)
	var trail := MeshInstance3D.new()
	trail.name = "Trail"
	trail.top_level = true
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.material_override = _scale_trail_material()
	trail.visible = false
	world.add_child(trail)
	var muzzle_root := Node3D.new()
	muzzle_root.name = "MuzzleMarks"
	var center_mark := _make_scale_gizmo_sphere("CenterMark", Color(1.0, 0.92, 0.28, 0.95), 0.08)
	var edge_ring := _make_scale_gizmo_ring("EdgeRing", Color(0.22, 0.92, 0.86, 0.85))
	if inst != null:
		inst.add_child(muzzle_root)
	else:
		holder.add_child(muzzle_root)
	holder.add_child(center_mark)
	holder.add_child(edge_ring)
	var nozzles: Array = []
	if inst != null and SHIP_ART.has_model(model_key):
		nozzles = SHIP_ART.engine_nozzle_locals(model_key, inst)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	card.add_child(info)
	info.add_child(_tonnage_icon(str(ship.get("tonnage", "frigate"))))
	var name_lab := Label.new()
	name_lab.text = str(ship.get("name", sid))
	name_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lab.clip_text = true
	name_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_child(name_lab)
	info.add_child(_axis_btn("X-", _nudge_euler.bind(sid, 0, -1)))
	info.add_child(_axis_btn("X+", _nudge_euler.bind(sid, 0, 1)))
	info.add_child(_axis_btn("Y-", _nudge_euler.bind(sid, 1, -1)))
	info.add_child(_axis_btn("Y+", _nudge_euler.bind(sid, 1, 1)))
	info.add_child(_axis_btn("Z-", _nudge_euler.bind(sid, 2, -1)))
	info.add_child(_axis_btn("Z+", _nudge_euler.bind(sid, 2, 1)))
	var on_scale := func(v: float, ship_id: String) -> void:
		if _loading:
			return
		_commit_scale(ship_id, v)
	info.add_child(_compact_spin("比例", DevBalance.model_mul(sid), on_scale.bind(sid), 0.10, 5.00, 0.05))
	_scale_cells.append({
		"sid": sid,
		"holder": holder,
		"model_key": model_key,
		"trail": trail,
		"trail_streams": [],
		"trail_nozzles": nozzles,
		"trail_acc": 0.0,
		"muzzle_root": muzzle_root,
		"center_mark": center_mark,
		"edge_ring": edge_ring,
	})
	return card


func _refit_scale_cell(sid: String) -> void:
	var ship_d := DevBalance.hull_diameter(sid)
	for cell in _scale_cells:
		if str(cell.get("sid", "")) != sid:
			continue
		var holder: Node3D = cell.get("holder")
		if holder == null or not is_instance_valid(holder):
			continue
		var model := holder.get_node_or_null("Model") as Node3D
		if model == null:
			continue
		var model_key := str(cell.get("model_key", ""))
		if SHIP_ART.has_model(model_key):
			SHIP_ART.apply_pose_and_scale(model, model_key, ship_d, sid)
			cell["trail_nozzles"] = SHIP_ART.engine_nozzle_locals(model_key, model)
			cell["trail_streams"] = []
		elif model is MeshInstance3D and (model as MeshInstance3D).mesh is SphereMesh:
			var sph := (model as MeshInstance3D).mesh as SphereMesh
			sph.radius = ship_d * 0.18
			sph.height = sph.radius * 2.0


func _clear_scale_previews() -> void:
	_scale_cells.clear()


func _process(delta: float) -> void:
	if not visible or _tab != 2:
		return
	for cell in _scale_cells:
		var holder: Node3D = cell.get("holder")
		if holder == null or not is_instance_valid(holder):
			continue
		holder.rotate_y(SCALE_SPIN_W * delta)
		_tick_scale_trail(cell, delta)
		_sync_scale_fx_marks(cell)


func _scale_trail_material() -> StandardMaterial3D:
	if _scale_trail_mat != null:
		return _scale_trail_mat
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.vertex_color_use_as_albedo = true
	tmat.albedo_color = Color(1, 1, 1, 1)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.emission_enabled = true
	tmat.emission = Color(0.35, 0.75, 1.0)
	tmat.emission_energy_multiplier = 1.8
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tmat.no_depth_test = false
	tmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_scale_trail_mat = tmat
	return tmat


func _scale_gizmo_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 1.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	return mat


func _make_scale_gizmo_sphere(node_name: String, color: Color, radius: float) -> MeshInstance3D:
	if _scale_gizmo_sphere == null:
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.height = 2.0
		sph.radial_segments = 12
		sph.rings = 8
		_scale_gizmo_sphere = sph
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _scale_gizmo_sphere
	mi.scale = Vector3.ONE * radius
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _scale_gizmo_mat(color)
	return mi


func _make_scale_gizmo_ring(node_name: String, color: Color) -> MeshInstance3D:
	if _scale_gizmo_ring == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 48
		var r0 := 0.92
		var r1 := 1.0
		for i in segs:
			var a0 := float(i) / float(segs) * TAU
			var a1 := float(i + 1) / float(segs) * TAU
			var p00 := Vector3(sin(a0) * r0, 0, -cos(a0) * r0)
			var p10 := Vector3(sin(a1) * r0, 0, -cos(a1) * r0)
			var p01 := Vector3(sin(a0) * r1, 0, -cos(a0) * r1)
			var p11 := Vector3(sin(a1) * r1, 0, -cos(a1) * r1)
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p11)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p01)
		_scale_gizmo_ring = st.commit()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _scale_gizmo_ring
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _scale_gizmo_mat(color)
	return mi


func _sync_scale_fx_marks(cell: Dictionary) -> void:
	var holder: Node3D = cell.get("holder") as Node3D
	if holder == null or not is_instance_valid(holder):
		return
	var model := holder.get_node_or_null("Model") as Node3D
	if model == null:
		return
	var anchors: Dictionary = SHIP_ART.fx_anchors_local(model, str(cell.get("model_key", "")))
	var muzzles: Array = anchors.get("muzzles_model", [])
	if muzzles.is_empty():
		muzzles = anchors.get("muzzles", [])
	if muzzles.is_empty():
		muzzles = [anchors.get("muzzle", Vector3.ZERO)]
	var center_l: Vector3 = anchors.get("center", Vector3.ZERO)
	var graze_r := float(anchors.get("graze", 0.55))
	var muzzle_root: Node3D = cell.get("muzzle_root") as Node3D
	if muzzle_root != null and is_instance_valid(muzzle_root):
		if muzzle_root.get_parent() != model:
			if muzzle_root.get_parent() != null:
				muzzle_root.get_parent().remove_child(muzzle_root)
			model.add_child(muzzle_root)
		var mark_r := 0.07
		if model.scale.x > 1e-8:
			mark_r = 0.07 / model.scale.x
		while muzzle_root.get_child_count() > muzzles.size():
			var extra: Node = muzzle_root.get_child(muzzle_root.get_child_count() - 1)
			muzzle_root.remove_child(extra)
			extra.free()
		while muzzle_root.get_child_count() < muzzles.size():
			muzzle_root.add_child(_make_scale_gizmo_sphere("MuzzleMark", Color(1.0, 0.45, 0.12, 0.95), 0.07))
		for i in muzzles.size():
			var mark: MeshInstance3D = muzzle_root.get_child(i) as MeshInstance3D
			if mark != null:
				mark.position = muzzles[i]
				mark.scale = Vector3.ONE * mark_r
	var center_mark: MeshInstance3D = cell.get("center_mark") as MeshInstance3D
	if center_mark != null and is_instance_valid(center_mark):
		center_mark.position = center_l
	var edge_ring: MeshInstance3D = cell.get("edge_ring") as MeshInstance3D
	if edge_ring != null and is_instance_valid(edge_ring):
		edge_ring.position = Vector3(center_l.x, center_l.y, center_l.z)
		edge_ring.scale = Vector3(graze_r, 1.0, graze_r)


func _tick_scale_trail(cell: Dictionary, delta: float) -> void:
	var trail: MeshInstance3D = cell.get("trail") as MeshInstance3D
	var holder: Node3D = cell.get("holder") as Node3D
	if trail == null or holder == null or not is_instance_valid(trail) or not is_instance_valid(holder):
		return
	var model := holder.get_node_or_null("Model") as Node3D
	var locals: Array = cell.get("trail_nozzles", [])
	if locals.is_empty() and model != null:
		var model_key := str(cell.get("model_key", ""))
		if SHIP_ART.has_model(model_key):
			locals = SHIP_ART.engine_nozzle_locals(model_key, model)
			cell["trail_nozzles"] = locals
	var heads: Array = []
	if model != null and not locals.is_empty():
		heads = SHIP_ART.engine_nozzle_worlds(model, locals)
	if heads.is_empty():
		trail.visible = false
		trail.mesh = null
		return
	var aft: Vector3 = SHIP_ART.engine_trail_aft_world(model)
	if aft.length_squared() < 0.0001:
		aft = Vector3(0, 0, 1)
	var speed := BoardTypes.HULL_DIAMETER * SCALE_TRAIL_SPEED_MUL
	var streams: Array = cell.get("trail_streams", [])
	while streams.size() < heads.size():
		streams.append([])
	while streams.size() > heads.size():
		streams.remove_at(streams.size() - 1)
	var acc := float(cell.get("trail_acc", 0.0)) + delta
	var do_stamp := acc >= SCALE_TRAIL_STAMP
	if do_stamp:
		acc = 0.0
	var any_pts := false
	for si in range(heads.size()):
		var pts: Array = streams[si] if si < streams.size() and typeof(streams[si]) == TYPE_ARRAY else []
		var aged: Array = []
		for p in pts:
			var age := float(p["age"]) + delta
			if age < SCALE_TRAIL_LIFE:
				aged.append({"pos": (p["pos"] as Vector3) + aft * speed * delta, "age": age})
		pts = aged
		if do_stamp:
			var head: Vector3 = heads[si]
			if pts.is_empty() or (pts[pts.size() - 1]["pos"] as Vector3).distance_to(head) >= 0.08:
				pts.append({"pos": head, "age": 0.0})
			while pts.size() > 28:
				pts.remove_at(0)
		streams[si] = pts
		if pts.size() >= 2:
			any_pts = true
	cell["trail_acc"] = acc
	cell["trail_streams"] = streams
	if not any_pts:
		trail.visible = false
		trail.mesh = null
		return
	trail.mesh = _scale_trail_mesh(streams)
	trail.global_position = Vector3.ZERO
	trail.visible = true


func _scale_trail_mesh(streams: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w := SCALE_TRAIL_HALF_W
	var any := false
	for stream in streams:
		if typeof(stream) != TYPE_ARRAY:
			continue
		var pts: Array = stream
		if pts.size() < 2:
			continue
		for i in range(pts.size() - 1):
			var a: Vector3 = pts[i]["pos"]
			var b: Vector3 = pts[i + 1]["pos"]
			var dir := b - a
			if dir.length_squared() < 0.0001:
				continue
			dir = dir.normalized()
			var side := dir.cross(Vector3.UP)
			if side.length_squared() < 0.0001:
				side = dir.cross(Vector3.RIGHT)
			side = side.normalized() * half_w
			var c0 := Color(0.45, 0.85, 1.0, clampf(1.0 - float(pts[i]["age"]) / SCALE_TRAIL_LIFE, 0.0, 1.0) * 0.55)
			var c1 := Color(0.45, 0.85, 1.0, clampf(1.0 - float(pts[i + 1]["age"]) / SCALE_TRAIL_LIFE, 0.0, 1.0) * 0.55)
			var up := dir.cross(side).normalized() * half_w
			for off in [side, up]:
				st.set_color(c0); st.add_vertex(a + off)
				st.set_color(c1); st.add_vertex(b + off)
				st.set_color(c1); st.add_vertex(b - off)
				st.set_color(c0); st.add_vertex(a + off)
				st.set_color(c1); st.add_vertex(b - off)
				st.set_color(c0); st.add_vertex(a - off)
			any = true
	return st.commit() if any else null


func _log_ui(control: String) -> void:
	var board := _board()
	var paused := false
	if board != null:
		paused = bool(board.get("sim_paused"))
	var tab_name := ""
	if _tab >= 0 and _tab < TAB_NAMES.size():
		tab_name = TAB_NAMES[_tab]
	else:
		tab_name = str(_tab)
	DebugSessionLog.append("UI", "global_data_panel", control, {
		"control": control,
		"tab": tab_name,
		"left_visible": _left.visible,
		"left_count": _left.item_count,
		"window_visible": visible,
		"sim_paused": paused,
		"runId": "grok-ui",
	})

func _board() -> Node:
	var nodes := get_tree().get_nodes_in_group("evertbs_board")
	if nodes.is_empty():
		return null
	return nodes[0]
