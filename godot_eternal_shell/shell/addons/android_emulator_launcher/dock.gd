@tool
extends VBoxContainer

const SETTINGS_PATH := "user://android_emulator_launcher.cfg"
const APK_OUTPUT := "res://build/android/game.apk"

var _sdk_input: LineEdit
var _preset_input: LineEdit
var _package_input: LineEdit
var _avd_option: OptionButton
var _start_button: Button
var _build_button: Button
var _stop_button: Button
var _log: RichTextLabel
var _emulator_pid: int = -1


func _init() -> void:
	name = "Android Emu"
	custom_minimum_size = Vector2(220, 0)
	_build_ui()


func _ready() -> void:
	_load_settings()
	if _sdk_input.text.is_empty():
		_sdk_input.text = _detect_sdk()
	_refresh_avds()
	_start_adb_server()
	_log_info("Ready. SDK: %s" % (_sdk_input.text if not _sdk_input.text.is_empty() else "(not set)"))


# ---------- UI ----------

func _build_ui() -> void:
	var header := Label.new()
	header.text = "Android Emulator Launcher"
	header.add_theme_font_size_override("font_size", 14)
	add_child(header)

	add_child(_section_label("Android SDK path"))
	var sdk_row := HBoxContainer.new()
	add_child(sdk_row)
	_sdk_input = LineEdit.new()
	_sdk_input.placeholder_text = "ANDROID_HOME"
	_sdk_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sdk_input.text_changed.connect(_on_sdk_changed)
	sdk_row.add_child(_sdk_input)
	var browse_btn := Button.new()
	browse_btn.text = "..."
	browse_btn.pressed.connect(_on_browse_sdk)
	sdk_row.add_child(browse_btn)

	add_child(_section_label("Export preset name"))
	_preset_input = LineEdit.new()
	_preset_input.text = "Android"
	_preset_input.text_changed.connect(func(_t): _save_settings())
	add_child(_preset_input)

	add_child(_section_label("Package name (auto if empty)"))
	_package_input = LineEdit.new()
	_package_input.placeholder_text = "com.example.game"
	_package_input.text_changed.connect(func(_t): _save_settings())
	add_child(_package_input)

	add_child(_section_label("AVD"))
	var avd_row := HBoxContainer.new()
	add_child(avd_row)
	_avd_option = OptionButton.new()
	_avd_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avd_row.add_child(_avd_option)
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_avds)
	avd_row.add_child(refresh_btn)

	add_child(HSeparator.new())

	_start_button = Button.new()
	_start_button.text = "Start emulator"
	_start_button.pressed.connect(_on_start_emulator)
	add_child(_start_button)

	_build_button = Button.new()
	_build_button.text = "Build && Run"
	_build_button.pressed.connect(_on_build_and_run)
	add_child(_build_button)

	_stop_button = Button.new()
	_stop_button.text = "Stop app"
	_stop_button.pressed.connect(_on_stop_app)
	add_child(_stop_button)

	add_child(HSeparator.new())

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 180)
	add_child(_log)

	var clear_btn := Button.new()
	clear_btn.text = "Clear log"
	clear_btn.pressed.connect(func(): _log.clear())
	add_child(clear_btn)


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	return l


# ---------- Settings ----------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_sdk_input.text = cfg.get_value("paths", "sdk", "")
	_preset_input.text = cfg.get_value("export", "preset", "Android")
	_package_input.text = cfg.get_value("export", "package", "")


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("paths", "sdk", _sdk_input.text)
	cfg.set_value("export", "preset", _preset_input.text)
	cfg.set_value("export", "package", _package_input.text)
	cfg.save(SETTINGS_PATH)


func _on_sdk_changed(_t: String) -> void:
	_save_settings()


func _on_browse_sdk() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.dir_selected.connect(func(d):
		_sdk_input.text = d
		_save_settings()
		_refresh_avds()
	)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered_ratio(0.6)


# ---------- SDK / tooling ----------

func _detect_sdk() -> String:
	for env_var in ["ANDROID_HOME", "ANDROID_SDK_ROOT"]:
		var v := OS.get_environment(env_var)
		if not v.is_empty() and DirAccess.dir_exists_absolute(v):
			return v
	var candidates := [
		OS.get_environment("LOCALAPPDATA").path_join("Android/Sdk"),
		OS.get_environment("USERPROFILE").path_join("AppData/Local/Android/Sdk"),
		OS.get_environment("HOME").path_join("Library/Android/sdk"),
		OS.get_environment("HOME").path_join("Android/Sdk"),
	]
	for c in candidates:
		if not c.is_empty() and DirAccess.dir_exists_absolute(c):
			return c
	return ""


func _adb_path() -> String:
	return _tool_path("platform-tools", "adb")


func _emulator_path() -> String:
	return _tool_path("emulator", "emulator")


func _tool_path(subdir: String, exe: String) -> String:
	var sdk := _sdk_input.text.strip_edges()
	if sdk.is_empty():
		return ""
	var ext := ".exe" if OS.get_name() == "Windows" else ""
	return sdk.path_join(subdir).path_join(exe + ext)


func _ensure_tool(path: String, label: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		_log_error("%s not found at %s — set the SDK path." % [label, path])
		return false
	return true


# ---------- AVDs ----------

func _refresh_avds() -> void:
	_avd_option.clear()
	var emu := _emulator_path()
	if not _ensure_tool(emu, "emulator"):
		_avd_option.add_item("(no SDK)")
		return
	var output: Array = []
	var code := OS.execute(emu, ["-list-avds"], output, true)
	if code != 0:
		_log_error("emulator -list-avds failed (exit %d)" % code)
		_avd_option.add_item("(error)")
		return
	var raw: String = "" if output.is_empty() else String(output[0])
	var found := 0
	for line in raw.split("\n"):
		var name := line.strip_edges()
		if name.is_empty() or name.begins_with("INFO") or name.begins_with("WARN"):
			continue
		_avd_option.add_item(name)
		found += 1
	if found == 0:
		_avd_option.add_item("(no AVDs — create one in Android Studio)")
	else:
		_log_info("Found %d AVD(s)." % found)


# ---------- Emulator ----------

func _on_start_emulator() -> void:
	var emu := _emulator_path()
	if not _ensure_tool(emu, "emulator"):
		return
	var avd := _avd_option.get_item_text(_avd_option.selected)
	if avd.is_empty() or avd.begins_with("("):
		_log_error("Select a valid AVD first.")
		return
	if _is_any_emulator_online():
		_log_info("An emulator is already online — skipping start.")
		return
	_log_info("Starting emulator: %s" % avd)
	_emulator_pid = OS.create_process(emu, ["-avd", avd, "-netdelay", "none", "-netspeed", "full"])
	if _emulator_pid <= 0:
		_log_error("Failed to spawn emulator process.")
		return
	_log_info("Emulator PID %d. Waiting for boot..." % _emulator_pid)
	_wait_for_boot_async()


func _wait_for_boot_async() -> void:
	# Poll boot state without blocking the editor.
	var max_seconds := 180
	var elapsed := 0
	while elapsed < max_seconds:
		await get_tree().create_timer(2.0).timeout
		elapsed += 2
		if _is_device_booted():
			_log_success("Emulator booted.")
			return
	_log_error("Timed out waiting for emulator boot.")


func _start_adb_server() -> void:
	var adb := _adb_path()
	if adb.is_empty() or not FileAccess.file_exists(adb):
		return
	var output: Array = []
	OS.execute(adb, ["start-server"], output, true)


func _device_state() -> String:
	# "device" = ready, "offline" = handshaking, "unauthorized" = needs accept,
	# "" = no device.
	var adb := _adb_path()
	if adb.is_empty():
		return ""
	var output: Array = []
	OS.execute(adb, ["devices"], output, true)
	var raw: String = "" if output.is_empty() else String(output[0])
	for line in raw.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("List of devices"):
			continue
		var parts := trimmed.split("\t")
		if parts.size() >= 2:
			return parts[1].strip_edges()
	return ""


func _wait_for_device_ready_async(timeout_sec: int = 90) -> bool:
	_start_adb_server()
	var elapsed := 0
	var last_state := ""
	while elapsed < timeout_sec:
		var state := _device_state()
		if state != last_state:
			_log_info("Device state: %s" % (state if not state.is_empty() else "(none)"))
			last_state = state
		if state == "device" and _is_device_booted():
			return true
		await get_tree().create_timer(1.5).timeout
		elapsed += 2
	return false


func _is_any_emulator_online() -> bool:
	var adb := _adb_path()
	if adb.is_empty():
		return false
	var output: Array = []
	OS.execute(adb, ["devices"], output, true)
	var raw: String = "" if output.is_empty() else String(output[0])
	for line in raw.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("List of devices"):
			continue
		var parts := trimmed.split("\t")
		if parts.size() >= 2 and parts[1].strip_edges() == "device":
			return true
	return false


func _device_abis() -> String:
	# Returns the device's supported ABI list, e.g. "x86_64,arm64-v8a".
	var adb := _adb_path()
	if adb.is_empty():
		return ""
	var output: Array = []
	var code := OS.execute(adb, ["shell", "getprop", "ro.product.cpu.abilist"], output, true)
	if code != 0:
		return ""
	return ("" if output.is_empty() else String(output[0])).strip_edges()


func _is_device_booted() -> bool:
	var adb := _adb_path()
	if adb.is_empty():
		return false
	var output: Array = []
	var code := OS.execute(adb, ["shell", "getprop", "sys.boot_completed"], output, true)
	if code != 0:
		return false
	var raw: String = "" if output.is_empty() else String(output[0])
	return raw.strip_edges() == "1"


# ---------- Build & run ----------

func _on_build_and_run() -> void:
	var adb := _adb_path()
	if not _ensure_tool(adb, "adb"):
		return
	if not _is_any_emulator_online():
		_log_error("No emulator online. Start one first.")
		return

	var preset := _preset_input.text.strip_edges()
	if preset.is_empty():
		_log_error("Set the export preset name (default: Android).")
		return
	_run_build_and_install(adb, preset)


func _run_build_and_install(adb: String, preset: String) -> void:
	# Resolve absolute APK path.
	var apk_abs := ProjectSettings.globalize_path(APK_OUTPUT)
	DirAccess.make_dir_recursive_absolute(apk_abs.get_base_dir())

	_log_info("Exporting APK using preset '%s'..." % preset)
	var godot_exe := OS.get_executable_path()
	var project_dir := ProjectSettings.globalize_path("res://")
	var args := [
		"--headless",
		"--path", project_dir,
		"--export-debug", preset, apk_abs,
	]
	var output: Array = []
	var code := OS.execute(godot_exe, args, output, true)
	if code != 0:
		_log_error("Export failed (exit %d). Output:\n%s" % [code, _join_output(output)])
		return
	if not FileAccess.file_exists(apk_abs):
		_log_error("Export reported success but APK missing at %s" % apk_abs)
		return
	_log_success("APK built: %s" % apk_abs)

	# Headless export starts/restarts its own adb server, which can knock the
	# emulator into "offline" briefly. Wait for it to come back to "device".
	_log_info("Waiting for device to be ready...")
	if not await _wait_for_device_ready_async(90):
		_log_error("Device did not reach 'device' state in time. Run `adb devices` to inspect.")
		return

	var abis := _device_abis()
	if not abis.is_empty():
		_log_info("Device ABIs: %s" % abis)

	# Install (-r reinstall, -t allow test packages, -d allow downgrade).
	_log_info("Installing APK on emulator...")
	output.clear()
	code = OS.execute(adb, ["install", "-r", "-t", "-d", apk_abs], output, true)
	if code != 0:
		var out_text := _join_output(output)
		_log_error("adb install failed (exit %d). Output:\n%s" % [code, out_text])
		if "INSTALL_FAILED_NO_MATCHING_ABIS" in out_text:
			_log_error("ABI mismatch — APK has no native libs for this device (%s)." % abis)
			_log_error("Fix: Project → Export → Android preset → enable matching architecture (e.g. x86_64) and re-run.")
		return
	_log_success("Installed.")

	# Launch.
	var package := _package_input.text.strip_edges()
	if package.is_empty():
		package = _resolve_package_from_preset(preset)
	if package.is_empty():
		_log_error("Couldn't determine package name. Fill it in or set 'package/unique_name' in your export preset.")
		return
	_log_info("Launching %s..." % package)
	output.clear()
	code = OS.execute(adb, [
		"shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1",
	], output, true)
	if code != 0:
		_log_error("Launch failed (exit %d). Output:\n%s" % [code, _join_output(output)])
		return
	_log_success("Launched %s on emulator." % package)


func _resolve_package_from_preset(preset_name: String) -> String:
	var path := "res://export_presets.cfg"
	if not FileAccess.file_exists(path):
		return ""
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	for section in cfg.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		if cfg.get_value(section, "name", "") == preset_name:
			var opts_section := section + ".options"
			var raw: String = cfg.get_value(opts_section, "package/unique_name", "")
			return _substitute_genname(raw)
	return ""


func _substitute_genname(pkg: String) -> String:
	# Godot substitutes $genname at export time using a sanitized lowercase
	# project name. We replicate that here so we can match the installed APK.
	if not "$genname" in pkg:
		return pkg
	var basename: String = ProjectSettings.get_setting("application/config/name", "")
	basename = basename.to_lower()
	var name := ""
	var first := true
	for i in basename.length():
		var c := basename.unicode_at(i)
		if c >= 0x30 and c <= 0x39 and first:
			name += "_"
		if (c >= 0x30 and c <= 0x39) or (c >= 0x61 and c <= 0x7a):
			name += String.chr(c)
			first = false
		elif c == 0x2d or c == 0x2e or c == 0x5f or c == 0x20:
			name += "_"
			first = false
	if name.is_empty():
		name = "noname"
	return pkg.replace("$genname", name)


# ---------- Stop ----------

func _on_stop_app() -> void:
	var adb := _adb_path()
	if not _ensure_tool(adb, "adb"):
		return
	var package := _package_input.text.strip_edges()
	if package.is_empty():
		package = _resolve_package_from_preset(_preset_input.text.strip_edges())
	if package.is_empty():
		_log_error("Set a package name to stop.")
		return
	var output: Array = []
	OS.execute(adb, ["shell", "am", "force-stop", package], output, true)
	_log_info("Stopped %s." % package)


# ---------- Logging ----------

func _join_output(output: Array) -> String:
	var parts: PackedStringArray = []
	for piece in output:
		parts.append(String(piece))
	return "\n".join(parts)


func _log_info(msg: String) -> void:
	_log.append_text("[color=#9ec5ff]%s[/color]\n" % msg)
	print("[AndroidEmu] ", msg)


func _log_success(msg: String) -> void:
	_log.append_text("[color=#9aef9a]%s[/color]\n" % msg)
	print("[AndroidEmu] ", msg)


func _log_error(msg: String) -> void:
	_log.append_text("[color=#ff9a9a]%s[/color]\n" % msg)
	push_warning("[AndroidEmu] %s" % msg)
