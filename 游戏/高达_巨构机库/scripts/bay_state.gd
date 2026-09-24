extends RefCounted
## One physical lift and cockpit. Input guards keep the round trip reversible.

var top_y: float
var y := 0.0
var at_top := false
var moving := false
var hatch_open := false
var seated := false
var boot_stage := 0
var _elapsed := 0.0
var _duration := 1.0
var _start := 0.0
var _target := 0.0

func _init(height: float = 10.8) -> void:
	top_y = maxf(height, 0.1)
	_duration = top_y / 2.4 + 1.2

func request_lift() -> bool:
	if moving or seated:
		return false
	moving = true
	hatch_open = false
	_start = y
	_target = 0.0 if at_top else top_y
	_elapsed = 0.0
	return true

func advance(delta: float, paused: bool = false) -> float:
	if not moving or paused:
		return 0.0
	var previous := y
	_elapsed = minf(_elapsed + maxf(delta, 0.0), _duration)
	var t := _elapsed / _duration
	y = lerpf(_start, _target, t * t * (3.0 - 2.0 * t))
	if _elapsed >= _duration:
		y = _target
		at_top = is_equal_approx(y, top_y)
		moving = false
	return y - previous

func open_hatch() -> bool:
	if not at_top or moving or seated:
		return false
	hatch_open = true
	return true

func board() -> bool:
	if moving or not at_top or not hatch_open or seated:
		return false
	seated = true
	boot_stage = 0
	return true

func boot() -> int:
	if seated:
		boot_stage = mini(boot_stage + 1, 3)
	return boot_stage

func leave() -> bool:
	if not seated:
		return false
	seated = false
	boot_stage = 0
	return true
