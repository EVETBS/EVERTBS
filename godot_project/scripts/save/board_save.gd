extends RefCounted
class_name BoardSave
## Lightweight save-slot index for EVERTBS main-menu load list (UI_AND_SHELL §0.1).

const INDEX_PATH := "user://save/board_slots.json"
const SAVE_DIR := "user://save"
const PROTO_ID := "prototype1"
const PROTO_NAME := "prototype1"
const PROTO_PATH := "user://save/slot_prototype1.json"
const REMOVED_FLAG := "user://save/prototype1_removed.flag"


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


static func list_slots() -> Array:
	ensure_dir()
	_ensure_prototype_seed()
	var slots: Array = _read_index()
	var out: Array = []
	for s in slots:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = s
		var sid := str(e.get("id", ""))
		if sid.is_empty():
			continue
		out.append({
			"id": sid,
			"name": str(e.get("name", sid)),
			"path": str(e.get("path", "")),
			"updated_at": str(e.get("updated_at", "")),
			"layout": str(e.get("layout", "res://data/board/layout.json")),
		})
	return out


static func delete_slot(slot_id: String) -> Dictionary:
	ensure_dir()
	var slots: Array = _read_index()
	var kept: Array = []
	var path := ""
	for s in slots:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == slot_id:
			path = str(s.get("path", ""))
			continue
		kept.append(s)
	_write_index(kept)
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if slot_id == PROTO_ID:
		var rf := FileAccess.open(REMOVED_FLAG, FileAccess.WRITE)
		if rf:
			rf.store_string("1")
			rf.close()
	return {"ok": true}


static func save_match(layout: String, factions: Array, slot_name: String = "") -> Dictionary:
	ensure_dir()
	var sid := "match_%d" % int(Time.get_unix_time_from_system())
	var path := "%s/slot_%s.json" % [SAVE_DIR, sid]
	var stamp := Time.get_datetime_string_from_system(false, true)
	var display := slot_name if slot_name != "" else "存档 %s" % stamp
	var payload := {
		"id": sid,
		"name": display,
		"path": path,
		"layout": layout,
		"updated_at": stamp,
		"factions": factions,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "write"}
	f.store_string(JSON.stringify(payload))
	f.close()
	var slots: Array = _read_index()
	slots.append({
		"id": sid,
		"name": display,
		"path": path,
		"layout": layout,
		"updated_at": stamp,
	})
	_write_index(slots)
	return {"ok": true, "id": sid, "name": display}


static func load_slot(slot_id: String) -> Dictionary:
	for s in list_slots():
		if str(s.get("id", "")) != slot_id:
			continue
		var layout := str(s.get("layout", "res://data/board/layout.json"))
		var boot := {"layout": layout}
		var slot_path := str(s.get("path", ""))
		if slot_path != "" and FileAccess.file_exists(slot_path):
			var slot_raw = JSON.parse_string(FileAccess.get_file_as_string(slot_path))
			if typeof(slot_raw) == TYPE_DICTIONARY and typeof(slot_raw.get("factions", null)) == TYPE_ARRAY:
				boot["factions"] = slot_raw["factions"]
		var bf := FileAccess.open("user://board_boot.json", FileAccess.WRITE)
		if bf == null:
			return {"ok": false, "error": "boot_write"}
		bf.store_string(JSON.stringify(boot))
		bf.close()
		return {"ok": true, "layout": layout, "scene": "res://game/board_test.tscn"}
	return {"ok": false, "error": "missing"}


static func _ensure_prototype_seed() -> void:
	if FileAccess.file_exists(REMOVED_FLAG):
		return
	var slots: Array = _read_index()
	for s in slots:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == PROTO_ID:
			return
	var meta := {
		"id": PROTO_ID,
		"name": PROTO_NAME,
		"path": PROTO_PATH,
		"layout": "res://data/board/layout.json",
		"updated_at": Time.get_datetime_string_from_system(false, true),
	}
	var pf := FileAccess.open(PROTO_PATH, FileAccess.WRITE)
	if pf:
		pf.store_string(JSON.stringify(meta))
		pf.close()
	slots.append(meta)
	_write_index(slots)


static func _read_index() -> Array:
	if not FileAccess.file_exists(INDEX_PATH):
		return []
	var raw = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if typeof(raw) == TYPE_DICTIONARY:
		return raw.get("slots", [])
	if typeof(raw) == TYPE_ARRAY:
		return raw
	return []


static func _write_index(slots: Array) -> void:
	ensure_dir()
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"slots": slots}))
	f.close()
