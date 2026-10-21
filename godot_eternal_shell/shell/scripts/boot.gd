extends Control

const APP_TITLE: String = "EVE模拟器：军团"

@onready var _title: Label = $Center/VBox/Title
@onready var _status: Label = $Center/VBox/Status
@onready var _bar: ProgressBar = $Center/VBox/Progress
@onready var _retry: Button = $Center/VBox/Buttons/Retry
@onready var _offline: Button = $Center/VBox/Buttons/Offline
@onready var _update: Button = $Center/VBox/Buttons/Update
@onready var _skip: Button = $Center/VBox/Buttons/Skip
@onready var _http: HTTPRequest = $HTTPRequest

var _bootstrap: UpdateBootstrap
var _client: UpdateClient
var _busy: bool = false
var _entering: bool = false
## True only after user picks「核实版本是否最新」(or options → same).
var _verify_mode: bool = false
var _choice_pending: bool = true


func _ready() -> void:
	_retry.pressed.connect(_on_retry)
	_offline.pressed.connect(_on_use_local)
	_update.pressed.connect(_on_update_confirm)
	_skip.pressed.connect(_on_skip_confirm)
	_apply_choice_button_styles()
	_offline.text = "直接进入游戏"
	_offline.tooltip_text = "离线/打断：用本机已应用内容进游戏（不覆盖较新热更）"
	_retry.text = "核实版本是否最新"
	_retry.tooltip_text = "主动检查指针仓/HF 是否有新内容"
	_title.text = APP_TITLE
	_update.visible = false
	_skip.visible = false
	_verify_mode = false
	## Cold start: finish verify → apply → enter (RELEASE_AND_HOTUPDATE 202608.8.26+).
	## 「直接进入」remains interrupt/offline fallback (Seed must not downgrade).
	if GameSession != null and GameSession.pending_content_verify:
		GameSession.pending_content_verify = false
	_set_choice_visible(false)
	_verify_mode = true
	_offline.visible = true
	_retry.visible = true
	_run_remote_verify()


func _apply_choice_button_styles() -> void:
	## 底部高亮条，强调二选一可点。
	_style_bottom_highlight(_offline, Color(0.35, 0.85, 0.55, 1.0))
	_style_bottom_highlight(_retry, Color(0.35, 0.7, 1.0, 1.0))


func _style_bottom_highlight(btn: Button, accent: Color) -> void:
	btn.custom_minimum_size = Vector2(200, 48)
	var normal: StyleBoxFlat = _make_btn_style(Color(0.14, 0.18, 0.26, 1.0), accent, 4)
	var hover: StyleBoxFlat = _make_btn_style(Color(0.2, 0.26, 0.36, 1.0), accent.lightened(0.15), 5)
	var pressed: StyleBoxFlat = _make_btn_style(Color(0.1, 0.14, 0.2, 1.0), accent.darkened(0.1), 3)
	var disabled: StyleBoxFlat = _make_btn_style(Color(0.1, 0.1, 0.12, 1.0), Color(0.3, 0.3, 0.35, 1.0), 2)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.9, 1.0, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.52, 0.55, 1.0))


func _make_btn_style(bg: Color, bottom: Color, bottom_w: int) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(0)
	s.border_width_bottom = bottom_w
	s.border_color = bottom
	s.content_margin_left = 18.0
	s.content_margin_right = 18.0
	s.content_margin_top = 10.0
	s.content_margin_bottom = 12.0
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 2
	s.corner_radius_bottom_right = 2
	return s


func _set_choice_visible(choice_on: bool) -> void:
	## 勿命名 show：会与 CanvasItem.show 冲突（warning→error）。
	_choice_pending = choice_on
	_offline.visible = true
	_retry.visible = true
	if choice_on:
		_busy = false
		_entering = false
		_verify_mode = false
		_offline.disabled = false
		_retry.disabled = false
		_hide_confirm()
		_set_ui("请选择进入方式（须点选其一）", 0.0)
		_bar.visible = false
	else:
		_bar.visible = true


func _on_retry() -> void:
	## 「核实版本是否最新」
	if _entering:
		return
	if _busy and _verify_mode:
		return
	_detach_bootstrap()
	_choice_pending = false
	_bar.visible = true
	_verify_mode = true
	_offline.disabled = false
	_retry.disabled = true
	_run_remote_verify()


func _detach_bootstrap() -> void:
	if _bootstrap == null:
		return
	if _bootstrap.finished.is_connected(_on_finished):
		_bootstrap.finished.disconnect(_on_finished)
	if _bootstrap.status.is_connected(_on_status):
		_bootstrap.status.disconnect(_on_status)
	if _bootstrap.confirm_requested.is_connected(_on_confirm_requested):
		_bootstrap.confirm_requested.disconnect(_on_confirm_requested)
	_bootstrap.abort()
	_http.cancel_request()
	_bootstrap = null
	_client = null
	_hide_confirm()


func _on_update_confirm() -> void:
	if _bootstrap:
		_bootstrap.respond_confirm(true)
	_update.visible = false
	_skip.visible = false
	_retry.disabled = true
	_busy = true
	_refresh_interrupt_local()


func _on_skip_confirm() -> void:
	if _bootstrap:
		_bootstrap.respond_confirm(false)
	_update.visible = false
	_skip.visible = false


func _on_use_local() -> void:
	## 选择页：进本地；验版中：打断远端进本地。
	if _entering:
		return
	if _choice_pending:
		_choice_pending = false
		_bar.visible = true
		_retry.disabled = true
		_offline.disabled = true
		_run_local_boot()
		return
	if not UpdateClient.new(self, _http).has_local_content_ready():
		_fail("没有本地内容包")
		return
	_entering = true
	_busy = true
	_detach_bootstrap()
	_retry.disabled = true
	_offline.disabled = true
	_hide_confirm()
	_set_ui("正在加载本地内容…", 0.5)
	var mount: Dictionary = _mount_local_packs()
	if not TypedVariant.as_bool(mount.get("ok", false), false):
		_entering = false
		_fail(str(mount.get("error", "没有本地内容包")))
		return
	_enter_game(str(mount["entry"]))


func _mount_local_packs() -> Dictionary:
	UpdateConfig.ensure_dirs()
	var entry: String = UpdateConfig.DEFAULT_ENTRY
	var listed: Array[String] = []
	var applied: String = UpdateConfig.applied_version_path()
	if FileAccess.file_exists(applied):
		var f: FileAccess = FileAccess.open(applied, FileAccess.READ)
		if f:
			var data: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(data) == TYPE_DICTIONARY:
				var d: Dictionary = TypedVariant.as_dict(data)
				if d.has("entry"):
					entry = str(d["entry"])
				var packs_v: Variant = d.get("packs", [])
				if packs_v is Array:
					for item: Variant in packs_v as Array:
						var rel: String = ""
						if typeof(item) == TYPE_DICTIONARY:
							rel = str(item.get("path", "")).replace("\\", "/").strip_edges()
						else:
							rel = str(item).replace("\\", "/").strip_edges()
						if rel.is_empty():
							continue
						if not rel.begins_with("packs/"):
							rel = "packs/%s" % rel.get_file()
						listed.append(rel)
	var packs_dir: String = UpdateConfig.CONTENT_RUNTIME_DIR.path_join("packs")
	## Prefer applied_version.packs[] so orphan legacy pck (models.pck) is never mounted.
	if not listed.is_empty():
		var any_ok: bool = false
		for rel2: String in listed:
			var full2: String = UpdateConfig.runtime_file_path(rel2)
			if not FileAccess.file_exists(full2):
				return {"ok": false, "error": "缺少内容包 %s" % rel2.get_file()}
			var abs2: String = ProjectSettings.globalize_path(full2)
			if not ProjectSettings.load_resource_pack(abs2, true):
				if not ProjectSettings.load_resource_pack(full2, true):
					return {"ok": false, "error": "挂载失败 %s" % rel2.get_file()}
			any_ok = true
		if not any_ok:
			return {"ok": false, "error": "没有本地内容包"}
		return {"ok": true, "entry": entry}
	var dir: DirAccess = DirAccess.open(packs_dir)
	if dir == null:
		return {"ok": false, "error": "没有本地内容包"}
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	var any_pack: bool = false
	while fn != "":
		if not dir.current_is_dir() and (fn.ends_with(".pck") or fn.ends_with(".zip")):
			any_pack = true
			var full: String = packs_dir.path_join(fn)
			var abs_path: String = ProjectSettings.globalize_path(full)
			if not ProjectSettings.load_resource_pack(abs_path, true):
				if not ProjectSettings.load_resource_pack(full, true):
					dir.list_dir_end()
					return {"ok": false, "error": "挂载失败 %s" % fn}
		fn = dir.get_next()
	dir.list_dir_end()
	if not any_pack:
		return {"ok": false, "error": "没有本地内容包"}
	return {"ok": true, "entry": entry}


func _run_local_boot() -> void:
	_busy = true
	_entering = false
	_verify_mode = false
	_hide_confirm()
	_set_ui("正在准备本地内容…", 0.02)
	_http.cancel_request()
	print("[Boot] local boot: seeding bundled content…")
	var seed_res: Dictionary = await BundledContentSeed.ensure_async(
		self,
		func(msg: String, frac: float) -> void:
			_set_ui(msg, frac)
	)
	print("[Boot] boot.seed ok=%s seeded=%s reason=%s" % [
		seed_res.get("ok", false), seed_res.get("seeded", false), seed_res.get("reason", "")
	])
	if not TypedVariant.as_bool(seed_res.get("ok", false), false):
		_fail("内置内容解压失败: %s" % seed_res.get("reason", ""))
		return
	if TypedVariant.as_bool(seed_res.get("seeded", false), false):
		_set_ui("内置内容已就绪", 0.2)
	if not UpdateClient.new(self, _http).has_local_content_ready():
		_fail("没有本地内容包。请改选「核实版本是否最新」从网络拉取。")
		return
	_set_ui("正在加载本地内容…", 0.5)
	var mount: Dictionary = _mount_local_packs()
	if not TypedVariant.as_bool(mount.get("ok", false), false):
		_fail(str(mount.get("error", "没有本地内容包")))
		return
	_enter_game(str(mount["entry"]))


func _run_remote_verify() -> void:
	_busy = true
	_entering = false
	_verify_mode = true
	_choice_pending = false
	_retry.disabled = true
	_hide_confirm()
	_set_ui("正在核实版本是否最新…", 0.0)
	_http.cancel_request()
	_client = UpdateClient.new(self, _http)
	_client.abort_requested = false
	_bootstrap = UpdateBootstrap.new(_client)
	_bootstrap.status.connect(_on_status)
	_bootstrap.finished.connect(_on_finished)
	_bootstrap.confirm_requested.connect(_on_confirm_requested)
	_refresh_interrupt_local()
	await _bootstrap.run()


func _on_confirm_requested(
	remote_version: String,
	local_version: String,
	notes: String,
	download_bytes: int,
	file_count: int
) -> void:
	_busy = false
	_retry.disabled = false
	_title.text = "发现内容更新"
	var local_txt: String = local_version if not local_version.is_empty() else "(无)"
	var msg: String = "远端 %s\n本地 %s" % [remote_version, local_txt]
	if not notes.is_empty():
		msg += "\n%s" % notes
	msg += "\n\n待下载：%d 个文件 · 约 %s" % [file_count, UpdateClient.format_bytes(download_bytes)]
	msg += "\n请确认是否更新。"
	_status.text = msg
	_bar.value = 20.0
	_update.visible = true
	_skip.visible = true
	_skip.disabled = not UpdateClient.new(self, _http).has_local_content_ready()
	if _skip.disabled:
		_skip.tooltip_text = "无本地内容，无法跳过"
	else:
		_skip.tooltip_text = "使用当前已安装内容进入游戏"
	_refresh_interrupt_local()


func _hide_confirm() -> void:
	_update.visible = false
	_skip.visible = false


func _refresh_interrupt_local() -> void:
	## 验版/下载中：本地按钮作打断；选择页不走这里。
	if _entering or _choice_pending:
		return
	_offline.visible = true
	var local_ready: bool = UpdateClient.new(self, _http).has_local_content_ready()
	_offline.disabled = not local_ready
	if local_ready:
		_offline.tooltip_text = "打断远端验版/下载，直接进入游戏"
	else:
		_offline.tooltip_text = "尚无本地内容，无法打断"


func _on_status(message: String, fraction: float) -> void:
	_set_ui(message, fraction)
	_refresh_interrupt_local()


func _on_finished(ok: bool, entry: String, message: String) -> void:
	if _entering:
		return
	if message == "aborted":
		return
	_busy = false
	_retry.disabled = false
	_hide_confirm()
	if ok:
		_set_ui(message, 1.0)
		_enter_game(entry)
		return
	_fail(message)


func _fail(message: String) -> void:
	_busy = false
	_entering = false
	_hide_confirm()
	_bar.value = 0.0
	_bar.visible = true
	_title.text = "无法进入"
	## 失败后回到二选一。
	_set_choice_visible(true)
	_status.text = message


func _set_ui(message: String, fraction: float) -> void:
	_title.text = APP_TITLE
	_status.text = message
	_bar.value = clampf(fraction, 0.0, 1.0) * 100.0


func _enter_game(entry: String) -> void:
	_entering = true
	_offline.visible = false
	_retry.visible = false
	if DataStore:
		DataStore.reload_all()
		## UI「内容」版 = applied_version（HF/内置 seed）；禁止停在默认 "local"。
		var applied: String = UpdateClient.new(self, _http).read_applied_version().strip_edges()
		DataStore.content_version = applied if not applied.is_empty() else "local"
	if AdminBus:
		AdminBus.reload_policies()
	if GameSession:
		GameSession.shell_version = str(ProjectSettings.get_setting("application/config/version", "shell"))
		GameSession._apply_platform_render_profile()
	print("[Boot] boot.apply content=%s entry=%s exists=%s" % [
		DataStore.content_version if DataStore else "?", entry, ResourceLoader.exists(entry)
	])
	if not ResourceLoader.exists(entry):
		_fail("入口不存在 %s（内容包未正确挂载）" % entry)
		return
	## 不在此做 SceneState 脚本探针：Variant→Script 强转在 Android debug 下 warning→error。
	## 入口无效时 change_scene 会失败并走 _fail。
	var err: Error = get_tree().change_scene_to_file(entry)
	if err != OK:
		_fail("无法加载入口 %s（错误 %s）" % [entry, err])
