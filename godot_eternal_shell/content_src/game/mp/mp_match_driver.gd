extends RefCounted
class_name MpMatchDriver
## Zone ownership, cold/hot write cadence, fog vision, and the one-minute cheat check.

var board: Node = null
var net: MpCampaignNet = null
var fog_on := false
var vision: Dictionary = {}
var assign: Dictionary = {}
var zone_of: Dictionary = {}
var zones: Array = []
var _flow_acc := 0.0
var _shift := ""
var _hot_acc := 0.0
var _full_acc := 0.0
var _cold_acc: Dictionary = {}
var _contact_acc := 0.0
var _zone_time := 0.0
var _over_budget := 0
var _sig := ""
var _applying := false
var _audit_peer := 0
var _audit_until := 0
var _audit_checked := 0
var _audit_matched := 0
var _audit_slice: Dictionary = {}
var _audit_ready: Dictionary = {}
var _close_scheduled := false
var _last_owner_ms: Dictionary = {}
var _lerp_ms := 80
var _targets: Dictionary = {}
var _vision_acc := 0.0
var _shift_i := 0


func attach(host: Node) -> void:
	board = host
	var gs := host.get_node_or_null("/root/GameSession/MpCampaignNet")
	if gs is MpCampaignNet:
		net = gs
	else:
		net = null
	fog_on = bool(board.map.layout.get("fog_of_war", false)) if board.map != null else false
	if net == null:
		_refresh_vision()
		return
	if not net.zone_received.is_connected(_on_zone):
		net.zone_received.connect(_on_zone)
	if not net.order_received.is_connected(_on_order):
		net.order_received.connect(_on_order)
	if not net.group_received.is_connected(_on_group):
		net.group_received.connect(_on_group)
	if not net.deputy_received.is_connected(_on_deputy):
		net.deputy_received.connect(_on_deputy)
	if not net.diplo_received.is_connected(_on_diplo):
		net.diplo_received.connect(_on_diplo)
	if not net.fog_received.is_connected(_on_fog):
		net.fog_received.connect(_on_fog)
	if not net.match_over_received.is_connected(_on_match_over):
		net.match_over_received.connect(_on_match_over)
	if not net.audit_sample.is_connected(_on_audit_sample):
		net.audit_sample.connect(_on_audit_sample)
	if not net.chat_received.is_connected(_on_chat):
		net.chat_received.connect(_on_chat)
	if not net.assignment_updated.is_connected(_on_assignment):
		net.assignment_updated.connect(_on_assignment)
	if not net.peers_changed.is_connected(_on_peers_changed):
		net.peers_changed.connect(_on_peers_changed)
	if not net.diplo_offer_received.is_connected(_on_diplo_offer):
		net.diplo_offer_received.connect(_on_diplo_offer)
	if not net.host_lost.is_connected(_on_host_lost):
		net.host_lost.connect(_on_host_lost)
	_apply_saved_progress()
	if int(board.viewer_faction) <= 0:
		fog_on = false
	if net.is_host:
		_recompute(true)
	else:
		_pull_assignment()


func active() -> bool:
	return net != null and net.match_started


func block_dev() -> bool:
	return active()


func sim_unit(u: Dictionary) -> bool:
	if not active():
		return true
	var primary: Dictionary = assign.get("primary", {})
	if primary.is_empty():
		return net.is_host
	var sid := str(u.get("sys", ""))
	var zid := str(zone_of.get(sid, ""))
	if zid == "":
		return net.is_host
	var me := _me()
	var secondary: Dictionary = assign.get("secondary", {})
	if int(primary.get(zid, 0)) == me or int(secondary.get(zid, 0)) == me:
		return true
	if _audit_peer != 0 and Time.get_ticks_msec() < _audit_until and _audit_slice.has(zid) and _audit_ready.has(zid):
		return true
	return false


func owns_global(name: String) -> bool:
	if not active():
		return true
	var globals: Dictionary = assign.get("globals", {})
	var secondary: Dictionary = assign.get("secondary", {})
	var me := _me()
	return int(globals.get(name, 0)) == me or int(secondary.get("g:" + name, 0)) == me


func fog_hides_unit(u: Dictionary) -> bool:
	if not fog_on:
		return false
	if int(u.get("faction", 0)) == int(board.viewer_faction):
		return false
	return not vision.has(str(u.get("sys", "")))


func fog_blocks_arc(sid: String) -> bool:
	if not fog_on:
		return false
	if sim_system(sid):
		return false
	return not vision.has(sid)


func ai_units(faction: int, units: Array) -> Array:
	if not fog_on:
		return units
	var seen := _vision_for(faction)
	var out: Array = []
	for u_v in units:
		if typeof(u_v) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = u_v
		if int(u.get("faction", 0)) == faction or seen.has(str(u.get("sys", ""))):
			out.append(u)
	return out


func before_capture() -> Dictionary:
	var saved: Dictionary = {}
	if not active() or board.map == null:
		return saved
	for sid_v in board.map.systems.keys():
		var sid := str(sid_v)
		if sim_system(sid):
			continue
		var cells: Array = []
		for c_v in board.map.systems[sid]["cells"]:
			if typeof(c_v) == TYPE_DICTIONARY:
				cells.append(int((c_v as Dictionary).get("owner", 0)))
		saved[sid] = cells
	return saved


func after_capture(saved: Dictionary) -> void:
	if board.map == null:
		return
	for sid_v in saved.keys():
		var sid := str(sid_v)
		if not board.map.systems.has(sid):
			continue
		var owners: Array = saved[sid]
		var cells: Array = board.map.systems[sid]["cells"]
		for i in range(mini(owners.size(), cells.size())):
			cells[i]["owner"] = int(owners[i])


func sim_system(sid: String) -> bool:
	if not active():
		return true
	var zid := str(zone_of.get(sid, ""))
	if zid == "":
		return true
	var me := _me()
	return int(assign.get("primary", {}).get(zid, 0)) == me or int(assign.get("secondary", {}).get(zid, 0)) == me


func tick(delta: float) -> void:
	if board == null:
		return
	if net != null and net.host_gone:
		board.sim_paused = true
		return
	if fog_on:
		_vision_acc += delta
		if _vision_acc >= 0.2:
			_vision_acc = 0.0
			_refresh_vision()
	if _audit_peer != 0 and Time.get_ticks_msec() >= _audit_until:
		board._chat_append("核对 %d 条，一致 %d 条" % [_audit_checked, _audit_matched])
		_audit_peer = 0
	if not active():
		return
	var t0 := Time.get_ticks_usec()
	if net.is_host:
		_contact_acc += delta
		if _contact_acc >= 1.0:
			_contact_acc = 0.0
			_maybe_reassign()
		_flow_acc += delta
		if _flow_acc >= 30.0:
			_flow_acc = 0.0
			_shift_one()
	_hot_acc += delta
	_full_acc += delta
	if _hot_acc >= 0.1:
		_hot_acc = 0.0
		_publish(true, false)
	if _full_acc >= 2.0:
		_full_acc = 0.0
		_publish(true, true)
	_publish_cold(delta)
	_lerp_remote(delta)
	var me := _me()
	var load_ms := 0.0
	for z_v in zones:
		var zid := str((z_v as Dictionary).get("id", ""))
		if int(assign.get("primary", {}).get(zid, 0)) == me:
			load_ms += float((z_v as Dictionary).get("cost", 1.0))
	_zone_time = float(Time.get_ticks_usec() - t0) / 1000.0
	net.note_zone_ms(_zone_time)
	var share := _my_share()
	if share > 0.0 and _zone_time > share * 1000.0:
		_over_budget += 1
	else:
		_over_budget = 0


func on_path(u: Dictionary, to_sys: String, to_cell: int) -> void:
	if not active() or _applying:
		return
	var zid := str(zone_of.get(str(u.get("sys", "")), ""))
	var owner := int(assign.get("primary", {}).get(zid, 0))
	net.send_order(str(u.get("id", "")), to_sys, to_cell, owner)


func on_group(unit_id: String, group_id: int) -> void:
	if not active() or _applying:
		return
	net.send_group(unit_id, group_id)


func on_deputy(faction: int, group_id: int) -> void:
	if not active() or _applying:
		return
	net.send_deputy(faction, group_id)


func on_diplo(a: int, b: int, on: bool) -> void:
	if not active() or _applying:
		return
	net.send_diplo(a, b, on)


func offer_diplo(from_fac: int, to_fac: int) -> void:
	if not active() or _applying:
		return
	net.send_diplo_offer(from_fac, to_fac)


func on_match_end(winner: int, reason: String) -> void:
	if not active():
		return
	if owns_global("victory"):
		net.send_match_over(winner, reason)


func after_settlement() -> void:
	if _close_scheduled or net == null or board == null:
		return
	_close_scheduled = true
	var tree: SceneTree = board.get_tree()
	if tree == null:
		net.close_match()
		return
	tree.create_timer(1.0).timeout.connect(_close_after_settle)


func _close_after_settle() -> void:
	if net != null:
		net.close_match()


func _on_host_lost() -> void:
	if board == null:
		return
	board.sim_paused = true
	board._chat_append("与房主断开")


func set_fog(on: bool) -> void:
	if active() and net != null and not net.is_host:
		net.send_fog(on)
		return
	fog_on = on
	if board.map != null:
		board.map.layout["fog_of_war"] = on
	_refresh_vision()
	if board.starmap_view != null:
		board.starmap_view.fog_mask = _fog_mask()
		board.starmap_view._rebuild_territory()
	_save_prefs(on)
	if active():
		if net.is_host:
			net.send_fog(on)
		else:
			net.send_fog(on)


func start_audit(target_peer: int, target_nick: String) -> void:
	if not active():
		return
	_audit_peer = target_peer
	_audit_until = Time.get_ticks_msec() + 60000
	_audit_checked = 0
	_audit_matched = 0
	_audit_ready.clear()
	_audit_slice = _slice_for(target_peer)
	net.request_audit(target_peer)
	var me := str(net.local_nick)
	board._chat_append("%s：你怀疑%s作弊？这可是很严肃的指控，我核查一下。" % [me, target_nick])


func audit_text() -> String:
	if _audit_peer == 0:
		return ""
	if Time.get_ticks_msec() < _audit_until:
		return "核查中"
	return "核对 %d 条，一致 %d 条" % [_audit_checked, _audit_matched]


func _slice_for(peer_id: int) -> Dictionary:
	var rows: Array = []
	for z_v in zones:
		var z: Dictionary = z_v
		if int(assign.get("primary", {}).get(str(z.get("id", "")), 0)) != peer_id:
			continue
		rows.append(z)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ah := 1 if bool(a.get("hot", false)) else 0
		var bh := 1 if bool(b.get("hot", false)) else 0
		if ah != bh:
			return ah > bh
		return float(a.get("cost", 0.0)) > float(b.get("cost", 0.0))
	)
	var total := 0.0
	for z2_v in rows:
		total += float((z2_v as Dictionary).get("cost", 0.0))
	var budget := total * 0.10
	var out: Dictionary = {}
	for z3_v in rows:
		if budget <= 0.0 and not out.is_empty():
			break
		var z3: Dictionary = z3_v
		out[str(z3.get("id", ""))] = true
		budget -= float(z3.get("cost", 0.0))
	return out


func _absorb_audit_baseline(rows: Array) -> bool:
	var fresh: Dictionary = {}
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var zid := str(zone_of.get(str(row.get("sys", "")), ""))
		if not _audit_slice.has(zid) or _audit_ready.has(zid):
			continue
		fresh[zid] = true
		var u: Dictionary = _ensure_unit(row)
		if u.is_empty():
			continue
		if bool(row.get("alive", true)):
			u["sys"] = str(row.get("sys", u.get("sys", "")))
			u["cell"] = int(row.get("cell", u.get("cell", 0)))
			var pos: Array = row.get("pos", [])
			if pos.size() >= 3:
				var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
				u["pos"] = at
				_targets[str(u.get("id", ""))] = at
		u["alive"] = bool(row.get("alive", true))
		_write_hull(u, row)
	for zid_v in fresh.keys():
		_audit_ready[str(zid_v)] = true
	return not fresh.is_empty()


func _on_audit_sample(rows: Array) -> void:
	if _audit_peer == 0:
		return
	if _absorb_audit_baseline(rows):
		return
	if _audit_ready.is_empty():
		return
	var hit := false
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var sample: Dictionary = row_v
		var sample_zid := str(zone_of.get(str(sample.get("sys", "")), ""))
		if _audit_slice.has(sample_zid) and _audit_ready.has(sample_zid):
			hit = true
			break
	if not hit:
		return
	var local: Array = []
	for u_v in board.units:
		if typeof(u_v) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = u_v
		var zid := str(zone_of.get(str(u.get("sys", "")), ""))
		if not _audit_slice.has(zid) or not _audit_ready.has(zid):
			continue
		var pos: Vector3 = u.get("pos", Vector3.ZERO)
		var inst_v: Variant = u.get("inst", {})
		var inst: Dictionary = inst_v if typeof(inst_v) == TYPE_DICTIONARY else {}
		var hp := float(inst.get("shield", 0.0)) + float(inst.get("armor", 0.0)) + float(inst.get("structure", 0.0))
		local.append({
			"id": str(u.get("id", "")),
			"sys": str(u.get("sys", "")),
			"hp": hp,
			"pos": [pos.x, pos.y, pos.z],
		})
	var cmp: Dictionary = MpZoneSched.compare_rows(local, rows, 4.0)
	_audit_checked = int(cmp.get("checked", 0))
	_audit_matched = int(cmp.get("matched", 0))


func _publish(hot_only: bool, full: bool) -> void:
	var me := _me()
	for z_v in zones:
		var z: Dictionary = z_v
		var zid := str(z.get("id", ""))
		var is_hot := bool(z.get("hot", false))
		if hot_only and not is_hot:
			continue
		if not _should_publish(zid):
			continue
		var reliable := not (is_hot and not full)
		var pkt := _packet(z, full or not is_hot, reliable)
		net.set_assignment(assign)
		net.send_zone(pkt, is_hot and not full)
		_last_owner_ms[zid] = Time.get_ticks_msec()


func _publish_cold(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for z_v in zones:
		var z: Dictionary = z_v
		if bool(z.get("hot", false)):
			continue
		var zid := str(z.get("id", ""))
		if not _should_publish(zid):
			continue
		var phase := MpZoneSched.cold_phase_ms(zid)
		var acc := float(_cold_acc.get(zid, 0.0)) + delta
		_cold_acc[zid] = acc
		var gate := 1.0 + float(phase) / 1000.0
		if acc < gate:
			continue
		_cold_acc[zid] = acc - gate
		if now - int(_last_owner_ms.get(zid, 0)) < 400 and not _is_primary(zid):
			continue
		net.set_assignment(assign)
		net.send_zone(_packet(z, true, true), false)
		_last_owner_ms[zid] = now


func _should_publish(zid: String) -> bool:
	if (assign.get("primary", {}) as Dictionary).is_empty() and not net.is_host:
		return false
	var me := _me()
	var primary := int(assign.get("primary", {}).get(zid, 0))
	var secondary := int(assign.get("secondary", {}).get(zid, 0))
	if primary == me:
		return true
	if secondary != me:
		return false
	var silent := Time.get_ticks_msec() - int(_last_owner_ms.get(zid, 0))
	return silent > 1500


func _is_primary(zid: String) -> bool:
	return int(assign.get("primary", {}).get(zid, 0)) == _me()


func _packet(zone: Dictionary, with_arcs: bool, with_kills: bool = false) -> Dictionary:
	var systems: Array = zone.get("systems", [])
	var want: Dictionary = {}
	for s_v in systems:
		want[str(s_v)] = true
	var units: Array = []
	var presence: Dictionary = {}
	for u_v in board.units:
		if typeof(u_v) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = u_v
		var sid := str(u.get("sys", ""))
		if not want.has(sid):
			continue
		if not presence.has(sid):
			presence[sid] = {"owner": _owner_of(sid), "facs": [], "owners": []}
		var fac := int(u.get("faction", 0))
		if bool(u.get("alive", false)) and not (presence[sid]["facs"] as Array).has(fac):
			(presence[sid]["facs"] as Array).append(fac)
		var pos: Vector3 = u.get("pos", Vector3.ZERO)
		var inst_v: Variant = u.get("inst", {})
		var inst: Dictionary = inst_v if typeof(inst_v) == TYPE_DICTIONARY else {}
		var shield := float(inst.get("shield", 0.0))
		var armor := float(inst.get("armor", 0.0))
		var structure := float(inst.get("structure", 0.0))
		units.append({
			"id": str(u.get("id", "")),
			"sys": sid,
			"cell": int(u.get("cell", 0)),
			"hp": shield + armor + structure,
			"shield": shield,
			"armor": armor,
			"structure": structure,
			"max_s": float(inst.get("max_s", shield)),
			"max_a": float(inst.get("max_a", armor)),
			"max_h": float(inst.get("max_h", structure)),
			"alive": bool(u.get("alive", false)),
			"phase": int(u.get("phase", 0)),
			"pos": [pos.x, pos.y, pos.z],
			"faction": fac,
			"ship_id": str(u.get("ship_id", "")),
			"pilot_id": str(u.get("pilot_id", "")),
			"garrison": bool(u.get("garrison", false)),
		})
	for sid_v in want.keys():
		var sid_s := str(sid_v)
		if not presence.has(sid_s):
			presence[sid_s] = {"owner": _owner_of(sid_s), "facs": [], "owners": []}
		var owners: Array = []
		if board.map != null and board.map.systems.has(sid_s):
			for c_v in board.map.systems[sid_s]["cells"]:
				if typeof(c_v) == TYPE_DICTIONARY:
					owners.append(int((c_v as Dictionary).get("owner", 0)))
		presence[sid_s]["owners"] = owners
	var kills: Array = []
	if with_kills:
		kills = board._mp_take_kills(want)
	var arcs: Dictionary = {}
	if with_arcs and board.map != null:
		for sid2_v in want.keys():
			var sid2 := str(sid2_v)
			var weights: Array = []
			for c_v in board.map.systems[sid2]["cells"]:
				weights.append(float((c_v as Dictionary).get("weight", 1.0)))
			arcs[sid2] = weights
	var pkt: Dictionary = {
		"zone": str(zone.get("id", "")),
		"owner": _me(),
		"hot": bool(zone.get("hot", false)),
		"units": units,
		"presence": presence,
		"arcs": arcs,
		"kills": kills,
		"vision": _all_faction_vision(),
		"sim_clock": float(board._sim_clock) if owns_global("clock") else null,
		"diplomacy": board.data.diplomacy if owns_global("diplo") and board.data != null else null,
	}
	if with_kills and owns_global("victory"):
		var occupy: Dictionary = {}
		for fac_v in board.match_stats.keys():
			var stat_v: Variant = board.match_stats[fac_v]
			var stat: Dictionary = stat_v if typeof(stat_v) == TYPE_DICTIONARY else {}
			occupy[str(fac_v)] = float(stat.get("occupy_score", 0.0))
		pkt["occupy"] = occupy
	return pkt


func _on_zone(pkt: Dictionary, _reliable: bool) -> void:
	if board == null or _applying:
		return
	_applying = true
	var zid := str(pkt.get("zone", ""))
	var sender := int(pkt.get("owner", 0))
	if sender == _me():
		_applying = false
		return
	var primary := int(assign.get("primary", {}).get(zid, sender))
	if sender != primary and sender != int(assign.get("secondary", {}).get(zid, 0)):
		_applying = false
		return
	if sender != primary:
		var silent := Time.get_ticks_msec() - int(_last_owner_ms.get(zid, 0))
		if silent < 1500:
			_applying = false
			return
	_last_owner_ms[zid] = Time.get_ticks_msec()
	_lerp_ms = clampi(int(net.rtt_ms.get(sender, 80)), 50, 250)
	var in_audit := _audit_slice.has(zid) and sender == _audit_peer and Time.get_ticks_msec() < _audit_until
	if not in_audit:
		for u_v in pkt.get("units", []):
			if typeof(u_v) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = u_v
			var u: Dictionary = _ensure_unit(row)
			if u.is_empty():
				continue
			if sim_unit(u) and int(assign.get("primary", {}).get(zid, 0)) == _me():
				continue
			if bool(row.get("alive", true)):
				u["sys"] = str(row.get("sys", u.get("sys", "")))
				u["cell"] = int(row.get("cell", u.get("cell", 0)))
				var pos: Array = row.get("pos", [])
				if pos.size() >= 3:
					_targets[str(u.get("id", ""))] = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			u["alive"] = bool(row.get("alive", true))
			_write_hull(u, row)
		var arcs_v: Variant = pkt.get("arcs", {})
		if typeof(arcs_v) == TYPE_DICTIONARY and board.map != null:
			for sid_v in (arcs_v as Dictionary).keys():
				var sid := str(sid_v)
				if fog_blocks_arc(sid):
					continue
				if not board.map.systems.has(sid):
					continue
				var weights: Array = (arcs_v as Dictionary)[sid_v]
				var cells: Array = board.map.systems[sid]["cells"]
				for i in range(mini(weights.size(), cells.size())):
					cells[i]["weight"] = float(weights[i])
	if pkt.get("sim_clock", null) != null and not owns_global("clock"):
		board._sim_clock = float(pkt.get("sim_clock", board._sim_clock))
	var dip_v: Variant = pkt.get("diplomacy", null)
	if typeof(dip_v) == TYPE_DICTIONARY and board.data != null and not owns_global("diplo"):
		board.data.diplomacy = dip_v
	for kill_v in pkt.get("kills", []):
		if typeof(kill_v) == TYPE_DICTIONARY:
			board._mp_apply_kill_event(kill_v)
	if not owns_global("victory"):
		var occ_v: Variant = pkt.get("occupy", null)
		if typeof(occ_v) == TYPE_DICTIONARY:
			for fac_v in (occ_v as Dictionary).keys():
				board._stat_fac(int(fac_v))["occupy_score"] = float((occ_v as Dictionary)[fac_v])
	_apply_presence(pkt.get("presence", {}))
	_applying = false


func _apply_presence(presence_v: Variant, force: bool = false) -> void:
	if typeof(presence_v) != TYPE_DICTIONARY or board.map == null:
		return
	for sid_v in (presence_v as Dictionary).keys():
		var sid := str(sid_v)
		if not board.map.systems.has(sid):
			continue
		if not force and sim_system(sid):
			continue
		var row_v: Variant = (presence_v as Dictionary)[sid_v]
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var cells: Array = board.map.systems[sid]["cells"]
		var owners_v: Variant = row.get("owners", [])
		var owners: Array = owners_v if owners_v is Array else []
		if (force or owns_global("victory")) and not owners.is_empty():
			for i in range(mini(owners.size(), cells.size())):
				if typeof(cells[i]) == TYPE_DICTIONARY:
					(cells[i] as Dictionary)["owner"] = int(owners[i])
			continue
		var owner := int(row.get("owner", 0))
		for c_v in cells:
			if typeof(c_v) == TYPE_DICTIONARY and int((c_v as Dictionary).get("kind", -1)) == BoardTypes.CellKind.SOV:
				(c_v as Dictionary)["owner"] = owner


func _lerp_remote(delta: float) -> void:
	var buf := maxf(float(_lerp_ms) / 1000.0, 0.05)
	var k := clampf(delta / buf, 0.0, 1.0)
	for id_v in _targets.keys():
		var u: Dictionary = board._unit_by_id(str(id_v))
		if u.is_empty():
			continue
		if sim_unit(u):
			continue
		var target: Vector3 = _targets[id_v]
		var pos: Vector3 = u.get("pos", target)
		u["pos"] = pos.lerp(target, k)


func _maybe_reassign() -> void:
	var sig := _signature()
	var full := sig != _sig or _over_budget >= 3
	if not full and _shift == "":
		_refresh_hot_flag()
		return
	_recompute(full)
	_sig = _signature()
	_shift = ""
	if _over_budget >= 3:
		_over_budget = 0


func _shift_one() -> void:
	if not net.is_host or zones.is_empty():
		return
	_shift_i = (_shift_i + 1) % zones.size()
	_shift = str((zones[_shift_i] as Dictionary).get("id", ""))
	_recompute(false)
	_shift = ""


func _recompute(full: bool) -> void:
	if not net.is_host or board.map == null:
		return
	var owners: Dictionary = {}
	var facs: Dictionary = {}
	for sid_v in board.map.systems.keys():
		var sid := str(sid_v)
		var remote: Dictionary = _presence_of(sid)
		var local_sim: bool = bool(sim_system(sid)) or net.world_presence.is_empty()
		if local_sim or remote.is_empty():
			owners[sid] = _owner_of(sid)
			facs[sid] = []
		else:
			owners[sid] = int(remote.get("owner", _owner_of(sid)))
			var raw_facs: Variant = remote.get("facs", [])
			facs[sid] = raw_facs if raw_facs is Array else []
	for u_v in board.units:
		if typeof(u_v) != TYPE_DICTIONARY or not bool((u_v as Dictionary).get("alive", false)):
			continue
		var sid2 := str((u_v as Dictionary).get("sys", ""))
		if not facs.has(sid2):
			continue
		if not sim_system(sid2) and net.world_presence.has(sid2):
			continue
		var fac := int((u_v as Dictionary).get("faction", 0))
		if not (facs[sid2] as Array).has(fac):
			(facs[sid2] as Array).append(fac)
	var layout: Dictionary = {"systems": []}
	for sid3_v in board.map.systems.keys():
		var sid3 := str(sid3_v)
		var sys: Dictionary = board.map.systems[sid3]
		layout["systems"].append({
			"id": sid3,
			"links": sys.get("links", []),
			"cells": sys.get("cells", []),
		})
	zones = MpZoneSched.partition(layout, owners, facs)
	zone_of.clear()
	for z_v in zones:
		for s_v in (z_v as Dictionary).get("systems", []):
			zone_of[str(s_v)] = str((z_v as Dictionary).get("id", ""))
	var peers := _peer_rows(facs)
	assign = MpZoneSched.assign(zones, peers, assign, full, _shift)
	net.publish_assignment(zones, assign)


func _refresh_hot_flag() -> void:
	var facs: Dictionary = {}
	for u_v in board.units:
		if typeof(u_v) != TYPE_DICTIONARY or not bool((u_v as Dictionary).get("alive", false)):
			continue
		var sid := str((u_v as Dictionary).get("sys", ""))
		if not facs.has(sid):
			facs[sid] = []
		var fac := int((u_v as Dictionary).get("faction", 0))
		if not (facs[sid] as Array).has(fac):
			(facs[sid] as Array).append(fac)
	var layout: Dictionary = {"systems": []}
	for sid_v in board.map.systems.keys():
		layout["systems"].append({"id": str(sid_v), "links": board.map.systems[sid_v].get("links", [])})
	var hot := MpZoneSched.contact_systems(layout, facs)
	for z_v in zones:
		var z: Dictionary = z_v
		var is_hot := false
		for s_v in z.get("systems", []):
			if hot.has(str(s_v)):
				is_hot = true
		z["hot"] = is_hot


func _peer_rows(_facs: Dictionary) -> Array:
	var rows: Array = []
	for m_v in net.room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if bool(m.get("ai", false)) or bool(m.get("offline", false)):
			continue
		var pid := int(m.get("peer", 0))
		if pid <= 0:
			continue
		var rep_v: Variant = net.reports.get(pid, {})
		var rep: Dictionary = rep_v if typeof(rep_v) == TYPE_DICTIONARY else {}
		var bench := float(m.get("bench", 1.0))
		var spent: float = net.zone_ms if pid == _me() else float(rep.get("zone_ms", 0.0))
		var throughput := bench
		if spent > 1.0:
			throughput = bench * clampf(1000.0 / spent, 0.25, 4.0)
		var fac := int(m.get("faction", 0))
		rows.append({
			"id": pid,
			"throughput": maxf(throughput, 0.001),
			"spectate": str(m.get("seat", "")) == "spectate",
			"rtt": net._rtt_estimate(pid),
			"facs": [fac] if fac > 0 else [],
		})
	if rows.is_empty():
		rows.append({
			"id": _me(),
			"throughput": maxf(net.bench, 1.0),
			"spectate": net.local_faction() <= 0,
			"rtt": {},
			"facs": [net.local_faction()] if net.local_faction() > 0 else [],
		})
	return rows


func _facs_for_peer(pid: int, _facs: Dictionary) -> Array:
	var fac := 0
	if pid == _me():
		fac = net.local_faction()
	else:
		var blob_v: Variant = net.metrics.get(pid, net.metrics.get(str(pid), {}))
		if typeof(blob_v) == TYPE_DICTIONARY:
			fac = int((blob_v as Dictionary).get("faction", 0))
	if fac <= 0:
		return []
	return [fac]


func _all_faction_vision() -> Dictionary:
	var out: Dictionary = {}
	var factions: Dictionary = {}
	for u_v in board.units:
		if typeof(u_v) == TYPE_DICTIONARY:
			factions[int((u_v as Dictionary).get("faction", 0))] = true
	for fac_v in factions.keys():
		var fac := int(fac_v)
		if fac <= 0:
			continue
		var seen := _vision_for(fac)
		var bag: Dictionary = {}
		for sid_v in seen.keys():
			bag[str(sid_v)] = true
		out[str(fac)] = bag
	return out


func _vision_for(faction: int) -> Dictionary:
	var sources: Array = []
	for u_v in board.units:
		if typeof(u_v) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = u_v
		if int(u.get("faction", 0)) == faction and bool(u.get("alive", false)):
			var sid := str(u.get("sys", ""))
			if sid != "" and not sources.has(sid):
				sources.append(sid)
	if board.map != null:
		for sid2_v in board.map.systems.keys():
			if _owner_of(str(sid2_v)) == faction and not sources.has(str(sid2_v)):
				sources.append(str(sid2_v))
	var layout: Dictionary = {"systems": []}
	if board.map != null:
		for sid3_v in board.map.systems.keys():
			layout["systems"].append({"id": str(sid3_v), "links": board.map.systems[sid3_v].get("links", [])})
	return MpZoneSched.vision(layout, sources)


func _refresh_vision() -> void:
	vision = _vision_for(int(board.viewer_faction)) if fog_on else {}
	if board.starmap_view != null:
		var mask := _fog_mask()
		if board.starmap_view.fog_mask != mask:
			board.starmap_view.fog_mask = mask
			board.starmap_view._rebuild_territory()


func _fog_mask() -> Dictionary:
	var mask: Dictionary = {}
	if not fog_on or board.map == null:
		return mask
	for sid_v in board.map.systems.keys():
		mask[str(sid_v)] = not vision.has(str(sid_v))
	return mask


func _owner_of(sid: String) -> int:
	if board.map == null or not board.map.systems.has(sid):
		return 0
	for c_v in board.map.systems[sid]["cells"]:
		if typeof(c_v) != TYPE_DICTIONARY:
			continue
		if int((c_v as Dictionary).get("kind", -1)) == BoardTypes.CellKind.SOV:
			return int((c_v as Dictionary).get("owner", 0))
	return 0


func _me() -> int:
	if net.multiplayer.has_multiplayer_peer():
		return net.multiplayer.get_unique_id()
	return 1


func _my_share() -> float:
	var mine := maxf(net.bench, 1.0)
	var sum := 0.0
	var blob: Dictionary = net.metrics
	if blob.is_empty():
		return 1.0
	for pid_v in blob.keys():
		var row_v: Variant = blob[pid_v]
		if typeof(row_v) == TYPE_DICTIONARY:
			sum += maxf(float((row_v as Dictionary).get("bench", 1.0)), 1.0)
	if sum <= 0.0:
		return 1.0
	return mine / sum


func _signature() -> String:
	var ids: Array = []
	for z_v in zones:
		var z: Dictionary = z_v
		var mark := "h" if bool(z.get("hot", false)) else "c"
		ids.append(str(z.get("id", "")) + mark)
	ids.sort()
	var rtt_sig := ""
	for pid_v in net.rtt_ms.keys():
		var ms := int(net.rtt_ms[pid_v])
		var bucket := 2 if ms > 250 else (0 if ms < 100 else 1)
		rtt_sig += "%s:%d," % [str(pid_v), bucket]
	return "|".join(PackedStringArray(ids)) + ":" + str(net.metrics.keys()) + ":" + rtt_sig


func _apply_saved_progress() -> void:
	if not FileAccess.file_exists(MpCampaignNet.PROGRESS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MpCampaignNet.PROGRESS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var prog: Dictionary = parsed
	if float(prog.get("sim_clock", 0.0)) > 0.0:
		board._sim_clock = float(prog.get("sim_clock", 0.0))
	for row_v in prog.get("units", []):
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var u: Dictionary = _ensure_unit(row)
		if u.is_empty():
			continue
		u["sys"] = str(row.get("sys", u.get("sys", "")))
		u["cell"] = int(row.get("cell", u.get("cell", 0)))
		u["alive"] = bool(row.get("alive", true))
		var pos: Array = row.get("pos", [])
		if pos.size() >= 3:
			u["pos"] = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		_write_hull(u, row)
	var arcs_v: Variant = prog.get("arcs", {})
	if typeof(arcs_v) == TYPE_DICTIONARY and board.map != null:
		for sid_v in (arcs_v as Dictionary).keys():
			var sid := str(sid_v)
			if not board.map.systems.has(sid):
				continue
			var weights: Array = (arcs_v as Dictionary)[sid_v]
			var cells: Array = board.map.systems[sid]["cells"]
			for i in range(mini(weights.size(), cells.size())):
				cells[i]["weight"] = float(weights[i])
	var tables_v: Variant = null
	if FileAccess.file_exists(MpCampaignNet.TABLES_PATH):
		tables_v = JSON.parse_string(FileAccess.get_file_as_string(MpCampaignNet.TABLES_PATH))
	if typeof(tables_v) == TYPE_DICTIONARY and board.data != null:
		var ships: Array = (tables_v as Dictionary).get("ships", [])
		if not ships.is_empty():
			board.data.ships.clear()
			for s_v in ships:
				if typeof(s_v) == TYPE_DICTIONARY:
					board.data.ships[str((s_v as Dictionary).get("id", ""))] = s_v
		var equip_v: Variant = (tables_v as Dictionary).get("equipment", {})
		if typeof(equip_v) == TYPE_DICTIONARY and not (equip_v as Dictionary).is_empty():
			board.data.equipment = equip_v
	_apply_presence(prog.get("presence", {}), true)
	var saved_kills: Variant = prog.get("kills", {})
	if typeof(saved_kills) == TYPE_DICTIONARY:
		for kill_v in (saved_kills as Dictionary).values():
			if typeof(kill_v) == TYPE_DICTIONARY:
				board._mp_apply_kill_event(kill_v)
	var saved_occ: Variant = prog.get("occupy", {})
	if typeof(saved_occ) == TYPE_DICTIONARY:
		for fac_v in (saved_occ as Dictionary).keys():
			board._stat_fac(int(fac_v))["occupy_score"] = float((saved_occ as Dictionary)[fac_v])


func _on_order(unit_id: String, to_sys: String, to_cell: int) -> void:
	var u: Dictionary = board._unit_by_id(unit_id)
	if u.is_empty():
		return
	_applying = true
	board._pathfind_apply(u, to_sys, to_cell)
	_applying = false


func _on_group(unit_id: String, group_id: int) -> void:
	_applying = true
	board._set_unit_ctrl_group(unit_id, group_id)
	_applying = false


func _on_deputy(faction: int, group_id: int) -> void:
	if int(board.viewer_faction) != faction:
		return
	_applying = true
	board.deputy_group = group_id
	board._rebuild_player_deputy()
	_applying = false


func _on_diplo(a: int, b: int, on: bool) -> void:
	_applying = true
	board.diplo_offer.erase("%d>%d" % [a, b])
	board.diplo_offer.erase("%d>%d" % [b, a])
	board._set_alliance(a, b, on)
	board._rebuild_diplomacy_rows()
	_applying = false


func _on_diplo_offer(from_fac: int, to_fac: int) -> void:
	board.diplo_offer["%d>%d" % [from_fac, to_fac]] = true
	board._rebuild_diplomacy_rows()


func _on_assignment() -> void:
	if net != null and not net.is_host:
		_pull_assignment()


func _on_peers_changed() -> void:
	if net != null and net.is_host:
		_recompute(true)


func _pull_assignment() -> void:
	if net == null or net.zone_sync.is_empty():
		return
	assign = net.assignment
	zones = net.zone_sync.duplicate(true)
	zone_of.clear()
	for z_v in zones:
		if typeof(z_v) != TYPE_DICTIONARY:
			continue
		var zid := str((z_v as Dictionary).get("id", ""))
		for s_v in (z_v as Dictionary).get("systems", []):
			zone_of[str(s_v)] = zid


func _presence_of(sid: String) -> Dictionary:
	var raw: Variant = net.world_presence.get(sid, {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func _write_hull(u: Dictionary, row: Dictionary) -> void:
	var inst_v: Variant = u.get("inst", {})
	var inst: Dictionary = inst_v if typeof(inst_v) == TYPE_DICTIONARY else {}
	if row.has("shield"):
		inst["shield"] = float(row.get("shield", 0.0))
	if row.has("armor"):
		inst["armor"] = float(row.get("armor", 0.0))
	if row.has("structure"):
		inst["structure"] = float(row.get("structure", 0.0))
	if not inst.is_empty():
		u["inst"] = inst


func _ensure_unit(row: Dictionary) -> Dictionary:
	var uid := str(row.get("id", ""))
	var u: Dictionary = board._unit_by_id(uid)
	if not u.is_empty() or not bool(row.get("alive", false)) or bool(row.get("garrison", false)):
		return u
	var ship_id := str(row.get("ship_id", ""))
	if ship_id == "" or board.data == null:
		return {}
	var pilot: Dictionary = board._pilot_by_id(str(row.get("pilot_id", "")))
	if pilot.is_empty():
		pilot = {
			"id": str(row.get("pilot_id", uid)),
			"name": str(row.get("pilot_id", uid)),
			"faction": int(row.get("faction", 0)),
			"home": str(row.get("sys", "")),
		}
	var def: Dictionary = board.data.ship_def(ship_id)
	var inst := {
		"ship_id": ship_id,
		"shield": float(row.get("shield", 0.0)),
		"armor": float(row.get("armor", 0.0)),
		"structure": float(row.get("structure", 0.0)),
		"max_s": float(row.get("max_s", def.get("shield", 0.0))),
		"max_a": float(row.get("max_a", def.get("armor", 0.0))),
		"max_h": float(row.get("max_h", def.get("structure", 0.0))),
		"pristine_s": float(row.get("max_s", 0.0)),
		"pristine_a": float(row.get("max_a", 0.0)),
		"pristine_h": float(row.get("max_h", 0.0)),
		"cap": float(def.get("cap", 0.0)),
		"max_cap": float(def.get("cap", 0.0)),
		"resist": int(def.get("resist", 0)),
	}
	var spawned: Dictionary = board._spawn_unit(pilot, inst, str(row.get("sys", "")), int(row.get("cell", 0)))
	if spawned.is_empty():
		return {}
	spawned["id"] = uid
	return spawned


func _on_fog(on: bool) -> void:
	fog_on = on
	if board.map != null:
		board.map.layout["fog_of_war"] = on
	_refresh_vision()


func _on_match_over(winner: int, reason: String) -> void:
	if bool(board.match_over):
		return
	board._end_match(winner, reason)


func _on_chat(text: String, scope: String, faction: int) -> void:
	if scope == "faction" and faction != int(board.viewer_faction):
		return
	board._chat_append(text)


func _save_prefs(on: bool) -> void:
	var path := "user://custom_campaign_prefs.json"
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	data["fog_of_war"] = on
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
