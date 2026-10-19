extends Node
## Editor / content autoload stub. Firing visuals do not read weapon_fx from here.

var content_version: String = "local"
var match_flow: Dictionary = {}
var economy: Dictionary = {}
var board: Dictionary = {}
var combat: Dictionary = {}
var ai: Dictionary = {}
var visual: Dictionary = {}
var weapon_fx: Dictionary = {}
var ships: Dictionary = {}
var host_ships_override: Dictionary = {}

func _ready() -> void:
	pass

func reload_all() -> void:
	pass

func get_ship(_id: Variant) -> Dictionary:
	if typeof(_id) == TYPE_STRING and ships.has(_id):
		return ships[_id]
	if typeof(_id) == TYPE_INT and ships.has(_id):
		return ships[_id]
	return {}

func ships_table_hash() -> String:
	return table_hash(ships)

func export_ships_table() -> Dictionary:
	return ships.duplicate(true)

func table_hash(table: Dictionary) -> String:
	return str(hash(table))

func apply_host_ships_override(table: Dictionary) -> bool:
	host_ships_override = table.duplicate(true)
	return true

func end_match_host_ships_material() -> void:
	host_ships_override.clear()
