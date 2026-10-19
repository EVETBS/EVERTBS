extends Node3D
class_name BoardShipMassDraw
## GPU-instanced impostor quads for far battlefield hulls.

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, specular_disabled;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform int yaw_n = 24;
void fragment() {
	float n = max(float(yaw_n), 1.0);
	float cell = 1.0 / n;
	float yi = floor(INSTANCE_CUSTOM.r + 0.5);
	vec2 uv = vec2(UV.x * cell + cell * yi, UV.y);
	vec4 c = texture(atlas, uv);
	if (c.a < 0.08) { discard; }
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""

var baker: Node
var _mm: Dictionary = {}
var _ids: Dictionary = {}

func setup(b: Node) -> void:
	baker = b

func sync(cam: Camera3D, units: Array, near_ids: Dictionary, battle: bool) -> void:
	_ids.clear()
	if not battle or cam == null or baker == null:
		_hide_all()
		return
	for u in units:
		if typeof(u) != TYPE_DICTIONARY or not bool(u.get("alive", false)):
			continue
		var uid := str(u.get("id", ""))
		if near_ids.has(uid) or bool(u.get("npc_hull", false)):
			continue
		var pos: Vector3 = u.get("pos", Vector3.ZERO)
		if cam.is_position_behind(pos):
			continue
		if not cam.is_position_in_frustum(pos):
			continue
		var key := str(u.get("model_key", u.get("ship_id", "")))
		if key == "" or not bool(baker.call("has_full", key)):
			baker.call("enqueue", key)
			continue
		if not _ids.has(key):
			_ids[key] = []
		(_ids[key] as Array).append(u)
		baker.call("enqueue", key)
	for k in _mm.keys():
		if not _ids.has(k):
			(_mm[k] as MultiMeshInstance3D).visible = false
	for key2 in _ids.keys():
		_fill_key(str(key2), cam)

func _hide_all() -> void:
	for k in _mm.keys():
		(_mm[k] as MultiMeshInstance3D).visible = false

func _fill_key(key: String, cam: Camera3D) -> void:
	var mmi := _ensure(key)
	if mmi == null:
		return
	var arr: Array = _ids[key]
	var mm: MultiMesh = mmi.multimesh
	mm.instance_count = arr.size()
	mmi.visible = arr.size() > 0
	var yaw_n := 24
	var e: Variant = baker.get("manifest")
	if typeof(e) == TYPE_DICTIONARY:
		var ent: Variant = (e as Dictionary).get(key, {})
		if typeof(ent) == TYPE_DICTIONARY:
			yaw_n = maxi(1, int((ent as Dictionary).get("yaw_n", 24)))
	var sz := 5.5
	for i in arr.size():
		var u: Dictionary = arr[i]
		var pos: Vector3 = u.get("pos", Vector3.ZERO)
		var face: Vector3 = u.get("face_dir", Vector3(0, 0, -1))
		face.y = 0.0
		if face.length_squared() < 0.0001:
			face = Vector3(0, 0, -1)
		var to_cam := cam.global_position - pos
		to_cam.y = 0.0
		var cam_yaw := atan2(to_cam.x, to_cam.z)
		var ship_yaw := atan2(face.x, face.z)
		var rel := wrapf(ship_yaw - cam_yaw, 0.0, TAU)
		var yi := int(floor(rel / TAU * float(yaw_n) + 0.5)) % yaw_n
		var z := cam.global_position - pos
		if z.length_squared() < 0.0001:
			z = Vector3(0, 0, 1)
		z = z.normalized()
		var x := Vector3.UP.cross(z)
		if x.length_squared() < 0.0001:
			x = Vector3.RIGHT
		x = x.normalized()
		var y := z.cross(x)
		var xf := Transform3D(Basis(x, y, z).scaled(Vector3(sz, sz, sz)), pos + Vector3(0, 0.4, 0))
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, Color(float(yi), 0, 0, 0))
	var mat := mmi.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("yaw_n", yaw_n)

func _ensure(key: String) -> MultiMeshInstance3D:
	if _mm.has(key):
		return _mm[key]
	var path: String = str(baker.call("tex_path", key))
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("atlas", tex)
	mat.set_shader_parameter("yaw_n", 24)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	(mm.mesh as QuadMesh).size = Vector2(1, 1)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_mm[key] = mmi
	return mmi

