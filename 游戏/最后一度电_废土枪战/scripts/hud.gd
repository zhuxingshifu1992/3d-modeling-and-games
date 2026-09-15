extends CanvasLayer

signal start_requested(difficulty: String)
signal resume_requested
signal retry_requested
signal restart_requested
signal quit_requested
signal settings_changed(settings: Dictionary)

const SAND: Color = Color("ded5bd")
const MUTED: Color = Color("948f7d")
const INK: Color = Color("1c2523")
const CYAN: Color = Color("68ccb7")
const YELLOW: Color = Color("d0a253")
const RUST: Color = Color("ce694d")
const BASE: Vector2 = Vector2(1280, 720)
const PHASE_NAMES: Dictionary = {"POWER":"恢复供电", "CONNECT":"接入电池", "CHARGE":"充能进行中", "RESET":"线路跳闸", "COLLECT":"取走电池", "EXTRACT":"携电撤离", "VICTORY":"电已送达"}

class InstrumentCanvas extends Control:
	var instrument: CanvasLayer
	func _draw() -> void:
		if is_instance_valid(instrument):
			instrument.paint(self)

var stage: Control
var canvas: InstrumentCanvas
var panel: Control
var font: Font
var mode: String = "menu"
var values: Dictionary = {}
var options: Dictionary = {"difficulty": "standard", "sensitivity": 1.0, "low_quality": false, "volume": 0.75}
var best_record: Dictionary = {}
var interaction: String = ""
var interaction_progress: float = 0.0
var message_title: String = ""
var message_body: String = ""
var message_remaining: float = 0.0
var hit_remaining: float = 0.0
var hit_headshot: bool = false
var damage_remaining: float = 0.0
var damage_angle: float = 0.0
var marker_position: Vector2 = Vector2.ZERO
var marker_distance: float = 0.0
var marker_on: bool = false
var result_text: String = ""
var clock: float = 0.0
var built: bool = false

func setup() -> void:
	if built:
		return
	built = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		font = load("res://assets/fonts/NotoSansSC.ttf") as Font
	stage = Control.new()
	stage.name = "HUDStage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = BASE
	add_child(stage)
	canvas = InstrumentCanvas.new()
	canvas.instrument = self
	canvas.size = BASE
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(canvas)
	panel = Control.new()
	panel.name = "MenuControls"
	panel.size = BASE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(panel)
	get_viewport().size_changed.connect(_resize)
	_resize()
	show_menu()

func _resize() -> void:
	if not is_instance_valid(stage):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var fit: float = minf(viewport_size.x / BASE.x, viewport_size.y / BASE.y)
	stage.scale = Vector2.ONE * fit
	stage.position = (viewport_size - BASE * fit) * 0.5

func _process(delta: float) -> void:
	clock += delta
	message_remaining = maxf(0.0, message_remaining - delta)
	hit_remaining = maxf(0.0, hit_remaining - delta)
	damage_remaining = maxf(0.0, damage_remaining - delta)
	if is_instance_valid(canvas):
		canvas.queue_redraw()

func _clear_panel() -> void:
	for child: Node in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	panel.visible = true

func _label(text: String, pos: Vector2, extent: Vector2, point_size: int = 18, color: Color = SAND) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = pos
	label.size = extent
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", point_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return label

func _button(text: String, pos: Vector2, extent: Vector2, action: Callable, primary: bool = false, node_name: String = "") -> Button:
	var button: Button = Button.new()
	button.text = text
	button.name = node_name if not node_name.is_empty() else text
	button.position = pos
	button.size = extent
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 18)
	for text_state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(text_state, INK if primary else SAND)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = YELLOW if primary else Color("2b3531")
		if state == "hover" or state == "focus":
			style.bg_color = SAND if primary else Color("465147")
		if state == "pressed":
			style.bg_color = CYAN if primary else Color("1b2623")
		style.border_color = YELLOW if primary else Color("667064")
		style.border_width_left = 3
		style.content_margin_left = 18
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	panel.add_child(button)
	return button

func _selector(pos: Vector2, items: Array[String], selected: int, changed: Callable) -> OptionButton:
	var control: OptionButton = OptionButton.new()
	control.position = pos
	control.size = Vector2(178, 32)
	control.add_theme_font_override("font", font)
	control.add_theme_font_size_override("font_size", 16)
	control.add_theme_color_override("font_color", SAND)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("303a34")
	style.content_margin_left = 10
	style.content_margin_right = 12
	control.add_theme_stylebox_override("normal", style)
	control.add_theme_stylebox_override("hover", style)
	control.add_theme_stylebox_override("focus", style)
	control.get_popup().add_theme_font_override("font", font)
	control.get_popup().add_theme_font_size_override("font_size", 16)
	control.get_popup().add_theme_color_override("font_color", SAND)
	control.get_popup().add_theme_stylebox_override("panel", style)
	for item: String in items:
		control.add_item(item)
	control.select(selected)
	control.item_selected.connect(changed)
	panel.add_child(control)
	return control

func _slider(pos: Vector2, min_value: float, max_value: float, step_value: float, current: float, changed: Callable) -> HSlider:
	var slider: HSlider = HSlider.new()
	slider.position = pos
	slider.size = Vector2(172, 30)
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step_value
	slider.value = current
	var rail: StyleBoxFlat = StyleBoxFlat.new()
	rail.bg_color = Color(SAND, 0.22)
	rail.content_margin_top = 2
	rail.content_margin_bottom = 2
	slider.add_theme_stylebox_override("slider", rail)
	var fill: StyleBoxFlat = rail.duplicate() as StyleBoxFlat
	fill.bg_color = YELLOW
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob: Image = Image.create(8, 14, false, Image.FORMAT_RGBA8)
	knob.fill(SAND)
	var knob_texture: ImageTexture = ImageTexture.create_from_image(knob)
	slider.add_theme_icon_override("grabber", knob_texture)
	slider.add_theme_icon_override("grabber_highlight", knob_texture)
	slider.value_changed.connect(changed)
	panel.add_child(slider)
	return slider

func _emit_options() -> void:
	settings_changed.emit(options.duplicate())

func set_settings(settings: Dictionary) -> void:
	# Loading a profile must not emit a user change or overwrite saved values with defaults.
	if settings.has("difficulty"):
		options.difficulty = "easy" if String(settings.difficulty) == "easy" else "standard"
	if settings.has("sensitivity"):
		options.sensitivity = clampf(float(settings.sensitivity), 0.2, 2.0)
	if settings.has("low_quality"):
		options.low_quality = bool(settings.low_quality)
	if settings.has("volume"):
		options.volume = clampf(float(settings.volume), 0.0, 1.0)
	if built and mode == "menu":
		show_menu(best_record)
	elif built and mode == "pause":
		show_pause()

func _settings(y: float) -> void:
	_label("难度", Vector2(84, y), Vector2(144, 32), 16, MUTED)
	_selector(Vector2(246, y), ["简单 · 更多余地", "标准 · 有限补给"], 0 if options.difficulty == "easy" else 1,
		func(index: int) -> void: options.difficulty = "easy" if index == 0 else "standard"; _emit_options())
	_label("画质", Vector2(84, y + 41), Vector2(144, 32), 16, MUTED)
	_selector(Vector2(246, y + 41), ["低 · 流畅优先", "标准"], 0 if options.low_quality else 1,
		func(index: int) -> void: options.low_quality = index == 0; _emit_options())
	var sensitivity: Label = _label("鼠标灵敏度  %.2f" % float(options.sensitivity), Vector2(84, y + 82), Vector2(160, 32), 15, MUTED)
	_slider(Vector2(246, y + 84), 0.2, 2.0, 0.05, float(options.sensitivity),
		func(value: float) -> void: options.sensitivity = value; sensitivity.text = "鼠标灵敏度  %.2f" % value; _emit_options())
	var volume_label: Label = _label("声音  %d%%" % roundi(float(options.volume) * 100.0), Vector2(84, y + 123), Vector2(144, 32), 16, MUTED)
	_slider(Vector2(246, y + 125), 0.0, 1.0, 0.05, float(options.volume),
		func(value: float) -> void: options.volume = value; volume_label.text = "声音  %d%%" % roundi(value * 100.0); _emit_options())

func show_menu(best: Dictionary = {}) -> void:
	if not built:
		setup()
	best_record = best.duplicate()
	mode = "menu"
	_clear_panel()
	_label("最后一度电", Vector2(81, 92), Vector2(368, 69), 47)
	_label("断 电 区", Vector2(85, 160), Vector2(340, 32), 23, YELLOW)
	_label("抢回足够撑过一夜的电。", Vector2(85, 212), Vector2(340, 35), 18)
	_label("离线单人战役  /  约 8—15 分钟", Vector2(85, 246), Vector2(340, 25), 14, MUTED)
	var start: Button = _button("开始行动     →", Vector2(84, 300), Vector2(340, 51), _start, true, "StartButton")
	_settings(374)
	_button("退出游戏", Vector2(84, 562), Vector2(340, 40), func() -> void: quit_requested.emit(), false, "QuitButton")
	var record: String = "尚无撤离记录"
	if best.has("elapsed"):
		record = "最佳撤离  " + _format_time(float(best.elapsed))
	_label(record, Vector2(84, 623), Vector2(340, 22), 13, MUTED)
	_label("行动须知", Vector2(908, 475), Vector2(300, 30), 20, SAND)
	_label("WASD 移动     鼠标瞄准 / 射击\n右键 瞄准    R 换弹    1 / 2 切枪\nShift 冲刺    Ctrl 蹲伏    空格 跳跃\n按住 E 交互    Q 急救    Esc 暂停", Vector2(908, 518), Vector2(314, 120), 15, SAND)
	start.grab_focus()

func _start() -> void:
	_emit_options()
	start_requested.emit(String(options.difficulty))

func show_pause() -> void:
	mode = "pause"
	_clear_panel()
	_label("行动暂停", Vector2(83, 102), Vector2(350, 60), 40)
	_label("电还在。喘口气，再出发。", Vector2(84, 166), Vector2(340, 36), 17, MUTED)
	var resume: Button = _button("继续行动     →", Vector2(84, 235), Vector2(340, 48), func() -> void: resume_requested.emit(), true, "ResumeButton")
	_button("重试检查点", Vector2(84, 294), Vector2(166, 43), func() -> void: retry_requested.emit(), false, "RetryButton")
	_button("重新开始", Vector2(258, 294), Vector2(166, 43), func() -> void: restart_requested.emit(), false, "RestartButton")
	_settings(370)
	_button("退出游戏", Vector2(84, 568), Vector2(340, 40), func() -> void: quit_requested.emit(), false, "QuitButton")
	resume.grab_focus()

func hide_panels() -> void:
	mode = "game"
	panel.visible = false

func _format_time(seconds: float) -> String:
	var value: int = maxi(0, int(seconds))
	return "%02d:%02d" % [value / 60, value % 60]

func _stat(stats: Dictionary, key: String, digits: bool = false) -> String:
	if not stats.has(key):
		return "—"
	return "%02d" % int(stats[key]) if digits else str(stats[key])

func show_end(won: bool, stats: Dictionary) -> void:
	mode = "victory" if won else "defeat"
	_clear_panel()
	_label("电已送达" if won else "行动中断", Vector2(83, 104), Vector2(350, 60), 40, CYAN if won else RUST)
	_label("医务站的灯，会亮过这一夜。" if won else "回到检查点，换一条掩体路线。", Vector2(84, 173), Vector2(350, 32), 17, SAND)
	var accuracy: String = "—"
	if stats.has("shots") and stats.has("hits") and float(stats.shots) > 0.0:
		accuracy = "%d%%" % roundi(clampf(float(stats.hits) / float(stats.shots), 0.0, 1.0) * 100.0)
	elif stats.has("accuracy"):
		var ratio: float = float(stats.accuracy)
		accuracy = "%d%%" % roundi(clampf(ratio * 100.0 if ratio <= 1.0 else ratio, 0.0, 100.0))
	var elapsed: String = _format_time(float(stats.elapsed)) if stats.has("elapsed") else "—"
	result_text = "行动用时     %s\n消灭人数     %s\n命中率        %s\n爆头次数     %s" % [elapsed, _stat(stats, "kills", true), accuracy, _stat(stats, "headshots", true)]
	_label(result_text, Vector2(88, 260), Vector2(333, 182), 23)
	var first: Button
	if won:
		first = _button("再行动一次    →", Vector2(84, 505), Vector2(340, 48), func() -> void: restart_requested.emit(), true, "RestartButton")
	else:
		first = _button("重试检查点    →", Vector2(84, 489), Vector2(340, 48), func() -> void: retry_requested.emit(), true, "RetryButton")
		_button("重新开始", Vector2(84, 548), Vector2(340, 39), func() -> void: restart_requested.emit(), false, "RestartButton")
	_button("退出游戏", Vector2(84, 603), Vector2(340, 39), func() -> void: quit_requested.emit(), false, "QuitButton")
	first.grab_focus()

func get_result_text() -> String:
	return result_text

func update_hud(data: Dictionary) -> void:
	values = data.duplicate()
	if values.has("phase"):
		values.phase = String(values.phase).to_upper()

func set_interaction(text: String, progress: float) -> void:
	interaction = text
	interaction_progress = clampf(progress, 0.0, 1.0)

func show_message(title: String, body: String, duration: float = 5.0) -> void:
	message_title = title
	message_body = body
	message_remaining = maxf(0.0, duration)

func hit_marker(headshot: bool = false) -> void:
	hit_remaining = 0.20
	hit_headshot = headshot

func damage_flash(direction: float = 0.0) -> void:
	damage_remaining = 0.65
	damage_angle = direction

func set_objective_marker(screen_pos: Vector2, distance: float, visible: bool) -> void:
	var fit: float = stage.scale.x if is_instance_valid(stage) else 1.0
	marker_position = (screen_pos - stage.position) / maxf(fit, 0.001)
	marker_distance = maxf(0.0, distance)
	marker_on = visible

func _write(c: Control, text: String, pos: Vector2, size_px: int, color: Color = SAND, width: float = -1.0) -> void:
	c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, color)

func _center(c: Control, text: String, pos: Vector2, size_px: int, color: Color = SAND) -> void:
	var extent: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	_write(c, text, pos - Vector2(extent.x * 0.5, 0), size_px, color)

func _plate(c: Control, rect: Rect2, alpha: float = 0.77) -> void:
	c.draw_rect(rect, Color(INK, alpha))
	c.draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), Color(SAND, 0.22), 1.0)
	c.draw_line(rect.position + Vector2(0, rect.size.y), rect.end, Color(SAND, 0.14), 1.0)

func _meter(c: Control, rect: Rect2, amount: float, color: Color, divisions: int = 20) -> void:
	var ratio: float = clampf(amount, 0.0, 1.0)
	var step: float = rect.size.x / float(divisions)
	for i: int in range(divisions):
		var segment: Rect2 = Rect2(rect.position + Vector2(float(i) * step, 0), Vector2(step - 2.0, rect.size.y))
		c.draw_rect(segment, color if (float(i) + 0.5) / float(divisions) <= ratio else Color(SAND, 0.13))

func paint(c: Control) -> void:
	if font == null:
		return
	if mode != "game":
		_paint_menu(c)
		return
	var health: float = clampf(float(values.get("health", 100.0)), 0.0, 100.0)
	var armor_capacity: float = 55.0 if options.difficulty == "easy" else 35.0
	var armor: float = maxf(float(values.get("armor", 35.0)), 0.0)
	var stamina: float = clampf(float(values.get("stamina", 100.0)), 0.0, 100.0)
	var aiming: bool = bool(values.get("aiming", false))
	# The top-left task plate doubles as a field-work instruction card.
	_plate(c, Rect2(30, 28, 410, 93), 0.77)
	c.draw_rect(Rect2(30, 28, 4, 93), CYAN)
	var phase_name: String = String(values.get("phase", "行动"))
	_write(c, "当前任务 / " + String(PHASE_NAMES.get(phase_name, phase_name)), Vector2(48, 50), 12, CYAN)
	_write(c, String(values.get("objective", "恢复充电场供电")), Vector2(48, 80), 21, SAND, 372)
	_write(c, String(values.get("detail", "前往办公室平台")), Vector2(48, 104), 14, MUTED, 374)
	var charge: float = clampf(float(values.get("charge", 0.0)), 0.0, 1.0)
	var phase: String = String(values.get("phase", ""))
	if phase in ["CHARGE", "RESET", "COLLECT"] or charge > 0.0:
		_plate(c, Rect2(30, 129, 410, 48), 0.75)
		_write(c, "储能电池", Vector2(47, 151), 13, MUTED)
		_write(c, "%03d%%" % roundi(charge * 100.0), Vector2(365, 151), 17, YELLOW if phase == "RESET" else CYAN)
		_meter(c, Rect2(48, 159, 373, 5), charge, YELLOW if phase == "RESET" else CYAN, 38)
	# Bottom left: large analog-like health readout, armor rail, stamina tick band.
	_plate(c, Rect2(30, 590, 296, 100))
	_write(c, "生命", Vector2(46, 613), 12, MUTED)
	_write(c, "%03d" % roundi(health), Vector2(45, 651), 37, RUST if health < 30 else SAND)
	_write(c, "护甲  %02d" % roundi(armor), Vector2(156, 616), 15, SAND)
	_meter(c, Rect2(156, 629, 149, 10), armor / armor_capacity, CYAN, 14)
	_meter(c, Rect2(48, 669, 257, 5), health / 100.0, RUST if health < 30 else YELLOW, 26)
	_write(c, "Q  急救 ×%d" % int(values.get("medkits", 2)), Vector2(157, 656), 13, MUTED)
	if stamina < 99.0:
		_meter(c, Rect2(535, 664, 210, 4), stamina / 100.0, SAND, 22)
		_center(c, "体力", Vector2(640, 690), 12, MUTED)
	# Ammunition is deliberately open and large, away from the center combat area.
	_plate(c, Rect2(1000, 590, 250, 100))
	_write(c, String(values.get("weapon", "R7 卡宾枪")), Vector2(1017, 614), 16, MUTED, 215)
	var ammo: int = int(values.get("ammo", 24))
	_write(c, "%02d" % ammo, Vector2(1015, 663), 45, RUST if ammo == 0 else SAND)
	_write(c, "/  %03d" % int(values.get("reserve", 120)), Vector2(1117, 660), 23, MUTED)
	if ammo == 0:
		_write(c, "R  换弹", Vector2(1149, 681), 12, YELLOW)
	_write(c, _format_time(float(values.get("elapsed", 0.0))), Vector2(1186, 44), 15, MUTED)
	if bool(values.get("carrying", false)):
		_plate(c, Rect2(1018, 61, 232, 34), 0.70)
		_write(c, "▣  电池已携带 · 前往出口", Vector2(1031, 84), 14, CYAN)
	var center: Vector2 = BASE * 0.5
	var gap: float = (3.0 if aiming else 7.0) + clampf(float(values.get("spread", 0.0)), 0.0, 20.0) * (0.15 if aiming else 0.55)
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		c.draw_line(center + direction * gap, center + direction * (gap + (4.0 if aiming else 7.0)), Color(SAND, 0.9), 1.25, true)
	c.draw_circle(center, 1.1, SAND)
	if hit_remaining > 0.0:
		var hit_color: Color = YELLOW if hit_headshot else SAND
		for direction: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			c.draw_line(center + direction * 9.0, center + direction * 15.0, hit_color, 2.0, true)
	if not interaction.is_empty():
		var dial: Vector2 = center + Vector2(0, 66)
		c.draw_circle(dial, 17, Color(INK, 0.8))
		c.draw_arc(dial, 22, -PI * 0.5, PI * 1.5, 48, Color(SAND, 0.25), 2, true)
		if interaction_progress > 0.0:
			c.draw_arc(dial, 22, -PI * 0.5, -PI * 0.5 + TAU * interaction_progress, 48, CYAN, 3, true)
		_center(c, "E", dial + Vector2(0,6), 18, CYAN)
		_center(c, interaction if interaction.begins_with("按住") else "按住 E · " + interaction, dial + Vector2(0,49), 16, SAND)
	if marker_on:
		_paint_marker(c)
	if message_remaining > 0.0:
		_paint_subtitle(c)
	if damage_remaining > 0.0:
		var alpha: float = clampf(damage_remaining / 0.65, 0.0, 1.0)
		c.draw_arc(center, 87.0, damage_angle - PI * 0.5 - 0.29, damage_angle - PI * 0.5 + 0.29, 20, Color(RUST, alpha), 5, true)
		c.draw_rect(Rect2(0,0,1280,720), Color(RUST, 0.075 * alpha))

func _paint_marker(c: Control) -> void:
	var point: Vector2 = Vector2(clampf(marker_position.x, 44, 1236), clampf(marker_position.y, 130, 560))
	# Screen bounds remain generous enough to retain a readable off-edge direction.
	if marker_position.x < 40:
		point.x = 44
	elif marker_position.x > 1240:
		point.x = 1236
	var shape: PackedVector2Array = PackedVector2Array([point + Vector2(0,-7),point + Vector2(7,0),point + Vector2(0,7),point + Vector2(-7,0),point + Vector2(0,-7)])
	c.draw_polyline(shape, CYAN, 1.5, true)
	_center(c, "%dm" % roundi(marker_distance), point + Vector2(0,25), 12, CYAN)

func _paint_subtitle(c: Control) -> void:
	var width: float = 698.0
	_plate(c, Rect2(291, 491, width, 82), 0.85)
	_write(c, message_title, Vector2(308, 513), 13, CYAN, width - 36)
	c.draw_multiline_string(font, Vector2(308, 539), message_body, HORIZONTAL_ALIGNMENT_LEFT, width - 36, 17, 2, SAND)

func _paint_menu(c: Control) -> void:
	# A translucent instrument case occupies only the left third of the scene.
	_plate(c, Rect2(52, 40, 405, 637), 0.92)
	c.draw_rect(Rect2(52, 40, 405, 5), YELLOW if mode != "victory" else CYAN)
	for point: Vector2 in [Vector2(65,56),Vector2(444,56),Vector2(65,664),Vector2(444,664)]:
		c.draw_circle(point, 3.0, Color(MUTED,0.5))
		c.draw_line(point - Vector2(1.5,1.5), point + Vector2(1.5,1.5), INK, 1.0)
	_write(c, "FIELD POWER / 7号检修站", Vector2(84, 77), 12, MUTED)
	c.draw_line(Vector2(84, 287 if mode == "menu" else 220), Vector2(424, 287 if mode == "menu" else 220), Color(SAND,0.18), 1.0)
	if mode == "menu":
		_plate(c, Rect2(886, 456, 360, 208), 0.73)
		c.draw_line(Vector2(908,505), Vector2(1225,505), Color(SAND,0.2), 1.0)
		# Quiet mechanical meter: calibration marks belong to the power theme.
		var origin: Vector2 = Vector2(1117, 121)
		c.draw_arc(origin, 55, PI * 1.08, PI * 1.92, 40, Color(SAND,0.45), 1.0, true)
		for i: int in range(11):
			var angle: float = PI * 1.08 + PI * 0.84 * float(i) / 10.0
			var ray: Vector2 = Vector2(cos(angle),sin(angle))
			c.draw_line(origin + ray * 49, origin + ray * 56, SAND, 1.0)
		var needle: float = PI * 1.22 + sin(clock * 0.8) * 0.016
		c.draw_line(origin, origin + Vector2(cos(needle), sin(needle)) * 46, YELLOW, 2, true)
		c.draw_circle(origin, 4, YELLOW)
		_center(c, "剩 余 电 力", origin + Vector2(0,28), 13, SAND)
		_center(c, "仅够一次行动", origin + Vector2(0,48), 11, MUTED)
