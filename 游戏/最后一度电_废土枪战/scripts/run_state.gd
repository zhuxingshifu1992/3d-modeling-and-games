extends RefCounted
var phase: String = "power"
var charge: float = 0.0
var tripped: bool = false
var carrying: bool = false
var elapsed: float = 0.0
var kills: int = 0
var headshots: int = 0
var shots: int = 0
var hits: int = 0
var checkpoint: String = "power"

func activate(id: String) -> bool:
	match phase:
		"power":
			if id == "power_console": phase = "connect"; checkpoint = "connect"; return true
		"connect":
			if id == "charge_terminal": phase = "charge"; return true
		"reset":
			if id == "reset_breaker": phase = "charge"; tripped = true; return true
		"collect":
			if id == "battery": phase = "extract"; carrying = true; checkpoint = "extract"; return true
		"extract":
			if id == "exit": phase = "victory"; return true
	return false

func advance(delta: float) -> void:
	if phase == "victory" or phase == "dead": return
	elapsed += maxf(0.0, delta)
	if phase != "charge": return
	charge += maxf(0.0, delta)
	if not tripped and charge >= 35.0:
		charge = 35.0
		phase = "reset"
	elif charge >= 75.0:
		charge = 75.0
		phase = "collect"

func restore_checkpoint(value: String) -> void:
	phase = value if value in ["power", "connect", "extract"] else "power"
	checkpoint = phase
	carrying = phase == "extract"
	tripped = carrying
	charge = 75.0 if carrying else 0.0

func stats() -> Dictionary:
	return {"time": elapsed, "elapsed": elapsed, "kills": kills, "headshots": headshots, "shots": shots, "hits": hits, "accuracy": float(hits) / maxf(1.0, shots) * 100.0}
