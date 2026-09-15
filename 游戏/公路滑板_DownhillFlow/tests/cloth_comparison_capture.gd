extends SceneTree
## Two isolated 3D viewports share camera, pose and lighting settings. Only the
## left actor's two albedo textures change; its material and normal data stay.

const OUTPUT := "res://previews/image2/cloth_comparison.png"
const OUTPUT_SIZE := Vector2i(1280, 900)
const VIEW_SIZE := Vector2i(640, 820)
const CAMERA_POSITION := Vector3(1.8, 1.65, -3.3)
const CAMERA_TARGET := Vector3(-0.08, 1.07, 0.02)
const SOURCE_ALBEDOS := {
	"CottonTee": "res://source/image_optimization/cotton_tee_original.png",
	"GreenDenim": "res://source/image_optimization/green_shorts_original.png",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = OUTPUT_SIZE
	root.content_scale_size = OUTPUT_SIZE
	var background := ColorRect.new()
	background.size = Vector2(OUTPUT_SIZE)
	background.color = Color("172226")
	root.add_child(background)
	var originals: Dictionary = {}
	for material_name: String in SOURCE_ALBEDOS:
		# Source assets deliberately bypass Godot import and remain outside PCK.
		var original := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_ALBEDOS[material_name]))
		if original == null or original.is_empty():
			_fail("Cannot read original albedo: " + SOURCE_ALBEDOS[material_name])
			return
		original.generate_mipmaps()
		originals[material_name] = ImageTexture.create_from_image(original)
	var actors: Array[Node3D] = []
	for index: int in range(2):
		var actor := _make_view(index, index == 0, originals)
		if actor == null:
			return
		actors.append(actor)
	var divider := ColorRect.new()
	divider.position = Vector2(639, 0)
	divider.size = Vector2(2, OUTPUT_SIZE.y)
	divider.color = Color("172226")
	root.add_child(divider)
	for frame: int in range(45):
		for actor: Node3D in actors:
			actor.call("animate", 1.0 / 60.0, 18.0, 0.0, 0.25, 0.0, 1.0)
		await process_frame
	RenderingServer.force_draw(false)
	var capture := root.get_texture().get_image()
	if capture == null or capture.is_empty() or capture.get_size() != OUTPUT_SIZE:
		_fail("Expected a rendered 1280x900 window image")
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK:
		_fail("Cannot create capture directory: " + str(directory_error))
		return
	var result := capture.save_png(output_path)
	if result != OK:
		_fail("Cannot save comparison PNG: " + str(result))
		return
	print("CLOTH_COMPARISON_CAPTURE_OK ", JSON.stringify({"path": OUTPUT, "width": capture.get_width(),
		"height": capture.get_height(), "frames": 45, "original_materials": SOURCE_ALBEDOS.keys(),
		"renderer": RenderingServer.get_current_rendering_method()}))
	quit(0)


func _make_view(index: int, use_original: bool, originals: Dictionary) -> Node3D:
	var viewport := SubViewport.new()
	viewport.name = "OriginalView" if use_original else "Image2View"
	viewport.size = VIEW_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var illumination: Dictionary = load("res://scripts/lighting.gd").build(stage, false)
	illumination.environment.background_mode = Environment.BG_COLOR
	illumination.environment.background_color = Color("768489")
	viewport.scaling_3d_scale = 1.0
	var actor: Node3D = load("res://scripts/rider.gd").new()
	stage.add_child(actor)
	actor.call("build")
	if use_original:
		var replaced: Dictionary = {}
		for instance: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
			for surface: int in range(instance.mesh.get_surface_count()):
				var current := instance.get_active_material(surface) as BaseMaterial3D
				if current == null or not originals.has(str(current.resource_name)):
					continue
				# Copy the material, leaving GLB resources shared by the right actor
				# untouched. In particular, preserve the original normal texture.
				var replacement := current.duplicate(false) as BaseMaterial3D
				replacement.albedo_texture = originals[str(current.resource_name)]
				if replacement.normal_texture != current.normal_texture or replacement.normal_enabled != current.normal_enabled:
					_fail("Normal data changed in comparison setup")
					return null
				instance.set_surface_override_material(surface, replacement)
				replaced[str(current.resource_name)] = int(replaced.get(str(current.resource_name), 0)) + 1
		if replaced.get("CottonTee", 0) != 1 or replaced.get("GreenDenim", 0) != 1:
			_fail("Expected exactly one original override for each garment: " + JSON.stringify(replaced))
			return null
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("434e50")
	ground_material.roughness = 0.9
	ground.material_override = ground_material
	stage.add_child(ground)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.16
	camera.position = CAMERA_POSITION
	camera.look_at(CAMERA_TARGET)
	camera.current = true
	var display := TextureRect.new()
	display.position = Vector2(index * VIEW_SIZE.x, 80)
	display.size = Vector2(VIEW_SIZE)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.texture = viewport.get_texture()
	root.add_child(display)
	var label := Label.new()
	label.position = Vector2(index * VIEW_SIZE.x, 0)
	label.size = Vector2(VIEW_SIZE.x, 80)
	label.text = "ORIGINAL" if use_original else "IMAGE 2"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color("edf2f0"))
	root.add_child(label)
	return actor


func _fail(message: String) -> void:
	printerr("CLOTH_COMPARISON_CAPTURE_FAILED " + message)
	quit(1)
