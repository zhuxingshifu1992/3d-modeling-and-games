extends RefCounted

## The same three hull samples participate in movement and wall sliding.
## Rotation can put an end sample over a bank while the center stays safe;
## such a sample may move out or along the bank, but never farther inward.
const VoyageLogic: Script = preload("res://scripts/voyage.gd")
const HULL_REACH: float = 1.0
const END_MARGIN: float = 0.52
const MAX_STEP: float = 0.2
const CONTACT_EPSILON: float = 0.000001


static func constrain_motion(voyage: RefCounted, from: Vector3, to: Vector3, heading: float) -> Vector3:
	var origin: Vector3 = voyage.constrain_motion(from, from)
	if not to.is_finite() or not is_finite(heading):
		return origin
	var destination := Vector3(clampf(to.x, -44.2, 44.2), origin.y, clampf(to.z, -39.2, 39.2))
	var forward := Vector2(sin(heading), -cos(heading)) * HULL_REACH
	var position := Vector2(origin.x, origin.z)
	var displacement := Vector2(destination.x, destination.z) - position
	var steps: int = maxi(1, int(ceil(displacement.length() / MAX_STEP)))
	var movement: Vector2 = displacement / float(steps)
	for step_index: int in range(steps):
		var candidate: Vector2 = position + movement
		if _allows_hull(position, candidate, forward):
			position = candidate
			continue
		# Axis separation preserves useful travel when thrust meets a bank.
		candidate = position + Vector2(movement.x, 0.0)
		if _allows_hull(position, candidate, forward):
			position = candidate
		candidate = position + Vector2(0.0, movement.y)
		if _allows_hull(position, candidate, forward):
			position = candidate
	return Vector3(position.x, origin.y, position.y)


static func _allows_hull(from: Vector2, to: Vector2, forward: Vector2) -> bool:
	return (
		_allows_sample(from, to, VoyageLogic.BOAT_MARGIN)
		and _allows_sample(from + forward, to + forward, END_MARGIN)
		and _allows_sample(from - forward, to - forward, END_MARGIN)
	)


static func _allows_sample(from: Vector2, to: Vector2, margin: float) -> bool:
	var x_limit: float = 45.0 - margin
	var z_limit: float = 40.0 - margin
	if maxf(0.0, absf(to.x) - x_limit) > maxf(CONTACT_EPSILON, absf(from.x) - x_limit):
		return false
	if maxf(0.0, absf(to.y) - z_limit) > maxf(CONTACT_EPSILON, absf(from.y) - z_limit):
		return false
	for island: Rect2 in VoyageLogic.ISLANDS:
		var expanded: Rect2 = island.grow(margin)
		if _penetration(to, expanded) > maxf(CONTACT_EPSILON, _penetration(from, expanded)):
			return false
	return true


static func _penetration(point: Vector2, bounds: Rect2) -> float:
	# Zero outside; inside, the shortest distance back to navigable water.
	# Test each island/sample separately so leaving one overlap cannot pay
	# for entering another obstacle or pushing the other end farther in.
	return maxf(0.0, minf(
		minf(point.x - bounds.position.x, bounds.end.x - point.x),
		minf(point.y - bounds.position.y, bounds.end.y - point.y)
	))
