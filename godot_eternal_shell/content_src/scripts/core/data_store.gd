extends Node
## Minimal DataStore stub for editor / net compile. Shell may replace at runtime.

var content_version: String = "local"
var ships: Dictionary = {}
var host_ships_override: Dictionary = {}

func _ready() -> void:
	pass

func ships_table_hash() -> String:
	return ""
