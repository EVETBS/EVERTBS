extends Node
class_name ModManager
## Stub for EVERTBS net compile (online wiring later).

const SYNC_MAX_BYTES: int = 10 * 1024 * 1024 * 1024

static func get_or_null() -> ModManager:
	return null

static func instance() -> Node:
	return null

static func titan_race_keys() -> Array:
	return []

static func is_titan_player_race(race: String) -> bool:
	return false

static func titan_pick_list() -> Array:
	return []

static func titan_ship_id_for(_race: String) -> int:
	return 0

static func titan_fetter_id_for(_race: String) -> String:
	return ""
