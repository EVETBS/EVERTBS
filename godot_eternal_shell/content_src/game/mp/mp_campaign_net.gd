extends Node
class_name MpCampaignNet
## ENet session for custom-campaign rooms. Connection order matches SEMI_ASYNC:
## LAN discovery, invite IPv6/IPv4, STUN reflexive, TURN last. Probe once a second.

signal joined
signal failed(msg: String)
signal room_updated
signal chat_received(text: String, scope: String, faction: int)
signal zone_received(pkt: Dictionary, reliable: bool)
signal order_received(unit_id: String, to_sys: String, to_cell: int, focus_id: String)
signal fit_received(unit_id: String, kind: String, on: bool)
signal group_received(unit_id: String, group_id: int)
signal deputy_received(faction: int, group_id: int)
signal diplo_received(a: int, b: int, on: bool)
signal fog_received(on: bool)
signal match_over_received(winner: int, reason: String)
signal audit_sample(rows: Array)
signal assignment_updated
signal peers_changed
signal diplo_offer_received(from_fac: int, to_fac: int, on: bool)
signal concede_received(fac: int)
signal host_lost
signal disc_notice(text: String)

const GAME_BASE := 24567
const BEACON_PORT := 24567
const TICKET_PATH := "user://etb_campaign_ticket.json"
const HISTORY_PATH := "user://mp_match_history.json"
const TABLES_PATH := "user://mp_campaign_tables.json"
const PROGRESS_PATH := "user://mp_campaign_progress.json"
const BOOT_PATH := "user://board_boot.json"
const LAYOUT_PATH := "user://custom_layout.json"
const LIVE_PATH := "user://mp_campaign_live"

var is_host := false
var match_started := false
var reopen_room := false
var local_nick := ""
var room_code := 0
var room_password := ""
var rules_hash := ""
var listen_port := 0
var lan_ip := ""
var ipv6 := ""
var reflexive_ip := ""
var reflexive_port := 0
var bench := 1.0
var zone_ms := 0.0
var room: Dictionary = {}
var metrics: Dictionary = {}
var rtt_ms: Dictionary = {}
var progress: Dictionary = {}
var assignment: Dictionary = {}
var reports: Dictionary = {}
var world_presence: Dictionary = {}
var zone_sync: Array = []
var room_key := ""
var _progress_dirty := false
var _progress_flush := 0.0
var _layout_sig := ""
var _audit_watcher_id := 0
var host_gone := false
var disc_capture: Callable = Callable()
var disc_apply: Callable = Callable()
var _opening := false
var _opening_layout: Dictionary = {}
var _opening_tables: Dictionary = {}
var _opening_prog: Dictionary = {}
var _opening_loaded: Dictionary = {}
var _boot_layer: CanvasLayer
var _boot_label: Label
var _boot_bar: ProgressBar
var _disc_active := false
var _disc_pvp := false
var _disc_link_ok := false
var _disc_probed := false
var _disc_wait_until := 0.0
var _disc_line := ""
const PAGES_URL := "https://evetbs.github.io/EVERTBS-online-update/"
const DUEL_WAIT_S := 600.0

var _beacon: PacketPeerUDP
var _beacon_acc := 0.0
var _probe_acc := 0.0
var _heartbeat_acc := 0.0
var _bound := false
var _audit_target := 0
var _audit_until := 0


func host_room(nick: String, password: String) -> Error:
	_reset_peer()
	local_nick = nick
	room_password = password.strip_edges()
	room_code = randi_range(1, 9999)
	rules_hash = MatchRng.compute_rules_hash()
	bench = _calibrate()
	var peer := ENetMultiplayerPeer.new()
	listen_port = GAME_BASE + clampi(room_code, 1, 9999)
	var err := peer.create_server(listen_port, 16)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	_bind_signals()
	_refresh_ips()
	room = _empty_room()
	_add_member(1, local_nick, bench, rules_hash)
	room_key = "%08x" % randi()
	_open_beacon()
	call_deferred("_discover_stun")
	joined.emit()
	room_updated.emit()
	return OK


func join_share(raw: String, nick: String) -> void:
	local_nick = nick
	rules_hash = MatchRng.compute_rules_hash()
	bench = _calibrate()
	var cleaned := InviteBlobHelper.sanitize_paste(raw)
	var decoded: Dictionary = InviteBlobHelper.decode(cleaned)
	var code := _code_of(cleaned, decoded)
	var endpoints: Array = []
	if code > 0:
		var found: Array = await _discover_lan(1.2)
		for row_v in found:
			if typeof(row_v) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = row_v
			if str(row.get("kind", "")) != "etb_campaign":
				continue
			if int(row.get("code", 0)) != code:
				continue
			if bool(row.get("in_match", false)) and _ignore_running():
				continue
			endpoints.append({"ip": str(row.get("ip", "")), "port": int(row.get("port", 0))})
	for ep_v in InviteBlobHelper.join_endpoints(decoded):
		endpoints.append(ep_v)
	var direct := _parse_host_port(cleaned)
	if not direct.is_empty():
		endpoints.append(direct)
	for turn_v in NetConnectivity.turn_join_endpoints():
		endpoints.append(turn_v)
	var pw := str(decoded.get("password", room_password))
	room_password = pw
	var key := str(decoded.get("room_key", "")).strip_edges()
	if key != "":
		room_key = key
	for ep_v2 in endpoints:
		if typeof(ep_v2) != TYPE_DICTIONARY:
			continue
		var ep: Dictionary = ep_v2
		var ip := str(ep.get("ip", "")).strip_edges()
		var port := int(ep.get("port", 0))
		if ip == "" or port <= 0:
			continue
		var joined_ok := false
		for _try_i in range(3):
			var err := await _try_client(ip, port)
			if err == OK:
				joined_ok = true
				break
			push_warning("战役房间连接失败 %s:%d 第%d次 (%s)" % [ip, port, _try_i + 1, error_string(err)])
		if joined_ok:
			return
	failed.emit("连不上房间")


func match_public(nick: String, ignore_running: bool) -> void:
	local_nick = nick
	rules_hash = MatchRng.compute_rules_hash()
	bench = _calibrate()
	var found: Array = await _discover_lan(1.6)
	for row_v in found:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if str(row.get("kind", "")) != "etb_campaign":
			continue
		if bool(row.get("in_match", false)) and ignore_running:
			continue
		if bool(row.get("has_password", false)):
			continue
		var err := await _try_client(str(row.get("ip", "")), int(row.get("port", 0)))
		if err == OK:
			return
	failed.emit("没有可加入的公开房间")


func restore_room(nick: String) -> void:
	if not FileAccess.file_exists(TICKET_PATH):
		failed.emit("没有可恢复的房间")
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TICKET_PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		failed.emit("恢复票无效")
		return
	var d: Dictionary = raw
	var blob := str(d.get("invite", ""))
	if blob == "":
		blob = "%s:%d" % [str(d.get("ip", "")), int(d.get("port", 0))]
	room_password = str(d.get("password", ""))
	await join_share(blob, nick)


func disconnect_room() -> void:
	_reset_peer()
	room = {}
	match_started = false
	is_host = false


func invite_text() -> String:
	var extra := {
		"password": room_password,
		"reflexive_ip": reflexive_ip,
		"reflexive_port": reflexive_port if reflexive_port > 0 else listen_port,
		"ipv6": ipv6,
		"room_key": room_key,
	}
	var hip := lan_ip if lan_ip != "" else "127.0.0.1"
	return InviteBlobHelper.encode(hip, listen_port, str(room_code), rules_hash, extra)


func say_verbatim(text: String, scope: String, faction: int) -> void:
	if text == "":
		return
	if is_host:
		_fanout_chat(text, scope, faction, 0)
	elif multiplayer.has_multiplayer_peer():
		chat_received.emit(text, scope, faction)
		rpc_id(1, "rpc_chat", text, scope, faction)


func submit_intent(kind: String, payload: Dictionary) -> void:
	var body := JSON.stringify(payload)
	if is_host:
		_apply_intent(1, kind, payload)
	elif multiplayer.has_multiplayer_peer():
		rpc_id(1, "rpc_intent", kind, body)


func set_assignment(next: Dictionary) -> void:
	assignment = next


func publish_assignment(zones_in: Array, next: Dictionary) -> void:
	assignment = next
	var slim: Array = []
	for z_v in zones_in:
		if typeof(z_v) != TYPE_DICTIONARY:
			continue
		var z: Dictionary = z_v
		slim.append({
			"id": str(z.get("id", "")),
			"systems": z.get("systems", []),
			"hot": bool(z.get("hot", false)),
			"cost": float(z.get("cost", 1.0)),
			"facs": z.get("facs", []),
		})
	zone_sync = slim
	if is_host and match_started and multiplayer.has_multiplayer_peer():
		rpc("rpc_metrics", JSON.stringify(_metrics_blob()))


func note_zone_ms(ms: float) -> void:
	zone_ms = ms


func send_zone(pkt: Dictionary, hot: bool) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	_merge_progress(pkt)
	if is_host:
		_fanout_zone(pkt, hot, _self_id())
	elif hot:
		rpc_id(1, "rpc_zone_submit_light", JSON.stringify(pkt))
	else:
		rpc_id(1, "rpc_zone_submit", JSON.stringify(pkt))
	_maybe_audit(pkt)


func send_fit(unit_id: String, kind: String, on: bool, owner_peer: int) -> void:
	if owner_peer <= 0 or not multiplayer.has_multiplayer_peer():
		return
	if owner_peer == _self_id():
		return
	if is_host or owner_peer == 1:
		rpc_id(owner_peer, "rpc_fit", unit_id, kind, on)
	else:
		rpc_id(1, "rpc_fit_to", owner_peer, unit_id, kind, on)


func send_order(unit_id: String, to_sys: String, to_cell: int, owner_peer: int, focus_id: String = "") -> void:
	if owner_peer <= 0 or not multiplayer.has_multiplayer_peer():
		return
	if owner_peer == _self_id():
		return
	#（攻击目标随移动命令交给星系模拟者）26.10.22 16:45 s
	if is_host or owner_peer == 1:
		rpc_id(owner_peer, "rpc_order", unit_id, to_sys, to_cell, focus_id)
	else:
		rpc_id(1, "rpc_order_to", owner_peer, unit_id, to_sys, to_cell, focus_id)
	#（攻击目标随移动命令交给星系模拟者）26.10.22 16:45 e


func send_group(unit_id: String, group_id: int) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if is_host:
		for pid in _relay_targets(_self_id()):
			rpc_id(int(pid), "rpc_group", unit_id, group_id)
	else:
		rpc_id(1, "rpc_group", unit_id, group_id)


func send_deputy(faction: int, group_id: int) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if is_host:
		for pid in _relay_targets(_self_id()):
			rpc_id(int(pid), "rpc_deputy", faction, group_id)
	else:
		rpc_id(1, "rpc_deputy", faction, group_id)


func send_diplo(a: int, b: int, on: bool) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if is_host:
		for pid in _relay_targets(_self_id()):
			rpc_id(int(pid), "rpc_diplo", a, b, on)
	else:
		rpc_id(1, "rpc_diplo", a, b, on)


func send_diplo_offer(from_fac: int, to_fac: int, on: bool = true) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if is_host:
		_deliver_diplo_offer(from_fac, to_fac, _self_id(), on)
	else:
		rpc_id(1, "rpc_diplo_offer", from_fac, to_fac, on)


func send_concede(fac: int) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if is_host:
		for pid in _relay_targets(_self_id()):
			rpc_id(int(pid), "rpc_concede", fac)
	else:
		rpc_id(1, "rpc_concede", fac)


func send_fog(on: bool) -> void:
	room["fog"] = on
	if is_host:
		rpc("rpc_fog", on)
		room_updated.emit()
	else:
		rpc_id(1, "rpc_fog_req", on)


func send_match_over(winner: int, reason: String) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if is_host:
		for pid in _relay_targets(_self_id()):
			rpc_id(int(pid), "rpc_match_over", winner, reason)
	else:
		rpc_id(1, "rpc_match_over", winner, reason)


func request_audit(target_peer: int) -> void:
	if is_host:
		_audit_target = target_peer
		_audit_until = Time.get_ticks_msec() + 60000
		_audit_watcher_id = _self_id()
	elif multiplayer.has_multiplayer_peer():
		rpc_id(1, "rpc_audit_watch", target_peer)


func mod_install_request(path: String) -> void:
	_mod_line("rpc_mod_install_request", path)


func approve_mod_install(path: String) -> void:
	_mod_line("rpc_approve_mod_install", path)


func reject_mod_install(path: String) -> void:
	_mod_line("rpc_reject_mod_install", path)


func try_autostart() -> void:
	if not is_host or match_started or _opening:
		return
	if not _ready_to_start():
		return
	_opening = true
	#（开局冻结一份布局，进局不再重抽）26.10.22 21:40 s
	_opening_layout = _layout_for_match()
	#（开局冻结一份布局，进局不再重抽）26.10.22 21:40 e
	_opening_tables = _read_tables()
	_opening_prog = {"sim_clock": 0.0, "units": [], "cells": [], "diplomacy": {}}
	progress = _opening_prog
	_opening_loaded.clear()
	var content_hash := _content_hash(_opening_tables)
	_opening_tables["content_hash"] = content_hash
	_show_boot("正在核对数据", 0.2)
	var targets := _relay_targets(_self_id())
	if targets.is_empty():
		_finish_opening()
		return
	for pid in targets:
		rpc_id(int(pid), "rpc_opening_hash", content_hash)


func _process(delta: float) -> void:
	if _beacon != null:
		_beacon_acc += delta
		if _beacon_acc >= 1.0:
			_beacon_acc = 0.0
			_beacon_announce()
		_beacon_replies()
	if _disc_active and _disc_wait_until > 0.0 and Time.get_unix_time_from_system() >= _disc_wait_until:
		_disc_active = false
		_disc_line = "等待重连已到 10 分钟，对局继续。"
		disc_notice.emit(_disc_line)
	if not multiplayer.has_multiplayer_peer():
		return
	_probe_acc += delta
	if _probe_acc >= 1.0:
		_probe_acc = 0.0
		if multiplayer.get_peers().size() > 0:
			rpc("rpc_probe", Time.get_ticks_msec())
	_progress_flush += delta
	if _progress_dirty and _progress_flush >= 5.0:
		_flush_progress()
	_heartbeat_acc += delta
	if _heartbeat_acc < 1.0 or not is_host:
		return
	_heartbeat_acc = 0.0
	if not match_started:
		_broadcast_room()
	else:
		rpc("rpc_metrics", JSON.stringify(_metrics_blob()))


func _ready_to_start() -> bool:
	var humans := 0
	var ready_n := 0
	var seated := 0
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		var spectate := str(m.get("seat", "")) == "spectate" or bool(m.get("left", false))
		if not spectate:
			seated += 1
		if bool(m.get("ai", false)) or spectate or bool(m.get("left", false)):
			continue
		humans += 1
		if str(m.get("hash", "")) != "" and str(m.get("hash", "")) != rules_hash:
			return false
		if bool(m.get("ready", false)):
			if _roster_block(m) != "":
				return false
			ready_n += 1
	return humans >= 1 and ready_n == humans and seated >= 2 and not room.get("layout", {}).is_empty()


func _layout_for_match() -> Dictionary:
	_ensure_players_seated()
	var layout: Dictionary = (room.get("layout", {}) as Dictionary).duplicate(true)
	if str(layout.get("mp_match_id", "")) == "":
		layout["mp_match_id"] = "%s:%d" % [room_key, int(Time.get_unix_time_from_system())]
	var opening: Dictionary = {}
	var deps: Dictionary = {}
	var ai_facs: Array = []
	var pilots: Array = []
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		var fac := int(m.get("faction", 0))
		if fac <= 0:
			continue
		opening[str(m.get("seat", ""))] = fac
		deps[str(fac)] = str(m.get("deputy", "yang"))
		if bool(m.get("ai", false)):
			ai_facs.append(fac)
		var roster: Array = m.get("roster", [])
		var n := 1
		for p_v in roster:
			if typeof(p_v) == TYPE_DICTIONARY:
				var p: Dictionary = (p_v as Dictionary).duplicate(true)
				p["faction"] = fac
				p["home"] = str(m.get("seat", ""))
				p["id"] = "f%d_p%d" % [fac, n]
				n += 1
				pilots.append(p)
	layout["opening_stations"] = opening
	layout["deputies"] = deps
	layout["ai_factions"] = ai_facs
	layout["pilots"] = pilots
	layout["viewer_faction"] = _faction_of_peer(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1)
	layout["match_modes"] = room.get("modes", ["hua_di"])
	layout["match_limit_s"] = clampi(int(room.get("limit_s", 5400)), 600, 86400)
	layout["annihilate_goal"] = clampi(int(room.get("annihilate", 50)), 10, 1000)
	layout["fog_of_war"] = bool(room.get("fog", false))
	layout["mp"] = true
	var fac_names: Dictionary = {}
	for m2_v in room.get("members", []):
		if typeof(m2_v) != TYPE_DICTIONARY:
			continue
		var m2: Dictionary = m2_v
		var fac2 := int(m2.get("faction", 0))
		if fac2 <= 0 or bool(m2.get("ai", false)):
			continue
		var nick := str(m2.get("nick", "")).strip_edges()
		if nick != "":
			fac_names[str(fac2)] = nick
	layout["faction_names"] = fac_names
	#（联机冻结名单不再套本机配置）26.10.22 01:52 s
	layout["roster_applied"] = true
	#（联机冻结名单不再套本机配置）26.10.22 01:52 e
	return layout


func _layout_for_peer(pid: int) -> Dictionary:
	var layout := _layout_for_match()
	var fac := _faction_of_peer(pid)
	layout["viewer_faction"] = fac
	if fac <= 0:
		layout["fog_of_war"] = false
	return layout


func _enter_match(layout: Dictionary, tables: Dictionary, prog: Dictionary) -> void:
	_hide_boot()
	_opening = false
	host_gone = false
	match_started = true
	#（进局用冻结布局，不再按当时房间重做）26.10.22 21:40 s
	var mine := layout.duplicate(true)
	var fac := _faction_of_peer(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1)
	if fac > 0:
		mine["viewer_faction"] = fac
	elif int(mine.get("viewer_faction", 0)) <= 0:
		mine["fog_of_war"] = false
	#（进局用冻结布局，不再按当时房间重做）26.10.22 21:40 e
	_write_json(LAYOUT_PATH, mine)
	_write_json(TABLES_PATH, tables)
	_write_json(PROGRESS_PATH, prog)
	_write_json(BOOT_PATH, {"layout": LAYOUT_PATH})
	_write_json(LIVE_PATH, {"on": true})
	persist()
	get_tree().change_scene_to_file("res://game/board_test.tscn")


func close_match() -> void:
	_flush_progress()
	match_started = false
	_reset_peer()
	_remove_user(LIVE_PATH)
	_remove_user(TABLES_PATH)
	_remove_user(PROGRESS_PATH)


func finish_match(rec: Dictionary) -> void:
	#（终局才把提前离开的人移出房间，并给还在的人发最终结算）26.10.22 15:10 s
	upsert_history(rec)
	reopen_room = true
	match_started = false
	_remove_user(LIVE_PATH)
	if is_host:
		var kept: Array = []
		for m_v in room.get("members", []):
			if typeof(m_v) != TYPE_DICTIONARY:
				continue
			var m: Dictionary = m_v
			if bool(m.get("left", false)) and not bool(m.get("ai", false)):
				continue
			kept.append(m)
		room["members"] = kept
		for m2_v in kept:
			var m2: Dictionary = m2_v
			m2["left"] = false
			m2["offline"] = false
			if bool(m2.get("wants_spectate", false)):
				m2["seat"] = "spectate"
				m2["faction"] = 0
				m2["ready"] = true
			else:
				m2["seat"] = ""
				m2["ready"] = false
		_renumber()
		var body := JSON.stringify(rec)
		if multiplayer.has_multiplayer_peer():
			rpc("rpc_match_closed", body)
		_broadcast_room()
	#（终局才把提前离开的人移出房间，并给还在的人发最终结算）26.10.22 15:10 e


func leave_match(rec: Dictionary, concede_fac: int) -> void:
	upsert_history(rec)
	reopen_room = false
	if concede_fac > 0:
		send_concede(concede_fac)
	if is_host:
		var me := _member(1)
		if not me.is_empty():
			me["left"] = true
			me["settle"] = rec
		get_tree().create_timer(0.4).timeout.connect(_drop_local_after_leave)
		return
	submit_intent("leave", {"settle": rec})
	get_tree().create_timer(0.4).timeout.connect(_drop_local_after_leave)


func _drop_local_after_leave() -> void:
	_reset_peer()
	room = {}
	match_started = false
	is_host = false


func _ensure_players_seated() -> void:
	if not is_host or match_started:
		return
	var changed := false
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if bool(m.get("left", false)) or bool(m.get("wants_spectate", false)):
			continue
		if str(m.get("seat", "")) == "spectate":
			m["seat"] = ""
			m["faction"] = 0
			changed = true
	if changed:
		_renumber()


static func read_history() -> Array:
	if not FileAccess.file_exists(HISTORY_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HISTORY_PATH))
	return parsed if typeof(parsed) == TYPE_ARRAY else []


static func upsert_history(rec: Dictionary) -> void:
	if rec.is_empty():
		return
	var arr := read_history()
	var mid := str(rec.get("match_id", ""))
	if mid != "":
		for i in range(arr.size()):
			if typeof(arr[i]) != TYPE_DICTIONARY:
				continue
			if str((arr[i] as Dictionary).get("match_id", "")) != mid:
				continue
			if bool(rec.get("provisional", false)) and not bool((arr[i] as Dictionary).get("provisional", true)):
				return
			arr[i] = rec
			_write_history(arr)
			return
	arr.append(rec)
	_write_history(arr)


static func _write_history(arr: Array) -> void:
	var f := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(arr))
	f.close()


static func history_text() -> String:
	var arr := read_history()
	if arr.is_empty():
		return "还没有多人对战结算"
	var lines: PackedStringArray = PackedStringArray()
	for i in range(arr.size() - 1, -1, -1):
		if typeof(arr[i]) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = arr[i]
		var stamp := Time.get_datetime_string_from_unix_time(int(rec.get("at", 0)))
		var kind := "离场结算" if bool(rec.get("provisional", false)) else "最终结算"
		lines.append("%s  %s  %s" % [stamp, kind, str(rec.get("reason", ""))])
		var detail := str(rec.get("detail", ""))
		if detail != "":
			lines.append(detail)
		for row_v in rec.get("rows", []):
			if typeof(row_v) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = row_v
			lines.append("%s  制造%d  击毁%d  损失%d  占领%.0f" % [
				str(row.get("name", "")), int(row.get("built", 0)), int(row.get("kills", 0)),
				int(row.get("losses", 0)), float(row.get("occupy", 0.0)),
			])
		lines.append("")
	return "\n".join(lines)


func persist() -> void:
	var gs := get_node_or_null("/root/GameSession")
	if gs == null or get_parent() == gs:
		return
	reparent(gs)


func local_faction() -> int:
	if not multiplayer.has_multiplayer_peer():
		var members: Array = room.get("members", [])
		if members.is_empty() or typeof(members[0]) != TYPE_DICTIONARY:
			return 1
		return int((members[0] as Dictionary).get("faction", 1))
	return _faction_of_peer(multiplayer.get_unique_id())


func _empty_room() -> Dictionary:
	return {
		"code": room_code,
		"layout": {},
		"modes": ["hua_di"],
		"limit_s": 5400,
		"annihilate": 50,
		"scale": RosterTemplates.active_size(),
		"fog": false,
		"hash": rules_hash,
		"members": [],
	}


func _add_member(peer_id: int, nick: String, score: float, hash: String) -> void:
	var members: Array = room.get("members", [])
	for m_v in members:
		if typeof(m_v) == TYPE_DICTIONARY and int((m_v as Dictionary).get("peer", 0)) == peer_id:
			return
	members.append({
		"peer": peer_id,
		"nick": nick,
		"seat": "",
		"deputy": "yang",
		"ready": false,
		"ai": false,
		"faction": 0,
		"roster": [],
		"bench": score,
		"hash": hash,
	})
	room["members"] = members
	if not match_started:
		_renumber()


func _renumber() -> void:
	if match_started:
		return
	var fac := 1
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if str(m.get("seat", "")) == "spectate":
			m["faction"] = 0
			continue
		if fac > 8:
			m["seat"] = "spectate"
			m["faction"] = 0
			continue
		m["faction"] = fac
		fac += 1
	_fill_farthest()


func _fill_farthest() -> void:
	var stations := _station_ids(room.get("layout", {}))
	if stations.is_empty():
		return
	var need: Array = []
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if str(m.get("seat", "")) == "spectate":
			continue
		if str(m.get("seat", "")) == "" or not stations.has(str(m.get("seat", ""))):
			need.append(m)
	if need.is_empty():
		return
	var chosen: Array = []
	for m2_v in room.get("members", []):
		if typeof(m2_v) != TYPE_DICTIONARY:
			continue
		var seat := str((m2_v as Dictionary).get("seat", ""))
		if seat != "" and seat != "spectate" and stations.has(seat) and not chosen.has(seat):
			chosen.append(seat)
	for m3_v in need:
		var m3: Dictionary = m3_v
		var pick := _farthest_free(stations, chosen)
		if pick == "":
			m3["seat"] = "spectate"
			m3["faction"] = 0
		else:
			m3["seat"] = pick
			chosen.append(pick)


func _farthest_free(stations: Array, chosen: Array) -> String:
	if chosen.is_empty():
		if stations.size() == 1:
			return str(stations[0])
		var best_d := -1.0
		var pair_a := ""
		for i in range(stations.size()):
			for j in range(i + 1, stations.size()):
				var d := _sys_pos(str(stations[i])).distance_to(_sys_pos(str(stations[j])))
				if d > best_d:
					best_d = d
					pair_a = str(stations[i])
		return pair_a
	var best_sid := ""
	var best_min := -1.0
	for sid_v in stations:
		var sid := str(sid_v)
		if chosen.has(sid):
			continue
		var mn := INF
		for c_v in chosen:
			mn = minf(mn, _sys_pos(sid).distance_to(_sys_pos(str(c_v))))
		if mn > best_min:
			best_min = mn
			best_sid = sid
	return best_sid


func _sys_pos(sid: String) -> Vector2:
	var layout: Dictionary = room.get("layout", {})
	for s_v in layout.get("systems", []):
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		if str((s_v as Dictionary).get("id", "")) != sid:
			continue
		var pos: Array = (s_v as Dictionary).get("pos", [0.0, 0.0])
		return Vector2(float(pos[0] if pos.size() > 0 else 0.0), float(pos[1] if pos.size() > 1 else 0.0))
	return Vector2.ZERO


func _station_ids(layout_v: Variant) -> Array:
	var out: Array = []
	if typeof(layout_v) != TYPE_DICTIONARY:
		return out
	for s_v in (layout_v as Dictionary).get("systems", []):
		if typeof(s_v) != TYPE_DICTIONARY:
			continue
		if str((s_v as Dictionary).get("kind", "")) == "station_system":
			out.append(str((s_v as Dictionary).get("id", "")))
	return out


func _apply_intent(sender: int, kind: String, payload: Dictionary) -> void:
	if not is_host:
		return
	var member := _member(sender)
	if member.is_empty() and kind != "hello":
		return
	#（开局核对期间不再改名单和规则）26.10.22 21:40 s
	if _opening and kind != "report":
		return
	#（开局核对期间不再改名单和规则）26.10.22 21:40 e
	match kind:
		"ready":
			var want_ready := bool(payload.get("on", false))
			if want_ready:
				var why := _roster_block(member)
				if why != "":
					member["ready"] = false
					_fanout_chat("[全体] %s：名单未通过（%s）" % [str(member.get("nick", "")), why], "all", 0, 0)
				else:
					member["ready"] = true
			else:
				member["ready"] = false
		"deputy":
			member["deputy"] = str(payload.get("id", "yang"))
			member["ready"] = false
		"roster":
			member["roster"] = payload.get("pilots", [])
			if payload.has("crew"):
				member["crew"] = payload.get("crew", [])
			member["ready"] = false
		"seat":
			if not match_started:
				var target := int(payload.get("peer", sender))
				var ai_index := int(payload.get("ai", -1))
				#（每人能改自己的出生站，房主能改所有人）26.10.22 15:10 s
				if sender != 1 and (ai_index > 0 or target != sender):
					pass
				else:
					var row := _member(target) if target > 0 else _member_ai(ai_index)
					if not row.is_empty():
						var new_seat := str(payload.get("seat", "spectate"))
						var old_seat := str(row.get("seat", ""))
						if new_seat != "" and new_seat != "spectate":
							for other_v in room.get("members", []):
								if typeof(other_v) != TYPE_DICTIONARY:
									continue
								var other: Dictionary = other_v
								if other == row:
									continue
								if str(other.get("seat", "")) == new_seat:
									other["seat"] = old_seat if old_seat != "" else "spectate"
									other["wants_spectate"] = false
									other["ready"] = false
						row["seat"] = new_seat
						row["wants_spectate"] = new_seat == "spectate"
						row["ready"] = false
						_renumber()
				#（每人能改自己的出生站，房主能改所有人）26.10.22 15:10 e
		"leave":
			if not member.is_empty():
				member["left"] = true
				member["offline"] = true
				member["peer"] = 0
				var settle_v: Variant = payload.get("settle", {})
				if typeof(settle_v) == TYPE_DICTIONARY:
					member["settle"] = settle_v
		"rules":
			if sender == 1:
				var scale_changed := payload.has("scale") and int(payload.get("scale", 0)) != int(room.get("scale", 0))
				var touched := false
				for key in ["modes", "limit_s", "annihilate", "scale", "fog"]:
					if payload.has(key):
						room[key] = payload[key]
						touched = true
				if touched:
					for ready_row_v in room.get("members", []):
						if typeof(ready_row_v) != TYPE_DICTIONARY:
							continue
						if not bool((ready_row_v as Dictionary).get("ai", false)):
							(ready_row_v as Dictionary)["ready"] = false
				if scale_changed:
					for m_v in room.get("members", []):
						if typeof(m_v) != TYPE_DICTIONARY:
							continue
						var m: Dictionary = m_v
						m["roster"] = []
						m["crew"] = []
						if not bool(m.get("ai", false)):
							m["ready"] = false
					_fill_ai_roster()
		"map":
			if sender == 1 and typeof(payload.get("layout", {})) == TYPE_DICTIONARY:
				room["layout"] = payload["layout"]
				_layout_sig = ""
				for m_v in room.get("members", []):
					if typeof(m_v) == TYPE_DICTIONARY:
						(m_v as Dictionary)["seat"] = ""
						(m_v as Dictionary)["ready"] = false
				_renumber()
		"add_ai":
			if sender == 1:
				_add_ai(str(payload.get("deputy", "yang")))
		"suggest":
			var line := "[全体] %s：希望把%s调整为%s" % [str(member.get("nick", "")), str(payload.get("item", "")), str(payload.get("value", ""))]
			_fanout_chat(line, "all", 0, 0)
		"urge":
			var who := _member(int(payload.get("peer", 0)))
			var line2 := "[全体] %s：请%s尽快准备" % [str(member.get("nick", "")), str(who.get("nick", ""))]
			_fanout_chat(line2, "all", 0, 0)
		"report":
			member["bench"] = float(payload.get("bench", member.get("bench", 1.0)))
			reports[sender] = payload
	if kind != "report":
		_broadcast_room()
	else:
		room_updated.emit()
	try_autostart()


func _add_ai(deputy: String) -> void:
	var members: Array = room.get("members", [])
	var n := 1
	for m_v in members:
		if typeof(m_v) == TYPE_DICTIONARY and bool((m_v as Dictionary).get("ai", false)):
			n += 1
	members.append({
		"peer": 0,
		"ai": true,
		"ai_index": n,
		"nick": "人机%d" % n,
		"seat": "",
		"deputy": deputy,
		"ready": true,
		"faction": 0,
		"roster": [],
		"bench": 0.0,
		"hash": rules_hash,
	})
	room["members"] = members
	_renumber()
	_fill_ai_roster()


func _fill_ai_roster() -> void:
	var scale := int(room.get("scale", 20))
	var r := RandomNumberGenerator.new()
	r.randomize()
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if not bool(m.get("ai", false)):
			continue
		if (m.get("roster", []) as Array).is_empty():
			m["roster"] = _pilots_from_resolve(RosterTemplates.resolve_ai(scale, r), int(m.get("faction", 0)), str(m.get("seat", "")), true, r)


func _pilots_from_resolve(res: Dictionary, fac: int, home: String, ai: bool, r: RandomNumberGenerator) -> Array:
	var members := {}
	for row_v in MemberTable.load_merged():
		if typeof(row_v) == TYPE_DICTIONARY:
			members[str((row_v as Dictionary).get("id", ""))] = row_v
	var ship_ids: Array = []
	var ships_root: Variant = _read_json_file("res://data/board/ships.json")
	if typeof(ships_root) == TYPE_DICTIONARY:
		for s_v in (ships_root as Dictionary).get("ships", []):
			if typeof(s_v) != TYPE_DICTIONARY:
				continue
			var sdef: Dictionary = s_v
			if bool(sdef.get("npc_hull", false)) or bool(sdef.get("npc", false)):
				continue
			var sid := str(sdef.get("id", "")).strip_edges()
			if sid != "":
				ship_ids.append(sid)
	var ids: PackedStringArray = res.get("ids", PackedStringArray())
	var starters: Dictionary = res.get("starters", {})
	var out: Array = []
	for n in range(ids.size()):
		var mid := str(ids[n])
		var mem: Dictionary = members.get(mid, {})
		var ship_id := str(mem.get("default_ship", "")).strip_edges()
		if ai and not ship_ids.is_empty():
			ship_id = str(ship_ids[r.randi_range(0, ship_ids.size() - 1)])
		if ship_id not in ship_ids and not ship_ids.is_empty():
			ship_id = str(ship_ids[n % ship_ids.size()])
		out.append({
			"id": "f%d_p%d" % [fac, n + 1],
			"name": str(mem.get("name", "军团%d-%d" % [fac, n + 1])),
			"faction": fac,
			"home": home,
			"ship": ship_id,
			"member_id": mid,
			"cell_kind": "station",
			"starter": starters.has(mid),
			"pref_eq": str(mem.get("pref_eq", "")),
		})
	return out


func build_local_roster(scale: int) -> Array:
	var r := RandomNumberGenerator.new()
	#（同一份模版关闭和准备得到同一份名单）26.10.22 21:40 s
	var entry: Dictionary = RosterTemplates.get_entry(scale)
	var on_ids: PackedStringArray = entry.get("onfield", PackedStringArray())
	var st_ids: PackedStringArray = entry.get("starters", PackedStringArray())
	r.seed = hash("%d|%s|%s" % [scale, "|".join(on_ids), "|".join(st_ids)])
	#（同一份模版关闭和准备得到同一份名单）26.10.22 21:40 e
	var fac := local_faction()
	var home := ""
	var me := _member(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1)
	home = str(me.get("seat", ""))
	var built: Array = _pilots_from_resolve(RosterTemplates.resolve(scale, r), fac, home, false, r)
	# #region agent log
	var ids: PackedStringArray = PackedStringArray()
	for p_v in built:
		if typeof(p_v) == TYPE_DICTIONARY:
			ids.append(str((p_v as Dictionary).get("member_id", "")))
	var ships := PackedStringArray()
	for p2_v in built:
		if typeof(p2_v) == TYPE_DICTIONARY:
			ships.append(str((p2_v as Dictionary).get("ship", "")))
	DebugSessionLog.append("ROSTER", "mp_campaign_net.build_local_roster", "mount", {
		"scale": scale,
		"n": built.size(),
		"ids": ",".join(ids),
		"ships": ",".join(ships),
		"runId": "post-fix",
		"hypothesisId": "R1",
	})
	# #endregion
	return built


func _roster_block(member: Dictionary) -> String:
	if str(member.get("seat", "")) == "spectate" or bool(member.get("left", false)):
		return ""
	var scale := int(room.get("scale", 20))
	var roster: Array = member.get("roster", [])
	if roster.size() != scale:
		return "人数不是本局 %d 人" % scale
	var playable := {}
	var ships_root: Variant = _read_json_file("res://data/board/ships.json")
	if typeof(ships_root) == TYPE_DICTIONARY:
		for s_v in (ships_root as Dictionary).get("ships", []):
			if typeof(s_v) != TYPE_DICTIONARY:
				continue
			var sdef: Dictionary = s_v
			if bool(sdef.get("npc_hull", false)) or bool(sdef.get("npc", false)):
				continue
			var sid := str(sdef.get("id", "")).strip_edges()
			if sid != "":
				playable[sid] = true
	var seen := {}
	var starters := 0
	for p_v in roster:
		if typeof(p_v) != TYPE_DICTIONARY:
			return "名单缺驾驶员"
		var p: Dictionary = p_v
		var mid := str(p.get("member_id", "")).strip_edges()
		if mid == "" or seen.has(mid):
			return "驾驶员重复或为空"
		seen[mid] = true
		var ship := str(p.get("ship", "")).strip_edges()
		if not playable.has(ship):
			return "舰型无效"
		if bool(p.get("starter", false)):
			starters += 1
	if starters > scale / 2:
		return "首发超过 %d" % (scale / 2)
	return ""


func crew_for_roster(pilots: Array) -> Array:
	var member_script = load("res://game/board/pilots/member_table.gd")
	var pack = load("res://game/board/pilots/custom_member_pack.gd")
	if member_script == null or pack == null:
		return []
	var by := {}
	for row_v in member_script.load_merged():
		if typeof(row_v) == TYPE_DICTIONARY:
			by[str((row_v as Dictionary).get("id", ""))] = row_v
	var out: Array = []
	var seen := {}
	for p_v in pilots:
		if typeof(p_v) != TYPE_DICTIONARY:
			continue
		var mid := str((p_v as Dictionary).get("member_id", ""))
		if mid.length() == 8 or seen.has(mid) or not by.has(mid):
			continue
		seen[mid] = true
		out.append(pack.portable_row((by[mid] as Dictionary).duplicate(true)))
	return out


func _member(peer_id: int) -> Dictionary:
	for m_v in room.get("members", []):
		if typeof(m_v) == TYPE_DICTIONARY and int((m_v as Dictionary).get("peer", 0)) == peer_id and not bool((m_v as Dictionary).get("ai", false)):
			return m_v
	return {}


func _member_ai(index: int) -> Dictionary:
	for m_v in room.get("members", []):
		if typeof(m_v) == TYPE_DICTIONARY and bool((m_v as Dictionary).get("ai", false)) and int((m_v as Dictionary).get("ai_index", 0)) == index:
			return m_v
	return {}


func _faction_of_peer(peer_id: int) -> int:
	return int(_member(peer_id).get("faction", 0))


func _nick_of(peer_id: int) -> String:
	var nick := str(_member(peer_id).get("nick", ""))
	return nick if nick != "" else "玩家"


func _fanout_chat(text: String, scope: String, faction: int, skip_peer: int) -> void:
	chat_received.emit(text, scope, faction)
	if not multiplayer.has_multiplayer_peer():
		return
	for pid in multiplayer.get_peers():
		if int(pid) == skip_peer:
			continue
		if scope == "faction" and _faction_of_peer(int(pid)) != faction and _faction_of_peer(int(pid)) != 0:
			continue
		if scope == "faction" and _faction_of_peer(int(pid)) == 0:
			continue
		rpc_id(int(pid), "rpc_chat", text, scope, faction)


func _filter_pkt(pkt: Dictionary, pid: int) -> Dictionary:
	var base := pkt.duplicate(true)
	var hot := bool(base.get("hot_wire", false))
	if not bool(room.get("fog", false)) or _faction_of_peer(pid) <= 0 or _peer_sims(pid, str(base.get("zone", ""))):
		if hot:
			base.erase("vision")
		return base
	var fac := _faction_of_peer(pid)
	var vis: Dictionary = {}
	var vision_v: Variant = base.get("vision", {})
	if typeof(vision_v) == TYPE_DICTIONARY:
		var raw: Variant = (vision_v as Dictionary).get(str(fac), {})
		if typeof(raw) == TYPE_DICTIONARY:
			vis = raw
	var units: Array = []
	for u_v in base.get("units", []):
		if typeof(u_v) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = u_v
		if not bool(u.get("alive", true)):
			units.append({"id": str(u.get("id", "")), "alive": false})
			continue
		if vis.has(str(u.get("sys", ""))):
			units.append(u)
	base["units"] = units
	var arcs_v: Variant = base.get("arcs", {})
	var arcs: Dictionary = {}
	if typeof(arcs_v) == TYPE_DICTIONARY:
		for sid_v in (arcs_v as Dictionary).keys():
			if vis.has(str(sid_v)):
				arcs[str(sid_v)] = (arcs_v as Dictionary)[sid_v]
	base["arcs"] = arcs
	if hot:
		base.erase("vision")
	return base


func _peer_sims(pid: int, zone: String) -> bool:
	var primary: Dictionary = assignment.get("primary", {})
	var secondary: Dictionary = assignment.get("secondary", {})
	return int(primary.get(zone, 0)) == pid or int(secondary.get(zone, 0)) == pid


func _merge_progress(pkt: Dictionary) -> void:
	if progress.is_empty():
		progress = {"sim_clock": 0.0, "units": [], "arcs": {}, "diplomacy": {}}
	var by_id: Dictionary = {}
	for u_v in progress.get("units", []):
		if typeof(u_v) == TYPE_DICTIONARY:
			by_id[str((u_v as Dictionary).get("id", ""))] = u_v
	for u2_v in pkt.get("units", []):
		if typeof(u2_v) != TYPE_DICTIONARY:
			continue
		#（进度缓存留下序号更新的移动记录）26.10.22 21:05 s
		var incoming: Dictionary = u2_v
		var uid := str(incoming.get("id", ""))
		var old_v: Variant = by_id.get(uid, null)
		if typeof(old_v) == TYPE_DICTIONARY and int((old_v as Dictionary).get("motion_seq", 0)) > int(incoming.get("motion_seq", 0)):
			continue
		by_id[uid] = incoming
		#（进度缓存留下序号更新的移动记录）26.10.22 21:05 e
	progress["units"] = by_id.values()
	var arcs: Dictionary = progress.get("arcs", {})
	if typeof(arcs) != TYPE_DICTIONARY:
		arcs = {}
	var pkt_arcs: Variant = pkt.get("arcs", {})
	if typeof(pkt_arcs) == TYPE_DICTIONARY:
		for sid_v in (pkt_arcs as Dictionary).keys():
			arcs[str(sid_v)] = (pkt_arcs as Dictionary)[sid_v]
	progress["arcs"] = arcs
	if pkt.get("sim_clock", null) != null:
		progress["sim_clock"] = pkt["sim_clock"]
	if typeof(pkt.get("diplomacy", null)) == TYPE_DICTIONARY:
		progress["diplomacy"] = pkt["diplomacy"]
	var kills: Dictionary = {}
	var old_kills: Variant = progress.get("kills", {})
	if typeof(old_kills) == TYPE_DICTIONARY:
		kills = old_kills as Dictionary
	for kill_v in pkt.get("kills", []):
		if typeof(kill_v) == TYPE_DICTIONARY:
			kills[str((kill_v as Dictionary).get("id", ""))] = kill_v
	progress["kills"] = kills
	if typeof(pkt.get("occupy", null)) == TYPE_DICTIONARY:
		progress["occupy"] = pkt["occupy"]
	var pres_v: Variant = pkt.get("presence", {})
	if typeof(pres_v) == TYPE_DICTIONARY:
		for sid2_v in (pres_v as Dictionary).keys():
			world_presence[str(sid2_v)] = (pres_v as Dictionary)[sid2_v]
		progress["presence"] = world_presence.duplicate(true)
	_progress_dirty = true


func _flush_progress() -> void:
	_progress_flush = 0.0
	if not _progress_dirty:
		return
	_progress_dirty = false
	_write_json(PROGRESS_PATH, progress)


func _metrics_blob() -> Dictionary:
	var peers: Dictionary = {}
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if bool(m.get("ai", false)) or bool(m.get("offline", false)):
			continue
		var pid := int(m.get("peer", 0))
		if pid <= 0:
			continue
		var rep_v: Variant = reports.get(pid, {})
		var rep: Dictionary = rep_v if typeof(rep_v) == TYPE_DICTIONARY else {}
		var spent := zone_ms if pid == _self_id() else float(rep.get("zone_ms", 0.0))
		peers[pid] = {
			"bench": float(m.get("bench", 1.0)),
			"zone_ms": spent,
			"rtt": _rtt_estimate(pid),
			"spectate": str(m.get("seat", "")) == "spectate",
			"faction": int(m.get("faction", 0)),
		}
	return {"peers": peers, "assignment": assignment, "zones": zone_sync}


func _push_audit_samples() -> void:
	if _audit_target == 0 or Time.get_ticks_msec() >= _audit_until:
		return
	var watcher := _audit_watcher()
	if watcher <= 0:
		return
	_send_audit_rows(progress.get("units", []))


func _audit_watcher() -> int:
	return _audit_watcher_id


func _read_tables() -> Dictionary:
	var ships: Array = []
	var equip: Dictionary = {}
	var ds := get_node_or_null("/root/DataStore")
	if ds != null:
		var mem: Variant = ds.get("host_ships_override")
		if typeof(mem) != TYPE_DICTIONARY or (mem as Dictionary).is_empty():
			mem = ds.get("ships")
		if typeof(mem) == TYPE_DICTIONARY and not (mem as Dictionary).is_empty():
			ships = (mem as Dictionary).values()
		elif typeof(mem) == TYPE_ARRAY and not (mem as Array).is_empty():
			ships = mem
		var eq_v: Variant = ds.get("equipment")
		if typeof(eq_v) == TYPE_DICTIONARY and not (eq_v as Dictionary).is_empty():
			equip = eq_v
	if ships.is_empty():
		var ships_root: Variant = _read_json_file("res://data/board/ships.json")
		if typeof(ships_root) == TYPE_DICTIONARY:
			ships = (ships_root as Dictionary).get("ships", [])
	if equip.is_empty():
		var equip_file: Variant = _read_json_file("res://data/board/equipment.json")
		if typeof(equip_file) == TYPE_DICTIONARY:
			equip = equip_file
	var members: Array = []
	var member_script = load("res://game/board/pilots/member_table.gd")
	if member_script != null:
		members = member_script.load_merged()
	members = _merge_peer_crew(members)
	return {"ships": ships, "equipment": equip, "members": members, "hash": rules_hash}


func _merge_peer_crew(rows: Array) -> Array:
	var by := {}
	var order: Array = []
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = (row_v as Dictionary).duplicate(true)
		var mid := str(row.get("id", ""))
		if mid == "" or by.has(mid):
			continue
		by[mid] = row
		order.append(mid)
	var pack = load("res://game/board/pilots/custom_member_pack.gd")
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var seat: Dictionary = m_v
		if bool(seat.get("ai", false)):
			continue
		var remap := {}
		for crew_v in seat.get("crew", []):
			if typeof(crew_v) != TYPE_DICTIONARY:
				continue
			var src: Dictionary = (crew_v as Dictionary).duplicate(true)
			var sid := str(src.get("id", ""))
			if sid.length() == 8 and sid.is_valid_int():
				continue
			var why := ""
			if pack != null:
				why = str(pack.reject_reason(src))
				if why == "":
					pack.fit_bonus(src)
			if why != "":
				_fanout_chat("[全体] 团员 %s %s，本局不带入" % [str(src.get("name", sid)), why], "all", 0, 0)
				remap[sid] = ""
				continue
			var assigned := sid
			if by.has(assigned):
				assigned = _free_six(by, sid.substr(0, 2) if sid.length() >= 2 else "00")
			if assigned == "":
				_fanout_chat("[全体] 团员 %s 编号已满，本局不带入" % str(src.get("name", sid)), "all", 0, 0)
				remap[sid] = ""
				continue
			src["id"] = assigned
			by[assigned] = src
			if not order.has(assigned):
				order.append(assigned)
			if assigned != sid:
				remap[sid] = assigned
		for p_v in seat.get("roster", []):
			if typeof(p_v) != TYPE_DICTIONARY:
				continue
			var pilot: Dictionary = p_v
			var pmid := str(pilot.get("member_id", ""))
			if remap.has(pmid):
				pilot["member_id"] = str(remap[pmid])
	var out: Array = []
	for mid2 in order:
		out.append(by[mid2])
	return out


func _free_six(by: Dictionary, prefix: String) -> String:
	if prefix.length() != 2 or not prefix.is_valid_int():
		prefix = "00"
	for n in 10000:
		var candidate := prefix + "%04d" % n
		if not by.has(candidate):
			return candidate
	return ""


func _mod_line(method: String, path: String) -> void:
	if is_host:
		call(method, path)
	elif multiplayer.has_multiplayer_peer():
		rpc_id(1, method, path)


func _self_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1


func _relay_targets(skip: int) -> Array:
	var out: Array = []
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if bool(m.get("ai", false)) or bool(m.get("offline", false)):
			continue
		var pid := int(m.get("peer", 0))
		if pid <= 0 or pid == skip or pid == _self_id():
			continue
		out.append(pid)
	return out


func _fanout_zone(pkt: Dictionary, hot: bool, skip: int) -> void:
	var wire := pkt.duplicate(true)
	if hot:
		wire["hot_wire"] = true
	for pid_v in _relay_targets(skip):
		var pid := int(pid_v)
		var view := _filter_pkt(wire, pid)
		var body := JSON.stringify(view)
		if hot:
			rpc_id(pid, "rpc_zone_light", body)
		else:
			rpc_id(pid, "rpc_zone", body)


func _accept_zone(body: String, hot: bool) -> void:
	if not is_host:
		return
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var pkt: Dictionary = parsed
	var sender := multiplayer.get_remote_sender_id()
	_merge_progress(pkt)
	zone_received.emit(pkt, not hot)
	_fanout_zone(pkt, hot, sender)
	_maybe_audit(pkt)


func _maybe_audit(pkt: Dictionary) -> void:
	if _audit_target == 0 or Time.get_ticks_msec() >= _audit_until:
		return
	if int(pkt.get("owner", 0)) != _audit_target:
		return
	_send_audit_rows(pkt.get("units", []))


func _send_audit_rows(rows_v: Variant) -> void:
	var watcher := _audit_watcher()
	if watcher <= 0:
		return
	var rows: Array = rows_v if rows_v is Array else []
	if watcher == _self_id():
		audit_sample.emit(rows)
		return
	var body := JSON.stringify(rows)
	if is_host or watcher == 1:
		rpc_id(watcher, "rpc_audit_sample", body)
	else:
		rpc_id(1, "rpc_audit_fwd", watcher, body)


func _broadcast_room() -> void:
	room_updated.emit()
	if not is_host or not multiplayer.has_multiplayer_peer():
		return
	rpc("rpc_room", _room_body())


func _room_body() -> String:
	var layout_v: Variant = room.get("layout", {})
	var sig := str(layout_v.hash()) if typeof(layout_v) == TYPE_DICTIONARY else ""
	var wire: Dictionary = room.duplicate(true)
	if sig != "" and sig == _layout_sig:
		wire.erase("layout")
		wire["layout_kept"] = true
	else:
		_layout_sig = sig
	return JSON.stringify(wire)


func _rtt_estimate(pid: int) -> Dictionary:
	var out: Dictionary = {}
	var ids: Array = []
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if bool(m.get("offline", false)) or bool(m.get("ai", false)):
			continue
		var other := int(m.get("peer", 0))
		if other > 0:
			ids.append(other)
	for other_v in ids:
		var other := int(other_v)
		if other == pid:
			continue
		if pid == _self_id():
			out[other] = int(rtt_ms.get(other, 80))
		elif other == _self_id():
			out[other] = int(rtt_ms.get(pid, 80))
		else:
			out[other] = int(rtt_ms.get(pid, 80)) + int(rtt_ms.get(other, 80))
	return out


func _reclaim_member(pid: int, nick: String, ticket_key: String) -> bool:
	var ticket_ok := ticket_key != "" and ticket_key == room_key
	var found: Dictionary = {}
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if bool(m.get("ai", false)) or bool(m.get("left", false)) or str(m.get("nick", "")) != nick:
			continue
		var old := int(m.get("peer", 0))
		if old == 1 and pid != 1:
			continue
		if not ticket_ok and not bool(m.get("offline", false)) and old != 0:
			continue
		if found.is_empty() or int(m.get("faction", 0)) > int(found.get("faction", 0)):
			found = m
	if found.is_empty():
		return false
	var prev := int(found.get("peer", 0))
	found["peer"] = pid
	found["offline"] = false
	if prev > 1 and prev != pid and multiplayer.get_peers().has(prev):
		multiplayer.disconnect_peer(prev)
	return true


func _add_spectator(pid: int, nick: String, score: float, hash: String) -> void:
	var members: Array = room.get("members", [])
	members.append({
		"peer": pid,
		"nick": nick,
		"seat": "spectate",
		"deputy": "yang",
		"ready": true,
		"ai": false,
		"offline": false,
		"faction": 0,
		"roster": [],
		"bench": score,
		"hash": hash,
	})
	room["members"] = members


func _deliver_diplo_offer(from_fac: int, to_fac: int, skip: int, on: bool = true) -> void:
	var target := 0
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if int(m.get("faction", 0)) == to_fac and int(m.get("peer", 0)) > 0:
			target = int(m.get("peer", 0))
			break
	if target == 0 or target == skip:
		return
	if target == _self_id():
		diplo_offer_received.emit(from_fac, to_fac, on)
	else:
		rpc_id(target, "rpc_diplo_offer_to", from_fac, to_fac, on)


func _remove_user(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _bind_signals() -> void:
	if _bound:
		return
	_bound = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	_apply_timeout(id)


func _on_peer_disconnected(id: int) -> void:
	rtt_ms.erase(id)
	reports.erase(id)
	if not is_host:
		return
	if match_started:
		var gone := _member(id)
		if not gone.is_empty() and not bool(gone.get("ai", false)):
			#（掉线按主动离开留在名单里，先记一笔，终局才删）26.10.22 15:10 s
			gone["offline"] = true
			gone["peer"] = 0
			gone["left"] = true
			#（掉线按主动离开留在名单里，先记一笔，终局才删）26.10.22 15:10 e
			_begin_disc_wait()
		peers_changed.emit()
		_broadcast_room()
		return
	var kept: Array = []
	for m_v in room.get("members", []):
		if typeof(m_v) == TYPE_DICTIONARY and int((m_v as Dictionary).get("peer", 0)) == id and not bool((m_v as Dictionary).get("ai", false)):
			continue
		kept.append(m_v)
	room["members"] = kept
	_renumber()
	_broadcast_room()


func _on_connected() -> void:
	_apply_timeout(1)
	rpc_id(1, "rpc_hello", local_nick, rules_hash, room_password, bench, room_key)


func _on_connection_failed() -> void:
	pass


func _on_server_disconnected() -> void:
	if match_started:
		host_gone = true
		_begin_disc_wait()
		host_lost.emit()
		return
	failed.emit("与房主断开")


func _apply_timeout(id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var pkt := enet.get_peer(id)
	if pkt != null:
		pkt.set_timeout(32, 10000, 45000)


func _try_client(ip: String, port: int) -> Error:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	_bind_signals()
	var waited := 0.0
	while waited < 8.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if multiplayer.multiplayer_peer == null:
			return ERR_CANT_CONNECT
		var st := multiplayer.multiplayer_peer.get_connection_status()
		if st == MultiplayerPeer.CONNECTION_CONNECTED:
			return OK
		if st == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return ERR_CANT_CONNECT
	_reset_peer()
	return ERR_TIMEOUT


func _reset_peer() -> void:
	_close_beacon()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_host = false


func _calibrate() -> float:
	var t0 := Time.get_ticks_usec()
	var n := 0
	var acc := 0.0
	while Time.get_ticks_usec() - t0 < 50000:
		acc += sin(float(n) * 0.017) * float((n % 5) + 1)
		n += 1
	var dt := maxf(float(Time.get_ticks_usec() - t0) / 1000000.0, 0.001)
	if acc == 0.0:
		acc = 0.0
	return maxf(float(n) / dt, 1.0)


func _refresh_ips() -> void:
	ipv6 = ""
	for addr_v in IP.get_local_addresses():
		var addr := str(addr_v)
		if addr.find(":") >= 0 and ipv6 == "" and not addr.begins_with("fe80"):
			ipv6 = addr
	var picked := LanAffinity.best_local_ipv4()
	lan_ip = "" if picked == "127.0.0.1" else picked
	DebugSessionLog.append("NET", "mp_campaign_net._refresh_ips", "lan_ip", {
		"ip": lan_ip,
		"emu": LanBeacon.is_android_emulator(),
		"runId": "handtune",
	})


func _discover_stun() -> void:
	if NetConnectivity.public_stun_enabled():
		var urls: PackedStringArray = NetConnectivity.stun_urls()
		if not urls.is_empty():
			var stun: Dictionary = StunClient.discover_mapped_ipv4(urls[0], 600)
			var sip := str(stun.get("ip", "")).strip_edges()
			if sip != "":
				reflexive_ip = sip
				reflexive_port = listen_port
	_write_ticket()


func _open_beacon() -> void:
	_close_beacon()
	_beacon = PacketPeerUDP.new()
	var err := _beacon.bind(BEACON_PORT, "0.0.0.0")
	if err != OK:
		_beacon.close()
		_beacon = PacketPeerUDP.new()
		err = _beacon.bind(0, "0.0.0.0")
		if err != OK:
			_beacon = null
			return
	_beacon.set_broadcast_enabled(true)
	_beacon_announce()


func _close_beacon() -> void:
	if _beacon != null:
		_beacon.close()
	_beacon = null


func _beacon_announce() -> void:
	if _beacon == null:
		return
	var payload := {
		"v": 2,
		"q": "eac_announce",
		"kind": "etb_campaign",
		"code": room_code,
		"port": listen_port,
		"rules": rules_hash,
		"in_match": match_started,
		"has_password": room_password != "",
		"nick": local_nick,
		"ip": lan_ip,
	}
	_spray_beacon(_beacon, JSON.stringify(payload).to_utf8_buffer(), false)


func _beacon_replies() -> void:
	if _beacon == null:
		return
	while _beacon.get_available_packet_count() > 0:
		var pkt := _beacon.get_packet()
		var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		if str((parsed as Dictionary).get("q", "")) != "eac_probe":
			continue
		var rip := _beacon.get_packet_ip()
		var rport := _beacon.get_packet_port()
		if rip == "":
			continue
		_beacon.set_dest_address(rip, rport)
		var payload := {
			"v": 2,
			"q": "eac_announce",
			"kind": "etb_campaign",
			"code": room_code,
			"port": listen_port,
			"in_match": match_started,
			"has_password": room_password != "",
			"nick": local_nick,
			"ip": lan_ip,
		}
		_beacon.put_packet(JSON.stringify(payload).to_utf8_buffer())


func _spray_beacon(udp: PacketPeerUDP, bytes: PackedByteArray, discover: bool) -> void:
	var dests: PackedStringArray = LanBeacon._peer_destinations(LanAffinity.local_ipv4s(), discover)
	for dest in dests:
		udp.set_dest_address(dest, BEACON_PORT)
		udp.put_packet(bytes)


func _discover_lan(wait_s: float) -> Array:
	if LanBeacon.is_android_emulator():
		wait_s = maxf(wait_s, 2.0)
	elif OS.get_name() == "Android":
		wait_s = maxf(wait_s, 2.2)
	var udp := PacketPeerUDP.new()
	var err := udp.bind(BEACON_PORT, "0.0.0.0")
	if err != OK:
		udp.close()
		udp = PacketPeerUDP.new()
		err = udp.bind(0, "0.0.0.0")
		if err != OK:
			return []
	udp.set_broadcast_enabled(true)
	var probe := JSON.stringify({"v": 1, "q": "eac_probe"}).to_utf8_buffer()
	_spray_beacon(udp, probe, true)
	var found: Dictionary = {}
	var end_ms := Time.get_ticks_msec() + int(maxf(wait_s, 0.2) * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		await get_tree().process_frame
		while udp.get_available_packet_count() > 0:
			var pkt := udp.get_packet()
			var ip := udp.get_packet_ip()
			var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(parsed) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = parsed
			if str(row.get("q", "")) != "eac_announce":
				continue
			row["ip"] = ip
			found["%s:%s" % [ip, str(row.get("port", 0))]] = row
	udp.close()
	return found.values()


func _write_ticket() -> void:
	_write_json(TICKET_PATH, {
		"code": room_code,
		"port": listen_port,
		"ip": lan_ip,
		"password": room_password,
		"room_key": room_key,
		"invite": invite_text(),
	})


func _code_of(raw: String, decoded: Dictionary) -> int:
	var room_s := str(decoded.get("room", "")).strip_edges()
	if room_s.is_valid_int():
		return clampi(int(room_s), 1, 9999)
	var up := raw.to_upper()
	if up.begins_with("ETB"):
		var digits := ""
		for i in range(up.length()):
			var ch := up.substr(i, 1)
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits != "":
			return clampi(int(digits), 1, 9999)
	if raw.is_valid_int():
		return clampi(int(raw), 1, 9999)
	return 0


func _parse_host_port(raw: String) -> Dictionary:
	var s := raw.strip_edges()
	var colon := s.rfind(":")
	if colon <= 0:
		return {}
	var ip := s.substr(0, colon)
	var port_s := s.substr(colon + 1)
	if not port_s.is_valid_int():
		return {}
	return {"ip": ip, "port": int(port_s)}


func _ignore_running() -> bool:
	var cf := ConfigFile.new()
	if cf.load("user://player_settings.cfg") != OK:
		return false
	return bool(cf.get_value("nullsec", "ignore_in_match", false))


func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()


func _read_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(path))


@rpc("any_peer", "reliable")
func rpc_hello(nick: String, hash: String, password: String, score: float, ticket_key: String = "") -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if room_password != "" and password != room_password:
		multiplayer.disconnect_peer(pid)
		return
	if match_started:
		if not _reclaim_member(pid, nick, ticket_key):
			_add_spectator(pid, nick, score, hash)
		_flush_progress()
		var layout := _layout_for_peer(pid)
		rpc_id(pid, "rpc_room", JSON.stringify(room))
		rpc_id(pid, "rpc_resume", JSON.stringify(layout), JSON.stringify(_read_tables()), JSON.stringify(progress))
		rpc_id(pid, "rpc_metrics", JSON.stringify(_metrics_blob()))
		peers_changed.emit()
		return
	_add_member(pid, nick, score, hash)
	rpc_id(pid, "rpc_welcome", JSON.stringify(room))
	_broadcast_room()


@rpc("authority", "reliable")
func rpc_welcome(body: String) -> void:
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) == TYPE_DICTIONARY:
		room = parsed
	joined.emit()
	room_updated.emit()


@rpc("any_peer", "reliable")
func rpc_intent(kind: String, body: String) -> void:
	if not is_host:
		return
	var parsed: Variant = JSON.parse_string(body)
	var payload: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_apply_intent(multiplayer.get_remote_sender_id(), kind, payload)


@rpc("authority", "reliable")
func rpc_room(body: String) -> void:
	if is_host:
		return
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var incoming: Dictionary = parsed
	if bool(incoming.get("layout_kept", false)):
		var keep: Variant = room.get("layout", {})
		room = incoming
		room["layout"] = keep
	else:
		room = incoming
	room_updated.emit()


@rpc("any_peer", "reliable")
func rpc_chat(text: String, scope: String, faction: int) -> void:
	if is_host:
		_fanout_chat(text, scope, faction, multiplayer.get_remote_sender_id())
		return
	chat_received.emit(text, scope, faction)


@rpc("any_peer", "unreliable")
func rpc_probe(t: int) -> void:
	var from_id := multiplayer.get_remote_sender_id()
	if from_id <= 0:
		return
	rpc_id(from_id, "rpc_probe_ack", t)


@rpc("any_peer", "unreliable")
func rpc_probe_ack(t: int) -> void:
	var from_id := multiplayer.get_remote_sender_id()
	rtt_ms[from_id] = maxi(Time.get_ticks_msec() - t, 0)
	if not is_host:
		rpc_id(1, "rpc_intent", "report", JSON.stringify({
			"bench": bench,
			"zone_ms": zone_ms,
			"rtt": rtt_ms,
		}))


@rpc("authority", "reliable")
func rpc_metrics(body: String) -> void:
	if is_host:
		return
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var pkt: Dictionary = parsed
	var peers_v: Variant = pkt.get("peers", {})
	if typeof(peers_v) == TYPE_DICTIONARY:
		metrics = peers_v
	var asg_v: Variant = pkt.get("assignment", {})
	if typeof(asg_v) == TYPE_DICTIONARY:
		assignment = asg_v
	var zones_v: Variant = pkt.get("zones", [])
	if zones_v is Array:
		zone_sync = zones_v
	assignment_updated.emit()


@rpc("any_peer", "reliable")
func rpc_zone(body: String) -> void:
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) == TYPE_DICTIONARY:
		zone_received.emit(parsed, true)
		if is_host:
			_merge_progress(parsed)


@rpc("any_peer", "unreliable_ordered")
func rpc_zone_light(body: String) -> void:
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) == TYPE_DICTIONARY:
		zone_received.emit(parsed, false)


@rpc("any_peer", "reliable")
func rpc_zone_submit(body: String) -> void:
	_accept_zone(body, false)


@rpc("any_peer", "unreliable_ordered")
func rpc_zone_submit_light(body: String) -> void:
	_accept_zone(body, true)


@rpc("any_peer", "reliable")
func rpc_fit(unit_id: String, kind: String, on: bool) -> void:
	fit_received.emit(unit_id, kind, on)


@rpc("any_peer", "reliable")
func rpc_fit_to(target: int, unit_id: String, kind: String, on: bool) -> void:
	if not is_host:
		return
	if target == _self_id():
		fit_received.emit(unit_id, kind, on)
	elif target > 0:
		rpc_id(target, "rpc_fit", unit_id, kind, on)


@rpc("any_peer", "reliable")
func rpc_order(unit_id: String, to_sys: String, to_cell: int, focus_id: String = "") -> void:
	order_received.emit(unit_id, to_sys, to_cell, focus_id)


@rpc("any_peer", "reliable")
func rpc_order_to(target: int, unit_id: String, to_sys: String, to_cell: int, focus_id: String = "") -> void:
	if not is_host:
		return
	if target == _self_id():
		order_received.emit(unit_id, to_sys, to_cell, focus_id)
	elif target > 0:
		rpc_id(target, "rpc_order", unit_id, to_sys, to_cell, focus_id)


@rpc("any_peer", "reliable")
func rpc_diplo_offer(from_fac: int, to_fac: int, on: bool = true) -> void:
	if not is_host:
		return
	_deliver_diplo_offer(from_fac, to_fac, multiplayer.get_remote_sender_id(), on)


@rpc("any_peer", "reliable")
func rpc_diplo_offer_to(from_fac: int, to_fac: int, on: bool = true) -> void:
	diplo_offer_received.emit(from_fac, to_fac, on)


@rpc("any_peer", "reliable")
func rpc_concede(fac: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	concede_received.emit(fac)
	if is_host:
		for pid in _relay_targets(sender):
			rpc_id(int(pid), "rpc_concede", fac)


@rpc("any_peer", "reliable")
func rpc_match_closed(body: String) -> void:
	match_started = false
	reopen_room = true
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) == TYPE_DICTIONARY:
		upsert_history(parsed)


@rpc("any_peer", "reliable")
func rpc_audit_fwd(target: int, body: String) -> void:
	if not is_host:
		return
	if target == _self_id():
		var parsed: Variant = JSON.parse_string(body)
		if parsed is Array:
			audit_sample.emit(parsed)
	elif target > 0:
		rpc_id(target, "rpc_audit_sample", body)


@rpc("any_peer", "reliable")
func rpc_group(unit_id: String, group_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == multiplayer.get_unique_id():
		return
	group_received.emit(unit_id, group_id)
	if is_host:
		for pid in _relay_targets(sender):
			rpc_id(int(pid), "rpc_group", unit_id, group_id)


@rpc("any_peer", "reliable")
func rpc_deputy(faction: int, group_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	deputy_received.emit(faction, group_id)
	if is_host:
		for pid in _relay_targets(sender):
			rpc_id(int(pid), "rpc_deputy", faction, group_id)


@rpc("any_peer", "reliable")
func rpc_diplo(a: int, b: int, on: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	diplo_received.emit(a, b, on)
	if is_host:
		for pid in _relay_targets(sender):
			rpc_id(int(pid), "rpc_diplo", a, b, on)


@rpc("any_peer", "reliable")
func rpc_fog(on: bool) -> void:
	room["fog"] = on
	fog_received.emit(on)


@rpc("any_peer", "reliable")
func rpc_fog_req(on: bool) -> void:
	if not is_host:
		return
	var who := _nick_of(multiplayer.get_remote_sender_id())
	_fanout_chat("[全体] %s：希望把战争迷雾调整为%s" % [who, "开" if on else "关"], "all", 0, 0)


func _content_hash(tables: Dictionary) -> String:
	var body := {
		"ships": tables.get("ships", {}),
		"equipment": tables.get("equipment", {}),
		"members": tables.get("members", []),
	}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(_canon(body).to_utf8_buffer())
	return ctx.finish().hex_encode()


func _canon(v: Variant) -> String:
	if typeof(v) == TYPE_DICTIONARY:
		var keys: Array = (v as Dictionary).keys()
		keys.sort()
		var parts: PackedStringArray = PackedStringArray()
		for k in keys:
			parts.append(JSON.stringify(str(k)) + ":" + _canon((v as Dictionary)[k]))
		return "{" + "|".join(parts) + "}"
	if typeof(v) == TYPE_ARRAY:
		var bits: PackedStringArray = PackedStringArray()
		for item in v:
			bits.append(_canon(item))
		return "[" + "|".join(bits) + "]"
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return "%.6f" % float(v)
	return JSON.stringify(v)


func _cached_tables() -> Dictionary:
	var parsed: Variant = _read_json_file(TABLES_PATH)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _human_peer_ids() -> Array:
	var out: Array = []
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if bool(m.get("ai", false)) or str(m.get("seat", "")) == "spectate":
			continue
		var pid := int(m.get("peer", 0))
		if pid > 0:
			out.append(pid)
	return out


func _count_humans() -> int:
	var n := 0
	for m_v in room.get("members", []):
		if typeof(m_v) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = m_v
		if bool(m.get("ai", false)) or str(m.get("seat", "")) == "spectate":
			continue
		n += 1
	return n


func _show_boot(text: String, ratio: float) -> void:
	if _boot_layer == null or not is_instance_valid(_boot_layer):
		_boot_layer = CanvasLayer.new()
		_boot_layer.layer = 120
		add_child(_boot_layer)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 1)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_boot_layer.add_child(bg)
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		box.offset_left = -220
		box.offset_right = 220
		box.offset_top = -120
		box.offset_bottom = -36
		box.add_theme_constant_override("separation", 8)
		_boot_layer.add_child(box)
		_boot_label = Label.new()
		_boot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_boot_label.add_theme_color_override("font_color", Color.WHITE)
		box.add_child(_boot_label)
		_boot_bar = ProgressBar.new()
		_boot_bar.min_value = 0.0
		_boot_bar.max_value = 1.0
		_boot_bar.custom_minimum_size = Vector2(360, 18)
		box.add_child(_boot_bar)
	_boot_label.text = text
	_boot_bar.value = clampf(ratio, 0.0, 1.0)
	_boot_layer.visible = true


func _hide_boot() -> void:
	if _boot_layer != null and is_instance_valid(_boot_layer):
		_boot_layer.queue_free()
	_boot_layer = null
	_boot_label = null
	_boot_bar = null


func _finish_opening() -> void:
	if not _opening:
		return
	_show_boot("正在进入对局", 1.0)
	var base: Dictionary = _opening_layout if not _opening_layout.is_empty() else _layout_for_match()
	for pid in _relay_targets(_self_id()):
		var mine := base.duplicate(true)
		var fac := _faction_of_peer(int(pid))
		mine["viewer_faction"] = fac
		if fac <= 0:
			mine["fog_of_war"] = false
		rpc_id(int(pid), "rpc_opening_go", JSON.stringify(mine), JSON.stringify(_opening_prog))
	_enter_match(base.duplicate(true), _opening_tables, _opening_prog)


func _note_opening_loaded(pid: int) -> void:
	_opening_loaded[pid] = true
	var humans := _human_peer_ids()
	var done := 0
	var need := 0
	for pid2 in humans:
		if int(pid2) == _self_id():
			continue
		need += 1
		if bool(_opening_loaded.get(pid2, false)):
			done += 1
	_show_boot("正在加载", 0.8 + (0.15 * float(done) / maxf(1.0, float(need))))
	if done >= need:
		_finish_opening()


func _begin_disc_wait() -> void:
	_disc_active = true
	_disc_pvp = false
	_disc_link_ok = false
	_disc_probed = false
	if _count_humans() <= 2:
		_disc_wait_until = Time.get_unix_time_from_system() + DUEL_WAIT_S
		_disc_line = "有人掉线。拟真已交接，双人最多再等 10 分钟。"
		_probe_pages_once()
	else:
		_disc_wait_until = 0.0
		_disc_line = "有人掉线。拟真已交接，多人等待重连不限时。"
	disc_notice.emit(_disc_line)


func disc_wait_text() -> String:
	return _disc_line


func note_player_combat(attacker: Dictionary, target: Dictionary) -> void:
	if not _disc_active or attacker.is_empty() or target.is_empty():
		return
	if bool(attacker.get("garrison", false)) or bool(target.get("garrison", false)):
		return
	var af := int(attacker.get("faction", 0))
	var tf := int(target.get("faction", 0))
	if af <= 0 or tf <= 0 or af == tf:
		return
	_disc_pvp = true


func disc_skip_remote_combat(from_host: bool) -> bool:
	if not _disc_pvp:
		return false
	if _disc_link_ok:
		return true
	return not from_host


func _probe_pages_once() -> void:
	if _disc_probed:
		return
	_disc_probed = true
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		_disc_link_ok = result == HTTPRequest.RESULT_SUCCESS and code > 0
		if is_instance_valid(http):
			http.queue_free()
	)
	if http.request(PAGES_URL) != OK:
		_disc_link_ok = false
		http.queue_free()


func _disc_body() -> Dictionary:
	if disc_capture.is_valid():
		var captured = disc_capture.call()
		if typeof(captured) == TYPE_DICTIONARY:
			return captured
	return {}


@rpc("authority", "reliable")
func rpc_opening_hash(content_hash: String) -> void:
	_show_boot("正在核对数据", 0.25)
	var need: bool = _content_hash(_cached_tables()) != content_hash
	_show_boot("正在同步数据" if need else "数据一致", 0.45 if need else 0.6)
	rpc_id(1, "rpc_opening_need", need)


@rpc("any_peer", "reliable")
func rpc_opening_need(need: bool) -> void:
	if not is_host or not _opening:
		return
	var pid := multiplayer.get_remote_sender_id()
	if need:
		_show_boot("正在同步数据", 0.55)
		rpc_id(pid, "rpc_opening_tables", JSON.stringify(_opening_tables))
	else:
		rpc_id(pid, "rpc_opening_load")


@rpc("authority", "reliable")
func rpc_opening_tables(body: String) -> void:
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) == TYPE_DICTIONARY:
		_write_json(TABLES_PATH, parsed)
	_show_boot("正在加载", 0.8)
	rpc_id(1, "rpc_opening_loaded")


@rpc("authority", "reliable")
func rpc_opening_load() -> void:
	_show_boot("正在加载", 0.8)
	rpc_id(1, "rpc_opening_loaded")


@rpc("any_peer", "reliable")
func rpc_opening_loaded() -> void:
	if not is_host or not _opening:
		return
	_note_opening_loaded(multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func rpc_opening_go(layout_json: String, progress_json: String) -> void:
	_show_boot("正在进入对局", 1.0)
	var layout_v: Variant = JSON.parse_string(layout_json)
	var prog_v: Variant = JSON.parse_string(progress_json)
	var layout: Dictionary = layout_v if typeof(layout_v) == TYPE_DICTIONARY else {}
	var prog: Dictionary = prog_v if typeof(prog_v) == TYPE_DICTIONARY else {}
	_enter_match(layout, _cached_tables(), prog)


@rpc("any_peer", "reliable")
func rpc_disc_push(body_json: String) -> void:
	if not is_host:
		return
	var parsed: Variant = JSON.parse_string(body_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var sender := multiplayer.get_remote_sender_id()
	var apply_combat := bool((parsed as Dictionary).get("link_ok", false)) and bool((parsed as Dictionary).get("pvp", false))
	if disc_apply.is_valid():
		disc_apply.call(parsed, apply_combat)
	if not apply_combat:
		rpc_id(sender, "rpc_disc_state", JSON.stringify(_disc_body()))


@rpc("authority", "reliable")
func rpc_disc_state(body_json: String) -> void:
	var parsed: Variant = JSON.parse_string(body_json)
	if typeof(parsed) == TYPE_DICTIONARY and disc_apply.is_valid():
		disc_apply.call(parsed, false)


@rpc("authority", "reliable")
func rpc_match_start(layout_json: String, tables_json: String, progress_json: String) -> void:
	var layout_v: Variant = JSON.parse_string(layout_json)
	var tables_v: Variant = JSON.parse_string(tables_json)
	var prog_v: Variant = JSON.parse_string(progress_json)
	var layout: Dictionary = layout_v if typeof(layout_v) == TYPE_DICTIONARY else {}
	var tables: Dictionary = tables_v if typeof(tables_v) == TYPE_DICTIONARY else {}
	var prog: Dictionary = prog_v if typeof(prog_v) == TYPE_DICTIONARY else {}
	_enter_match(layout, tables, prog)


@rpc("authority", "reliable")
func rpc_resume(layout_json: String, tables_json: String, progress_json: String) -> void:
	if match_started and _disc_active:
		var layout_v: Variant = JSON.parse_string(layout_json)
		var tables_v: Variant = JSON.parse_string(tables_json)
		var prog_v: Variant = JSON.parse_string(progress_json)
		var layout: Dictionary = layout_v if typeof(layout_v) == TYPE_DICTIONARY else {}
		var tables: Dictionary = tables_v if typeof(tables_v) == TYPE_DICTIONARY else {}
		var prog: Dictionary = prog_v if typeof(prog_v) == TYPE_DICTIONARY else {}
		if _disc_pvp and not _disc_link_ok:
			_disc_active = false
			_enter_match(layout, tables, prog)
			return
		var mine := _disc_body()
		mine["pvp"] = _disc_pvp
		mine["link_ok"] = _disc_link_ok
		rpc_id(1, "rpc_disc_push", JSON.stringify(mine))
		if not _disc_pvp and disc_apply.is_valid():
			disc_apply.call(prog, false)
		_disc_active = false
		host_gone = false
		return
	rpc_match_start(layout_json, tables_json, progress_json)


@rpc("any_peer", "reliable")
func rpc_match_over(winner: int, reason: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	match_over_received.emit(winner, reason)
	if is_host:
		for pid in _relay_targets(sender):
			rpc_id(int(pid), "rpc_match_over", winner, reason)


@rpc("any_peer", "reliable")
func rpc_audit_watch(target_peer: int) -> void:
	if not is_host:
		return
	_audit_target = target_peer
	_audit_until = Time.get_ticks_msec() + 60000
	_audit_watcher_id = multiplayer.get_remote_sender_id()


@rpc("any_peer", "reliable")
func rpc_audit_sample(body: String) -> void:
	var parsed: Variant = JSON.parse_string(body)
	if parsed is Array:
		audit_sample.emit(parsed)


@rpc("any_peer", "reliable")
func rpc_mod_install_request(path: String) -> void:
	if is_host:
		_fanout_chat("[全体] %s：希望互发 mod %s" % [_nick_of(multiplayer.get_remote_sender_id()), path], "all", 0, 0)


@rpc("any_peer", "reliable")
func rpc_approve_mod_install(path: String) -> void:
	if is_host:
		_fanout_chat("[全体] %s：同意互发 mod %s" % [_nick_of(multiplayer.get_remote_sender_id()), path], "all", 0, 0)


@rpc("any_peer", "reliable")
func rpc_reject_mod_install(path: String) -> void:
	if is_host:
		_fanout_chat("[全体] %s：拒绝互发 mod %s" % [_nick_of(multiplayer.get_remote_sender_id()), path], "all", 0, 0)
