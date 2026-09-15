extends SceneTree

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func _initialize() -> void:
	var script: Script = load("res://scripts/ride_state.gd")
	check(script != null, "Ride state module must exist")
	if script == null:
		quit(1)
		return
	var ride = script.new()
	ride.start("challenge")
	for i in 120:
		ride.step(1.0 / 60.0, {"push": true}, -0.035, 0.0)
	check(ride.distance > 20.0, "Pushing must move the skater along track")
	check(ride.speed > 12.0, "Pushing must accelerate")
	var old_speed: float = ride.speed
	for i in 60:
		ride.step(1.0 / 60.0, {"brake": true}, -0.035, 0.0)
	check(ride.speed < old_speed, "Braking must reduce speed")
	for i in 40:
		ride.step(1.0 / 60.0, {"steer": 1.0}, 0.0, 0.0)
	check(ride.offset > 0.25, "Right input must move right")
	ride.toggle_pause()
	var old_distance: float = ride.distance
	var old_time: float = ride.elapsed
	ride.step(1.0, {"push": true}, -0.1, 0.0)
	check(ride.distance == old_distance and ride.elapsed == old_time, "Paused run must freeze simulation and timer")
	ride.toggle_pause()
	for i in 240:
		ride.step(1.0 / 60.0, {"steer": 1.0, "push": true}, -0.03, 0.0)
	check(absf(ride.offset) <= 4.12, "Road edge must contain skater")
	check(ride.hits > 0, "Road edge must register impact")
	ride.distance = 2599.9
	ride.speed = 15.0
	ride.step(0.1, {}, -0.03, 0.0)
	check(ride.phase == "finished", "Challenge must finish at 2600m")
	check(ride.distance == 2600.0, "Finish distance must be exact")
	ride.start("free")
	ride.distance = 2599.9
	ride.step(0.1, {}, -0.03, 0.0)
	check(ride.phase == "riding" and ride.laps == 1, "Free ride must loop without ending")
	ride.start("challenge")
	check(ride.distance == 0.0 and ride.elapsed == 0.0 and ride.hits == 0 and ride.offset == 0.0, "Restart must reset all run progress")
	# A fixed simulation must be stable across different rendering rates.
	var fast = script.new()
	var slow = script.new()
	fast.start("challenge")
	slow.start("challenge")
	for i in 600:
		fast.step(1.0/60.0, {"push": true}, -0.03, 0.0)
	for i in 300:
		slow.step(1.0/30.0, {"push": true}, -0.03, 0.0)
	check(absf(fast.distance - slow.distance) < 1.0, "Travel must remain stable between 30 and 60Hz")
	print("RIDE_TESTS failures=", failures)
	quit(1 if failures > 0 else 0)
