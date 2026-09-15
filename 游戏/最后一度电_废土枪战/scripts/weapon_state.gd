extends RefCounted
var kind: String = "rifle"
var title: String = "R7 卡宾枪"
var capacity: int = 24
var ammo: int = 24
var reserve: int = 120
var fire_interval: float = 0.125
var damage: float = 24.0
var pellets: int = 1
var spread: float = 0.016
var reload_duration: float = 1.9
var reload_left: float = 0.0
var cooldown: float = 0.0

func configure(value: String) -> void:
	kind = value
	if kind == "shotgun":
		title = "破门者 霰弹枪"; capacity = 5; reserve = 20; fire_interval = 0.9
		damage = 12.0; pellets = 7; spread = 0.065; reload_duration = 2.35
	else:
		title = "R7 卡宾枪"; capacity = 24; reserve = 120; fire_interval = 0.125
		damage = 24.0; pellets = 1; spread = 0.016; reload_duration = 1.9
	ammo = capacity; cooldown = 0.0; reload_left = 0.0

func trigger() -> bool:
	if ammo <= 0 or reload_left > 0.0 or cooldown > 0.0: return false
	ammo -= 1; cooldown = fire_interval
	return true

func request_reload() -> bool:
	if reload_left > 0.0 or ammo >= capacity or reserve <= 0: return false
	reload_left = reload_duration
	return true

func advance(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if reload_left <= 0.0: return
	reload_left = maxf(0.0, reload_left - delta)
	if reload_left <= 0.0:
		var transfer: int = mini(capacity - ammo, reserve)
		ammo += transfer; reserve -= transfer
