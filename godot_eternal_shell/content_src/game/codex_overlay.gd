extends Control

const MemberTableScr := preload("res://game/board/pilots/member_table.gd")
const SHIP_ART := preload("res://art_modules/eve_ship_art/scripts/eve_ship_art_module.gd")
## Codex overlay: deputies, members, playable ships (UI_AND_SHELL §0.3).

signal closed

const PANEL_BG := Color(0.08, 0.1, 0.14, 0.15)
const PANEL_BORDER := Color(0.7, 0.75, 0.82, 0.55)
const FLEET_BG := Color(0.9, 0.94, 1.0, 0.08)
const FLEET_BORDER := Color(1, 1, 1, 0.38)
const PREVIEW_SIZE := Vector2(360, 240)
const PREVIEW_ORBIT_RAD_S := 0.35
const PREVIEW_MODEL_D := 3.2
const PREVIEW_CAM_DIST := 5.2

const TON_LABEL := {
	"frigate": "护卫",
	"destroyer": "驱逐",
	"cruiser": "巡洋",
	"battlecruiser": "战巡",
	"battleship": "战列",
}

const FLEET_DETAIL := {
	"主力": "贴脸交战。占点被夺时先打回来。星门被攻时门前集结守门；战场压敌。",
	"中型": "避开敌人不硬抗，占点，同一星系尽量停同一格。若是唯一舰队，敌人进入 4 跳内改按主力机动。",
	"小型": "避开敌人不硬抗，占点，同一星系尽量停同一格。若是唯一舰队，敌人进入 4 跳内改按主力机动。",
	"战术换损": "默认同步移动。编队内保留一艘默认装甲链接的舰。跃迁直落敌人中敌对的格子；择敌时优先敌对权重更小的格子。",
	"盾守": "护盾立场与远射程约 1:2。靠近敌人。邻系时去非门后星门的相邻格并强制进入。同系停在非星门格，集火血量最低的目标。",
	"抢占": "各舰分开行动，只造毒蜥。无敌人时四人一组占不同格，并避开敌人。邻系集同一扇星门。本系守门。战列或战巡则朝己方站退一跳。本系有己方站则进站，直到敌人离开。",
	"战术主力": "主力的门后、隔门对峙、战术压迫，外加一艘默认副装备含拦截泡发射器的舰。对不上就回最近己方站换；没有库存则全队聚集排队制造。",
}

var _detail: VBoxContainer
var _hover: PanelContainer
var _hover_label: Label
var _ships: Dictionary = {}
var _equip: Dictionary = {}
var _preview_host: SubViewportContainer
var _preview_vp: SubViewport
var _preview_world: Node3D
var _preview_pivot: Node3D
var _preview_cam: Camera3D
var _preview_yaw := 0.0
var _preview_active := false


func _ready() -> void:
	_load_ships()
	_load_equip()
	_build()


func _process(delta: float) -> void:
	if not _preview_active or _preview_pivot == null:
		return
	_preview_yaw += PREVIEW_ORBIT_RAD_S * delta
	_preview_pivot.rotation.y = _preview_yaw


func _load_ships() -> void:
	_ships.clear()
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/board/ships.json"))
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for s in raw.get("ships", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		_ships[str(s.get("id", ""))] = s


func _load_equip() -> void:
	_equip.clear()
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/board/equipment.json"))
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for k in raw.keys():
		var e = raw[k]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		_equip[str(e.get("id", k))] = e


func _playable_ships() -> Array:
	var out: Array = []
	for ton in ["frigate", "destroyer", "cruiser", "battlecruiser", "battleship"]:
		for sid in _ships.keys():
			var def: Dictionary = _ships[sid]
			if bool(def.get("npc_hull", false)):
				continue
			if str(def.get("tonnage", "")) != ton:
				continue
			out.append(def)
	return out


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(row)
	var left := _panel()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	row.add_child(left)
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(left_scroll)
	var left_box := VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.add_theme_constant_override("separation", 10)
	left_scroll.add_child(left_box)
	var head := HBoxContainer.new()
	left_box.add_child(head)
	var title := Label.new()
	title.text = "图鉴"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color.WHITE)
	head.add_child(title)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(func() -> void:
		_hide_ship_preview()
		closed.emit()
		queue_free()
	)
	head.add_child(back)
	left_box.add_child(_section_label("副指挥官"))
	var dep_row := HBoxContainer.new()
	dep_row.add_theme_constant_override("separation", 8)
	left_box.add_child(dep_row)
	for spec in _deputies():
		dep_row.add_child(_deputy_card(spec))
	left_box.add_child(_section_label("团员"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left_box.add_child(grid)
	for member in MemberTableScr.load_merged():
		if typeof(member) != TYPE_DICTIONARY:
			continue
		grid.add_child(_member_card(member))
	left_box.add_child(_section_label("舰船"))
	var ship_grid := GridContainer.new()
	ship_grid.columns = 3
	ship_grid.add_theme_constant_override("h_separation", 8)
	ship_grid.add_theme_constant_override("v_separation", 8)
	left_box.add_child(ship_grid)
	for ship in _playable_ships():
		ship_grid.add_child(_ship_card(ship))
	var right := _panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.9
	row.add_child(right)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(right_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	right_scroll.add_child(_detail)
	_show_hint("点开一张卡查看详情。")
	_hover = PanelContainer.new()
	_hover.visible = false
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.z_index = 40
	_hover.add_theme_stylebox_override("panel", _style(Color(0.05, 0.07, 0.1, 0.82), Color(1, 1, 1, 0.45)))
	add_child(_hover)
	_hover_label = Label.new()
	_hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_label.custom_minimum_size = Vector2(280, 0)
	_hover_label.add_theme_color_override("font_color", Color.WHITE)
	_hover.add_child(_hover_label)
	_build_ship_preview()


func _build_ship_preview() -> void:
	_preview_host = SubViewportContainer.new()
	_preview_host.name = "ShipPreview"
	_preview_host.visible = false
	_preview_host.stretch = true
	_preview_host.custom_minimum_size = PREVIEW_SIZE
	_preview_host.size = PREVIEW_SIZE
	_preview_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_host.z_index = 30
	_preview_host.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_preview_host.offset_left = -PREVIEW_SIZE.x - 24.0
	_preview_host.offset_top = -PREVIEW_SIZE.y - 24.0
	_preview_host.offset_right = -24.0
	_preview_host.offset_bottom = -24.0
	add_child(_preview_host)
	_preview_vp = SubViewport.new()
	_preview_vp.transparent_bg = true
	_preview_vp.size = Vector2i(int(PREVIEW_SIZE.x), int(PREVIEW_SIZE.y))
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_preview_vp.own_world_3d = true
	_preview_host.add_child(_preview_vp)
	_preview_world = Node3D.new()
	_preview_world.name = "PreviewWorld"
	_preview_vp.add_child(_preview_world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, 35, 0)
	light.light_energy = 1.35
	_preview_world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.45
	_preview_world.add_child(fill)
	_preview_pivot = Node3D.new()
	_preview_pivot.name = "OrbitPivot"
	_preview_world.add_child(_preview_pivot)
	_preview_cam = Camera3D.new()
	_preview_cam.fov = 38.0
	_preview_cam.current = true
	_preview_pivot.add_child(_preview_cam)
	_preview_cam.position = Vector3(0.0, 1.15, PREVIEW_CAM_DIST)
	_preview_cam.look_at(Vector3(0.0, 0.2, 0.0), Vector3.UP)


func _deputies() -> Array:
	return [
		{
			"id": "yang",
			"name": "羊",
			"face": "res://assets/ui/deputies/yang.png",
			"blurb": "策略最均衡的指挥官，敢于尝试，但会给机会。指挥上限 60 人。最多四支舰队：两个主力、一个中型、一个小型。",
			"resource": "被任命的守卫先持有到 3，再换下一名。",
			"build": "进度条能走的最大吨位；已经是这一档就继续造。每支舰队任命一名装甲链接驾驶员。",
			"triggers": "敌人超过 4 跳 → 全舰队散占。敌人超过 2 跳 → 小型三舰一组清本系。任一势力主权 >90% → 先抢主权。没有空间站 → 先集结再去敌人最少的站。只有一支小型且敌人 ≤4 跳 → 改按主力。",
			"rows": [
				{"n": "N < 25", "fleets": ["主力", "小型"], "ratio": "1:2"},
				{"n": "25 ≤ N < 44", "fleets": ["主力", "中型", "小型"], "ratio": "2:2:1"},
				{"n": "N ≥ 44", "fleets": ["主力", "主力", "中型", "小型"], "ratio": "4:4:2:1"},
			],
		},
		{
			"id": "chuang",
			"name": "创",
			"face": "res://assets/ui/deputies/chuang.png",
			"blurb": "创迷信上限降低机制。起初大家对他不屑一顾，后来发现事情有点不对劲。指挥上限 60 人。最多四支舰队：一个中型、一个小型、两个战术换损。",
			"resource": "名下全部人均匀分。",
			"build": "当前能造的吨位里，近防炮 DPS 高者优先，同 DPS 取吨位更高。任命只在战术换损舰队。",
			"triggers": "只有一支小型且敌人 ≤4 跳 → 改按主力。任一势力主权 >90% → 先抢主权。没有空间站 → 先集结再去敌人最少的站。战术换损直接进入敌对更少的格子。",
			"rows": [
				{"n": "N < 10", "fleets": ["小型"], "ratio": "仅"},
				{"n": "10 ≤ N < 20", "fleets": ["小型", "战术换损"], "ratio": "2:1"},
				{"n": "20 ≤ N < 35", "fleets": ["中型", "小型", "战术换损"], "ratio": "2:1:2"},
				{"n": "35 ≤ N ≤ 60", "fleets": ["战术换损", "中型", "小型", "战术换损"], "ratio": "4:3:1:3"},
			],
		},
		{
			"id": "six",
			"name": "6",
			"face": "res://assets/ui/deputies/six.png",
			"blurb": "倾向于船坚炮利。指挥上限 60 人。最多四支舰队：一个主力、一个中型、一个小型、一个盾守。",
			"resource": "盾守成员先每人 4，剩下的在全部被指挥的人之间均分。",
			"build": "盾守任命者造当前能造的最大吨位且默认副装备含护盾立场。其余人用进度条能走的最大吨位。",
			"triggers": "敌人超过 4 跳 → 全舰队散占。敌人超过 2 跳 → 小型三舰一组清本系。任一势力主权 >90% → 先抢主权。没有空间站 → 先集结再去敌人最少的站。盾守：邻系落在非门后星门的相邻格并强制进入；同系停非星门并集火最低血。没有人能开护盾立场舰 → 改为组主力舰队。",
			"rows": [
				{"n": "N < 10", "fleets": ["小型"], "ratio": "仅"},
				{"n": "10 ≤ N < 20", "fleets": ["小型", "盾守"], "ratio": "2:1"},
				{"n": "20 ≤ N < 35", "fleets": ["中型", "小型", "盾守"], "ratio": "2:1:2"},
				{"n": "N ≥ 35", "fleets": ["主力", "中型", "小型", "盾守"], "ratio": "4:3:1:3"},
			],
		},
		{
			"id": "bei",
			"name": "狈",
			"face": "res://assets/ui/deputies/bei.png",
			"blurb": "狈喜欢打后期。指挥上限 60 人。最多五支舰队：两个抢占、三个主力。",
			"split_note": "抢占按人数，主力按吨位权重均分。交界：20 人用 1:1，40 人先抽 20 人进两个抢占。",
			"resource": "每个抢占成员先 1 个资源点，多出来的只分给非抢占成员。",
			"build": "能造毒蜥的优先编入抢占，不够再按团员 id。抢占只造毒蜥。每支主力先各任命一艘护盾立场、一艘装甲链接，再填近防 DPS 高的舰。",
			"triggers": "无敌人 → 抢占四人一组占不同格。邻系 → 全队同一扇星门。本系有敌人 → 停在星门。敌人有战列或战巡 → 朝己方站退一跳。本系有己方站 → 进站直到敌人离开。人数不足 10 且敌人 ≤4 跳 → 小型改按主力。任一势力主权 >90% → 先抢主权。没有空间站 → 先集结再去敌人最少的站。没有人能造毒蜥 → 改为组主力舰队。",
			"rows": [
				{"n": "N < 10", "fleets": ["小型"], "ratio": "全部"},
				{"n": "10–20", "fleets": ["抢占", "主力"], "ratio": "人数 1:1"},
				{"n": "20–40", "fleets": ["抢占", "主力"], "ratio": "人数 1:2"},
				{"n": "40–60", "fleets": ["抢占", "主力"], "ratio": "20 人两队抢占"},
			],
		},
		{
			"id": "i",
			"name": "I",
			"face": "res://assets/ui/deputies/i.png",
			"blurb": "难缠，舰队携带拦截。指挥上限 60 人，最多四支战术主力。",
			"split_note": "队数看人数，进队按吨位权重均分。交界用更高一档。",
			"resource": "专文未写，名下全部人均分。",
			"build": "每队一艘默认含拦截泡发射器的舰。没有就回最近己方站换，没库存则全队聚集排队造。其余人造进度条能走的最大吨位。",
			"triggers": "舰上没有拦截泡发射器 → 回站更换；没有库存 → 就地聚集并排队制造。门后、隔门对峙、战术压迫与主力相同。任一势力主权 >90% → 先抢主权。没有空间站 → 先集结再去敌人最少的站。没有人能开拦截泡舰 → 改为组主力舰队。",
			"rows": [
				{"n": "N < 15", "fleets": ["战术主力"], "ratio": "1 支"},
				{"n": "15 ≤ N < 30", "fleets": ["战术主力"], "ratio": "2 支"},
				{"n": "30 ≤ N < 45", "fleets": ["战术主力"], "ratio": "3 支"},
				{"n": "N ≥ 45", "fleets": ["战术主力"], "ratio": "4 支"},
			],
		},
	]


func _deputy_card(spec: Dictionary) -> Button:
	var b := Button.new()
	b.text = str(spec.get("name", ""))
	b.custom_minimum_size = Vector2(160, 72)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var face_path := str(spec.get("face", ""))
	var tex := load(face_path) as Texture2D
	if tex == null and FileAccess.file_exists(face_path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(face_path))
		if img:
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		b.icon = tex
		b.expand_icon = true
	b.add_theme_stylebox_override("normal", _style(PANEL_BG, PANEL_BORDER))
	b.pressed.connect(_show_deputy.bind(spec))
	return b


func _member_card(member: Dictionary) -> Button:
	var b := Button.new()
	b.text = str(member.get("name", member.get("id", "")))
	b.custom_minimum_size = Vector2(120, 64)
	var tex := MemberTableScr.load_portrait(
		str(member.get("portrait", "")),
		PackedStringArray([str(member.get("id", ""))])
	)
	if tex != null:
		b.icon = tex
		b.expand_icon = true
	b.add_theme_stylebox_override("normal", _style(PANEL_BG, PANEL_BORDER))
	b.pressed.connect(_show_member.bind(member))
	return b


func _ship_card(ship: Dictionary) -> Button:
	var b := Button.new()
	var ton := str(ship.get("tonnage", ""))
	b.text = "%s\n%s" % [str(ship.get("name", ship.get("id", ""))), str(TON_LABEL.get(ton, ton))]
	b.custom_minimum_size = Vector2(150, 72)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var portrait := str(ship.get("portrait", ""))
	if portrait != "" and ResourceLoader.exists(portrait):
		var tex := load(portrait) as Texture2D
		if tex != null:
			b.icon = tex
			b.expand_icon = true
	b.add_theme_stylebox_override("normal", _style(PANEL_BG, PANEL_BORDER))
	b.pressed.connect(_show_ship.bind(ship))
	return b


func _add_deputy_blurb(title: String, body: String) -> void:
	if body == "":
		return
	var lab := Label.new()
	lab.text = "%s\n%s" % [title, body]
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.add_theme_color_override("font_color", Color(0.9, 0.93, 1, 0.95))
	_detail.add_child(lab)


func _show_deputy(spec: Dictionary) -> void:
	_hide_ship_preview()
	_clear_detail()
	_detail.add_child(_big_label(str(spec.get("name", ""))))
	var body := Label.new()
	body.text = str(spec.get("blurb", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", Color.WHITE)
	_detail.add_child(body)
	var note := Label.new()
	note.text = "定档看人数，进队按吨位权重（护卫 1、驱逐 2、巡洋 4、战巡 7、战列 14）。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.9, 0.93, 1, 0.9))
	if str(spec.get("split_note", "")) != "":
		note.text = str(spec.get("split_note", ""))
	_detail.add_child(note)
	_add_deputy_blurb("资源", str(spec.get("resource", "")))
	_add_deputy_blurb("制造", str(spec.get("build", "")))
	_add_deputy_blurb("条件触发", str(spec.get("triggers", "")))
	for row in spec.get("rows", []):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		_detail.add_child(line)
		var nlab := Label.new()
		nlab.text = str(row.get("n", ""))
		nlab.custom_minimum_size = Vector2(130, 0)
		nlab.add_theme_color_override("font_color", Color.WHITE)
		line.add_child(nlab)
		for fleet_name in row.get("fleets", []):
			line.add_child(_fleet_button(str(fleet_name)))
		var ratio := Label.new()
		ratio.text = str(row.get("ratio", ""))
		ratio.add_theme_color_override("font_color", Color(0.85, 0.9, 1, 0.85))
		line.add_child(ratio)


func _fleet_button(fleet_name: String) -> Button:
	var b := Button.new()
	b.text = fleet_name
	b.custom_minimum_size = Vector2(88, 32)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_stylebox_override("normal", _style(FLEET_BG, FLEET_BORDER))
	b.add_theme_stylebox_override("hover", _style(Color(0.9, 0.94, 1.0, 0.18), Color(1, 1, 1, 0.7)))
	b.mouse_entered.connect(_show_fleet_hover.bind(b, fleet_name))
	b.mouse_exited.connect(func() -> void:
		if _hover:
			_hover.visible = false
	)
	return b


func _show_fleet_hover(btn: Button, fleet_name: String) -> void:
	if _hover == null or _hover_label == null:
		return
	_hover_label.text = "%s详情\n%s" % [fleet_name, str(FLEET_DETAIL.get(fleet_name, ""))]
	var origin := btn.global_position + Vector2(0, btn.size.y + 6)
	_hover.position = origin - global_position
	_hover.visible = true


func _show_member(member: Dictionary) -> void:
	_hide_ship_preview()
	_clear_detail()
	_detail.add_child(_big_label(str(member.get("name", ""))))
	var bio := Label.new()
	bio.text = str(member.get("bio", ""))
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.add_theme_color_override("font_color", Color.WHITE)
	_detail.add_child(bio)
	var rank := Label.new()
	rank.text = "等级 %s" % str(member.get("rank", ""))
	rank.add_theme_color_override("font_color", Color.WHITE)
	_detail.add_child(rank)
	var bonus := str(member.get("bonus", "")).strip_edges()
	if bonus != "":
		var bonus_l := Label.new()
		bonus_l.text = "人物装备  %s" % bonus
		bonus_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bonus_l.add_theme_color_override("font_color", Color.WHITE)
		_detail.add_child(bonus_l)
	var grouped: Dictionary = {}
	for sid in str(member.get("ships", "")).split("|", false):
		var ship_id := str(sid).strip_edges()
		if ship_id.is_empty():
			continue
		var def: Dictionary = _ships.get(ship_id, {})
		var ton := str(def.get("tonnage", ""))
		if not grouped.has(ton):
			grouped[ton] = []
		grouped[ton].append(str(def.get("name", ship_id)))
	for ton in ["frigate", "destroyer", "cruiser", "battlecruiser", "battleship"]:
		if not grouped.has(ton):
			continue
		var line := Label.new()
		line.text = "%s  %s" % [str(TON_LABEL.get(ton, ton)), "、".join(PackedStringArray(grouped[ton]))]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_color_override("font_color", Color(0.92, 0.95, 1, 0.95))
		_detail.add_child(line)


func _show_ship(ship: Dictionary) -> void:
	_clear_detail()
	_detail.add_child(_big_label(str(ship.get("name", ship.get("id", "")))))
	var ton := str(ship.get("tonnage", ""))
	var ton_l := Label.new()
	ton_l.text = "吨位  %s" % str(TON_LABEL.get(ton, ton))
	ton_l.add_theme_color_override("font_color", Color.WHITE)
	_detail.add_child(ton_l)
	var pilot_l := Label.new()
	pilot_l.text = "驾驶员"
	pilot_l.add_theme_color_override("font_color", Color.WHITE)
	_detail.add_child(pilot_l)
	_detail.add_child(_section_label("默认装备"))
	for line in _default_equip_lines(ship):
		var lab := Label.new()
		lab.text = line
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.add_theme_color_override("font_color", Color(0.92, 0.95, 1, 0.95))
		_detail.add_child(lab)
	_show_ship_preview(str(ship.get("model", ship.get("id", ""))))


func _default_equip_lines(ship: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var fit: Dictionary = ship.get("fit", {})
	var slots: Array = fit.get("slots", [])
	for i in slots.size():
		var slot_ref = slots[i]
		if slot_ref == null or str(slot_ref) == "":
			lines.append("副装%d  空" % (i + 1))
			continue
		var sid := str(slot_ref)
		var eq: Dictionary = _equip.get(sid, {})
		var ename := str(eq.get("name", sid))
		lines.append("副装%d  %s — %s" % [i + 1, ename, _describe_slot_equip(sid, eq)])
	for h in fit.get("hidden", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var line := _describe_hidden_equip(h)
		if line != "":
			lines.append(line)
	if lines.is_empty():
		lines.append("（无默认装备）")
	return lines


func _describe_slot_equip(sid: String, eq: Dictionary) -> String:
	match sid:
		"bubble":
			return "拦截泡；拉力%d格；最短持续%ds；电容%d" % [
				int(eq.get("pull_range_cells", 3)), int(eq.get("min_uptime_s", 15)), int(eq.get("cap_cost", 0))
			]
		"shield_field":
			return "守卫护盾立场"
		"armor_link":
			return "守卫装甲链接"
		"shield_booster_m":
			return "周期%.1fs；护盾+%d；电容%d" % [
				float(eq.get("cycle_s", 0)), int(eq.get("heal_shield", 0)), int(eq.get("cap_cost", 0))
			]
		"armor_repairer_m":
			return "周期%.1fs；装甲+%d；电容%d" % [
				float(eq.get("cycle_s", 0)), int(eq.get("heal_armor", 0)), int(eq.get("cap_cost", 0))
			]
		_:
			return str(eq.get("name", sid))


func _describe_hidden_equip(h: Dictionary) -> String:
	var kind := str(h.get("kind", ""))
	match kind:
		"pd":
			var ref := str(h.get("ref", ""))
			var eq: Dictionary = _equip.get(ref, {})
			var n := int(h.get("count", 1))
			var nm := str(eq.get("name", ref))
			if n > 1:
				nm = "%s×%d" % [nm, n]
			return "%s — 周期%.1fs；伤%d；电容%d；同系近防无需锁定" % [
				nm, float(eq.get("cycle_s", 0)), int(eq.get("damage", 0)), int(eq.get("cap_cost", 0))
			]
		"weapon":
			var wref := str(h.get("ref", ""))
			var weq: Dictionary = _equip.get(wref, {})
			var rc := int(h.get("range_cells", weq.get("range_cells", 0)))
			var wnm := str(weq.get("name", wref))
			var dmg_parts: PackedStringArray = PackedStringArray()
			if float(weq.get("damage_emp", 0)) > 0.0:
				dmg_parts.append("电磁%.0f" % float(weq.get("damage_emp", 0)))
			if float(weq.get("damage_thermal", 0)) > 0.0:
				dmg_parts.append("热能%.0f" % float(weq.get("damage_thermal", 0)))
			if float(weq.get("damage_kinetic", 0)) > 0.0:
				dmg_parts.append("动能%.0f" % float(weq.get("damage_kinetic", 0)))
			if float(weq.get("damage_explosive", 0)) > 0.0:
				dmg_parts.append("爆炸%.0f" % float(weq.get("damage_explosive", 0)))
			if int(weq.get("heal_armor", 0)) > 0:
				dmg_parts.append("装甲+%d" % int(weq.get("heal_armor", 0)))
			var dmg_s := "、".join(dmg_parts) if not dmg_parts.is_empty() else "—"
			return "%s — 射程%d格；周期%.1fs；%s；电容%d" % [
				wnm, rc, float(weq.get("cycle_s", 0)), dmg_s, int(weq.get("cap_cost", 0))
			]
		"implant":
			var iref := str(h.get("ref", ""))
			var ieq: Dictionary = _equip.get(iref, {})
			var inm := str(ieq.get("name", iref))
			match iref:
				"implant_sniper":
					var sdesc := str(ieq.get("desc", ""))
					if sdesc != "":
						return "%s — %s" % [inm, sdesc]
					return "%s — 伤害周期×%d，单发×%d，跟踪×%d" % [
						inm, int(ieq.get("every", 10)), int(ieq.get("mul", 10)), int(ieq.get("tracking_mul", 1000))
					]
				"implant_focus_crystal":
					return "%s — 叠层+%d%%；电容+%d%%；护盾冷却%d" % [
						inm, int(ieq.get("stack_pct", 0)), int(ieq.get("cap_pct", 0)), int(ieq.get("shield_cd", 0))
					]
				"implant_armor_support":
					return "%s — 抗性+%d%%" % [inm, int(ieq.get("res_pct", 0))]
				_:
					return inm
		"range_mul":
			return "射程倍率 — 武器射程×%.1f" % float(h.get("value", 1.0))
		"resistance_mul":
			return "抗性倍率 — 抗性×%.1f（封顶100）" % float(h.get("value", 1.0))
		"pd_damage_mul":
			return "近防伤害倍率 — 近防伤害×%.1f" % float(h.get("value", 1.0))
		"shield_regen":
			return "护盾回复 — 护盾自然回复"
		"cap_regen":
			return "电容回复 — 电容自然回复"
		"bubble_immune":
			return "泡免疫 — 不受拦截泡牵引"
		_:
			return ""


func _show_ship_preview(model_key: String) -> void:
	if _preview_host == null or _preview_world == null:
		return
	_clear_preview_model()
	_preview_yaw = 0.0
	_preview_pivot.rotation.y = 0.0
	if model_key == "" or not SHIP_ART.has_model(model_key):
		_preview_host.visible = false
		_preview_active = false
		return
	var holder := Node3D.new()
	holder.name = "ShipHolder"
	_preview_world.add_child(holder)
	var inst: Node3D = SHIP_ART.spawn_model(holder, model_key, PREVIEW_MODEL_D)
	if inst == null:
		holder.queue_free()
		_preview_host.visible = false
		_preview_active = false
		return
	_preview_host.visible = true
	_preview_active = true


func _clear_preview_model() -> void:
	if _preview_world == null:
		return
	## Sync free — queue_free stacks multiple ShipHolders across clicks (BH-51).
	var doomed: Array = []
	for c in _preview_world.get_children():
		if str(c.name).begins_with("ShipHolder"):
			doomed.append(c)
	for c in doomed:
		_preview_world.remove_child(c)
		c.free()


func _hide_ship_preview() -> void:
	_preview_active = false
	_clear_preview_model()
	if _preview_host:
		_preview_host.visible = false


func _show_hint(text: String) -> void:
	_hide_ship_preview()
	_clear_detail()
	var hint := Label.new()
	hint.text = text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_detail.add_child(hint)


func _clear_detail() -> void:
	if _detail == null:
		return
	for c in _detail.get_children():
		c.queue_free()


func _big_label(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 26)
	lab.add_theme_color_override("font_color", Color.WHITE)
	return lab


func _section_label(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 18)
	lab.add_theme_color_override("font_color", Color.WHITE)
	return lab


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(PANEL_BG, PANEL_BORDER))
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return p


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	return sb
