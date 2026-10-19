extends RefCounted
class_name UiAssets
## Minimal font/texture helpers for EVE战棋 main menu (no full EveAutochess UiAssets).

const MAIN_BG: String = "res://assets/ui/main_menu/MainMenuBG.png"
const ANNOUNCE_DIR: String = "res://assets/ui/main_menu/Announcements"
const ANNOUNCE_FILES: PackedStringArray = [
	"bug_feedback.png",
	"github_open_source.png",
	"sponsor.png",
	"survey.png",
	"update.png",
]


static func tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func announcement_textures() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for fn: String in ANNOUNCE_FILES:
		var t: Texture2D = tex(ANNOUNCE_DIR.path_join(fn))
		if t != null:
			out.append(t)
	return out


static func apply_label_font(lab: Control, _bold: bool = false, size: int = 16) -> void:
	if lab == null:
		return
	lab.add_theme_font_size_override("font_size", size)


static func apply_button_font(btn: Control, size: int = 16) -> void:
	if btn == null:
		return
	btn.add_theme_font_size_override("font_size", size)

static func race_tips_skybox(_race: String) -> Texture2D:
	return null
