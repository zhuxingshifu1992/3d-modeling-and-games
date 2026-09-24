extends SceneTree
## Check the actual generated furniture bounds against the actual cabin wall meshes.
## Headless Bay fixtures only; no game profiles or desktop input.

const SEAT_SIZES := [Vector3(0.52, 0.4, 0.70), Vector3(0.68, 0.18, 0.67),
	Vector3(0.72, 1.02, 0.23), Vector3(0.48, 0.28, 0.18), Vector3(0.15, 0.12, 0.73),
	Vector3(0.075, 0.24, 0.10), Vector3(0.095, 0.08, 0.16), Vector3(0.025, 0.022, 0.026)]
var checks := 0
var failures := 0
var fixture: Node3D

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FURNITURE_FAIL " + message)

func _initialize() -> void:
	call_deferred("run")

func _make_bay(id: String, cockpit: Dictionary):
	var instance = load("res://scripts/bay.gd").new()
	fixture.add_child(instance)
	instance.setup({"id": id, "model": id.to_upper(), "height": 22.0 if id == "nu" else 18.0,
		"bay": "TEST", "position": Vector3(-22, 0, -30), "yaw": -PI / 2.0,
		"color": Color.CYAN, "cockpit": cockpit})
	return instance

func _make_catalog_bay(id: String):
	for info: Dictionary in load("res://scripts/catalog.gd").machines():
		if str(info.id) != id:
			continue
		check(not (info.get("cockpit", {}) as Dictionary).is_empty(), id + " has a production cockpit profile")
		if (info.get("cockpit", {}) as Dictionary).is_empty():
			return null
		var instance = load("res://scripts/bay.gd").new()
		fixture.add_child(instance)
		instance.setup(info)
		return instance
	check(false, id + " exists in the production catalog")
	return null

func _boxes(parent: Node3D, sizes: Array) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in parent.find_children("*", "MeshInstance3D", true, false):
		if not mesh.mesh is BoxMesh:
			continue
		for size: Vector3 in sizes:
			if (mesh.mesh as BoxMesh).size.is_equal_approx(size):
				result.append(mesh)
				break
	return result

func _bounds(mesh: MeshInstance3D, cabin: Node3D) -> AABB:
	return (cabin.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()

func _interior(instance) -> Dictionary:
	var walls: Array[MeshInstance3D] = []
	var rears := _boxes(instance.cabin, [Vector3(1.20, 2.08, 0.06)])
	var floors: Array[MeshInstance3D] = []
	var ceilings: Array[MeshInstance3D] = []
	# Identify actual shell meshes by cross-section, allowing each bay its own depth.
	for child in instance.cabin.get_children():
		if not child is MeshInstance3D or not child.mesh is BoxMesh:
			continue
		var size: Vector3 = (child.mesh as BoxMesh).size
		if is_equal_approx(size.x, 0.04) and is_equal_approx(size.y, 2.08):
			walls.append(child)
		elif is_equal_approx(size.x, 1.20) and is_equal_approx(size.y, 0.20):
			floors.append(child)
		elif is_equal_approx(size.x, 1.20) and is_equal_approx(size.y, 0.07):
			ceilings.append(child)
	var label := str(instance.info.id)
	check(walls.size() == 2 and rears.size() == 1 and floors.size() == 1 and ceilings.size() == 1, label + " has two side walls, rear wall, floor and ceiling with the original compact cross-sections")
	if walls.size() != 2 or rears.size() != 1 or floors.size() != 1 or ceilings.size() != 1:
		return {}
	if label == "nu":
		for mesh in walls + floors + ceilings:
			check(is_equal_approx((mesh.mesh as BoxMesh).size.z, 2.0), "Nu keeps the 1.20m wide, 2.0m deep cabin")
	var left := _bounds(walls[0], instance.cabin)
	var right := _bounds(walls[1], instance.cabin)
	if left.position.x > right.position.x:
		var swap := left
		left = right
		right = swap
	var interior := {"left": left.end.x, "right": right.position.x,
		"rear": _bounds(rears[0], instance.cabin).position.z,
		"front": _bounds(floors[0], instance.cabin).position.z,
		"ceiling": _bounds(ceilings[0], instance.cabin).position.y}
	check(float(interior.left) < float(interior.right) and float(interior.front) < float(interior.rear), label + " has positive measured cabin clearance")
	print("FURNITURE_INTERIOR ", label, " cabin_local_m=", interior)
	return interior

func _fits(mesh: MeshInstance3D, instance, interior: Dictionary, label: String) -> void:
	var box := _bounds(mesh, instance.cabin)
	check(box.position.x >= float(interior.left) - 0.00001 and box.end.x <= float(interior.right) + 0.00001,
		label + " stays between side walls: " + str(box) + " limits=" + str(interior.left) + ".." + str(interior.right))
	# Include measured limits on every failure so source profile repairs are reviewable.
	check(box.end.z <= float(interior.rear) + 0.00001, label + " stays ahead of the rear wall: rear_z=" + str(box.end.z) + " limit=" + str(interior.rear))
	check(box.position.z >= float(interior.front) - 0.00001, label + " stays behind the cabin front edge: front_z=" + str(box.position.z) + " limit=" + str(interior.front))
	check(box.end.y <= float(interior.ceiling) + 0.00001, label + " stays below the ceiling inner face: top_y=" + str(box.end.y) + " limit=" + str(interior.ceiling))

func _check_screens(instance, interior: Dictionary, state: String) -> void:
	check(instance.monitor_panels.size() == 3, state + " has three monitor panels")
	for panel: Node3D in instance.monitor_panels:
		var frames := _boxes(panel, [Vector3(0.36, 0.58, 0.08), Vector3(0.78, 0.62, 0.08)])
		check(frames.size() == 1, state + " retains full-size monitor frame")
		for frame: MeshInstance3D in frames:
			_fits(frame, instance, interior, state + " " + str(panel.name))

func _sample_screen_motion(instance, interior: Dictionary, opened: bool) -> void:
	instance.set_access(opened)
	# Advance the real production Tween deterministically, including its two phases.
	instance.access_tween.pause()
	for index in range(1, 11):
		instance.access_tween.custom_step(0.05)
		_check_screens(instance, interior, str(instance.info.id) + " " + ("Fold" if opened else "Deploy") + " tween at " + str(index * 0.05) + "s")

func _check_furniture(instance) -> void:
	var label := str(instance.info.id) + " "
	var first_check := checks
	var first_failure := failures
	var interior := _interior(instance)
	if interior.is_empty():
		return
	var seats := _boxes(instance.cabin, SEAT_SIZES)
	check(seats.size() == 12, label + "all full-size seat, armrest, and control pieces are present")
	for mesh: MeshInstance3D in seats:
		_fits(mesh, instance, interior, label + "Pilot seat " + str(mesh.name))
	var consoles := _boxes(instance.cabin, [Vector3(0.12, 0.25, 1.13)])
	check(consoles.size() == 2, label + "both full-size consoles are present")
	for mesh: MeshInstance3D in consoles:
		_fits(mesh, instance, interior, label + "Console " + str(mesh.name))
	var buttons := _boxes(instance.cabin, [Vector3(0.055, 0.025, 0.055)])
	check(buttons.size() == 10, label + "console buttons are retained")
	for mesh: MeshInstance3D in buttons:
		_fits(mesh, instance, interior, label + "Console button " + str(mesh.name))
	_check_screens(instance, interior, label + "Deployed")
	instance.set_access(true, true)
	_check_screens(instance, interior, label + "Folded immediate")
	instance.set_access(false, true)
	for i in range(3):
		check(is_equal_approx(instance.monitor_panels[i].rotation.y, float(i - 1) * -0.55), label + "deployed panel restores original yaw")
	_sample_screen_motion(instance, interior, true)
	_check_screens(instance, interior, label + "Folded tween")
	_sample_screen_motion(instance, interior, false)
	_check_screens(instance, interior, label + "Deployed tween")
	for i in range(3):
		check(is_equal_approx(instance.monitor_panels[i].rotation.y, float(i - 1) * -0.55), label + "Tween restores deployed yaw")
	print("FURNITURE_MACHINE ", instance.info.id, " checks=", checks - first_check, " failures=", failures - first_failure)

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("FURNITURE requires --headless")
		quit(2)
		return
	fixture = Node3D.new()
	root.add_child(fixture)
	var nu = _make_catalog_bay("nu")
	var exia = _make_catalog_bay("exia")
	var freedom = _make_catalog_bay("freedom")
	var unicorn = _make_catalog_bay("unicorn")
	var rx = _make_bay("rx78", {"floor_y": 12.65, "portal_z": -2.50, "interior_front_z": -1.45,
		"rear_z": 0.40, "seat_offset_z": -0.90, "screen_z": -1.25})
	await process_frame
	for instance in [nu, exia, freedom, unicorn]:
		if instance != null:
			_check_furniture(instance)
	for mesh: MeshInstance3D in _boxes(rx.cabin, [Vector3(0.12, 0.25, 1.13)]):
		check(is_equal_approx(absf(mesh.position.x), 0.50) and is_equal_approx(mesh.position.z, -1.29), "Default RX console position is unchanged")
	rx.set_access(true, true)
	for i in range(3):
		check(is_equal_approx(rx.monitor_panels[i].position.x, float(i - 1) * 0.43), "Default RX screen spacing is unchanged")
		check(is_equal_approx(rx.monitor_panels[i].rotation.y, float(i - 1) * -0.55), "Default RX folded yaw is unchanged")
		check(is_equal_approx(rx.monitor_panels[i].position.y, 1.98), "Default RX folded height is unchanged")
	fixture.queue_free()
	await process_frame
	print("FURNITURE ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
