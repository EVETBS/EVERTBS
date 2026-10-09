extends RefCounted
class_name GameNav


static func go_main_menu(tree: SceneTree) -> void:
	tree.change_scene_to_file("res://game/main.tscn")
