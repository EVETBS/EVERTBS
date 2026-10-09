@tool
extends EditorPlugin

const Dock := preload("res://addons/android_emulator_launcher/dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = Dock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
