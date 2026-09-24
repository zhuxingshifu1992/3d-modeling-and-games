extends SceneTree
## B1 acceptance uses imported geometry and the actual production world.
## The 18.88 m landmark is the adopted footsole-to-helmet-antenna convention;
## the official total-height label does not independently identify that endpoint.

const ASSET := "res://assets/models/freedom_refined.glb"
var output := "res://previews/refined_freedom/asset_acceptance.json"
const AUTHORED_MATERIALS := ["arm_left", "arm_right", "backpack", "Chest", "gold", "Head", "left_cannon", "leg_left", "leg_right", "material", "mini_bim", "right_wing_up", "shield_left", "shield_right", "waist", "waist_shield"]

class GuardedGame:
	extends "res://scripts/game.gd"
	var mouse_attempts := 0
	func _save() -> void:
		pass
	func _apply_mouse_mode(_mode: int) -> void:
		mouse_attempts += 1

var report := {"checks": [], "failures": [], "measurements": {}, "limitations": [
	"Scale landmark is the adopted footsole-to-helmet-antenna convention at 18.88 m, not a verified official endpoint definition. Equipment wings may exceed it.",
	"B1/B2 separation is the distance between their world-space mesh AABBs: a conservative geometric lower bound, not an exact nearest-triangle measurement.",
	"This asset test does not prove hatch sweep, cockpit entry, furniture clearance, wing clearance from individual hangar fixtures, or GPU appearance. Separate tests cover those scopes."
]}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, message: String, detail: Variant = null) -> void:
	report.checks.append({"name": message, "passed": ok, "detail": detail})
	if not ok:
		report.failures.append(message)
		push_error("FREEDOM_ASSET_FAIL " + message)

func vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func bounds_of(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func box_record(box: AABB) -> Dictionary:
	return {"min": vec(box.position), "max": vec(box.end)}

func inspect_asset() -> void:
	var available := ResourceLoader.exists(ASSET)
	check(available, "Derived Freedom GLB is imported", ASSET)
	if not available:
		return
	var model := (load(ASSET) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	for required in ["FreedomBody", "CockpitHatch", "TotalHeightReference"]:
		check(model.find_child(required, true, false) != null, "Derived model contains " + required)
	var marker := model.find_child("TotalHeightReference", true, false) as Node3D
	if marker != null:
		check(absf(marker.global_position.y - 18.88) < 0.015, "Adopted scale landmark is 18.88 m", marker.global_position.y)
	var box := bounds_of(model)
	check(absf(box.position.y) < 0.025, "Feet rest on zero meters", box.position.y)
	check(box.end.y >= 18.86, "Equipped bounds contain the scale landmark; taller wings are allowed", box.end.y)
	var triangles := 0
	var material_names := {}
	var textured_names := {}
	var textures := {}
	var hatch_triangles := 0
	var authored_head_top := -INF
	var hatch := model.find_child("CockpitHatch", true, false)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		check(mesh.skin == null, "Static parked geometry has no unbaked skin: " + str(mesh.name))
		for index in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count: int = indices.size() / 3 if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
			triangles += count
			if hatch != null and (mesh == hatch or hatch.is_ancestor_of(mesh)):
				hatch_triangles += count
			var material := mesh.get_active_material(index) as BaseMaterial3D
			check(material != null, "Surface retains a PBR material: " + str(mesh.name) + "/" + str(index))
			if material == null:
				continue
			var material_name := str(material.resource_name)
			if material_name == "Head":
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for vertex: Vector3 in vertices:
					authored_head_top = maxf(authored_head_top, (mesh.global_transform * vertex).y)
			if material_name in AUTHORED_MATERIALS:
				material_names[material_name] = true
				if material.albedo_texture != null:
					textured_names[material_name] = true
			for slot in ["albedo_texture", "normal_texture", "metallic_texture", "roughness_texture", "ao_texture", "emission_texture"]:
				var texture: Texture2D = material.get(slot)
				if texture == null or textures.has(texture.get_instance_id()):
					continue
				var width := texture.get_width()
				var height := texture.get_height()
				textures[texture.get_instance_id()] = {"material": material_name, "slot": slot, "width": width, "height": height}
				check(width > 0 and height > 0 and width <= 2048 and height <= 2048, "Imported maps remain within the received 2K texture tier", textures[texture.get_instance_id()])
	check(triangles >= 350000 and triangles <= 450000, "Detailed source geometry is retained within the derived asset budget", triangles)
	check(hatch_triangles > 0, "CockpitHatch carries real moving armor triangles", hatch_triangles)
	check(is_finite(authored_head_top) and absf(authored_head_top - 18.88) < 0.025, "Authored Head geometry reaches the adopted antenna landmark", authored_head_top)
	check(material_names.size() >= 15, "At least 15 of 16 authored materials survive conversion", material_names.keys())
	check(textured_names.size() >= 15, "At least 15 authored materials retain actual albedo textures", textured_names.keys())
	report.measurements["asset"] = {"sha256": FileAccess.get_sha256(ASSET), "bounds_m": box_record(box), "triangles": triangles, "hatch_triangles": hatch_triangles, "authored_head_top_m": authored_head_top, "authored_materials": material_names.keys(), "textured_authored_materials": textured_names.keys(), "textures": textures.values()}
	model.free()

func inspect_world() -> void:
	var game := GuardedGame.new()
	game.automated_test = true
	root.add_child(game)
	game.audio.set_muted(true)
	check(game.bays.size() == 6, "Six boarding stations are retained")
	var info: Dictionary = game.catalog[3]
	check(str(info.id) == "freedom" and str(info.bay) == "B1", "B1 remains the Strike Freedom station")
	check(str(info.model_path) == ASSET and bool(info.get("refined", false)), "B1 selects the refined Freedom asset", info.model_path)
	check(game.bays[3].compact and game.bays[3].exterior_hatch != null, "B1 binds the real armor hatch and adapted cockpit")
	check(is_equal_approx(game.player.camera.position.y, 1.65), "Standing eye height remains 1.65 m")
	var player_capsule: CapsuleShape3D
	for child in game.player.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			player_capsule = child.shape
	check(player_capsule != null and is_equal_approx(player_capsule.height, 1.75) and is_equal_approx(player_capsule.radius, 0.28), "Player retains the 1.75 m human capsule and 0.28 m radius")
	var freedom := game.world.get_node_or_null("freedom") as Node3D
	var wing := game.world.get_node_or_null("wing") as Node3D
	check(freedom != null and wing != null, "Actual B1 and neighboring B2 models exist")
	if freedom != null and wing != null:
		var b1 := bounds_of(freedom)
		var b2 := bounds_of(wing)
		check(b1.position.x > -41.5 and b1.end.x < 41.5 and b1.position.z > -54.0 and b1.end.z < 54.0 and b1.end.y < 33.0, "B1 equipment stays within hangar wall and roof margins", box_record(b1))
		var gap := Vector3(maxf(0.0, maxf(b1.position.x - b2.end.x, b2.position.x - b1.end.x)), maxf(0.0, maxf(b1.position.y - b2.end.y, b2.position.y - b1.end.y)), maxf(0.0, maxf(b1.position.z - b2.end.z, b2.position.z - b1.end.z)))
		var distance := gap.length()
		check(not b1.intersects(b2) and distance > 0.05, "B1 and B2 geometry AABBs have more than 5 cm separation", distance)
		report.measurements["b1_b2_aabb_separation"] = {"coordinate_space": "world meters", "b1": box_record(b1), "b2": box_record(b2), "axis_gaps_m": vec(gap), "distance_lower_bound_m": distance, "acceptance_margin_m": 0.05}
	check(game.mouse_attempts == 0, "Automated fixture never reaches the desktop mouse boundary")
	game.queue_free()
	await process_frame

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("FREEDOM_ASSET requires --headless")
		quit(2)
		return
	inspect_asset()
	await inspect_world()
	report["status"] = "passed_with_documented_limits" if report.failures.is_empty() else "failed"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write " + output)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("FREEDOM_ASSET ", report.status, " checks=", report.checks.size(), " failures=", report.failures.size(), " report=", output)
	quit(0 if report.failures.is_empty() else 1)
