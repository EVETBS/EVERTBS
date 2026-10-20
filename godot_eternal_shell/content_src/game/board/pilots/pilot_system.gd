extends RefCounted
class_name BoardPilotSystem

const MemberTableScr := preload("res://game/board/pilots/member_table.gd")
const DevBalance := preload("res://game/board/dev_balance.gd")

const TONNAGES := ["frigate", "destroyer", "cruiser", "battlecruiser", "battleship"]

var admin: BoardAdminProxy
var data: BoardData

func make_pilot(p: Dictionary) -> Dictionary:
	var member_id := str(p.get("member_id", ""))
	var member: Dictionary = {}
	if data != null and member_id != "":
		member = data.member_by_id(member_id)
	var ship_id := str(member.get("default_ship", "")).strip_edges()
	if ship_id == "":
		ship_id = str(p.get("ship", "")).strip_edges()
	if ship_id == "":
		ship_id = "gila_cc2"
	var def: Dictionary = data.ship_def(ship_id)
	var display_name := str(p.get("name", ""))
	if display_name.is_empty() and not member.is_empty():
		display_name = str(member.get("name", ""))
	var crew_equip_id := ""
	if member_id != "":
		crew_equip_id = "crew_%s" % member_id
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
		"name": display_name,
		"member_id": member_id,
		"crew_equip_id": crew_equip_id,
		"faction": int(p["faction"]),
		"home": p["home"],
		"current_station": p["home"],
		"home_station": p["home"],
		"in_station": false,
		"unit_id": "",
		"default_ship": ship_id,
		"last_ship_id": ship_id,
		"starter": bool(p.get("starter", false)),
		"starter_used": false,
		"auto_build": auto,
		"storage": storage,
		"building": building,
		"opening_cell_kind": p.get("cell_kind", "resource"),
		"opening_gate_to": p.get("gate_to", ""),
	}

func make_ship_instance(ship_id: String, crew_eq: Dictionary = {}) -> Dictionary:
	var def: Dictionary = data.ship_def(ship_id)
	var hp_mul := MemberTableScr.effect_mul(crew_eq, "hp_mul")
	var shield := float(def["shield"]) * hp_mul * MemberTableScr.effect_mul(crew_eq, "shield_mul")
	var armor := float(def["armor"]) * hp_mul * MemberTableScr.effect_mul(crew_eq, "armor_mul")
	var structure := float(def["structure"]) * hp_mul * MemberTableScr.effect_mul(crew_eq, "structure_mul")
	var cap := float(def["cap"]) * MemberTableScr.effect_mul(crew_eq, "cap_mul")
	return {
		"ship_id": ship_id,
		"pristine_s": shield,
		"pristine_a": armor,
		"pristine_h": structure,
		"max_s": shield,
		"max_a": armor,
		"max_h": structure,
		"shield": shield,
		"armor": armor,
		"structure": structure,
		"cap": cap,
		"max_cap": cap,
		"resist": int(def["resist"]),
	}

func apply_fit_resist(inst: Dictionary, ship_id: String) -> void:
	var def: Dictionary = data.ship_def(ship_id)
	var resist = int(def["resist"])
	for h in def.get("fit", {}).get("hidden", []):
		if str(h.get("kind")) == "resistance_mul" and h.get("enabled", true) != false:
			resist = mini(100, int(round(resist * float(h.get("value", 1.0)))))
	inst["resist"] = resist

func tick_build(pilots: Array, delta: float, map: BoardMapModel = null) -> Array:
	## Returns list of {faction, ship_id} completed this tick.
	var completed: Array = []
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
					if map != null and not bool(building.get("starter_job", false)):
						var def_cur: Dictionary = data.ship_def(str(building["ship_id"]))
						var base_s: float = DevBalance.build_seconds(ton, float(def_cur.get("build_s", building.get("build_s", 60))))
						var eff: Dictionary = BoardResourceAssign.effective_build_s(data, map, p, base_s, ton)
						var next_s := base_s
						if eff["ok"]:
							next_s = float(eff["build_s"])
						next_s = _scaled_build_s(p, next_s)
						if DevBalance.force_build_one():
							next_s = 1.0
						building["build_s"] = next_s
					building["t"] = float(building["t"]) + delta
					var need: float = float(building["build_s"])
					if building["t"] >= need:
						var inst = make_ship_instance(building["ship_id"], _crew_eq(p))
						apply_fit_resist(inst, building["ship_id"])
						var crew_now := _crew_eq(p)
						var resist_mul := MemberTableScr.effect_mul(crew_now, "resist_mul") * MemberTableScr.effect_mul(crew_now, "resistance_mul")
						inst["resist"] = mini(100, int(round(float(inst["resist"]) * resist_mul)))
						store.append(inst)
						p["building"][ton] = null
						if bool(building.get("starter_job", false)):
							p["starter_used"] = true
						completed.append({"faction": int(p.get("faction", -1)), "ship_id": str(building["ship_id"])})
						if admin:
							admin.request("pilot.build", {"pilot": p["id"], "done": building["ship_id"]})
			# start new if under cap and auto set (job queued even when unlock blocks progress)
			if p["building"][ton] == null and auto_id != "" and store.size() < cap:
				var def: Dictionary = data.ship_def(auto_id)
				if def.is_empty() or str(def.get("tonnage")) != ton:
					continue
				if data != null and not CrewRank.member_has_ship(data.member_by_id(str(p.get("member_id", ""))), auto_id):
					continue
				var base2: float = DevBalance.build_seconds(ton, float(def.get("build_s", 60)))
				var build_s2: float = base2
				if map != null:
					var eff2: Dictionary = BoardResourceAssign.effective_build_s(data, map, p, base2, ton)
					if eff2["ok"]:
						build_s2 = float(eff2["build_s"])
				build_s2 = _scaled_build_s(p, build_s2)
				if DevBalance.force_build_one():
					build_s2 = 1.0
				var job := {"ship_id": auto_id, "t": 0.0, "build_s": build_s2}
				## SHIPS §7.3: starter's first hull takes 1 s flat.
				if bool(p.get("starter", false)) and not bool(p.get("starter_used", false)) and not _has_starter_job(p):
					job["build_s"] = 1.0
					job["starter_job"] = true
				p["building"][ton] = job
	return completed


func _has_starter_job(p: Dictionary) -> bool:
	for ton in TONNAGES:
		var b = p["building"].get(ton)
		if b != null and typeof(b) == TYPE_DICTIONARY and bool(b.get("starter_job", false)):
			return true
	return false

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

func _crew_eq(pilot: Dictionary) -> Dictionary:
	if data == null:
		return {}
	var eq = data.equipment.get(str(pilot.get("crew_equip_id", "")), {})
	return eq if typeof(eq) == TYPE_DICTIONARY else {}

func _scaled_build_s(pilot: Dictionary, base_s: float) -> float:
	return base_s * MemberTableScr.effect_mul(_crew_eq(pilot), "build_mul")
