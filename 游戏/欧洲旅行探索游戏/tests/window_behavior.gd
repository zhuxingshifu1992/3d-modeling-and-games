extends SceneTree
## Pure placement math only; never queries or moves any native window.

func result_path() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):
			return arg.trim_prefix("--result=")
	return "res://tests/window_behavior_result.json"

func _initialize() -> void:
	var started := Time.get_unix_time_from_system()
	var game = load("res://scripts/main.gd").new()
	var errors: Array[String] = []
	var cases: Array = []
	if not game.has_method("desired_window_rect"):
		errors.append("Missing safe screen-centered placement")
	else:
		var work := Rect2i(0,0,1920,1080)
		if game.desired_window_rect(work,Vector2i(1280,800)) != Rect2i(320,140,1280,800):
			errors.append("Default centered rectangle changed")
		for screen: Rect2i in [Rect2i(0,0,1920,1080),Rect2i(0,0,1024,700),Rect2i(1920,-200,1280,720),Rect2i(-1920,0,1920,1040),Rect2i(0,0,3840,2060),Rect2i(-1080,0,1080,1880),Rect2i(0,0,800,480),Rect2i(0,0,320,240),Rect2i(0,0,80,60)]:
			for requested: Vector2i in [Vector2i(1280,800),Vector2i(1600,900),Vector2i(1920,1080),Vector2i.ZERO]:
				var placed: Rect2i = game.desired_window_rect(screen,requested)
				var passed: bool = screen.encloses(placed) and placed.size.x>0 and placed.size.y>0
				if requested.x>0 and requested.y>0:
					passed = passed and placed.size.x<=requested.x and placed.size.y<=requested.y
				cases.append({"work_area":[screen.position.x,screen.position.y,screen.size.x,screen.size.y],"requested":[requested.x,requested.y],"placed":[placed.position.x,placed.position.y,placed.size.x,placed.size.y],"passed":passed})
				if not passed:
					errors.append("Invalid placement: " + str(screen) + " request " + str(requested) + " got " + str(placed))
	var result := {"passed":errors.is_empty(),"cases":cases,"errors":errors,"started_unix":started,"completed_unix":Time.get_unix_time_from_system(),"headless":DisplayServer.get_name()=="headless","coverage_limits":["Pure placement math only. No native window placement, manual resizing, DPI scaling, taskbar, monitor hotplug, or OS cursor exercised."]}
	var file := FileAccess.open(result_path(),FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result,"  "))
		file.close()
	print("WINDOW_RESULT ",JSON.stringify(result))
	game.free()
	quit(0 if errors.is_empty() else 1)
