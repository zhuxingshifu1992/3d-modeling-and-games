extends SceneTree

# Regression: benchmark must measure wall-clock stalls, not a clamped animation delta.
func _initialize() -> void:
	var game = load("res://scripts/main.gd").new()
	game.benchmark = true
	game.paused_game = true
	game.bench_seconds = 1000.0
	game._process(0.001)
	var before: float = game.bench_elapsed
	OS.delay_msec(150)
	game._process(0.001)
	var measured: float = game.bench_elapsed-before
	var passed: bool = measured >= 0.14 and measured < 2.0
	print("FRAME_TIMING ", "PASS" if passed else "FAIL", " wall_stall_seconds=", measured)
	game.free()
	quit(0 if passed else 1)
