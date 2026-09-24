extends SceneTree

# Export one actual running bay. No desktop window or mouse writes.
# Godot --headless --path <project> --script tools/export_refined_game_review.gd
var output := "res://previews/refined_game"
var machine_id := "rx78"
var file_prefix := "rx78_a1"
var game
var bay
var machine: Node3D
var manifest := {
	"purpose": "Actual game geometry exported headlessly for CPU structural review; not a gameplay screenshot.",
	"omissions": ["Label3D text is omitted by this geometry export.", "HUD and dynamic SubViewport monitor video are not exported.", "Other bays and the hangar are omitted; preview renderer adds neutral lighting and a floor."],
	"states": {},
}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--machine="):
			machine_id = argument.trim_prefix("--machine=")
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("This structural exporter requires --headless.")
		quit(2)
		return
	if machine_id not in ["rx78", "nu", "exia", "freedom", "unicorn", "wing"]:
		push_error("Unsupported structural review machine: " + machine_id)
		quit(2)
		return
	if machine_id != "rx78":
		output = "res://previews/refined_" + machine_id + "_game"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = load("res://scripts/game.gd").new()
	game.automated_test = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.enabled = false
	game.player.look_enabled = false
	game.audio.set_muted(true)
	for candidate in game.bays:
		if candidate.info.id == machine_id:
			bay = candidate
	machine = game.world.get_node_or_null(machine_id) as Node3D
	if bay == null or machine == null or bay.exterior_hatch == null:
		push_error("Final refined model with CockpitHatch must be imported before export: " + machine_id)
		quit(3)
		return
	file_prefix = machine_id + "_" + str(bay.info.bay).to_lower()
	manifest["machine_id"] = machine_id
	manifest["source_model"] = bay.info.model_path
	manifest["source_model_sha256"] = FileAccess.get_sha256(bay.info.model_path)
	manifest["game_script_sha256"] = FileAccess.get_sha256("res://scripts/game.gd")
	manifest["bay_script_sha256"] = FileAccess.get_sha256("res://scripts/bay.gd")
	manifest["catalog_sha256"] = FileAccess.get_sha256("res://scripts/catalog.gd")
	manifest["cockpit"] = bay.cockpit
	manifest["height_m"] = float(bay.info.height)
	manifest["height_note"] = str(bay.info.get("height_note", ""))
	# Wing's official HEIGHT label does not define a crown/feather endpoint.
	# Preserve that distinction instead of calling the catalog value full wing height.
	var height_reference := "catalog_height" if machine_id == "wing" else "total_height" if machine_id in ["exia", "freedom", "unicorn"] else "head_height"
	manifest["height_reference"] = height_reference
	manifest[height_reference + "_m"] = float(bay.info.height)
	for opened in [false, true]:
		bay.state.y = bay.top_y
		bay.state.at_top = true
		bay.state.moving = false
		bay.state.hatch_open = opened
		bay.state.seated = not opened
		bay.transfer_active = false
		bay.door_amount = 1.0 if opened else 0.0
		bay.set_access(opened, true)
		bay.set_power(1)
		bay.tick(0.0)
		var state_name := "open" if opened else "closed"
		if not _export_state(state_name):
			quit(4)
			return
	var file := FileAccess.open(output + "/export_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("REFINED_GAME_REVIEW_EXPORTED ", JSON.stringify(manifest.states))
	game.queue_free()
	await process_frame
	quit(0)

func _material_without_viewport(source: Material, count: Dictionary) -> Material:
	if source == null:
		return null
	if not source is BaseMaterial3D:
		return source
	var replacement: BaseMaterial3D = source.duplicate()
	for property in replacement.get_property_list():
		var key: String = str(property.name)
		if key.ends_with("_texture") and replacement.get(key) is ViewportTexture:
			replacement.set(key, null)
			count["omitted_viewport_textures"] += 1
	return replacement

func _copy_geometry(source: Node, target: Node3D, basis_to_origin: Transform3D, count: Dictionary) -> void:
	if source is Label3D:
		count["omitted_labels"] += 1
	elif source is MeshInstance3D and source.is_visible_in_tree() and source.mesh != null:
		var instance := MeshInstance3D.new()
		instance.name = str(source.name) + "_" + str(count.meshes)
		instance.mesh = source.mesh
		instance.material_override = _material_without_viewport(source.material_override, count)
		for i in range(source.mesh.get_surface_count()):
			var override: Material = source.get_surface_override_material(i)
			if override != null:
				instance.set_surface_override_material(i, _material_without_viewport(override, count))
		target.add_child(instance)
		instance.owner = target
		instance.transform = basis_to_origin * source.global_transform
		count["meshes"] += 1
		count["triangles"] += instance.mesh.get_faces().size() / 3
	elif source is OmniLight3D and source.is_visible_in_tree():
		var light := OmniLight3D.new()
		light.name = "ActualCabinLight"
		light.light_color = source.light_color
		light.light_energy = source.light_energy
		light.omni_range = source.omni_range
		light.omni_attenuation = source.omni_attenuation
		target.add_child(light)
		light.owner = target
		light.transform = basis_to_origin * source.global_transform
		count["lights"] += 1
	for child in source.get_children():
		_copy_geometry(child, target, basis_to_origin, count)

func _export_state(state_name: String) -> bool:
	var review := Node3D.new()
	review.name = file_prefix.to_upper() + "_ActualGame_" + state_name
	root.add_child(review)
	var count := {"meshes": 0, "triangles": 0, "lights": 0, "omitted_labels": 0, "omitted_viewport_textures": 0}
	var to_origin: Transform3D = machine.global_transform.affine_inverse()
	_copy_geometry(machine, review, to_origin, count)
	_copy_geometry(bay, review, to_origin, count)
	var seat_world: Vector3 = bay.seat_position()
	var eye := Camera3D.new()
	eye.name = "ActualSeatedCamera"
	eye.fov = game.player.camera.fov
	eye.near = game.player.camera.near
	eye.far = game.player.camera.far
	var actual_pose := Transform3D(Basis(Vector3.UP, bay.rotation.y) * Basis(Vector3.RIGHT, 0.10), seat_world + Vector3.UP * 1.16)
	review.add_child(eye)
	eye.owner = review
	eye.transform = to_origin * actual_pose
	var eye_local: Vector3 = eye.position
	var document := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var error := document.append_from_scene(review, gltf_state)
	if error == OK:
		error = document.write_to_filesystem(gltf_state, ProjectSettings.globalize_path(output + "/" + file_prefix + "_" + state_name + ".glb"))
	if error != OK:
		push_error("Actual game geometry export failed: " + str(error))
		review.free()
		return false
	count["hatch_angle_degrees"] = float(bay.cockpit.get("hatch_angle", 90.0)) if state_name == "open" else 0.0
	count["hatch_extension_m"] = float(bay.cockpit.get("hatch_travel", 0.55)) if state_name == "open" else 0.0
	count["lift_height_m"] = bay.state.y
	count["seated_camera_godot_xyz"] = [eye_local.x, eye_local.y, eye_local.z]
	count["seated_camera_fov_degrees"] = eye.fov
	count["glb_path"] = output + "/" + file_prefix + "_" + state_name + ".glb"
	count["glb_sha256"] = FileAccess.get_sha256(count.glb_path)
	manifest.states[state_name] = count
	review.free()
	return true
