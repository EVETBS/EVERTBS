extends Control

## Draws tetris board; logic on parent.


func _draw() -> void:
	var root = get_parent()
	if root == null:
		return
	var cols: int = root.COLS
	var rows: int = root.ROWS
	var cell: int = root.CELL
	var origin := Vector2((size.x - cols * cell) * 0.5, (size.y - rows * cell) * 0.5)
	draw_rect(Rect2(origin, Vector2(cols * cell, rows * cell)), Color(0.1, 0.11, 0.15))
	for y in range(rows):
		for x in range(cols):
			var v: int = int(root._grid[y][x])
			if v >= 0:
				var c: Color = root.COLORS[v]
				draw_rect(Rect2(origin + Vector2(x, y) * cell + Vector2(1, 1), Vector2(cell - 2, cell - 2)), c)
	if root._alive:
		for p in root._cells(root._origin, root._piece):
			if p.y < 0:
				continue
			var c2: Color = root.COLORS[root._shape_i]
			draw_rect(Rect2(origin + Vector2(p) * cell + Vector2(1, 1), Vector2(cell - 2, cell - 2)), c2)
	for x in range(cols + 1):
		var x0 := origin.x + x * cell
		draw_line(Vector2(x0, origin.y), Vector2(x0, origin.y + rows * cell), Color(0.2, 0.22, 0.28), 1.0)
	for y in range(rows + 1):
		var y0 := origin.y + y * cell
		draw_line(Vector2(origin.x, y0), Vector2(origin.x + cols * cell, y0), Color(0.2, 0.22, 0.28), 1.0)
	if not root._alive:
		draw_rect(Rect2(origin, Vector2(cols * cell, rows * cell)), Color(0, 0, 0, 0.4))
