extends RefCounted
## A single analytic centreline drives terrain, board, camera and simulation.
## s is longitudinal metres. Small horizontal variation makes travelled distance
## slightly longer than the nominal route length without discontinuous segments.

const LENGTH: float = 2600.0
const HALF_WIDTH: float = 4.8

func sample(s: float) -> Dictionary:
	var distance: float = clampf(s, -100.0, LENGTH + 200.0)
	var x: float = 76.0 * sin(distance / 120.0) + 61.0 * sin(distance / 390.0)
	var y: float = 130.0 - distance * (95.0 / LENGTH) + 1.35 * sin(distance / 135.0) + 0.7 * sin(distance / 325.0)
	var dx: float = 76.0 / 120.0 * cos(distance / 120.0) + 61.0 / 390.0 * cos(distance / 390.0)
	var dy: float = -95.0 / LENGTH + 1.35 / 135.0 * cos(distance / 135.0) + 0.7 / 325.0 * cos(distance / 325.0)
	var ddx: float = -76.0 / (120.0 * 120.0) * sin(distance / 120.0) - 61.0 / (390.0 * 390.0) * sin(distance / 390.0)
	var forward: Vector3 = Vector3(dx, dy, -1.0).normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(forward).normalized()
	return {
		"position": Vector3(x, y, -distance),
		"forward": forward,
		"right": right,
		"up": up,
		"curvature": ddx / pow(1.0 + dx * dx, 1.5),
		"slope": dy / sqrt(1.0 + dx * dx),
	}
