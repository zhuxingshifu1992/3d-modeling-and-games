extends SceneTree
var errors: Array[String] = []

func expect(value: bool, label: String) -> void:
	if not value: errors.append(label)

func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/run_state.gd") or not ResourceLoader.exists("res://scripts/weapon_state.gd"):
		print("CORE_TEST_FAIL: mission and weapon rules do not exist yet")
		quit(1)
		return
	var s = load("res://scripts/run_state.gd").new()
	expect(not s.activate("charge_terminal"), "cannot charge before supplying power")
	expect(s.activate("power_console") and s.phase == "connect", "power opens charging objective")
	expect(not s.activate("power_console"), "power interaction cannot be repeated")
	expect(s.activate("charge_terminal"), "start charging")
	s.advance(40.0)
	expect(s.phase == "reset" and is_equal_approx(s.charge, 35.0), "single trip caps progress at 35")
	s.advance(25.0)
	expect(is_equal_approx(s.charge, 35.0), "outage pauses charge without losing progress")
	expect(s.activate("reset_breaker"), "breaker reset accepted")
	s.advance(40.0)
	expect(s.phase == "collect", "charging completes after reset")
	expect(s.activate("battery") and s.carrying, "battery can be collected once")
	expect(s.activate("exit") and s.phase == "victory", "extraction wins without all enemies dead")
	var checkpoint = load("res://scripts/run_state.gd").new()
	checkpoint.restore_checkpoint("extract")
	expect(checkpoint.carrying and checkpoint.phase == "extract", "extraction checkpoint preserves battery")
	var w = load("res://scripts/weapon_state.gd").new()
	w.configure("rifle")
	expect(w.trigger(), "loaded weapon fires")
	expect(not w.trigger(), "fire rate prevents same-frame double shot")
	w.advance(1.0)
	w.ammo = 2
	w.reserve = 3
	expect(w.request_reload(), "reload starts with partial reserve")
	expect(not w.trigger(), "cannot fire during reload")
	w.advance(3.0)
	expect(w.ammo == 5 and w.reserve == 0, "reload conserves total ammunition")
	w.ammo = 0
	expect(not w.trigger() and not w.request_reload(), "empty weapon cannot fire or invent rounds")
	if errors.is_empty(): print("CORE_TEST_OK: 16 mission and ammunition assertions")
	else: print("CORE_TEST_FAIL ", JSON.stringify(errors))
	quit(0 if errors.is_empty() else 1)
