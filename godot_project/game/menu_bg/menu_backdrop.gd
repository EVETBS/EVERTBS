extends Node3D
## Main-menu live bigmap backdrop (ported from evertbs-bigmap CG preview).

const MAP_JSON := "res://game/menu_bg/data/starfield_topology_annot_complete_v1.json"
const RAISE_Y_BASE := 1.2
const DEFAULT_CAM_POS := Vector3(-85.2876, 216.1264, 1921.6818)
const DEFAULT_CAM_PITCH := -0.3507
const DEFAULT_CAM_YAW := -0.3675
const RING_PER_FRAME := 20
const SKY_TEX := "res://game/menu_bg/assets/skyboxes/board_panorama.jpeg"
const BigmapFromStarfieldScr := preload("res://game/menu_bg/bigmap_from_starfield.gd")
const BoardPresenterScr := preload("res://game/menu_bg/board_presenter.gd")
const TerritoryBakerScr := preload("res://game/menu_bg/territory_baker.gd")
const MenuSkirmishScr := preload("res://game/menu_bg/menu_skirmish.gd")

@onready var rings_root: Node3D = $Rings
@onready var territory_root: Node3D = $Territory
@onready var camera: Camera3D = $PreviewCamera
@onready var world_env: WorldEnvironment = $WorldEnvironment

var _map
var _board
var _raise_y := 0.59
var _fill_y := 0.02
var _skirmish: Node
var _running := false


func _ready() -> void:
	_setup_skybox()
	camera.current = true
	_boot.call_deferred()


func _boot() -> void:
	if _running:
		return
	_running = true
	await get_tree().process_frame
	var map = BigmapFromStarfieldScr.new()
	map.load_annot(MAP_JSON, 20261013)
	_map = map
	camera.global_position = DEFAULT_CAM_POS
	camera.rotation = Vector3(DEFAULT_CAM_PITCH, DEFAULT_CAM_YAW, 0.0)
	var icons := Node3D.new()
	icons.name = "Icons"
	add_child(icons)
	var links := Node3D.new()
	links.name = "Links"
	add_child(links)
	var board = BoardPresenterScr.new()
	_board = board
	board.begin(map, rings_root, icons, links)
	while not board.step_rings(RING_PER_FRAME):
		await get_tree().process_frame
	await get_tree().process_frame
	board.build_icons_and_links()
	await _load_territory()
	_start_menu_skirmish()


func _start_menu_skirmish() -> void:
	var sk: Node = MenuSkirmishScr.new()
	sk.name = "MenuSkirmish"
	add_child(sk)
	_skirmish = sk
	if "allow_cam_controls" in sk:
		sk.allow_cam_controls = false
	sk.setup(_map, _board, camera, territory_root)


func _load_territory() -> void:
	if _map == null:
		return
	_raise_y = maxf(6.0, RAISE_Y_BASE * maxf(1.0, float(_map.map_scale))) / 20.0
	var baker = TerritoryBakerScr.new()
	baker.build_vector_dual_layers(
		territory_root, _map, 0.05, 0.2, _raise_y, 0.42, true
	)
	var grid_args: Dictionary = territory_root.get_meta("territory_grid_args", {})
	if not grid_args.is_empty():
		var task_id := WorkerThreadPool.add_task(
			baker.build_site_grid.bind(grid_args), false, "menu territory grid"
		)
		while not WorkerThreadPool.is_task_completed(task_id):
			await get_tree().process_frame
		var wait_error := WorkerThreadPool.wait_for_task_completion(task_id)
		if wait_error == OK:
			baker.apply_site_grid(territory_root, baker.take_site_grid())
		else:
			push_warning("menu territory grid worker failed: %s" % error_string(wait_error))
		territory_root.remove_meta("territory_grid_args")
	var fill := territory_root.get_node_or_null("TerritoryFill") as Node3D
	if fill:
		_fill_y = fill.position.y
	var stroke := territory_root.get_node_or_null("TerritoryStrokeRaised") as Node3D
	if stroke:
		stroke.position.y = _fill_y + _raise_y


func _setup_skybox() -> void:
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sky_tex = load(SKY_TEX)
	if sky_tex:
		e.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var pan := PanoramaSkyMaterial.new()
		pan.panorama = sky_tex
		pan.energy_multiplier = 1.25
		sky.sky_material = pan
		e.sky = sky
	else:
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.01, 0.02, 0.04)
	world_env.environment = e


func stop_backdrop() -> void:
	set_process(false)
	if _skirmish != null and is_instance_valid(_skirmish):
		_skirmish.queue_free()
		_skirmish = null
	_running = false
