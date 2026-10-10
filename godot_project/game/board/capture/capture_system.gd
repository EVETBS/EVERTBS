extends RefCounted
class_name BoardCaptureSystem

var admin: BoardAdminProxy
var _admin_acc := 0.0

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
				occupants[fac] = float(occupants.get(fac, 0.0)) + float(u.get("work_rate", 0.0))
			# 2+ factions: pause (keep work). 0: abandoned clear below.
			if occupants.size() != 1:
				c["capturing"] = 0
				continue
			var fac2: int = occupants.keys()[0]
			if int(c["owner"]) == fac2:
				c["capturing"] = 0
				# own cell: top up work if somehow drained
				continue
			c["capturing"] = fac2
			var rate: float = float(occupants[fac2])
			var before: float = float(c["work"])
			c["work"] = maxf(0.0, before - rate * delta)
			if absf(c["work"] - before) > 0.0001:
				work_dirty = true
			if do_admin and admin:
				admin.request("board.capture", {"sys": sid, "cell": c["index"], "work": c["work"], "by": fac2})
			if c["work"] <= 0.0:
				var prev_owner: int = int(c["owner"])
				var prev_assignee: String = str(c.get("assigned_pilot_id", ""))
				if prev_assignee != "":
					c["last_assignee"] = prev_assignee
				c["assigned_pilot_id"] = ""
				c["owner"] = fac2
				c["capturing"] = 0
				c["work"] = BoardTypes.WORK_MAX
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
			if float(c["work"]) >= BoardTypes.WORK_MAX - 0.01:
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
				c["work"] = BoardTypes.WORK_MAX
				c["capturing"] = 0
