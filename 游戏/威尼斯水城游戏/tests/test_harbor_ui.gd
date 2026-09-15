extends SceneTree

const HUD_SCRIPT: Script = preload("res://scripts/harbor_ui.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud: CanvasLayer = HUD_SCRIPT.new()
	root.add_child(hud)
	_test_map_shorelines(hud)
	_test_level_and_daily_progress(hud)
	_test_camera_mode_button(hud)
	_test_hud_mouse_transparency(hud)
	hud.free()
	print("HUD_TEST_RESULT checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_map_shorelines(hud: CanvasLayer) -> void:
	var minimap: Control = hud.get("_map") as Control
	_check(minimap != null and minimap.has_method("land_rectangles"), "HUD must instantiate its canal map")
	if minimap == null or not minimap.has_method("land_rectangles"):
		return
	var shapes: Array[Rect2] = minimap.call("land_rectangles")
	# y marks the expected land/water classification for each x/z probe.
	var probes: Array[Vector3] = [
		Vector3(7.0, 1.0, -5.0), Vector3(-7.0, 1.0, -5.0),
		Vector3(30.5, 1.0, -25.5), Vector3(-23.0, 1.0, 28.3),
		Vector3(32.0, 0.0, 12.0), Vector3(-32.0, 0.0, -12.0),
		Vector3(18.0, 0.0, 25.0), Vector3(-23.0, 0.0, 28.5),
		Vector3(-17.0, 0.0, 27.0), Vector3(0.0, 0.0, 20.0),
		Vector3(20.0, 0.0, 0.0)
	]
	for probe: Vector3 in probes:
		var on_land: bool = false
		for shape: Rect2 in shapes:
			on_land = on_land or shape.has_point(Vector2(probe.x, probe.z))
		_check(on_land == (probe.y > 0.5), "Map shoreline must match the scene at x=%.1f z=%.1f" % [probe.x, probe.z])


func _test_level_and_daily_progress(hud: CanvasLayer) -> void:
	var completed_label: Label = hud.get("_completed") as Label
	var pause_label: Label = hud.get("_pause_details") as Label
	_check(completed_label != null and pause_label != null, "HUD and pause menu must both instantiate progress labels")
	if completed_label == null or pause_label == null:
		return
	hud.set_hud({"level": 0, "completed": 0, "day": 1, "day_completed": 0, "day_goal": 5})
	_check(completed_label.text.contains("Lv.1") and pause_label.text.contains("Lv.1"), "An unupgraded boat must display Lv.1 in both HUD and pause menu")
	_check(_has_label_text(hud, "第 1 天 · 今日 0 / 5 单"), "New voyage must show today's five-trip goal")
	hud.set_hud({"level": 3, "completed": 4, "day_completed": 4})
	_check(completed_label.text.contains("Lv.4") and _has_label_text(hud, "第 1 天 · 今日 4 / 5 单"), "Incremental updates must preserve the day goal and show the upgraded level")
	hud.set_hud({"completed": 5, "day": 2, "day_completed": 0})
	_check(_has_label_text(hud, "第 2 天 · 今日 0 / 5 单"), "Completing five trips must show the next day's fresh goal")


func _has_label_text(hud: CanvasLayer, text: String) -> bool:
	for child: Node in hud.find_children("*", "Label", true, false):
		if child is Label and (child as Label).text == text:
			return true
	return false


func _test_camera_mode_button(hud: CanvasLayer) -> void:
	var view_button: Button = null
	var commands: Array[String] = []
	hud.action.connect(func(command: String) -> void: commands.append(command))
	var modes: Array[Dictionary] = [
		{"mode": "follow", "label": "视角：跟随 V"},
		{"mode": "first_person", "label": "视角：船头 V"},
		{"mode": "overview", "label": "视角：全景 V"},
		{"mode": "follow", "label": "视角：跟随 V"}
	]
	for mode: Dictionary in modes:
		hud.set_hud({"camera_mode": mode["mode"]})
		var current_button: Button = _find_button_with_text(hud, str(mode["label"]))
		_check(current_button != null, "Camera mode %s must appear on the view button as %s" % [mode["mode"], mode["label"]])
		if current_button == null:
			continue
		if view_button != null:
			_check(current_button == view_button, "Changing camera mode must update the existing view button")
		view_button = current_button
		commands.clear()
		current_button.pressed.emit()
		_check(commands == ["view"], "Each camera mode must keep the view command for cycling")


func _test_hud_mouse_transparency(hud: CanvasLayer) -> void:
	var hud_root: Control = hud.get("_hud") as Control
	_check(hud_root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD canvas must pass water clicks and camera drags through")
	for child: Node in hud_root.find_children("*", "Control", true, false):
		var control: Control = child as Control
		if control is Button:
			_check(control.mouse_filter == Control.MOUSE_FILTER_STOP, "HUD buttons must receive clicks")
		else:
			_check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD labels, maps and panels must pass camera input through")


func _find_button_with_text(hud: CanvasLayer, text: String) -> Button:
	for child: Node in hud.find_children("*", "Button", true, false):
		if child is Button and (child as Button).text == text:
			return child as Button
	return null


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("HUD_TEST: " + message)
