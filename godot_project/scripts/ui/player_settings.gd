extends RefCounted
class_name PlayerSettings
## Shared settings for main menu and in-match pause (user://player_settings.cfg).

const PATH := "user://player_settings.cfg"
const SECTION := "evertbs"
const MEM_15_GIB := 15 * 1024 * 1024 * 1024

static func load_cfg() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(PATH)
	return cf

static func get_bgm() -> float:
	return float(load_cfg().get_value(SECTION, "bgm_vol", 1.0))

static func get_sfx() -> float:
	return float(load_cfg().get_value(SECTION, "sfx_vol", 1.0))

static func get_full_plates() -> bool:
	return bool(load_cfg().get_value(SECTION, "battle_full_plates", false))

static func get_deputy_id() -> String:
	return str(load_cfg().get_value(SECTION, "deputy_id", "yang"))

## Physical RAM (bytes). PC/mobile same rule. Missing → 0.
static func physical_memory_bytes() -> int:
	var info: Dictionary = OS.get_memory_info()
	return int(info.get("physical", 0))

## Auto default when user never toggled: ≥15GiB → dynamic, else static.
static func default_menu_bg_dynamic() -> bool:
	var phys := physical_memory_bytes()
	if phys <= 0:
		return false
	return phys >= MEM_15_GIB

## 1.0 = 8px hold/drag split. Range is default/10 … default×10.
static func get_op_sensitivity() -> float:
	return clampf(float(load_cfg().get_value(SECTION, "op_sensitivity", 1.0)), 0.1, 10.0)

static func set_op_sensitivity(v: float) -> void:
	var cf := load_cfg()
	cf.set_value(SECTION, "op_sensitivity", clampf(v, 0.1, 10.0))
	cf.save(PATH)

## True = live bigmap skirmish; false = static MainMenuBG.
## Persisted only after the player toggles; otherwise follows memory default.
static func get_menu_bg_dynamic() -> bool:
	var cf := load_cfg()
	if cf.has_section_key(SECTION, "menu_bg_dynamic"):
		return bool(cf.get_value(SECTION, "menu_bg_dynamic"))
	return default_menu_bg_dynamic()

static func set_bgm(v: float) -> void:
	var cf := load_cfg()
	cf.set_value(SECTION, "bgm_vol", clampf(v, 0.0, 1.0))
	cf.save(PATH)

static func set_sfx(v: float) -> void:
	var cf := load_cfg()
	cf.set_value(SECTION, "sfx_vol", clampf(v, 0.0, 1.0))
	cf.save(PATH)

static func set_full_plates(on: bool) -> void:
	var cf := load_cfg()
	cf.set_value(SECTION, "battle_full_plates", on)
	cf.save(PATH)

static func set_deputy_id(id: String) -> void:
	var cf := load_cfg()
	cf.set_value(SECTION, "deputy_id", id)
	cf.save(PATH)

static func set_menu_bg_dynamic(on: bool) -> void:
	var cf := load_cfg()
	cf.set_value(SECTION, "menu_bg_dynamic", on)
	cf.save(PATH)