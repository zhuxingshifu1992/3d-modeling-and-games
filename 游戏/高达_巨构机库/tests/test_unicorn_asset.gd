extends SceneTree
## A2 acceptance inspects imported geometry and the real production world.
## 21.7 m uses our footsole-to-helmet-antenna endpoint, not an official endpoint definition.

const ASSET := "res://assets/models/unicorn_refined.glb"
const SOURCE_TRIANGLES := 377328
var output := "res://previews/refined_unicorn/asset_acceptance.json"

class GuardedGame:
	extends "res://scripts/game.gd"
	var mouse_attempts := 0
	func _save() -> void:
		pass
	func _apply_mouse_mode(_mode: int) -> void:
		mouse_attempts += 1

var report := {"checks": [], "failures": [], "measurements": {}, "limitations": [
	"21.7 m is the adopted footsole-to-helmet-antenna landmark for this game, not an independently verified official endpoint definition.",
	"A2/A1 and A2/A3 separation uses world mesh AABBs: a conservative lower bound, not an exact nearest-triangle distance.",
	"Imported metallic/emission maps are checked on a 33x33 grid including edges, with the complete decoded pixel buffer hashed. This is not exhaustive per-pixel or UV-surface coverage proof.",
	"CPU material checks confirm maps and red emission settings, not GPU appearance. Hatch sweep, boarding and furniture have separate tests."
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
		push_error("UNICORN_ASSET_FAIL " + message)

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

func inspect_paint_metallic(material: BaseMaterial3D) -> Dictionary:
	var material_name := str(material.resource_name)
	var evidence := {"factor": material.metallic, "has_texture": material.metallic_texture != null}
	if material.metallic_texture == null:
		evidence["effective_metallic_max"] = material.metallic
		check(material.metallic <= 0.2, "Untextured paint/frame remains dielectric: " + material_name, evidence)
		return evidence
	# glTF packs roughness in G and metallic in B. A factor of 1 is valid when B is zero.
	var channel_is_blue := material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	evidence["texture_channel"] = material.metallic_texture_channel
	check(channel_is_blue, "Paint/frame MR texture selects the blue metallic channel: " + material_name, evidence)
	var pixels := material.metallic_texture.get_image()
	var readable := pixels != null and not pixels.is_empty()
	if readable and pixels.is_compressed():
		readable = pixels.decompress() == OK
	check(readable, "Paint/frame metallic texture has readable pixels: " + material_name)
	if not readable:
		return evidence
	var pixel_hash := HashingContext.new()
	pixel_hash.start(HashingContext.HASH_SHA256)
	pixel_hash.update(pixels.get_data())
	evidence["decoded_pixel_sha256"] = pixel_hash.finish().hex_encode()
	evidence["image_format"] = pixels.get_format()
	evidence["width"] = pixels.get_width()
	evidence["height"] = pixels.get_height()
	evidence["has_mipmaps"] = pixels.has_mipmaps()
	var blue_max := 0.0
	for row in range(33):
		for column in range(33):
			var x := roundi(float(column) * (pixels.get_width() - 1) / 32.0)
			var y := roundi(float(row) * (pixels.get_height() - 1) / 32.0)
			blue_max = maxf(blue_max, pixels.get_pixel(x, y).b)
	evidence["grid_samples"] = 1089
	evidence["sampled_blue_max"] = blue_max
	if material_name.ends_with("_WHITE"):
		check(is_zero_approx(blue_max), "White paint blue metallic samples remain zero: " + material_name, evidence)
	if channel_is_blue:
		evidence["effective_metallic_max"] = material.metallic * blue_max
		check(material.metallic * blue_max <= 0.2, "Paint/frame effective metallic does not inherit source SPEC intensity: " + material_name, evidence)
	return evidence

func inspect_frame_emission(material: BaseMaterial3D) -> Dictionary:
	var material_name := str(material.resource_name)
	var factor := material.emission.srgb_to_linear()
	var evidence := {"enabled": material.emission_enabled, "factor_srgb": [material.emission.r, material.emission.g, material.emission.b],
		"factor_linear": [factor.r, factor.g, factor.b], "energy_multiplier": material.emission_energy_multiplier,
		"operator": material.emission_operator, "has_texture": material.emission_texture != null}
	check(material.emission_enabled and material.emission_energy_multiplier > 0.0, "Destroy frame emission is enabled with positive energy: " + material_name, evidence)
	check(material.emission_texture != null, "Destroy frame retains the authored-color emission mask: " + material_name)
	if material.emission_texture == null:
		return evidence
	check(material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY, "Destroy frame emission multiplies the color factor by its mask: " + material_name, evidence)
	var pixels := material.emission_texture.get_image()
	var readable := pixels != null and not pixels.is_empty()
	if readable and pixels.is_compressed():
		readable = pixels.decompress() == OK
	check(readable, "Destroy frame emission mask has readable pixels: " + material_name)
	if not readable:
		return evidence
	var pixel_hash := HashingContext.new()
	pixel_hash.start(HashingContext.HASH_SHA256)
	pixel_hash.update(pixels.get_data())
	evidence["decoded_pixel_sha256"] = pixel_hash.finish().hex_encode()
	evidence["image_format"] = pixels.get_format()
	evidence["width"] = pixels.get_width()
	evidence["height"] = pixels.get_height()
	evidence["has_mipmaps"] = pixels.has_mipmaps()
	var positive_samples := 0
	var red_samples := 0
	var masked_black_samples := 0
	var peak := Vector3.ZERO
	for row in range(33):
		for column in range(33):
			var x := roundi(float(column) * (pixels.get_width() - 1) / 32.0)
			var y := roundi(float(row) * (pixels.get_height() - 1) / 32.0)
			var texel := pixels.get_pixel(x, y).srgb_to_linear()
			if maxf(texel.r, maxf(texel.g, texel.b)) <= 0.0001:
				masked_black_samples += 1
			var effective := texel * factor * material.emission_energy_multiplier
			if material.emission_operator == BaseMaterial3D.EMISSION_OP_ADD:
				effective = (texel + factor) * material.emission_energy_multiplier
			peak = peak.max(Vector3(effective.r, effective.g, effective.b))
			if maxf(effective.r, maxf(effective.g, effective.b)) <= 0.0001:
				continue
			positive_samples += 1
			if effective.r > effective.g * 1.5 and effective.r > effective.b * 1.5:
				red_samples += 1
	var red_ratio := float(red_samples) / maxi(positive_samples, 1)
	evidence["grid_samples"] = 1089
	evidence["masked_black_samples"] = masked_black_samples
	evidence["positive_emission_samples"] = positive_samples
	evidence["red_dominant_samples"] = red_samples
	evidence["red_fraction_of_positive_samples"] = red_ratio
	evidence["effective_linear_rgb_max"] = vec(peak)
	evidence["positive_threshold_linear"] = 0.0001
	check(positive_samples > 0 and peak.x > 0.05, "Destroy frame mask yields measurable emission after factor modulation: " + material_name, evidence)
	check(positive_samples > 0 and red_ratio >= 0.95, "At least 95 percent of emitting frame samples are red; masked dark areas may remain unlit: " + material_name, evidence)
	return evidence

func inspect_asset() -> void:
	var available := ResourceLoader.exists(ASSET)
	check(available, "Derived Unicorn GLB is imported", ASSET)
	if not available:
		return
	var packed := load(ASSET) as PackedScene
	check(packed != null, "Derived Unicorn GLB loads as a scene")
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	for required in ["UnicornBody", "CockpitHatch", "TotalHeightReference"]:
		check(model.find_child(required, true, false) != null, "Derived model contains " + required)
	var marker := model.find_child("TotalHeightReference", true, false) as Node3D
	if marker != null:
		check(absf(marker.global_position.y - 21.7) < 0.015, "Adopted scale landmark is 21.7 m", marker.global_position.y)
	var box := bounds_of(model)
	check(absf(box.position.y) < 0.025, "Feet rest on zero meters", box.position.y)
	check(box.end.y >= 21.675, "Equipped bounds contain the adopted scale landmark", box.end.y)
	var triangles := 0
	var head_triangles := 0
	var red_triangles := 0
	var hatch_triangles := 0
	var transparent_triangles := 0
	var authored_head_top := -INF
	var source_materials := {}
	var textured_materials := {}
	var normal_materials := {}
	var rough_materials := {}
	var red_materials := {}
	var paint_metallic := {}
	var frame_emission := {}
	var textures := {}
	var hatch := model.find_child("CockpitHatch", true, false)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		check(mesh.skin == null, "Static Destroy geometry has no unbaked skin: " + str(mesh.name))
		for index in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count: int = indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			triangles += count
			if hatch != null and (mesh == hatch or hatch.is_ancestor_of(mesh)):
				hatch_triangles += count
			var material := mesh.get_active_material(index) as BaseMaterial3D
			check(material != null, "Surface retains a PBR material: " + str(mesh.name) + "/" + str(index))
			if material == null:
				continue
			var material_name := str(material.resource_name)
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				transparent_triangles += count
			if material_name.begins_with("UC_HEAD_"):
				head_triangles += count
				for vertex: Vector3 in vertices:
					authored_head_top = maxf(authored_head_top, (mesh.global_transform * vertex).y)
			if material_name.begins_with("UC_"):
				source_materials[material_name] = true
				if material.albedo_texture != null:
					textured_materials[material_name] = true
				if material.normal_enabled and material.normal_texture != null:
					normal_materials[material_name] = true
				if material.roughness_texture != null:
					rough_materials[material_name] = true
				if material_name.ends_with("_WHITE") or material_name.ends_with("_RED"):
					if not paint_metallic.has(material.get_instance_id()):
						var evidence := inspect_paint_metallic(material)
						evidence["material"] = material_name
						paint_metallic[material.get_instance_id()] = evidence
				# The source has one untextured red cockpit material, not a verified frame region.
				if material_name.ends_with("_RED") and material_name not in ["UC_COCKPIT_RED", "UC_UNTEXTURED_RED"]:
					red_triangles += count
					red_materials[material_name] = true
					if not frame_emission.has(material.get_instance_id()):
						var evidence := inspect_frame_emission(material)
						evidence["material"] = material_name
						frame_emission[material.get_instance_id()] = evidence
			for slot in ["albedo_texture", "normal_texture", "metallic_texture", "roughness_texture", "ao_texture", "emission_texture"]:
				var texture: Texture2D = material.get(slot)
				if texture == null or textures.has(texture.get_instance_id()):
					continue
				var pixels := texture.get_image()
				var record := {"material": material_name, "slot": slot, "width": texture.get_width(), "height": texture.get_height(), "has_image": pixels != null and not pixels.is_empty()}
				textures[texture.get_instance_id()] = record
				check(bool(record.has_image) and int(record.width) == 2000 and int(record.height) == 2000, "Imported authored map retains real 2000x2000 pixels", record)
	check(triangles >= 300000 and triangles <= 500000, "Detailed geometry remains near the measured 377328 source triangles", triangles)
	check(hatch_triangles > 0, "CockpitHatch carries real moving armor triangles", hatch_triangles)
	check(head_triangles > 1000 and is_finite(authored_head_top) and absf(authored_head_top - 21.7) < 0.025, "Actual authored head geometry reaches the adopted antenna landmark", {"triangles": head_triangles, "top_m": authored_head_top})
	check(source_materials.size() >= 24, "At least 24 of 25 source materials survive semantic conversion", source_materials.keys())
	check(textured_materials.size() >= 24, "At least 24 authored materials retain actual color maps", textured_materials.keys())
	check(normal_materials.size() >= 20, "Source bump detail survives as normal maps on most authored materials", normal_materials.keys())
	check(rough_materials.size() >= 20, "Source surface response survives as roughness maps on most authored materials", rough_materials.keys())
	check(red_materials.size() >= 5 and red_triangles > 1000, "Destroy frame has detailed red geometry across the body", {"materials": red_materials.keys(), "triangles": red_triangles})
	check(triangles > 0 and float(transparent_triangles) / maxi(triangles, 1) <= 0.10, "Opaque armor is not accidentally imported as broadly transparent", {"transparent_triangles": transparent_triangles, "total_triangles": triangles})
	report.measurements["asset"] = {"sha256": FileAccess.get_sha256(ASSET), "bounds_m": box_record(box), "triangles": triangles, "source_triangles": SOURCE_TRIANGLES, "derived_to_source_ratio": float(triangles) / SOURCE_TRIANGLES, "hatch_triangles": hatch_triangles, "authored_head_top_m": authored_head_top, "authored_materials": source_materials.keys(), "textured_authored_materials": textured_materials.keys(), "paint_metallic": paint_metallic.values(), "frame_emission": frame_emission.values(), "textures": textures.values()}
	model.free()

func inspect_world() -> void:
	var game := GuardedGame.new()
	game.automated_test = true
	root.add_child(game)
	game.audio.set_muted(true)
	check(game.bays.size() == 6, "Six boarding stations are retained")
	var info: Dictionary = game.catalog[1]
	check(str(info.id) == "unicorn" and str(info.bay) == "A2", "A2 remains the Unicorn station")
	check(str(info.model_path) == ASSET and bool(info.get("refined", false)), "A2 selects the refined Unicorn asset", info.model_path)
	check(game.bays[1].compact and game.bays[1].exterior_hatch != null, "A2 binds the real armor hatch and adapted cockpit")
	check(is_equal_approx(game.player.camera.position.y, 1.65), "Standing eye height remains 1.65 m")
	var player_capsule: CapsuleShape3D
	for child in game.player.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			player_capsule = child.shape
	check(player_capsule != null and is_equal_approx(player_capsule.height, 1.75) and is_equal_approx(player_capsule.radius, 0.28), "Player retains the 1.75 m human capsule and 0.28 m radius")
	var unicorn := game.world.get_node_or_null("unicorn") as Node3D
	check(unicorn != null, "Actual A2 world model exists")
	if unicorn != null:
		var a2 := bounds_of(unicorn)
		check(a2.position.x > -41.5 and a2.end.x < 41.5 and a2.position.z > -54.0 and a2.end.z < 54.0 and a2.end.y < 33.0, "A2 equipment stays within hangar wall and roof margins", box_record(a2))
		for neighbor in ["rx78", "nu"]:
			var other := game.world.get_node_or_null(neighbor) as Node3D
			check(other != null, "A2 neighboring world model exists: " + neighbor)
			if other == null:
				continue
			var adjacent := bounds_of(other)
			var gap := Vector3(maxf(0.0, maxf(a2.position.x - adjacent.end.x, adjacent.position.x - a2.end.x)), maxf(0.0, maxf(a2.position.y - adjacent.end.y, adjacent.position.y - a2.end.y)), maxf(0.0, maxf(a2.position.z - adjacent.end.z, adjacent.position.z - a2.end.z)))
			check(not a2.intersects(adjacent) and gap.length() > 0.05, "A2 and " + neighbor + " geometry AABBs have more than 5 cm separation", gap.length())
			report.measurements["a2_" + neighbor + "_aabb_separation"] = {"coordinate_space": "world meters", "a2": box_record(a2), "neighbor": box_record(adjacent), "axis_gaps_m": vec(gap), "distance_lower_bound_m": gap.length(), "acceptance_margin_m": 0.05}
	check(game.mouse_attempts == 0, "Automated fixture never reaches the desktop mouse boundary")
	game.queue_free()
	await process_frame

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("UNICORN_ASSET requires --headless")
		quit(2)
		return
	report["engine_version"] = Engine.get_version_info()
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
	print("UNICORN_ASSET ", report.status, " checks=", report.checks.size(), " failures=", report.failures.size(), " report=", output)
	quit(0 if report.failures.is_empty() else 1)
