extends SceneTree

# Observe only the OS boundary. Never capture the real desktop cursor in this test.
class ObservedGame:
	extends "res://scripts/game.gd"
	var mouse_requests: Array[int] = []
	func _apply_mouse_mode(mode: int) -> void:
		mouse_requests.append(mode)

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game := ObservedGame.new()
	if not "automated_test" in game:
		push_error("MOUSE_OWNERSHIP FAIL: automated tests have no cursor ownership guard")
		game.free()
		quit(1)
		return
	game.automated_test = true
	root.add_child(game)
	game.audio.set_muted(true)
	game.start()
	game.pause_game()
	game.resume()
	game.pause_game(true)
	game.select_bay(2)
	game.return_to_entry()
	check(game.mouse_requests.is_empty(), "Automated initialization/start/pause/resume/directory/home must never change OS cursor mode")
	check(not game.player.is_processing_unhandled_input(), "Automated player must ignore physical mouse motion")
	# Test ordinary player behavior against the recorder, without touching the OS cursor.
	game.automated_test = false
	game.start()
	game.pause_game()
	game.resume()
	check(game.mouse_requests == [Input.MOUSE_MODE_CAPTURED, Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_CAPTURED], "Interactive start/pause/resume must retain cursor controls")
	game.queue_free()
	await process_frame
	await process_frame
	print("MOUSE_OWNERSHIP ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
