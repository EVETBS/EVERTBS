extends RefCounted
class_name BoardShipDeathFx
## Echoes ship-death explode used by the battlefield view and the menu backdrop.
## Explode phase only (no wreck). Scale follows Eve autochess ship_death_fx groups.

const EchoesScr := preload("res://game/board/fx/echoes_ship_death_fx.gd")
const EXPLODE_DURATION_S := 2.4

static var _warmed := false


static func scale_for_tonnage(tonnage: String) -> float:
	match tonnage:
		"frigate":
			return 0.12
		"destroyer":
			return 0.18
		"cruiser", "battlecruiser":
			return 0.28
		"battleship":
			return 0.45
		"dreadnought", "carrier", "force_auxiliary", "capital_industrial":
			return 0.7
		"titan":
			return 1.0
		"freighter":
			return 0.85
		_:
			return 0.2


static func warm() -> void:
	if _warmed:
		return
	_warmed = true
	EchoesScr.warm_resource_cache()


static func spawn(parent: Node, world_pos: Vector3, tonnage: String) -> void:
	if parent == null:
		return
	warm()
	var fx := Node3D.new()
	fx.set_script(EchoesScr)
	fx.name = "ShipDeathFx"
	parent.add_child(fx)
	fx.global_position = world_pos
	fx.scale = Vector3.ONE * scale_for_tonnage(tonnage)
	var runner := _DeathFxRunner.new()
	parent.add_child(runner)
	runner.begin(fx)


class _DeathFxRunner extends Node:
	var _fx: Node3D
	var _t := 0.0

	func begin(fx: Node3D) -> void:
		_fx = fx
		_t = 0.0
		set_process(true)

	func _process(delta: float) -> void:
		if _fx == null or not is_instance_valid(_fx):
			queue_free()
			return
		_t += delta
		var amt := clampf(_t / EXPLODE_DURATION_S, 0.0, 1.0)
		if _fx.has_method("apply_phase"):
			_fx.call("apply_phase", "explode", amt, true)
		if amt >= 1.0:
			if is_instance_valid(_fx):
				_fx.queue_free()
			queue_free()