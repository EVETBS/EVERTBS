extends RefCounted
class_name MpZoneSched
## Sim zones from occupation and unit factions, packed by measured throughput.
## Cold/hot only marks write rate. About 10% of cost is ticked twice; higher throughput publishes.

const HOT_MUL := 4.0
const GLOBAL_COST := 2.0
const OVERLAP := 0.10
const GLOBAL_IDS: Array[String] = ["clock", "victory", "diplo"]


static func partition(layout: Dictionary, owners: Dictionary, unit_facs: Dictionary) -> Array:
	var parent: Dictionary = {}
	var systems: Array = layout.get("systems", [])
	for s_v in systems:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var sid := str((s_v as Dictionary).get("id", ""))
		if sid != "":
			parent[sid] = sid
	for s_v2 in systems:
		if typeof(s_v2) != TYPE_DICTIONARY:
			continue
		var a := str((s_v2 as Dictionary).get("id", ""))
		if a == "":
			continue
		var links: Array = (s_v2 as Dictionary).get("links", [])
		for lk_v in links:
			var b := str(lk_v)
			if parent.has(b) and a < b:
				if _should_merge(a, b, owners, unit_facs):
					_union(parent, a, b)
	var groups: Dictionary = {}
	for sid_v in parent.keys():
		var root := _find(parent, str(sid_v))
		if not groups.has(root):
			groups[root] = []
		(groups[root] as Array).append(str(sid_v))
	var hot := contact_systems(layout, unit_facs)
	var zones: Array = []
	var roots: Array = groups.keys()
	roots.sort()
	for root_v in roots:
		var members: Array = groups[root_v]
		members.sort()
		var zid := "z:" + "|".join(PackedStringArray(members))
		var unit_n := 0
		var sov_n := 0
		var facs: Dictionary = {}
		var is_hot := false
		for m_v in members:
			var m := str(m_v)
			var uf: Array = _facs(unit_facs, m)
			unit_n += uf.size()
			for f_v in uf:
				facs[int(f_v)] = true
			sov_n += _sov_count(layout, m)
			if hot.has(m):
				is_hot = true
		var cost := float(unit_n + sov_n)
		if cost < 1.0:
			cost = 1.0
		if is_hot:
			cost *= HOT_MUL
		zones.append({
			"id": zid,
			"systems": members,
			"cost": cost,
			"hot": is_hot,
			"facs": facs.keys(),
		})
	_link_neighbors(layout, zones)
	return zones


static func contact_systems(layout: Dictionary, unit_facs: Dictionary) -> Dictionary:
	var hot: Dictionary = {}
	var systems: Array = layout.get("systems", [])
	for sid_v in unit_facs.keys():
		var facs := _facs(unit_facs, str(sid_v))
		if facs.size() >= 2:
			hot[str(sid_v)] = true
	for s_v in systems:
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var a := str((s_v as Dictionary).get("id", ""))
		if a == "":
			continue
		var fa := _facs(unit_facs, a)
		for lk_v in (s_v as Dictionary).get("links", []):
			var b := str(lk_v)
			if a >= b:
				continue
			var fb := _facs(unit_facs, b)
			if _different_pair(fa, fb):
				hot[a] = true
				hot[b] = true
	return hot


static func assign(zones: Array, peers: Array, previous: Dictionary, full_reset: bool, shift_zone: String) -> Dictionary:
	var weights: Array = []
	var peer_ids: Array = []
	for p_v in peers:
		if typeof(p_v) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_v
		peer_ids.append(int(p.get("id", 0)))
		weights.append(maxf(float(p.get("throughput", 1.0)), 0.001))
	var total := 0.0
	for z_v in zones:
		total += float((z_v as Dictionary).get("cost", 1.0))
	total += GLOBAL_COST * float(GLOBAL_IDS.size())
	var budgets := _largest_remainder(weights, total)
	var remaining: Dictionary = {}
	for i in range(peer_ids.size()):
		remaining[int(peer_ids[i])] = float(budgets[i])
	var primary: Dictionary = {}
	var kept: Dictionary = previous.get("primary", {}) if typeof(previous.get("primary", {})) == TYPE_DICTIONARY else {}
	if not full_reset:
		for z_v2 in zones:
			var zid := str((z_v2 as Dictionary).get("id", ""))
			if zid == shift_zone:
				continue
			var prev_id := int(kept.get(zid, 0))
			if prev_id != 0 and remaining.has(prev_id) and _peer_ok(peers, prev_id):
				primary[zid] = prev_id
				remaining[prev_id] = float(remaining[prev_id]) - float((z_v2 as Dictionary).get("cost", 1.0))
	var hot_zones: Array = []
	var cold_zones: Array = []
	for z_v3 in zones:
		var z3: Dictionary = z_v3
		if primary.has(str(z3.get("id", ""))):
			continue
		if bool(z3.get("hot", false)):
			hot_zones.append(z3)
		else:
			cold_zones.append(z3)
	_sort_cost(hot_zones)
	_sort_cost(cold_zones)
	for hz_v in hot_zones:
		var hz: Dictionary = hz_v
		var owner := _pick_hot(hz, peers, remaining, primary, zones)
		primary[str(hz.get("id", ""))] = owner
		if remaining.has(owner):
			remaining[owner] = float(remaining[owner]) - float(hz.get("cost", 1.0))
	var cold_tasks: Array = cold_zones.duplicate()
	for gid in GLOBAL_IDS:
		cold_tasks.append({"id": "g:" + gid, "cost": GLOBAL_COST, "hot": false, "global": true})
	_sort_cost(cold_tasks)
	var globals: Dictionary = {}
	for ct_v in cold_tasks:
		var ct: Dictionary = ct_v
		var owner2 := _pick_most_remaining(peers, remaining)
		var cid := str(ct.get("id", ""))
		if bool(ct.get("global", false)):
			globals[cid.trim_prefix("g:")] = owner2
		else:
			primary[cid] = owner2
		if remaining.has(owner2):
			remaining[owner2] = float(remaining[owner2]) - float(ct.get("cost", 1.0))
	var secondary := _overlap(zones, peers, primary, globals, remaining)
	return {"primary": primary, "secondary": secondary, "globals": globals}


static func vision(layout: Dictionary, sources: Array) -> Dictionary:
	var adj := _adj(layout)
	var seen: Dictionary = {}
	var q: Array = []
	for s_v in sources:
		var s := str(s_v)
		if s == "" or seen.has(s):
			continue
		seen[s] = 0
		q.append(s)
	var head := 0
	while head < q.size():
		var cur := str(q[head])
		head += 1
		var dist := int(seen[cur])
		if dist >= 4:
			continue
		for nb_v in adj.get(cur, []):
			var nb := str(nb_v)
			if seen.has(nb):
				continue
			seen[nb] = dist + 1
			q.append(nb)
	return seen


static func cold_phase_ms(zone_id: String) -> int:
	var h := zone_id.hash()
	if h < 0:
		h = -h
	return h % 1000


static func compare_rows(local_rows: Array, remote_rows: Array, eps: float) -> Dictionary:
	var remote: Dictionary = {}
	for r_v in remote_rows:
		if typeof(r_v) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = r_v
		remote[str(r.get("id", ""))] = r
	var checked := 0
	var matched := 0
	for l_v in local_rows:
		if typeof(l_v) != TYPE_DICTIONARY:
			continue
		var l: Dictionary = l_v
		var rid := str(l.get("id", ""))
		if not remote.has(rid):
			continue
		checked += 1
		var o: Dictionary = remote[rid]
		var lp: Array = l.get("pos", [0, 0, 0])
		var op: Array = o.get("pos", [0, 0, 0])
		var dx := float(lp[0] if lp.size() > 0 else 0) - float(op[0] if op.size() > 0 else 0)
		var dz := float(lp[2] if lp.size() > 2 else 0) - float(op[2] if op.size() > 2 else 0)
		var same_sys := str(l.get("sys", "")) == str(o.get("sys", ""))
		var same_hp := absf(float(l.get("hp", 0.0)) - float(o.get("hp", 0.0))) <= maxf(eps, 1.0)
		if same_sys and same_hp and dx * dx + dz * dz <= eps * eps:
			matched += 1
	return {"checked": checked, "matched": matched}


static func _overlap(zones: Array, peers: Array, primary: Dictionary, globals: Dictionary, remaining: Dictionary) -> Dictionary:
	var total := 0.0
	var ordered: Array = []
	for z_v in zones:
		var z: Dictionary = z_v
		total += float(z.get("cost", 1.0))
		ordered.append(z)
	total += GLOBAL_COST * float(GLOBAL_IDS.size())
	var budget := total * OVERLAP
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ah := 1 if bool(a.get("hot", false)) else 0
		var bh := 1 if bool(b.get("hot", false)) else 0
		if ah != bh:
			return ah > bh
		return float(a.get("cost", 0.0)) > float(b.get("cost", 0.0))
	)
	var secondary: Dictionary = {}
	for z2_v in ordered:
		if budget <= 0.0:
			break
		var z2: Dictionary = z2_v
		var zid := str(z2.get("id", ""))
		var cost := float(z2.get("cost", 1.0))
		var first := int(primary.get(zid, 0))
		var second := _pick_other(peers, remaining, first)
		if second == 0 or second == first:
			continue
		secondary[zid] = second
		remaining[second] = float(remaining.get(second, 0.0)) - cost
		budget -= cost
	for gid in GLOBAL_IDS:
		if budget <= 0.0:
			break
		var gfirst := int(globals.get(gid, 0))
		var gsecond := _pick_other(peers, remaining, gfirst)
		if gsecond == 0 or gsecond == gfirst:
			continue
		secondary["g:" + gid] = gsecond
		budget -= GLOBAL_COST
	return secondary


static func _pick_hot(zone: Dictionary, peers: Array, remaining: Dictionary, primary: Dictionary, zones: Array) -> int:
	var zfacs: Array = zone.get("facs", [])
	var neighbors: Array = zone.get("neighbors", [])
	var taken: Dictionary = {}
	for nb_v in neighbors:
		var nb := str(nb_v)
		if primary.has(nb):
			taken[int(primary[nb])] = true
	var combatants: Array = []
	for p_v in peers:
		var p: Dictionary = p_v
		if bool(p.get("spectate", false)):
			continue
		if _intersects(p.get("facs", []), zfacs):
			combatants.append(p)
	var pool: Array = combatants
	var any_room := false
	for c_v in combatants:
		if float(remaining.get(int((c_v as Dictionary).get("id", 0)), 0.0)) > 0.0:
			any_room = true
			break
	if combatants.is_empty() or not any_room:
		pool = peers
	var best := 0
	var best_score := 1.0e18
	for p2_v in pool:
		var p2: Dictionary = p2_v
		var pid := int(p2.get("id", 0))
		if pid == 0:
			continue
		var rtt := _rtt_to_others(p2, pool)
		var score := rtt
		if taken.has(pid):
			score += 100000.0
		if float(remaining.get(pid, 0.0)) <= 0.0:
			score += 50000.0
		if score < best_score or (is_equal_approx(score, best_score) and (best == 0 or pid < best)):
			best_score = score
			best = pid
	if best == 0:
		best = _pick_most_remaining(peers, remaining)
	return best


static func _rtt_to_others(peer: Dictionary, pool: Array) -> float:
	var rtt: Dictionary = peer.get("rtt", {})
	var pid := int(peer.get("id", 0))
	var sum := 0.0
	var n := 0
	for o_v in pool:
		var oid := int((o_v as Dictionary).get("id", 0))
		if oid == 0 or oid == pid:
			continue
		sum += float(rtt.get(oid, rtt.get(str(oid), 80.0)))
		n += 1
	if n == 0:
		return 80.0
	return sum / float(n)


static func _pick_most_remaining(peers: Array, remaining: Dictionary) -> int:
	var best := 0
	var best_left := -1.0e18
	for p_v in peers:
		var pid := int((p_v as Dictionary).get("id", 0))
		var left := float(remaining.get(pid, 0.0))
		if left > best_left or (is_equal_approx(left, best_left) and (best == 0 or pid < best)):
			best_left = left
			best = pid
	return best


static func _pick_other(peers: Array, remaining: Dictionary, avoid: int) -> int:
	var best := 0
	var best_left := -1.0e18
	for p_v in peers:
		var pid := int((p_v as Dictionary).get("id", 0))
		if pid == 0 or pid == avoid:
			continue
		var left := float(remaining.get(pid, 0.0))
		if left > best_left or (is_equal_approx(left, best_left) and (best == 0 or pid < best)):
			best_left = left
			best = pid
	return best


static func _largest_remainder(weights: Array, total: float) -> Array:
	var sum_w := 0.0
	for w_v in weights:
		sum_w += float(w_v)
	if sum_w <= 0.0:
		sum_w = 1.0
	var target := maxi(int(round(total)), weights.size())
	var raw: Array = []
	var floors: Array = []
	var used := 0
	for w_v2 in weights:
		var q := float(w_v2) / sum_w * float(target)
		raw.append(q)
		var fl := int(floor(q))
		floors.append(fl)
		used += fl
	var left := target - used
	var guard := 0
	while left > 0 and guard < 10000:
		guard += 1
		var best_i := 0
		var best_frac := -1.0
		for i in range(raw.size()):
			var frac := float(raw[i]) - float(floors[i])
			if frac > best_frac:
				best_frac = frac
				best_i = i
		floors[best_i] = int(floors[best_i]) + 1
		raw[best_i] = float(floors[best_i])
		left -= 1
	return floors


static func _sort_cost(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := float(a.get("cost", 0.0))
		var cb := float(b.get("cost", 0.0))
		if not is_equal_approx(ca, cb):
			return ca > cb
		return str(a.get("id", "")) < str(b.get("id", ""))
	)


static func _should_merge(a: String, b: String, owners: Dictionary, unit_facs: Dictionary) -> bool:
	var fa := _facs(unit_facs, a)
	var fb := _facs(unit_facs, b)
	if _intersects(fa, fb):
		return true
	var oa := int(owners.get(a, 0))
	var ob := int(owners.get(b, 0))
	var ua := not fa.is_empty()
	var ub := not fb.is_empty()
	if ua and ub and oa != ob:
		return true
	var qa := oa != 0 and not _foreign(oa, fa)
	var qb := ob != 0 and not _foreign(ob, fb)
	if qa and qb and oa == ob:
		return true
	if oa == 0 and ob == 0 and not ua and not ub:
		return true
	return false


static func _foreign(owner: int, facs: Array) -> bool:
	for f_v in facs:
		if int(f_v) != owner:
			return true
	return false


static func _intersects(a_v: Variant, b_v: Variant) -> bool:
	var a: Array = a_v if a_v is Array else []
	var b: Array = b_v if b_v is Array else []
	for x_v in a:
		if b.has(x_v) or b.has(int(x_v)):
			return true
	return false


static func _different_pair(a: Array, b: Array) -> bool:
	for x_v in a:
		for y_v in b:
			if int(x_v) != int(y_v):
				return true
	return false


static func _facs(unit_facs: Dictionary, sid: String) -> Array:
	var raw: Variant = unit_facs.get(sid, [])
	if raw is Array:
		return raw
	return []


static func _sov_count(layout: Dictionary, sid: String) -> int:
	for s_v in layout.get("systems", []):
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		if str((s_v as Dictionary).get("id", "")) != sid:
			continue
		var n := 0
		for c_v in (s_v as Dictionary).get("cells", []):
			if typeof(c_v) != TYPE_DICTIONARY:
				continue
			if int((c_v as Dictionary).get("kind", -1)) == BoardTypes.CellKind.SOV:
				n += 1
		return n
	return 0


static func _link_neighbors(layout: Dictionary, zones: Array) -> void:
	var sys_zone: Dictionary = {}
	for z_v in zones:
		var z: Dictionary = z_v
		for s_v in z.get("systems", []):
			sys_zone[str(s_v)] = str(z.get("id", ""))
	var neigh: Dictionary = {}
	for s2_v in layout.get("systems", []):
		if typeof(s2_v) != TYPE_DICTIONARY:
			continue
		var a := str((s2_v as Dictionary).get("id", ""))
		var za := str(sys_zone.get(a, ""))
		if za == "":
			continue
		for lk_v in (s2_v as Dictionary).get("links", []):
			var zb := str(sys_zone.get(str(lk_v), ""))
			if zb == "" or zb == za:
				continue
			if not neigh.has(za):
				neigh[za] = {}
			(neigh[za] as Dictionary)[zb] = true
	for z2_v in zones:
		var z2: Dictionary = z2_v
		var bag: Dictionary = neigh.get(str(z2.get("id", "")), {})
		z2["neighbors"] = bag.keys()


static func _adj(layout: Dictionary) -> Dictionary:
	var adj: Dictionary = {}
	for s_v in layout.get("systems", []):
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		var a := str((s_v as Dictionary).get("id", ""))
		if a == "":
			continue
		if not adj.has(a):
			adj[a] = []
		for lk_v in (s_v as Dictionary).get("links", []):
			var b := str(lk_v)
			if b == "":
				continue
			if not (adj[a] as Array).has(b):
				(adj[a] as Array).append(b)
			if not adj.has(b):
				adj[b] = []
			if not (adj[b] as Array).has(a):
				(adj[b] as Array).append(a)
	return adj


static func _find(parent: Dictionary, x: String) -> String:
	var p := str(parent.get(x, x))
	if p != x:
		parent[x] = _find(parent, p)
		return str(parent[x])
	return x


static func _union(parent: Dictionary, a: String, b: String) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


static func _peer_ok(peers: Array, pid: int) -> bool:
	for p_v in peers:
		if int((p_v as Dictionary).get("id", 0)) == pid:
			return true
	return false
