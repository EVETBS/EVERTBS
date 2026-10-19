extends RefCounted
class_name BoardAiController

var faction = 2
var deputy_id := "yang"
var fleets: Array = []
var stolen_mode = false
var stolen_sys = ""
var stolen_cell = -1
var dip: Dictionary = {}
var _gather_sys := ""
var _gather_cell := -1
var shortage_lines: Array = []
var shortage_sent: Dictionary = {}
var bubble_ships: Dictionary = {}
var bubble_stock: Dictionary = {}

const LACK_SHIELD := "\u76fe\u5b88\u8230\u961f"
const LACK_RAID := "\u62a2\u5360\u8230\u961f"
const LACK_TAC := "\u6218\u672f\u4e3b\u529b\u8230\u961f"


func setup_fleets(units: Array, only_ids: Dictionary = {}) -> void:
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
	shortage_lines = []
	if mine.is_empty():
		return
	mine = _cap60(mine)
	if deputy_id == "chuang":
		_setup_fleets_chuang(mine)
	elif deputy_id == "six":
		_setup_fleets_six(mine)
	elif deputy_id == "bei":
		_setup_fleets_bei(mine)
	elif deputy_id == "i":
		_setup_fleets_i(mine)
	else:
		_setup_fleets_yang(mine)


func _cap60(mine: Array) -> Array:
	var rows: Array = mine.duplicate()
	rows.sort_custom(func(a, b):
		return str(a.get("pilot_id", a.get("id", ""))) < str(b.get("pilot_id", b.get("id", "")))
	)
	if rows.size() > 60:
		return rows.slice(0, 60)
	return rows


func _new_fleet(i: int, role: String, share: float) -> Dictionary:
	return {
		"id": i,
		"role": role,
		"share": share,
		"members": [],
		"weight": 0,
		"state": "station",
		"marker": "",
		"pilot_ids": [],
		"seen_pilots": [],
		"appoint": "",
		"lock_home": false,
		"rear_sys": "",
		"rear_cell": -1,
		"rear_track": "",
		"rear_hot": false,
		"rear_was_hot": false,
		"prev_alive": 0,
		"wait_out": false,
		"wait_pilots": [],
		"req_pilot": "",
		"req_shield": "",
	}


func _place(f: Dictionary, u: Dictionary) -> void:
	var uid := str(u.get("id", ""))
	var pid := str(u.get("pilot_id", ""))
	if uid != "" and not (f["members"] as Array).has(uid):
		f["members"].append(uid)
		f["weight"] = int(f["weight"]) + BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
		u["fleet_id"] = int(f["id"])
	if pid != "":
		if not (f["pilot_ids"] as Array).has(pid):
			f["pilot_ids"].append(pid)
		if not (f["seen_pilots"] as Array).has(pid):
			f["seen_pilots"].append(pid)


func _already(uid: String) -> bool:
	if uid == "":
		return false
	for f in fleets:
		if (f["members"] as Array).has(uid):
			return true
	return false


func _create_from_specs(specs: Array) -> void:
	var part_sum := 0
	for sp in specs:
		part_sum += int(sp[1])
	for i in specs.size():
		var share := float(specs[i][1]) / float(maxi(part_sum, 1))
		fleets.append(_new_fleet(fleets.size(), str(specs[i][0]), share))


func _fill_lowest(mine: Array) -> void:
	var rows: Array = mine.duplicate()
	rows.sort_custom(func(a, b):
		return BoardTypes.tonnage_weight(a.get("tonnage", "destroyer")) > BoardTypes.tonnage_weight(b.get("tonnage", "destroyer"))
	)
	for u in rows:
		var uid := str(u.get("id", ""))
		if uid == "" or _already(uid) or fleets.is_empty():
			continue
		var best := 0
		var best_ratio := 999999.0
		for i in fleets.size():
			var ratio := float(fleets[i]["weight"]) / maxf(float(fleets[i]["share"]), 0.001)
			if ratio < best_ratio:
				best_ratio = ratio
				best = i
		_place(fleets[best], u)


func _assign_by_weight_specs(mine: Array, specs: Array) -> void:
	_create_from_specs(specs)
	_fill_lowest(mine)


func _setup_fleets_yang(mine: Array) -> void:
	var n := mine.size()
	var specs: Array = [["main", 1], ["small", 2]]
	if n >= 44:
		specs = [["main", 4], ["main", 4], ["mid", 2], ["small", 1]]
	elif n >= 25:
		specs = [["main", 2], ["mid", 2], ["small", 1]]
	_assign_by_weight_specs(mine, specs)
	for f in fleets:
		f["appoint"] = "link"


func _setup_fleets_chuang(mine: Array) -> void:
	var n := mine.size()
	var specs: Array = [["small", 1]]
	if n >= 35:
		specs = [["attrition", 4], ["mid", 3], ["small", 1], ["attrition", 3]]
	elif n >= 20:
		specs = [["mid", 2], ["small", 1], ["attrition", 2]]
	elif n >= 10:
		specs = [["small", 2], ["attrition", 1]]
	_assign_by_weight_specs(mine, specs)
	for f in fleets:
		if str(f["role"]) == "attrition":
			f["appoint"] = "link"


func _anyone(mine: Array, key: String) -> bool:
	for u in mine:
		if bool(u.get(key, false)):
			return true
	return false


func _note_shortage(key: String, label: String) -> void:
	if shortage_sent.has(key):
		return
	shortage_sent[key] = true
	shortage_lines.append("\u7f3a\u4e4f\u7ec4\u6210[%s]\u6240\u9700\u5173\u952e\u8239\u578b\uff0c\u6539\u4e3a\u7ec4\u4e3b\u529b\u8230\u961f\u3002" % label)


func _clear_shortage(key: String) -> void:
	shortage_sent.erase(key)


func _setup_fleets_six(mine: Array) -> void:
	var n := mine.size()
	var specs: Array = [["small", 1]]
	if n >= 35:
		specs = [["main", 4], ["mid", 3], ["small", 1], ["shield", 3]]
	elif n >= 20:
		specs = [["mid", 2], ["small", 1], ["shield", 2]]
	elif n >= 10:
		specs = [["small", 2], ["shield", 1]]
	var wants_shield := false
	for sp in specs:
		if str(sp[0]) == "shield":
			wants_shield = true
	if wants_shield and not _anyone(mine, "can_shield"):
		for i in specs.size():
			if str(specs[i][0]) == "shield":
				specs[i][0] = "main"
		_note_shortage("shield", LACK_SHIELD)
	elif wants_shield:
		_clear_shortage("shield")
	_create_from_specs(specs)
	_seed_shield(mine)
	_fill_lowest(mine)
	for f in fleets:
		if str(f["role"]) == "shield":
			f["appoint"] = "shield"


func _seed_shield(mine: Array) -> void:
	var total_w := 0
	for u in mine:
		if str(u.get("id", "")) != "":
			total_w += BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
	for f in fleets:
		if str(f["role"]) != "shield":
			continue
		var target := float(total_w) * float(f["share"])
		var field_budget := target / 3.0
		var fields: Array = []
		var longs: Array = []
		for u in mine:
			if str(u.get("id", "")) == "" or _already(str(u.get("id", ""))):
				continue
			if bool(u.get("has_shield", false)):
				fields.append(u)
			elif bool(u.get("has_range", false)):
				longs.append(u)
		for u2 in fields:
			if float(f["weight"]) >= field_budget:
				break
			if _already(str(u2.get("id", ""))):
				continue
			_place(f, u2)
		for u3 in longs:
			if float(f["weight"]) >= target:
				break
			if _already(str(u3.get("id", ""))):
				continue
			_place(f, u3)


func _setup_fleets_bei(mine: Array) -> void:
	var people: Array = mine.duplicate()
	people.sort_custom(func(a, b):
		var ga := bool(a.get("can_gila", false))
		var gb := bool(b.get("can_gila", false))
		if ga != gb:
			return ga and not gb
		return str(a.get("pilot_id", "")) < str(b.get("pilot_id", ""))
	)
	var n := people.size()
	if n < 10:
		_assign_by_weight_specs(people, [["small", 1]])
		return
	var raid_n := 0
	var raid_fleets := 1
	if n >= 40:
		raid_n = 20
		raid_fleets = 2
	elif n > 20:
		var k := int(n / 3)
		raid_n = k + (n - k * 3)
	else:
		raid_n = int((n + 1) / 2)
	var gila_n := 0
	for gp in people:
		if bool(gp.get("can_gila", false)):
			gila_n += 1
	var raid_role := "raid"
	if raid_n > 0 and gila_n <= 0:
		raid_role = "main"
		_note_shortage("raid", LACK_RAID)
	else:
		_clear_shortage("raid")
		if gila_n > 0:
			raid_fleets = mini(raid_fleets, gila_n)
	var raid_people: Array = people.slice(0, raid_n)
	var rest: Array = people.slice(raid_n, people.size())
	for i in raid_fleets:
		var share := 1.0 / float(maxi(raid_fleets, 1))
		var f := _new_fleet(fleets.size(), raid_role, share)
		f["lock_home"] = true
		fleets.append(f)
	for i in raid_people.size():
		_place(fleets[i % raid_fleets], raid_people[i])
	if rest.is_empty():
		return
	var main_n := 1
	if n >= 40:
		main_n = mini(3, rest.size())
	for _jn in main_n:
		var mf := _new_fleet(fleets.size(), "main", 1.0 / float(main_n))
		mf["lock_home"] = true
		mf["appoint"] = "both"
		fleets.append(mf)
	var mains: Array = []
	for f2 in fleets:
		if str(f2["role"]) == "main" and bool(f2.get("lock_home", false)) and str(f2.get("appoint", "")) == "both":
			mains.append(f2)
	_lock_bei_mains(mains, rest)
	for f3 in mains:
		for u0 in rest:
			var p0 := str(u0.get("pilot_id", ""))
			if p0 == "" or (p0 != str(f3.get("req_pilot", "")) and p0 != str(f3.get("req_shield", ""))):
				continue
			if str(u0.get("id", "")) == "" or not _already(str(u0.get("id", ""))):
				_place(f3, u0)
	var rest_units: Array = rest.duplicate()
	rest_units.sort_custom(func(a, b): return float(a.get("pd_dps", 0.0)) > float(b.get("pd_dps", 0.0)))
	for u in rest_units:
		var pid_u := str(u.get("pilot_id", ""))
		if pid_u != "" and _pilot_taken(pid_u):
			continue
		if str(u.get("id", "")) != "" and _already(str(u.get("id", ""))):
			continue
		if mains.is_empty():
			break
		var best: Dictionary = mains[0]
		var best_ratio := 999999.0
		for mf2 in mains:
			var ratio := float(mf2["weight"]) / maxf(float(mf2["share"]), 0.001)
			if ratio < best_ratio:
				best_ratio = ratio
				best = mf2
		_place(best, u)


func _lock_bei_mains(mains: Array, rest: Array) -> void:
	var used: Dictionary = {}
	for f in mains:
		var shield_p := _first_flag(rest, "can_shield", used)
		var link_p := _first_flag(rest, "can_link", used)
		if shield_p != "":
			f["req_shield"] = shield_p
			used[shield_p] = true
		if link_p != "":
			f["req_pilot"] = link_p
			used[link_p] = true


func _first_flag(rows: Array, key: String, used: Dictionary) -> String:
	var best := ""
	for u in rows:
		var pid := str(u.get("pilot_id", ""))
		if pid == "" or used.has(pid) or not bool(u.get(key, false)):
			continue
		if best == "" or pid < best:
			best = pid
	return best


func _setup_fleets_i(mine: Array) -> void:
	var n := mine.size()
	var count := 1
	if n >= 45:
		count = 4
	elif n >= 30:
		count = 3
	elif n >= 15:
		count = 2
	var capable: Array = []
	for u in mine:
		if bool(u.get("can_bubble", false)):
			capable.append(u)
	capable.sort_custom(func(a, b):
		var ha := bool(a.get("has_bubble", false))
		var hb := bool(b.get("has_bubble", false))
		if ha != hb:
			return ha and not hb
		return str(a.get("pilot_id", "")) < str(b.get("pilot_id", ""))
	)
	var role := "tac_main"
	if capable.is_empty():
		role = "main"
		_note_shortage("tac", LACK_TAC)
	else:
		_clear_shortage("tac")
		count = mini(count, capable.size())
	var share := 1.0 / float(maxi(count, 1))
	for i in count:
		var f := _new_fleet(i, role, share)
		fleets.append(f)
		if role == "tac_main":
			f["appoint"] = "bubble"
			var cap: Dictionary = capable[i]
			f["req_pilot"] = str(cap.get("pilot_id", ""))
			_place(f, cap)
	_fill_lowest(mine)


func _pilot_taken(pid: String) -> bool:
	for f in fleets:
		if (f.get("pilot_ids", []) as Array).has(pid):
			return true
	return false


func _locked_fleet(pid: String) -> int:
	if pid == "":
		return -1
	for f in fleets:
		if bool(f.get("lock_home", false)) and (f.get("pilot_ids", []) as Array).has(pid):
			return int(f.get("id", -1))
	return -1


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


func _remember_pilot(f: Dictionary, u: Dictionary) -> void:
	var pid := str(u.get("pilot_id", ""))
	if pid == "" :
		return
	var seen: Array = f.get("seen_pilots", [])
	if not seen.has(pid):
		seen.append(pid)
		f["seen_pilots"] = seen


func accept_ship(u: Dictionary) -> void:
	var uid := str(u.get("id", ""))
	if uid == "" or fleets.is_empty():
		return
	for f0 in fleets:
		for m0 in f0.get("members", []):
			if str(m0) == uid:
				return
	var home := _locked_fleet(str(u.get("pilot_id", "")))
	if home >= 0 and accept_ship_into(u, home):
		return
	var best := 0
	var best_ratio := 999999.0
	for i in fleets.size():
		var ratio := float(int(fleets[i].get("weight", 0))) / maxf(float(fleets[i].get("share", 1.0)), 0.001)
		if ratio < best_ratio:
			best_ratio = ratio
			best = i
	fleets[best]["members"].append(uid)
	fleets[best]["weight"] = int(fleets[best].get("weight", 0)) + BoardTypes.tonnage_weight(u.get("tonnage", "destroyer"))
	u["fleet_id"] = int(fleets[best].get("id", best))
	_remember_pilot(fleets[best], u)


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
		_remember_pilot(f, u)
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
	dip = diplomacy
	var orders: Array = []
	_refresh_stolen(map)
	_update_rears(map, units)
	for f in fleets:
		if str(f.get("state", "")) == "marker":
			continue
		var members := _alive_members(f, units)
		_note_presence(f, members)
		if members.is_empty():
			continue
		orders.append_array(_orders_for_fleet(map, units, f, members))
	return orders


func _refresh_stolen(map: BoardMapModel) -> void:
	if not stolen_mode:
		return
	var still := false
	if map.systems.has(stolen_sys):
		var c: Dictionary = map.systems[stolen_sys]["cells"][stolen_cell]
		if int(c["owner"]) != faction:
			still = true
	if not still:
		stolen_mode = false
		for f in fleets:
			f["state"] = "station"


func _alive_members(f: Dictionary, units: Array) -> Array:
	var members: Array = []
	for uid in f.get("members", []):
		for u in units:
			if str(u.get("id", "")) == str(uid) and u.get("alive", false):
				members.append(u)
	return members


func _note_presence(f: Dictionary, members: Array) -> void:
	var n := members.size()
	if (deputy_id == "yang" or deputy_id == "six") and int(f.get("prev_alive", 0)) > 0 and n == 0 and not bool(f.get("wait_out", false)):
		f["wait_out"] = true
		f["wait_pilots"] = (f.get("seen_pilots", []) as Array).duplicate()
	f["prev_alive"] = n


func _orders_for_fleet(map: BoardMapModel, units: Array, f: Dictionary, members: Array) -> Array:
	var orders: Array = []
	var fw := maxf(float(f.get("weight", 1)), 1.0)
	var lead: Dictionary = members[0]
	var state := str(f.get("state", ""))
	var forced := _forced_target(map, units, f, members, state, fw)
	if not forced.is_empty():
		_push_moves(orders, members, forced, str(f.get("role", "")) != "raid", int(f.get("id", 0)), false)
		return orders
	var role := str(f.get("role", "main"))
	var sys := str(lead.get("sys", ""))
	var jumps := _enemy_jumps(map, units, sys, fw)
	if fleets.size() == 1 and role == "small" and jumps <= 4:
		role = "main"
	if (deputy_id == "yang" or deputy_id == "six") and jumps > 4:
		if role == "small":
			_push_spread(orders, map, units, members, sys, fw, 3, int(f.get("id", 0)))
		else:
			_push_moves(orders, members, _pick_capture_cell(map, units, lead, fw), true, int(f.get("id", 0)), false)
		return orders
	if (deputy_id == "yang" or deputy_id == "six") and role == "small" and jumps > 2:
		_push_spread(orders, map, units, members, sys, fw, 3, int(f.get("id", 0)))
		return orders
	if role == "attrition":
		_push_moves(orders, members, _pick_attrition_cell(map, units, lead, fw), true, int(f.get("id", 0)), false)
		return orders
	if role == "shield":
		_orders_shield(orders, map, units, f, members, fw)
		return orders
	if role == "raid":
		_orders_raid(orders, map, units, f, members, fw)
		return orders
	if role == "mid" or role == "small":
		_push_moves(orders, members, _pick_capture_cell(map, units, lead, fw), true, int(f.get("id", 0)), false)
		return orders
	if role == "tac_main" and _bubble_blocked(map, f, members):
		_orders_bubble_wait(orders, map, f, members)
		return orders
	_orders_main(orders, map, units, f, members, fw)
	return orders


func _forced_target(map: BoardMapModel, units: Array, f: Dictionary, members: Array, state: String, fw: float) -> Dictionary:
	var lead: Dictionary = members[0]
	if state == "hold_gate" and stolen_mode:
		return _nearest_empty_gate_toward_enemy(map, units, stolen_sys, fw)
	if state == "attack_thief" and stolen_mode:
		for u in units:
			if not u.get("alive", false) or not _is_enemy_fac(int(u["faction"])):
				continue
			if u.get("sys") == stolen_sys and int(u.get("cell", -1)) == stolen_cell:
				return {"sys": stolen_sys, "cell": stolen_cell}
		for u2 in units:
			if u2.get("alive", false) and _is_enemy_fac(int(u2["faction"])) and u2.get("sys") == stolen_sys:
				return {"sys": stolen_sys, "cell": int(u2["cell"])}
	if not _owns_station(map):
		var rally := _pick_homeless_order(map, units, members, fw)
		if not rally.is_empty():
			return rally
	if _sov_dominance_over_90(map):
		var sov := _pick_sov_capture_cell(map, units, lead, fw)
		if not sov.is_empty():
			return sov
	return {}


func _bubble_blocked(_map: BoardMapModel, f: Dictionary, members: Array) -> bool:
	var pid := str(f.get("req_pilot", ""))
	if pid == "":
		return false
	for u in members:
		if str(u.get("pilot_id", "")) != pid:
			continue
		return not bubble_ships.has(str(u.get("ship_id", "")))
	return true


func _orders_bubble_wait(orders: Array, map: BoardMapModel, f: Dictionary, members: Array) -> void:
	var lead: Dictionary = members[0]
	var station := _nearest_owned_station(map, str(lead.get("sys", "")))
	if station.is_empty():
		return
	var pid := str(f.get("req_pilot", ""))
	var fid := int(f.get("id", 0))
	if bubble_stock.has(pid):
		var found := false
		for u in members:
			if str(u.get("pilot_id", "")) != pid:
				continue
			found = true
			if str(u.get("sys", "")) == str(station["sys"]) and int(u.get("cell", -1)) == int(station["cell"]):
				orders.append({"unit_id": u["id"], "kind": "dock", "sys": station["sys"], "cell": station["cell"], "fleet_id": fid, "sync": true})
			else:
				_push_moves(orders, [u], station, true, fid, true)
		if found:
			return
	_push_moves(orders, members, station, true, fid, true)


func _orders_main(orders: Array, map: BoardMapModel, units: Array, f: Dictionary, members: Array, fw: float) -> void:
	var fid := int(f.get("id", 0))
	var lead: Dictionary = members[0]
	var sys := str(lead.get("sys", ""))
	if bool(f.get("rear_was_hot", false)) and not bool(f.get("rear_hot", false)):
		var cross := _cross_rear(map, f)
		if not cross.is_empty():
			_push_moves(orders, members, cross, true, fid, false)
			return
	if _standoff_active(map, units, f, fw):
		var rear := {"sys": str(f.get("rear_sys", "")), "cell": int(f.get("rear_cell", -1))}
		if str(rear["sys"]) != "" and int(rear["cell"]) >= 0:
			_push_moves(orders, members, rear, true, fid, false)
			return
	if system_has_enemy(units, sys, fw):
		if _cell_is_gate(map, sys, int(lead.get("cell", -1))):
			_push_moves(orders, members, {"sys": sys, "cell": int(lead.get("cell", -1))}, true, fid, false)
			return
		_push_moves(orders, members, _pick_wait_gate(map, units, sys, fw), true, fid, false)
		return
	var toward := _pick_enemy_system_gate(map, units, sys, fw, int(lead.get("cell", -1)))
	if not toward.is_empty():
		_push_moves(orders, members, toward, true, fid, false)
		return
	var home := str(lead.get("current_station", lead.get("home", "")))
	if home != "" and map.systems.has(home):
		var sc := map.station_cell(home)
		if sc >= 0:
			_push_moves(orders, members, {"sys": home, "cell": sc}, true, fid, false)


func _orders_shield(orders: Array, map: BoardMapModel, units: Array, f: Dictionary, members: Array, fw: float) -> void:
	var fid := int(f.get("id", 0))
	var lead: Dictionary = members[0]
	var sys := str(lead.get("sys", ""))
	var jumps := _enemy_jumps(map, units, sys, fw)
	if jumps == 0:
		if _cell_is_gate(map, sys, int(lead.get("cell", -1))):
			var park := _nearest_nongate(map, sys, int(lead.get("cell", -1)))
			if park >= 0:
				_push_moves(orders, members, {"sys": sys, "cell": park}, true, fid, true)
		var focus_cell := _nearest_enemy_cell(map, units, sys, int(lead.get("cell", -1)), fw)
		if focus_cell >= 0:
			_push_focus(orders, members, sys, focus_cell, fid)
		return
	if jumps == 1:
		var dest := _nearest_enemy_system(map, units, sys, fw)
		var gi := _gate_not_rear(map, sys, dest, int(f.get("rear_cell", -1)) if str(f.get("rear_sys", "")) == sys else -1)
		if gi >= 0:
			var adj := _adjacent_cell(map, sys, gi)
			_push_moves(orders, members, {"sys": sys, "cell": adj}, true, fid, true)
		return
	var toward := _pick_enemy_system_gate(map, units, sys, fw, int(lead.get("cell", -1)))
	_push_moves(orders, members, toward, true, fid, false)


func _orders_raid(orders: Array, map: BoardMapModel, units: Array, f: Dictionary, members: Array, fw: float) -> void:
	var fid := int(f.get("id", 0))
	var lead: Dictionary = members[0]
	var sys := str(lead.get("sys", ""))
	var jumps := _enemy_jumps(map, units, sys, fw)
	var station := _owned_station_cell(map, sys)
	if jumps == 0 and _system_has_capital(units, sys, fw):
		if station >= 0:
			for u in members:
				if str(u.get("sys", "")) == sys and int(u.get("cell", -1)) == station:
					orders.append({"unit_id": u["id"], "kind": "dock", "sys": sys, "cell": station, "fleet_id": fid, "sync": false})
				else:
					_push_moves(orders, [u], {"sys": sys, "cell": station}, false, fid, true)
			return
		var hop := _one_hop_toward_station(map, sys)
		if not hop.is_empty():
			_push_moves(orders, members, hop, false, fid, false)
			return
	if jumps == 0:
		if not _cell_is_gate(map, sys, int(lead.get("cell", -1))):
			_push_moves(orders, members, _pick_wait_gate(map, units, sys, fw), false, fid, false)
		else:
			_push_moves(orders, members, {"sys": sys, "cell": int(lead.get("cell", -1))}, false, fid, false)
		return
	if jumps == 1:
		var gate := _pick_enemy_system_gate(map, units, sys, fw, int(lead.get("cell", -1)))
		_push_moves(orders, members, gate, false, fid, false)
		return
	_push_spread(orders, map, units, members, sys, fw, 4, fid)


func _push_spread(orders: Array, map: BoardMapModel, units: Array, members: Array, sys: String, fw: float, group_size: int, fid: int) -> void:
	var rows: Array = members.duplicate()
	rows.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	var groups := ceili(float(rows.size()) / float(maxi(group_size, 1)))
	var spots := _collect_spots(map, units, sys, fw, groups)
	if spots.is_empty():
		return
	for i in rows.size():
		var spot: Dictionary = spots[int(i / maxi(group_size, 1)) % spots.size()]
		_push_moves(orders, [rows[i]], spot, false, fid, false)


func _collect_spots(map: BoardMapModel, units: Array, from_sys: String, fw: float, need: int) -> Array:
	var spots: Array = []
	var q: Array = [from_sys]
	var seen: Dictionary = {from_sys: true}
	while not q.is_empty() and spots.size() < need:
		var sid: String = q.pop_front()
		if not system_has_enemy(units, sid, fw):
			for ci in _raid_cells(map, units, sid):
				spots.append({"sys": sid, "cell": ci})
				if spots.size() >= need:
					break
		if not map.systems.has(sid):
			continue
		for link in map.systems[sid]["links"]:
			var nxt := str(link)
			if nxt == "" or seen.has(nxt) or not map.systems.has(nxt):
				continue
			seen[nxt] = true
			q.append(nxt)
	return spots


func _raid_cells(map: BoardMapModel, units: Array, sys: String) -> Array:
	var out: Array = []
	if not map.systems.has(sys):
		return out
	for c in map.systems[sys]["cells"]:
		var kind := int(c.get("kind", -1))
		if kind == BoardTypes.CellKind.EMPTY:
			continue
		if int(c.get("owner", 0)) == faction:
			continue
		var ci := int(c.get("index", -1))
		if _cell_has_big_sleeper(units, sys, ci):
			continue
		if _friendly_on_cell(units, sys, ci):
			continue
		out.append(ci)
	return out


func _cell_has_big_sleeper(units: Array, sys: String, cell: int) -> bool:
	for u in units:
		if not u.get("alive", false) or not bool(u.get("garrison", false)):
			continue
		if str(u.get("sys", "")) != sys or int(u.get("cell", -1)) != cell:
			continue
		var ton := str(u.get("tonnage", ""))
		if ton == "battlecruiser" or ton == "battleship":
			return true
	return false


func _friendly_on_cell(units: Array, sys: String, cell: int) -> bool:
	for u in units:
		if not u.get("alive", false) or bool(u.get("garrison", false)):
			continue
		if int(u.get("faction", -1)) != faction:
			continue
		if str(u.get("sys", "")) == sys and int(u.get("cell", -1)) == cell:
			return true
	return false


func _system_has_capital(units: Array, sys: String, fw: float) -> bool:
	for u in units:
		if not u.get("alive", false) or not _is_enemy_fac(int(u.get("faction", -1))):
			continue
		if str(u.get("sys", "")) != sys:
			continue
		var ton := str(u.get("tonnage", ""))
		if ton != "battlecruiser" and ton != "battleship":
			continue
		if cell_enemy_weight(units, sys, int(u.get("cell", -1)), fw) <= 0.0:
			continue
		return true
	return false


func _push_moves(orders: Array, members: Array, dest: Dictionary, sync_on: bool, fid: int, force_enter: bool) -> void:
	if dest.is_empty():
		return
	var sys := str(dest.get("sys", ""))
	var cell := int(dest.get("cell", -1))
	if sys == "" or cell < 0:
		return
	for u in members:
		if bool(u.get("garrison", false)) or bool(u.get("player_hold", false)):
			continue
		if int(u.get("phase", 0)) != BoardTypes.MovePhase.IDLE:
			continue
		if not (u.get("path", []) as Array).is_empty():
			continue
		var same := str(u.get("sys", "")) == sys and int(u.get("cell", -1)) == cell
		if same:
			orders.append({"unit_id": u["id"], "kind": "sync", "sync": sync_on, "fleet_id": fid, "sys": sys, "cell": cell})
			continue
		orders.append({
			"unit_id": u["id"], "kind": "move", "sys": sys, "cell": cell,
			"sync": sync_on, "fleet_id": fid, "force_enter": force_enter,
		})


func _push_focus(orders: Array, members: Array, sys: String, cell: int, fid: int) -> void:
	for u in members:
		if bool(u.get("garrison", false)):
			continue
		orders.append({"unit_id": u["id"], "kind": "focus", "sys": sys, "cell": cell, "fleet_id": fid})


func _update_rears(map: BoardMapModel, units: Array) -> void:
	for f in fleets:
		var sys := _common_sys(f, units)
		var prev := str(f.get("rear_track", ""))
		if sys != "" and prev != "" and prev != sys:
			var land := _paired_gate_cell(map, sys, prev)
			if land >= 0:
				f["rear_sys"] = sys
				f["rear_cell"] = land
		if sys != "":
			f["rear_track"] = sys
		var was := bool(f.get("rear_hot", false))
		var hot := false
		var rear := str(f.get("rear_sys", ""))
		if rear != "":
			hot = system_has_enemy(units, rear, maxf(float(f.get("weight", 1)), 1.0))
		f["rear_was_hot"] = was
		f["rear_hot"] = hot


func _common_sys(f: Dictionary, units: Array) -> String:
	var sys := ""
	var any := false
	for u in _alive_members(f, units):
		any = true
		var s := str(u.get("sys", ""))
		if sys == "":
			sys = s
		elif s != sys:
			return ""
	return sys if any else ""


func _standoff_active(map: BoardMapModel, units: Array, f: Dictionary, fw: float) -> bool:
	var rear := str(f.get("rear_sys", ""))
	if rear == "":
		return false
	var lead_sys := str(f.get("rear_track", rear))
	var enemy_sys := _nearest_enemy_system(map, units, lead_sys, fw)
	if enemy_sys == "":
		return false
	var station := _nearest_any_station_sys(map, enemy_sys)
	if station == "":
		return false
	return _path_systems(map, enemy_sys, station).has(rear)


func _cross_rear(map: BoardMapModel, f: Dictionary) -> Dictionary:
	var sys := str(f.get("rear_sys", ""))
	var cell := int(f.get("rear_cell", -1))
	if sys == "" or cell < 0 or not map.systems.has(sys):
		return {}
	var far := ""
	for c in map.systems[sys]["cells"]:
		if int(c.get("index", -1)) == cell:
			far = str(c.get("gate_to", ""))
	if far == "" or not map.systems.has(far):
		return {}
	var land := _paired_gate_cell(map, far, sys)
	if land < 0:
		return {}
	return {"sys": far, "cell": land}


func _path_systems(map: BoardMapModel, a: String, b: String) -> Array:
	var parent: Dictionary = {a: ""}
	var q: Array = [a]
	while not q.is_empty():
		var sid: String = q.pop_front()
		if sid == b:
			break
		if not map.systems.has(sid):
			continue
		for link in map.systems[sid]["links"]:
			var nxt := str(link)
			if parent.has(nxt) or not map.systems.has(nxt):
				continue
			parent[nxt] = sid
			q.append(nxt)
	if a != b and not parent.has(b):
		return []
	var out: Array = []
	var cur := b
	while cur != "":
		out.append(cur)
		if cur == a:
			break
		cur = str(parent.get(cur, ""))
	return out


func _nearest_any_station_sys(map: BoardMapModel, from_sys: String) -> String:
	var q: Array = [from_sys]
	var seen: Dictionary = {from_sys: true}
	while not q.is_empty():
		var sid: String = q.pop_front()
		if _system_station_cell(map, sid) >= 0:
			return sid
		if not map.systems.has(sid):
			continue
		for link in map.systems[sid]["links"]:
			var nxt := str(link)
			if nxt == "" or seen.has(nxt) or not map.systems.has(nxt):
				continue
			seen[nxt] = true
			q.append(nxt)
	return ""


func _nearest_owned_station(map: BoardMapModel, from_sys: String) -> Dictionary:
	var q: Array = [from_sys]
	var seen: Dictionary = {from_sys: true}
	while not q.is_empty():
		var sid: String = q.pop_front()
		var cell := _owned_station_cell(map, sid)
		if cell >= 0:
			return {"sys": sid, "cell": cell}
		if not map.systems.has(sid):
			continue
		for link in map.systems[sid]["links"]:
			var nxt := str(link)
			if nxt == "" or seen.has(nxt) or not map.systems.has(nxt):
				continue
			seen[nxt] = true
			q.append(nxt)
	return {}


func _one_hop_toward_station(map: BoardMapModel, sys: String) -> Dictionary:
	var dest := ""
	var q: Array = [sys]
	var parent: Dictionary = {sys: ""}
	while not q.is_empty():
		var sid: String = q.pop_front()
		if sid != sys and _owned_station_cell(map, sid) >= 0:
			dest = sid
			break
		if not map.systems.has(sid):
			continue
		for link in map.systems[sid]["links"]:
			var nxt := str(link)
			if parent.has(nxt) or not map.systems.has(nxt):
				continue
			parent[nxt] = sid
			q.append(nxt)
	if dest == "":
		return {}
	var cur := dest
	var prev := str(parent.get(cur, ""))
	while prev != "" and prev != sys:
		cur = prev
		prev = str(parent.get(cur, ""))
	if prev != sys:
		return {}
	var land := _paired_gate_cell(map, cur, sys)
	if land < 0:
		return {}
	return {"sys": cur, "cell": land}


func _owned_station_cell(map: BoardMapModel, sys: String) -> int:
	if not map.systems.has(sys):
		return -1
	for c in map.systems[sys]["cells"]:
		if int(c.get("kind", -1)) == BoardTypes.CellKind.STATION and int(c.get("owner", 0)) == faction:
			return int(c.get("index", -1))
	return -1


func _system_station_cell(map: BoardMapModel, sys: String) -> int:
	if not map.systems.has(sys):
		return -1
	for c in map.systems[sys]["cells"]:
		if int(c.get("kind", -1)) == BoardTypes.CellKind.STATION:
			return int(c.get("index", -1))
	return -1


func _adjacent_cell(map: BoardMapModel, sys: String, cell: int) -> int:
	if not map.systems.has(sys):
		return cell
	var n: int = map.systems[sys]["cells"].size()
	if n <= 1:
		return cell
	return (cell + 1) % n


func _nearest_nongate(map: BoardMapModel, sys: String, near_cell: int) -> int:
	if not map.systems.has(sys):
		return -1
	var n: int = map.systems[sys]["cells"].size()
	var best := -1
	var best_d := 999
	for c in map.systems[sys]["cells"]:
		if int(c.get("kind", -1)) == BoardTypes.CellKind.GATE:
			continue
		var ci := int(c.get("index", -1))
		var d := BoardTypes.shorter_arc_steps(near_cell, ci, n)
		if d < best_d:
			best_d = d
			best = ci
	return best


func _nearest_enemy_cell(map: BoardMapModel, units: Array, sys: String, from_cell: int, fw: float) -> int:
	if not map.systems.has(sys):
		return -1
	var n: int = map.systems[sys]["cells"].size()
	var best := -1
	var best_d := 999
	for u in units:
		if not u.get("alive", false) or not _is_enemy_fac(int(u.get("faction", -1))):
			continue
		if str(u.get("sys", "")) != sys:
			continue
		var ci := int(u.get("cell", -1))
		if cell_enemy_weight(units, sys, ci, fw) <= 0.0:
			continue
		var d := BoardTypes.shorter_arc_steps(from_cell, ci, n)
		if d < best_d:
			best_d = d
			best = ci
	return best


func _gate_not_rear(map: BoardMapModel, sys: String, dest: String, rear_cell: int) -> int:
	var gi := _first_gate_toward(map, sys, dest)
	if gi < 0 or gi != rear_cell:
		return gi
	if not map.systems.has(sys):
		return gi
	for c in map.systems[sys]["cells"]:
		if int(c.get("kind", -1)) != BoardTypes.CellKind.GATE:
			continue
		var ci := int(c.get("index", -1))
		if ci != rear_cell:
			return ci
	return gi


func _enemy_jumps(map: BoardMapModel, units: Array, from_sys: String, fw: float) -> int:
	if from_sys == "":
		return 99
	if system_has_enemy(units, from_sys, fw):
		return 0
	var q: Array = [{"s": from_sys, "d": 0}]
	var seen: Dictionary = {from_sys: true}
	while not q.is_empty():
		var cur: Dictionary = q.pop_front()
		var sid := str(cur["s"])
		var dist := int(cur["d"])
		if dist > 0 and system_has_enemy(units, sid, fw):
			return dist
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
	return 99


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


func _owns_station(map: BoardMapModel) -> bool:
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c.get("kind", -1)) != BoardTypes.CellKind.STATION:
				continue
			if int(c.get("owner", 0)) == faction:
				return true
	return false


func _pick_homeless_order(map: BoardMapModel, units: Array, members: Array, _my_w: float) -> Dictionary:
	if not _fleets_share_system(units):
		_ensure_gather_point(map, units)
		if _gather_sys != "":
			return {"sys": _gather_sys, "cell": _gather_cell}
	else:
		_gather_sys = ""
		_gather_cell = -1
	return _quietest_station(map, units, members[0] if not members.is_empty() else {})


func _fleets_share_system(units: Array) -> bool:
	var sys := ""
	var any := false
	for f in fleets:
		for uid in f.get("members", []):
			for u in units:
				if str(u.get("id", "")) != str(uid) or not u.get("alive", false):
					continue
				any = true
				var s := str(u.get("sys", ""))
				if sys == "":
					sys = s
				elif s != sys:
					return false
	return any


func _ensure_gather_point(map: BoardMapModel, units: Array) -> void:
	if _gather_sys != "" and map.systems.has(_gather_sys):
		return
	var counts: Dictionary = {}
	var cell_of: Dictionary = {}
	for f in fleets:
		for uid in f.get("members", []):
			for u in units:
				if str(u.get("id", "")) != str(uid) or not u.get("alive", false):
					continue
				var s := str(u.get("sys", ""))
				counts[s] = int(counts.get(s, 0)) + 1
				if not cell_of.has(s):
					cell_of[s] = int(u.get("cell", 0))
	var best := ""
	var best_n := -1
	for s in counts.keys():
		if int(counts[s]) > best_n:
			best_n = int(counts[s])
			best = str(s)
	_gather_sys = best
	_gather_cell = int(cell_of.get(best, 0))


func _quietest_station(map: BoardMapModel, units: Array, lead: Dictionary) -> Dictionary:
	var best := {}
	var best_enemies := INF
	var lead_sys := str(lead.get("sys", ""))
	for sid in map.systems.keys():
		var station_cell := _system_station_cell(map, str(sid))
		if station_cell < 0:
			continue
		var enemies := 0
		for u in units:
			if not u.get("alive", false) or not _is_enemy_fac(int(u.get("faction", -1))):
				continue
			if str(u.get("sys", "")) == str(sid):
				enemies += 1
		var score := float(enemies)
		if str(sid) != lead_sys:
			score += 0.25
		if score < best_enemies:
			best_enemies = score
			best = {"sys": str(sid), "cell": station_cell}
	return best


func _sov_dominance_over_90(map: BoardMapModel) -> bool:
	var total := 0
	var by_fac: Dictionary = {}
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c.get("kind", -1)) != BoardTypes.CellKind.SOV:
				continue
			total += 1
			var ow := int(c.get("owner", 0))
			if ow == 0:
				continue
			by_fac[ow] = int(by_fac.get(ow, 0)) + 1
	if total <= 0:
		return false
	for k in by_fac.keys():
		if float(by_fac[k]) / float(total) > 0.90:
			return true
	return false


func _pick_sov_capture_cell(map: BoardMapModel, units: Array, lead: Dictionary, my_w: float) -> Dictionary:
	var lead_sys := str(lead.get("sys", ""))
	var best := {}
	var best_score := INF
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c.get("kind", -1)) != BoardTypes.CellKind.SOV:
				continue
			if int(c.get("owner", 0)) == faction:
				continue
			var ci := int(c.get("index", -1))
			if cell_enemy_weight(units, str(sid), ci, my_w) > 0.0:
				continue
			var score := 5.0
			if str(sid) != lead_sys:
				score += 20.0
			if score < best_score:
				best_score = score
				best = {"sys": str(sid), "cell": ci}
	return best


func _pick_capture_cell(map: BoardMapModel, units: Array, lead: Dictionary, my_w: float) -> Dictionary:
	var lead_sys := str(lead.get("sys", ""))
	var best := {}
	var best_score := INF
	var sov_prio := _sov_dominance_over_90(map)
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
			if sov_prio and kind == BoardTypes.CellKind.SOV:
				score -= 50.0
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


func _pick_wait_gate(map: BoardMapModel, units: Array, sys: String, my_w: float) -> Dictionary:
	if not map.systems.has(sys):
		return {}
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
	for c2 in map.systems[sys]["cells"]:
		if int(c2["kind"]) == BoardTypes.CellKind.GATE:
			return {"sys": sys, "cell": int(c2["index"])}
	return {}


func _nearest_empty_gate_toward_enemy(map: BoardMapModel, units: Array, sys: String, my_w: float) -> Dictionary:
	if not map.systems.has(sys):
		return {}
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
		if cell_enemy_weight(units, sys, gi, my_w) > 0.0:
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
	for c2 in map.systems[sys]["cells"]:
		if int(c2["kind"]) == BoardTypes.CellKind.GATE:
			return {"sys": sys, "cell": int(c2["index"])}
	return {"sys": sys, "cell": 0}


func redistribute_resources(map: BoardMapModel, pilots: Array, rng: RandomNumberGenerator) -> void:
	BoardResourceAssign.ai_redistribute(map, pilots, faction, rng)
