extends RefCounted
class_name MemberTable
## Header-driven member.csv. Builtin defaults plus a half-exposed copy.

const BUILTIN := "res://data/board/member.csv"
const EXPOSED := "user://content_runtime/data/board/member.csv"
const DRAFT_DIR := "user://content_runtime/data/board/custom_drafts"
const DEFAULT_PREF := "damage_control|shield_booster_s|armor_repairer_s|hull_repairer_s"

const PILOTS_DIR := "res://assets/ui/pilots"
const DEFAULT_PORTRAIT := "default"

## Resolve member face: portrait key -> alt keys -> default.png.
static func load_portrait(portrait_key: String = "", alt_keys: PackedStringArray = []) -> Texture2D:
	var keys: Array = []
	var pk := portrait_key.strip_edges()
	if pk.begins_with("user://") or pk.begins_with("res://"):
		if ResourceLoader.exists(pk):
			var direct := load(pk) as Texture2D
			if direct != null:
				return direct
		var abs := ProjectSettings.globalize_path(pk)
		if FileAccess.file_exists(pk):
			var img := Image.new()
			if img.load(abs) == OK:
				return ImageTexture.create_from_image(img)
	if pk != "":
		keys.append(pk)
	for k in alt_keys:
		var s := str(k).strip_edges()
		if s != "" and s not in keys:
			keys.append(s)
	if DEFAULT_PORTRAIT not in keys:
		keys.append(DEFAULT_PORTRAIT)
	for k in keys:
		var path := "%s/%s.png" % [PILOTS_DIR, k]
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	return null



static func load_merged() -> Array:
	var builtin: Array = rows_from_file(BUILTIN)
	if not FileAccess.file_exists(EXPOSED):
		_expand_rank_a_ships(builtin)
		_write_rows(_headers_of(builtin), builtin)
		return builtin
	var exposed: Array = rows_from_file(EXPOSED)
	var by_id: Dictionary = {}
	var order: Array[String] = []
	for row in builtin:
		var mid := str(row.get("id", ""))
		if mid.is_empty() or by_id.has(mid):
			continue
		by_id[mid] = (row as Dictionary).duplicate(true)
		order.append(mid)
	var exposed_ids: Dictionary = {}
	for row2 in exposed:
		var mid2 := str(row2.get("id", ""))
		if mid2.is_empty():
			continue
		exposed_ids[mid2] = true
		if not by_id.has(mid2):
			by_id[mid2] = (row2 as Dictionary).duplicate(true)
			order.append(mid2)
		elif _differs(by_id[mid2], row2):
			by_id[mid2] = (row2 as Dictionary).duplicate(true)
	var missing: Array = []
	for row3 in builtin:
		var mid3 := str(row3.get("id", ""))
		if mid3.is_empty() or exposed_ids.has(mid3):
			continue
		missing.append(by_id[mid3])
	if not missing.is_empty():
		var kept: Array = exposed.duplicate(true)
		for extra in missing:
			kept.append(extra)
		_write_rows(_headers_of(kept), kept)
	var out: Array = []
	for mid4 in order:
		out.append(by_id[mid4])
	if _expand_rank_a_ships(out):
		_write_rows(_headers_of(out), out)
	if _stamp_pref(out):
		_write_rows(_headers_of(out), out)
	return out


static func _stamp_pref(rows: Array) -> bool:
	var dirty := false
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("pref_eq", "")).strip_edges() == "":
			row["pref_eq"] = DEFAULT_PREF
			dirty = true
	return dirty


static func builtin_ids() -> Dictionary:
	var ids := {}
	for row in rows_from_file(BUILTIN):
		ids[str(row.get("id", ""))] = true
	return ids


static func is_builtin(member_id: String) -> bool:
	return builtin_ids().has(member_id)


static func pref_list(row: Dictionary) -> PackedStringArray:
	var raw := str(row.get("pref_eq", "")).strip_edges()
	if raw == "":
		raw = DEFAULT_PREF
	var out := PackedStringArray()
	for part in raw.split("|", false):
		out.append(part.strip_edges())
	while out.size() < 4:
		out.append("")
	if out.size() > 4:
		out = out.slice(0, 4)
	return out


static func dismiss(member_id: String) -> bool:
	if member_id == "" or is_builtin(member_id):
		return false
	var rows: Array = load_merged()
	var kept: Array = []
	var found := false
	for row in rows:
		if str(row.get("id", "")) == member_id:
			found = true
			continue
		kept.append(row)
	if not found:
		return false
	_write_rows(_headers_of(kept), kept)
	var draft := "%s/%s.json" % [DRAFT_DIR, member_id]
	if FileAccess.file_exists(draft):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(draft))
	return true


static func _expand_rank_a_ships(rows: Array) -> bool:
	var playable := CrewRank.playable_ship_ids()
	if playable.is_empty():
		return false
	var dirty := false
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if CrewRank.expand_full_unlock_ships(row as Dictionary, playable):
			dirty = true
	return dirty


static func crew_equipment(row: Dictionary) -> Dictionary:
	var mid := str(row.get("id", ""))
	var eq := {
		"id": "crew_%s" % mid,
		"name": str(row.get("name", mid)),
		"kind": "crew",
	}
	var bonus := str(row.get("bonus", "")).strip_edges()
	if bonus.is_empty():
		return eq
	for part in bonus.split("|", false):
		var piece := str(part).strip_edges()
		var cut := piece.find("=")
		if cut <= 0:
			continue
		var key := piece.substr(0, cut).strip_edges()
		var val := piece.substr(cut + 1).strip_edges()
		if key.is_empty():
			continue
		eq[key] = val
	return eq


static func effect_mul(eq: Dictionary, key: String) -> float:
	if eq.is_empty() or not eq.has(key):
		return 1.0
	return float(eq[key])


static func rows_from_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var rows := rows_from_text(FileAccess.get_file_as_string(path))
	if path != BUILTIN:
		return rows
	var kept: Array = []
	for row in rows:
		var mid := str(row.get("id", "")).strip_edges()
		if mid.is_valid_int() and mid.length() == 8:
			kept.append(row)
	return kept


static func rows_from_text(text: String) -> Array:
	var records: Array = _parse_records(text)
	if records.is_empty():
		return []
	var header: Array = records[0]
	var out: Array = []
	for i in range(1, records.size()):
		var cells: Array = records[i]
		var blank := true
		for cell in cells:
			if str(cell).strip_edges() != "":
				blank = false
				break
		if blank:
			continue
		var row: Dictionary = {}
		for c in header.size():
			var key := str(header[c]).strip_edges()
			if key.is_empty():
				continue
			var val := ""
			if c < cells.size():
				val = str(cells[c])
			row[key] = val
		if str(row.get("id", "")).strip_edges().is_empty():
			continue
		out.append(row)
	return out


static func _differs(a: Dictionary, b: Dictionary) -> bool:
	var keys: Dictionary = {}
	for k in a.keys():
		keys[str(k)] = true
	for k2 in b.keys():
		keys[str(k2)] = true
	for key in keys.keys():
		if str(a.get(key, "")) != str(b.get(key, "")):
			return true
	return false


static func _headers_of(rows: Array) -> PackedStringArray:
	var seen: Dictionary = {}
	var out := PackedStringArray()
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		for k in (row as Dictionary).keys():
			var key := str(k)
			if key.is_empty() or seen.has(key):
				continue
			seen[key] = true
			out.append(key)
	return out


static func write_rows(header: PackedStringArray, rows: Array) -> void:
	_write_rows(header, rows)


static func _write_rows(header: PackedStringArray, rows: Array) -> void:
	DirAccess.make_dir_recursive_absolute("user://content_runtime/data/board")
	var lines: PackedStringArray = PackedStringArray()
	lines.append(_join_csv(header))
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var cells := PackedStringArray()
		for key in header:
			cells.append(_escape(str((row as Dictionary).get(key, ""))))
		lines.append(",".join(cells))
	var f := FileAccess.open(EXPOSED, FileAccess.WRITE)
	if f == null:
		push_error("MemberTable cannot write %s" % EXPOSED)
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()


static func _join_csv(cells: PackedStringArray) -> String:
	var escaped := PackedStringArray()
	for cell in cells:
		escaped.append(_escape(cell))
	return ",".join(escaped)


static func _escape(value: String) -> String:
	if value.find(",") >= 0 or value.find("\"") >= 0 or value.find("\n") >= 0 or value.find("\r") >= 0:
		return "\"%s\"" % value.replace("\"", "\"\"")
	return value


static func _parse_records(text: String) -> Array:
	var records: Array = []
	var row: Array = []
	var cell := ""
	var in_quotes := false
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text.substr(i, 1)
		if in_quotes:
			if ch == "\"":
				if i + 1 < n and text.substr(i + 1, 1) == "\"":
					cell += "\""
					i += 2
					continue
				in_quotes = false
				i += 1
				continue
			cell += ch
			i += 1
			continue
		if ch == "\"":
			in_quotes = true
			i += 1
			continue
		if ch == ",":
			row.append(cell)
			cell = ""
			i += 1
			continue
		if ch == "\n" or ch == "\r":
			if ch == "\r" and i + 1 < n and text.substr(i + 1, 1) == "\n":
				i += 1
			row.append(cell)
			cell = ""
			if not _row_blank(row):
				records.append(row)
			row = []
			i += 1
			continue
		cell += ch
		i += 1
	if cell != "" or not row.is_empty():
		row.append(cell)
		if not _row_blank(row):
			records.append(row)
	return records


static func _row_blank(row: Array) -> bool:
	for cell in row:
		if str(cell).strip_edges() != "":
			return false
	return true
