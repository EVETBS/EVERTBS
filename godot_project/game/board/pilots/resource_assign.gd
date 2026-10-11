extends RefCounted
class_name BoardResourceAssign

## Resource cell ↔ pilot assignment helpers.

static func unlock_need(data: BoardData, ton: String) -> int:
	var table: Dictionary = data.equipment.get("tonnage_resource_unlock", {})
	return int(table.get(ton, 0))

static func reduction_per_point(data: BoardData) -> float:
	return float(data.equipment.get("resource_build_time_reduction_per_point", 0.05))

static func reduction_cap(data: BoardData) -> float:
	return float(data.equipment.get("build_time_reduction_cap", 0.99))

static func pilot_held_count(map: BoardMapModel, pilot_id: String) -> int:
	var n := 0
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c["kind"]) != BoardTypes.CellKind.RESOURCE:
				continue
			if str(c.get("assigned_pilot_id", "")) == pilot_id:
				n += 1
	return n

static func list_held_cells(map: BoardMapModel, pilot_id: String) -> Array:
	var out: Array = []
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c["kind"]) != BoardTypes.CellKind.RESOURCE:
				continue
			if str(c.get("assigned_pilot_id", "")) == pilot_id:
				out.append({"sys": sid, "cell": int(c["index"])})
	return out

static func list_unassigned_owned(map: BoardMapModel, faction: int) -> Array:
	## Strict empty only (no assignee).
	var out: Array = []
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c["kind"]) != BoardTypes.CellKind.RESOURCE:
				continue
			if int(c["owner"]) != faction:
				continue
			if str(c.get("assigned_pilot_id", "")) != "":
				continue
			out.append({"sys": sid, "cell": int(c["index"])})
	return out

static func list_pool_owned(map: BoardMapModel, faction: int, exclude_pilot: String = "") -> Array:
	## 待分配池: empty OR auto_assigned.
	## exclude_pilot: omit that pilot's auto cells (for + take / max — avoid double-count with held).
	## Pass exclude_pilot="" to list ALL auto as free (submenu 待分配 display).
	var out: Array = []
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c["kind"]) != BoardTypes.CellKind.RESOURCE:
				continue
			if int(c["owner"]) != faction:
				continue
			var ap := str(c.get("assigned_pilot_id", ""))
			var auto := bool(c.get("auto_assigned", false))
			if ap == "":
				out.append({"sys": sid, "cell": int(c["index"])})
			elif auto and (exclude_pilot == "" or ap != exclude_pilot):
				out.append({"sys": sid, "cell": int(c["index"])})
	return out

static func pool_counts(map: BoardMapModel, faction: int, exclude_pilot: String = "") -> Dictionary:
	## {empty, auto, total} for debug / HUD.
	var empty_n := 0
	var auto_n := 0
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c["kind"]) != BoardTypes.CellKind.RESOURCE:
				continue
			if int(c["owner"]) != faction:
				continue
			var ap := str(c.get("assigned_pilot_id", ""))
			var auto := bool(c.get("auto_assigned", false))
			if ap == "":
				empty_n += 1
			elif auto and (exclude_pilot == "" or ap != exclude_pilot):
				auto_n += 1
	return {"empty": empty_n, "auto": auto_n, "total": empty_n + auto_n}

static func max_assignable(map: BoardMapModel, pilot: Dictionary) -> int:
	var pid := str(pilot["id"])
	var held := pilot_held_count(map, pid)
	## Take-pool excludes own auto (already inside held).
	var free := list_pool_owned(map, int(pilot["faction"]), pid).size()
	return held + free

static func set_target_count(map: BoardMapModel, pilot: Dictionary, target: int, rng: RandomNumberGenerator, admin: BoardAdminProxy = null) -> int:
	var pid: String = pilot["id"]
	var fac: int = int(pilot["faction"])
	target = clampi(target, 0, max_assignable(map, pilot))
	var held := list_held_cells(map, pid)
	var cur := held.size()
	if target > cur:
		var free := list_pool_owned(map, fac, pid)
		_shuffle(free, rng)
		var need := target - cur
		for i in mini(need, free.size()):
			var ref: Dictionary = free[i]
			var c: Dictionary = map.systems[ref["sys"]]["cells"][ref["cell"]]
			c["assigned_pilot_id"] = pid
			c["last_assignee"] = pid
			c["auto_assigned"] = false
	elif target < cur:
		## Prefer releasing auto_assigned first so they return to 待分配 cleanly.
		held.sort_custom(func(a, b):
			var ca: Dictionary = map.systems[a["sys"]]["cells"][a["cell"]]
			var cb: Dictionary = map.systems[b["sys"]]["cells"][b["cell"]]
			var aa := 1 if bool(ca.get("auto_assigned", false)) else 0
			var bb := 1 if bool(cb.get("auto_assigned", false)) else 0
			return aa > bb
		)
		var drop := cur - target
		for i in drop:
			var ref2: Dictionary = held[i]
			var c2: Dictionary = map.systems[ref2["sys"]]["cells"][ref2["cell"]]
			c2["assigned_pilot_id"] = ""
			c2["auto_assigned"] = false
	if admin:
		admin.request("pilot.assign_resource", {"pilot": pid, "count": pilot_held_count(map, pid)})
	return pilot_held_count(map, pid)

static func effective_build_s(data: BoardData, map: BoardMapModel, pilot: Dictionary, base_s: float, ton: String) -> Dictionary:
	## Returns {ok, build_s, held, unlock, effective_points, reduction}
	var held := pilot_held_count(map, str(pilot["id"]))
	var unlock := unlock_need(data, ton)
	if held < unlock:
		return {
			"ok": false,
			"build_s": base_s,
			"held": held,
			"unlock": unlock,
			"effective_points": 0,
			"reduction": 0.0,
		}
	var eff_pts := maxi(0, held - unlock)
	var red := minf(reduction_cap(data), float(eff_pts) * reduction_per_point(data))
	return {
		"ok": true,
		"build_s": base_s * (1.0 - red),
		"held": held,
		"unlock": unlock,
		"effective_points": eff_pts,
		"reduction": red,
	}

static func on_resource_owner_flip(map: BoardMapModel, flip: Dictionary, pilots: Array) -> void:
	if int(flip.get("kind", -1)) != BoardTypes.CellKind.RESOURCE:
		return
	var sid: String = flip["sys"]
	var ci: int = int(flip["cell"])
	var c: Dictionary = map.systems[sid]["cells"][ci]
	var new_owner: int = int(flip["owner"])
	var last: String = str(flip.get("last_assignee", c.get("last_assignee", "")))
	if last == "":
		return
	# Auto-return to last assignee if still same faction
	for p in pilots:
		if str(p["id"]) != last:
			continue
		if int(p["faction"]) != new_owner:
			return
		c["assigned_pilot_id"] = last
		c["last_assignee"] = last
		c["auto_assigned"] = true
		return

static func ai_redistribute(map: BoardMapModel, pilots: Array, faction: int, rng: RandomNumberGenerator) -> void:
	var mine: Array = []
	for p in pilots:
		if int(p["faction"]) == faction:
			mine.append(p)
	if mine.is_empty():
		return
	var free := list_unassigned_owned(map, faction)
	_shuffle(free, rng)
	if free.is_empty():
		return
	# Round-robin to balance counts
	mine.sort_custom(func(a, b): return pilot_held_count(map, a["id"]) < pilot_held_count(map, b["id"]))
	var idx := 0
	for ref in free:
		var p: Dictionary = mine[idx % mine.size()]
		var c: Dictionary = map.systems[ref["sys"]]["cells"][ref["cell"]]
		c["assigned_pilot_id"] = p["id"]
		c["last_assignee"] = p["id"]
		c["auto_assigned"] = true
		idx += 1
		mine.sort_custom(func(a, b): return pilot_held_count(map, a["id"]) < pilot_held_count(map, b["id"]))

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func auto_assign_new_cell(map: BoardMapModel, flip: Dictionary, pilots: Array, rng: RandomNumberGenerator) -> void:
	## On capture: randomly assign THIS cell to a same-faction pilot.
	## Never touches cells that already have assigned_pilot_id.
	if int(flip.get("kind", -1)) != BoardTypes.CellKind.RESOURCE:
		return
	var sid: String = flip["sys"]
	var ci: int = int(flip["cell"])
	var c: Dictionary = map.systems[sid]["cells"][ci]
	if str(c.get("assigned_pilot_id", "")) != "":
		return
	var fac: int = int(flip.get("owner", c.get("owner", 0)))
	if fac == 0:
		return
	# Prefer last_assignee if still same faction
	var last: String = str(c.get("last_assignee", ""))
	if last != "":
		for p in pilots:
			if str(p["id"]) == last and int(p["faction"]) == fac:
				c["assigned_pilot_id"] = last
				c["auto_assigned"] = true
				return
	var mine: Array = []
	for p in pilots:
		if int(p["faction"]) == fac:
			mine.append(p)
	if mine.is_empty():
		return
	# Balance: pick among pilots with lowest held count
	mine.sort_custom(func(a, b): return pilot_held_count(map, a["id"]) < pilot_held_count(map, b["id"]))
	var best = pilot_held_count(map, mine[0]["id"])
	var pool: Array = []
	for p in mine:
		if pilot_held_count(map, p["id"]) <= best:
			pool.append(p)
	var pick: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	c["assigned_pilot_id"] = pick["id"]
	c["last_assignee"] = pick["id"]
	c["auto_assigned"] = true
