extends SceneTree

var failures: Array[String] = []
var started: String = ""
var received_options: Dictionary = {}
var resumed: bool = false

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(FileAccess.file_exists("res://scripts/hud.gd"), "HUD module must exist")
	check(FileAccess.file_exists("res://scripts/audio_bank.gd"), "Audio module must exist")
	if not failures.is_empty():
		quit(1)
		return
	var hud_script: Script = load("res://scripts/hud.gd")
	var bank_script: Script = load("res://scripts/audio_bank.gd")
	check(hud_script != null and hud_script.can_instantiate(), "HUD must compile")
	check(bank_script != null and bank_script.can_instantiate(), "Audio must compile")
	if not failures.is_empty():
		quit(1)
		return
	var hud: CanvasLayer = hud_script.new()
	root.add_child(hud)
	hud.setup()
	check(hud.has_method("set_settings"), "HUD must support loading persisted menu settings")
	if not hud.has_method("set_settings"):
		hud.free()
		quit(1)
		return
	hud.set_settings({"difficulty":"easy", "sensitivity":1.35, "low_quality":true, "volume":0.25})
	check(hud.options.difficulty == "easy" and is_equal_approx(hud.options.sensitivity,1.35), "Saved difficulty/sensitivity must replace menu defaults")
	hud.set_settings({"difficulty":"standard", "sensitivity":1.0, "low_quality":false, "volume":0.75})
	for method: String in ["show_menu", "show_pause", "hide_panels", "show_end", "update_hud", "set_interaction", "show_message", "hit_marker", "damage_flash"]:
		check(hud.has_method(method), "HUD method missing: " + method)
	for signal_name: String in ["start_requested", "resume_requested", "retry_requested", "restart_requested", "quit_requested", "settings_changed"]:
		check(hud.has_signal(signal_name), "HUD signal missing: " + signal_name)
	var initial_mouse: int = Input.mouse_mode
	hud.start_requested.connect(func(difficulty: String) -> void: started = difficulty)
	hud.settings_changed.connect(func(settings: Dictionary) -> void: received_options = settings)
	hud.resume_requested.connect(func() -> void: resumed = true)
	hud.show_menu({})
	var start_button: Button = hud.find_child("StartButton", true, false) as Button
	check(start_button != null, "Main menu exposes campaign start")
	start_button.pressed.emit()
	check(started == "standard" and received_options.has("sensitivity"), "Starting must emit selected difficulty and full settings")
	hud.show_pause()
	var resume_button: Button = hud.find_child("ResumeButton", true, false) as Button
	resume_button.pressed.emit()
	check(resumed, "Pause menu must emit resume request")
	check(not paused and Input.mouse_mode == initial_mouse, "HUD must leave pause/mouse ownership to game")
	hud.hide_panels()
	hud.update_hud({"health": -10, "armor": 35, "ammo": 0, "reserve": 120, "weapon": "R7 卡宾枪", "stamina": 130, "charge": 0.5, "aiming": true})
	hud.update_hud({"phase":"reset", "charge":0.5})
	check(hud.values.phase == "RESET", "Lowercase game states must select Chinese phase and reset styling")
	hud.set_interaction("接通电源", 2.0)
	check(hud.interaction_progress == 1.0, "Interaction ring clamps over-completion")
	hud.show_message("医务站", "我们需要撑过这一夜。", 0.01)
	hud.hit_marker(true)
	hud.damage_flash(0.5)
	hud.set_objective_marker(Vector2(640, 80), 21.7, true)
	hud.show_end(true, {"elapsed": 125.0, "kills": 7, "headshots": 2, "shots": 20, "hits": 10})
	check(hud.get_result_text().contains("07") and hud.get_result_text().contains("50%"), "Result must reflect passed kills and accuracy")
	hud.show_end(false, {})
	check(hud.get_result_text().contains("—"), "Missing statistics must stay unknown")
	var audio: Node = bank_script.new()
	root.add_child(audio)
	audio.setup()
	check(audio.streams.size() == 17, "All required local effects must load")
	var before: int = audio.get_child_count()
	for i: int in range(80):
		audio.play("rifle", Vector3(float(i), 1.0, 2.0))
		audio.play("hit")
	check(audio.get_child_count() == before, "Repeated sounds must reuse bounded voice pool")
	audio.set_volume(0.0)
	check(audio.master_volume == 0.0, "Sound option can mute all effects")
	audio.set_volume(5.0)
	check(audio.master_volume == 1.0, "Volume clamps unsafe external values")
	audio.set_ambience(false)
	audio.play("unknown_key")
	check(audio.has_method("shutdown"), "Audio bank must support an explicit final shutdown")
	if audio.has_method("shutdown"):
		audio.shutdown()
		audio.play("rifle")
		for voice: Node in audio.get_children():
			if voice is AudioStreamPlayer or voice is AudioStreamPlayer3D:
				check(voice.stream == null, "Shutdown releases voices and ignores late playback requests")
	else:
		for voice: Node in audio.get_children():
			if voice is AudioStreamPlayer or voice is AudioStreamPlayer3D:
				voice.stop()
				voice.stream = null
	hud.queue_free()
	audio.queue_free()
	await process_frame
	await process_frame
	# --fixed-fps advances simulated timers faster than the real-time audio mixer.
	# This test-only wall-clock grace retires mixer playbacks before server teardown.
	if DisplayServer.get_name() == "headless":
		OS.delay_msec(150)
	await process_frame
	print("HUD_AUDIO_PROBE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
