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
var _cold_phased: Dictionary = {}
var _sim_ms := 0.0
var _global_acc := 0.0
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
var _zone_fresh: Dictionary = {}
var _zone_tx: Dictionary = {}
var _zone_rx: Dictionary = {}
var _zone_low: Dictionary = {}
var _suspect_log: Dictionary = {}
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
	if not net.concede_received.is_connected(_on_concede):
		net.concede_received.connect(_on_concede)
	if not net.fit_received.is_connected(_on_fit):
		net.fit_received.connect(_on_fit)
	if not net.host_lost.is_connected(_on_host_lost):
		net.host_lost.connect(_on_host_lost)
	if not net.disc_notice.is_connected(_on_disc_notice):
		net.disc_notice.connect(_on_disc_notice)
	net.disc_capture = Callable(self, "_capture_disc")
	net.disc_apply = Callable(self, "_apply_disc")
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
		return net.is_host or net.host_gone
	var sid := str(u.get("sys", ""))
	var zid := str(zone_of.get(sid, ""))
	if zid == "":
		return net.is_host or net.host_gone
	var me := _me()
	var secondary: Dictionary = assign.get("secondary", {})
	#（房主掉线后接管他的区）26.10.22 11:25 s
	if net.host_gone:
		var owner := int(primary.get(zid, 1))
		return owner == me or owner <= 1
	#（房主掉线后接管他的区）26.10.22 11:25 e
	if int(primary.get(zid, 0)) == me or int(secondary.get(zid, 0)) == me:
		return true
	if _audit_peer != 0 and Time.get_ticks_msec() < _audit_until and _audit_slice.has(zid) and _audit_ready.has(zid):
		return true
	return false


func owns_global(name: String) -> bool:
	if not active():
		return true
	if net.host_gone:
		var owner := int(assign.get("globals", {}).get(name, 1))
		return owner == _me() or owner <= 1
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
		if authority_zone(_zone_of(sid)):
			continue
		var cells: Array = []
		for c_v in board.map.systems[sid]["cells"]:
			if typeof(c_v) != TYPE_DICTIONARY:
				continue
			var c: Dictionary = c_v
			cells.append({
				"owner": int(c.get("owner", 0)),
				"work": float(c.get("work", 0.0)),
				"capturing": int(c.get("capturing", 0)),
				"cap_stall": float(c.get("cap_stall", 0.0)),
				"cap_stall_done": bool(c.get("cap_stall_done", false)),
			})
		saved[sid] = cells
	return saved


func after_capture(saved: Dictionary) -> void:
	if board.map == null:
		return
	for sid_v in saved.keys():
		var sid := str(sid_v)
		if not board.map.systems.has(sid):
			continue
		var rows: Array = saved[sid]
		var cells: Array = board.map.systems[sid]["cells"]
		for i in range(mini(rows.size(), cells.size())):
			if typeof(rows[i]) != TYPE_DICTIONARY or typeof(cells[i]) != TYPE_DICTIONARY:
				continue
			var src: Dictionary = rows[i]
			var cell: Dictionary = cells[i]
			cell["owner"] = int(src.get("owner", 0))
			cell["work"] = float(src.get("work", 0.0))
			cell["capturing"] = int(src.get("capturing", 0))
			cell["cap_stall"] = float(src.get("cap_stall", 0.0))
			cell["cap_stall_done"] = bool(src.get("cap_stall_done", false))


func _zone_of(sid: String) -> String:
	return str(zone_of.get(sid, ""))


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
	_publish_globals(delta)
	_lerp_remote(delta)
	var me := _me()
	var load_ms := 0.0
	for z_v in zones:
		var zid := str((z_v as Dictionary).get("id", ""))
		if int(assign.get("primary", {}).get(zid, 0)) == me:
			load_ms += float((z_v as Dictionary).get("cost", 1.0))
	_zone_time = _sim_ms
	net.note_zone_ms(_sim_ms)
	var share := _my_share()
	if share > 0.0 and _sim_ms > share * 1000.0:
		_over_budget += 1
	else:
		_over_budget = 0


func note_sim_ms(ms: float) -> void:
	_sim_ms = ms


func on_fit(unit_id: String, kind: String, on: bool) -> void:
	if not active() or _applying:
		return
	var u: Dictionary = board._unit_by_id(unit_id)
	if u.is_empty():
		return
	var zid := str(zone_of.get(str(u.get("sys", "")), ""))
	var owner := int(assign.get("primary", {}).get(zid, 0))
	net.send_fit(unit_id, kind, on, owner)


func on_path(u: Dictionary, to_sys: String, to_cell: int) -> void:
	if not active() or _applying:
		return
	var zid := str(zone_of.get(str(u.get("sys", "")), ""))
	var owner := int(assign.get("primary", {}).get(zid, 0))
	net.send_order(str(u.get("id", "")), to_sys, to_cell, owner, str(u.get("focus_id", "")))


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


func offer_diplo(from_fac: int, to_fac: int, on: bool = true) -> void:
	if not active() or _applying:
		return
	net.send_diplo_offer(from_fac, to_fac, on)


func leave_match(rec: Dictionary, concede_fac: int) -> void:
	if net == null:
		return
	net.leave_match(rec, concede_fac)


func on_match_end(winner: int, reason: String) -> void:
	if not active():
		return
	if owns_global("victory"):
		net.send_match_over(winner, reason)


func after_settlement() -> void:
	if _close_scheduled or net == null or board == null:
		return
	_close_scheduled = true
	#（终局同步结算并回到房间，不把还在打的人改成观战）26.10.22 15:10 s
	var rec: Dictionary = {}
	if board.has_method("mp_settlement_record"):
		rec = board.mp_settlement_record(str(board.match_msg), false)
	net.finish_match(rec)
	#（终局同步结算并回到房间，不把还在打的人改成观战）26.10.22 15:10 e


func _on_host_lost() -> void:
	if board == null:
		return
	#（掉线后继续等重连，不暂停）26.10.22 11:25 s
	board.sim_paused = false
	var line := net.disc_wait_text() if net != null else ""
	board._chat_append(line if line != "" else "与房主断开")
	#（掉线后继续等重连，不暂停）26.10.22 11:25 e


func _on_disc_notice(text: String) -> void:
	if board != null and text != "":
		board._chat_append(text)


func note_player_combat(attacker: Dictionary, target: Dictionary) -> void:
	if net != null:
		net.note_player_combat(attacker, target)


func _capture_disc() -> Dictionary:
	var units: Array = []
	var cells: Array = []
	if board == null:
		return {"units": units, "cells": cells}
	for u in board.units:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var pos: Vector3 = u.get("pos", Vector3.ZERO)
		var inst: Dictionary = u.get("inst", {})
		units.append({
			"id": str(u.get("id", "")),
			"sys": str(u.get("sys", "")),
			"cell": int(u.get("cell", 0)),
			"pos": [pos.x, pos.y, pos.z],
			"motion_seq": int(u.get("motion_seq", 0)),
			"alive": bool(u.get("alive", false)),
			"shield": float(inst.get("shield", 0.0)),
			"armor": float(inst.get("armor", 0.0)),
			"structure": float(inst.get("structure", 0.0)),
		})
	if board.map != null:
		for sid in board.map.systems.keys():
			var sysd: Dictionary = board.map.systems[sid]
			var row_cells: Array = sysd.get("cells", [])
			for i in row_cells.size():
				var c: Dictionary = row_cells[i]
				cells.append({"sys": str(sid), "cell": i, "owner": int(c.get("owner", 0))})
	return {"units": units, "cells": cells}


func _apply_disc(body: Dictionary, combat: bool) -> void:
	if board == null or typeof(body) != TYPE_DICTIONARY:
		return
	for row_v in body.get("units", []):
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var u: Dictionary = board._unit_by_id(str(row.get("id", "")))
		if u.is_empty():
			continue
		#（重连底稿不能把更新的移动记录按回去）26.10.22 21:05 s
		if _motion_newer(u, row):
			_apply_motion_row(u, row, "RECONNECT")
		elif int(row.get("motion_seq", 0)) < int(u.get("motion_seq", 0)):
			DebugSessionLog.append("MOT", "mp_match_driver._apply_disc", "reject_old", {
				"id": str(u.get("id", "")), "have": int(u.get("motion_seq", 0)),
				"incoming": int(row.get("motion_seq", 0)), "runId": "motion-fence"
			})
		#（重连底稿不能把更新的移动记录按回去）26.10.22 21:05 e
		if combat:
			u["alive"] = bool(row.get("alive", u.get("alive", false)))
			_write_hull(u, row)
	if board.map == null:
		return
	for cell_v in body.get("cells", []):
		if typeof(cell_v) != TYPE_DICTIONARY:
			continue
		var cell: Dictionary = cell_v
		var sid := str(cell.get("sys", ""))
		if not board.map.systems.has(sid):
			continue
		var sysd: Dictionary = board.map.systems[sid]
		var row_cells: Array = sysd.get("cells", [])
		var idx := int(cell.get("cell", -1))
		if idx < 0 or idx >= row_cells.size():
			continue
		row_cells[idx]["owner"] = int(cell.get("owner", row_cells[idx].get("owner", 0)))


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
	if _audit_peer != 0 and Time.get_ticks_msec() < _audit_until:
		return "核查中"
	if _audit_checked > 0:
		return "核对 %d 条，一致 %d 条" % [_audit_checked, _audit_matched]
	return ""


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
	_audit_checked += int(cmp.get("checked", 0))
	_audit_matched += int(cmp.get("matched", 0))


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
		var phased := bool(_cold_phased.get(zid, false))
		var gate := 1.0 if phased else 1.0 + float(phase) / 1000.0
		if acc < gate:
			continue
		_cold_acc[zid] = acc - gate
		_cold_phased[zid] = true
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
	if secondary == me:
		var silent := Time.get_ticks_msec() - int(_last_owner_ms.get(zid, 0))
		#（静默只记怀疑，不把写权限交给备机）26.10.22 21:05 s
		if silent > 1500 and int(_suspect_log.get(zid, -1)) != int(Time.get_ticks_msec() / 1000):
			_suspect_log[zid] = int(Time.get_ticks_msec() / 1000)
			DebugSessionLog.append("MOT", "mp_match_driver._should_publish", "suspect_silent", {
				"zone": zid, "silent_ms": silent, "runId": "motion-fence"
			})
		#（静默只记怀疑，不把写权限交给备机）26.10.22 21:05 e
	return false


func _is_primary(zid: String) -> bool:
	return int(assign.get("primary", {}).get(zid, 0)) == _me()


func authority_zone(zid: String) -> bool:
	## One writer: the assigned primary. Silence does not grant the backup a term.
	if not active() or zid == "":
		return true
	return _is_primary(zid)


func _packet(zone: Dictionary, with_arcs: bool, with_kills: bool = false) -> Dictionary:
	var systems: Array = zone.get("systems", [])
	var want: Dictionary = {}
	for s_v in systems:
		want[str(s_v)] = true
	var zid_tx := str(zone.get("id", ""))
	_zone_tx[zid_tx] = int(_zone_tx.get(zid_tx, 0)) + 1
	var units: Array = []
	var presence: Dictionary = {}
	for u_v in board.units:
		if typeof(u_v) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = u_v
		var sid := str(u.get("sys", ""))
		if not _zone_wants_unit(want, u):
			continue
		if not presence.has(sid):
			presence[sid] = {"owner": _owner_of(sid), "facs": [], "owners": []}
		var fac := int(u.get("faction", 0))
		if bool(u.get("alive", false)) and not (presence[sid]["facs"] as Array).has(fac):
			(presence[sid]["facs"] as Array).append(fac)
		#（本机模拟星系写出存活舰数）26.10.22 01:52 s
		if bool(u.get("alive", false)):
			presence[sid]["ships"] = int(presence[sid].get("ships", 0)) + 1
		#（本机模拟星系写出存活舰数）26.10.22 01:52 e
		var pos: Vector3 = u.get("pos", Vector3.ZERO)
		#（快照带船头和这一步终点）26.10.22 23:58 s
		var face: Vector3 = u.get("face_dir", Vector3.ZERO)
		var to_p: Vector3 = u.get("to_pos", pos)
		#（快照带船头和这一步终点）26.10.22 23:58 e
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
			"face": [face.x, face.z],
			"to": [to_p.x, to_p.y, to_p.z],
			"faction": fac,
			"ship_id": str(u.get("ship_id", "")),
			"pilot_id": str(u.get("pilot_id", "")),
			"garrison": bool(u.get("garrison", false)),
			"focus_id": str(u.get("focus_id", "")),
			"cap": float(inst.get("cap", 0.0)),
			"max_cap": float(inst.get("max_cap", 0.0)),
			"step_t": float(u.get("step_t", 0.0)),
			"motion_seq": int(u.get("motion_seq", 0)),
			"phase_t": float(u.get("phase_t", 0.0)),
			"from_sys": str(u.get("from_sys", sid)),
			"from_cell": int(u.get("from_cell", u.get("cell", 0))),
			"to_sys": str(u.get("to_sys", sid)),
			"to_cell": int(u.get("to_cell", u.get("cell", 0))),
			"step_kind": str(u.get("step_kind", "")),
			"step_invuln": float(u.get("step_invuln", 0.0)),
			"order_dest_sys": str(u.get("order_dest_sys", "")),
			"order_dest_cell": int(u.get("order_dest_cell", -1)),
			"command_id": int(u.get("command_id", 0)),
			"nav_standby": bool(u.get("nav_standby_on_sys_enter", false)),
			"weapon_cd": _cd_list(u.get("weapons", [])),
			"repair_cd": _cd_list(u.get("self_rep", [])),
			"path": _path_blob(u.get("path", [])),
			"skirmish_left": float(u.get("skirmish_left", 0.0)),
			"skirmish_speed": float(u.get("skirmish_speed", 0.0)),
			"skirmish_prep": float(u.get("skirmish_prep", 0.0)),
			"bursts": _burst_blob(u.get("bursts", [])),
		})
	for sid_v in want.keys():
		var sid_s := str(sid_v)
		if not presence.has(sid_s):
			presence[sid_s] = {"owner": _owner_of(sid_s), "facs": [], "owners": []}
		var owners: Array = []
		var works: Array = []
		var caps: Array = []
		var stalls: Array = []
		var assignees: Array = []
		if board.map != null and board.map.systems.has(sid_s):
			for c_v in board.map.systems[sid_s]["cells"]:
				if typeof(c_v) == TYPE_DICTIONARY:
					owners.append(int((c_v as Dictionary).get("owner", 0)))
					works.append(float((c_v as Dictionary).get("work", 0.0)))
					caps.append(int((c_v as Dictionary).get("capturing", 0)))
					stalls.append(float((c_v as Dictionary).get("cap_stall", 0.0)))
					assignees.append(str((c_v as Dictionary).get("assigned_pilot_id", "")))
		presence[sid_s]["owners"] = owners
		presence[sid_s]["works"] = works
		presence[sid_s]["capturing"] = caps
		presence[sid_s]["stalls"] = stalls
		presence[sid_s]["assignees"] = assignees
		if not presence[sid_s].has("ships"):
			presence[sid_s]["ships"] = 0
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
		"frame_seq": int(_zone_tx.get(zid_tx, 0)),
		"owner": _me(),
		"hot": bool(zone.get("hot", false)),
		"units": units,
		"presence": presence,
		"arcs": arcs,
		"kills": kills,
		"vision": _all_faction_vision(),
		"fx": board._fx_recent.duplicate(),
	}
	return pkt


func _cd_list(rows: Variant) -> Array:
	var out: Array = []
	if typeof(rows) != TYPE_ARRAY:
		return out
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			out.append(0.0)
		else:
			out.append(float((row_v as Dictionary).get("cd", 0.0)))
	return out


func _path_blob(path: Variant) -> Array:
	var out: Array = []
	if typeof(path) != TYPE_ARRAY:
		return out
	for step_v in path:
		if typeof(step_v) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = step_v
		var step_out := {
			"sys": str(step.get("sys", "")),
			"from": int(step.get("from", 0)),
			"to": int(step.get("to", 0)),
			"kind": str(step.get("kind", "")),
			"duration": float(step.get("duration", 0.0)),
		}
		#（跳跃步骤交接保留目的星系）26.10.22 01:52 s
		if str(step.get("to_sys", "")) != "":
			step_out["to_sys"] = str(step.get("to_sys", ""))
		#（跳跃步骤交接保留目的星系）26.10.22 01:52 e
		out.append(step_out)
	return out


func _burst_blob(rows: Variant) -> Array:
	var out: Array = []
	if typeof(rows) != TYPE_ARRAY:
		return out
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = row_v
		out.append({
			"ref": str(b.get("ref", "")),
			"cd": float(b.get("cd", 0.0)),
			"remain": float(b.get("remain", 0.0)),
			"auto_on": bool(b.get("auto_on", true)),
		})
	return out


func _publish_globals(delta: float) -> void:
	if not active():
		return
	_global_acc += delta
	if _global_acc < 1.0:
		return
	_global_acc = 0.0
	var pkt := {"zone": "__global__", "owner": _me()}
	var any := false
	if _global_live("clock"):
		pkt["sim_clock"] = float(board._sim_clock)
		_last_owner_ms["g:clock"] = Time.get_ticks_msec()
		any = true
	if _global_live("diplo") and board.data != null:
		pkt["diplomacy"] = board.data.diplomacy
		_last_owner_ms["g:diplo"] = Time.get_ticks_msec()
		any = true
	if _global_live("victory"):
		var occupy: Dictionary = {}
		for fac_v in board.match_stats.keys():
			var stat_v: Variant = board.match_stats[fac_v]
			var stat: Dictionary = stat_v if typeof(stat_v) == TYPE_DICTIONARY else {}
			occupy[str(fac_v)] = float(stat.get("occupy_score", 0.0))
		pkt["occupy"] = occupy
		_last_owner_ms["g:victory"] = Time.get_ticks_msec()
		any = true
	if any:
		net.send_zone(pkt, false)


func _global_live(name: String) -> bool:
	var primary := int(assign.get("globals", {}).get(name, 0))
	if primary == _me():
		return true
	if int(assign.get("secondary", {}).get("g:" + name, 0)) != _me():
		return false
	return Time.get_ticks_msec() - int(_last_owner_ms.get("g:" + name, 0)) > 1500


func _take_zone_frame(zid: String, sender: int, frame_seq: int) -> bool:
	## Live primary keeps its own counter. A new primary, or the same one
	## climbing through a stale watermark for 1.5s, becomes the sequence.
	if frame_seq <= 0:
		return true
	var now := Time.get_ticks_msec()
	var st_v: Variant = _zone_rx.get(zid, {})
	var st: Dictionary = st_v if typeof(st_v) == TYPE_DICTIONARY else {}
	var have_sender := int(st.get("sender", -999))
	var have_seq := int(st.get("seq", -1))
	if have_sender != sender or frame_seq >= have_seq:
		if have_sender != sender and have_sender != -999:
			DebugSessionLog.append("MOT", "mp_match_driver._take_zone_frame", "accept_sender", {
				"zone": zid, "sender": sender, "prev": have_sender, "seq": frame_seq, "runId": "post-fix"
			})
		_zone_rx[zid] = {"sender": sender, "seq": frame_seq, "accept_ms": now}
		_zone_low.erase(zid)
		return true
	var low_v: Variant = _zone_low.get(zid, {})
	var low: Dictionary = low_v if typeof(low_v) == TYPE_DICTIONARY else {}
	if int(low.get("sender", -999)) != sender or frame_seq <= int(low.get("prev", -1)):
		low = {"sender": sender, "prev": frame_seq, "n": 1, "since_ms": now}
	else:
		low["prev"] = frame_seq
		low["n"] = int(low.get("n", 0)) + 1
	_zone_low[zid] = low
	var silent := now - int(st.get("accept_ms", now))
	if int(low.get("n", 0)) >= 8 and silent > 1500:
		_zone_rx[zid] = {"sender": sender, "seq": frame_seq, "accept_ms": now}
		_zone_low.erase(zid)
		DebugSessionLog.append("MOT", "mp_match_driver._take_zone_frame", "resync", {
			"zone": zid, "sender": sender, "have": have_seq, "incoming": frame_seq,
			"silent_ms": silent, "runId": "post-fix"
		})
		return true
	DebugSessionLog.append("MOT", "mp_match_driver._on_zone", "reject_frame", {
		"zone": zid, "have": have_seq, "incoming": frame_seq, "sender": sender, "runId": "motion-fence"
	})
	return false


func _on_zone(pkt: Dictionary, _reliable: bool) -> void:
	if board == null or _applying:
		return
	_applying = true
	var zid := str(pkt.get("zone", ""))
	var sender := int(pkt.get("owner", 0))
	if zid == "__global__":
		_apply_globals(pkt, sender)
		_applying = false
		return
	if sender == _me():
		_applying = false
		return
	var primary := int(assign.get("primary", {}).get(zid, sender))
	if sender != primary:
		_applying = false
		return
	var frame_seq := int(pkt.get("frame_seq", 0))
	#（同一任期只接受更新的区帧）26.10.22 21:05 s
	#（主节点换人或旧帧停住超过一秒半就改认新序列）26.10.22 23:35 s
	if not _take_zone_frame(zid, sender, frame_seq):
		_applying = false
		return
	#（主节点换人或旧帧停住超过一秒半就改认新序列）26.10.22 23:35 e
	#（同一任期只接受更新的区帧）26.10.22 21:05 e
	_zone_fresh[zid] = Time.get_ticks_msec()
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
			if sim_unit(u) and _is_primary(zid):
				continue
			var skip_combat := net.disc_skip_remote_combat(sender == 1)
			if bool(row.get("alive", true)):
				var inc_seq := int(row.get("motion_seq", 0))
				var have_seq := int(u.get("motion_seq", 0))
				if inc_seq < have_seq:
					if int(u.get("_mot_rej", -1)) != int(Time.get_ticks_msec() / 500):
						u["_mot_rej"] = int(Time.get_ticks_msec() / 500)
						DebugSessionLog.append("MOT", "mp_match_driver._on_zone", "reject_old", {
							"id": str(u.get("id", "")), "have": have_seq, "incoming": inc_seq,
							"cell": int(u.get("cell", -1)), "pkt_cell": int(row.get("cell", -1)),
							"runId": "motion-fence"
						})
				else:
					#（出发区旧包不再改已经归新区的船）26.10.23 01:04 s
					var home := str(zone_of.get(str(u.get("sys", "")), ""))
					if home != "" and home != zid and _is_primary(home):
						pass
					else:
						_apply_motion_row(u, row, "NET_SNAPSHOT", inc_seq > have_seq)
					#（出发区旧包不再改已经归新区的船）26.10.23 01:04 e
			if not skip_combat:
				u["alive"] = bool(row.get("alive", true))
				_write_hull(u, row)
			_write_combat(u, row, not skip_combat)
		var arcs_v: Variant = pkt.get("arcs", {})
		if typeof(arcs_v) == TYPE_DICTIONARY and board.map != null:
			for sid_v in (arcs_v as Dictionary).keys():
				var sid := str(sid_v)
				#（迷雾里仍套用弧长）26.10.22 13:42 s
				if not board.map.systems.has(sid):
					continue
				#（迷雾里仍套用弧长）26.10.22 13:42 e
				var weights: Array = (arcs_v as Dictionary)[sid_v]
				var cells: Array = board.map.systems[sid]["cells"]
				for i in range(mini(weights.size(), cells.size())):
					cells[i]["weight"] = float(weights[i])
	if pkt.get("sim_clock", null) != null and not owns_global("clock"):
		#（全局时钟只向前对齐）26.10.23 01:04 s
		var incoming_clock := float(pkt.get("sim_clock", board._sim_clock))
		if incoming_clock + 0.02 >= board._sim_clock:
			board._sim_clock = incoming_clock
		#（全局时钟只向前对齐）26.10.23 01:04 e
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
	for ev_v in pkt.get("fx", []):
		if typeof(ev_v) == TYPE_DICTIONARY:
			board.play_replicated_fx(ev_v)
	_applying = false


func _apply_presence(presence_v: Variant, force: bool = false) -> void:
	if typeof(presence_v) != TYPE_DICTIONARY or board.map == null:
		return
	for sid_v in (presence_v as Dictionary).keys():
		var sid := str(sid_v)
		if not board.map.systems.has(sid):
			continue
		if not force and authority_zone(_zone_of(sid)):
			continue
		var row_v: Variant = (presence_v as Dictionary)[sid_v]
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var cells: Array = board.map.systems[sid]["cells"]
		var owners_v: Variant = row.get("owners", [])
		var owners: Array = owners_v if owners_v is Array else []
		#（观察端套用整格占领）26.10.22 17:58 s
		var works_v: Variant = row.get("works", [])
		var caps_v: Variant = row.get("capturing", [])
		var stalls_v: Variant = row.get("stalls", [])
		var asg_v: Variant = row.get("assignees", [])
		var works: Array = works_v if works_v is Array else []
		var caps: Array = caps_v if caps_v is Array else []
		var stalls: Array = stalls_v if stalls_v is Array else []
		var asg: Array = asg_v if asg_v is Array else []
		var names_changed := false
		if not owners.is_empty():
			for i in range(mini(owners.size(), cells.size())):
				if typeof(cells[i]) != TYPE_DICTIONARY:
					continue
				var cell: Dictionary = cells[i]
				cell["owner"] = int(owners[i])
				if i < works.size():
					cell["work"] = float(works[i])
				if i < caps.size():
					cell["capturing"] = int(caps[i])
				if i < stalls.size():
					cell["cap_stall"] = float(stalls[i])
				#（资源点换人后清掉上一个名字）26.10.22 23:58 s
				if i < asg.size():
					var next_id := str(asg[i])
					if str(cell.get("assigned_pilot_id", "")) != next_id:
						cell["assigned_pilot_id"] = next_id
						names_changed = true
				#（资源点换人后清掉上一个名字）26.10.22 23:58 e
			if board.map:
				board.map.capture_dirty = true
			if names_changed and board.starmap_view:
				board.starmap_view.rebuild_labels(board.pilots)
				# #region agent log
				DebugSessionLog.append("RES", "mp_match_driver._apply_presence", "assignees", {
					"sys": sid, "runId": "post-fix", "hypothesisId": "RES",
				})
				# #endregion
			if int(Time.get_ticks_msec() / 1000) != int(board.get_meta("_dbg_cap", -1)):
				board.set_meta("_dbg_cap", int(Time.get_ticks_msec() / 1000))
				DebugSessionLog.append("CAP", "mp_match_driver._apply_presence", "owners", {"sys": sid, "n": owners.size(), "runId": "post-fix"})
			continue
		#（观察端套用整格占领）26.10.22 17:58 e
		var owner := int(row.get("owner", 0))
		for c_v in cells:
			if typeof(c_v) == TYPE_DICTIONARY and int((c_v as Dictionary).get("kind", -1)) == BoardTypes.CellKind.SOV:
				(c_v as Dictionary)["owner"] = owner


func _lerp_remote(_delta: float) -> void:
	#（显示层自己追，不再把插值写回拟真坐标）26.10.22 17:58 s
	return
	#（显示层自己追，不再把插值写回拟真坐标）26.10.22 17:58 e


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
	var ship_counts: Dictionary = {}
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
			#（远端区用存活舰数算代价）26.10.22 01:52 s
			var remote_row := _presence_of(sid2)
			if remote_row.has("ships"):
				ship_counts[sid2] = int(remote_row.get("ships", 0))
			#（远端区用存活舰数算代价）26.10.22 01:52 e
			continue
		var fac := int((u_v as Dictionary).get("faction", 0))
		if not (facs[sid2] as Array).has(fac):
			(facs[sid2] as Array).append(fac)
		ship_counts[sid2] = int(ship_counts.get(sid2, 0)) + 1
	var layout: Dictionary = {"systems": []}
	for sid3_v in board.map.systems.keys():
		var sid3 := str(sid3_v)
		var sys: Dictionary = board.map.systems[sid3]
		layout["systems"].append({
			"id": sid3,
			"links": sys.get("links", []),
			"cells": sys.get("cells", []),
		})
	zones = MpZoneSched.partition(layout, owners, facs, ship_counts)
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


func _on_order(unit_id: String, to_sys: String, to_cell: int, focus_id: String = "") -> void:
	var u: Dictionary = board._unit_by_id(unit_id)
	if u.is_empty():
		return
	_applying = true
	if focus_id != "":
		u["focus_id"] = focus_id
	board._pathfind_apply(u, to_sys, to_cell)
	if focus_id != "":
		u["focus_id"] = focus_id
	# #region agent log
	DebugSessionLog.append("ATK", "mp_match_driver._on_order", "focus_applied", {
		"unit": unit_id, "focus": focus_id, "to": [to_sys, to_cell], "runId": "post-fix",
	})
	# #endregion
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
	if on:
		board._diplo_chat_allied(a, b)
	else:
		board._diplo_chat_cancelled(a, b)
	board._rebuild_diplomacy_rows()
	_applying = false


func _on_diplo_offer(from_fac: int, to_fac: int, on: bool = true) -> void:
	var key := "%d>%d" % [from_fac, to_fac]
	if on:
		board.diplo_offer[key] = true
		if int(board.viewer_faction) == to_fac:
			board._diplo_chat_received(from_fac)
	else:
		board.diplo_offer.erase(key)
		board.diplo_ai_wait.erase(key)
	board._rebuild_diplomacy_rows()


func _on_concede(fac: int) -> void:
	if board == null or board._faction_out.has(fac):
		return
	board._defeat_faction(fac)


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


func _note_primary_global(pkt: Dictionary, sender: int) -> void:
	#（备份先记主节点全局包时间）26.10.22 01:52 s
	var globals: Dictionary = assign.get("globals", {})
	if pkt.get("sim_clock", null) != null and sender == int(globals.get("clock", 0)):
		_last_owner_ms["g:clock"] = Time.get_ticks_msec()
	if typeof(pkt.get("diplomacy", null)) == TYPE_DICTIONARY and sender == int(globals.get("diplo", 0)):
		_last_owner_ms["g:diplo"] = Time.get_ticks_msec()
	if pkt.has("occupy") and sender == int(globals.get("victory", 0)):
		_last_owner_ms["g:victory"] = Time.get_ticks_msec()
	#（备份先记主节点全局包时间）26.10.22 01:52 e


func _apply_globals(pkt: Dictionary, sender: int) -> void:
	_note_primary_global(pkt, sender)
	if pkt.get("sim_clock", null) != null and _global_from(sender, "clock") and not owns_global("clock"):
		board._sim_clock = float(pkt.get("sim_clock", board._sim_clock))
	var dip_v: Variant = pkt.get("diplomacy", null)
	if typeof(dip_v) == TYPE_DICTIONARY and board.data != null and _global_from(sender, "diplo") and not owns_global("diplo"):
		_last_owner_ms["g:diplo"] = Time.get_ticks_msec()
		board.data.diplomacy = dip_v
	if not owns_global("victory") and _global_from(sender, "victory"):
		_last_owner_ms["g:victory"] = Time.get_ticks_msec()
		var occ_v: Variant = pkt.get("occupy", null)
		if typeof(occ_v) == TYPE_DICTIONARY:
			for fac_v in (occ_v as Dictionary).keys():
				board._stat_fac(int(fac_v))["occupy_score"] = float((occ_v as Dictionary)[fac_v])


func _global_from(sender: int, name: String) -> bool:
	return sender == int(assign.get("globals", {}).get(name, 0)) or sender == int(assign.get("secondary", {}).get("g:" + name, 0))


func _zone_wants_unit(want: Dictionary, u: Dictionary) -> bool:
	if want.has(str(u.get("sys", ""))):
		return true
	var ph := int(u.get("phase", 0))
	if (ph == BoardTypes.MovePhase.INVULN or ph == BoardTypes.MovePhase.LANDING) and want.has(str(u.get("from_sys", ""))):
		return true
	if float(u.get("handoff_until", 0.0)) > float(board._sim_clock) and want.has(str(u.get("handoff_from", ""))):
		return true
	return false


func _motion_newer(u: Dictionary, row: Dictionary) -> bool:
	return int(row.get("motion_seq", 0)) > int(u.get("motion_seq", 0))


func _apply_motion_row(u: Dictionary, row: Dictionary, reason: String, structural: bool = true) -> void:
	var old_sys := str(u.get("sys", ""))
	var old_cell := int(u.get("cell", -1))
	var old_pos: Vector3 = u.get("pos", Vector3.ZERO)
	var pos: Array = row.get("pos", [])
	if pos.size() >= 3:
		var sim_p := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		u["pos"] = sim_p
		u["rest_pos"] = Vector3(sim_p.x, BoardTypes.UNIT_Y, sim_p.z)
	if row.has("phase"):
		u["phase"] = int(row.get("phase", u.get("phase", 0)))
	if row.has("phase_t"):
		u["phase_t"] = float(row.get("phase_t", 0.0))
	#（观察端套用权威朝向和终点）26.10.22 23:58 s
	var face_v: Variant = row.get("face", [])
	if face_v is Array and (face_v as Array).size() >= 2:
		u["face_dir"] = Vector3(float((face_v as Array)[0]), 0.0, float((face_v as Array)[1]))
	var to_v: Variant = row.get("to", [])
	if to_v is Array and (to_v as Array).size() >= 3:
		u["to_pos"] = Vector3(float((to_v as Array)[0]), float((to_v as Array)[1]), float((to_v as Array)[2]))
	#（观察端套用权威朝向和终点）26.10.22 23:58 e
	if not structural:
		return
	u["sys"] = str(row.get("sys", old_sys))
	u["cell"] = int(row.get("cell", old_cell))
	if row.has("from_sys"):
		u["from_sys"] = str(row.get("from_sys", ""))
		u["from_cell"] = int(row.get("from_cell", u.get("cell", 0)))
		u["to_sys"] = str(row.get("to_sys", u.get("sys", "")))
		u["to_cell"] = int(row.get("to_cell", u.get("cell", 0)))
		u["step_kind"] = str(row.get("step_kind", ""))
		u["step_invuln"] = float(row.get("step_invuln", 0.0))
	if row.has("order_dest_sys"):
		var dest_sys := str(row.get("order_dest_sys", ""))
		if dest_sys == "":
			u.erase("order_dest_sys")
			u.erase("order_dest_cell")
		else:
			u["order_dest_sys"] = dest_sys
			u["order_dest_cell"] = int(row.get("order_dest_cell", -1))
	if row.has("nav_standby"):
		u["nav_standby_on_sys_enter"] = bool(row.get("nav_standby", false))
	if row.has("path") and typeof(row.get("path", [])) == TYPE_ARRAY:
		u["path"] = _accepted_path(row.get("path", []))
	u["motion_seq"] = int(row.get("motion_seq", u.get("motion_seq", 0)))
	var new_pos: Vector3 = u.get("pos", old_pos)
	if old_sys != str(u.get("sys", "")) or old_cell != int(u.get("cell", -1)) or old_pos.distance_to(new_pos) > 0.4:
		DebugSessionLog.append("MOT", "mp_match_driver._apply_motion_row", reason, {
			"id": str(u.get("id", "")), "seq": int(u.get("motion_seq", 0)),
			"old": [old_sys, old_cell], "new": [str(u.get("sys", "")), int(u.get("cell", -1))],
			"runId": "motion-fence"
		})


func _write_combat(u: Dictionary, row: Dictionary, combat: bool = true) -> void:
	var inst_v: Variant = u.get("inst", {})
	var inst: Dictionary = inst_v if typeof(inst_v) == TYPE_DICTIONARY else {}
	if combat and row.has("cap"):
		inst["cap"] = float(row.get("cap", 0.0))
	if combat and row.has("max_cap"):
		inst["max_cap"] = float(row.get("max_cap", inst.get("max_cap", 0.0)))
	if not inst.is_empty():
		u["inst"] = inst
	if row.has("focus_id") and not sim_unit(u):
		u["focus_id"] = str(row.get("focus_id", ""))
	if row.has("step_t"):
		u["step_t"] = float(row.get("step_t", 0.0))
	if combat:
		_write_cds(u.get("weapons", []), row.get("weapon_cd", []))
		_write_cds(u.get("self_rep", []), row.get("repair_cd", []))
	if row.has("skirmish_left"):
		u["skirmish_left"] = float(row.get("skirmish_left", 0.0))
		u["skirmish_speed"] = float(row.get("skirmish_speed", 0.0))
		u["skirmish_prep"] = float(row.get("skirmish_prep", 0.0))
	var bursts_v: Variant = row.get("bursts", [])
	if combat and typeof(bursts_v) == TYPE_ARRAY:
		var local: Array = u.get("bursts", [])
		for i in mini(local.size(), (bursts_v as Array).size()):
			#（指挥波条目先确认是字典）26.10.22 10:25 s
			var src_v: Variant = (bursts_v as Array)[i]
			if typeof(src_v) != TYPE_DICTIONARY or typeof(local[i]) != TYPE_DICTIONARY:
				continue
			var src: Dictionary = src_v
			#（指挥波条目先确认是字典）26.10.22 10:25 e
			local[i]["cd"] = float(src.get("cd", 0.0))
			local[i]["remain"] = float(src.get("remain", 0.0))
			local[i]["auto_on"] = bool(src.get("auto_on", true))


func _write_cds(local: Variant, cds: Variant) -> void:
	if typeof(local) != TYPE_ARRAY or typeof(cds) != TYPE_ARRAY:
		return
	for i in mini((local as Array).size(), (cds as Array).size()):
		if typeof((local as Array)[i]) == TYPE_DICTIONARY:
			(local as Array)[i]["cd"] = float((cds as Array)[i])


func _on_fit(unit_id: String, kind: String, on: bool) -> void:
	var u: Dictionary = board._unit_by_id(unit_id)
	if u.is_empty() or not sim_unit(u):
		return
	_applying = true
	board.apply_fit_switch(u, kind, on, false)
	_applying = false


func _accepted_path(raw: Array) -> Array:
	#（路径步骤先查类型）26.10.22 10:25 s
	var out: Array = []
	for step_v in raw:
		if typeof(step_v) != TYPE_DICTIONARY:
			push_warning("EVERTBS path step is not a dictionary")
			continue
		var step: Dictionary = step_v
		if not step.has("to") or not step.has("kind") or str(step.get("kind", "")) == "":
			push_warning("EVERTBS path step missing to or kind")
			continue
		if str(step.get("kind", "")) == "jump" and typeof(step.get("to_sys", null)) != TYPE_STRING:
			push_warning("EVERTBS jump step missing to_sys")
			continue
		out.append(step.duplicate(true))
	#（路径步骤先查类型）26.10.22 10:25 e
	return out


func _clamp_layer(inst: Dictionary, cur_key: String, max_key: String) -> void:
	var cur := float(inst.get(cur_key, 0.0))
	if not is_finite(cur) or cur < 0.0:
		cur = 0.0
	var mx := float(inst.get(max_key, 0.0))
	if is_finite(mx) and mx >= 0.0 and cur > mx:
		cur = mx
	inst[cur_key] = cur


func _write_hull(u: Dictionary, row: Dictionary) -> void:
	var inst_v: Variant = u.get("inst", {})
	var inst: Dictionary = inst_v if typeof(inst_v) == TYPE_DICTIONARY else {}
	if inst.is_empty():
		return
	if row.has("shield"):
		inst["shield"] = float(row.get("shield", 0.0))
	if row.has("armor"):
		inst["armor"] = float(row.get("armor", 0.0))
	if row.has("structure"):
		inst["structure"] = float(row.get("structure", 0.0))
	#（已有单位套用当前上限并夹紧）26.10.22 10:25 s
	if row.has("max_s"):
		inst["max_s"] = float(row.get("max_s", inst.get("max_s", 0.0)))
	if row.has("max_a"):
		inst["max_a"] = float(row.get("max_a", inst.get("max_a", 0.0)))
	if row.has("max_h"):
		inst["max_h"] = float(row.get("max_h", inst.get("max_h", 0.0)))
	_clamp_layer(inst, "shield", "max_s")
	_clamp_layer(inst, "armor", "max_a")
	_clamp_layer(inst, "structure", "max_h")
	#（已有单位套用当前上限并夹紧）26.10.22 10:25 e
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
	if def.is_empty() or board.pilots_sys == null:
		return {}
	#（联机重建用本地表算原始上限）26.10.22 10:25 s
	var inst: Dictionary = board.pilots_sys.make_ship_instance(ship_id, board.pilots_sys._crew_eq(pilot))
	inst["shield"] = float(row.get("shield", inst.get("shield", 0.0)))
	inst["armor"] = float(row.get("armor", inst.get("armor", 0.0)))
	inst["structure"] = float(row.get("structure", inst.get("structure", 0.0)))
	if row.has("max_s"):
		inst["max_s"] = float(row.get("max_s", inst.get("max_s", 0.0)))
	if row.has("max_a"):
		inst["max_a"] = float(row.get("max_a", inst.get("max_a", 0.0)))
	if row.has("max_h"):
		inst["max_h"] = float(row.get("max_h", inst.get("max_h", 0.0)))
	#（联机重建用本地表算原始上限）26.10.22 10:25 e
	var spawned: Dictionary = board._spawn_unit(pilot, inst, str(row.get("sys", "")), int(row.get("cell", 0)))
	if spawned.is_empty():
		return {}
	spawned["id"] = uid
	#（联机远端舰补显示节点）26.10.22 17:58 s
	if board.has_node("Units"):
		board._ensure_unit_node(spawned)
	#（联机远端舰补显示节点）26.10.22 17:58 e
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
