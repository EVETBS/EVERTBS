extends Node3D
class_name BoardStarmapView

const DevBalance := preload("res://game/board/dev_balance.gd")

var map: BoardMapModel
var diplomacy: Dictionary
var viewer = 1
## Faction ids marked npc:true — painted as unowned on territory (CAPTURE.md).
var npc_faction_ids: Dictionary = {}
var units_ref: Array = []
var transit_gates: Dictionary = {}
var label_root: Node3D
var icon_root: Node3D
var territory_root: Node3D
var pilots_ref: Array = []
var cell_pick_root: Node3D
var link_cam: Camera3D
## visual_scale per system id (smoothed)
var visual_scales: Dictionary = {}
## sid -> true when that system is outside vision. Empty means fog is off.
var fog_mask: Dictionary = {}

func _work_full(c: Dictionary) -> float:
	return DevBalance.work_cap(int(c.get("kind", 0)))

@onready var mesh_inst: MeshInstance3D = $Mesh

var SECTOR_ICON: Dictionary = {
	1: "res://assets/ui/sector/stargate.png",
	2: "res://assets/ui/sector/resource.png",
	3: "res://assets/ui/sector/station.png",
	4: "res://assets/ui/sector/sov.png",
}

const ICON_REF_DIST := 60.0
const ICON_BASE_PIXEL := 0.072
## Locked: tactical icon scale; 战场视角 uses ORBIT_ICON_SCALE (×1.5 base).
const ORBIT_ICON_SCALE := 1.5
const BATTLE_SYSNAME_SCALE := 1.0
const STARMAP_ICON_SCALE := 4.2
var icon_scale: float = 5.6
var _tactical_icon_mode := false
## "battle" | "tactical" | "starmap"
var view_tier: String = "battle"
var border_jagged: float = 0.16
var system_name_scale: float = 1.85 ## tactical
var starmap_name_scale: float = 6.55 ## 星图星系名倍率（固化）
var starmap_icon_scale: float = 2.6 ## 星图系标倍率（固化）
var starmap_badge_scale: float = 10.05 ## 声望角标图标倍率（固化）
var starmap_count_scale: float = 8.55 ## 人数数字倍率（固化）
var starmap_highlight_sys: String = "" ## 点选/指令目标系（黄光晕）
var _starmap_counts_cache: Dictionary = {}
var _voronoi_mi: MeshInstance3D = null
var _rep_badge_tex: Dictionary = {} ## rel key -> Texture2D
## Point-line starmap redraw (only visible in 星图视角).
var starmap_graph_root: Node3D = null
const RIM_THICK := 0.64
const WEDGE_SEGS := 8
const CURTAIN_H0 := 0.15
const CURTAIN_H1 := 4.65
## INSTANCE_CUSTOM 0..1 pack; shader unpacks with r_scale (BH-35).
const CUSTOM_R_SCALE := 64.0
## Per system: 12 separator key points on transparent seams (STARMAP §2.0).
const KEY_COUNT := 12

## GPU board: unit wedge × MultiMesh × data texture (BH-35).
var _fill_mmi: MultiMeshInstance3D
var _rim_mmi: MultiMeshInstance3D
var _link_mmi: MultiMeshInstance3D
var _tip_mmi: MultiMeshInstance3D
var _curtain_mmi: MultiMeshInstance3D
var _fill_mm: MultiMesh
var _rim_mm: MultiMesh
var _link_mm: MultiMesh
var _tip_mm: MultiMesh
var _curtain_mm: MultiMesh
var _cell_img: Image
var _cell_tex: ImageTexture
var _curtain_img: Image
var _curtain_tex: ImageTexture
var _fill_mat: ShaderMaterial
var _rim_mat: ShaderMaterial
var _link_mat: Material
var _tip_mat: Material
var _curtain_mat: ShaderMaterial
var _cell_capacity: int = 0
var _link_capacity: int = 0
var _curtain_capacity: int = 0
var _index_map: Array = [] ## [{sid, cell}]
var _gpu_ready := false
var _gpu_ok := false
## Per-system annulus + 12 key uniforms (not deforming MultiMesh wedges).
var _gpu_draw_enabled := true
var _curtain_mesh_rev := 0
const CURTAIN_MESH_REV := 7 ## bump when _build_unit_curtain / shader recipe changes
var _ring_root: Node3D
var _ring_ready := false
## Static triangle BVH of the shared Fill/Rim meshes. Built once; click uses the node's live transform.
var _fill_pick: Dictionary = {}
var _rim_pick: Dictionary = {}
## Scale 补间 + throttled sector paint (avoid continuous micro-stutter).
var _scale_tween_targets: Dictionary = {}
var _scale_tweens: Dictionary = {}
var _ring_paint_acc := 0.0
const RING_PAINT_DT := 0.07
## Occupancy scale-up: longer settle so dest ships don't jump (BH-36).
const SCALE_TWEEN_DUR := 0.95

# region agent log
func _dbg59_board(hid: String, loc: String, msg: String, data: Dictionary = {}) -> void:
	var path := "h:/debug-59aff0.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "59aff0",
		"hypothesisId": hid,
		"location": loc,
		"message": msg,
		"data": data,
		"timestamp": Time.get_ticks_msec(),
		"runId": str(data.get("runId", "pre-fix"))
	}))
	f.close()
# endregion


func setup(m: BoardMapModel, dipl: Dictionary, viewer_fac: int) -> void:
	map = m
	diplomacy = dipl
	viewer = viewer_fac
	_ensure_mesh_inst()
	_ensure_gpu_board()
	if label_root == null:
		label_root = Node3D.new()
		label_root.name = "ResourceLabels"
		add_child(label_root)
	if icon_root == null:
		icon_root = Node3D.new()
		icon_root.name = "SectorIcons"
		add_child(icon_root)
	if territory_root == null:
		territory_root = Node3D.new()
		territory_root.name = "Territory"
		add_child(territory_root)
		move_child(territory_root, 0)
		## view_tier is already battle before setup; do not leave this hidden.
		territory_root.visible = _territory_visible_for_tier()
	if cell_pick_root == null:
		cell_pick_root = Node3D.new()
		cell_pick_root.name = "CellPick"
		add_child(cell_pick_root)
	## Analytic pick only — clear any legacy per-cell StaticBody3D.
	_clear_cell_pick()
	for sid in map.systems.keys():
		## Sync visual to occupancy target immediately (empty systems start shrunk).
		var tgt := float(map.systems[sid].get("scale", 1.0))
		visual_scales[sid] = tgt
		map.systems[sid]["visual_scale"] = tgt
	rebuild()

func _ensure_mesh_inst() -> void:
	if mesh_inst != null and is_instance_valid(mesh_inst):
		return
	mesh_inst = get_node_or_null("Mesh") as MeshInstance3D
	if mesh_inst != null:
		return
	mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	add_child(mesh_inst)

func _ensure_gpu_board() -> void:
	if _gpu_ready:
		if _curtain_mesh_rev < CURTAIN_MESH_REV and _curtain_mm:
			_curtain_mm.mesh = _build_unit_curtain(8, 12)
			## Hot-reload shader recipe with mesh rev (UTF-8 / blend_add albedo path).
			var sh2: Shader = load("res://shaders/board_guard_curtain.gdshader")
			if sh2 and _curtain_mat:
				_curtain_mat.shader = sh2
			_curtain_mesh_rev = CURTAIN_MESH_REV
			# #region agent log
			_dbg59_board("CUR", "starmap._ensure_gpu_board", "mesh_rev_bump", {
				"rev": CURTAIN_MESH_REV,
				"albedo_mul": sh2 != null and sh2.get_code().contains("ALBEDO = rgb *"),
				"blend_add": sh2 != null and sh2.get_code().contains("blend_add"),
				"runId": "curtain-chain"
			})
			# #endregion
		return
	var wedge_fill := _build_unit_wedge(WEDGE_SEGS)
	var wedge_rim := _build_unit_wedge(WEDGE_SEGS)
	var shaft := _build_unit_shaft()
	var tip := _build_unit_tip()
	var curtain := _build_unit_curtain(8, 12)

	_fill_mat = _make_cell_mat(false)
	_rim_mat = _make_cell_mat(true)
	## Links use vertex colors — no custom deform shader (that path drew nothing).
	_link_mat = StandardMaterial3D.new()
	_link_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_link_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_link_mat.vertex_color_use_as_albedo = true
	_link_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tip_mat = _link_mat
	_curtain_mat = ShaderMaterial.new()
	var curtain_sh: Shader = load("res://shaders/board_guard_curtain.gdshader")
	_curtain_mat.shader = curtain_sh
	# #region agent log
	_dbg59_board("H1", "starmap._ensure_gpu_board", "curtain_shader", {
		"shader_ok": curtain_sh != null,
		"code_len": curtain_sh.get_code().length() if curtain_sh else 0,
		"has_varying": curtain_sh != null and curtain_sh.get_code().contains("v_instance_id"),
		"runId": "curtain-shader-fix"
	})
	# #endregion
	_gpu_ok = _fill_mat.shader != null and _rim_mat.shader != null

	_fill_mm = MultiMesh.new()
	_fill_mm.transform_format = MultiMesh.TRANSFORM_3D
	_fill_mm.use_custom_data = true
	_fill_mm.mesh = wedge_fill
	_rim_mm = MultiMesh.new()
	_rim_mm.transform_format = MultiMesh.TRANSFORM_3D
	_rim_mm.use_custom_data = true
	_rim_mm.mesh = wedge_rim
	_link_mm = MultiMesh.new()
	_link_mm.transform_format = MultiMesh.TRANSFORM_3D
	_link_mm.use_colors = true
	_link_mm.mesh = shaft
	_tip_mm = MultiMesh.new()
	_tip_mm.transform_format = MultiMesh.TRANSFORM_3D
	_tip_mm.use_colors = true
	_tip_mm.mesh = tip
	_curtain_mm = MultiMesh.new()
	_curtain_mm.transform_format = MultiMesh.TRANSFORM_3D
	_curtain_mm.mesh = curtain

	## Large custom AABB — vertex shader expands far beyond unit mesh bounds (H1).
	var board_aabb := AABB(Vector3(-400, -5, -400), Vector3(800, 20, 800))
	_fill_mmi = MultiMeshInstance3D.new()
	_fill_mmi.name = "GpuFill"
	_fill_mmi.multimesh = _fill_mm
	_fill_mmi.material_override = _fill_mat
	_fill_mmi.custom_aabb = board_aabb
	_fill_mmi.extra_cull_margin = 128.0
	add_child(_fill_mmi)
	_rim_mmi = MultiMeshInstance3D.new()
	_rim_mmi.name = "GpuRim"
	_rim_mmi.multimesh = _rim_mm
	_rim_mmi.material_override = _rim_mat
	_rim_mmi.custom_aabb = board_aabb
	_rim_mmi.extra_cull_margin = 128.0
	add_child(_rim_mmi)
	_link_mmi = MultiMeshInstance3D.new()
	_link_mmi.name = "GpuLinks"
	_link_mmi.multimesh = _link_mm
	_link_mmi.material_override = _link_mat
	_link_mmi.custom_aabb = board_aabb
	_link_mmi.extra_cull_margin = 128.0
	add_child(_link_mmi)
	_tip_mmi = MultiMeshInstance3D.new()
	_tip_mmi.name = "GpuTips"
	_tip_mmi.multimesh = _tip_mm
	_tip_mmi.material_override = _tip_mat
	_tip_mmi.custom_aabb = board_aabb
	add_child(_tip_mmi)
	_curtain_mmi = MultiMeshInstance3D.new()
	_curtain_mmi.name = "GpuCurtains"
	_curtain_mmi.multimesh = _curtain_mm
	_curtain_mmi.material_override = _curtain_mat
	_curtain_mmi.custom_aabb = board_aabb
	_curtain_mmi.extra_cull_margin = 128.0
	add_child(_curtain_mmi)
	_curtain_mesh_rev = CURTAIN_MESH_REV
	_gpu_ready = true
	_set_gpu_meshes_visible(_gpu_draw_enabled and _gpu_ok)
	# #region agent log
	_dbg59_board("VIS", "starmap._ensure_gpu_board", "gpu_init", {
		"gpu_ok": _gpu_ok,
		"gpu_draw": _gpu_draw_enabled,
		"fill_shader": _fill_mat != null and _fill_mat.shader != null,
		"link_std": _link_mat is StandardMaterial3D,
		"runId": "post-fix"
	})
	# #endregion
	if mesh_inst:
		mesh_inst.visible = not (_gpu_draw_enabled and _gpu_ok)

func _set_gpu_meshes_visible(on: bool) -> void:
	## 星图: hide all battle/tactical GPU board meshes (point-line graph is separate).
	if view_tier == "starmap":
		for mmi in [_fill_mmi, _rim_mmi, _link_mmi, _tip_mmi, _curtain_mmi]:
			if mmi:
				mmi.visible = false
		return
	for mmi in [_fill_mmi, _rim_mmi, _link_mmi, _tip_mmi, _curtain_mmi]:
		if mmi:
			mmi.visible = on

func _apply_battle_gpu_vis() -> void:
	## StdMat rings own fill/rim. Keep GPU curtains + gate links/tips (BH-39).
	if view_tier == "starmap":
		_set_gpu_meshes_visible(false)
		if mesh_inst:
			mesh_inst.visible = false
		if _ring_root:
			_ring_root.visible = false
		return
	if _fill_mmi:
		_fill_mmi.visible = false
	if _rim_mmi:
		_rim_mmi.visible = false
	if _link_mmi:
		_link_mmi.visible = true
	if _tip_mmi:
		_tip_mmi.visible = true
	if _curtain_mmi:
		_curtain_mmi.visible = true
	if mesh_inst:
		mesh_inst.visible = false
	if _ring_root:
		_ring_root.visible = true

func _make_cell_mat(rim: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/board_cell_wedge.gdshader")
	mat.set_shader_parameter("rim_thick", RIM_THICK)
	mat.set_shader_parameter("r_scale", CUSTOM_R_SCALE)
	mat.set_shader_parameter("is_rim", 1 if rim else 0)
	## Seed 1x4 so first sample is never unbound black (H3).
	var seed_img := Image.create(1, 4, false, Image.FORMAT_RGBAF)
	seed_img.set_pixel(0, 0, Color(0, 0, 0, TAU))
	seed_img.set_pixel(0, 1, Color(12, 26, 1, 1))
	seed_img.set_pixel(0, 2, Color(0.5, 0.5, 0.55, 0.7))
	seed_img.set_pixel(0, 3, Color(1, 1, 1, 1))
	var seed_tex := ImageTexture.create_from_image(seed_img)
	mat.set_shader_parameter("cell_data", seed_tex)
	mat.set_shader_parameter("data_width", 1.0)
	return mat

func _build_unit_wedge(segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## Tiny UV wedge only — cull via custom_aabb. Full-circle placeholder caused huge gray blocks (H6).
	for i in segs:
		var u0 := float(i) / float(segs)
		var u1 := float(i + 1) / float(segs)
		_st_uv_tri(st, Vector3(u0, 0, 0), Vector2(u0, 0.0), Vector3(u1, 0, 0), Vector2(u1, 0.0), Vector3(u1, 0, 1), Vector2(u1, 1.0))
		_st_uv_tri(st, Vector3(u0, 0, 0), Vector2(u0, 0.0), Vector3(u1, 0, 1), Vector2(u1, 1.0), Vector3(u0, 0, 1), Vector2(u0, 1.0))
	st.generate_normals()
	return st.commit()

func _build_unit_shaft() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## X 0..1 along length, Z ±0.5 half-width, Y=0.
	var a := Vector3(0, 0.05, 0.5)
	var b := Vector3(1, 0.05, 0.5)
	var c := Vector3(1, 0.05, -0.5)
	var d := Vector3(0, 0.05, -0.5)
	_st_uv_tri(st, a, Vector2(0, 0), b, Vector2(1, 0), c, Vector2(1, 1))
	_st_uv_tri(st, a, Vector2(0, 0), c, Vector2(1, 1), d, Vector2(0, 1))
	st.generate_normals()
	return st.commit()

func _build_unit_tip() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## Tip at x=1, base at x=0 spanning z ±1.
	_st_uv_tri(st, Vector3(1, 0.05, 0), Vector2(1, 0.5), Vector3(0, 0.05, 1), Vector2(0, 1), Vector3(0, 0.05, -1), Vector2(0, 0))
	st.generate_normals()
	return st.commit()

func _build_unit_curtain(r_segs: int, y_segs: int) -> ArrayMesh:
	## Open ribbon: UV (u,v) wall; VERTEX.z = angular thickness sample. No lids/caps.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const A_SEGS := 3
	for i in r_segs:
		for yi in y_segs:
			for ai in A_SEGS:
				var u0 := float(i) / float(r_segs)
				var u1 := float(i + 1) / float(r_segs)
				var v0 := float(yi) / float(y_segs)
				var v1 := float(yi + 1) / float(y_segs)
				var z0 := float(ai) / float(A_SEGS) * 2.0 - 1.0
				var z1 := float(ai + 1) / float(A_SEGS) * 2.0 - 1.0
				_st_uv_tri(st, Vector3(u0, v0, z0), Vector2(u0, v0), Vector3(u0, v1, z0), Vector2(u0, v1), Vector3(u1, v0, z0), Vector2(u1, v0))
				_st_uv_tri(st, Vector3(u0, v1, z0), Vector2(u0, v1), Vector3(u1, v1, z0), Vector2(u1, v1), Vector3(u1, v0, z0), Vector2(u1, v0))
				_st_uv_tri(st, Vector3(u0, v0, z1), Vector2(u0, v0), Vector3(u1, v0, z1), Vector2(u1, v0), Vector3(u0, v1, z1), Vector2(u0, v1))
				_st_uv_tri(st, Vector3(u0, v1, z1), Vector2(u0, v1), Vector3(u1, v0, z1), Vector2(u1, v0), Vector3(u1, v1, z1), Vector2(u1, v1))
	return st.commit()

func _st_uv_tri(st: SurfaceTool, a: Vector3, uva: Vector2, b: Vector3, uvb: Vector2, c: Vector3, uvc: Vector2) -> void:
	st.set_uv(uva)
	st.add_vertex(a)
	st.set_uv(uvb)
	st.add_vertex(b)
	st.set_uv(uvc)
	st.add_vertex(c)

func set_units(u: Array) -> void:
	units_ref = u

func set_camera(c: Camera3D) -> void:
	link_cam = c

func tick_smooth_scales(_delta: float) -> bool:
	## Tween visual scale toward occupancy target (BH-36). Xform-only each step — no tex paint.
	if map == null:
		return false
	var moving := false
	for sid in map.systems.keys():
		var sid_s := str(sid)
		var target := float(map.systems[sid].get("scale", 1.0))
		var cur := float(visual_scales.get(sid_s, target))
		var tw_tgt := float(_scale_tween_targets.get(sid_s, cur))
		if absf(target - tw_tgt) > 0.001:
			_scale_tween_targets[sid_s] = target
			_start_scale_tween(sid_s, cur, target)
		if absf(float(visual_scales.get(sid_s, target)) - target) > 0.0008:
			moving = true
	if moving:
		_sync_ring_xforms_only()
		tick_icon_edge_follow()
	return moving

func _start_scale_tween(sid: String, from_v: float, to_v: float) -> void:
	if _scale_tweens.has(sid):
		var old: Tween = _scale_tweens[sid]
		if old != null and is_instance_valid(old):
			old.kill()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: _apply_visual_scale(v, sid), from_v, to_v, SCALE_TWEEN_DUR)
	_scale_tweens[sid] = tw

func _apply_visual_scale(v: float, sid: String) -> void:
	visual_scales[sid] = v
	if map and map.systems.has(sid):
		map.systems[sid]["visual_scale"] = v
	if _ring_root:
		var node := _ring_root.get_node_or_null(sid) as Node3D
		if node:
			node.scale = Vector3(v, 1.0, v)

func tick_icon_edge_follow() -> void:
	## Edge containers (icon+pilot name) glued to ring; basis X = screen-right so name at local −X stays left.
	if map == null or icon_root == null:
		return
	var s_right := Vector3(1.0, 0.0, 0.0)
	if link_cam != null and is_instance_valid(link_cam):
		var rx := link_cam.global_transform.basis.x
		s_right = Vector3(rx.x, 0.0, rx.z)
		if s_right.length_squared() < 0.0001:
			s_right = Vector3(1.0, 0.0, 0.0)
		else:
			s_right = s_right.normalized()
	var s_fwd := s_right.cross(Vector3.UP)
	if s_fwd.length_squared() < 0.0001:
		s_fwd = Vector3(0.0, 0.0, -1.0)
	else:
		s_fwd = s_fwd.normalized()
	for node in icon_root.get_children():
		if not node.has_meta("edge_sid"):
			continue
		var sid: String = str(node.get_meta("edge_sid"))
		if not map.systems.has(sid):
			continue
		var a: float = float(node.get_meta("edge_ang", 0.0))
		if node.has_meta("edge_cell"):
			var ci: int = int(node.get_meta("edge_cell"))
			var cells: Array = map.systems[sid]["cells"]
			if ci >= 0 and ci < cells.size():
				a = float(cells[ci].get("angle_center", a))
				node.set_meta("edge_ang", a)
		var pad: float = float(node.get_meta("edge_pad", 3.2))
		var y: float = float(node.get_meta("edge_y", 0.55))
		var sc = visual_scale_of(sid)
		var outer: float = float(map.layout.get("ring_outer", 26)) * sc
		var center: Vector3 = map.systems[sid]["center"]
		var radial := Vector3(sin(a), 0.0, -cos(a))
		var n3 := node as Node3D
		n3.position = center + radial * (outer + pad) + Vector3(0.0, y, 0.0)
		var b := Basis()
		b.x = s_right
		b.y = Vector3.UP
		b.z = s_fwd
		n3.basis = b

func visual_scale_of(sid: String) -> float:
	return float(visual_scales.get(sid, map.systems[sid].get("scale", 1.0) if map and map.systems.has(sid) else 1.0))

func gate_outer_point(sys_id: String, to_id: String) -> Vector3:
	var sys: Dictionary = map.systems[sys_id]
	var center: Vector3 = sys["center"]
	var sys_scale: float = visual_scale_of(sys_id)
	var outer: float = float(map.layout.get("ring_outer", 26)) * sys_scale
	var ang = 0.0
	var found = false
	for c in sys["cells"]:
		if int(c["kind"]) == BoardTypes.CellKind.GATE and str(c["gate_to"]) == to_id:
			ang = float(c["angle_center"])
			found = true
			break
	if not found and map.systems.has(to_id):
		var other: Vector3 = map.systems[to_id]["center"]
		var dir = other - center
		ang = atan2(dir.x, -dir.z)
	return center + Vector3(sin(ang) * (outer + 0.4), 0.05, -cos(ang) * (outer + 0.4))

func rebuild() -> void:
	if map == null:
		return
	_ensure_gpu_board()
	_clear_cell_pick()
	rebuild_mesh_only()
	## Defer icons/labels so board mesh shows first (faster scene entry).
	call_deferred("_deferred_rebuild_decor")

func _deferred_rebuild_decor() -> void:
	## Icons (containers) first — pilot names attach into the same edge holder.
	_rebuild_sector_icons()
	rebuild_labels(pilots_ref)
	_rebuild_system_markers()
	_rebuild_territory()

func sync_ring_visuals(delta: float, arcs_moving: bool, scale_moving: bool, force_paint: bool) -> bool:
	## 200ms arc 补帧: paint every frame while keys tween; idle = no paint storm.
	## Returns true when sector textures were rewritten (caller may clear capture_dirty).
	if map == null:
		return false
	_ensure_gpu_board()
	if not _gpu_draw_enabled:
		if force_paint or arcs_moving or scale_moving:
			_cpu_rebuild_mesh()
			return force_paint or arcs_moving
		return false
	_ensure_rings()
	if arcs_moving or scale_moving or force_paint:
		_sync_ring_xforms_only()
	## Arc 补帧 = every frame for ≤200ms. Capture/work = throttled (was every-frame storm).
	var do_paint := false
	if arcs_moving:
		do_paint = true
		_ring_paint_acc = 0.0
	elif force_paint:
		_ring_paint_acc += delta
		if _ring_paint_acc >= RING_PAINT_DT:
			_ring_paint_acc = 0.0
			do_paint = true
	if do_paint:
		_paint_all_sector_tex()
		sync_links()
		# #region agent log
		if Engine.get_process_frames() % 12 == 0:
			_dbg59_board("PERF", "starmap.sync_ring_visuals", "paint", {
				"arcs": arcs_moving, "scale": scale_moving, "force": force_paint,
				"runId": "post-fix"
			})
		# #endregion
	elif scale_moving:
		sync_links()
	_apply_battle_gpu_vis()
	return do_paint

func _sync_ring_xforms_only() -> void:
	if _ring_root == null or map == null:
		return
	for sid in map.systems.keys():
		var node := _ring_root.get_node_or_null(str(sid)) as Node3D
		if node == null:
			continue
		var center: Vector3 = map.systems[sid]["center"]
		var sc := visual_scale_of(str(sid))
		node.position = Vector3(center.x, 0.0, center.z)
		node.scale = Vector3(sc, 1.0, sc)

func _paint_all_sector_tex() -> void:
	if map == null or _ring_root == null:
		return
	var max_span_deg := 0.0
	var px := Color.BLACK
	for sid in map.systems.keys():
		var node := _ring_root.get_node_or_null(str(sid)) as Node3D
		if node == null:
			continue
		var sys: Dictionary = map.systems[sid]
		var cells: Array = sys["cells"]
		var n: int = mini(cells.size(), 12)
		var keys := PackedFloat32Array()
		keys.resize(12)
		var fills := PackedColorArray()
		fills.resize(12)
		var edges := PackedColorArray()
		edges.resize(12)
		var works := PackedFloat32Array()
		works.resize(12)
		var stored: Array = sys.get("key_ang", [])
		for i in 12:
			var ang := 0.0
			if i < n:
				if stored.size() == cells.size():
					ang = float(stored[i])
				else:
					ang = float(cells[i]["angle_center"]) - float(cells[i]["angle_half"])
				var c: Dictionary = cells[i]
				var kind := int(c["kind"])
				var base := _kind_color(kind)
				var edge := Color(1, 1, 1, 1)
				var capturing := int(c.get("capturing", 0))
				var owner_fac := int(c["owner"])
				if kind != BoardTypes.CellKind.EMPTY:
					if capturing != 0:
						edge = _owner_color(capturing)
					elif owner_fac != 0:
						edge = _owner_color(owner_fac)
				fills[i] = Color(base.r, base.g, base.b, 0.70)
				edges[i] = edge
				works[i] = clampf(float(c.get("work", 0.0)) / _work_full(c), 0.0, 1.0)
				var span := float(c.get("angle_half", 0.0)) * 2.0
				max_span_deg = maxf(max_span_deg, rad_to_deg(span))
			else:
				fills[i] = Color(0, 0, 0, 0)
				edges[i] = Color(1, 1, 1, 1)
				works[i] = 1.0
			keys[i] = ang
		node.set_meta("pick_keys", keys)
		node.set_meta("pick_n", n)
		var img: Image = node.get_meta("sector_img")
		_paint_sector_tex(img, keys, n, fills, edges, works)
		var tex: ImageTexture = node.get_meta("sector_tex")
		tex.set_image(img)
		if str(sid) == "soular":
			px = img.get_pixel(0, 0)
		for child in node.get_children():
			var mi := child as MeshInstance3D
			if mi == null:
				continue
			var mat := mi.material_override as StandardMaterial3D
			if mat == null:
				continue
			mat.albedo_texture = tex
	# #region agent log
	if Engine.get_process_frames() % 30 == 0:
		_dbg59_board("COL", "starmap._paint_all_sector_tex", "sector_tex", {
			"px0": [px.r, px.g, px.b, px.a],
			"max_span_deg": max_span_deg,
			"paint_dt": RING_PAINT_DT,
			"mat": "std",
			"runId": "post-fix"
		})
	# #endregion

func _sync_rings() -> void:
	## Full sync (setup / forced rebuild).
	_ensure_rings()
	_sync_ring_xforms_only()
	_paint_all_sector_tex()

func _paint_sector_tex(img: Image, keys: PackedFloat32Array, n: int, fills: PackedColorArray, edges: PackedColorArray, works: PackedFloat32Array) -> void:
	var w := img.get_width()
	## Fixed pixel seam width — uniform when board is still (no span-fraction jump).
	const SEAM_PX := 3
	for x in w:
		var ang := (float(x) + 0.5) / float(w) * TAU
		var ci := _cell_at_angle(ang, keys, n)
		var a0 := float(keys[ci])
		var span := fposmod(float(keys[(ci + 1) % n]) - a0, TAU)
		var rel := fposmod(ang - a0, TAU)
		var fill: Color = fills[ci]
		var edge: Color = edges[ci]
		var arc_t := rel / maxf(span, 0.001)
		var wn := float(works[ci])
		var spread := 1.0 - wn
		var from_mid := absf(arc_t - 0.5) * 2.0
		if wn < 0.999 and from_mid > spread:
			edge = Color(1, 1, 1, 1)
		edge.a = 1.0
		img.set_pixel(x, 0, fill)
		img.set_pixel(x, 1, edge)
	## Punch equal-width transparent seams at each key (texture-space).
	for i in n:
		var kx := int(floor(fposmod(float(keys[i]), TAU) / TAU * float(w)))
		for dx in range(-SEAM_PX + 1, SEAM_PX):
			var xx := posmod(kx + dx, w)
			img.set_pixel(xx, 0, Color(0, 0, 0, 0))
			img.set_pixel(xx, 1, Color(0, 0, 0, 0))

func _cell_at_angle(ang: float, keys: PackedFloat32Array, n: int) -> int:
	for i in n:
		var a0 := float(keys[i])
		var span := fposmod(float(keys[(i + 1) % n]) - a0, TAU)
		var rel := fposmod(ang - a0, TAU)
		if rel <= span + 0.0001:
			return i
	return 0

func rings_pick_active() -> bool:
	return _ring_root != null and is_instance_valid(_ring_root) and _ring_root.visible

func pick_painted_cell(origin: Vector3, dir: Vector3) -> Dictionary:
	## Closest triangle of the drawn Fill/Rim. UV of that hit reads this frame's sector image.
	if not rings_pick_active() or map == null:
		return {}
	if dir.length_squared() < 1e-8:
		return {}
	var ndir := dir.normalized()
	_ensure_pick_meshes()
	var best_t := INF
	var best_ring: Node3D = null
	var best_uv := Vector2.ZERO
	for ch in _ring_root.get_children():
		var ring := ch as Node3D
		if ring == null or not ring.visible:
			continue
		var fill := ring.get_node_or_null("Fill") as MeshInstance3D
		var rim := ring.get_node_or_null("Rim") as MeshInstance3D
		var hit := _closer_mesh_hit(fill, _fill_pick, rim, _rim_pick, origin, ndir)
		if hit.is_empty() or float(hit["t"]) >= best_t:
			continue
		best_t = float(hit["t"])
		best_ring = ring
		best_uv = hit["uv"]
	if best_ring == null:
		return {}
	return _cell_for_painted_angle(best_ring, fposmod(best_uv.x, 1.0) * TAU)

func _closer_mesh_hit(a: MeshInstance3D, a_pick: Dictionary, b: MeshInstance3D, b_pick: Dictionary, origin: Vector3, dir: Vector3) -> Dictionary:
	var ha := _ray_mesh_uv(a, a_pick, origin, dir)
	var hb := _ray_mesh_uv(b, b_pick, origin, dir)
	if ha.is_empty():
		return hb
	if hb.is_empty() or float(ha["t"]) <= float(hb["t"]):
		return ha
	return hb

func _ray_mesh_uv(mi: MeshInstance3D, pick: Dictionary, origin: Vector3, dir: Vector3) -> Dictionary:
	## TriangleMesh is local to the baked mesh. The instance transform (scale included) is applied here.
	if mi == null or not mi.visible or pick.is_empty():
		return {}
	## Flat annulus AABB has no thickness. TriangleMesh.intersect_ray drops shallow battlefield rays.
	## Hit the drawn plane, then the triangle in XZ. Transform is the live ring scale.
	var inv := mi.global_transform.affine_inverse()
	var lfrom: Vector3 = inv * origin
	var ldir: Vector3 = inv.basis * dir
	if ldir.length_squared() < 1e-12 or absf(ldir.y) < 1e-8:
		return {}
	var faces: PackedVector3Array = pick["faces"]
	var uvs: PackedVector2Array = pick["uv"]
	if faces.size() < 3 or uvs.size() < 3:
		return {}
	var plane_y := faces[0].y
	var t_local := (plane_y - lfrom.y) / ldir.y
	if t_local < 0.0:
		return {}
	var hit: Vector3 = lfrom + ldir * t_local
	var nfaces := int(float(faces.size()) / 3.0)
	var base := -1
	var bc := Vector3.ZERO
	for fi in nfaces:
		var b0 := fi * 3
		var bary := _bary_xz(hit, faces[b0], faces[b0 + 1], faces[b0 + 2])
		if bary.x >= -0.002 and bary.y >= -0.002 and bary.z >= -0.002:
			base = b0
			bc = bary
			break
	if base < 0:
		return {}
	var uv := uvs[base] * bc.x + uvs[base + 1] * bc.y + uvs[base + 2] * bc.z
	var world: Vector3 = mi.global_transform * hit
	var t := (world - origin).dot(dir)
	if t < 0.0:
		return {}
	return {"t": t, "uv": uv}


func _bary_xz(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0x := b.x - a.x
	var v0z := b.z - a.z
	var v1x := c.x - a.x
	var v1z := c.z - a.z
	var v2x := p.x - a.x
	var v2z := p.z - a.z
	var den := v0x * v1z - v1x * v0z
	if absf(den) < 1e-8:
		return Vector3(-1.0, -1.0, -1.0)
	var inv_d := 1.0 / den
	var bu := (v2x * v1z - v1x * v2z) * inv_d
	var bv := (v0x * v2z - v2x * v0z) * inv_d
	return Vector3(1.0 - bu - bv, bu, bv)

func _ensure_pick_meshes() -> void:
	if not _fill_pick.is_empty() and not _rim_pick.is_empty():
		return
	if _ring_root == null or _ring_root.get_child_count() == 0:
		return
	var sample := _ring_root.get_child(0)
	var fill := sample.get_node_or_null("Fill") as MeshInstance3D
	var rim := sample.get_node_or_null("Rim") as MeshInstance3D
	if fill != null and fill.mesh is ArrayMesh:
		_fill_pick = _cache_triangle_pick(fill.mesh as ArrayMesh)
	if rim != null and rim.mesh is ArrayMesh:
		_rim_pick = _cache_triangle_pick(rim.mesh as ArrayMesh)

func _cache_triangle_pick(mesh: ArrayMesh) -> Dictionary:
	var md := MeshDataTool.new()
	if md.create_from_surface(mesh, 0) != OK:
		return {}
	var faces := PackedVector3Array()
	var uvs := PackedVector2Array()
	var n := md.get_face_count()
	for i in n:
		for k in 3:
			var vi := md.get_face_vertex(i, k)
			faces.append(md.get_vertex(vi))
			uvs.append(md.get_vertex_uv(vi))
	var tm := TriangleMesh.new()
	if not tm.create_from_faces(faces):
		return {}
	return {"tm": tm, "uv": uvs, "faces": faces}

func _cell_for_painted_angle(ring: Node3D, ang: float) -> Dictionary:
	var sid := str(ring.name)
	if not map.systems.has(sid):
		return {}
	var sys: Dictionary = map.systems[sid]
	var cells: Array = sys.get("cells", [])
	var n := int(ring.get_meta("pick_n", 0))
	var keys: PackedFloat32Array = ring.get_meta("pick_keys", PackedFloat32Array())
	if n <= 0 or keys.size() < n:
		n = mini(cells.size(), 12)
		keys = PackedFloat32Array()
		keys.resize(n)
		var stored: Array = sys.get("key_ang", [])
		for i in n:
			if stored.size() == cells.size():
				keys[i] = float(stored[i])
			else:
				keys[i] = float(cells[i]["angle_center"]) - float(cells[i]["angle_half"])
	if n <= 0:
		return {}
	var w := 256
	var img: Image = ring.get_meta("sector_img") if ring.has_meta("sector_img") else null
	if img != null:
		w = img.get_width()
	var px := int(floor(fposmod(ang, TAU) / TAU * float(w))) % w
	## Transparent seam pixels are not a cell — do not award the neighbor.
	if img != null and img.get_pixel(px, 0).a < 0.05 and img.get_pixel(px, 1).a < 0.05:
		return {}
	var ang_c := (float(px) + 0.5) / float(w) * TAU
	var ci := _cell_at_angle(ang_c, keys, n)
	if ci < 0 or ci >= cells.size():
		return {}
	return {"sys": sid, "cell": int(cells[ci].get("index", ci))}

func _ensure_rings() -> void:
	if _ring_ready and _ring_root != null:
		## Rebuild once if leftover ShaderMaterial rings from prior attempt.
		var sample := _ring_root.get_child(0) if _ring_root.get_child_count() > 0 else null
		var ok_std := false
		if sample:
			var fill := sample.get_node_or_null("Fill") as MeshInstance3D
			var rim := sample.get_node_or_null("Rim") as MeshInstance3D
			## Rim thin + annulus segs match current bake.
			ok_std = (
				fill != null and fill.material_override is StandardMaterial3D
				and rim != null and rim.has_meta("thin_rim")
				and is_equal_approx(float(rim.get_meta("rim_thick", -1.0)), RIM_THICK)
				and int(fill.get_meta("annulus_segs", 0)) == 256
			)
		if ok_std:
			return
		## Immediate free — queue_free leaves names occupied same frame.
		while _ring_root.get_child_count() > 0:
			var dead := _ring_root.get_child(0)
			_ring_root.remove_child(dead)
			dead.free()
		_fill_pick = {}
		_rim_pick = {}
		_ring_ready = false
	if _ring_root == null:
		_ring_root = Node3D.new()
		_ring_root.name = "GpuRings"
		add_child(_ring_root)
	## 256 segs ≈ 1 texel/seg → radial seams stay straight (linear UV no longer bows).
	var annulus := _build_annulus(256)
	var rim_band := _build_rim_band(256)
	for sid in map.systems.keys():
		if _ring_root.get_node_or_null(str(sid)) != null:
			continue
		var root := Node3D.new()
		root.name = str(sid)
		var img := Image.create(256, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 0.45, 0.9, 0.7))
		var tex := ImageTexture.create_from_image(img)
		root.set_meta("sector_img", img)
		root.set_meta("sector_tex", tex)
		## StandardMaterial + albedo_texture — ShaderMaterial path rendered solid grey (screenshot).
		var fill_mi := MeshInstance3D.new()
		fill_mi.name = "Fill"
		fill_mi.mesh = annulus
		fill_mi.set_meta("annulus_segs", 256)
		fill_mi.material_override = _make_ring_std_mat(tex, 0.25, true)
		fill_mi.extra_cull_margin = 64.0
		root.add_child(fill_mi)
		var rim_mi := MeshInstance3D.new()
		rim_mi.name = "Rim"
		rim_mi.mesh = rim_band
		rim_mi.set_meta("thin_rim", true)
		rim_mi.set_meta("rim_thick", RIM_THICK)
		rim_mi.material_override = _make_ring_std_mat(tex, 0.75, false)
		rim_mi.extra_cull_margin = 64.0
		root.add_child(rim_mi)
		_ring_root.add_child(root)
	_ring_ready = true
	# #region agent log
	_dbg59_board("VIS", "starmap._ensure_rings", "rings", {
		"std_mat": true, "thin_rim": true, "rim_thick": RIM_THICK,
		"annulus_segs": 256, "systems": map.systems.size(), "runId": "post-fix"
	})
	# #endregion

func _make_ring_std_mat(tex: Texture2D, row_v: float, fade_inner: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.vertex_color_use_as_albedo = fade_inner
	## Sample a thin horizontal strip of the 256×2 atlas (fill or rim row).
	mat.uv1_scale = Vector3(1.0, 0.001, 1.0)
	mat.uv1_offset = Vector3(0.0, row_v, 0.0)
	return mat

func _build_annulus(segs: int) -> ArrayMesh:
	## Baked r=12..26. Vertex alpha fades to 0 at inner (系心透明).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_in := 12.0
	var r_out := 26.0
	var c_out := Color(1, 1, 1, 0.85)
	var c_in := Color(1, 1, 1, 0.0)
	for i in segs:
		var u0 := float(i) / float(segs)
		var u1 := float(i + 1) / float(segs)
		var a0 := u0 * TAU
		var a1 := u1 * TAU
		var p00 = Vector3(sin(a0) * r_out, 0.02, -cos(a0) * r_out)
		var p10 = Vector3(sin(a1) * r_out, 0.02, -cos(a1) * r_out)
		var p01 = Vector3(sin(a0) * r_in, 0.02, -cos(a0) * r_in)
		var p11 = Vector3(sin(a1) * r_in, 0.02, -cos(a1) * r_in)
		_st_uv_col_tri(st, p00, Vector2(u0, 1.0), c_out, p10, Vector2(u1, 1.0), c_out, p11, Vector2(u1, 0.0), c_in)
		_st_uv_col_tri(st, p00, Vector2(u0, 1.0), c_out, p11, Vector2(u1, 0.0), c_in, p01, Vector2(u0, 0.0), c_in)
	st.generate_normals()
	return st.commit()

func _build_rim_band(segs: int) -> ArrayMesh:
	## Outer rim only: r_out .. r_out+RIM_THICK (same width as CPU path).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r0 := 26.0
	var r1 := 26.0 + RIM_THICK
	var col := Color(1, 1, 1, 1)
	for i in segs:
		var u0 := float(i) / float(segs)
		var u1 := float(i + 1) / float(segs)
		var a0 := u0 * TAU
		var a1 := u1 * TAU
		var p00 = Vector3(sin(a0) * r1, 0.03, -cos(a0) * r1)
		var p10 = Vector3(sin(a1) * r1, 0.03, -cos(a1) * r1)
		var p01 = Vector3(sin(a0) * r0, 0.03, -cos(a0) * r0)
		var p11 = Vector3(sin(a1) * r0, 0.03, -cos(a1) * r0)
		_st_uv_col_tri(st, p00, Vector2(u0, 1.0), col, p10, Vector2(u1, 1.0), col, p11, Vector2(u1, 0.0), col)
		_st_uv_col_tri(st, p00, Vector2(u0, 1.0), col, p11, Vector2(u1, 0.0), col, p01, Vector2(u0, 0.0), col)
	st.generate_normals()
	return st.commit()

func _st_uv_col_tri(st: SurfaceTool, a: Vector3, uva: Vector2, ca: Color, b: Vector3, uvb: Vector2, cb: Color, c: Vector3, uvc: Vector2, cc: Color) -> void:
	st.set_uv(uva)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_uv(uvb)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_uv(uvc)
	st.set_color(cc)
	st.add_vertex(c)

func rebuild_mesh_only() -> void:
	_ensure_gpu_board()
	if _gpu_draw_enabled:
		_sync_rings()
		sync_links()
		_apply_battle_gpu_vis()
		return
	_set_gpu_meshes_visible(false)
	_cpu_rebuild_mesh()
	if view_tier == "starmap" and mesh_inst:
		mesh_inst.visible = false
	elif _curtain_mmi:
		_curtain_mmi.visible = true

func sync_instance_data() -> void:
	if map == null:
		return
	_ensure_gpu_board()
	if not _gpu_ok:
		return
	_ensure_cell_capacity()
	if _cell_img == null or _cell_capacity <= 0:
		# #region agent log
		_dbg59_board("H4", "starmap.sync_instance_data", "empty_capacity", {
			"capacity": _cell_capacity, "img": _cell_img != null, "runId": "pre-fix"
		})
		# #endregion
		return
	var n := _index_map.size()
	var shown := 0
	var sample: Dictionary = {}
	## Cache 12 separator key angles per system (transparent seams).
	var keys_by_sid: Dictionary = {}
	for sid0 in map.systems.keys():
		keys_by_sid[sid0] = _separator_keys(map.systems[sid0]["cells"])
	for i in n:
		var entry: Dictionary = _index_map[i]
		var sid: String = str(entry["sid"])
		var ci: int = int(entry["cell"])
		if not map.systems.has(sid):
			_hide_instance(i)
			continue
		var sys: Dictionary = map.systems[sid]
		var cells: Array = sys["cells"]
		if ci < 0 or ci >= cells.size():
			_hide_instance(i)
			continue
		var keys: PackedFloat32Array = keys_by_sid[sid]
		var kn := keys.size()
		if kn < 2:
			_hide_instance(i)
			continue
		## Cell i = key[i] → key[i+1] (GPU fills the wedge).
		var k0: float = keys[ci % kn]
		var k1: float = keys[(ci + 1) % kn]
		var span: float = fposmod(k1 - k0, TAU)
		if span < 0.001:
			span = TAU / float(kn)
		var a0: float = k0
		var a1: float = k0 + span
		var c: Dictionary = cells[ci]
		var center: Vector3 = sys["center"]
		var sys_scale: float = visual_scale_of(sid)
		var inner: float = float(map.layout.get("ring_inner", 12)) * sys_scale
		var outer: float = float(map.layout.get("ring_outer", 26)) * sys_scale
		var kind: int = int(c["kind"])
		var base = _kind_color(kind)
		var owner_fac = int(c["owner"])
		var capturing = int(c.get("capturing", 0))
		var edge = Color(1, 1, 1, 1)
		if kind != BoardTypes.CellKind.EMPTY:
			if capturing != 0:
				edge = _owner_color(capturing)
			elif owner_fac != 0:
				edge = _owner_color(owner_fac)
		if c.get("bubble", false):
			var t: float = float(c.get("bubble_t", 0.0))
			var breath = 0.35 + 0.65 * (0.5 + 0.5 * sin(t / BoardTypes.BUBBLE_BREATH_S * TAU))
			base = base.lightened(0.25 + breath * 0.35)
			base = Color(base.r, minf(1.0, base.g + 0.25), minf(1.0, base.b + 0.45), base.a)
			edge = Color(0.35, 0.85, 1.0, 1.0)
		var half = maxf(span * 0.5, 0.001)
		var gap = minf(0.55 / maxf(outer, 1.0), half * 0.18)
		if span - 2.0 * gap < 0.012:
			gap = maxf(0.0, span * 0.04)
		var work_logic = float(c.get("work", 0.0))
		var work_full := _work_full(c)
		c["work_vis"] = work_logic
		var ga0 = a0 + gap
		var ga1 = a1 - gap
		## Capture rim must stay visible on narrow wedges (CAPTURE §4.1).
		var must_draw = capturing != 0 or absf(work_logic - work_full) > 0.5
		var show_cell := 1.0
		if ga1 <= ga0 + 0.002:
			if must_draw:
				ga0 = a0
				ga1 = a1
			else:
				show_cell = 0.0
		var work_n = clampf(work_logic / work_full, 0.0, 1.0)
		var fill = Color(base.r, base.g, base.b, 0.70)
		_write_cell_texel(i, center.x, center.z, ga0, ga1, inner, outer, work_n, show_cell, fill, edge)
		var custom := Color(
			fposmod(ga0, TAU) / TAU,
			clampf((ga1 - ga0) / TAU, 0.0, 1.0),
			clampf(inner / CUSTOM_R_SCALE, 0.0, 1.0),
			clampf(outer / CUSTOM_R_SCALE, 0.0, 1.0)
		)
		var xform := Transform3D(Basis.IDENTITY, Vector3(center.x, 0.0, center.z))
		if show_cell < 0.5:
			_hide_instance(i)
			continue
		shown += 1
		_fill_mm.set_instance_transform(i, xform)
		_rim_mm.set_instance_transform(i, xform)
		_fill_mm.set_instance_custom_data(i, custom)
		_rim_mm.set_instance_custom_data(i, custom)
		if sample.is_empty():
			sample = {
				"sid": sid, "cell": ci, "keys": kn,
				"k0": k0, "k1": k1, "ga0": ga0, "ga1": ga1,
				"inner": inner, "outer": outer, "show": show_cell,
				"custom": [custom.r, custom.g, custom.b, custom.a]
			}
	_cell_tex.set_image(_cell_img)
	_fill_mat.set_shader_parameter("cell_data", _cell_tex)
	_fill_mat.set_shader_parameter("data_width", float(_cell_capacity))
	_fill_mat.set_shader_parameter("r_scale", CUSTOM_R_SCALE)
	_rim_mat.set_shader_parameter("cell_data", _cell_tex)
	_rim_mat.set_shader_parameter("data_width", float(_cell_capacity))
	_rim_mat.set_shader_parameter("r_scale", CUSTOM_R_SCALE)
	# #region agent log
	if Engine.get_process_frames() % 30 == 0:
		_dbg59_board("KP", "starmap.sync_instance_data", "keypoint_gpu", {
			"n": n, "shown": shown, "key_count": KEY_COUNT,
			"fill_vis": _fill_mmi.visible if _fill_mmi else false,
			"cpu_mesh_vis": mesh_inst.visible if mesh_inst else false,
			"sample": sample,
			"runId": "post-fix"
		})
	# #endregion

func _separator_keys(cells: Array) -> PackedFloat32Array:
	## Key i = start of cell i = transparent seam before that cell.
	var keys := PackedFloat32Array()
	var n := cells.size()
	keys.resize(n)
	for i in n:
		keys[i] = float(cells[i]["angle_center"]) - float(cells[i]["angle_half"])
	return keys

func _hide_instance(i: int) -> void:
	var z := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -9999, 0))
	_fill_mm.set_instance_transform(i, z)
	_rim_mm.set_instance_transform(i, z)
	_fill_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	_rim_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))

func _write_cell_texel(
	i: int,
	cx: float, cz: float, a0: float, a1: float,
	inner: float, outer: float, work_n: float, show_cell: float,
	fill: Color, edge: Color
) -> void:
	## Row0 = geometry floats (a0,a1,inner,outer); center stays on instance xform.
	_cell_img.set_pixel(i, 0, Color(a0, a1, inner, outer))
	_cell_img.set_pixel(i, 1, Color(cx, cz, work_n, show_cell))
	_cell_img.set_pixel(i, 2, fill)
	_cell_img.set_pixel(i, 3, Color(edge.r, edge.g, edge.b, 1.0))

func _ensure_cell_capacity() -> void:
	_index_map.clear()
	if map == null:
		return
	for sid in map.systems.keys():
		var cells: Array = map.systems[sid]["cells"]
		for c in cells:
			_index_map.append({"sid": sid, "cell": int(c["index"])})
	var n := _index_map.size()
	if n <= 0:
		_cell_capacity = 0
		_fill_mm.instance_count = 0
		_rim_mm.instance_count = 0
		return
	if n == _cell_capacity and _cell_img != null:
		return
	_cell_capacity = n
	_cell_img = Image.create(_cell_capacity, 4, false, Image.FORMAT_RGBAF)
	_cell_tex = ImageTexture.create_from_image(_cell_img)
	## Must set use_custom_data before instance_count (Godot resets buffer).
	_fill_mm.use_custom_data = true
	_rim_mm.use_custom_data = true
	_fill_mm.instance_count = _cell_capacity
	_rim_mm.instance_count = _cell_capacity
	var ident := Transform3D.IDENTITY
	for i in _cell_capacity:
		_fill_mm.set_instance_transform(i, ident)
		_rim_mm.set_instance_transform(i, ident)
		_fill_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
		_rim_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	# #region agent log
	_dbg59_board("H4", "starmap._ensure_cell_capacity", "realloc", {
		"n": n, "systems": map.systems.size(), "runId": "pre-fix"
	})
	# #endregion

func _cpu_rebuild_mesh() -> void:
	## Emergency fallback when GPU shaders fail to load (H2).
	_ensure_mesh_inst()
	if mesh_inst == null or map == null:
		return
	mesh_inst.visible = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		var center: Vector3 = sys["center"]
		var sys_scale: float = visual_scale_of(sid)
		var inner: float = float(map.layout.get("ring_inner", 12)) * sys_scale
		var outer: float = float(map.layout.get("ring_outer", 26)) * sys_scale
		for c in sys["cells"]:
			var a0: float = float(c["angle_center"]) - float(c["angle_half"])
			var a1: float = float(c["angle_center"]) + float(c["angle_half"])
			var base = _kind_color(int(c["kind"]))
			var owner_fac = int(c["owner"])
			var capturing = int(c.get("capturing", 0))
			var edge = Color(1, 1, 1, 1)
			if int(c["kind"]) != BoardTypes.CellKind.EMPTY:
				if capturing != 0:
					edge = _owner_color(capturing)
				elif owner_fac != 0:
					edge = _owner_color(owner_fac)
			var half = maxf(float(c["angle_half"]), 0.001)
			var gap = minf(0.55 / maxf(outer, 1.0), half * 0.18)
			var span = a1 - a0
			if span - 2.0 * gap < 0.012:
				gap = maxf(0.0, span * 0.04)
			var ga0 = a0 + gap
			var ga1 = a1 - gap
			var work_logic = float(c.get("work", 0.0))
			var work_full := _work_full(c)
			var must_draw_cpu = capturing != 0 or absf(work_logic - work_full) > 0.5
			if ga1 <= ga0 + 0.002:
				if must_draw_cpu:
					ga0 = a0
					ga1 = a1
				else:
					continue
			var steps = maxi(4, int((ga1 - ga0) / 0.08))
			var c_out = Color(base.r, base.g, base.b, 0.70)
			var c_in = Color(base.r * 0.55, base.g * 0.55, base.b * 0.55, 0.28)
			for si in steps:
				var t0 = float(si) / float(steps)
				var t1 = float(si + 1) / float(steps)
				var b0 = lerpf(ga0, ga1, t0)
				var b1 = lerpf(ga0, ga1, t1)
				var p00 = center + Vector3(sin(b0) * outer, 0.02, -cos(b0) * outer)
				var p10 = center + Vector3(sin(b1) * outer, 0.02, -cos(b1) * outer)
				var p01 = center + Vector3(sin(b0) * inner, 0.02, -cos(b0) * inner)
				var p11 = center + Vector3(sin(b1) * inner, 0.02, -cos(b1) * inner)
				st.set_color(c_out)
				st.add_vertex(p00)
				st.set_color(c_out)
				st.add_vertex(p10)
				st.set_color(c_in)
				st.add_vertex(p11)
				st.set_color(c_out)
				st.add_vertex(p00)
				st.set_color(c_in)
				st.add_vertex(p11)
				st.set_color(c_in)
				st.add_vertex(p01)
				var mid_t = (t0 + t1) * 0.5
				var spread = (work_full - work_logic) / work_full
				var from_mid = absf(mid_t - 0.5) * 2.0
				var rimc = edge if (work_logic >= work_full - 0.01 or from_mid <= spread) else Color(1, 1, 1, 1)
				var r1 = outer + RIM_THICK
				var q00 = center + Vector3(sin(b0) * r1, 0.03, -cos(b0) * r1)
				var q10 = center + Vector3(sin(b1) * r1, 0.03, -cos(b1) * r1)
				var q01 = center + Vector3(sin(b0) * outer, 0.03, -cos(b0) * outer)
				var q11 = center + Vector3(sin(b1) * outer, 0.03, -cos(b1) * outer)
				st.set_color(rimc)
				st.add_vertex(q00)
				st.add_vertex(q10)
				st.add_vertex(q11)
				st.add_vertex(q00)
				st.add_vertex(q11)
				st.add_vertex(q01)
	## Star-gate links (H7) — CPU path must draw these; GPU links are gated off.
	var link_n := 0
	for sid in map.systems.keys():
		for link in map.systems[sid]["links"]:
			_cpu_draw_link(st, sid, str(link))
			link_n += 1
	mesh_inst.mesh = st.commit()
	# #region agent log
	_dbg59_board("H7", "starmap._cpu_rebuild_mesh", "cpu_cells_links", {
		"links": link_n, "gpu_draw": _gpu_draw_enabled, "runId": "pre-fix"
	})
	# #endregion

func _cpu_draw_link(st: SurfaceTool, from_id: String, to_id: String) -> void:
	var a: Vector3 = gate_outer_point(from_id, to_id)
	var b: Vector3 = gate_outer_point(to_id, from_id)
	var gate_i = -1
	var owner_fac = 0
	for c in map.systems[from_id]["cells"]:
		if int(c["kind"]) == BoardTypes.CellKind.GATE and str(c["gate_to"]) == to_id:
			gate_i = int(c["index"])
			owner_fac = int(c["owner"])
			break
	var col = _owner_color(owner_fac) if owner_fac != 0 else Color(1, 1, 1, 1)
	var can = gate_i >= 0 and map.can_pass_gate(from_id, gate_i, viewer, diplomacy)
	var transit = transit_gates.has("%s:%d" % [from_id, gate_i])
	var owned = owner_fac != 0
	var use_solid = owned or can or transit
	if use_solid:
		col = Color(col.r, col.g, col.b, 0.95 if (can or transit) else 0.75)
	else:
		col = Color(col.r, col.g, col.b, 0.28)
	var tip: Vector3 = a.lerp(b, 0.72)
	tip.y = 0.05
	a.y = 0.05
	if use_solid:
		_cpu_solid_line(st, a, tip, col)
	else:
		_cpu_dashed_line(st, a, tip, col)
	var dir = (tip - a).normalized()
	var side = Vector3(-dir.z, 0, dir.x) * 2.0
	_cpu_tri(st, tip, tip - dir * 3.0 + side, tip - dir * 3.0 - side, col)

func _cpu_solid_line(st: SurfaceTool, a: Vector3, b: Vector3, col: Color) -> void:
	var side = (b - a).cross(Vector3.UP).normalized() * 0.28
	if side.length_squared() < 0.0001:
		side = Vector3(0.28, 0, 0)
	_cpu_tri(st, a + side, b + side, b - side, col)
	_cpu_tri(st, a + side, b - side, a - side, col)

func _cpu_dashed_line(st: SurfaceTool, a: Vector3, b: Vector3, col: Color) -> void:
	var n = 12
	for i in n:
		if i % 2 == 1:
			continue
		var p0 = a.lerp(b, float(i) / float(n))
		var p1 = a.lerp(b, float(i + 1) / float(n))
		var side = (b - a).cross(Vector3.UP).normalized() * 0.25
		_cpu_tri(st, p0 + side, p1 + side, p1 - side, col)
		_cpu_tri(st, p0 + side, p1 - side, p0 - side, col)

func _cpu_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)

func sync_links() -> void:
	if map == null:
		return
	_ensure_gpu_board()
	_ensure_link_capacity()
	var i := 0
	for sid in map.systems.keys():
		for link in map.systems[sid]["links"]:
			if i >= _link_capacity:
				break
			_write_link_instance(i, sid, str(link))
			i += 1
	## Hide unused slots.
	var z := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
	while i < _link_capacity:
		_link_mm.set_instance_transform(i, z)
		_tip_mm.set_instance_transform(i, z)
		i += 1

func _ensure_link_capacity() -> void:
	var n := 0
	if map:
		for sid in map.systems.keys():
			n += map.systems[sid]["links"].size()
	if n == _link_capacity and _link_mm != null and _link_mm.instance_count == n:
		return
	_link_capacity = n
	_link_mm.use_colors = true
	_tip_mm.use_colors = true
	_link_mm.instance_count = n
	_tip_mm.instance_count = n

func _write_link_instance(i: int, from_id: String, to_id: String) -> void:
	var a: Vector3 = gate_outer_point(from_id, to_id)
	var b: Vector3 = gate_outer_point(to_id, from_id)
	var gate_i = -1
	var owner_fac = 0
	for c in map.systems[from_id]["cells"]:
		if int(c["kind"]) == BoardTypes.CellKind.GATE and str(c["gate_to"]) == to_id:
			gate_i = int(c["index"])
			owner_fac = int(c["owner"])
			break
	var col = _owner_color(owner_fac) if owner_fac != 0 else Color(1, 1, 1, 1)
	var can = gate_i >= 0 and map.can_pass_gate(from_id, gate_i, viewer, diplomacy)
	var transit = transit_gates.has("%s:%d" % [from_id, gate_i])
	var owned = owner_fac != 0
	var use_solid = owned or can or transit
	var alpha: float
	if use_solid:
		alpha = 0.95 if (can or transit) else 0.75
	else:
		alpha = 0.28
	var tip: Vector3 = a.lerp(b, 0.72)
	tip.y = 0.05
	a.y = 0.05
	## Shaft: map unit X 0..1 from a→tip, Z half-width world ~0.28.
	var dir = tip - a
	var seg_len = dir.length()
	if seg_len < 0.001:
		_link_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
		_tip_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
		return
	dir /= seg_len
	var side = Vector3(-dir.z, 0, dir.x)
	if side.length_squared() < 0.0001:
		side = Vector3(1, 0, 0)
	side = side.normalized()
	var shaft_basis = Basis()
	shaft_basis.x = dir * seg_len
	shaft_basis.y = Vector3.UP
	shaft_basis.z = side * 0.56
	_link_mm.set_instance_transform(i, Transform3D(shaft_basis, a))
	_link_mm.set_instance_color(i, Color(col.r, col.g, col.b, alpha))
	## Tip triangle at tip, pointing along dir.
	var tip_len := 3.0
	var tip_basis = Basis()
	tip_basis.x = dir * tip_len
	tip_basis.y = Vector3.UP
	tip_basis.z = side * 2.0
	var tip_origin = tip - dir * tip_len
	_tip_mm.set_instance_transform(i, Transform3D(tip_basis, tip_origin))
	_tip_mm.set_instance_color(i, Color(col.r, col.g, col.b, alpha))

func sync_guard_curtains(units: Array) -> void:
	if map == null:
		return
	_ensure_gpu_board()
	_ensure_cell_capacity()
	_ensure_curtain_capacity()
	if _curtain_capacity <= 0 or _curtain_img == null:
		# #region agent log
		_dbg59_board("CUR", "starmap.sync_guard_curtains", "no_capacity", {
			"idx": _index_map.size(), "cap": _curtain_capacity, "runId": "curtain-vis"
		})
		# #endregion
		return
	if _curtain_mmi and view_tier != "starmap":
		_curtain_mmi.visible = true
	## Clear all visible flags.
	for i in _curtain_capacity:
		_curtain_img.set_pixel(i, 0, Color(0, 0, 0, 0))
	var cell_flags: Dictionary = {}
	for u in units:
		if not u.get("alive", false):
			continue
		var g: Dictionary = u.get("guard", {})
		var key = "%s:%d" % [str(u["sys"]), int(u["cell"])]
		if not cell_flags.has(key):
			cell_flags[key] = {"field": false, "link": false, "sys": str(u["sys"]), "cell": int(u["cell"])}
		if g.get("field_on", false):
			cell_flags[key]["field"] = true
		if g.get("link_on", false):
			cell_flags[key]["link"] = true
	var now_t: float = float(Time.get_ticks_msec()) * 0.001
	var written := 0
	var miss := 0
	var sample_gap := 0.0
	var sample_a0 := 0.0
	for key in cell_flags.keys():
		var fl: Dictionary = cell_flags[key]
		var field_on: bool = fl["field"]
		var link_on: bool = fl["link"]
		if not field_on and not link_on:
			continue
		var sid: String = fl["sys"]
		var ci: int = fl["cell"]
		if not map.systems.has(sid):
			continue
		var sys: Dictionary = map.systems[sid]
		var cells: Array = sys["cells"]
		if ci < 0 or ci >= cells.size():
			continue
		## Same seam keys + gap as GPU wedges — curtains sit in transparent intervals.
		var keys: PackedFloat32Array = _separator_keys(cells)
		var kn := keys.size()
		if kn < 2:
			continue
		var k0: float = keys[ci % kn]
		var k1: float = keys[(ci + 1) % kn]
		var span: float = fposmod(k1 - k0, TAU)
		if span < 0.001:
			span = TAU / float(kn)
		var a0: float = k0
		var a1: float = k0 + span
		var sc: float = visual_scale_of(sid)
		var inner: float = float(map.layout.get("ring_inner", 12)) * sc
		var outer: float = float(map.layout.get("ring_outer", 26)) * sc
		var half := maxf(span * 0.5, 0.001)
		var gap := minf(0.55 / maxf(outer, 1.0), half * 0.18)
		if span - 2.0 * gap < 0.012:
			gap = maxf(0.0, span * 0.04)
		## Wall half-angle = gap so ribbon fills the transparent seam only.
		var mode := 0.0 if field_on and not link_on else (1.0 if link_on and not field_on else 2.0)
		var base_i := _curtain_slot_for(sid, ci)
		if base_i < 0:
			miss += 1
			continue
		_write_curtain(base_i, sys["center"], a0, inner, outer, mode, now_t / 8.0, 0.0, gap)
		_write_curtain(base_i + 1, sys["center"], a1, inner, outer, mode, now_t / 8.0, 1.0, gap)
		if sample_gap <= 0.0:
			sample_gap = gap
			sample_a0 = a0
		written += 1
	_curtain_tex.set_image(_curtain_img)
	_curtain_mat.set_shader_parameter("curtain_data", _curtain_tex)
	_curtain_mat.set_shader_parameter("data_width", float(_curtain_capacity))
	# #region agent log
	if Engine.get_process_frames() % 30 == 0:
		var sample_vis := 0.0
		var sample_ang := 0.0
		if written > 0 and _curtain_img != null:
			for si in _curtain_capacity:
				var px: Color = _curtain_img.get_pixel(si, 0)
				if px.a > 0.5:
					sample_vis = px.a
					sample_ang = px.b
					break
		var sh_code := ""
		if _curtain_mat and _curtain_mat.shader:
			sh_code = _curtain_mat.shader.get_code()
		var sample_inner := 0.0
		var sample_h0 := 0.0
		var sh_ang_ok := sh_code.contains("p0.z")
		var sh_row1_ok := sh_code.contains("0.5)")
		if written > 0 and _curtain_img != null:
			for si2 in _curtain_capacity:
				var px0: Color = _curtain_img.get_pixel(si2, 0)
				if px0.a > 0.5:
					var px1: Color = _curtain_img.get_pixel(si2, 1)
					sample_inner = px1.r
					sample_h0 = px1.b
					break
		_dbg59_board("CUR", "starmap.sync_guard_curtains", "chain", {
			"written": written, "miss": miss, "cap": _curtain_capacity,
			"vis": _curtain_mmi.visible if _curtain_mmi else false,
			"tier": view_tier, "sample_vis": sample_vis, "sample_ang": sample_ang,
			"sample_inner": sample_inner, "sample_h0": sample_h0,
			"sample_gap": sample_gap, "sample_a0": sample_a0,
			"mesh_rev": _curtain_mesh_rev, "h0": CURTAIN_H0, "h1": CURTAIN_H1,
			"sh_ang_p0z": sh_ang_ok, "sh_row1_half": sh_row1_ok,
			"sh_ah_p2w": sh_code.contains("p2.w"),
			"blend_add": sh_code.contains("blend_add"),
			"inst_count": _curtain_mm.instance_count if _curtain_mm else -1,
			"runId": "curtain-gap"
		})
	# #endregion

func _curtain_slot_for(sid: String, ci: int) -> int:
	## Two instances per cell: edges at a0/a1. Same order as _index_map.
	for i in _index_map.size():
		var e: Dictionary = _index_map[i]
		if str(e["sid"]) == sid and int(e["cell"]) == ci:
			return i * 2
	return -1

func _write_curtain(
	i: int, center: Vector3, ang: float, inner: float, outer: float,
	mode: float, phase: float, edge_u: float, ang_half: float = 0.02
) -> void:
	if i < 0 or i >= _curtain_capacity:
		return
	_curtain_img.set_pixel(i, 0, Color(center.x, center.z, ang, 1.0))
	_curtain_img.set_pixel(i, 1, Color(inner, outer, CURTAIN_H0, CURTAIN_H1))
	## p2.w = angular half-width of transparent seam (matches GPU wedge gap).
	_curtain_img.set_pixel(i, 2, Color(mode, phase, edge_u, maxf(ang_half, 0.004)))
	_curtain_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(center.x, 0.0, center.z)))

func _ensure_curtain_capacity() -> void:
	var n := _index_map.size() * 2
	if n <= 0:
		_curtain_capacity = 0
		if _curtain_mm:
			_curtain_mm.instance_count = 0
		return
	if n == _curtain_capacity and _curtain_img != null:
		return
	_curtain_capacity = n
	_curtain_img = Image.create(_curtain_capacity, 3, false, Image.FORMAT_RGBAF)
	_curtain_tex = ImageTexture.create_from_image(_curtain_img)
	_curtain_mm.instance_count = _curtain_capacity
	var ident := Transform3D.IDENTITY
	for i in _curtain_capacity:
		_curtain_mm.set_instance_transform(i, ident)

func _rel(owner_fac: int) -> String:
	if owner_fac == 0:
		return "unowned"
	if npc_faction_ids.has(int(owner_fac)):
		return "unowned"
	var rels: Dictionary = diplomacy.get("relations", {}).get(str(viewer), {})
	return str(rels.get(str(owner_fac), "hostile"))

func _owner_color(owner_fac: int) -> Color:
	return BoardTypes.relation_color(_rel(owner_fac))

func _kind_color(kind: int) -> Color:
	match kind:
		BoardTypes.CellKind.GATE:
			return Color(0.22, 0.38, 0.82, 1.0)
		BoardTypes.CellKind.RESOURCE:
			return Color(0.22, 0.65, 0.28, 1.0)
		BoardTypes.CellKind.STATION:
			return Color(0.82, 0.72, 0.18, 1.0)
		BoardTypes.CellKind.SOV:
			return Color(0.78, 0.18, 0.18, 1.0)
		_:
			return Color(0.55, 0.55, 0.58, 1.0)

func _clear_cell_pick() -> void:
	if cell_pick_root == null:
		return
	for c in cell_pick_root.get_children():
		c.queue_free()

func _rebuild_cell_pick() -> void:
	## Deprecated: analytic ray pick in board_root._pick_cell.
	_clear_cell_pick()


func _sov_owner_of(sid: String) -> int:
	## Territory color: SOV beacon cell only (never station / other kinds).
	if map == null or not map.systems.has(sid):
		return 0
	for c in map.systems[sid]["cells"]:
		if int(c.get("kind", -1)) != BoardTypes.CellKind.SOV:
			continue
		return int(c.get("owner", 0))
	return 0



func _link_adj() -> Dictionary:
	var adj: Dictionary = {}
	for sid in map.systems.keys():
		var s := str(sid)
		if not adj.has(s):
			adj[s] = {}
		for link in map.systems[sid]["links"]:
			var to_id := str(link)
			if to_id == "" or not map.systems.has(to_id):
				continue
			if not adj.has(to_id):
				adj[to_id] = {}
			adj[s][to_id] = true
			adj[to_id][s] = true
	return adj


func _find_link_cycles() -> Array:
	## Simple cycles length 3..6 in undirected link graph (closed shapes to fill).
	var adj: Dictionary = _link_adj()
	var nodes: Array = adj.keys()
	nodes.sort()
	var found: Dictionary = {}
	var out: Array = []
	for start in nodes:
		var stack: Array = [[str(start)]]
		while not stack.is_empty():
			var path: Array = stack.pop_back()
			var last: String = str(path[path.size() - 1])
			for nxt in adj.get(last, {}).keys():
				var n2 := str(nxt)
				if n2 == str(path[0]) and path.size() >= 3:
					if path.size() <= 6:
						var canon: Array = path.duplicate()
						var rot_i := 0
						for i in canon.size():
							if str(canon[i]) < str(canon[rot_i]):
								rot_i = i
						var rotated: Array = []
						for j in canon.size():
							rotated.append(canon[(rot_i + j) % canon.size()])
						var rev: Array = rotated.duplicate()
						rev.reverse()
						var key_a := ",".join(PackedStringArray(rotated))
						var key_b := ",".join(PackedStringArray(rev))
						var key := key_a if key_a < key_b else key_b
						if not found.has(key):
							found[key] = true
							out.append(rotated)
					continue
				if path.has(n2):
					continue
				if path.size() >= 6:
					continue
				var np: Array = path.duplicate()
				np.append(n2)
				stack.append(np)
	return out


func _add_cycle_voronoi_fill(cyc: Array, centroid: Vector3) -> void:
	## Balanced fill of closed link polygon: fan from centroid, half-edge to each endpoint owner.
	if territory_root == null or cyc.size() < 3:
		return
	var n := cyc.size()
	var centers: Array = []
	for i in n:
		centers.append(map.systems[str(cyc[i])]["center"])
	## Sort by angle around centroid for a clean fan.
	var order: Array = []
	for i in n:
		var c: Vector3 = centers[i]
		order.append({"i": i, "a": atan2(c.x - centroid.x, c.z - centroid.z)})
	order.sort_custom(func(a, b): return float(a["a"]) < float(b["a"]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n:
		var i0: int = int(order[k]["i"])
		var i1: int = int(order[(k + 1) % n]["i"])
		var v0: Vector3 = centers[i0]
		var v1: Vector3 = centers[i1]
		var mid := (v0 + v1) * 0.5
		var o0 := _sov_owner_of(str(cyc[i0]))
		var o1 := _sov_owner_of(str(cyc[i1]))
		var col0: Color = _owner_color(o0) if o0 != 0 else Color(0.78, 0.78, 0.80, 1.0)
		var col1: Color = _owner_color(o1) if o1 != 0 else Color(0.78, 0.78, 0.80, 1.0)
		col0.a = 0.05
		col1.a = 0.05
		var y := 0.015
		var cflat := Vector3(centroid.x, y, centroid.z)
		var a0 := Vector3(v0.x, y, v0.z)
		var a1 := Vector3(v1.x, y, v1.z)
		var am := Vector3(mid.x, y, mid.z)
		## Tri centroid-v0-mid (owner i0), centroid-mid-v1 (owner i1).
		st.set_color(col0)
		st.add_vertex(cflat); st.add_vertex(a0); st.add_vertex(am)
		st.set_color(col1)
		st.add_vertex(cflat); st.add_vertex(am); st.add_vertex(a1)
	var mi := MeshInstance3D.new()
	mi.name = "CycleFill_%s" % "_".join(PackedStringArray(cyc))
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	territory_root.add_child(mi)

func _add_territory_ring(center: Vector3, radius: float, col: Color, ring_name: String) -> void:
	if territory_root == null or radius < 0.5:
		return
	var mi := MeshInstance3D.new()
	mi.name = ring_name
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segs := 72
	for i in range(segs + 1):
		var a := TAU * float(i) / float(segs)
		st.add_vertex(Vector3(cos(a) * radius, 0.03, sin(a) * radius))
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.no_depth_test = true
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	territory_root.add_child(mi)

func set_territory_visible(on: bool) -> void:
	if territory_root:
		territory_root.visible = on

func _rebuild_territory() -> void:
	## Closed link faces + influence outside, fill on the ground and a raised stroke.
	if territory_root == null or map == null:
		return
	_voronoi_mi = null
	var doomed: Array = territory_root.get_children()
	for c in doomed:
		territory_root.remove_child(c)
		c.free()
	var sites_pos := PackedVector4Array()
	var sites_col := PackedVector4Array()
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var sov_snap: Array = []
	for sid in map.systems.keys():
		var center: Vector3 = map.systems[sid]["center"]
		min_x = minf(min_x, center.x)
		max_x = maxf(max_x, center.x)
		min_z = minf(min_z, center.z)
		max_z = maxf(max_z, center.z)
		var sov_owner := _sov_owner_of(str(sid))
		var col: Color = _owner_color(sov_owner) if sov_owner != 0 else Color(0.78, 0.78, 0.80, 1.0)
		sites_pos.append(Vector4(center.x, 0.0, center.z, float(sov_owner)))
		sites_col.append(Vector4(col.r, col.g, col.b, 1.0))
		sov_snap.append({"sid": str(sid), "ow": sov_owner})
	var nsite := mini(sites_pos.size(), 512)
	if nsite <= 0:
		territory_root.visible = _territory_visible_for_tier()
		return
	var mid := Vector3((min_x + max_x) * 0.5, 0.02, (min_z + max_z) * 0.5)
	const RING_OUT := 26.0
	var nn_sum := 0.0
	var nn_n := 0
	for i in nsite:
		var sp: Vector4 = sites_pos[i]
		var best_nn := 1.0e20
		for j in nsite:
			if i == j:
				continue
			var sq: Vector4 = sites_pos[j]
			best_nn = minf(best_nn, Vector2(sp.x - sq.x, sp.z - sq.z).length())
		if best_nn < 1.0e19:
			nn_sum += best_nn
			nn_n += 1
	var nn_avg := nn_sum / float(maxi(nn_n, 1))
	var site_r := clampf(nn_avg * 0.58, RING_OUT * 1.35, RING_OUT * 3.5) * 2.0
	var span_x := maxf(max_x - min_x, 40.0)
	var span_z := maxf(max_z - min_z, 40.0)
	var pad := site_r * 2.2 + 20.0
	var size := Vector2(span_x + pad * 2.0, span_z + pad * 2.0)
	var pos_img := Image.create(nsite, 1, false, Image.FORMAT_RGBAF)
	var col_img := Image.create(nsite, 1, false, Image.FORMAT_RGBAF)
	for i in nsite:
		var sp2: Vector4 = sites_pos[i]
		var sc: Vector4 = sites_col[i]
		pos_img.set_pixel(i, 0, Color(sp2.x, sp2.y, sp2.z, sp2.w))
		col_img.set_pixel(i, 0, Color(sc.x, sc.y, sc.z, sc.w))
	var pos_tex := ImageTexture.create_from_image(pos_img)
	var col_tex := ImageTexture.create_from_image(col_img)
	var border_w := 0.22
	var raise_y := 0.45
	var faces: Array = _terr_bounded_faces()
	var mask_tex := _terr_bake_closed_mask(faces, mid, size, border_w)
	_terr_add_layer(territory_root, "TerritoryFill", pos_tex, col_tex, nsite, mid, size, site_r, border_w, border_jagged, 0.05, 0.2, mask_tex)
	_terr_add_layer(territory_root, "TerritoryStrokeRaised", pos_tex, col_tex, nsite, mid + Vector3(0.0, raise_y, 0.0), size, site_r, border_w, border_jagged, 0.0, 0.2, mask_tex)
	if not fog_mask.is_empty():
		var fog_img := Image.create(nsite, 1, false, Image.FORMAT_RGBAF)
		var fi := 0
		for sid_f in map.systems.keys():
			if fi >= nsite:
				break
			var hidden := bool(fog_mask.get(str(sid_f), false))
			var fc := Color(0, 0, 0, 0.3) if hidden else Color(0, 0, 0, 0)
			fog_img.set_pixel(fi, 0, fc)
			fi += 1
		var fog_tex := ImageTexture.create_from_image(fog_img)
		_terr_add_layer(territory_root, "FogFill", pos_tex, fog_tex, nsite, mid + Vector3(0.0, 0.08, 0.0), size, site_r, border_w, border_jagged, 1.0, 0.0, mask_tex)
	_voronoi_mi = territory_root.get_node_or_null("TerritoryFill") as MeshInstance3D
	territory_root.visible = _territory_visible_for_tier()
	_dbg59_board("TERR", "starmap._rebuild_territory", "territory", {
		"blobs": territory_root.get_child_count(), "sites": nsite, "faces": faces.size(),
		"mode": "closed_influence", "sov": sov_snap, "jagged": border_jagged, "runId": "studio-port"
	})



func _terr_link_adj_sorted() -> Dictionary:
	var adj: Dictionary = {}
	for sid in map.systems.keys():
		var s := str(sid)
		if not adj.has(s):
			adj[s] = []
		for link in map.systems[sid]["links"]:
			var to_id := str(link)
			if to_id == "" or not map.systems.has(to_id):
				continue
			if not (adj[s] as Array).has(to_id):
				(adj[s] as Array).append(to_id)
			if not adj.has(to_id):
				adj[to_id] = []
			if not (adj[to_id] as Array).has(s):
				(adj[to_id] as Array).append(s)
	for s in adj.keys():
		var c: Vector3 = map.systems[str(s)]["center"]
		var neigh: Array = adj[s]
		neigh.sort_custom(func(na: String, nb: String) -> bool:
			var ca: Vector3 = map.systems[na]["center"]
			var cb: Vector3 = map.systems[nb]["center"]
			return atan2(ca.x - c.x, ca.z - c.z) < atan2(cb.x - c.x, cb.z - c.z)
		)
		adj[s] = neigh
	return adj


func _terr_bounded_faces() -> Array:
	var adj: Dictionary = _terr_link_adj_sorted()
	var used: Dictionary = {}
	var faces_nodes: Array = []
	for a0 in adj.keys():
		var a := str(a0)
		for b0 in adj[a]:
			var b := str(b0)
			var dkey := "%s>%s" % [a, b]
			if used.has(dkey):
				continue
			var path: Array = [a]
			var prev := a
			var cur := b
			var ok := true
			var guard := 0
			while cur != a:
				used["%s>%s" % [prev, cur]] = true
				path.append(cur)
				var neigh: Array = adj.get(cur, [])
				if neigh.is_empty():
					ok = false
					break
				var idx := neigh.find(prev)
				if idx < 0:
					ok = false
					break
				var nidx := (idx - 1 + neigh.size()) % neigh.size()
				var nxt := str(neigh[nidx])
				prev = cur
				cur = nxt
				guard += 1
				if guard > 96 or path.size() > 96:
					ok = false
					break
			if not ok or path.size() < 3:
				continue
			used["%s>%s" % [prev, cur]] = true
			faces_nodes.append(path)
	var polys: Array = []
	var areas: Array = []
	var max_abs := -1.0
	var max_i := -1
	for fi in faces_nodes.size():
		var nodes: Array = faces_nodes[fi]
		var poly := PackedVector2Array()
		poly.resize(nodes.size())
		for pi in nodes.size():
			var pc: Vector3 = map.systems[str(nodes[pi])]["center"]
			poly[pi] = Vector2(pc.x, pc.z)
		var area := _terr_poly_area(poly)
		polys.append(poly)
		areas.append(area)
		if absf(area) > max_abs:
			max_abs = absf(area)
			max_i = fi
	var out: Array = []
	for ai in polys.size():
		if ai == max_i:
			continue
		if absf(float(areas[ai])) < 4.0:
			continue
		out.append(polys[ai])
	return out


func _terr_poly_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	var n := poly.size()
	for i in n:
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % n]
		area += p0.x * p1.y - p1.x * p0.y
	return area * 0.5


func _terr_point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var prev_i := n - 1
	for i in n:
		var yi: float = poly[i].y
		var yj: float = poly[prev_i].y
		var xi: float = poly[i].x
		var xj: float = poly[prev_i].x
		if ((yi > p.y) != (yj > p.y)) and (p.x < (xj - xi) * (p.y - yi) / (yj - yi + 1e-20) + xi):
			inside = not inside
		prev_i = i
	return inside


func _terr_dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var lab2 := ab.length_squared()
	if lab2 < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / lab2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _terr_bake_closed_mask(faces: Array, mid: Vector3, size: Vector2, border_w: float) -> ImageTexture:
	var tex_n := 384
	var img := Image.create(tex_n, tex_n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 1, 0, 1))
	if faces.is_empty():
		return ImageTexture.create_from_image(img)
	var origin := Vector2(mid.x - size.x * 0.5, mid.z - size.y * 0.5)
	var sx := size.x / float(tex_n)
	var sz := size.y / float(tex_n)
	var pack := 256.0
	var search_r := maxf(border_w * 4.0, 8.0)
	var edges: Array = []
	for face in faces:
		var poly: PackedVector2Array = face
		var n := poly.size()
		for i in n:
			edges.append([poly[i], poly[(i + 1) % n]])
		var tris: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			var bbmin := Vector2(INF, INF)
			var bbmax := Vector2(-INF, -INF)
			for i in n:
				bbmin = bbmin.min(poly[i])
				bbmax = bbmax.max(poly[i])
			var x0 := clampi(int(floor((bbmin.x - origin.x) / sx)), 0, tex_n - 1)
			var x1 := clampi(int(ceil((bbmax.x - origin.x) / sx)), 0, tex_n - 1)
			var y0 := clampi(int(floor((bbmin.y - origin.y) / sz)), 0, tex_n - 1)
			var y1 := clampi(int(ceil((bbmax.y - origin.y) / sz)), 0, tex_n - 1)
			for py in range(y0, y1 + 1):
				var wz := origin.y + (float(py) + 0.5) * sz
				for px in range(x0, x1 + 1):
					var wx := origin.x + (float(px) + 0.5) * sx
					if _terr_point_in_poly(Vector2(wx, wz), poly):
						var old := img.get_pixel(px, py)
						img.set_pixel(px, py, Color(1.0, old.g, 0.0, 1.0))
			continue
		var ti := 0
		while ti + 2 < tris.size():
			var ta: Vector2 = poly[tris[ti]]
			var tb: Vector2 = poly[tris[ti + 1]]
			var tc: Vector2 = poly[tris[ti + 2]]
			ti += 3
			var bbmin2 := Vector2(minf(ta.x, minf(tb.x, tc.x)), minf(ta.y, minf(tb.y, tc.y)))
			var bbmax2 := Vector2(maxf(ta.x, maxf(tb.x, tc.x)), maxf(ta.y, maxf(tb.y, tc.y)))
			var x0b := clampi(int(floor((bbmin2.x - origin.x) / sx)), 0, tex_n - 1)
			var x1b := clampi(int(ceil((bbmax2.x - origin.x) / sx)), 0, tex_n - 1)
			var y0b := clampi(int(floor((bbmin2.y - origin.y) / sz)), 0, tex_n - 1)
			var y1b := clampi(int(ceil((bbmax2.y - origin.y) / sz)), 0, tex_n - 1)
			for py2 in range(y0b, y1b + 1):
				var wz2 := origin.y + (float(py2) + 0.5) * sz
				for px2 in range(x0b, x1b + 1):
					var wx2 := origin.x + (float(px2) + 0.5) * sx
					if Geometry2D.point_is_inside_triangle(Vector2(wx2, wz2), ta, tb, tc):
						var old2 := img.get_pixel(px2, py2)
						img.set_pixel(px2, py2, Color(1.0, old2.g, 0.0, 1.0))
	for e in edges:
		var ea: Vector2 = e[0]
		var eb: Vector2 = e[1]
		var emin := Vector2(minf(ea.x, eb.x) - search_r, minf(ea.y, eb.y) - search_r)
		var emax := Vector2(maxf(ea.x, eb.x) + search_r, maxf(ea.y, eb.y) + search_r)
		var x0e := clampi(int(floor((emin.x - origin.x) / sx)), 0, tex_n - 1)
		var x1e := clampi(int(ceil((emax.x - origin.x) / sx)), 0, tex_n - 1)
		var y0e := clampi(int(floor((emin.y - origin.y) / sz)), 0, tex_n - 1)
		var y1e := clampi(int(ceil((emax.y - origin.y) / sz)), 0, tex_n - 1)
		for py3 in range(y0e, y1e + 1):
			var wz3 := origin.y + (float(py3) + 0.5) * sz
			for px3 in range(x0e, x1e + 1):
				var wx3 := origin.x + (float(px3) + 0.5) * sx
				var dist := _terr_dist_seg(Vector2(wx3, wz3), ea, eb)
				if dist > search_r:
					continue
				var old3 := img.get_pixel(px3, py3)
				var g := minf(old3.g, clampf(dist / pack, 0.0, 1.0))
				img.set_pixel(px3, py3, Color(old3.r, g, 0.0, 1.0))
	return ImageTexture.create_from_image(img)


func _terr_add_layer(
	parent: Node3D, layer_name: String, pos_tex: Texture2D, col_tex: Texture2D, nsite: int,
	mid: Vector3, size: Vector2, cluster_r: float, border_w: float, jagged: float,
	fill_a: float, border_a: float, closed_mask: Texture2D
) -> void:
	var mi := MeshInstance3D.new()
	mi.name = layer_name
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/board_territory_voronoi.gdshader")
	sm.set_shader_parameter("site_pos_tex", pos_tex)
	sm.set_shader_parameter("site_col_tex", col_tex)
	sm.set_shader_parameter("site_count", nsite)
	sm.set_shader_parameter("cluster_center", Vector4(mid.x, 0.0, mid.z, 0.0))
	sm.set_shader_parameter("cluster_r", cluster_r)
	sm.set_shader_parameter("fill_a", fill_a)
	sm.set_shader_parameter("border_a", border_a)
	sm.set_shader_parameter("border_w", border_w)
	sm.set_shader_parameter("jagged", jagged)
	sm.set_shader_parameter("edge_base", 0.92)
	sm.set_shader_parameter("quad_half", Vector2(size.x * 0.5, size.y * 0.5))
	sm.set_shader_parameter("noise_scale", 1.0)
	sm.set_shader_parameter("closed_mask_tex", closed_mask)
	sm.set_shader_parameter("use_closed_mask", 1)
	mi.material_override = sm
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.position = mid
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func set_border_jagged(v: float) -> void:
	border_jagged = clampf(v, 0.0, 1.5)
	var mi_ok := false
	var applied := -1.0
	var kids := 0
	if territory_root:
		kids = territory_root.get_child_count()
		for layer in territory_root.get_children():
			if not (layer is MeshInstance3D):
				continue
			var lmi := layer as MeshInstance3D
			if not (lmi.material_override is ShaderMaterial):
				continue
			var sm := lmi.material_override as ShaderMaterial
			sm.set_shader_parameter("jagged", border_jagged)
			applied = float(sm.get_shader_parameter("jagged"))
			mi_ok = true
	# #region agent log
	_dbg59_board("JAG_JUNC", "starmap.set_border_jagged", "jagged_junction", {
		"v": border_jagged,
		"mi_ok": mi_ok,
		"applied": applied,
		"kids": kids,
		"warp_amp": border_jagged * 28.0,
		"edge_wobble": border_jagged * 16.0,
		"outer_gain": 2.6,
		"runId": "junc-fix"
	})
	# #endregion


func set_system_name_scale(v: float) -> void:
	system_name_scale = clampf(v, 0.25, 8.0)
	_apply_sysname_scale_for_tier()
	# #region agent log
	_dbg59_board("SYS_N", "starmap.set_system_name_scale", "sys_name", {
		"v": system_name_scale, "eff": _effective_sysname_scale(), "tier": view_tier, "runId": "tiers"
	})
	# #endregion


func set_view_tier(tier: String) -> void:
	view_tier = tier if tier in ["battle", "tactical", "starmap"] else "battle"
	_tactical_icon_mode = view_tier == "tactical" or view_tier == "starmap"
	_apply_icon_scale_all()
	_apply_sysname_scale_for_tier()
	_apply_tier_visibility()
	# #region agent log
	_dbg59_board("TIER", "starmap.set_view_tier", "view_tier", {
		"tier": view_tier, "eff_icon": _effective_icon_scale(),
		"eff_sys": _effective_sysname_scale(), "runId": "tiers"
	})
	# #endregion


func set_tactical_icon_mode(on: bool) -> void:
	## Legacy bridge — prefer set_view_tier.
	set_view_tier("tactical" if on else "battle")


func set_icon_scale(v: float) -> void:
	icon_scale = clampf(v, 0.25, 8.0)
	_apply_icon_scale_all()
	# #region agent log
	_dbg59_board("ICON_SC", "starmap.set_icon_scale", "icon_scale", {
		"v": icon_scale, "tier": view_tier, "eff": _effective_icon_scale(), "runId": "tiers"
	})
	# #endregion


func _effective_icon_scale() -> float:
	if view_tier == "starmap":
		return STARMAP_ICON_SCALE
	if view_tier == "tactical":
		return icon_scale
	return ORBIT_ICON_SCALE


func _effective_sysname_scale() -> float:
	return system_name_scale if view_tier != "battle" else BATTLE_SYSNAME_SCALE


func _apply_sysname_scale_for_tier() -> void:
	if icon_root == null:
		return
	var eff := _effective_sysname_scale()
	for c in icon_root.get_children():
		if c is Label3D and c.has_meta("system_label"):
			var base_f := int(c.get_meta("base_font", 640))
			(c as Label3D).font_size = int(round(float(base_f) * eff))


func _territory_visible_for_tier() -> bool:
	return view_tier == "battle" or view_tier == "tactical" or view_tier == "starmap"


func _apply_tier_visibility() -> void:
	var star := view_tier == "starmap"
	var show_terr := _territory_visible_for_tier()
	## 星图: hide ring/fill/rim chrome; keep Territory 底图 + StarmapGraph.
	if label_root:
		label_root.visible = not star
	if icon_root:
		icon_root.visible = not star
	if territory_root:
		territory_root.visible = show_terr
	if _ring_root:
		_ring_root.visible = not star
	## Fill/Rim wedges stay off (StdMat rings); curtains/links stay on in battle/tactical.
	_apply_battle_gpu_vis()
	_ensure_starmap_graph()
	if starmap_graph_root:
		starmap_graph_root.visible = star
		## Keep graph above territory in tree so icons/lines draw after 底图.
		if star and territory_root and starmap_graph_root.get_index() < territory_root.get_index():
			move_child(starmap_graph_root, get_child_count() - 1)


func _apply_icon_scale_all() -> void:
	if icon_root == null:
		return
	var eff := _effective_icon_scale()
	_apply_icon_scale_node(icon_root, eff)


func _apply_icon_scale_node(n: Node, eff: float) -> void:
	if n is Sprite3D and n.has_meta("base_pixel"):
		(n as Sprite3D).pixel_size = float(n.get_meta("base_pixel")) * eff
	for ch in n.get_children():
		_apply_icon_scale_node(ch, eff)


func _ensure_starmap_graph() -> void:
	if starmap_graph_root != null and is_instance_valid(starmap_graph_root):
		return
	starmap_graph_root = Node3D.new()
	starmap_graph_root.name = "StarmapGraph"
	starmap_graph_root.visible = false
	add_child(starmap_graph_root)


func set_starmap_name_scale(v: float) -> void:
	## Font only — does not affect system icons.
	starmap_name_scale = maxf(v, 0.05)
	if view_tier == "starmap":
		rebuild_starmap_graph(_starmap_counts_cache)


func set_starmap_icon_scale(v: float) -> void:
	starmap_icon_scale = maxf(v, 0.05)
	if view_tier == "starmap":
		rebuild_starmap_graph(_starmap_counts_cache)


func set_starmap_badge_scale(v: float) -> void:
	starmap_badge_scale = maxf(v, 0.05)
	if view_tier == "starmap":
		rebuild_starmap_graph(_starmap_counts_cache)


func set_starmap_count_scale(v: float) -> void:
	starmap_count_scale = maxf(v, 0.05)
	# #region agent log
	_dbg59_board("CNT", "starmap.set_starmap_count_scale", "spin", {
		"v": starmap_count_scale,
		"count_px": ICON_BASE_PIXEL * 0.55 * starmap_count_scale,
		"tier": view_tier, "runId": "count-scale-fix"
	})
	# #endregion
	if view_tier == "starmap":
		rebuild_starmap_graph(_starmap_counts_cache)


func set_starmap_highlight(sid: String) -> void:
	starmap_highlight_sys = str(sid)
	_apply_starmap_highlight()


func _apply_starmap_highlight() -> void:
	## Soft yellow halo a=0.2 — no torus / ring / horizontal line.
	if starmap_graph_root == null or not is_instance_valid(starmap_graph_root):
		return
	for c in starmap_graph_root.get_children():
		if not str(c.name).begins_with("Sys_"):
			continue
		var s: String = str(c.name).substr(4)
		var on: bool = (s == starmap_highlight_sys and starmap_highlight_sys != "")
		c.scale = Vector3.ONE
		## Strip legacy ring if any.
		var legacy: Node = c.get_node_or_null("HighlightRing")
		if legacy:
			legacy.queue_free()
		var glow: MeshInstance3D = c.get_node_or_null("HighlightGlow") as MeshInstance3D
		if on:
			if glow == null:
				glow = MeshInstance3D.new()
				glow.name = "HighlightGlow"
				var sph := SphereMesh.new()
				var r := 6.2 * maxf(starmap_icon_scale, 0.5)
				sph.radius = r
				sph.height = r * 2.0
				glow.mesh = sph
				var gmat := StandardMaterial3D.new()
				gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				gmat.albedo_color = Color(1.0, 0.92, 0.35, 0.2)
				gmat.no_depth_test = true
				gmat.disable_receive_shadows = true
				gmat.render_priority = -1
				glow.material_override = gmat
				glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				glow.position = Vector3(0, 0.55, 0)
				c.add_child(glow)
			else:
				glow.visible = true
		elif glow:
			glow.visible = false
		for ch in c.get_children():
			if ch is Sprite3D and ch.get_meta("system_marker", false):
				(ch as Sprite3D).modulate = Color.WHITE
			elif ch is MeshInstance3D and ch.get_meta("system_marker", false) and str(ch.name) != "HighlightGlow":
				var mi := ch as MeshInstance3D
				if mi.material_override is StandardMaterial3D:
					(mi.material_override as StandardMaterial3D).albedo_color = Color(0.82, 0.9, 1.0, 1.0)


func sync_rep_badges(counts: Dictionary) -> void:
	## Rebuild point-line graph with names + reputation headcounts + gate status.
	_starmap_counts_cache = counts.duplicate(true)
	if view_tier != "starmap":
		_ensure_starmap_graph()
		if starmap_graph_root:
			starmap_graph_root.visible = false
		return
	rebuild_starmap_graph(counts)


func rebuild_starmap_graph(counts: Dictionary = {}) -> void:
	_ensure_starmap_graph()
	if map == null:
		return
	if not counts.is_empty():
		_starmap_counts_cache = counts.duplicate(true)
	else:
		counts = _starmap_counts_cache
	for c in starmap_graph_root.get_children():
		starmap_graph_root.remove_child(c)
		c.free()
	_ensure_rep_badge_tex()
	## Directed gate status lines UNDER icons (depth test; lower Y).
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.vertex_color_use_as_albedo = true
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lmat.no_depth_test = false
	lmat.render_priority = -2
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, lmat)
	var edge_n := 0
	for sid in map.systems.keys():
		var a := str(sid)
		for link in map.systems[sid].get("links", []):
			var b := str(link)
			if b == "" or not map.systems.has(b):
				continue
			_graph_emit_gate_link(im, a, b)
			edge_n += 1
	im.surface_end()
	var line_mi := MeshInstance3D.new()
	line_mi.name = "GraphLinks"
	line_mi.mesh = im
	line_mi.material_override = lmat
	line_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	starmap_graph_root.add_child(line_mi)
	## Kind icons + name + headcount (STARMAP §2 kinds).
	var name_fs := int(round(520.0 * starmap_name_scale))
	## Count world size via pixel_size (same lever as badges) — font_size alone is near-invisible at starmap height.
	var count_px := ICON_BASE_PIXEL * 0.55 * maxf(starmap_count_scale, 0.05)
	var badge_px := ICON_BASE_PIXEL * 1.35 * starmap_badge_scale
	const STATION_TEX := "res://assets/ui/sector/station.png"
	const GEAR_TEX := "res://assets/ui/sector/gear.png"
	const RESOURCE_FALLBACK := "res://assets/ui/sector/resource.png"
	for sid in map.systems.keys():
		var s := str(sid)
		var sysd: Dictionary = map.systems[sid]
		var center: Vector3 = sysd["center"]
		var node := Node3D.new()
		node.name = "Sys_%s" % s
		node.position = Vector3(center.x, 0.12, center.z)
		starmap_graph_root.add_child(node)
		var kind := str(sysd.get("kind", "station_system"))
		_graph_add_system_marker(node, kind, STATION_TEX, GEAR_TEX, RESOURCE_FALLBACK)
		var nm := str(sysd.get("name", s))
		var name_lab := _billboard_label(nm, Vector3(0, 0.2, 5.2 * maxf(starmap_name_scale, 0.7)), name_fs, Color(0.95, 0.97, 1.0, 1.0))
		name_lab.set_meta("system_label", true)
		node.add_child(name_lab)
		var bag: Dictionary = counts.get(s, {})
		## Right of system icon; non-zero rows only, centered on icon horizontal (local Z=0).
		_graph_add_rep_stack(node, bag, badge_px, count_px)
	starmap_graph_root.visible = true
	_apply_starmap_highlight()
	# #region agent log
	var sample_n := 0
	var sample_sid := ""
	var sample_rows := 0
	for sk in counts.keys():
		sample_sid = str(sk)
		var b0: Dictionary = counts[sk]
		sample_n = int(b0.get("self", 0)) + int(b0.get("ally", 0)) + int(b0.get("hostile", 0))
		for kk in ["hostile", "ally", "self"]:
			if int(b0.get(kk, 0)) > 0:
				sample_rows += 1
		break
	_dbg59_board("CNT", "starmap.rebuild_starmap_graph", "rep_stack", {
		"nodes": map.systems.size(), "edges": edge_n,
		"counts": counts.size(), "count_px": count_px, "badge_px": badge_px,
		"sample_sid": sample_sid, "sample_n": sample_n, "sample_rows": sample_rows,
		"badge_sc": starmap_badge_scale, "count_sc": starmap_count_scale,
		"hl": starmap_highlight_sys, "runId": "count-scale-fix"
	})
	# #endregion


func _graph_add_rep_stack(node: Node3D, bag: Dictionary, badge_px: float, count_px: float) -> void:
	## Non-zero rows only; stack centered on system-icon horizontal (local Z=0 / nadir mid-line).
	var bsc := maxf(starmap_badge_scale, 0.05)
	var csc := maxf(starmap_count_scale, 0.05)
	var layout_sc := maxf(bsc, csc)
	var rx := 4.2 * maxf(layout_sc, 0.6) ## right of system marker
	var row_dz := 2.6 * maxf(maxf(bsc, csc * 0.55), 0.6)
	var num_dx := 2.4 * maxf(layout_sc, 0.6)
	var order: Array = [
		{"k": "hostile", "col": Color(0.95, 0.32, 0.28, 1.0)},
		{"k": "ally", "col": Color(0.4, 0.65, 1.0, 1.0)},
		{"k": "self", "col": Color(0.35, 0.95, 0.45, 1.0)},
	]
	var rows: Array = []
	for ent0 in order:
		var ent: Dictionary = ent0
		var n0: int = int(bag.get(ent["k"], 0))
		if n0 > 0:
			rows.append({"k": ent["k"], "col": ent["col"], "n": n0})
	if rows.is_empty():
		return
	## Center visible block on Z=0 (system icon horizontal line under nadir cam).
	var z0 := -0.5 * float(rows.size() - 1) * row_dz
	## Glyph resolution fixed; world size = pixel_size × count scale.
	const COUNT_FONT := 96
	var px := maxf(count_px, 0.001)
	for i in rows.size():
		var ent2: Dictionary = rows[i]
		var n: int = int(ent2["n"])
		var z := z0 + float(i) * row_dz
		var icon_pos := Vector3(rx, 0.55, z) ## y matches system marker mid
		var tex: Texture2D = _rep_badge_tex.get(ent2["k"])
		if tex:
			var spr := Sprite3D.new()
			spr.texture = tex
			spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			spr.shaded = false
			spr.double_sided = true
			spr.no_depth_test = true
			spr.transparent = true
			spr.pixel_size = badge_px
			spr.position = icon_pos
			spr.render_priority = 1
			spr.set_meta("rep_badge", true)
			node.add_child(spr)
		var cnt := Label3D.new()
		cnt.text = str(n)
		cnt.font_size = COUNT_FONT
		cnt.pixel_size = px
		cnt.modulate = ent2["col"]
		cnt.outline_size = 8
		cnt.outline_modulate = Color(0.04, 0.05, 0.08, 1.0)
		cnt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cnt.no_depth_test = true
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cnt.position = icon_pos + Vector3(num_dx, 0.05, 0.0)
		cnt.render_priority = 3
		cnt.set_meta("rep_count", true)
		cnt.set_meta("base_font", COUNT_FONT)
		cnt.set_meta("base_pixel", px)
		node.add_child(cnt)


func _graph_add_system_marker(node: Node3D, kind: String, station_tex: String, gear_tex: String, resource_fb: String) -> void:
	## Inherit battlefield/tactical system marker kinds; size = starmap_icon_scale only.
	var isc := maxf(starmap_icon_scale, 0.05)
	if kind == "station_system" and ResourceLoader.exists(station_tex):
		var spr := _billboard_sprite(station_tex, Vector3(0, 0.55, 0), ICON_BASE_PIXEL * 1.85 * isc)
		spr.set_meta("system_marker", true)
		## Depth on: occlude gate arrows underneath (nadir cam).
		spr.no_depth_test = false
		spr.render_priority = 2
		if spr.has_meta("screen_const"):
			spr.remove_meta("screen_const")
		node.add_child(spr)
		return
	if kind == "resource_system":
		var gear_path := gear_tex if ResourceLoader.exists(gear_tex) else resource_fb
		if ResourceLoader.exists(gear_path):
			var spr2 := _billboard_sprite(gear_path, Vector3(0, 0.55, 0), ICON_BASE_PIXEL * 0.45 * isc)
			spr2.set_meta("system_marker", true)
			spr2.no_depth_test = false
			spr2.render_priority = 2
			if spr2.has_meta("screen_const"):
				spr2.remove_meta("screen_const")
			node.add_child(spr2)
			return
	var dot := MeshInstance3D.new()
	var sph := SphereMesh.new()
	var r := 2.4 * isc
	sph.radius = r
	sph.height = r * 2.0
	dot.mesh = sph
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(0.82, 0.9, 1.0, 1.0)
	dmat.no_depth_test = false
	dmat.render_priority = 2
	dot.material_override = dmat
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot.position = Vector3(0, 0.55, 0)
	dot.set_meta("system_marker", true)
	node.add_child(dot)


func _graph_emit_gate_link(im: ImmediateMesh, from_id: String, to_id: String) -> void:
	## Directed stargate status — same solid/dash + relation color as tactical links.
	var ca: Vector3 = map.systems[from_id]["center"]
	var cb: Vector3 = map.systems[to_id]["center"]
	var dir := Vector3(cb.x - ca.x, 0.0, cb.z - ca.z)
	var L := dir.length()
	if L < 0.001:
		return
	dir /= L
	## Slight lateral offset so A→B / B→A don't fully overlap.
	var side := Vector3(-dir.z, 0.0, dir.x)
	if side.length_squared() < 0.0001:
		side = Vector3(1, 0, 0)
	side = side.normalized() * 0.9
	## y low so system markers (higher Y) occlude shafts/arrows from nadir.
	var start := Vector3(ca.x, 0.04, ca.z) + dir * 3.6 + side
	var end := Vector3(cb.x, 0.04, cb.z) - dir * 3.6 + side
	var tip := start.lerp(end, 0.72)
	var gate_i := -1
	var owner_fac := 0
	for c in map.systems[from_id]["cells"]:
		if int(c["kind"]) == BoardTypes.CellKind.GATE and str(c["gate_to"]) == to_id:
			gate_i = int(c["index"])
			owner_fac = int(c["owner"])
			break
	var col := _owner_color(owner_fac) if owner_fac != 0 else Color(1, 1, 1, 1)
	var can := gate_i >= 0 and map.can_pass_gate(from_id, gate_i, viewer, diplomacy)
	var transit := transit_gates.has("%s:%d" % [from_id, gate_i])
	var owned := owner_fac != 0
	var use_solid := owned or can or transit
	var alpha: float
	if use_solid:
		alpha = 0.95 if (can or transit) else 0.72
	else:
		alpha = 0.32
	col.a = alpha
	if use_solid:
		im.surface_set_color(col)
		im.surface_add_vertex(start)
		im.surface_add_vertex(tip)
	else:
		_graph_emit_dashed(im, start, tip, col, 2.4, 1.6)
	## Arrow tip at 2/3 (STARMAP §4).
	var wing := side.normalized() * 1.7
	var base := tip - dir * 2.2
	im.surface_set_color(col)
	im.surface_add_vertex(tip)
	im.surface_add_vertex(base + wing)
	im.surface_add_vertex(tip)
	im.surface_add_vertex(base - wing)


func _graph_emit_dashed(im: ImmediateMesh, a: Vector3, b: Vector3, col: Color, on_len: float, off_len: float) -> void:
	var delta := b - a
	var total := delta.length()
	if total < 0.001:
		return
	var step_dir := delta / total
	var t := 0.0
	var drawing := true
	while t < total - 0.001:
		var seg := on_len if drawing else off_len
		var t1 := minf(t + seg, total)
		if drawing:
			im.surface_set_color(col)
			im.surface_add_vertex(a + step_dir * t)
			im.surface_add_vertex(a + step_dir * t1)
		t = t1
		drawing = not drawing


func _ensure_rep_badge_tex() -> void:
	if not _rep_badge_tex.is_empty():
		return
	var paths := {
		"self": "res://assets/ui/sprites/tonnage_overlays/07_corp_fleet_badge.png",
		"ally": "res://assets/ui/sprites/tonnage_overlays/06_friendly_badge.png",
		"hostile": "res://assets/ui/sprites/tonnage_overlays/01_red_minus_badge.png",
	}
	for k in paths.keys():
		var p: String = paths[k]
		if not ResourceLoader.exists(p) and k == "self":
			p = "res://assets/ui/sprites/tonnage_overlays/03_fleet_member.png"
		if ResourceLoader.exists(p):
			_rep_badge_tex[k] = load(p)

func _billboard_sprite(tex_path: String, pos: Vector3, pixel: float = ICON_BASE_PIXEL) -> Sprite3D:
	var spr = Sprite3D.new()
	if ResourceLoader.exists(tex_path):
		spr.texture = load(tex_path)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.double_sided = true
	spr.no_depth_test = true
	spr.transparent = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	spr.set_meta("base_pixel", pixel)
	spr.pixel_size = pixel * _effective_icon_scale()
	spr.position = pos
	## screen_const disabled — world-fixed icon size.
	return spr

func _billboard_label(text: String, pos: Vector3, size: int = 84, col: Color = Color(0.95, 0.95, 1.0)) -> Label3D:
	var lab = Label3D.new()
	lab.text = text
	lab.font_size = size
	lab.modulate = col
	lab.outline_size = 2
	lab.outline_modulate = Color(0.04, 0.05, 0.08, 1.0)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = pos
	lab.set_meta("base_font", size)
	## screen_const disabled — world-fixed label size.
	return lab

func tick_screen_const_icons() -> void:
	## Disabled: icons/names keep fixed world size (no zoom compensation).
	return

func _apply_screen_const(node: Node) -> void:
	if not node.has_meta("screen_const"):
		return
	var dist = link_cam.global_position.distance_to((node as Node3D).global_position)
	## No upper clamp — keep on-screen size stable into tactical zoom-out.
	var sc = maxf(dist / ICON_REF_DIST, 0.65)
	if node is Sprite3D:
		var base_p = float(node.get_meta("base_pixel", ICON_BASE_PIXEL))
		(node as Sprite3D).pixel_size = base_p * sc
	elif node is Label3D:
		var base_f = int(node.get_meta("base_font", 84))
		(node as Label3D).font_size = int(round(float(base_f) * sc))
		if node.has_meta("system_label") and Engine.get_process_frames() % 90 == 0:
			_dbg59_board("SYS_LBL", "starmap._apply_screen_const", "sys_name_scale", {
				"base": base_f, "sc": sc, "font": (node as Label3D).font_size, "dist": dist, "runId": "post-fix"
			})

func _rebuild_sector_icons() -> void:
	if icon_root == null or map == null:
		return
	## Keep system-center markers (station/gear/dot) + name labels; only refresh edge holders.
	for c in icon_root.get_children():
		if c.has_meta("system_marker") or c.has_meta("system_label"):
			continue
		c.queue_free()
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		var sys_scale: float = visual_scale_of(sid)
		var outer: float = float(map.layout.get("ring_outer", 26)) * sys_scale
		for cell in sys["cells"]:
			var kind: int = int(cell["kind"])
			if not SECTOR_ICON.has(kind):
				continue
			var a: float = float(cell["angle_center"])
			var r: float = outer + 3.2
			var pos: Vector3 = sys["center"] + Vector3(sin(a) * r, 0.55, -cos(a) * r)
			var holder := Node3D.new()
			holder.name = "Edge_%s_%d" % [sid, int(cell.get("index", 0))]
			holder.position = pos
			holder.set_meta("edge_sid", sid)
			holder.set_meta("edge_ang", a)
			holder.set_meta("edge_cell", int(cell.get("index", 0)))
			holder.set_meta("edge_pad", 3.2)
			holder.set_meta("edge_y", 0.55)
			if kind == BoardTypes.CellKind.RESOURCE:
				holder.set_meta("edge_resource", true)
			var spr = _billboard_sprite(SECTOR_ICON[kind], Vector3.ZERO, ICON_BASE_PIXEL)
			spr.name = "Icon"
			holder.add_child(spr)
			icon_root.add_child(holder)
	tick_icon_edge_follow()

func _rebuild_system_markers() -> void:
	if icon_root == null or map == null:
		return
	for c in icon_root.get_children():
		if c.has_meta("system_marker") or c.has_meta("system_label"):
			c.queue_free()
	const STATION_TEX := "res://assets/ui/sector/station.png"
	const GEAR_TEX := "res://assets/ui/sector/gear.png"
	const RESOURCE_FALLBACK := "res://assets/ui/sector/resource.png"
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		var center: Vector3 = sys["center"]
		var kind: String = str(sys.get("kind", "station_system"))
		if kind == "station_system":
			var tex_path = STATION_TEX
			if ResourceLoader.exists(tex_path):
				var spr = _billboard_sprite(tex_path, center + Vector3(0, 0.35, 0), ICON_BASE_PIXEL * 1.85)
				spr.set_meta("system_marker", true)
				## Center marks stay world-sized (not screen-const blown up).
				spr.remove_meta("screen_const")
				icon_root.add_child(spr)
			else:
				_add_system_sphere_marker(center)
		elif kind == "resource_system":
			var gear_path = GEAR_TEX if ResourceLoader.exists(GEAR_TEX) else RESOURCE_FALLBACK
			if ResourceLoader.exists(gear_path):
				## Gear was oversized; 1/3 of prior (1.35 → 0.45).
				var spr2 = _billboard_sprite(gear_path, center + Vector3(0, 0.35, 0), ICON_BASE_PIXEL * 0.45)
				spr2.set_meta("system_marker", true)
				spr2.remove_meta("screen_const")
				icon_root.add_child(spr2)
			else:
				_add_system_sphere_marker(center)
		else:
			_add_system_sphere_marker(center)
		## Name under icon (south / +Z) — not above.
		var lab = _billboard_label(str(sys.get("name", sid)), center + Vector3(0, 0.25, 3.4), 640)
		lab.set_meta("system_label", true)
		lab.font_size = int(round(640.0 * _effective_sysname_scale()))
		icon_root.add_child(lab)

func _add_system_sphere_marker(center: Vector3) -> void:
	var dot = MeshInstance3D.new()
	var sph = SphereMesh.new()
	sph.radius = 0.85
	sph.height = 1.7
	dot.mesh = sph
	var dmat = StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(0.85, 0.9, 1.0, 0.9)
	dot.material_override = dmat
	dot.position = center + Vector3(0, 0.2, 0)
	dot.set_meta("system_marker", true)
	icon_root.add_child(dot)

func rebuild_labels(pilots: Array) -> void:
	## Pilot names live in the same edge holder as the resource icon (STARMAP §5) — left via local −X.
	pilots_ref = pilots
	if label_root:
		for c in label_root.get_children():
			c.queue_free()
	if icon_root == null or map == null:
		return
	var name_by_id: Dictionary = {}
	for p in pilots:
		name_by_id[str(p["id"])] = str(p.get("name", ""))
	var holders: Dictionary = {}
	for c in icon_root.get_children():
		if not c.has_meta("edge_resource"):
			continue
		var key := "%s:%d" % [str(c.get_meta("edge_sid")), int(c.get_meta("edge_cell"))]
		holders[key] = c
		var old_n := c.get_node_or_null("PilotName")
		if old_n:
			old_n.queue_free()
	var attached := 0
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		for cell in sys["cells"]:
			if int(cell["kind"]) != BoardTypes.CellKind.RESOURCE:
				continue
			var pid: String = str(cell.get("assigned_pilot_id", ""))
			if pid == "" or not name_by_id.has(pid):
				continue
			var key2 := "%s:%d" % [sid, int(cell.get("index", 0))]
			if not holders.has(key2):
				continue
			var holder: Node3D = holders[key2]
			var lab = _billboard_label(str(name_by_id[pid]), Vector3(-2.6, 0.15, 0.0), 440, Color(0.85, 1.0, 0.85, 1.0))
			lab.name = "PilotName"
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			holder.add_child(lab)
			attached += 1
	# #region agent log
	_dbg59_board("RES_C", "starmap.rebuild_labels", "edge_holder", {
		"holders": holders.size(), "attached": attached, "runId": "res-container"
	})
	# #endregion
	tick_icon_edge_follow()
