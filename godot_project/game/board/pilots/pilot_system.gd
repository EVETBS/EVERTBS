extends RefCounted
class_name BoardPilotSystem

const TONNAGES := ["frigate", "destroyer", "cruiser", "battlecruiser", "battleship"]

var admin: BoardAdminProxy
var data: BoardData

func make_pilot(p: Dictionary) -> Dictionary:
	var ship_id: String = p.get("ship", "jdl_haiyan")
	var def: Dictionary = data.ship_def(ship_id)
	var _ton: String = def.get("tonnage", "destroyer")
	var auto: Dictionary = {}
	for t in TONNAGES:
		auto[t] = ""
	var storage: Dictionary = {}
	for t in TONNAGES:
		storage[t] = [] # list of ship instance dicts
	var building: Dictionary = {}
	for t in TONNAGES:
		building[t] = null
	return {
		"id": p["id"],
		"name": p["name"],
		"faction": int(p["faction"]),
		"home": p["home"],
		"current_station": p["home"],
		"home_station": p["home"],
		"in_station": false,
		"unit_id": "",
		"default_ship": ship_id,
		"auto_build": auto,
		"storage": storage,
		"building": building,
		"opening_cell_kind": p.get("cell_kind", "resource"),
		"opening_gate_to": p.get("gate_to", ""),
	}

func make_ship_instance(ship_id: String) -> Dictionary:
	var def: Dictionary = data.ship_def(ship_id)
	return {
		"ship_id": ship_id,
		"pristine_s": float(def["shield"]),
		"pristine_a": float(def["armor"]),
		"pristine_h": float(def["structure"]),
		"max_s": float(def["shield"]),
		"max_a": float(def["armor"]),
		"max_h": float(def["structure"]),
		"shield": float(def["shield"]),
		"armor": float(def["armor"]),
		"structure": float(def["structure"]),
		"cap": float(def["cap"]),
		"max_cap": float(def["cap"]),
		"resist": int(def["resist"]),
	}

func apply_fit_resist(inst: Dictionary, ship_id: String) -> void:
	var def: Dictionary = data.ship_def(ship_id)
	var resist = int(def["resist"])
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind")) == "resistance_mul":
			resist = mini(100, int(round(resist * float(h.get("value", 1.0)))))
	inst["resist"] = resist

func tick_build(pilots: Array, delta: float, map: BoardMapModel = null) -> void:
	for p in pilots:
		for ton in TONNAGES:
			var store: Array = p["storage"][ton]
			var cap: int = int(data.equipment.get("storage_slots_per_tonnage", 2))
			var auto_id: String = str(p["auto_build"].get(ton, ""))
			var building = p["building"][ton]
			var can_progress := true
			if map != null:
				var unlock: int = BoardResourceAssign.unlock_need(data, ton)
				var held: int = BoardResourceAssign.pilot_held_count(map, str(p["id"]))
				if held < unlock:
					can_progress = false
			if building != null:
				if can_progress:
					# Refresh effective duration from current allocation
					if map != null:
						var def_cur: Dictionary = data.ship_def(str(building["ship_id"]))
						var base_s: float = float(def_cur.get("build_s", building.get("build_s", 60)))
						var eff: Dictionary = BoardResourceAssign.effective_build_s(data, map, p, base_s, ton)
						if eff["ok"]:
							building["build_s"] = float(eff["build_s"])
					building["t"] = float(building["t"]) + delta
					var need: float = float(building["build_s"])
					if building["t"] >= need:
						var inst = make_ship_instance(building["ship_id"])
						apply_fit_resist(inst, building["ship_id"])
						store.append(inst)
						p["building"][ton] = null
						if admin:
							admin.request("pilot.build", {"pilot": p["id"], "done": building["ship_id"]})
			# start new if under cap and auto set (job queued even when unlock blocks progress)
			if p["building"][ton] == null and auto_id != "" and store.size() < cap:
				var def: Dictionary = data.ship_def(auto_id)
				if def.is_empty() or str(def.get("tonnage")) != ton:
					continue
				var base2: float = float(def.get("build_s", 60))
				var build_s2: float = base2
				if map != null:
					var eff2: Dictionary = BoardResourceAssign.effective_build_s(data, map, p, base2, ton)
					if eff2["ok"]:
						build_s2 = float(eff2["build_s"])
				p["building"][ton] = {"ship_id": auto_id, "t": 0.0, "build_s": build_s2}

func storage_count_by_model(pilot: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for ton in TONNAGES:
		for inst in pilot["storage"][ton]:
			var sid: String = inst["ship_id"]
			out[sid] = int(out.get(sid, 0)) + 1
	return out

func destroy_one(pilot: Dictionary, ship_id: String) -> bool:
	var def: Dictionary = data.ship_def(ship_id)
	var ton: String = def.get("tonnage", "")
	if ton == "" or not pilot["storage"].has(ton):
		return false
	var store: Array = pilot["storage"][ton]
	for i in store.size():
		if store[i]["ship_id"] == ship_id:
			store.remove_at(i)
			return true
	return false

func take_one(pilot: Dictionary, ship_id: String) -> Dictionary:
	var def: Dictionary = data.ship_def(ship_id)
	var ton: String = def.get("tonnage", "")
	var store: Array = pilot["storage"][ton]
	for i in store.size():
		if store[i]["ship_id"] == ship_id:
			var inst: Dictionary = store[i]
			store.remove_at(i)
			return inst
	return {}

func dock_ship(pilot: Dictionary, inst: Dictionary) -> void:
	# full restore
	inst["max_s"] = inst["pristine_s"]
	inst["max_a"] = inst["pristine_a"]
	inst["max_h"] = inst["pristine_h"]
	inst["shield"] = inst["max_s"]
	inst["armor"] = inst["max_a"]
	inst["structure"] = inst["max_h"]
	inst["cap"] = inst["max_cap"]
	var def: Dictionary = data.ship_def(inst["ship_id"])
	var ton: String = def.get("tonnage", "destroyer")
	pilot["storage"][ton].append(inst)
	pilot["in_station"] = true
	pilot["unit_id"] = ""

func set_auto(pilot: Dictionary, ton: String, ship_id: String) -> void:
	pilot["auto_build"][ton] = ship_id
	if admin:
		admin.request("pilot.build", {"pilot": pilot["id"], "auto": ton, "ship": ship_id})
