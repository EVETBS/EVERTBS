extends Node
## Drag on a ScrollContainer or ItemList to page.
## A click is the lift after a press that did not move. Moving cancels the click.

const SLOP := 18.0

var _down := false
var _moved := false
var _at := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _ptr := ""
var _press_ctl: Control = null
static var _claim: Node = null
static var _armed := false


func _ready() -> void:
	var parent := get_parent() as CanvasItem
	if parent != null:
		parent.visibility_changed.connect(_on_parent_hidden)
		parent.tree_exiting.connect(_cancel_gesture)


func _on_parent_hidden() -> void:
	var parent := get_parent() as CanvasItem
	if parent != null and not parent.is_visible_in_tree():
		_cancel_gesture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_gesture()


func _cancel_gesture() -> void:
	#（手势中断时放掉滚动占用）26.10.23 00:24 s
	if _claim == self:
		_claim = null
	if _moved:
		_release_press_visual()
	_down = false
	_moved = false
	_ptr = ""
	_press_ctl = null
	#（手势中断时放掉滚动占用）26.10.23 00:24 e


func _input(event: InputEvent) -> void:
	var target := get_parent() as Control
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		_cancel_gesture()
		return
	if _claim != null and not is_instance_valid(_claim):
		_claim = null
	var pos := _pos_of(event)
	var press := _is_press(event)
	var release := _is_release(event)
	var drag := _is_drag(event)
	var ptr := _ptr_of(event)
	if press:
		if _down and ptr != _ptr:
			return
		if _claim != null and _claim != self:
			return
		if not _inside(target, pos) or _blocked_at(target, pos):
			if _claim == self:
				_cancel_gesture()
			return
		_claim = self
		_down = true
		_moved = false
		_at = pos
		_press_pos = pos
		_ptr = ptr
		_press_ctl = _top_at(target, pos)
		#（按下不点击，抬手才点击）26.10.22 22:10 s
		#（按下留给控件，抬手没拖动才算点击）26.10.22 23:58 s
		#（按下留给控件，抬手没拖动才算点击）26.10.22 23:58 e
		#（按下不点击，抬手才点击）26.10.22 22:10 e
		return
	if not _down or _claim != self:
		return
	if ptr != "" and ptr != _ptr:
		return
	if drag:
		var rel := _rel_of(event, pos)
		if not _moved and pos.distance_to(_press_pos) >= SLOP:
			_moved = true
		if _moved:
			_scroll(target, rel)
			get_viewport().set_input_as_handled()
		_at = pos
		return
	if release:
		var was := _moved
		var origin := _press_pos
		_down = false
		_moved = false
		_claim = null
		_ptr = ""
		#（拖动过了才吞掉抬手，单击仍交给按钮）26.10.22 23:58 s
		if was:
			get_viewport().set_input_as_handled()
			_release_press_visual()
			# #region agent log
			DebugSessionLog.append("UI", "drag_scroll.release", "scroll_cancel_click", {
				"runId": "post-fix", "hypothesisId": "SOLO",
			})
			# #endregion
			_press_ctl = null
			return
		# #region agent log
		DebugSessionLog.append("UI", "drag_scroll.release", "click_through", {
			"runId": "post-fix", "hypothesisId": "SOLO", "x": origin.x, "y": origin.y,
		})
		# #endregion
		_press_ctl = null
		#（拖动过了才吞掉抬手，单击仍交给按钮）26.10.22 23:58 e


func _inside(target: Control, pos: Vector2) -> bool:
	if not target.get_global_rect().has_point(pos):
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return true
	return hovered == target or target.is_ancestor_of(hovered)


func _ptr_of(event: InputEvent) -> String:
	if event is InputEventScreenTouch:
		return "t%d" % int((event as InputEventScreenTouch).index)
	if event is InputEventScreenDrag:
		return "t%d" % int((event as InputEventScreenDrag).index)
	if event is InputEventMouse:
		return "m%d" % int((event as InputEventMouse).device)
	return ""


func _pos_of(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).global_position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	return Vector2.ZERO


func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _is_release(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	return false


func _is_drag(event: InputEvent) -> bool:
	if event is InputEventScreenDrag:
		return true
	if event is InputEventMouseMotion:
		return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	return false


func _rel_of(event: InputEvent, pos: Vector2) -> Vector2:
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).relative
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).relative
	return pos - _at


func _blocked_at(target: Control, pos: Vector2) -> bool:
	var hit := _top_at(target, pos)
	var node: Node = hit
	while node != null and node != target.get_parent():
		if node is Slider or node is LineEdit or node is TextEdit or node is SpinBox:
			return true
		var scr := node.get_script()
		if scr != null and str(scr.resource_path).ends_with("ratio_dual_slider.gd"):
			return true
		if node == target:
			break
		node = node.get_parent()
	return false


func _top_at(node: Node, pos: Vector2) -> Control:
	for i in range(node.get_child_count() - 1, -1, -1):
		var c := node.get_child(i)
		if c == self or not (c is Control):
			continue
		var ctl := c as Control
		if not ctl.visible:
			continue
		if not ctl.get_global_rect().has_point(pos):
			continue
		var nested := _top_at(ctl, pos)
		if nested:
			return nested
		if ctl.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return ctl
	return null


func _scroll(target: Control, rel: Vector2) -> void:
	if target is ScrollContainer:
		var sc := target as ScrollContainer
		if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			sc.scroll_vertical = int(round(float(sc.scroll_vertical) - rel.y))
		if sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			sc.scroll_horizontal = int(round(float(sc.scroll_horizontal) - rel.x))
		return
	if target is ItemList:
		var bar := (target as ItemList).get_v_scroll_bar()
		if bar:
			bar.value -= rel.y


func _release_press_visual() -> void:
	#（取消拖动不改按钮本来的禁用）26.10.23 00:24 s
	var btn := _press_ctl as BaseButton
	if btn == null or not is_instance_valid(btn):
		return
	var was := btn.disabled
	btn.disabled = true
	btn.disabled = was
	#（取消拖动不改按钮本来的禁用）26.10.23 00:24 e


static func attach(target: Control) -> void:
	if target == null or target.get_node_or_null("DragScroll") != null:
		return
	var node := (load("res://game/ui/drag_scroll.gd") as GDScript).new()
	node.name = "DragScroll"
	target.add_child(node)
	var tree := target.get_tree()
	if tree:
		_arm_tree(tree)


static func _arm_tree(tree: SceneTree) -> void:
	if _armed:
		return
	_armed = true
	tree.node_added.connect(_on_node_added)
	if tree.root:
		_walk(tree.root)


static func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		(n as BaseButton).action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE


static func _walk(n: Node) -> void:
	if n is BaseButton:
		(n as BaseButton).action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	for c in n.get_children():
		_walk(c)
