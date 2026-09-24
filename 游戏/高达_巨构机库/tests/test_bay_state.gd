extends SceneTree

var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var script_path := "res://scripts/bay_state.gd"
	if not ResourceLoader.exists(script_path):
		check(false, "Missing real boarding and lift controller")
		quit(1)
		return
	var State = load(script_path)
	var b = State.new(10.8)
	check(not b.board(), "Cannot board a cockpit from the ground")
	check(not b.open_hatch(), "Cannot open distant hatch from ground")
	check(b.request_lift(), "Ground lift can be activated")
	check(not b.request_lift(), "Repeated input cannot reverse moving lift")
	check(not b.board(), "Cannot board while lift is moving")
	b.advance(1.0, true)
	check(is_equal_approx(b.y, 0.0), "Pause freezes lift position")
	for i in range(240):
		b.advance(1.0 / 30.0, false)
	check(is_equal_approx(b.y, 10.8), "Lift reaches physical cockpit floor")
	check(b.at_top and not b.moving, "Lift unlocks only at arrival")
	check(not b.board(), "Closed hatch blocks boarding")
	check(b.open_hatch() and b.board(), "Open hatch allows boarding at top")
	check(not b.request_lift(), "Seated pilot cannot move platform")
	check(b.boot() == 1 and b.boot() == 2 and b.boot() == 3, "Three ordered startup stages")
	check(b.boot() == 3, "Extra input cannot advance beyond ready")
	check(b.leave(), "Pilot can leave ready cockpit")
	check(not b.seated and b.boot_stage == 0, "Exit clears power without moving lift")
	check(b.request_lift(), "Unoccupied cockpit permits return to ground")
	for i in range(240):
		b.advance(1.0 / 30.0, false)
	check(is_equal_approx(b.y, 0.0) and not b.at_top, "Complete round trip reaches ground")
	check(not b.leave(), "Repeated exit is harmless")
	var tall = State.new(13.2)
	tall.request_lift()
	tall.advance(100.0, false)
	check(is_equal_approx(tall.y, 13.2), "Large frame step cannot overshoot platform")
	print("BAY_STATE ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
