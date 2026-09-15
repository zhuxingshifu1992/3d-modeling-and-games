extends CanvasLayer

signal action_requested(action: String, payload: Variant)

const INK: Color = Color("213f42")
const MUTED: Color = Color("637672")
const PAPER: Color = Color("f5f0e5")
const GOLD: Color = Color("b98444")
const MAP_SCRIPT: Script = preload("res://scripts/map_canvas.gd")

var root_control: Control
var hud: Control
var modal: Control
var region_label: Label
var progress_label: Label
var visit_label: Label
var prompt_label: Label
var prompt_panel: PanelContainer
var toast_panel: PanelContainer
var toast_label: Label
var toast_remaining: float = 0.0
var map_canvas: Control
var mode: String = "loading"
var game_visible: bool = false
var options: Dictionary = {}
var ui_theme: Theme

func _ready() -> void:
	layer = 10
	ui_theme = Theme.new()
	ui_theme.default_font_size = 17
	var font_path: String = "res://assets/fonts/NotoSansSC.ttf"
	if FileAccess.file_exists(font_path):
		var font: FontFile = FontFile.new()
		font.data = FileAccess.get_file_as_bytes(font_path)
		var readable_font: FontVariation = FontVariation.new()
		readable_font.base_font = font
		readable_font.variation_opentype = {"wght": 450.0}
		ui_theme.default_font = readable_font
	ui_theme.set_color("font_color", "Label", INK)
	ui_theme.set_color("font_color", "Button", INK)
	ui_theme.set_color("font_hover_color", "Button", INK)
	ui_theme.set_color("font_focus_color", "Button", INK)
	ui_theme.set_color("font_pressed_color", "Button", PAPER)
	ui_theme.set_color("font_disabled_color", "Button", Color("9ca49a"))
	ui_theme.set_stylebox("normal", "Button", _style(Color("e5e8dd"), 7, 13))
	ui_theme.set_stylebox("hover", "Button", _style(Color("d4dfd1"), 7, 13))
	ui_theme.set_stylebox("pressed", "Button", _style(INK, 7, 13))
	ui_theme.set_stylebox("disabled", "Button", _style(Color("e9e8df"), 7, 13))
	var focus: StyleBoxFlat = _style(Color(0, 0, 0, 0), 7, 0)
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	ui_theme.set_stylebox("focus", "Button", focus)
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.theme = ui_theme
	add_child(root_control)
	_build_hud()
	show_loading("正在准备旅行地图与场景……")

func _style(color: Color, radius: int = 12, padding: int = 20) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _label(text: String, size: int = 17, color: Color = INK) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _paragraph(text: String, size: int = 16, color: Color = MUTED) -> Label:
	var label: Label = _label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(text: String, action: String, payload: Variant = null) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 43
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func() -> void: action_requested.emit(action, payload))
	return button

func _spacer(height: float = 10) -> Control:
	var space: Control = Control.new()
	space.custom_minimum_size.y = height
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return space

func _panel(content: Control, color: Color = PAPER) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(color, 10, 18))
	panel.add_child(content)
	return panel

func _column() -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	return column

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(hud)
	var top: HBoxContainer = HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 22
	top.offset_right = -22
	top.offset_top = 20
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	var place: VBoxContainer = _column()
	place.add_theme_constant_override("separation", 3)
	place.add_child(_label("EUROPE  /  旅行手记", 13, MUTED))
	region_label = _label("四国之间，慢慢行走", 22)
	place.add_child(region_label)
	var place_panel: PanelContainer = _panel(place, Color(0.96, 0.95, 0.90, 0.94))
	place_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(place_panel)
	var stretch: Control = Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(stretch)
	var progress: VBoxContainer = _column()
	progress.add_theme_constant_override("separation", 4)
	progress_label = _label("旅行印章  0 / 4", 19)
	progress.add_child(progress_label)
	visit_label = _label("已探访建筑  0", 13, MUTED)
	progress.add_child(visit_label)
	var progress_panel: PanelContainer = _panel(progress, Color(0.96, 0.95, 0.90, 0.94))
	progress_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(progress_panel)
	var controls: Label = _label("WASD 行走   按住右键观察   Shift 快走   Space 跳跃   E 互动   M 地图   F 拍照   Esc 暂停", 14, PAPER)
	controls.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	controls.add_theme_constant_override("shadow_offset_x", 1)
	controls.add_theme_constant_override("shadow_offset_y", 2)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_left = 24
	controls.offset_top = -40
	controls.offset_right = -24
	controls.offset_bottom = -12
	hud.add_child(controls)
	var crosshair: Label = _label("·", 30, Color(1, 1, 1, 0.86))
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -7
	crosshair.offset_top = -20
	crosshair.offset_right = 10
	crosshair.offset_bottom = 20
	hud.add_child(crosshair)
	prompt_label = _label("", 17, PAPER)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_panel = _panel(prompt_label, Color(0.08, 0.18, 0.18, 0.92))
	prompt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_panel.offset_left = -300
	prompt_panel.offset_right = 300
	prompt_panel.offset_top = -115
	prompt_panel.offset_bottom = -62
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(prompt_panel)
	prompt_panel.hide()
	toast_label = _label("", 16, PAPER)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_panel = _panel(toast_label, Color(0.09, 0.22, 0.22, 0.97))
	toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_panel.offset_left = -320
	toast_panel.offset_right = 320
	toast_panel.offset_top = 132
	toast_panel.offset_bottom = 196
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(toast_panel)
	toast_panel.hide()
	hud.hide()

func _modal(title: String, width: float = 540) -> VBoxContainer:
	if is_instance_valid(modal):
		modal.hide()
		modal.queue_free()
	map_canvas = null
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(modal)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.06, 0.14, 0.15, 0.83)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var column: VBoxContainer = _column()
	column.custom_minimum_size.x = width
	column.add_child(_label("E U R O P E   /   旅 行 手 记", 13, GOLD))
	column.add_child(_label(title, 31))
	column.add_child(_spacer(3))
	center.add_child(_panel(column))
	hud.hide()
	return column

func show_loading(message: String) -> void:
	mode = "loading"
	var column: VBoxContainer = _modal("让旅途慢下来", 610)
	column.add_child(_paragraph(message, 18))
	column.add_child(_spacer(12))
	column.add_child(_label("巴黎  ·  罗马  ·  阿尔卑斯  ·  巴伐利亚", 16, MUTED))

func show_title(can_continue: bool, subtitle: String = "从巴黎的街角走到阿尔卑斯的山脚。\n推开一扇门，收集一枚印章，留下一张照片。") -> void:
	mode = "title"
	var column: VBoxContainer = _modal("欧洲漫游", 580)
	column.add_child(_paragraph(subtitle, 18))
	column.add_child(_spacer(9))
	var continue_button: Button = _button("继续我的旅行", "continue")
	continue_button.disabled = not can_continue
	column.add_child(continue_button)
	column.add_child(_button("开始新的旅行", "new_trip"))
	column.add_child(_button("旅行偏好设置", "open_settings"))
	column.add_child(_button("离开", "quit"))
	column.add_child(_spacer(4))
	column.add_child(_paragraph("四国连通步道 · 可进入建筑 · 地标印章\n进度自动保存在这台电脑，地图车站支持快速旅行。", 13))
	if can_continue:
		continue_button.grab_focus()

func show_pause() -> void:
	mode = "pause"
	var column: VBoxContainer = _modal("稍作停留", 510)
	column.add_child(_paragraph("旅途没有倒计时，按自己的节奏继续。", 17))
	column.add_child(_button("继续行走", "resume"))
	column.add_child(_button("展开旅行地图", "open_map"))
	column.add_child(_button("偏好设置", "open_settings"))
	column.add_child(_button("保存并回到首页", "title"))
	column.add_child(_button("保存并离开", "quit"))

func hide_modal() -> void:
	mode = "play"
	if is_instance_valid(modal):
		modal.hide()
		modal.queue_free()
	modal = null
	map_canvas = null
	hud.visible = game_visible

func set_game_visible(value: bool) -> void:
	game_visible = value
	if is_instance_valid(hud):
		hud.visible = value and mode == "play"

func update_hud(region: String, stamp_count: int, stamp_total: int, visited: int, total_buildings: int, interaction: String = "") -> void:
	region_label.text = region
	progress_label.text = "旅行印章  %d / %d" % [stamp_count, stamp_total]
	visit_label.text = "已探访建筑  %d / %d" % [visited, total_buildings]
	prompt_label.text = interaction
	prompt_panel.visible = not interaction.is_empty()

func toast(message: String, duration: float = 4.0) -> void:
	toast_label.text = message
	toast_remaining = duration
	toast_panel.show()
	root_control.move_child(toast_panel, root_control.get_child_count() - 1)

func set_photo_mode(active: bool) -> void:
	root_control.visible = not active

func _process(delta: float) -> void:
	if toast_remaining > 0:
		toast_remaining -= delta
		if toast_remaining <= 0:
			toast_panel.hide()

func show_map(manifest: Dictionary, player_position: Vector3, heading: float, stamps: Array, visited_count: int) -> void:
	mode = "map"
	var column: VBoxContainer = _modal("我的四国旅行地图", 1040)
	var regions: Array = manifest.get("regions", [])
	var landmarks: Array = manifest.get("landmarks", [])
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	column.add_child(row)
	map_canvas = MAP_SCRIPT.new() as Control
	map_canvas.custom_minimum_size = Vector2(590, 440)
	map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_canvas.set("regions", regions)
	map_canvas.set("landmarks", landmarks)
	var typed_stamps: Array[String] = []
	for stamp: Variant in stamps:
		typed_stamps.append(str(stamp))
	map_canvas.set("collected", typed_stamps)
	map_canvas.set("traveler", player_position)
	map_canvas.set("heading", heading)
	row.add_child(map_canvas)
	var sidebar: VBoxContainer = _column()
	sidebar.custom_minimum_size.x = 340
	row.add_child(sidebar)
	sidebar.add_child(_label("选择下一站", 21))
	sidebar.add_child(_paragraph("沿道路步行，也可以从车站直接出发。", 14))
	for region: Dictionary in regions:
		sidebar.add_child(_button(str(region.get("name", region.get("id", ""))) + "  →", "travel", region))
	sidebar.add_child(_spacer(7))
	sidebar.add_child(_label("旅行护照", 20))
	for landmark: Dictionary in landmarks:
		var earned: bool = str(landmark.get("id", "")) in typed_stamps
		var text: String = ("已盖章  ·  " if earned else "待盖章  ·  ") + str(landmark.get("label", "地标"))
		sidebar.add_child(_label(text, 14, GOLD if earned else MUTED))
	var building_total: int = manifest.get("buildings", []).size()
	sidebar.add_child(_label("室内探访  %d / %d" % [visited_count, building_total], 14, MUTED))
	if not landmarks.is_empty() and typed_stamps.size() >= landmarks.size():
		sidebar.add_child(_paragraph("四国印章已集齐。旅程仍可继续，把喜欢的街角留在照片里。", 14, INK))
	column.add_child(_button("收起地图，继续行走  ·  M / Esc", "resume"))

func update_map_player(player_position: Vector3, heading: float) -> void:
	if is_instance_valid(map_canvas):
		map_canvas.set("traveler", player_position)
		map_canvas.set("heading", heading)
		map_canvas.queue_redraw()

func show_settings(settings: Dictionary) -> void:
	mode = "settings"
	options = settings.duplicate(true)
	var column: VBoxContainer = _modal("旅行偏好", 610)
	column.add_child(_paragraph("设置立即生效，并随旅行进度保存在本机。", 15))
	column.add_child(_setting_slider("鼠标灵敏度", "sensitivity", 0.0005, 0.006, 0.0001, 0.0018, 1000.0))
	column.add_child(_setting_slider("环境与脚步音量", "volume", 0.0, 1.0, 0.01, 0.55, 100.0))
	column.add_child(_setting_choices("画面细节", "quality", ["轻便 · 优先流畅", "均衡 · 推荐", "细致 · 较高画质"], 1))
	column.add_child(_setting_choices("窗口分辨率", "resolution", ["1280 × 800", "1600 × 900", "1920 × 1080"], 0))
	column.add_child(_paragraph("窗口模式 · 鼠标可自由移到桌面；按住右键观察。", 14))
	column.add_child(_paragraph("遇到卡顿时可选择「轻便」，并降低窗口分辨率。", 14))
	column.add_child(_spacer(4))
	column.add_child(_button("完成，返回", "back"))

func _setting_slider(caption: String, key: String, minimum: float, maximum: float, increment: float, fallback: float, multiplier: float) -> VBoxContainer:
	var column: VBoxContainer = _column()
	column.add_theme_constant_override("separation", 5)
	column.add_child(_label(caption, 16))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	var slider: HSlider = HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	slider.value = float(options.get(key, fallback))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 28
	row.add_child(slider)
	var number: Label = _label("%.1f" % (slider.value * multiplier), 15, MUTED)
	number.custom_minimum_size.x = 58
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(number)
	slider.value_changed.connect(func(value: float) -> void:
		options[key] = value
		number.text = "%.1f" % (value * multiplier)
		action_requested.emit("settings", options.duplicate(true)))
	return column

func _setting_choices(caption: String, key: String, choices: Array, fallback: int) -> VBoxContainer:
	var column: VBoxContainer = _column()
	column.add_theme_constant_override("separation", 4)
	column.add_child(_label(caption, 16))
	var select: OptionButton = OptionButton.new()
	select.custom_minimum_size.y = 39
	select.add_theme_color_override("font_color", INK)
	select.add_theme_color_override("font_hover_color", INK)
	select.add_theme_color_override("font_pressed_color", PAPER)
	for choice: Variant in choices:
		select.add_item(str(choice))
	select.select(clampi(int(options.get(key, fallback)), 0, choices.size() - 1))
	select.item_selected.connect(func(index: int) -> void:
		options[key] = index
		action_requested.emit("settings", options.duplicate(true)))
	column.add_child(select)
	return column

func show_error(message: String) -> void:
	mode = "error"
	var column: VBoxContainer = _modal("旅途还没有准备好", 650)
	column.add_child(_paragraph(message, 17))
	column.add_child(_paragraph("请使用整套游戏文件启动，保持 assets 文件夹与项目在同一目录。", 14))
	column.add_child(_button("重新载入", "reload"))
	column.add_child(_button("离开", "quit"))
