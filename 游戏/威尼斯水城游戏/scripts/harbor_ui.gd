class_name HarborUI
extends CanvasLayer

signal action(command: String)

const LAGOON: Color = Color("#145e68")
const NAVY: Color = Color("#153340")
const PAPER: Color = Color("#fff1cf")
const GOLD: Color = Color("#f3c660")
const CORAL: Color = Color("#e89176")
const MUTED: Color = Color("#afc8c5")


class TicketCutline extends Control:

	func _draw() -> void:
		var line_color: Color = Color(1.0, 0.945, 0.812, 0.28)
		var x: float = 4.0
		while x < size.x - 4.0:
			draw_line(Vector2(x, size.y * 0.5), Vector2(minf(x + 4.0, size.x - 4.0), size.y * 0.5), line_color, 1.0)
			x += 9.0
		draw_circle(Vector2(0.0, size.y * 0.5), 4.0, line_color)
		draw_circle(Vector2(size.x, size.y * 0.5), 4.0, line_color)


class HarborMap extends Control:
	var boat_pos: Vector3 = Vector3.ZERO
	var target_pos: Vector3 = Vector3.ZERO
	var has_target: bool = false


	func world_to_map(point: Vector3) -> Vector2:
		return Vector2(
			lerpf(8.0, size.x - 8.0, clampf((point.x + 45.0) / 90.0, 0.0, 1.0)),
			lerpf(8.0, size.y - 8.0, clampf((point.z + 40.0) / 80.0, 0.0, 1.0))
		)


	func _draw() -> void:
		var land: Color = Color("#abc4b4")
		land.a = 0.55
		for island: Rect2 in land_rectangles():
			var a: Vector2 = world_to_map(Vector3(island.position.x, 0.0, island.position.y))
			var b: Vector2 = world_to_map(Vector3(island.end.x, 0.0, island.end.y))
			draw_rect(Rect2(a, b - a), land)
		var boat: Vector2 = world_to_map(boat_pos)
		if has_target:
			var target: Vector2 = world_to_map(target_pos)
			draw_line(boat, target, Color(0.953, 0.776, 0.376, 0.4), 1.0, true)
			draw_arc(target, 6.0, 0.0, TAU, 24, Color("#f3c660"), 1.7, true)
			draw_circle(target, 2.1, Color("#f3c660"))
		draw_circle(boat, 6.2, Color("#153340"))
		draw_circle(boat, 3.8, Color("#fff1cf"))
		var arrow: PackedVector2Array = PackedVector2Array([
			boat + Vector2(0.0, -9.0), boat + Vector2(-2.8, -4.0), boat + Vector2(2.8, -4.0)
		])
		draw_colored_polygon(arrow, Color("#fff1cf"))


	func land_rectangles() -> Array[Rect2]:
		return [
			Rect2(-31.0, -26.0, 25.0, 22.0),
			Rect2(6.0, -26.0, 25.0, 22.0),
			Rect2(-31.0, 4.0, 25.0, 20.0),
			Rect2(6.0, 4.0, 25.0, 20.0),
			Rect2(-27.25, 23.6, 8.5, 4.8)
		]


var _hud: Control
var _start_overlay: Control
var _pause_overlay: Control
var _target: Label
var _day_progress: Label
var _stage: Label
var _distance: Label
var _wallet: Label
var _completed: Label
var _speed: Label
var _navigation: Label
var _technical: Label
var _pause_details: Label
var _map: HarborMap
var _toast_panel: PanelContainer
var _toast_label: Label
var _view_button: Button
var _quality_button: Button
var _mute_button: Button
var _upgrade_button: Button
var _pause_upgrade_button: Button
var _target_button: Button
var _data: Dictionary = {}
var _built: bool = false
var _start_requested: bool = false
var _pause_requested: bool = false
var _toast_remaining: float = 0.0
var _pending_toast: String = ""


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	var ui_theme: Theme = Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 17
	var root: Control = Control.new()
	root.name = "HarborInterface"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ui_theme
	add_child(root)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud)
	_build_ticket()
	_build_wallet()
	_build_map()
	_build_controls()
	_build_start(root)
	_build_pause(root)
	_build_toast(root)
	_built = true
	_apply_hud()
	_apply_visibility()
	if not _pending_toast.is_empty():
		show_toast(_pending_toast)


func _process(delta: float) -> void:
	if _toast_remaining > 0.0 and _built:
		_toast_remaining = maxf(0.0, _toast_remaining - delta)
		_toast_panel.visible = _toast_remaining > 0.0
		_toast_panel.modulate.a = clampf(_toast_remaining / 0.4, 0.0, 1.0)


func set_hud(data: Dictionary) -> void:
	_data.merge(data, true)
	if _built:
		_apply_hud()


func show_toast(text: String) -> void:
	_pending_toast = text
	if not _built:
		return
	_toast_label.text = text
	_toast_remaining = 5.0
	_toast_panel.modulate.a = 1.0
	_toast_panel.show()


func set_paused(value: bool) -> void:
	_pause_requested = value
	if _built:
		_apply_visibility()


func show_start() -> void:
	_start_requested = true
	if _built:
		_apply_visibility()


func hide_start() -> void:
	_start_requested = false
	if _built:
		_apply_visibility()


func show_milestone(deliveries: int) -> void:
	show_toast("已完成 %d 次接送！  继续慢游，下一段风景在前方。" % deliveries)


func _apply_visibility() -> void:
	_start_overlay.visible = _start_requested
	_pause_overlay.visible = _pause_requested and not _start_requested
	_hud.visible = not _start_requested


func _apply_hud() -> void:
	var wallet: int = int(_data.get("wallet", 0))
	var completed: int = int(_data.get("completed", 0))
	var level: int = maxi(0, int(_data.get("level", 0))) + 1
	var day_goal: int = maxi(1, int(_data.get("day_goal", 5)))
	var day: int = maxi(1, int(_data.get("day", floori(float(completed) / float(day_goal)) + 1)))
	var day_completed: int = clampi(int(_data.get("day_completed", completed % day_goal)), 0, day_goal)
	var cost: int = int(_data.get("upgrade_cost", 60))
	var stage: String = str(_data.get("stage", "pickup"))
	var target_name: String = str(_data.get("target_name", "水城码头"))
	var distance: float = float(_data.get("distance", 0.0))
	var quality: String = str(_data.get("quality", "流畅"))
	var muted: bool = bool(_data.get("muted", false))
	var auto_nav: bool = bool(_data.get("auto_nav", false))
	_target.text = target_name
	_day_progress.text = "第 %d 天 · 今日 %d / %d 单" % [day, day_completed, day_goal]
	_stage.text = "送客航程  /  前往目的地" if stage == "delivery" else "接客航程  /  前往亮起的码头"
	_distance.text = "距码头  %d 米" % roundi(distance)
	_wallet.text = "%d  金币" % wallet
	_completed.text = "完成 %d 次接送    ·    船只 Lv.%d" % [completed, level]
	_speed.text = "航速  %.1f" % float(_data.get("speed", 0.0))
	_navigation.text = "自动航行中 · 按 W/S 或 A/D 接管" if auto_nav else "靠近亮起的码头，自动接送"
	_navigation.add_theme_color_override("font_color", GOLD if auto_nav else MUTED)
	_technical.text = "%s · %d FPS" % [quality, roundi(float(_data.get("fps", 0.0)))]
	_pause_details.text = "船只 Lv.%d     ·     完成 %d 次接送     ·     %d 金币" % [level, completed, wallet]
	_quality_button.text = "画质：%s" % quality
	match str(_data.get("camera_mode", "follow")):
		"first_person":
			_view_button.text = "视角：船头 V"
		"overview":
			_view_button.text = "视角：全景 V"
		_:
			_view_button.text = "视角：跟随 V"
	_mute_button.text = "声音：关" if muted else "声音：开"
	_upgrade_button.text = "升级船只  %d 金" % cost if cost > 0 else "船只已满级"
	_pause_upgrade_button.text = "升级船只  ·  %d 金币" % cost if cost > 0 else "船只已满级"
	_upgrade_button.disabled = cost <= 0
	_pause_upgrade_button.disabled = cost <= 0
	_upgrade_button.tooltip_text = "船速与金币吸附范围一起提升。当前拥有 %d 金币。" % wallet
	_target_button.text = "前往当前码头"
	if _data.has("boat_pos") and _data["boat_pos"] is Vector3:
		_map.boat_pos = _data["boat_pos"]
	if _data.has("target_pos") and _data["target_pos"] is Vector3:
		_map.target_pos = _data["target_pos"]
		_map.has_target = true
	_map.queue_redraw()


func _build_ticket() -> void:
	var ticket: PanelContainer = _panel(Color(0.055, 0.17, 0.20, 0.91), 5, 18)
	_fixed_rect(ticket, Vector2(24.0, 24.0), Vector2(386.0, 162.0))
	_hud.add_child(ticket)
	var column: VBoxContainer = _column(5)
	ticket.add_child(column)
	var header: HBoxContainer = _row(12)
	column.add_child(header)
	var brand: Label = _label("水城慢游", 15, GOLD)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	_day_progress = _label("第 1 天 · 今日 0 / 5 单", 12, GOLD)
	header.add_child(_day_progress)
	_target = _label("水城码头", 28, PAPER)
	_target.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_target)
	_stage = _label("接客航程  /  前往亮起的码头", 14, MUTED)
	column.add_child(_stage)
	var cutline: TicketCutline = TicketCutline.new()
	cutline.custom_minimum_size.y = 12.0
	cutline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(cutline)
	var footer: HBoxContainer = _row(12)
	column.add_child(footer)
	_distance = _label("距码头  0 米", 15, GOLD)
	_distance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_distance)
	_speed = _label("航速  0.0", 13, MUTED)
	footer.add_child(_speed)
	_navigation = _label("靠近亮起的码头，自动接送", 13, MUTED)
	_fixed_rect(_navigation, Vector2(28.0, 195.0), Vector2(390.0, 24.0))
	_navigation.add_theme_constant_override("outline_size", 3)
	_navigation.add_theme_color_override("font_outline_color", Color(0.025, 0.11, 0.13, 0.8))
	_hud.add_child(_navigation)


func _build_wallet() -> void:
	var panel: PanelContainer = _panel(Color(0.055, 0.17, 0.20, 0.87), 5, 15)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -278.0
	panel.offset_top = 24.0
	panel.offset_right = -24.0
	panel.offset_bottom = 114.0
	_hud.add_child(panel)
	var column: VBoxContainer = _column(5)
	panel.add_child(column)
	_wallet = _label("0  金币", 25, GOLD)
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_wallet)
	_completed = _label("完成 0 次接送    ·    船只 Lv.1", 13, MUTED)
	_completed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_completed)
	_technical = _label("流畅 · 60 FPS", 11, PAPER)
	_technical.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_technical.offset_left = -260.0
	_technical.offset_top = 121.0
	_technical.offset_right = -28.0
	_technical.offset_bottom = 144.0
	_technical.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_technical.add_theme_constant_override("outline_size", 3)
	_technical.add_theme_color_override("font_outline_color", Color(0.025, 0.11, 0.13, 0.7))
	_hud.add_child(_technical)


func _build_map() -> void:
	var panel: PanelContainer = _panel(Color(0.055, 0.17, 0.20, 0.86), 5, 10)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 24.0
	panel.offset_top = -192.0
	panel.offset_right = 213.0
	panel.offset_bottom = -24.0
	_hud.add_child(panel)
	var column: VBoxContainer = _column(3)
	panel.add_child(column)
	column.add_child(_label("运河小图", 12, MUTED))
	_map = HarborMap.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.custom_minimum_size = Vector2(169.0, 108.0)
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_map)
	column.add_child(_label("● 你的船     ○ 当前码头", 11, PAPER))


func _build_controls() -> void:
	var controls: VBoxContainer = _column(8)
	controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	controls.offset_left = -179.0
	controls.offset_top = -71.0
	controls.offset_right = -24.0
	controls.offset_bottom = 137.0
	_hud.add_child(controls)
	_view_button = _button("视角：跟随 V", "view")
	controls.add_child(_view_button)
	_target_button = _button("前往当前码头", "target")
	controls.add_child(_target_button)
	_upgrade_button = _button("升级船只  60 金", "upgrade")
	controls.add_child(_upgrade_button)
	controls.add_child(_button("暂停   Esc", "pause"))
	var hint: PanelContainer = _panel(Color(0.055, 0.17, 0.20, 0.81), 5, 12)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -306.0
	hint.offset_top = -78.0
	hint.offset_right = 306.0
	hint.offset_bottom = -24.0
	_hud.add_child(hint)
	var hint_column: VBoxContainer = _column(3)
	hint.add_child(hint_column)
	var line_one: Label = _label("W / S 前后    ·    A / D 转向    ·    左键点水面 自动航行", 13, PAPER)
	line_one.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_column.add_child(line_one)
	var line_two: Label = _label("右键拖动 环顾    ·    滚轮 缩放    ·    V 切换视角    ·    空格 鸣笛", 12, MUTED)
	line_two.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_column.add_child(line_two)


func _build_toast(root: Control) -> void:
	_toast_panel = _panel(Color(0.98, 0.921, 0.788, 0.98), 6, 14)
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_panel.offset_left = -310.0
	_toast_panel.offset_top = -149.0
	_toast_panel.offset_right = 310.0
	_toast_panel.offset_bottom = -92.0
	root.add_child(_toast_panel)
	_toast_label = _label("", 16, NAVY)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast_label)
	_toast_panel.hide()


func _build_start(root: Control) -> void:
	_start_overlay = _overlay(root, Color(0.02, 0.08, 0.1, 0.41))
	var panel: PanelContainer = _modal_panel(_start_overlay, 516.0)
	var column: VBoxContainer = _column(13)
	panel.add_child(column)
	column.add_child(_label("V E N E Z I A    /    一段悠闲航程", 12, GOLD))
	column.add_child(_label("水城慢游", 44, PAPER))
	var description: Label = _label("驾一叶贡多拉，穿过暖色小巷与碧绿运河。\n接送旅人、收集金币，慢慢升级你的小船。", 17, PAPER)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	var cutline: TicketCutline = TicketCutline.new()
	cutline.custom_minimum_size.y = 14.0
	cutline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(cutline)
	column.add_child(_label("W / S 前后 · A / D 转向 · 方向键同样可驾驶", 14, MUTED))
	column.add_child(_label("左键点水面航行 · 靠近码头自动接送 · 空格鸣笛", 14, MUTED))
	column.add_child(_label("V 切换跟随 / 船头 / 全景 · 右键拖动环顾 · 滚轮缩放", 14, MUTED))
	var start_button: Button = _button("开始航行", "start", true)
	start_button.custom_minimum_size.y = 52.0
	column.add_child(start_button)
	var note: Label = _label("进度自动保存在这台电脑，随时回来继续。", 12, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)


func _build_pause(root: Control) -> void:
	_pause_overlay = _overlay(root, Color(0.02, 0.08, 0.1, 0.59))
	var panel: PanelContainer = _modal_panel(_pause_overlay, 452.0)
	var column: VBoxContainer = _column(11)
	panel.add_child(column)
	column.add_child(_label("小憩片刻", 33, PAPER))
	_pause_details = _label("", 13, MUTED)
	column.add_child(_pause_details)
	column.add_child(_button("继续航行", "resume", true))
	_pause_upgrade_button = _button("升级船只", "upgrade")
	column.add_child(_pause_upgrade_button)
	var settings: HBoxContainer = _row(9)
	column.add_child(settings)
	_quality_button = _button("画质：流畅", "quality")
	_quality_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(_quality_button)
	_mute_button = _button("声音：开", "mute")
	_mute_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(_mute_button)
	column.add_child(_button("保存并退出", "quit"))
	var note: Label = _label("没有倒计时，等你准备好了再出发。", 12, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)


func _overlay(root: Control, color: Color) -> Control:
	var overlay: ColorRect = ColorRect.new()
	overlay.color = color
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	return overlay


func _modal_panel(overlay: Control, width: float) -> PanelContainer:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel: PanelContainer = _panel(Color(0.055, 0.17, 0.20, 0.97), 8, 28)
	panel.custom_minimum_size.x = width
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	return panel


func _panel(color: Color, radius: int, padding: int) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(color, radius, padding))
	return panel


func _style(color: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, command: String, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 43.0
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 14)
	var base: Color = GOLD if primary else Color(0.065, 0.24, 0.27, 0.96)
	var hover: Color = Color("#ffdc89") if primary else Color("#24626c")
	button.add_theme_stylebox_override("normal", _style(base, 5, 10))
	button.add_theme_stylebox_override("hover", _style(hover, 5, 10))
	button.add_theme_stylebox_override("pressed", _style(CORAL if primary else LAGOON, 5, 10))
	button.add_theme_stylebox_override("disabled", _style(Color(0.10, 0.20, 0.23, 0.8), 5, 10))
	button.add_theme_color_override("font_color", NAVY if primary else PAPER)
	button.add_theme_color_override("font_hover_color", NAVY if primary else PAPER)
	button.add_theme_color_override("font_pressed_color", NAVY if primary else PAPER)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.pressed.connect(func() -> void: action.emit(command))
	return button


func _column(separation: int) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", separation)
	return box


func _row(separation: int) -> HBoxContainer:
	var box: HBoxContainer = HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", separation)
	return box


func _fixed_rect(control: Control, position: Vector2, dimensions: Vector2) -> void:
	control.position = position
	control.size = dimensions
