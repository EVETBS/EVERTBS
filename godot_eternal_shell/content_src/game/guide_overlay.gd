extends Control

signal closed

const MOUSE_LINES: PackedStringArray = [
	"左键点己方船：改选这一艘。脚下色环：自己绿、盟友蓝、敌人红。固守的冬眠者点不中。",
	"左键按住拖过一小段：拉框，只选己方。战术俯视里双击同一个铭牌框，选中框里全部本方可指挥的船。",
	"已经选中时，左键点格子：这队寻路过去。点到另一艘己方船只改选中，不把整队开过去。",
	"已经选中时，左键点敌人：下令攻击；不在同一格就先走过去。对着有敌方冬眠者的格子，前两次会停在射程外锁住他们，短时间内第三次才冲进格子。",
	"右键点空地或格子：打开格子菜单。可以让全部舰船向这里移动，把这座已占领的空间站设成所有人的初始站，或设、取消集结点。星图上右键点空白只取消选中，不下令移动。",
	"右键点己方船，或右键点左栏那一行：打开命令菜单（拦截泡、进站、护卫立场、指挥波等），对当前选中的所有人一起生效。",
	"在左栏名单里按住左键拖出蓝框：竖直盖住某一行大约七成高度，就选中这一行正在场上的船。",
	"中键：战场视角里绕着看；战术俯视里平移。滚轮拉近、拉远。战术俯视时按住中键再滚轮，转动俯视朝向。鼠标停在屏幕四边，镜头往那边移；停在按钮或左右栏上不会移。",
	"数字键 1 到 0：选中这一组还活着的己方。再按一次同一个数字，镜头随机跟上这组里的一个人。按住 Ctrl 再按数字，或先点底栏的 Ctrl 再点数字：用当前选中覆盖这一组。",
	"点屏幕上的「菜单」暂停对局。",
]
const TOUCH_LINES: PackedStringArray = [
	"单指点一下：等于左键点一下。",
	"单指在棋盘空白处拖：移动视角。指头往上，画面往上。战术俯视同样如此。",
	"单指在名单、战报、详情、聊天、底栏上拖：这些界面跟着手指翻，不挪棋盘。竖直的上下翻，底栏左右翻。",
	"单指按住原地大约 1 秒：从按住的地方长出一个框，松手时按当时的框选中。框出现之前，手指移动超过操作灵敏度，就当成拖视角，不开始框选。框出来之后不松手，框的中心跟着触摸点走。电脑上仍是拖动拉框。",
	"双指张开拉远，捏合拉近。",
	"双指按住转动：只在战术俯视里转动朝向。",
	"底栏上的「↑」「↓」：↑是拉近，↓是拉远，和滚轮同一档。按住超过半秒后连续拉近或拉远，松手停止。",
	"同一位置连点两次：打开右键菜单。点在空地或格子上是格子菜单；点在己方船上，或点在左栏那一行，是命令菜单。两次都算点，手指不能拖开。这次不会再当作左键下令。",
]
const ROSTER_LINES: PackedStringArray = [
	"可以通过自定义团员增加有特殊加成的团员，可以把你希望与你并肩作战的人写进来哦。",
	"在配置团员界面决定首发团员，他们制造第一艘船的时间只需要一秒。",
	"制造战巡需要分配两个资源点给该团员，制造战列需要分配三个，多分配给该团员的资源点能加速舰船制造。",
	"盾守能抵御来自其他格的攻击，不分敌我，甲链能代为承受格子内自己人受到的装甲伤害。",
	"轻拦只能吸附敌人改变敌人落点，重拦能阻止敌人离开格子，并且能吸附敌人改变敌人落点。",
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color(0.08, 0.1, 0.14, 0.15), Color(0.55, 0.62, 0.72, 0.85)))
	margin.add_child(panel)
	var root := MarginContainer.new()
	root.add_theme_constant_override("margin_left", 16)
	root.add_theme_constant_override("margin_right", 16)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var title := Label.new()
	title.text = "新手指南"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	head.add_child(title)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(func() -> void:
		closed.emit()
		queue_free()
	)
	head.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	(preload("res://game/ui/drag_scroll.gd") as GDScript).attach(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	_section(body, "键鼠", MOUSE_LINES)
	_section(body, "触摸", TOUCH_LINES)
	_section(body, "团员", ROSTER_LINES)


func _section(body: VBoxContainer, heading: String, lines: PackedStringArray) -> void:
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 18)
	h.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	body.add_child(h)
	for line in lines:
		var l := Label.new()
		l.text = "· " + line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", Color.WHITE)
		body.add_child(l)


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	return sb
