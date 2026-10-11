extends Node3D
class_name BoardTurretVfx

## EveAC-inspired short beam / muzzle flash between world points.

const DEFAULT_THICK := 0.08

var _manifest: Dictionary = {}
var _cache: Dictionary = {} # path -> Texture2D

func _ready() -> void:
	if ResourceLoader.exists("res://assets/vfx/turret_fx/manifest.json"):
		var f = FileAccess.open("res://assets/vfx/turret_fx/manifest.json", FileAccess.READ)
		_manifest = JSON.parse_string(f.get_as_text())

func play(
	fx_kind: String,
	from: Vector3,
	to: Vector3,
	_camera: Camera3D = null,
	thick_wu: float = 0.0
) -> void:
	## thick_wu: tactical beam cross-section width in world units (icon circum-radius).
	var entry: Dictionary = _manifest.get(fx_kind, _manifest.get("rail", {}))
	if entry.is_empty():
		entry = {"tex_near": "res://assets/vfx/turret_fx/rail/hybridblastfx_01a.png"}
	var dist = from.distance_to(to)
	var tex_path = str(entry.get("tex_far" if dist > 8.0 else "tex_near", entry.get("tex_shared", "")))
	var tex = _tex(tex_path)
	var mid = from.lerp(to, 0.5)
	mid.y += 0.35
	var thick := DEFAULT_THICK
	if thick_wu > 0.0:
		thick = maxf(thick, thick_wu)
	# Core beam strip (always)
	var beam = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(thick, thick, maxf(dist, 0.5))
	beam.mesh = box
	var bmat = StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(1.0, 0.85, 0.45, 0.75)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.7, 0.2)
	bmat.emission_energy_multiplier = 3.5
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.no_depth_test = true
	beam.material_override = bmat
	add_child(beam)
	beam.top_level = true
	beam.global_position = mid
	var aim := to + Vector3(0, 0.35, 0)
	if from.distance_squared_to(aim) > 0.0001:
		## Top-down: avoid look_at colinear with UP (beam vanishes).
		var dir: Vector3 = aim - beam.global_position
		var up: Vector3 = Vector3.UP
		if dir.length_squared() > 0.0001 and absf(dir.normalized().dot(up)) > 0.92:
			up = Vector3.FORWARD
		beam.look_at(aim, up)
	var tw = create_tween()
	tw.tween_property(bmat, "albedo_color:a", 0.0, 0.18)
	tw.parallel().tween_property(bmat, "emission_energy_multiplier", 0.2, 0.18)
	tw.tween_callback(beam.queue_free)
	if tex == null:
		return
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.double_sided = true
	spr.transparent = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.pixel_size = 0.0038
	spr.modulate = Color(1, 1, 1, 0.85)
	var mid2 = from.lerp(to, 0.28)
	mid2.y += 0.45
	spr.position = mid2
	var stretch = clampf(dist * 0.025, 0.7, 1.8)
	## Match flash lateral scale to tactical beam width when thickened.
	var tex_h: int = tex.get_height() if tex != null else 0
	if thick > DEFAULT_THICK + 0.001 and tex_h > 0:
		var base_h: float = float(tex_h) * spr.pixel_size
		if base_h > 0.0001:
			stretch = maxf(stretch, thick / base_h)
	spr.scale = Vector3(stretch, stretch * 0.5, 1.0)
	add_child(spr)
	var tw2 = create_tween()
	tw2.tween_property(spr, "modulate:a", 0.0, 0.2)
	tw2.tween_callback(spr.queue_free)

func _tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var t = load(path)
	_cache[path] = t
	return t
