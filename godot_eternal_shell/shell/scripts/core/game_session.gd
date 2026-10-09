extends Node
## Tiny session bridge for menu → match mode.
## Shell Autoload (PCK cannot replace Autoload class). Keep in sync with eveautochess-dev.
## Settings authority moved to content PlayerSettings (user://player_settings.cfg).

var pending_mode: String = "versus"
## Nullsec lobby → match handoff (assignments / seats / match_seed).
var pending_nullsec: Dictionary = {}
var shell_version: String = "1.0.0-shell"
var resume_save: bool = false
## Empty → last_match.json; otherwise named slot path / id via MatchSave.
var resume_slot_id: String = ""
## One-shot payload from 读取存档 (e.g. 旗舰测试 inject). Prefer over re-reading disk.
## Cleared after match applies it. Never used by「继续上次对局」.
var resume_payload: Dictionary = {}
## Options「核实版本是否最新」→ Boot 才走指针仓/HF（默认启动不联网）。
var pending_content_verify: bool = false

const SETTINGS_PATH: String = "user://player_settings.cfg"


func request_verify_content_version() -> void:
	## Shell Boot owns real verify; editor/dev may lack boot.tscn update UI.
	pending_content_verify = true
	var boot: String = "res://scenes/boot.tscn"
	if ResourceLoader.exists(boot):
		var err: Error = get_tree().change_scene_to_file(boot)
		if err != OK:
			push_error("[GameSession] boot scene failed: %s" % err)
			pending_content_verify = false
	else:
		push_warning("[GameSession] no boot.tscn — verify only works in eternal shell")
		pending_content_verify = false


func _ready() -> void:
	_apply_mobile_content_scale()
	_apply_platform_render_profile()
	apply_adaptive_fps()


## Android/iOS: canvas_items stretch leaves 3D on native window size while HUD uses
## design 1920×1080 — LDPlayer shows board scrap top-right while cam.unproject stays centered
## (BUG_REGRESSION §3.1d). Viewport mode renders 2D+3D in one buffer then scales.
func _apply_mobile_content_scale() -> void:
	var mobile: bool = OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"
	if not mobile:
		return
	var win: Window = get_tree().root
	if win == null:
		return
	win.content_scale_size = Vector2i(1920, 1080)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	print("[GameSession] mobile content_scale=viewport 1920x1080 expand")
	## #region agent log
	_agent_debug_log(
		"A",
		"game_session.gd:_apply_mobile_content_scale",
		"mobile_content_scale_applied",
		{
			"scale_mode": win.content_scale_mode,
			"scale_size_x": win.content_scale_size.x,
			"scale_size_y": win.content_scale_size.y,
			"aspect": win.content_scale_aspect,
			"os": OS.get_name(),
		}
	)
	## #endregion


## #region agent log
func _agent_debug_log(hypothesis_id: String, location: String, message: String, data: Dictionary = {}) -> void:
	var payload: Dictionary = {
		"sessionId": "3822fa",
		"runId": "keep-reapply-13.15",
		"hypothesisId": hypothesis_id,
		"location": location,
		"message": message,
		"data": data,
		"timestamp": Time.get_unix_time_from_system() * 1000.0,
	}
	var line: String = JSON.stringify(payload)
	var paths: PackedStringArray = PackedStringArray(["H:/debug-3822fa.log", "user://debug_3822fa.ndjson"])
	for i: int in range(paths.size()):
		var path: String = paths[i]
		var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
			f.close()
## #endregion


## Boot-thin FPS from cfg before content PlayerSettings mounts. Content may re-apply later.
func apply_adaptive_fps() -> void:
	var mobile: bool = OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"
	var floor_fps: int = 30 if mobile else 60
	var refresh: float = DisplayServer.screen_get_refresh_rate()
	if refresh < 1.0:
		refresh = 60.0
	var adaptive: int = int(roundf(refresh * 0.75))
	var fps: int = maxi(floor_fps, adaptive)
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		var saved: int = TypedVariant.as_int(cf.get_value("graphics", "target_fps", fps), fps)
		if saved > 0:
			fps = saved
	Engine.max_fps = fps
	print("[GameSession] boot fps=%d (refresh=%.1f ×0.75, floor=%d)" % [fps, refresh, floor_fps])


func _apply_platform_render_profile() -> void:
	## PC: 1.5 + MSAA4. Mobile: 1.0 / MSAA off. UI_AND_SHELL §3.0.
	var mobile: bool = OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"
	var root: Window = get_tree().root
	if root == null:
		return
	if mobile:
		root.scaling_3d_scale = 1.0
		root.msaa_3d = Viewport.MSAA_DISABLED
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		print("[GameSession] mobile render profile: scaling_3d=1.0 msaa=off")
		return
	var scale: float = 1.5
	var data_store: Node = get_node_or_null(^"/root/DataStore")
	var visual: Dictionary = {}
	if data_store != null and data_store.get("visual") is Dictionary:
		visual = TypedVariant.as_dict(data_store.get("visual"))
	if not visual.is_empty():
		var key: String = "editor_scaling_3d" if OS.has_feature("editor") else "desktop_scaling_3d"
		if visual.has(key):
			scale = TypedVariant.as_float(visual.get(key), scale)
	scale = clampf(scale, 1.0, 4.0)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = scale
	root.msaa_3d = Viewport.MSAA_4X
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	root.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	_ensure_desktop_maximized()
	print("[GameSession] desktop render profile: scaling_3d=%.1f msaa=4x editor=%s" % [
		scale, OS.has_feature("editor")
	])


func _ensure_desktop_maximized() -> void:
	if OS.has_feature("editor"):
		return
	if OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS":
		return
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_MAXIMIZED or mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	print("[GameSession] desktop window maximized")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_EXIT_TREE:
		release_os_side_effects()


func release_os_side_effects() -> void:
	## PROCESS_LIFETIME: no OS pointer capture / GUI drag after quit or focus loss.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var root_vp: Viewport = tree.root
	if root_vp:
		root_vp.gui_release_focus()
		if root_vp.has_method("gui_cancel_drag"):
			root_vp.gui_cancel_drag()
	tree.call_group("match_root", "force_release_pointer_grabs")
