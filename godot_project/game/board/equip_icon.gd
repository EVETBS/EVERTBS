extends RefCounted

static var _clear: Texture2D


static func load_path(path: String) -> Texture2D:
	var p := path.strip_edges()
	if p == "":
		return null
	if ResourceLoader.exists(p):
		var loaded := load(p) as Texture2D
		if loaded != null:
			return loaded
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img != null:
			return ImageTexture.create_from_image(img)
	return null


static func clear_tex() -> Texture2D:
	if _clear == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_clear = ImageTexture.create_from_image(img)
	return _clear


static func for_row(eq: Dictionary) -> Texture2D:
	var tex := load_path(str(eq.get("icon", "")))
	if tex == null:
		var eid := str(eq.get("id", "")).strip_edges()
		if eid != "":
			tex = load_path("res://assets/ui/equipment/%s.png" % eid)
	return tex if tex != null else clear_tex()
