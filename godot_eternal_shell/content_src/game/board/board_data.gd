extends RefCounted
class_name BoardData

const MemberTableScr := preload("res://game/board/pilots/member_table.gd")

var factions: Dictionary = {}
var diplomacy: Dictionary = {}
var ships: Dictionary = {} # id -> dict
var equipment: Dictionary = {}
var members: Dictionary = {} # 8-digit id -> row
var layout_path = "res://data/board/layout.json"

func load_all() -> void:
	factions = _load_json("res://data/board/factions.json")
	diplomacy = _load_json("res://data/board/diplomacy.json")
	equipment = _load_json("res://data/board/equipment.json")
	_load_members()
	var ships_root = _load_json("res://data/board/ships.json")
	ships.clear()
	for s in ships_root.get("ships", []):
		ships[s["id"]] = s
	ensure_npc_diplomacy()

func _load_json(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("BoardData missing %s" % path)
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if typeof(v) == TYPE_DICTIONARY else {}

func ship_def(id: String) -> Dictionary:
	return ships.get(id, {})

func member_by_id(member_id: String) -> Dictionary:
	var row = members.get(member_id, {})
	return row if typeof(row) == TYPE_DICTIONARY else {}

func apply_saved_members(factions_in: Array) -> void:
	for fac in factions_in:
		if typeof(fac) != TYPE_DICTIONARY:
			continue
		for member in fac.get("members", []):
			if typeof(member) != TYPE_DICTIONARY:
				continue
			var mid := str(member.get("id", ""))
			if mid.is_empty():
				continue
			members[mid] = member
			var eq: Dictionary = MemberTableScr.crew_equipment(member)
			var eid := str(eq.get("id", ""))
			if eid != "" and eid != "crew_":
				equipment[eid] = eq

func _load_members() -> void:
	members.clear()
	for row in MemberTableScr.load_merged():
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var mid := str(row.get("id", ""))
		if mid.is_empty():
			continue
		members[mid] = row
		var eq: Dictionary = MemberTableScr.crew_equipment(row)
		var eid := str(eq.get("id", ""))
		if eid != "" and eid != "crew_":
			equipment[eid] = eq

func is_npc_faction(fid: int) -> bool:
	for f in factions.get("factions", []):
		if int(f.get("id", -1)) == int(fid):
			return bool(f.get("npc", false))
	return false

func npc_faction_ids() -> Array:
	var out: Array = []
	for f in factions.get("factions", []):
		if bool(f.get("npc", false)):
			out.append(int(f.get("id", 0)))
	return out

func primary_npc_faction() -> int:
	var ids := npc_faction_ids()
	if ids.is_empty():
		return 0
	return int(ids[0])

func ensure_npc_diplomacy() -> void:
	## Non-NPC ↔ NPC are hostile by mark; ids are table keys only.
	var rels: Dictionary = diplomacy.get("relations", {})
	var all_ids: Array = []
	var npc_set: Dictionary = {}
	for f in factions.get("factions", []):
		var fid := int(f.get("id", 0))
		all_ids.append(fid)
		if bool(f.get("npc", false)):
			npc_set[fid] = true
	for fid2 in all_ids:
		var key := str(fid2)
		if not rels.has(key):
			rels[key] = {}
		var row: Dictionary = rels[key]
		row[key] = "self"
		for other in all_ids:
			if other == fid2:
				continue
			var ok := str(other)
			var cross_npc := bool(npc_set.has(fid2)) != bool(npc_set.has(other))
			if cross_npc:
				row[ok] = "hostile"
			elif not row.has(ok):
				row[ok] = "hostile"
		rels[key] = row
	diplomacy["relations"] = rels
