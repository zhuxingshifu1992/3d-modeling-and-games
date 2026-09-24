extends SceneTree
## Actual Exia fixture: fixed bridge clears the door sweep while the physical
## hatch remains reachable after walking across the deployed docking step.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("EXIA_DOCKING_FAIL " + label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var info: Dictionary = {}
	for row: Dictionary in load("res://scripts/catalog.gd").machines():
		if row.id == "exia": info = row
	var fixture := Node3D.new()
	root.add_child(fixture)
	var bay = load("res://scripts/bay.gd").new()
	fixture.add_child(bay)
	bay.setup(info)
	check(bay.near_hatch(bay.to_global(Vector3(0, bay.top_y + 0.14, -5.05))), "Pilot can interact from safe waiting line")
	check(bay.near_hatch(bay.to_global(Vector3(0, bay.top_y + 0.14, -2.10))), "Pilot can still board at actual armor hatch after walking across step")
	check(not bay.near_hatch(bay.to_global(Vector3(.08, bay.top_y + .14, -2.10))), "Actual hatch still requires narrow lateral alignment")
	var fixed_bridge: MeshInstance3D
	for mesh: MeshInstance3D in bay.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh is BoxMesh and is_equal_approx(mesh.mesh.size.x, 2.05) and is_equal_approx(mesh.mesh.size.y, .19): fixed_bridge = mesh
	check(fixed_bridge != null, "Fixed bridge found from actual dimensions")
	if fixed_bridge != null:
		var box: AABB = (bay.global_transform.affine_inverse() * fixed_bridge.global_transform) * fixed_bridge.get_aabb()
		check(box.end.z <= -4.64, "Fixed bridge ends before downward armor sweep")
	check(bay.boarding_step != null, "Docking step exists")
	if bay.boarding_step != null:
		var box: AABB = bay.boarding_step.transform * bay.boarding_step.get_aabb()
		check(box.position.z <= -4.70 and box.end.z >= -.85, "Deployed step continuously joins fixed bridge to cabin")
		var step_body: StaticBody3D = bay.boarding_step.get_child(0)
		for amount in [0.0, .5, .999, 1.0]:
			bay.state.hatch_open = true
			bay.door_amount = amount
			bay.tick(0)
			check(bay.boarding_step.visible == (amount > .999), "Step visual follows fully-open gate at " + str(amount))
			check((step_body.collision_layer != 0) == (amount > .999), "Step collision follows fully-open gate at " + str(amount))
	fixture.queue_free()
	await process_frame
	print("EXIA_DOCKING ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
