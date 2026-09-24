extends SceneTree
## Headless fixture for real Bay geometry and narrow-entry interaction limits.
## Does not instantiate the main game or access player profiles.

var failures := 0
var checks := 0
var fixture: Node3D

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("NARROW_ENTRY_FAIL " + message)

func _initialize() -> void:
	call_deferred("run")

func _make_bay(id: String, cockpit: Dictionary):
	var instance = load("res://scripts/bay.gd").new()
	fixture.add_child(instance)
	instance.setup({"id": id, "model": id.to_upper(), "height": 18.0, "bay": "TEST",
		"position": Vector3.ZERO, "yaw": 0.0, "color": Color.CYAN, "cockpit": cockpit})
	return instance

func _entry_point(instance, x: float) -> Vector3:
	return instance.to_global(Vector3(x, instance.top_y + 0.12, instance.portal_z - 1.0))

func _check_step(instance, expected_width: float, label: String) -> void:
	var step: MeshInstance3D = instance.boarding_step
	check(step != null and step.mesh is BoxMesh, label + " has a real docking step mesh")
	if step == null or not step.mesh is BoxMesh:
		return
	# Generated hierarchy is MeshInstance3D -> StaticBody3D -> CollisionShape3D.
	var shapes := step.find_children("*", "CollisionShape3D", true, false)
	check(shapes.size() == 1, label + " has exactly one generated collision shape")
	if shapes.size() != 1:
		return
	var collision := shapes[0] as CollisionShape3D
	check(collision.shape is BoxShape3D, label + " collision is a box")
	if not collision.shape is BoxShape3D:
		return
	var mesh_size: Vector3 = (step.mesh as BoxMesh).size
	var collision_size: Vector3 = (collision.shape as BoxShape3D).size
	check(is_equal_approx(mesh_size.x, expected_width), label + " visible step width is " + str(expected_width))
	check(is_equal_approx(collision_size.x, expected_width), label + " collision width is " + str(expected_width))
	check(mesh_size.is_equal_approx(collision_size), label + " visual and collision dimensions agree")
	check(is_equal_approx(mesh_size.y, 0.19), label + " step thickness is preserved")

func _has_box(instance: Node3D, expected_size: Vector3) -> bool:
	for mesh: MeshInstance3D in instance.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh is BoxMesh and (mesh.mesh as BoxMesh).size.is_equal_approx(expected_size):
			return true
	return false

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("NARROW_ENTRY requires --headless")
		quit(2)
		return
	fixture = Node3D.new()
	root.add_child(fixture)
	var baseline_profile := {"floor_y": 12.65, "portal_z": -2.5, "interior_front_z": -1.45,
		"rear_z": 0.40, "seat_offset_z": -0.90, "screen_z": -1.25, "wait_z": -5.20, "gate_z": -4.80}
	var narrow_profile := baseline_profile.duplicate(true)
	narrow_profile["docking_width"] = 0.72
	narrow_profile["entry_half_width"] = 0.10
	var narrow = _make_bay("nu", narrow_profile)
	var baseline = _make_bay("rx78", baseline_profile)
	var standard = _make_bay("exia", {})
	await process_frame

	_check_step(narrow, 0.72, "Narrow profile")
	_check_step(baseline, 1.12, "Default RX compact profile")
	check(standard.boarding_step == null, "Noncompact bay does not gain a docking step")
	for x in [-0.10, 0.0, 0.10]:
		check(narrow.near_hatch(_entry_point(narrow, x)), "Narrow entrance permits x=" + str(x))
	for x in [-0.11, 0.11]:
		check(not narrow.near_hatch(_entry_point(narrow, x)), "Narrow entrance rejects x=" + str(x))
	for x in [-0.89, 0.89]:
		check(baseline.near_hatch(_entry_point(baseline, x)), "Default compact entrance still permits x=" + str(x))
	for x in [-0.91, 0.91]:
		check(not baseline.near_hatch(_entry_point(baseline, x)), "Default compact entrance still rejects x=" + str(x))
	for x in [-1.79, 1.79]:
		check(standard.near_hatch(_entry_point(standard, x)), "Noncompact entrance still permits x=" + str(x))
	for x in [-1.81, 1.81]:
		check(not standard.near_hatch(_entry_point(standard, x)), "Noncompact entrance still rejects x=" + str(x))
	check(not narrow.near_hatch(narrow.to_global(Vector3(0, narrow.top_y + 1.0, narrow.portal_z - 1.0))), "Narrow entrance keeps its vertical range")
	check(not narrow.near_hatch(narrow.to_global(Vector3(0, narrow.top_y + 0.12, narrow.portal_z - 3.0))), "Narrow entrance keeps its approach depth range")
	check(_has_box(narrow.cabin, Vector3(0.72, 1.02, 0.23)), "Human seat back remains 0.72m wide")
	check(_has_box(narrow.cabin, Vector3(0.15, 0.12, 0.73)), "Human armrests keep their full dimensions")
	check(_has_box(narrow.cabin, Vector3(1.20, 0.20, 1.85)), "Inner cabin remains 1.20m wide")
	# Exercise the actual hangar-side placement, not only an origin-aligned fixture.
	narrow.position = Vector3(-22, 0, -30)
	narrow.rotation.y = -PI / 2.0
	for x in [-0.10, 0.10]:
		check(narrow.near_hatch(_entry_point(narrow, x)), "Rotated hangar bay permits boundary x=" + str(x))
	for x in [-0.11, 0.11]:
		check(not narrow.near_hatch(_entry_point(narrow, x)), "Rotated hangar bay rejects x=" + str(x))
	fixture.queue_free()
	await process_frame
	print("NARROW_ENTRY ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
