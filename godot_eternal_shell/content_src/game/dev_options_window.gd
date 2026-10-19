extends Window
## Developer options. Does not pause the match.

const DevBalance := preload("res://game/board/dev_balance.gd")
const GlobalPanel := preload("res://game/global_data_panel.gd")

var _master: CheckButton
var _build: CheckButton
var _resource: CheckButton
var _faction: OptionButton
var _switch: Button
var _global: Button
var _hint: Label

func _ready() -> void:
	title = "开发者选项"
	size = Vector2i(460, 320)
	unresizable = true
	exclusive = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_requested.connect(hide)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 12)
	root.add_theme_constant_override("margin_right", 12)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_bottom", 12)
	add_child(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)
	_master = CheckButton.new()
	_master.text = "启用开发者选项"
	_master.toggled.connect(_on_master)
	box.add_child(_master)
	_build = CheckButton.new()
	_build.text = "单位制造时间 1 秒"
	_build.toggled.connect(_on_build)
	box.add_child(_build)
	_resource = CheckButton.new()
	_resource.text = "全体我方满资源点"
	_resource.toggled.connect(_on_resource)
	box.add_child(_resource)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var lab := Label.new()
	lab.text = "换边到势力"
	row.add_child(lab)
	_faction = OptionButton.new()
	_faction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_faction)
	_switch = Button.new()
	_switch.text = "换边"
	_switch.pressed.connect(_on_switch)
	row.add_child(_switch)
	_hint = Label.new()
	_hint.text = "进局后可用"
	box.add_child(_hint)
	_global = Button.new()
	_global.text = "全局数据调整"
	_global.pressed.connect(_on_global)
	box.add_child(_global)

func present() -> void:
	DevBalance.load()
	_fill_factions()
	_master.set_pressed_no_signal(DevBalance.master_on)
	_build.set_pressed_no_signal(DevBalance.want_build_1s)
	_resource.set_pressed_no_signal(DevBalance.want_resource)
	_refresh_enabled()
	popup_centered()

func _fill_factions() -> void:
	_faction.clear()
	var rows: Array = []
	var board := _board()
	if board != null:
		var data = board.get("data")
		if data != null:
			rows = data.factions.get("factions", [])
	if rows.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/board/factions.json"))
		if typeof(parsed) == TYPE_DICTIONARY:
			rows = parsed.get("factions", [])
	for f in rows:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		if bool(f.get("npc", false)):
			continue
		var fid := int(f.get("id", -1))
		var name := str(f.get("name", fid))
		_faction.add_item("%s (%d)" % [name, fid], fid)

func _refresh_enabled() -> void:
	var on := DevBalance.master()
	var in_match := _board() != null
	_build.disabled = not on
	_resource.disabled = not on
	_faction.disabled = not on or not in_match
	_switch.disabled = not on or not in_match
	_global.disabled = not on
	_hint.visible = not in_match

func _on_master(on: bool) -> void:
	DevBalance.set_master(on)
	_push_resource()
	_refresh_enabled()
	_log_ui("启用开发者选项")

func _on_build(on: bool) -> void:
	DevBalance.set_want_build(on)
	_log_ui("单位制造时间 1 秒")

func _on_resource(on: bool) -> void:
	DevBalance.set_want_resource(on)
	_push_resource()
	_log_ui("全体我方满资源点")

func _on_switch() -> void:
	var board = _board()
	if board == null or not DevBalance.master():
		return
	var fid := _faction.get_selected_id()
	if fid < 0:
		return
	if board.has_method("dev_switch_viewer"):
		board.dev_switch_viewer(fid)
	_log_ui("换边")

func _on_global() -> void:
	if not DevBalance.master():
		return
	var host := get_parent()
	if host == null:
		return
	var panel := host.get_node_or_null("GlobalDataPanel")
	if panel == null:
		panel = GlobalPanel.new()
		panel.name = "GlobalDataPanel"
		host.add_child(panel)
	if panel.has_method("present"):
		panel.present()
	_log_ui("全局数据调整")

func _push_resource() -> void:
	var board = _board()
	if board != null and board.has_method("dev_push_resource_bonus"):
		board.dev_push_resource_bonus(DevBalance.master() and DevBalance.want_resource)

func _log_ui(control: String) -> void:
	var board := _board()
	var paused := false
	var viewer := -1
	if board != null:
		paused = bool(board.get("sim_paused"))
		viewer = int(board.get("viewer_faction"))
	DebugSessionLog.append("UI", "dev_options_window", "click", {
		"control": control,
		"master": DevBalance.master_on,
		"build_disabled": _build.disabled,
		"resource_disabled": _resource.disabled,
		"faction_disabled": _faction.disabled,
		"switch_disabled": _switch.disabled,
		"global_disabled": _global.disabled,
		"hint_visible": _hint.visible,
		"hint": _hint.text,
		"sim_paused": paused,
		"viewer_faction": viewer,
		"runId": "grok-ui",
	})

func _board() -> Node:
	var nodes := get_tree().get_nodes_in_group("evertbs_board")
	if nodes.is_empty():
		return null
	return nodes[0]
