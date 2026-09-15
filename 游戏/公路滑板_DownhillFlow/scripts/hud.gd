extends CanvasLayer

signal start_requested(mode: String)
signal resume_requested
signal restart_requested
signal menu_requested

const WHITE: Color = Color("eff7f6")
const YELLOW: Color = Color("f5ce63")
const MUTED: Color = Color("b6d3db")
var root: Control
var menu: Control
var riding: Control
var pause_panel: Control
var result_panel: Control
var speed_label: Label
var time_label: Label
var distance_label: Label
var status_label: Label
var camera_label: Label
var mode_label: Label
var result_label: Label
var best_label: Label
var bar: ColorRect
var route_draw: Control
var font: SystemFont
var number_font: SystemFont
var last_phase: String = ""

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
	number_font = SystemFont.new()
	number_font.font_names = PackedStringArray(["Bahnschrift", "Consolas", "sans-serif"])
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_menu()
	_build_riding()
	_build_pause()
	_build_result()
	set_phase("menu")

func _label(parent: Node, text: String, pos: Vector2, size: int, color: Color = WHITE, numeric: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", number_font if numeric else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0.01,0.04,0.07,0.45))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _box(parent: Node, pos: Vector2, dimensions: Vector2, color: Color) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.position = pos
	rect.size = dimensions
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

func _button(parent: Node, text: String, pos: Vector2, dimensions: Vector2, primary: bool, action: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.position = pos
	b.size = dimensions
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 21)
	for style_name in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = YELLOW if primary else Color(0.035,0.15,0.20,0.8)
		if style_name == "hover":
			style.bg_color = style.bg_color.lightened(0.15)
		style.corner_radius_top_left = 5
		style.corner_radius_top_right = 5
		style.corner_radius_bottom_left = 5
		style.corner_radius_bottom_right = 5
		if style_name == "focus":
			style.set_border_width_all(2)
			style.border_color = WHITE
		b.add_theme_stylebox_override(style_name, style)
	b.add_theme_color_override("font_color", Color("16313e") if primary else WHITE)
	b.add_theme_color_override("font_hover_color", Color("16313e") if primary else WHITE)
	b.add_theme_color_override("font_pressed_color", Color("16313e") if primary else WHITE)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _layer() -> Control:
	var c: Control = Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	return c

func _build_menu() -> void:
	menu = _layer()
	var fade: ColorRect = _box(menu, Vector2.ZERO, Vector2(1440,900), Color.WHITE)
	var shader: Shader = Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ COLOR=vec4(0.015,0.065,0.095,0.86*(1.0-smoothstep(0.0,0.64,UV.x))); }"
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	fade.material = mat
	_label(menu, "DF  /  COASTAL SESSION", Vector2(72,54), 19, YELLOW, true)
	_box(menu, Vector2(74,184), Vector2(38,4), YELLOW)
	_label(menu, "逐 风", Vector2(68,212), 100)
	_label(menu, "DOWNHILL FLOW", Vector2(74,345), 32, WHITE, true)
	_label(menu, "把重心交给弯道。", Vector2(76,418), 26)
	_label(menu, "海岸公路 · 长板速降\n沿着双黄线，从山坡滑向海风。", Vector2(76,468), 19, MUTED)
	_button(menu, "开始下坡   →", Vector2(76,572), Vector2(340,62), true, func(): start_requested.emit("challenge"))
	_button(menu, "自由滑行", Vector2(76,648), Vector2(340,55), false, func(): start_requested.emit("free"))
	_label(menu, "2.6 KM  /  海岸弯道  /  单人滑行", Vector2(77,735), 16, MUTED)
	_label(menu, "W 蹬地     A / D 转向     空格 漂移", Vector2(77,820), 16, WHITE)
	_label(menu, "ENTER  开始", Vector2(1230,832), 16, WHITE)

func _build_riding() -> void:
	riding = _layer()
	_box(riding, Vector2(38,35), Vector2(300,78), Color(0.015,0.06,0.08,0.57))
	_label(riding, "逐风  /  DOWNHILL FLOW", Vector2(56,45), 18, WHITE)
	mode_label = _label(riding, "海岸计时  ·  出发", Vector2(57,78), 15, MUTED)
	time_label = _label(riding, "00:00.00", Vector2(1190,42), 35, WHITE, true)
	distance_label = _label(riding, "0 / 2600 M", Vector2(1202,87), 16, WHITE, true)
	_box(riding, Vector2(480,51), Vector2(480,4), Color(1,1,1,0.25))
	bar = _box(riding, Vector2(480,51), Vector2(0,4), YELLOW)
	_label(riding, "山海之间", Vector2(680,67), 14, WHITE)
	_box(riding, Vector2(38,716), Vector2(217,137), Color(0.015,0.06,0.08,0.62))
	_label(riding, "SPEED", Vector2(55,729), 14, MUTED, true)
	speed_label = _label(riding, "43", Vector2(51,744), 78, WHITE, true)
	_label(riding, "KM/H", Vector2(180,808), 17, YELLOW, true)
	status_label = _label(riding, "顺着海风滑行", Vector2(58,672), 23, YELLOW)
	camera_label = _label(riding, "低位跟拍  /  C 切换", Vector2(1150,790), 17, WHITE)
	_label(riding, "W 蹬地   A D 转向   S 刹车   空格 漂移   Shift 低伏", Vector2(372,827), 16, WHITE)
	_label(riding, "P 暂停    R 重来    M 声音    F11 全屏", Vector2(980,841), 13, MUTED)

func _build_pause() -> void:
	pause_panel = _layer()
	_box(pause_panel, Vector2.ZERO, Vector2(1440,900), Color(0.015,0.055,0.075,0.69))
	_label(pause_panel, "停一停，听海风。", Vector2(513,267), 42)
	_label(pause_panel, "PAUSED", Vector2(669,337), 18, YELLOW, true)
	_button(pause_panel, "继续滑行", Vector2(560,430), Vector2(320,61), true, func(): resume_requested.emit())
	_button(pause_panel, "重新出发", Vector2(560,507), Vector2(320,55), false, func(): restart_requested.emit())
	_button(pause_panel, "返回主菜单", Vector2(560,577), Vector2(320,55), false, func(): menu_requested.emit())
	_label(pause_panel, "按 P / Esc 继续", Vector2(643,664), 17, MUTED)

func _build_result() -> void:
	result_panel = _layer()
	_box(result_panel, Vector2.ZERO, Vector2(1440,900), Color(0.015,0.055,0.075,0.75))
	_label(result_panel, "COASTAL RUN  /  COMPLETE", Vector2(488,191), 22, YELLOW, true)
	_label(result_panel, "这一程，乘风而过。", Vector2(444,247), 48)
	result_label = _label(result_panel, "", Vector2(500,359), 27)
	best_label = _label(result_panel, "", Vector2(501,493), 20, YELLOW)
	_button(result_panel, "再滑一次   →", Vector2(550,575), Vector2(340,62), true, func(): restart_requested.emit())
	_button(result_panel, "自由滑行", Vector2(550,651), Vector2(340,55), false, func(): start_requested.emit("free"))
	_button(result_panel, "返回主菜单", Vector2(550,720), Vector2(340,50), false, func(): menu_requested.emit())

func set_phase(phase: String) -> void:
	last_phase = phase
	menu.visible = phase == "menu"
	riding.visible = phase == "riding" or phase == "paused"
	pause_panel.visible = phase == "paused"
	result_panel.visible = phase == "finished"

func update_state(state, camera_mode: int, muted: bool, best: float) -> void:
	if state.phase != last_phase:
		set_phase(state.phase)
	speed_label.text = "%02d" % roundi(state.speed * 3.6)
	time_label.text = format_time(state.elapsed)
	distance_label.text = "%d / 2600 M" % int(state.distance)
	bar.size.x = 480.0 * clampf(state.distance / 2600.0,0.0,1.0)
	var section: String = "临海起点"
	if state.distance > 650.0: section = "山崖回弯"
	if state.distance > 1400.0: section = "海风长弯"
	if state.distance > 2150.0: section = "最后冲线"
	mode_label.text = ("海岸计时" if state.mode == "challenge" else "自由滑行") + "  ·  " + section
	camera_label.text = ["低位跟拍", "全景跟拍", "第一人称"][camera_mode] + "  /  C 切换" + ("  · 静音" if muted else "")
	if state.impact > 0.0:
		status_label.text = "擦到路缘 · 松开转向回正"
	elif state.drifting:
		status_label.text = "压弯漂移   +%d FLOW" % int(state.flow)
	elif state.braking > 0.5:
		status_label.text = "稳住重心 · 减速"
	elif state.tuck > 0.5:
		status_label.text = "低伏 · 迎风加速"
	else:
		status_label.text = "顺着海风滑行"
	if state.phase == "finished":
		result_label.text = "用时      %s\n极速      %d KM/H\n漂移      %d FLOW   ·   路缘碰撞 %d" % [format_time(state.elapsed), roundi(state.top_speed * 3.6), int(state.flow), state.hits]
		best_label.text = "个人最佳   " + format_time(best)

func format_time(value: float) -> String:
	var minutes: int = int(value / 60.0)
	var seconds: int = int(value) % 60
	var hundredths: int = int(value * 100.0) % 100
	return "%02d:%02d.%02d" % [minutes, seconds, hundredths]
