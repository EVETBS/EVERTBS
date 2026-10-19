extends RefCounted
class_name BoardCaptureSystem

const DevBalance := preload("res://game/board/dev_balance.gd")

var admin: BoardAdminProxy
var _admin_acc := 0.0
## First time captured progress hits 100, freeze deduction for this long.
const STALL_PROGRESS := 100.0
const STALL_SEC := 3.5

func tick(map: BoardMapModel, units: Array, delta: float) -> Array:
	## Returns list of flip events {sys, cell, owner}
	var flips: Array = []
	var work_dirty = false
	_admin_acc += delta
	var do_admin = _admin_acc >= 0.25
	if do_admin:
		_admin_acc = 0.0
	for sid in map.systems.keys():
		var sys: Dictionary = map.systems[sid]
		for c in sys["cells"]:
			var kind: int = c["kind"]
			if kind == BoardTypes.CellKind.EMPTY:
				continue
			var cap := DevBalance.work_cap(kind)
			var occupants: Dictionary = {} # faction -> work_rate sum
			for u in units:
				if not u.get("alive", false):
					continue
				if u.get("sys") != sid or int(u.get("cell", -1)) != int(c["index"]):
					continue
				# INVULN (jump) does not count; PREP/LANDING/IDLE do (design: prep = landed)
				if u.get("phase", BoardTypes.MovePhase.IDLE) == BoardTypes.MovePhase.INVULN:
					continue
				var fac: int = u["faction"]
				var ton := str(u.get("tonnage", ""))
				occupants[fac] = float(occupants.get(fac, 0.0)) + DevBalance.work_rate(ton, float(u.get("work_rate", 0.0)))
			# 0 factions: abandoned clear below. 2+: pause (keep work + capturing for rim).
			if occupants.is_empty():
				continue
			if occupants.size() > 1:
				## Pause — do not wipe capturing or rim will vanish until remesh luck.
				continue
			var fac2: int = occupants.keys()[0]
			if int(c["owner"]) == fac2:
				if int(c.get("capturing", 0)) != 0:
					c["capturing"] = 0
					work_dirty = true
				continue
			if int(c.get("capturing", 0)) != fac2:
				work_dirty = true
			c["capturing"] = fac2
			var rate: float = float(occupants[fac2])
			var before: float = float(c["work"])
			var stall_left := float(c.get("cap_stall", 0.0))
			if stall_left > 0.0:
				c["cap_stall"] = maxf(0.0, stall_left - delta)
				continue
			var progress := cap - before
			var step := rate * delta
			var stall_at := minf(STALL_PROGRESS, cap)
			if not bool(c.get("cap_stall_done", false)) and progress < stall_at and progress + step >= stall_at - 0.0001:
				c["work"] = cap - stall_at
				c["cap_stall"] = STALL_SEC
				c["cap_stall_done"] = true
				work_dirty = true
			else:
				c["work"] = maxf(0.0, before - step)
				if absf(float(c["work"]) - before) > 0.0001:
					work_dirty = true
			if do_admin and admin:
				admin.request("board.capture", {"sys": sid, "cell": c["index"], "work": c["work"], "by": fac2})
			if c["work"] <= 0.0:
				var prev_owner: int = int(c["owner"])
				var prev_assignee: String = str(c.get("assigned_pilot_id", ""))
				if prev_assignee != "":
					c["last_assignee"] = prev_assignee
				c["assigned_pilot_id"] = ""
				c["auto_assigned"] = false
				c["owner"] = fac2
				c["capturing"] = 0
				c["work"] = cap
				c["dev_cap"] = cap
				c["cap_stall"] = 0.0
				c["cap_stall_done"] = false
				work_dirty = true
				flips.append({
					"sys": sid,
					"cell": int(c["index"]),
					"owner": fac2,
					"prev_owner": prev_owner,
					"kind": kind,
					"last_assignee": str(c.get("last_assignee", "")),
				})
	_clear_abandoned(map, units)
	if work_dirty:
		map.capture_dirty = true
	return flips

func _clear_abandoned(map: BoardMapModel, units: Array) -> void:
	for sid in map.systems.keys():
		for c in map.systems[sid]["cells"]:
			if int(c["kind"]) == BoardTypes.CellKind.EMPTY:
				continue
			if float(c["work"]) >= DevBalance.work_cap(int(c["kind"])) - 0.01:
				c["capturing"] = 0
				continue
			var present: Dictionary = {}
			for u in units:
				if not u.get("alive", false):
					continue
				if u.get("sys") != sid or int(u.get("cell", -1)) != int(c["index"]):
					continue
				if u.get("phase", BoardTypes.MovePhase.IDLE) == BoardTypes.MovePhase.INVULN:
					continue
				present[u["faction"]] = true
			if present.is_empty():
				var full := DevBalance.work_cap(int(c["kind"]))
				c["work"] = full
				c["dev_cap"] = full
				c["capturing"] = 0
				c["cap_stall"] = 0.0
				c["cap_stall_done"] = false
