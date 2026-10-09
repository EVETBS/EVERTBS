extends Control

## Hot-update entry: pick a mini-game.


func _ready() -> void:
	var ver := _read_version()
	$Center/VBox/Meta.text = "content %s  ·  %s" % [ver, OS.get_name()]


func _read_version() -> String:
	var path := "user://online_update/applied_version.json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(data) == TYPE_DICTIONARY and data.has("version"):
				return str(data["version"])
	return "(editor)"


func _on_tetris_pressed() -> void:
	get_tree().change_scene_to_file("res://game/tetris.tscn")


func _on_breakout_pressed() -> void:
	get_tree().change_scene_to_file("res://game/breakout.tscn")


func _unhandled_input(event: InputEvent) -> void:
	# ESC on menu does nothing special
	pass
