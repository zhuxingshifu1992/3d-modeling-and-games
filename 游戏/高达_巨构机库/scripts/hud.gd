extends CanvasLayer

signal start_pressed
signal resume_pressed
signal home_pressed
signal quit_pressed
signal bay_selected(index: int)
signal setting_changed(key: String, value: float)

var root: Control
var game_ui: Control
var menu: Control
var pause_menu: Control
var guide: Control
var prompt: Label
var subtitle: Label
var altitude: Label
var progress: Label
var target: Label
var location_label: Label
var toast_label: Label
var cabin_panel: PanelContainer
var cabin_label: Label
var cross: Label
var font: Font
var catalog: Array
var dark := Color("111d28")
var amber := Color("edbd70")
var white := Color("e8edf0")
var muted := Color("8ea4b4")
var _toast_timer := 0.0
var _time := 0.0
var settings_controls: Dictionary = {}

func build(data: Array) -> void:
	catalog = data
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = load("res://assets/fonts/NotoSansSC.ttf")
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	root.theme = theme
	add_child(root)
	_build_game_ui()
	_build_menu()
	_build_pause()
	_build_guide()
	show_menu()

func _style(color: Color, border: Color = Color.TRANSPARENT, margin: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0 else 0)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s

func _label(parent: Control, text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _button(parent: Control, text: String, callback: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_stylebox_override("normal", _style(amber if primary else Color("1c2e3d"), Color("345060")))
	b.add_theme_stylebox_override("hover", _style(Color("f3d09a") if primary else Color("2b4456"), amber))
	b.add_theme_stylebox_override("pressed", _style(Color("c99d5b") if primary else Color("162632"), amber))
	b.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), amber))
	b.add_theme_color_override("font_color", dark if primary else white)
	b.add_theme_color_override("font_hover_color", dark if primary else white)
	b.add_theme_color_override("font_pressed_color", dark if primary else white)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _full(parent: Control, shade: Color = Color.TRANSPARENT) -> Control:
	var c: Control
	if shade.a > 0:
		var r := ColorRect.new()
		r.color = shade
		c = r
	else:
		c = Control.new()
	parent.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c

func _panel(parent: Control, at: Vector2, size: Vector2, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = at
	p.custom_minimum_size = size
	p.add_theme_stylebox_override("panel", _style(color))
	parent.add_child(p)
	return p

func _column(parent: Control, separation: int = 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	parent.add_child(v)
	return v

func _anchored(control: Control, preset: Control.LayoutPreset, at: Vector2, dimensions: Vector2) -> void:
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = at.x
	control.offset_top = at.y
	control.offset_right = at.x + dimensions.x
	control.offset_bottom = at.y + dimensions.y

func _build_menu() -> void:
	menu = _full(root)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.027, 0.055, 0.08, 0.97))
	gradient.set_color(1, Color(0.027, 0.055, 0.08, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2.ZERO
	tex.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = tex
	menu.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	menu.add_child(box)
	box.position = Vector2(74, 100)
	box.size = Vector2(430, 650)
	box.add_theme_constant_override("separation", 16)
	_label(box, "MOBILE SUIT  /  MAINTENANCE DECK", 17, amber)
	_label(box, "GUNDAM", 73, white)
	_label(box, "巨 构 机 库", 44, white)
	var line := HSeparator.new()
	box.add_child(line)
	_label(box, "从巨人的脚下，走进驾驶舱。", 23, white)
	_label(box, "六台机体  ·  第一人称  ·  自由观摩", 18, muted)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 30
	box.add_child(spacer)
	_button(box, "进入机库    →", func(): start_pressed.emit(), true)
	_button(box, "机体与操作导览", func(): show_guide())
	_button(box, "退出", func(): quit_pressed.emit())
	_label(box, "W A S D  行走    鼠标  观察    E  交互\nShift  快走    Tab  导览    Esc  暂停", 17, muted)
	var credit := _label(menu, "HANGAR 01\nPILOT ACCESS GRANTED", 18, amber)
	_anchored(credit, Control.PRESET_BOTTOM_RIGHT, Vector2(-335, -88), Vector2(280, 60))
	var note := _label(menu, "同人体验原型  /  风格化机体重构", 15, muted)
	note.position = Vector2(75, 840)

func _build_game_ui() -> void:
	game_ui = _full(root)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := _panel(game_ui, Vector2(32, 28), Vector2(375, 98), Color(0.035, 0.06, 0.085, 0.82))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := _column(top, 7)
	_label(v, "HANGAR 01    /    驾驶员整备区", 17, amber)
	target = _label(v, "前往 A1 · 元祖高达", 21, white)
	subtitle = _label(v, "在机体脚边找到升降平台", 16, muted)
	progress = _label(game_ui, "启动记录  0 / 6", 20, white)
	_anchored(progress, Control.PRESET_TOP_RIGHT, Vector2(-245, 37), Vector2(210, 32))
	cross = _label(game_ui, "+", 22, Color(0.86, 0.94, 1, 0.62))
	_anchored(cross, Control.PRESET_CENTER, Vector2(-12, -17), Vector2(24, 34))
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt = _label(game_ui, "", 23, white)
	_anchored(prompt, Control.PRESET_CENTER_BOTTOM, Vector2(-450, -152), Vector2(900, 40))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt.add_theme_constant_override("shadow_offset_x", 2)
	prompt.add_theme_constant_override("shadow_offset_y", 2)
	var bottom := _full(game_ui)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	location_label = _label(bottom, "PILOT  /  地面整备区", 18, white)
	_anchored(location_label, Control.PRESET_BOTTOM_LEFT, Vector2(34, -66), Vector2(610, 28))
	altitude = _label(bottom, "视线高度  1.65 m", 16, muted)
	_anchored(altitude, Control.PRESET_BOTTOM_LEFT, Vector2(34, -38), Vector2(450, 25))
	var keys := _label(bottom, "E  交互     Tab  导览     Esc  暂停", 16, muted)
	_anchored(keys, Control.PRESET_BOTTOM_RIGHT, Vector2(-368, -45), Vector2(340, 25))
	toast_label = _label(game_ui, "", 21, amber)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_label.offset_top = 152
	toast_label.offset_bottom = 186
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cabin_panel = _panel(game_ui, Vector2.ZERO, Vector2(530, 86), Color(0.028, 0.06, 0.077, 0.92))
	_anchored(cabin_panel, Control.PRESET_CENTER_TOP, Vector2(-265, 25), Vector2(530, 86))
	cabin_label = _label(cabin_panel, "", 19, Color("8ce3d1"))
	cabin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cabin_panel.visible = false

func _center_panel(parent: Control, width: float) -> PanelContainer:
	var center := CenterContainer.new()
	parent.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.065, 0.09, 0.98), Color("385365"), 34))
	center.add_child(panel)
	return panel

func _build_pause() -> void:
	pause_menu = _full(root, Color(0.015, 0.025, 0.04, 0.73))
	var col := _column(_center_panel(pause_menu, 480), 14)
	_label(col, "PILOT SYSTEM", 15, amber)
	_label(col, "整备暂停", 33, white)
	_button(col, "继续观摩", func(): resume_pressed.emit(), true)
	_slider(col, "鼠标灵敏度", "sensitivity", 0.5, 2.0, 1.0)
	_slider(col, "垂直视场角", "fov", 55, 80, 65)
	var sound := CheckButton.new()
	sound.text = "机库环境声与设备音效"
	sound.button_pressed = true
	settings_controls.sound = sound
	sound.toggled.connect(func(on: bool): setting_changed.emit("sound", 1.0 if on else 0.0))
	col.add_child(sound)
	_button(col, "返回入口", func(): home_pressed.emit())
	_button(col, "退出游戏", func(): quit_pressed.emit())

func _slider(parent: Control, title: String, key: String, minimum: float, maximum: float, initial: float) -> void:
	var l := _label(parent, title, 17, muted)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.1 if maximum < 10 else 1.0
	slider.value = initial
	settings_controls[key] = slider
	slider.custom_minimum_size.y = 28
	parent.add_child(slider)
	slider.value_changed.connect(func(value: float):
		l.text = title + "  " + ("%.1f" % value if maximum < 10 else "%d°" % int(value))
		setting_changed.emit(key, value))

func _build_guide() -> void:
	guide = _full(root, Color(0.014, 0.025, 0.04, 0.88))
	var col := _column(_center_panel(guide, 870), 14)
	_label(col, "DECK DIRECTORY    /    六机整备泊位", 17, amber)
	_label(col, "选择下一台要观摩的机体", 28, white)
	_label(col, "设置步行导航后，前往泊位内的黄色升降平台。", 17, muted)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	col.add_child(grid)
	for index in [0, 3, 1, 4, 2, 5]:
		var item: Dictionary = catalog[index]
		var b := _button(grid, "%s   %s\n%s  /  %.2f m" % [item.bay, item.name, item.model, item.height], func(): bay_selected.emit(index))
		b.custom_minimum_size = Vector2(390, 90)
		b.add_theme_font_size_override("font_size", 18)
	_label(col, "登舱：乘升降平台 → 打开舱门 → 落座 → 三步启动\nWASD 行走 · Shift 快走 · Ctrl 蹲下 · F 工作灯 · F2 隐藏界面", 17, muted)
	_button(col, "返回", func(): resume_pressed.emit())

func show_menu() -> void:
	menu.show()
	game_ui.hide()
	pause_menu.hide()
	guide.hide()

func show_game() -> void:
	menu.hide()
	game_ui.show()
	pause_menu.hide()
	guide.hide()

func show_pause() -> void:
	pause_menu.show()
	guide.hide()

func show_guide() -> void:
	guide.show()
	pause_menu.hide()

func update_view(data: Dictionary) -> void:
	prompt.text = data.get("prompt", "")
	location_label.text = data.get("location", "地面整备区")
	altitude.text = "视线高度  %.2f m" % data.get("altitude", 1.65)
	progress.text = "启动记录  %d / 6" % data.get("visited", 0)
	target.text = data.get("target", "自由观摩")
	subtitle.text = data.get("hint", "走近机体，仰望巨构")
	cabin_panel.visible = data.get("cabin", false)
	cabin_label.text = data.get("cabin_text", "")
	cross.visible = not data.get("cabin", false)

func toast(text: String, duration: float = 4.0) -> void:
	toast_label.text = text
	_toast_timer = duration

func sync_settings(settings: Dictionary) -> void:
	settings_controls.fov.set_value_no_signal(float(settings.fov))
	settings_controls.sensitivity.set_value_no_signal(float(settings.sensitivity))
	settings_controls.sound.set_pressed_no_signal(bool(settings.sound))

func _process(delta: float) -> void:
	if _toast_timer > 0:
		_toast_timer -= delta
		if _toast_timer <= 0:
			toast_label.text = ""
