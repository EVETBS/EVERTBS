extends Control


func _draw() -> void:
	var root = get_parent()
	if root == null:
		return
	var o: Vector2 = root._field_origin()
	var fw: float = root.FIELD_W
	var fh: float = root.FIELD_H
	draw_rect(Rect2(o, Vector2(fw, fh)), Color(0.09, 0.1, 0.14))
	# bricks
	for b in root._bricks:
		if not b["alive"]:
			continue
		var r: Rect2 = b["rect"]
		draw_rect(Rect2(o + r.position, r.size), b["color"])
	# paddle
	var pr: Rect2 = root._paddle_rect()
	draw_rect(Rect2(o + pr.position, pr.size), Color(0.85, 0.9, 1.0))
	# ball
	draw_circle(o + root._ball, root.BALL_R, Color(1.0, 0.85, 0.35))
	# border
	draw_rect(Rect2(o, Vector2(fw, fh)), Color(0.35, 0.4, 0.5), false, 2.0)
	if not root._alive:
		draw_rect(Rect2(o, Vector2(fw, fh)), Color(0, 0, 0, 0.4))
