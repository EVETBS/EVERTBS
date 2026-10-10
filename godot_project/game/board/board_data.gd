extends RefCounted
class_name BoardData

var factions: Dictionary = {}
var diplomacy: Dictionary = {}
var ships: Dictionary = {} # id -> dict
var equipment: Dictionary = {}
var layout_path = "res://data/board/layout.json"

func load_all() -> void:
	factions = _load_json("res://data/board/factions.json")
	diplomacy = _load_json("res://data/board/diplomacy.json")
	equipment = _load_json("res://data/board/equipment.json")
	var ships_root = _load_json("res://data/board/ships.json")
	ships.clear()
	for s in ships_root.get("ships", []):
		ships[s["id"]] = s

func _load_json(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("BoardData missing %s" % path)
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if typeof(v) == TYPE_DICTIONARY else {}

func ship_def(id: String) -> Dictionary:
	return ships.get(id, {})
