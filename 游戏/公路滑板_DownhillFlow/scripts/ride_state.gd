extends RefCounted

const TRACK_LENGTH: float = 2600.0
const ROAD_LIMIT: float = 4.1
var phase: String = "menu"
var mode: String = "challenge"
var distance: float = 0.0
var speed: float = 12.0
var offset: float = 0.0
var lateral_speed: float = 0.0
var elapsed: float = 0.0
var top_speed: float = 0.0
var flow: float = 0.0
var hits: int = 0
var laps: int = 0
var impact: float = 0.0
var steer: float = 0.0
var tuck: float = 0.0
var braking: float = 0.0
var drifting: bool = false

func start(new_mode: String = "challenge") -> void:
	phase = "riding"
	mode = new_mode
	distance = 0.0
	speed = 12.0
	offset = 0.0
	lateral_speed = 0.0
	elapsed = 0.0
	top_speed = 0.0
	flow = 0.0
	hits = 0
	laps = 0
	impact = 0.0
	steer = 0.0
	tuck = 0.0
	braking = 0.0
	drifting = false

func toggle_pause() -> void:
	if phase == "riding":
		phase = "paused"
	elif phase == "paused":
		phase = "riding"

func step(delta: float, controls: Dictionary, slope: float, curvature: float) -> void:
	if phase != "riding":
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	elapsed += dt
	impact = maxf(0.0, impact - dt)
	var target_steer: float = clampf(float(controls.get("steer", 0.0)), -1.0, 1.0)
	steer = lerpf(steer, target_steer, 1.0 - exp(-7.0 * dt))
	tuck = lerpf(tuck, 1.0 if controls.get("tuck", false) else 0.0, 1.0 - exp(-6.0 * dt))
	braking = lerpf(braking, 1.0 if controls.get("brake", false) else 0.0, 1.0 - exp(-9.0 * dt))
	drifting = bool(controls.get("drift", false)) and absf(steer) > 0.12 and speed > 5.0
	var acceleration: float = 0.6 - slope * 10.0 - speed * speed * lerpf(0.0024, 0.0012, tuck)
	if controls.get("push", false):
		acceleration += 2.5 * clampf((30.0 - speed) / 16.0, 0.15, 1.0)
	acceleration -= braking * 8.0
	if drifting:
		acceleration -= 2.7 * absf(steer)
		flow += speed * absf(steer) * dt * 2.0
	speed = clampf(speed + acceleration * dt, 2.0, 30.0)
	var target_lateral: float = steer * lerpf(1.9, 4.4, speed / 30.0)
	target_lateral += clampf(curvature * speed * speed * 0.025, -0.65, 0.65)
	if drifting:
		target_lateral *= 1.25
	lateral_speed = lerpf(lateral_speed, target_lateral, 1.0 - exp(-5.0 * dt))
	offset += lateral_speed * dt
	if absf(offset) > ROAD_LIMIT:
		offset = signf(offset) * ROAD_LIMIT
		lateral_speed *= -0.4
		if impact <= 0.0:
			speed = maxf(4.0, speed * 0.60)
			impact = 0.85
			hits += 1
			offset *= 0.94
	distance += speed * dt
	top_speed = maxf(top_speed, speed)
	if distance >= TRACK_LENGTH:
		if mode == "free":
			distance = fmod(distance, TRACK_LENGTH)
			laps += 1
		else:
			distance = TRACK_LENGTH
			phase = "finished"
