extends SceneTree
## Catch the real bridge approach dead-end: E must work without 6 cm manual aiming.
## Uses actual walking, capsule collisions and game actions; never desktop mouse input.

class GuardedGame:
	extends "res://scripts/game.gd"
	var mouse_attempts := 0
	func _save() -> void:
		pass
	func _apply_mouse_mode(_mode: int) -> void:
		mouse_attempts += 1

var game
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOARDING_ALIGNMENT_FAIL " + message)

func wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout

func _initialize() -> void:
	call_deferred("run")

func prepare(bay, offset: float) -> void:
	game.return_to_entry()
	bay.state.request_lift()
	bay.state.advance(100.0)
	bay.tick(0.0)
	game.player.set_view(bay.to_global(Vector3(offset, bay.top_y + 0.15, -6.38)), bay.rotation.y + PI)
	await wait(0.15)
	Input.action_press("forward")
	await wait(1.2)
	Input.action_release("forward")
	await wait(0.1)
	game._update_interaction()
	game._update_hud()

func run() -> void:
	if DisplayServer.get_name() != "headless":
		quit(2)
		return
	game = GuardedGame.new()
	game.automated_test = true
	root.add_child(game)
	game.audio.set_muted(true)
	game.start()
	await wait(0.1)
	var exia
	var expected_ids := ["exia", "nu", "freedom", "unicorn"]
	var exercised_ids: Array[String] = []
	for bay in game.bays:
		if str(bay.info.id) not in expected_ids:
			continue
		exercised_ids.append(str(bay.info.id))
		check(bay.compact and bay.cockpit.has("entry_half_width"), "Production narrow cockpit profile is active: " + str(bay.info.id))
		if str(bay.info.id) == "exia":
			exia = bay
		for offset in [-0.25, 0.25]:
			await prepare(bay, offset)
			var before: Vector3 = bay.to_local(game.player.global_position)
			print("OFFSET_APPROACH ", bay.info.id, " local=", before, " interaction=", game.interaction)
			check(absf(before.x) > 0.20, "Walking preserves realistic lateral offset before E")
			check(not bay.near_hatch(game.player.global_position), "Actual narrow throat still rejects the off-center body")
			check(game.interaction_bay == bay and game.hud.prompt.text.contains("[ E ]"), "Bridge approach provides an actionable E prompt")
			game.interact()
			await wait(0.04)
			check(not bay.state.hatch_open, "Armor remains shut until lateral alignment finishes")
			await wait(0.70)
			var after: Vector3 = bay.to_local(game.player.global_position)
			check(absf(after.x) < 0.01 and absf(after.z - before.z) < 0.015, "E physically centers the pilot without moving toward armor")
			check(bay.state.hatch_open and not game.transition, "E opens the hatch after centering")
			if not bay.state.hatch_open:
				continue
			await wait(1.35)
			game.interact()
			await wait(2.2)
			check(game.seated_bay == bay and bay.state.seated and not game.transition, "A second E completes boarding from an offset approach")
	for id in expected_ids:
		check(id in exercised_ids, "Alignment approaches were exercised for " + str(id))
	# Already-open hatch, pause, cancellation and physical obstruction use the same staging area.
	await prepare(exia, 0.60)
	exia.state.open_hatch()
	exia.set_access(true, true)
	exia.tick(2.0)
	game.interact()
	await wait(0.08)
	game.pause_game()
	var paused_position: Vector3 = game.player.global_position
	await wait(0.20)
	check(game.player.global_position.distance_to(paused_position) < 0.001, "Pause freezes assisted motion")
	game.resume()
	await wait(2.85)
	check(game.seated_bay == exia and exia.state.seated and not game.transition, "Already-open hatch aligns then boards")
	await prepare(exia, -0.60)
	game.interact()
	await wait(0.05)
	game.return_to_entry()
	await wait(0.80)
	check(game.player.global_position.z > 45.0 and not game.transition and game.seated_bay == null and not exia.state.hatch_open, "Return to entry cancels alignment and pending hatch action")
	await prepare(exia, 0.60)
	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.04, 2.0, 0.40)
	shape.shape = box
	obstacle.add_child(shape)
	exia.add_child(obstacle)
	var current: Vector3 = exia.to_local(game.player.global_position)
	obstacle.position = Vector3(0.0, exia.top_y + 1.15, current.z)
	await wait(0.1)
	game.interact()
	await wait(0.85)
	check(not exia.state.hatch_open and not game.transition and game.player.enabled, "Blocked alignment cancels cleanly without opening armor")
	check(exia.to_local(game.player.global_position).x > 0.29, "Assisted motion respects an actual physical obstacle")
	obstacle.queue_free()
	check(game.mouse_attempts == 0, "Automated test never reaches desktop mouse boundary")
	game.queue_free()
	await process_frame
	print("BOARDING_ALIGNMENT ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
