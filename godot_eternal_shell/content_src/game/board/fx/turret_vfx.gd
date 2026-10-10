extends Node3D
class_name BoardTurretVfx

## EveAC-inspired short beam / muzzle flash between world points.

var _manifest: Dictionary = {}
var _cache: Dictionary = {} # path -> Texture2D

func _ready() -> void:
	if ResourceLoader.exists("res://assets/vfx/turret_fx/manifest.json"):
		var f = FileAccess.open("res://assets/vfx/turret_fx/manifest.json", FileAccess.READ)
		_manifest = JSON.parse_string(f.get_as_text())

func play(fx_kind: String, from: Vector3, to: Vector3) -> void:
	var entry: Dictionary = _manifest.get(fx_kind, _manifest.get("rail", {}))
	if entry.is_empty():
		entry = {"tex_near": "res://assets/vfx/turret_fx/rail/hybridblastfx_01a.png"}
	var dist = from.distance_to(to)
	var tex_path = str(entry.get("tex_far" if dist > 8.0 else "tex_near", entry.get("tex_shared", "")))
	var tex = _tex(tex_path)
	# Core beam strip (always)
	var beam = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.08, 0.08, maxf(dist, 0.5))
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
	var mid = from.lerp(to, 0.5)
	mid.y += 0.35
	add_child(beam)
	beam.top_level = true
	beam.global_position = mid
	if from.distance_squared_to(to) > 0.0001:
		beam.look_at(to + Vector3(0, 0.35, 0), Vector3.UP)
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
