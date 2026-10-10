extends RefCounted
class_name BoardAiController

var faction = 2
var fleets: Array = [] # {id, members: [unit_id], role}
var stolen_mode = false
var stolen_sys = ""
var stolen_cell = -1

func setup_fleets(units: Array) -> void:
	var mine: Array = []
	for u in units:
		if int(u.get("faction", 0)) == faction and u.get("alive", false):
			mine.append(u)
	var n = mine.size()
	var fleet_n = 1
	if n >= 6:
		fleet_n = 3
	elif n >= 2:
		fleet_n = 2
	fleets.clear()
	for i in fleet_n:
		fleets.append({"id": i, "members": [], "weight": 0, "state": "station"})
	# balance by weight
	mine.sort_custom(func(a, b): return BoardTypes.tonnage_weight(a.get("tonnage", "destroyer")) > BoardTypes.tonnage_weight(b.get("tonnage", "destroyer")))
	for u in mine:
		var best = 0
		var best_w = 999999
		for i in fleets.size():
			if int(fleets[i]["weight"]) < best_w:
				best_w = int(fleets[i]["weight"])
				best = i
		fleets[best]["members"].append(u["id"])
		fleets[best]["weight"] = int(fleets[best]["weight"]) + BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
		u["fleet_id"] = best

func total_weight(units: Array) -> float:
	var w = 0.0
	for u in units:
		if int(u.get("faction", 0)) == faction and u.get("alive", false):
			w += BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
	return maxf(w, 1.0)

func cell_enemy_weight(units: Array, sys: String, cell: int, my_total: float) -> float:
	var w = 0.0
	for u in units:
		if not u.get("alive", false):
			continue
		if int(u["faction"]) == faction:
			continue
		if u.get("sys") != sys or int(u.get("cell", -1)) != cell:
			continue
		w += BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
	if w < my_total * 0.1:
		return 0.0
	return w

func system_has_enemy(units: Array, sys: String, my_total: float) -> bool:
	for u in units:
		if not u.get("alive", false):
			continue
		if int(u["faction"]) == faction:
			continue
		if u.get("sys") != sys:
			continue
		if cell_enemy_weight(units, sys, int(u["cell"]), my_total) > 0.0:
			return true
	return false

func largest_fleet_id() -> int:
	var best = 0
	var bw = -1
	for f in fleets:
		var w: int = f["weight"]
		var n: int = f["members"].size()
		if w > bw or (w == bw and n > fleets[best]["members"].size()) or (w == bw and n == fleets[best]["members"].size() and int(f["id"]) < best):
			bw = w
			best = int(f["id"])
	return best

func smallest_fleet_id() -> int:
	var best = 0
	var bw = 999999
	for f in fleets:
		var w: int = f["weight"]
		if w < bw or (w == bw and int(f["id"]) > best):
			bw = w
			best = int(f["id"])
	return best

func on_capture_stolen(sys: String, cell: int) -> void:
	stolen_mode = true
	stolen_sys = sys
	stolen_cell = cell
	var big = largest_fleet_id()
	var small = smallest_fleet_id()
	for f in fleets:
		var fid: int = f["id"]
		if fid == big:
			f["state"] = "hold_gate"
		elif fid == small:
			f["state"] = "attack_thief"
		else:
			f["state"] = "station"

func tick_orders(map: BoardMapModel, units: Array, diplomacy: Dictionary) -> Array:
	## Returns list of {unit_id, sys, cell}
	var orders: Array = []
	var my_w = total_weight(units)
	if stolen_mode:
		var still = false
		if map.systems.has(stolen_sys):
			var c: Dictionary = map.systems[stolen_sys]["cells"][stolen_cell]
			if int(c["owner"]) != faction:
				still = true
		if not still:
			stolen_mode = false
			for f in fleets:
				f["state"] = "station"
	for f in fleets:
		var members: Array = []
		for uid in f["members"]:
			for u in units:
				if u["id"] == uid and u.get("alive", false):
					members.append(u)
		if members.is_empty():
			continue
		var state: String = f["state"]
		var target = _pick_target(map, units, diplomacy, members, state, my_w)
		if target.is_empty():
			continue
		for u in members:
			if u.get("phase", BoardTypes.MovePhase.IDLE) != BoardTypes.MovePhase.IDLE:
				continue
			if u.get("sys") == target["sys"] and int(u.get("cell")) == int(target["cell"]):
				continue
			orders.append({"unit_id": u["id"], "sys": target["sys"], "cell": target["cell"]})
	return orders

func _pick_target(map: BoardMapModel, units: Array, _diplomacy: Dictionary, members: Array, state: String, my_w: float) -> Dictionary:
	var lead: Dictionary = members[0]
	var sys: String = lead["sys"]
	if state == "hold_gate" and stolen_mode:
		return _nearest_empty_gate_toward_enemy(map, units, stolen_sys, my_w)
	if state == "attack_thief" and stolen_mode:
		for u in units:
			if not u.get("alive", false) or int(u["faction"]) == faction:
				continue
			if u.get("sys") == stolen_sys and int(u.get("cell", -1)) == stolen_cell:
				return {"sys": stolen_sys, "cell": stolen_cell}
		# any enemy in stolen sys
		for u in units:
			if u.get("alive", false) and int(u["faction"]) != faction and u.get("sys") == stolen_sys:
				return {"sys": stolen_sys, "cell": int(u["cell"])}
	# same system enemies -> gate wait (except hold/attack fleets)
	if state != "hold_gate" and state != "attack_thief" and system_has_enemy(units, sys, my_w):
		return _pick_wait_gate(map, units, sys, my_w)
	# station
	var home: String = str(lead.get("current_station", lead.get("home", "soular")))
	if home == "" or not map.systems.has(home):
		home = "soular"
	var sc = map.station_cell(home)
	if sc >= 0:
		return {"sys": home, "cell": sc}
	return {}

func _pick_wait_gate(map: BoardMapModel, units: Array, sys: String, my_w: float) -> Dictionary:
	var best = -1
	var best_score = -999.0
	for c in map.systems[sys]["cells"]:
		if int(c["kind"]) != BoardTypes.CellKind.GATE:
			continue
		var gi: int = c["index"]
		if cell_enemy_weight(units, sys, gi, my_w) > 0.0:
			continue
		var far: String = c["gate_to"]
		var score = 10.0
		if system_has_enemy(units, far, my_w):
			score -= 5.0
		if score > best_score:
			best_score = score
			best = gi
	if best >= 0:
		return {"sys": sys, "cell": best}
	# all gated occupied — still pick nearest
	for c in map.systems[sys]["cells"]:
		if int(c["kind"]) == BoardTypes.CellKind.GATE:
			return {"sys": sys, "cell": int(c["index"])}
	return {}

func _nearest_empty_gate_toward_enemy(map: BoardMapModel, units: Array, sys: String, my_w: float) -> Dictionary:
	# enemy positions in sys
	var enemy_cells: Array = []
	for u in units:
		if u.get("alive", false) and int(u["faction"]) != faction and u.get("sys") == sys:
			if cell_enemy_weight(units, sys, int(u["cell"]), my_w) > 0.0:
				enemy_cells.append(int(u["cell"]))
	var best = -1
	var best_d = 999
	var n: int = map.systems[sys]["cells"].size()
	for c in map.systems[sys]["cells"]:
		if int(c["kind"]) != BoardTypes.CellKind.GATE:
			continue
		var gi: int = c["index"]
		var occupied = cell_enemy_weight(units, sys, gi, my_w) > 0.0
		if occupied:
			continue
		var d = 999
		for ec in enemy_cells:
			d = mini(d, BoardTypes.shorter_arc_steps(gi, ec, n))
		if enemy_cells.is_empty():
			d = 0
		if d < best_d:
			best_d = d
			best = gi
	if best >= 0:
		return {"sys": sys, "cell": best}
	# fallback any nearest gate even if occupied (will not order INTO if attack — hold skips)
	for c in map.systems[sys]["cells"]:
		if int(c["kind"]) == BoardTypes.CellKind.GATE:
			return {"sys": sys, "cell": int(c["index"])}
	return {"sys": sys, "cell": 0}

func redistribute_resources(map: BoardMapModel, pilots: Array, rng: RandomNumberGenerator) -> void:
	BoardResourceAssign.ai_redistribute(map, pilots, faction, rng)
