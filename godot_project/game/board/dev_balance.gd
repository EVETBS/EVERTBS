extends RefCounted
class_name BoardDevBalance
## Session + user://dev_balance.json. Does not rewrite ships.json.

const SAVE_PATH := "user://dev_balance.json"
const TONS: Array[String] = ["frigate", "destroyer", "cruiser", "battlecruiser", "battleship"]

static var loaded := false
static var master_on := false
static var want_build_1s := false
static var want_resource := false
static var resource_bonus := 0
static var resource_pilot_ids: Dictionary = {}

static var hp: Dictionary = {}
static var dph: Dictionary = {}
static var model_scale: Dictionary = {}
static var model_euler: Dictionary = {}
static var hidden_off: Dictionary = {}
static var equip_num: Dictionary = {}
static var tonnage_build: Dictionary = {}
static var tonnage_work: Dictionary = {}
static var work_caps: Dictionary = {}
static var scale_prep := 1.0
static var scale_move := 1.0
static var scale_jump := 1.0
static var scale_landing := 1.0
## Same-system landing scale by cells skipped on the short arc. Index 0 = adjacent cell.
static var land_arc: Array = [0.10, 0.20, 0.60, 1.0, 1.0, 1.0]

static func master() -> bool:
	return master_on

static func force_build_one() -> bool:
	return master_on and want_build_1s

static func resource_extra(pilot_id: String) -> int:
	if not master_on or resource_bonus <= 0:
		return 0
	if resource_pilot_ids.has(pilot_id):
		return resource_bonus
	return 0

static func set_master(on: bool) -> void:
	master_on = on
	if not on:
		resource_bonus = 0
		resource_pilot_ids.clear()
	save()

static func set_want_build(on: bool) -> void:
	want_build_1s = on
	save()

static func set_want_resource(on: bool) -> void:
	want_resource = on
	if not on:
		resource_bonus = 0
		resource_pilot_ids.clear()
	save()

static func apply_resource_payload(payload: Dictionary) -> void:
	resource_bonus = int(payload.get("bonus", 0))
	resource_pilot_ids.clear()
	if resource_bonus <= 0:
		resource_bonus = 0
		return
	var ids = payload.get("pilots", [])
	if typeof(ids) != TYPE_ARRAY:
		return
	for id in ids:
		resource_pilot_ids[str(id)] = true

static func build_seconds(tonnage: String, fallback: float) -> float:
	ensure_defaults()
	if tonnage_build.has(tonnage):
		return float(tonnage_build[tonnage])
	return fallback

static func work_rate(tonnage: String, fallback: float) -> float:
	ensure_defaults()
	if tonnage_work.has(tonnage):
		return float(tonnage_work[tonnage])
	return fallback

static func scale_of(which: String) -> float:
	match which:
		"scale_prep":
			return scale_prep
		"scale_move":
			return scale_move
		"scale_jump":
			return scale_jump
		"scale_landing":
			return scale_landing
		_:
			return 1.0

static func set_scale(which: String, value: float) -> void:
	match which:
		"scale_prep":
			scale_prep = value
		"scale_move":
			scale_move = value
		"scale_jump":
			scale_jump = value
		"scale_landing":
			scale_landing = value

static func land_arc_of(skip: int) -> float:
	var i := clampi(skip, 0, 5)
	if i < land_arc.size():
		return float(land_arc[i])
	return 1.0

static func land_arc_mul(from_cell: int, to_cell: int, cell_count: int) -> float:
	var steps := BoardTypes.shorter_arc_steps(from_cell, to_cell, cell_count)
	return land_arc_of(maxi(steps - 1, 0))

static func set_land_arc(skip: int, value: float) -> void:
	var i := clampi(skip, 0, 5)
	while land_arc.size() < 6:
		land_arc.append(1.0)
	land_arc[i] = value

static func model_mul(ship_id: String) -> float:
	return clampf(float(model_scale.get(ship_id, 1.0)), 0.10, 5.0)

static func hull_diameter(ship_id: String) -> float:
	return BoardTypes.HULL_DIAMETER * model_mul(ship_id)

static func set_model_scale(ship_id: String, value: float) -> void:
	model_scale[ship_id] = clampf(value, 0.10, 5.0)

static func model_euler_of(ship_id: String) -> Vector3:
	var row: Dictionary = _dict(model_euler.get(ship_id, {}))
	return Vector3(
		float(row.get("x", 0.0)),
		float(row.get("y", 0.0)),
		float(row.get("z", 0.0))
	)

static func set_model_euler(ship_id: String, euler: Vector3) -> void:
	model_euler[ship_id] = {
		"x": wrapf(euler.x, -180.0, 180.0),
		"y": wrapf(euler.y, -180.0, 180.0),
		"z": wrapf(euler.z, -180.0, 180.0),
	}

static func work_cap(kind: int) -> float:
	var key := str(kind)
	if work_caps.has(key):
		return maxf(1.0, float(work_caps[key]))
	return 1000.0

static func ensure_defaults() -> void:
	if not tonnage_build.is_empty() and not tonnage_work.is_empty():
		return
	var eq := _read_json("res://data/board/equipment.json")
	if tonnage_build.is_empty():
		var tb = eq.get("tonnage_build_s", {})
		if typeof(tb) == TYPE_DICTIONARY:
			for k in tb.keys():
				tonnage_build[str(k)] = float(tb[k])
	if tonnage_work.is_empty():
		var tw = eq.get("tonnage_work_rate", {})
		if typeof(tw) == TYPE_DICTIONARY:
			for k in tw.keys():
				tonnage_work[str(k)] = float(tw[k])

static func load() -> void:
	if loaded:
		ensure_defaults()
		return
	loaded = true
	if FileAccess.file_exists(SAVE_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			master_on = bool(parsed.get("master", false))
			want_build_1s = bool(parsed.get("build_1s", false))
			want_resource = bool(parsed.get("resource", false))
			hp = _dict(parsed.get("hp", {}))
			dph = _dict(parsed.get("dph", {}))
			model_scale = _dict(parsed.get("model_scale", {}))
			model_euler = _dict(parsed.get("model_euler", {}))
			hidden_off = _dict(parsed.get("hidden_off", {}))
			equip_num = _dict(parsed.get("equip", {}))
			tonnage_build = _dict(parsed.get("tonnage_build", {}))
			tonnage_work = _dict(parsed.get("tonnage_work", {}))
			work_caps = _dict(parsed.get("work_caps", {}))
			scale_prep = float(parsed.get("scale_prep", 1.0))
			scale_move = float(parsed.get("scale_move", 1.0))
			scale_jump = float(parsed.get("scale_jump", 1.0))
			scale_landing = float(parsed.get("scale_landing", 1.0))
			var arc_raw = parsed.get("land_arc", [])
			if typeof(arc_raw) == TYPE_ARRAY and not arc_raw.is_empty():
				land_arc = [0.10, 0.20, 0.60, 1.0, 1.0, 1.0]
				for i in mini(6, arc_raw.size()):
					land_arc[i] = float(arc_raw[i])
	if not master_on:
		resource_bonus = 0
		resource_pilot_ids.clear()
	ensure_defaults()

static func save() -> void:
	var body := {
		"master": master_on,
		"build_1s": want_build_1s,
		"resource": want_resource,
		"hp": hp,
		"dph": dph,
		"model_scale": model_scale,
		"model_euler": model_euler,
		"hidden_off": hidden_off,
		"equip": equip_num,
		"tonnage_build": tonnage_build,
		"tonnage_work": tonnage_work,
		"work_caps": work_caps,
		"scale_prep": scale_prep,
		"scale_move": scale_move,
		"scale_jump": scale_jump,
		"scale_landing": scale_landing,
		"land_arc": land_arc,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(body))

static func apply_to_data(data: BoardData) -> void:
	ensure_defaults()
	for sid in data.ships.keys():
		var def: Dictionary = data.ships[sid]
		if hp.has(sid):
			var row: Dictionary = _dict(hp[sid])
			def["shield"] = float(row.get("shield", def.get("shield", 1)))
			def["armor"] = float(row.get("armor", def.get("armor", 1)))
			def["structure"] = float(row.get("structure", def.get("structure", 1)))
		if bool(def.get("npc_hull", false)):
			continue
		_ensure_dph(def, float(dph.get(sid, 1.0)))
		var hidden = def.get("fit", {}).get("hidden", [])
		if typeof(hidden) != TYPE_ARRAY:
			continue
		for i in hidden.size():
			var h = hidden[i]
			if typeof(h) != TYPE_DICTIONARY:
				continue
			var key := "%s|%d" % [str(sid), i]
			h["enabled"] = not bool(hidden_off.get(key, false))
	for eid in equip_num.keys():
		var eq = data.equipment.get(eid, {})
		if typeof(eq) != TYPE_DICTIONARY:
			continue
		var fields: Dictionary = _dict(equip_num[eid])
		for fk in fields.keys():
			eq[str(fk)] = fields[fk]

static func all_ships() -> Array:
	var root := _read_json("res://data/board/ships.json")
	var rows: Array = []
	for s in root.get("ships", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == "":
			continue
		rows.append(s)
	return rows

static func playable_ships() -> Array:
	var root := _read_json("res://data/board/ships.json")
	var rows: Array = []
	for s in root.get("ships", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if bool(s.get("npc_hull", false)):
			continue
		rows.append(s)
	return rows

static func secondary_equipment() -> Array:
	var eq := _read_json("res://data/board/equipment.json")
	var rows: Array = []
	for k in eq.keys():
		var row = eq[k]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if not row.has("id"):
			continue
		if bool(row.get("parked", false)) or str(row.get("size", "")) == "XL":
			continue
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var na := str(a.get("name", a.get("id", "")))
		var nb := str(b.get("name", b.get("id", "")))
		if na == nb:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return na < nb
	)
	return rows

static func _ensure_dph(def: Dictionary, value: float) -> void:
	var fit = def.get("fit", {})
	if typeof(fit) != TYPE_DICTIONARY:
		fit = {}
		def["fit"] = fit
	var hidden = fit.get("hidden", [])
	if typeof(hidden) != TYPE_ARRAY:
		hidden = []
		fit["hidden"] = hidden
	for h in hidden:
		if typeof(h) == TYPE_DICTIONARY and str(h.get("kind", "")) == "dph_mul":
			h["value"] = value
			return
	hidden.append({"kind": "dph_mul", "value": value})

static func _dict(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
