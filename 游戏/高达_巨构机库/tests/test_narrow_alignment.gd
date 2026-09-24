extends SceneTree
## Actual game interaction/HUD checks; no profile writes or desktop mouse effects.

class GuardedGame:
	extends "res://scripts/game.gd"
	var save_attempts := 0
	var mouse_attempts := 0
	func _save() -> void:
		save_attempts += 1
	func _apply_mouse_mode(_mode: int) -> void:
		mouse_attempts += 1

var checks := 0
var failures := 0
var game
const ALIGN_PROMPT := "请移到桥面中央，对准舱口"

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("NARROW_ALIGNMENT_FAIL " + message)

func _initialize() -> void:
	call_deferred("run")

func _bay(id: String):
	for instance in game.bays:
		if str(instance.info.id) == id:
			return instance
	return null

func _show(instance, x: float, y_offset: float = 0.12, z_offset: float = -1.0) -> void:
	game.player.global_position = instance.to_global(Vector3(x, instance.top_y + y_offset, instance.portal_z + z_offset))
	game._update_interaction()
	game._update_hud()

func _noncompact_fixture():
	# Keep exercising the production Bay.gd fallback after every real machine is
	# refined. This explicit fixture must not inherit a catalog cockpit profile.
	var instance = load("res://scripts/bay.gd").new()
	game.add_child(instance)
	instance.setup({"id": "noncompact_fixture", "model": "TEST STANDARD BAY", "name": "标准舱测试",
		"bay": "TEST", "height": 18.0, "position": Vector3(200.0, 0.0, 0.0),
		"yaw": 0.0, "color": Color("b9dfd7")})
	game.bays.append(instance)
	return instance

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("NARROW_ALIGNMENT requires --headless")
		quit(2)
		return
	game = GuardedGame.new()
	game.automated_test = true
	root.add_child(game)
	game.audio.set_muted(true)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	await process_frame
	var nu = _bay("nu")
	var rx78 = _bay("rx78")
	var standard = _noncompact_fixture()
	check(nu != null and rx78 != null and standard != null, "Production bays and independent standard fixture exist")
	if nu == null or rx78 == null or standard == null:
		game.queue_free()
		await process_frame
		quit(1)
		return
	check(nu.compact and is_equal_approx(float(nu.cockpit.get("entry_half_width", 0.0)), 0.06), "Nu uses the production 6cm entry limit")
	nu.state.at_top = true
	nu.state.y = nu.top_y
	nu.state.moving = false
	nu.state.hatch_open = false
	nu.state.seated = false
	nu.door_amount = 0.0
	for x in [-0.20, 0.20]:
		_show(nu, x)
		check(game.interaction == "align", "Off-center Nu requests alignment at x=" + str(x))
		check(game.hud.prompt.text == ALIGN_PROMPT, "Actual HUD shows alignment without an E action")
		var before: Vector3 = game.player.global_position
		game.interact()
		check(not nu.state.hatch_open and not nu.state.seated and not game.transition and game.seated_bay == null, "E cannot open or board while off-center")
		check(game.player.global_position.is_equal_approx(before), "E does not move the off-center pilot")
	nu.state.hatch_open = true
	nu.door_amount = 1.0
	_show(nu, 0.20)
	game.interact()
	check(game.interaction == "align" and not nu.state.seated and not game.transition, "An already-open hatch still requires alignment before boarding")

	for x in [-0.06, 0.06]:
		_show(nu, x)
		check(game.interaction == "board" and game.hud.prompt.text.contains("[ E ]"), "Aligned Nu retains board action at x=" + str(x))
	nu.state.hatch_open = false
	_show(nu, 0.0)
	check(game.interaction == "hatch", "Aligned closed hatch retains open action")
	nu.state.hatch_open = true
	nu.door_amount = 0.5
	_show(nu, 0.0)
	check(game.interaction == "opening", "Aligned moving hatch retains opening state")
	for x in [-0.91, 0.91]:
		_show(nu, x)
		check(game.interaction == "" and game.hud.prompt.text.is_empty(), "No alignment prompt beyond original approach width")
	_show(nu, 0.20, 0.80)
	check(game.interaction == "", "No alignment prompt outside approach height")
	_show(nu, 0.20, 0.12, -2.90)
	check(game.interaction == "", "No alignment prompt behind approach depth")
	_show(nu, 0.20, 0.12, 0.50)
	check(game.interaction == "", "No alignment prompt past approach depth")
	_show(rx78, 0.20)
	check(game.interaction == "hatch", "RX78 without explicit narrow limit keeps existing interaction")
	check(not standard.compact and standard.cockpit.is_empty(), "Independent fixture explicitly uses production noncompact fallback")
	_show(standard, 1.0)
	check(game.interaction_bay == standard and game.interaction == "hatch", "Noncompact bay permits a wider hatch approach without alignment")
	standard.state.hatch_open = true
	standard.door_amount = 0.95
	_show(standard, -1.0)
	check(game.interaction_bay == standard and game.interaction == "board", "Noncompact bay retains its 0.92 open-door threshold")
	for x in [-1.81, 1.81]:
		_show(standard, x)
		check(game.interaction == "" and game.hud.prompt.text.is_empty(), "Noncompact approach rejects points beyond its 1.8 m half width")

	game.transition = true
	_show(nu, 0.20)
	check(game.interaction == "" and game.hud.prompt.text != ALIGN_PROMPT, "Transition has priority over alignment")
	game.transition = false
	game.riding = nu
	_show(nu, 0.20)
	check(game.interaction == "" and game.hud.prompt.text.contains("升降平台运行中"), "Riding has priority over alignment")
	game.riding = null
	game.seated_bay = nu
	nu.state.seated = true
	nu.state.boot_stage = 0
	_show(nu, 0.20)
	check(game.interaction == "boot", "Seated startup has priority over alignment")
	nu.state.boot_stage = 3
	_show(nu, 0.20)
	check(game.interaction == "exit", "Seated exit has priority over alignment")
	game.seated_bay = null
	nu.state.seated = false
	game.player.global_position = nu.to_global(Vector3(0.20, nu.top_y + 0.12, -7.8))
	game._update_interaction()
	game._update_hud()
	check(game.interaction == "lift", "Platform keeps lift interaction")
	check(game.save_attempts == 0, "No profile write boundary was reached")
	check(game.mouse_attempts == 0, "No desktop mouse boundary was reached")
	game.queue_free()
	await process_frame
	print("NARROW_ALIGNMENT ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
