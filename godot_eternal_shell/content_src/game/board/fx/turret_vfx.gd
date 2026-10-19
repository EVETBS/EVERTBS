extends Node3D
class_name BoardTurretVfx

## EveAC-inspired short beam / muzzle flash between world points.

const DEFAULT_THICK := 0.08
## Sender tip lights immediately; receiver tip lights this much later (TACTICAL_TOPDOWN).
const TIP_DELAY_S := 0.1

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
	thick_wu: float = 0.0,
	width_mul: float = 1.0
) -> void:
	## thick_wu: tactical beam cross-section width in world units (icon circum-radius).
	## width_mul: battlefield view and menu backdrop pass 0.5; tactical stays 1.
	var entry: Dictionary = _manifest.get(fx_kind, _manifest.get("rail", {}))
	if entry.is_empty():
		entry = {"tex_near": "res://assets/vfx/turret_fx/rail/hybridblastfx_01a.png"}
	var dist = from.distance_to(to)
	var tex_path = str(entry.get("tex_far" if dist > 8.0 else "tex_near", entry.get("tex_shared", "")))
	var tex = _tex(tex_path)
	var thick := DEFAULT_THICK
	if thick_wu > 0.0:
		thick = thick_wu
	var drawn := thick * maxf(width_mul, 0.05)
	var start := from + Vector3(0, 0.35, 0)
	var aim := to + Vector3(0, 0.35, 0)
	var beam_len := maxf(start.distance_to(aim), 0.5)
	# Grow from the sender tip. scale.z = 1 reaches the receiver tip.
	var host := Node3D.new()
	add_child(host)
	host.top_level = true
	host.global_position = start
	if start.distance_squared_to(aim) > 0.0001:
		## Top-down: avoid look_at colinear with UP (beam vanishes).
		var dir: Vector3 = aim - start
		var up: Vector3 = Vector3.UP
		if absf(dir.normalized().dot(up)) > 0.92:
			up = Vector3.FORWARD
		host.look_at(aim, up)
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(drawn, drawn, beam_len)
	beam.mesh = box
	## look_at aims -Z at the receiver. Box center sits halfway along -Z.
	beam.position = Vector3(0, 0, -beam_len * 0.5)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(1.0, 0.85, 0.45, 0.75)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.7, 0.2)
	bmat.emission_energy_multiplier = 3.5
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.no_depth_test = true
	beam.material_override = bmat
	host.add_child(beam)
	host.scale = Vector3(1, 1, 0.001)
	var tw := create_tween()
	tw.tween_property(host, "scale:z", 1.0, TIP_DELAY_S)
	tw.tween_property(bmat, "albedo_color:a", 0.0, 0.18)
	tw.parallel().tween_property(bmat, "emission_energy_multiplier", 0.2, 0.18)
	tw.tween_callback(host.queue_free)
	if tex == null:
		return
	_flash_at(start, tex, dist, thick, width_mul, 0.0)
	_flash_at(aim, tex, dist, thick, width_mul, TIP_DELAY_S)

func _flash_at(at: Vector3, tex: Texture2D, dist: float, thick: float, width_mul: float, delay_s: float) -> void:
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.double_sided = true
	spr.transparent = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.pixel_size = 0.0038
	spr.modulate = Color(1, 1, 1, 0.0 if delay_s > 0.0 else 0.85)
	var pos := at
	pos.y += 0.10
	spr.position = pos
	var stretch := clampf(dist * 0.025, 0.7, 1.8)
	var tex_h: int = tex.get_height()
	if thick > DEFAULT_THICK + 0.001 and tex_h > 0:
		var base_h: float = float(tex_h) * spr.pixel_size
		if base_h > 0.0001:
			stretch = maxf(stretch, thick / base_h)
	spr.scale = Vector3(stretch * width_mul, stretch * 0.5 * width_mul, 1.0)
	add_child(spr)
	var tw := create_tween()
	if delay_s > 0.0:
		tw.tween_interval(delay_s)
		tw.tween_property(spr, "modulate:a", 0.85, 0.001)
	tw.tween_property(spr, "modulate:a", 0.0, 0.2)
	tw.tween_callback(spr.queue_free)


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
