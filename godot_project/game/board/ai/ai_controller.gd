extends RefCounted
class_name BoardAiController

var faction = 2
var deputy_id := "yang" ## yang | chuang
var fleets: Array = [] # {id, members: [unit_id], role, marker}
var stolen_mode = false
var stolen_sys = ""
var stolen_cell = -1
var dip: Dictionary = {}

func setup_fleets(units: Array, only_ids: Dictionary = {}) -> void:
	## only_ids empty = every alive ship of this faction (AI full-faction).
	## Does not write control-group numbers.
	var mine: Array = []
	for u in units:
		if int(u.get("faction", 0)) != faction or not u.get("alive", false):
			continue
		if bool(u.get("garrison", false)):
			continue
		if not only_ids.is_empty() and not only_ids.has(str(u.get("id", ""))):
			continue
		mine.append(u)
	fleets.clear()
	if mine.is_empty():
		return
	if deputy_id == "chuang":
		_setup_fleets_chuang(mine)
	else:
		_setup_fleets_yang(mine)

func _setup_fleets_yang(mine: Array) -> void:
	## Tier by headcount N; ratio fill by tonnage weight (羊.md).
	var n = mine.size()
	var specs: Array = [["main", 1], ["small", 2]]
	if n >= 44:
		specs = [["main", 4], ["main", 4], ["mid", 2], ["small", 1]]
	elif n >= 25:
		specs = [["main", 2], ["mid", 2], ["small", 1]]
	_assign_by_weight_specs(mine, specs)

func _setup_fleets_chuang(mine: Array) -> void:
	## Cap 60 people, then tier by headcount (创.md). Prefer high PD DPS / tonnage / armor_link.
	mine.sort_custom(func(a, b):
		var wa := _chuang_pick_score(a)
		var wb := _chuang_pick_score(b)
		if wa != wb:
			return wa > wb
		return BoardTypes.tonnage_weight(a.get("tonnage", "destroyer")) > BoardTypes.tonnage_weight(b.get("tonnage", "destroyer"))
	)
	if mine.size() > 60:
		mine = mine.slice(0, 60)
	## Tier by headcount N after cap; ratio fill by tonnage weight (创.md).
	var n = mine.size()
	var specs: Array = [["small", 1]]
	if n >= 35:
		specs = [["attrition", 4], ["mid", 3], ["small", 1], ["attrition", 3]]
	elif n >= 20:
		specs = [["mid", 2], ["small", 1], ["attrition", 2]]
	elif n >= 10:
		specs = [["small", 2], ["attrition", 1]]
	_assign_by_weight_specs(mine, specs)

func _chuang_pick_score(u: Dictionary) -> float:
	var ton_w := float(BoardTypes.tonnage_weight(u.get("tonnage", "destroyer")))
	var pd := 0.0
	for g in u.get("pd", []):
		pd += float(g.get("damage", 0.0)) / maxf(float(g.get("cycle", 1.0)), 0.001)
	var link := 0.0
	if u.has("guard") and bool(u.get("guard", {}).get("has_link", false)):
		link = 50.0
	## Prefer high PD DPS and higher tonnage for attrition pools.
	return pd * 3.0 + ton_w * 10.0 + link

func _assign_by_weight_specs(mine: Array, specs: Array) -> void:
	var part_sum := 0
	for sp in specs:
		part_sum += int(sp[1])
	for i in specs.size():
		fleets.append({
			"id": i,
			"role": str(specs[i][0]),
			"share": float(specs[i][1]) / float(maxi(part_sum, 1)),
			"members": [],
			"weight": 0,
			"state": "station",
			"marker": "",
		})
	mine.sort_custom(func(a, b): return BoardTypes.tonnage_weight(a.get("tonnage", "destroyer")) > BoardTypes.tonnage_weight(b.get("tonnage", "destroyer")))
	for u in mine:
		if str(u.get("id", "")) == "":
			continue
		var best = 0
		var best_ratio = 999999.0
		for i in fleets.size():
			var share: float = float(fleets[i]["share"])
			var ratio := float(fleets[i]["weight"]) / maxf(share, 0.001)
			if ratio < best_ratio:
				best_ratio = ratio
				best = i
		var uid := str(u.get("id", ""))
		fleets[best]["members"].append(uid)
		u["fleet_id"] = best
		fleets[best]["weight"] = int(fleets[best]["weight"]) + BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
	## Keep empty fleets. Their share stays, so the next launch can fill the one under ratio.

func remove_member(uid: String, weight: int) -> bool:
	for f in fleets:
		var members: Array = f.get("members", [])
		var next: Array = []
		var hit := false
		for m in members:
			if str(m) == uid:
				hit = true
			else:
				next.append(m)
		if not hit:
			continue
		f["members"] = next
		f["weight"] = maxi(0, int(f.get("weight", 0)) - weight)
		return true
	return false

func accept_ship(u: Dictionary) -> void:
	## Launch fills the fleet most below its share. Do not reshuffle ships already in fleets.
	var uid := str(u.get("id", ""))
	if uid == "" or fleets.is_empty():
		return
	for f0 in fleets:
		for m0 in f0.get("members", []):
			if str(m0) == uid:
				return
	var best := 0
	var best_ratio := 999999.0
	for i in fleets.size():
		var share: float = float(fleets[i].get("share", 1.0))
		var ratio := float(int(fleets[i].get("weight", 0))) / maxf(share, 0.001)
		if ratio < best_ratio:
			best_ratio = ratio
			best = i
	fleets[best]["members"].append(uid)
	fleets[best]["weight"] = int(fleets[best].get("weight", 0)) + BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
	u["fleet_id"] = int(fleets[best].get("id", best))

func accept_ship_into(u: Dictionary, fid: int) -> bool:
	var uid := str(u.get("id", ""))
	if uid == "":
		return false
	for f0 in fleets:
		if (f0.get("members", []) as Array).has(uid):
			return true
	for f in fleets:
		if int(f.get("id", -1)) != fid:
			continue
		if not (f["members"] as Array).has(uid):
			f["members"].append(uid)
			f["weight"] = int(f.get("weight", 0)) + BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
		u["fleet_id"] = fid
		return true
	return false

func total_weight(units: Array) -> float:
	var w = 0.0
	for u in units:
		if int(u.get("faction", 0)) == faction and u.get("alive", false):
			w += BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
	return maxf(w, 1.0)

func _is_enemy_fac(fac: int) -> bool:
	if int(fac) == faction:
		return false
	var rels: Dictionary = dip.get("relations", {}).get(str(faction), {})
	var rel := str(rels.get(str(fac), "hostile"))
	return rel != "ally" and rel != "self"

func cell_enemy_weight(units: Array, sys: String, cell: int, my_total: float) -> float:
	var w = 0.0
	for u in units:
		if not u.get("alive", false):
			continue
		if not _is_enemy_fac(int(u["faction"])):
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
		if not _is_enemy_fac(int(u["faction"])):
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
	dip = diplomacy
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
		if state == "marker":
			continue
		var target = _pick_target(map, units, diplomacy, members, state, my_w)
		if target.is_empty():
			continue
		for u in members:
			if bool(u.get("garrison", false)):
				continue
			if bool(u.get("player_hold", false)):
				continue
			if u.get("phase", BoardTypes.MovePhase.IDLE) != BoardTypes.MovePhase.IDLE:
				continue
			if not (u.get("path", []) as Array).is_empty():
				continue
			if u.get("sys") == target["sys"] and int(u.get("cell")) == int(target["cell"]):
				continue
			orders.append({"unit_id": u["id"], "sys": target["sys"], "cell": target["cell"]})
	return orders

func _pick_target(map: BoardMapModel, units: Array, _diplomacy: Dictionary, members: Array, state: String, my_w: float) -> Dictionary:
	var lead: Dictionary = members[0]
	var sys: String = lead["sys"]
	var role := str(lead.get("fleet_role", ""))
	## Prefer fleet role from fleets table when available.
	for f in fleets:
		if (f.get("members", []) as Array).has(lead.get("id")) \
				or (f.get("members", []) as Array).has(str(lead.get("id", ""))):
			role = str(f.get("role", role))
			break
	if state == "hold_gate" and stolen_mode:
		return _nearest_empty_gate_toward_enemy(map, units, stolen_sys, my_w)
	if state == "attack_thief" and stolen_mode:
		for u in units:
			if not u.get("alive", false) or not _is_enemy_fac(int(u["faction"])):
				continue
			if u.get("sys") == stolen_sys and int(u.get("cell", -1)) == stolen_cell:
				return {"sys": stolen_sys, "cell": stolen_cell}
		for u in units:
			if u.get("alive", false) and _is_enemy_fac(int(u["faction"])) and u.get("sys") == stolen_sys:
				return {"sys": stolen_sys, "cell": int(u["cell"])}
	## Chuang attrition: dive hostile cells; prefer lower enemy weight nearby.
	if deputy_id == "chuang" and role == "attrition":
		var dive := _pick_attrition_cell(map, units, lead, my_w)
		if not dive.is_empty():
			return dive
	## Chuang mid/small: avoid enemies, capture unowned cells (same cell when possible).
	if deputy_id == "chuang" and (role == "mid" or role == "small"):
		var only_small := fleets.size() == 1 and role == "small"
		if only_small and _enemy_within_jumps(map, units, sys, 4):
			## Solo small acts as main when enemies within 4 jumps.
			role = "main"
		else:
			var cap := _pick_capture_cell(map, units, lead, my_w)
			if not cap.is_empty():
				return cap
	if role == "main" or (deputy_id != "chuang" and state != "hold_gate" and state != "attack_thief"):
		if system_has_enemy(units, sys, my_w):
			## 隔门对峙：已经在门上就地固守，不再改去另一扇门。
			if _cell_is_gate(map, sys, int(lead.get("cell", -1))):
				return {"sys": sys, "cell": int(lead.get("cell", -1))}
			return _pick_wait_gate(map, units, sys, my_w)
		var toward := _pick_enemy_system_gate(map, units, sys, my_w, int(lead.get("cell", -1)))
		if not toward.is_empty():
			return toward
	if state != "hold_gate" and state != "attack_thief" and system_has_enemy(units, sys, my_w):
		return _pick_wait_gate(map, units, sys, my_w)
	var home: String = str(lead.get("current_station", lead.get("home", "soular")))
	if home == "" or not map.systems.has(home):
		home = "soular"
	var sc = map.station_cell(home)
	if sc >= 0:
		return {"sys": home, "cell": sc}
	return {}

func _pick_attrition_cell(_map: BoardMapModel, units: Array, lead: Dictionary, my_w: float) -> Dictionary:
	var best := {}
	var best_score := INF
	var lead_sys := str(lead.get("sys", ""))
	for u in units:
		if not u.get("alive", false) or not _is_enemy_fac(int(u["faction"])):
			continue
		var esys := str(u.get("sys", ""))
		var ecell := int(u.get("cell", -1))
		var ew := cell_enemy_weight(units, esys, ecell, my_w)
		if ew <= 0.0:
			continue
		var score := ew
		if esys != lead_sys:
			score += 40.0
		if score < best_score:
			best_score = score
			best = {"sys": esys, "cell": ecell}
	return best

func _pick_capture_cell(map: BoardMapModel, units: Array, lead: Dictionary, my_w: float) -> Dictionary:
	## Prefer capturable cells without enemies; stay in-system first.
	var lead_sys := str(lead.get("sys", ""))
	var best := {}
	var best_score := INF
	for sid in map.systems.keys():
		if system_has_enemy(units, str(sid), my_w):
			continue
		for c in map.systems[sid]["cells"]:
			var kind := int(c.get("kind", -1))
			if kind == BoardTypes.CellKind.EMPTY:
				continue
			if int(c.get("owner", 0)) == faction:
				continue
			var ci := int(c.get("index", -1))
			if cell_enemy_weight(units, str(sid), ci, my_w) > 0.0:
				continue
			var score := 10.0
			if str(sid) != lead_sys:
				score += 30.0
			if kind == BoardTypes.CellKind.RESOURCE:
				score -= 2.0
			if score < best_score:
				best_score = score
				best = {"sys": str(sid), "cell": ci}
	return best

func _cell_is_gate(map: BoardMapModel, sys: String, cell: int) -> bool:
	if not map.systems.has(sys):
		return false
	var cells: Array = map.systems[sys]["cells"]
	if cell < 0 or cell >= cells.size():
		return false
	return int(cells[cell].get("kind", -1)) == BoardTypes.CellKind.GATE


func _nearest_enemy_system(map: BoardMapModel, units: Array, from_sys: String, my_w: float) -> String:
	var q: Array = [{"s": from_sys, "d": 0}]
	var seen: Dictionary = {from_sys: true}
	while not q.is_empty():
		var cur: Dictionary = q.pop_front()
		var sid := str(cur["s"])
		var dist := int(cur["d"])
		if dist > 0 and system_has_enemy(units, sid, my_w):
			return sid
		if dist >= 8 or not map.systems.has(sid):
			continue
		for c in map.systems[sid]["cells"]:
			if int(c.get("kind", -1)) != BoardTypes.CellKind.GATE:
				continue
			var nxt := str(c.get("gate_to", ""))
			if nxt == "" or seen.has(nxt) or not map.systems.has(nxt):
				continue
			seen[nxt] = true
			q.append({"s": nxt, "d": dist + 1})
	return ""


func _first_gate_toward(map: BoardMapModel, from_sys: String, dest_sys: String) -> int:
	var parent: Dictionary = {from_sys: ""}
	var q: Array = [from_sys]
	while not q.is_empty():
		var sid: String = q.pop_front()
		if sid == dest_sys:
			break
		if not map.systems.has(sid):
			continue
		for link in map.systems[sid]["links"]:
			var nxt := str(link)
			if parent.has(nxt):
				continue
			parent[nxt] = sid
			q.append(nxt)
	if dest_sys != from_sys and not parent.has(dest_sys):
		return -1
	var cur := dest_sys
	var prev := str(parent.get(cur, ""))
	while prev != "" and prev != from_sys:
		cur = prev
		prev = str(parent.get(cur, ""))
	if prev != from_sys:
		return -1
	for c in map.systems[from_sys]["cells"]:
		if int(c.get("kind", -1)) == BoardTypes.CellKind.GATE and str(c.get("gate_to", "")) == cur:
			return int(c.get("index", -1))
	return -1


func _paired_gate_cell(map: BoardMapModel, sys_id: String, from_sys: String) -> int:
	if not map.systems.has(sys_id):
		return -1
	for c in map.systems[sys_id]["cells"]:
		if int(c.get("kind", -1)) == BoardTypes.CellKind.GATE and str(c.get("gate_to", "")) == from_sys:
			return int(c.get("index", -1))
	return -1


func _pick_enemy_system_gate(map: BoardMapModel, units: Array, sys: String, my_w: float, lead_cell: int = -1) -> Dictionary:
	## Approach the nearest enemy system. On a passable gate, the order is the far 门后 cell — not the same local gate again.
	var dest := _nearest_enemy_system(map, units, sys, my_w)
	if dest == "":
		return {}
	var gi := _first_gate_toward(map, sys, dest)
	if gi < 0:
		return {}
	var far := ""
	for c in map.systems[sys]["cells"]:
		if int(c.get("index", -1)) == gi:
			far = str(c.get("gate_to", ""))
			break
	if lead_cell == gi and far != "" and map.can_pass_gate(sys, gi, faction, dip):
		var land := _paired_gate_cell(map, far, sys)
		if land >= 0:
			return {"sys": far, "cell": land}
	return {"sys": sys, "cell": gi}

func _enemy_within_jumps(map: BoardMapModel, units: Array, from_sys: String, max_j: int) -> bool:
	## BFS on gate graph up to max_j.
	var q: Array = [{"s": from_sys, "d": 0}]
	var seen: Dictionary = {from_sys: true}
	while not q.is_empty():
		var cur: Dictionary = q.pop_front()
		var sid := str(cur["s"])
		var d := int(cur["d"])
		if d > 0 and system_has_enemy(units, sid, 1.0):
			return true
		if d >= max_j or not map.systems.has(sid):
			continue
		for c in map.systems[sid]["cells"]:
			if int(c["kind"]) != BoardTypes.CellKind.GATE:
				continue
			var nxt := str(c.get("gate_to", ""))
			if nxt == "" or seen.has(nxt):
				continue
			seen[nxt] = true
			q.append({"s": nxt, "d": d + 1})
	return false

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
		if u.get("alive", false) and _is_enemy_fac(int(u["faction"])) and u.get("sys") == sys:
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
