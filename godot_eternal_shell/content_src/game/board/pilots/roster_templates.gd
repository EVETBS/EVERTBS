extends RefCounted
class_name RosterTemplates
## Per-size member roster templates (SHIPS §7.2 · UI_AND_SHELL §0.5).
## Doc shape: {"templates": {"<n>": {"onfield": [id…], "starters": [id…]}}}.
## Legacy "<n>": [id…] is read as onfield.

const PATH := "user://content_runtime/data/board/roster_templates.json"
const SIZES := [10, 15, 20, 40, 60]
const MemberTableScr := preload("res://game/board/pilots/member_table.gd")

static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute("user://content_runtime/data/board")


static func load_all() -> Dictionary:
	ensure_dir()
	if not FileAccess.file_exists(PATH):
		return {"templates": {}, "active_size": 20, "saved": false}
	var raw = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		return {"templates": {}, "active_size": 20, "saved": false}
	var t = raw.get("templates", {})
	if typeof(t) != TYPE_DICTIONARY:
		t = {}
	var size_n := int(raw.get("active_size", 20))
	if not SIZES.has(size_n):
		size_n = 20
	return {"templates": t, "active_size": size_n, "saved": bool(raw.get("saved", false))}


static func save_all(doc: Dictionary) -> void:
	ensure_dir()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("RosterTemplates cannot write %s" % PATH)
		return
	f.store_string(JSON.stringify(doc))
	f.close()


static func starter_cap(size_n: int) -> int:
	return int(size_n / 2)


static func _ids_of(v) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(v) != TYPE_ARRAY:
		return out
	for x in v as Array:
		var mid := str(x).strip_edges()
		if mid != "" and not out.has(mid):
			out.append(mid)
	return out


static func get_entry(size_n: int) -> Dictionary:
	## {"onfield": PackedStringArray, "starters": PackedStringArray}; seeds random onfield when empty.
	var doc := load_all()
	var templates: Dictionary = doc.get("templates", {})
	var key := str(size_n)
	var raw = templates.get(key, null)
	var onfield := PackedStringArray()
	var starters := PackedStringArray()
	if raw == null:
		onfield = random_fill(size_n)
		templates[key] = {"onfield": Array(onfield), "starters": []}
		doc["templates"] = templates
		save_all(doc)
	elif typeof(raw) == TYPE_ARRAY:
		onfield = _ids_of(raw)
	elif typeof(raw) == TYPE_DICTIONARY:
		onfield = _ids_of((raw as Dictionary).get("onfield", []))
		starters = _ids_of((raw as Dictionary).get("starters", []))
	return {"onfield": onfield, "starters": starters}


static func set_active_size(size_n: int) -> void:
	if not SIZES.has(size_n):
		return
	var doc := load_all()
	doc["active_size"] = size_n
	save_all(doc)


static func active_size() -> int:
	var n := int(load_all().get("active_size", 20))
	return n if SIZES.has(n) else 20


static func has_saved() -> bool:
	return bool(load_all().get("saved", false))


static func get_template(size_n: int) -> PackedStringArray:
	## Backward-compatible: onfield list (unresolved).
	return get_entry(size_n)["onfield"]


static func set_entry(size_n: int, onfield: PackedStringArray, starters: PackedStringArray) -> void:
	var doc := load_all()
	var templates: Dictionary = doc.get("templates", {})
	templates[str(size_n)] = {"onfield": Array(onfield), "starters": Array(starters)}
	doc["templates"] = templates
	doc["active_size"] = size_n if SIZES.has(size_n) else int(doc.get("active_size", 20))
	doc["saved"] = true
	save_all(doc)


static func set_template(size_n: int, ids: PackedStringArray) -> void:
	var cur := get_entry(size_n)
	set_entry(size_n, ids, cur["starters"])


static func _pool_ids() -> Array:
	var pool: Array = []
	for row in MemberTableScr.load_merged():
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var mid := str(row.get("id", "")).strip_edges()
		if mid != "":
			pool.append(mid)
	return pool


static func random_fill(size_n: int) -> PackedStringArray:
	var pool: Array = _pool_ids()
	pool.shuffle()
	var out := PackedStringArray()
	var n := mini(size_n, pool.size())
	for i in range(n):
		out.append(str(pool[i]))
	## If pool smaller than size, wrap.
	while out.size() < size_n and not pool.is_empty():
		out.append(str(pool[out.size() % pool.size()]))
	return out


static func _fill_to_size(chosen: Array, size_n: int, r: RandomNumberGenerator) -> Array:
	if chosen.size() > size_n:
		_shuffle(chosen, r)
		return chosen.slice(0, size_n)
	if chosen.size() == size_n:
		return chosen
	var rest: Array = []
	for mid in _pool_ids():
		if not chosen.has(mid):
			rest.append(mid)
	_shuffle(rest, r)
	for mid2 in rest:
		if chosen.size() >= size_n:
			break
		chosen.append(mid2)
	var k := 0
	while chosen.size() < size_n and not chosen.is_empty():
		chosen.append(chosen[k % chosen.size()])
		k += 1
	return chosen


static func _fill_starters(chosen: Array, marked: Array, size_n: int, r: RandomNumberGenerator) -> Dictionary:
	## Prefer template marks that made the field; fill shortfall from remaining on-field.
	var cand: Array = []
	for sid in marked:
		var s := str(sid)
		if chosen.has(s) and not cand.has(s):
			cand.append(s)
	var cap := starter_cap(size_n)
	if cand.size() > cap:
		_shuffle(cand, r)
		cand = cand.slice(0, cap)
	elif cand.size() < cap:
		var extra: Array = []
		for mid in chosen:
			var s2 := str(mid)
			if not cand.has(s2):
				extra.append(s2)
		_shuffle(extra, r)
		for e in extra:
			if cand.size() >= cap:
				break
			cand.append(e)
	var starters: Dictionary = {}
	for c in cand:
		starters[str(c)] = true
	return starters


static func resolve(size_n: int, rng: RandomNumberGenerator = null) -> Dictionary:
	## Player faction: template onfield + fill vacancies; starters filled to cap from on-field.
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var e := get_entry(size_n)
	var chosen: Array = _fill_to_size(Array(e["onfield"]), size_n, r)
	var starters: Dictionary = _fill_starters(chosen, Array(e["starters"]), size_n, r)
	var ids := PackedStringArray()
	for c2 in chosen:
		ids.append(str(c2))
	return {"ids": ids, "starters": starters}


static func resolve_ai(size_n: int, rng: RandomNumberGenerator = null) -> Dictionary:
	## AI faction: independent draw from the full member table (not the player template).
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var pool: Array = _pool_ids()
	_shuffle(pool, r)
	var chosen: Array = _fill_to_size([], size_n, r) if pool.is_empty() else _fill_to_size(pool.duplicate(), size_n, r)
	var starters: Dictionary = _fill_starters(chosen, [], size_n, r)
	var ids := PackedStringArray()
	for c2 in chosen:
		ids.append(str(c2))
	return {"ids": ids, "starters": starters}


static func _shuffle(arr: Array, r: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
