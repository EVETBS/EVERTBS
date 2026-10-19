extends RefCounted
class_name CrewRank
## Rank rules run only when the builtin member table is written.
## Runtime reads the ships column and crew-equipment fields.

const TONNAGES: Array[String] = ["frigate", "destroyer", "cruiser", "battlecruiser", "battleship"]
const EFFECT_KEYS: Array[String] = ["hp_mul", "weapon_damage_mul", "cap_convert_mul", "move_penalty_mul", "build_mul"]


static func unlock_count(rank: String) -> int:
	match rank:
		"D":
			return 1
		"C":
			return 2
		"B":
			return 3
		_:
			return 999999


static func playable_ship_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var path := "res://data/board/ships.json"
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for s in (parsed as Dictionary).get("ships", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = s
		if bool(def.get("npc_hull", false)) or bool(def.get("npc", false)):
			continue
		var sid := str(def.get("id", "")).strip_edges()
		if sid != "":
			out.append(sid)
	return out


static func member_has_ship(member: Dictionary, ship_id: String) -> bool:
	if ship_id.strip_edges() == "":
		return false
	if member.is_empty():
		return true
	var raw := str(member.get("ships", "")).strip_edges()
	if raw == "":
		return true
	for sid in raw.split("|", false):
		if sid.strip_edges() == ship_id:
			return true
	return false


static func expand_full_unlock_ships(row: Dictionary, playable: PackedStringArray) -> bool:
	var rank := str(row.get("rank", "")).strip_edges().to_upper()
	if rank != "A" and rank != "SR":
		return false
	if playable.is_empty():
		return false
	var have: Dictionary = {}
	for sid in str(row.get("ships", "")).split("|", false):
		var s := sid.strip_edges()
		if s != "":
			have[s] = true
	var missing := false
	for pid in playable:
		if not have.has(pid):
			missing = true
			break
	if not missing and have.size() == playable.size():
		return false
	row["ships"] = "|".join(playable)
	return true


static func unlocked_ids(rank: String, member_id: String, by_ton: Dictionary) -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(member_id)
	var out := PackedStringArray()
	var n := unlock_count(rank)
	for ton in TONNAGES:
		var pool: Array = by_ton.get(ton, [])
		var copy: Array = pool.duplicate()
		if n >= copy.size():
			for sid in copy:
				out.append(str(sid))
			continue
		for _i in n:
			if copy.is_empty():
				break
			var pick := rng.randi_range(0, copy.size() - 1)
			out.append(str(copy[pick]))
			copy.remove_at(pick)
	return out
