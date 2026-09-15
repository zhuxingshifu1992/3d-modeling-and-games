extends Node3D
## Original reference model plus a deliberately small, gameplay-safe collision set.
## Coordinates are Godot metres: original Blender (x,y,z) -> (x,z,-y).

const MODEL_PATH: String = "res://assets/models/charging_yard.glb"
const CELL: float = 0.5
const NAV_MIN: Vector2 = Vector2(-23.5, -27.5)
const NAV_SIZE: Vector2i = Vector2i(95, 105)
const BODY_CLEARANCE: float = 0.40
const TERRACE_Y: float = 3.04
const STAIR_SHIFT: float = 0.85

var _built: bool = false
var _grid: AStarGrid2D = AStarGrid2D.new()
var _obstacles: Array[Rect2] = []
var _covers: Array[Vector3] = []
var _power_lights: Array[OmniLight3D] = []
var _power_materials: Array[StandardMaterial3D] = []
var _source_power_materials: Array[BaseMaterial3D] = []
var _source_power_copies: Dictionary = {}
var _render_meshes: Array[MeshInstance3D] = []
var _sun: DirectionalLight3D
var _environment: Environment
var _alarm_light: OmniLight3D
var _alarm_material: StandardMaterial3D
var _alarm: bool = false
var _power: bool = false
var _time: float = 0.0
var _low_quality: bool = false
var _materials: Dictionary = {}

func build() -> void:
	if _built:
		return
	_built = true
	name = "World"
	_load_reference()
	_build_collision()
	_build_walkable_stairs()
	_build_cover()
	_build_perimeter()
	_build_lighting()
	_build_power_lights()
	_build_navigation()
	set_power(false)
	set_process(false)

func _load_reference() -> void:
	var resource: PackedScene = load(MODEL_PATH) as PackedScene
	if resource == null:
		push_error("Cannot load original charging yard: " + MODEL_PATH)
		return
	var model: Node3D = resource.instantiate() as Node3D
	model.name = "ReferenceYard"
	add_child(model)
	_configure_import(model)
	_batch_reference_geometry(model)

func _configure_import(node: Node) -> void:
	if node is Node3D and "Open metal office staircase" in String(node.name):
		# The reference stair intersected its upper passage. Move the entire
		# unchanged assembly east and bridge the landing, preserving every part.
		(node as Node3D).position.x += STAIR_SHIFT
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		_render_meshes.append(instance)
		var label: String = String(instance.name).to_lower()
		var decoration: bool = "overgrowth" in label or "utilities" in label or "debris" in label
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if decoration else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		instance.visibility_range_end = 125.0 if decoration else 155.0
		instance.visibility_range_end_margin = 8.0
		# Duplicate just the actual cyan emissive material, preserving every
		# original albedo/normal/roughness map and every other GLB material.
		for surface: int in range(instance.mesh.get_surface_count()):
			var source: Material = instance.mesh.surface_get_material(surface)
			if source is BaseMaterial3D and "light_cyan" in source.resource_name.to_lower():
				var material_id: int = source.get_instance_id()
				if not _source_power_copies.has(material_id):
					var power_copy: BaseMaterial3D = source.duplicate() as BaseMaterial3D
					_source_power_copies[material_id] = power_copy
					_source_power_materials.append(power_copy)
				var copy: BaseMaterial3D = _source_power_copies[material_id]
				instance.set_surface_override_material(surface, copy)
	if node is Light3D:
		(node as Light3D).visible = false
	for child: Node in node.get_children():
		_configure_import(child)

func _batch_reference_geometry(model: Node3D) -> void:
	# GLB groups are useful authoring boundaries, but repeat the same material
	# across 310 surfaces. A static batch shares the exact Material object and
	# vertex format, while keeping shadow-free leaves/cables out of sun passes.
	# SurfaceTool preserves UVs, vertex colours, indices, normals and tangents.
	var started: int = Time.get_ticks_msec()
	var sources: Array[MeshInstance3D] = _render_meshes.duplicate()
	var groups: Dictionary = {}
	var statistics: Dictionary = {"source_meshes": sources.size(), "source_surfaces": 0, "source_triangles": 0, "source_uv_vertices": 0, "source_shadow_surfaces": 0, "batch_meshes": 0, "batch_surfaces": 0, "batch_triangles": 0, "batch_uv_vertices": 0, "batch_shadow_surfaces": 0}
	var relative_root: Transform3D = model.global_transform.affine_inverse()
	for instance: MeshInstance3D in sources:
		var transform: Transform3D = relative_root * instance.global_transform
		for surface: int in range(instance.mesh.get_surface_count()):
			var source_arrays: Array = instance.mesh.surface_get_arrays(surface)
			statistics.source_surfaces += 1
			statistics.source_triangles += _triangle_count(source_arrays)
			statistics.source_uv_vertices += _uv_count(source_arrays)
			if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				statistics.source_shadow_surfaces += 1
			var material: Material = instance.get_active_material(surface)
			var material_id: int = material.get_instance_id() if material != null else 0
			var format: int = instance.mesh.surface_get_format(surface)
			var key: String = str(material_id) + ":" + str(instance.cast_shadow) + ":" + str(format)
			# Transparent geometry retains object-level sorting, rather than
			# collecting unrelated glass into one scene-wide transparent object.
			if material is BaseMaterial3D and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				key += ":transparent:" + str(instance.get_instance_id())
			if not groups.has(key):
				var surface_tool: SurfaceTool = SurfaceTool.new()
				surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				surface_tool.set_material(material)
				groups[key] = {"tool": surface_tool, "shadow": instance.cast_shadow, "material": material, "names": PackedStringArray(), "range": instance.visibility_range_end}
			var group: Dictionary = groups[key]
			var tool: SurfaceTool = group.tool
			tool.append_from(instance.mesh, surface, transform)
			var names: PackedStringArray = group.names
			if not names.has(String(instance.name)):
				names.append(String(instance.name))
			group.names = names
	var batch_root: Node3D = Node3D.new()
	batch_root.name = "StaticMaterialBatches"
	model.add_child(batch_root)
	_render_meshes.clear()
	for key: String in groups:
		var group: Dictionary = groups[key]
		var tool: SurfaceTool = group.tool
		var combined: ArrayMesh = tool.commit()
		var instance: MeshInstance3D = MeshInstance3D.new()
		var material: Material = group.material
		instance.name = "Batch_%02d_%s" % [_render_meshes.size(), material.resource_name if material != null else "default"]
		instance.mesh = combined
		instance.cast_shadow = int(group.shadow)
		instance.visibility_range_end = float(group.range)
		instance.visibility_range_end_margin = 8.0
		instance.set_meta("reference_source_names", group.names)
		batch_root.add_child(instance)
		_render_meshes.append(instance)
		for surface: int in range(combined.get_surface_count()):
			var arrays: Array = combined.surface_get_arrays(surface)
			statistics.batch_surfaces += 1
			statistics.batch_triangles += _triangle_count(arrays)
			statistics.batch_uv_vertices += _uv_count(arrays)
			if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				statistics.batch_shadow_surfaces += 1
	# Keep all original named nodes and transforms as reference markers. Clear
	# their meshes only after every SurfaceTool has committed successfully.
	for source: MeshInstance3D in sources:
		source.set_meta("reference_source_name", String(source.name))
		source.set_meta("reference_transform", source.transform)
		source.mesh = null
		source.visible = false
	statistics.batch_meshes = _render_meshes.size()
	statistics.merge_ms = Time.get_ticks_msec() - started
	set_meta("static_batch_stats", statistics)
	print("WORLD_STATIC_BATCH ", JSON.stringify(statistics))

func _triangle_count(arrays: Array) -> int:
	if arrays[Mesh.ARRAY_INDEX] != null:
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if not indices.is_empty():
			return int(indices.size() / 3)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return int(vertices.size() / 3)

func _uv_count(arrays: Array) -> int:
	if arrays[Mesh.ARRAY_TEX_UV] == null:
		return 0
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	return uv.size()

func _solid_box(label: String, center: Vector3, size: Vector3, navigation: bool = true, padding: float = BODY_CLEARANCE) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	body.add_to_group("world_solids")
	if navigation:
		_obstacles.append(Rect2(Vector2(center.x - size.x * 0.5, center.z - size.z * 0.5), Vector2(size.x, size.z)).grow(padding))
	return body

func _build_collision() -> void:
	# No triangle collision is generated from the 63 MB scene. Wires, leaves,
	# scooters, wheel stops, hoses and small discarded items stay non-solid.
	_solid_box("YardGround", Vector3(0, -0.14, -2), Vector3(50, 0.32, 56), false)
	_solid_box("WestBoundary", Vector3(-24.25, 3, -2), Vector3(0.5, 6, 55), false)
	_solid_box("EastBoundary", Vector3(24.25, 3, -2), Vector3(0.5, 6, 55), false)
	_solid_box("SouthBoundary", Vector3(0, 3, 24.35), Vector3(49, 6, 0.5), false)
	_solid_box("NorthBoundary", Vector3(0, 3, -28.6), Vector3(49, 6, 0.5), false)
	_solid_box("OfficeClosedShell", Vector3(10, 2.94, 0), Vector3(6.10, 5.88, 5.10))
	_solid_box("RearWarehouseClosed", Vector3(3, 2.7, -25.5), Vector3(34.1, 5.4, 7.05))
	_solid_box("WhiteUtilityContainers", Vector3(-16.4, 2.8, -13.8), Vector3(6.10, 5.6, 4.25))
	_solid_box("BlueContainerAndTank", Vector3(-16.47, 2.68, -19.34), Vector3(6.1, 5.36, 4.45))
	_solid_box("EntranceBooth", Vector3(-17, 1.43, 14), Vector3(3.68, 2.86, 3.68))
	for x: float in [6.0, 10.0, 14.0, 18.0]:
		_solid_box("TruckChassis_" + str(int(x)), Vector3(x, 0.77, -12.5), Vector3(2.35, 1.54, 6.16))
		_solid_box("TruckCab_" + str(int(x)), Vector3(x, 2.16, -10.61), Vector3(2.17, 1.34, 2.08), false)
		_solid_box("TruckHydraulicBase_" + str(int(x)), Vector3(x, 1.82, -13.0), Vector3(1.52, 0.82, 1.6), false)
	_solid_box("CargoVan", Vector3(-5, 1.18, -17), Vector3(2.08, 2.36, 4.63))
	for z: float in [-7.5, -12.0]:
		_solid_box("CarLowerBody_" + str(z), Vector3(-5.3, 0.67, z), Vector3(4.28, 1.24, 1.87))
		_solid_box("CarGlazedCabin_" + str(z), Vector3(-5.2, 1.39, z), Vector3(2.18, 0.60, 1.69), false)
	for z: float in [-3.0, -7.5, -12.0]:
		_solid_box("WhiteChargePod_" + str(z), Vector3(-10, 0.82, z), Vector3(1.0, 1.64, 2.13))
		_solid_box("FastPedestal_" + str(z), Vector3(-10, 1.1, z - 1.58), Vector3(0.40, 2.2, 0.48))
	_solid_box("VendingMachine", Vector3(-9.8, 1.03, 3.5), Vector3(0.81, 2.06, 1.1))
	_solid_box("Freezer", Vector3(-9.75, 0.54, 1.8), Vector3(0.74, 1.08, 1.17))
	_solid_box("ElectricalCabinet", Vector3(-9.90, 0.79, 0.65), Vector3(0.61, 1.58, 0.96))
	_solid_box("ACChargerCase", Vector3(-9.7, 0.97, -0.2), Vector3(0.38, 1.94, 0.44))
	for x: float in [-11.05, -3.03]:
		for z: float in [5.1, -0.2, -5.5, -10.8, -16.1]:
			_solid_box("CanopyPost", Vector3(x, 1.95, z), Vector3(0.19, 3.9, 0.20), true, 0.32)
	_solid_box("BarrierMotor", Vector3(-7, 0.95, 17.15), Vector3(0.63, 1.75, 0.64))

func _build_walkable_stairs() -> void:
	_solid_box("OfficeFrontTerrace", Vector3(10, 2.97, 3.27), Vector3(6.60, 0.14, 1.49), false)
	_solid_box("OfficeSidePassage", Vector3(13.56, 2.97, 1.04), Vector3(1.13, 0.14, 3.0), false)
	_solid_box("ShiftedStairLanding", Vector3(14.90, 2.97, -0.20), Vector3(1.67, 0.14, 0.96), false)
	var steel: StandardMaterial3D = _material("catwalk", Color(0.19, 0.21, 0.20), 0.65)
	# Bridge the relocated landing to the original passage and widen its L turn.
	for item: Array in [[Vector3(14.08, 2.97, -0.13), Vector3(1.42, 0.14, 1.1)], [Vector3(13.48, 2.97, 2.92), Vector3(1.35, 0.14, 1.35)]]:
		_solid_box("WalkwayBridge", item[0], item[1], false)
		_box_visual("PerforatedSteelBridge", item[0], item[1], steel)
	var ramp: StaticBody3D = StaticBody3D.new()
	ramp.name = "SmoothOfficeStairRamp"
	ramp.collision_layer = 1
	ramp.collision_mask = 0
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(14.20, -0.04, 6.49), Vector3(15.60, -0.04, 6.49),
		Vector3(14.20, -0.04, 0.22), Vector3(15.60, -0.04, 0.22),
		Vector3(14.20, 0.04, 6.49), Vector3(15.60, 0.04, 6.49),
		Vector3(14.20, TERRACE_Y, 0.22), Vector3(15.60, TERRACE_Y, 0.22)
	])
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	ramp.add_child(collision)
	add_child(ramp)
	ramp.add_to_group("world_solids")
	_obstacles.append(Rect2(13.80, -0.18, 2.20, 7.07))
	# Rail colliders are narrow, never whole opaque walls in front of the view.
	_solid_box("TerraceFrontRail", Vector3(10, 3.62, 4.04), Vector3(6.7, 1.15, 0.085), false)
	_solid_box("TerraceWestRail", Vector3(6.65, 3.62, 3.27), Vector3(0.085, 1.15, 1.55), false)
	_solid_box("PassageEastRail", Vector3(14.16, 3.62, 1.50), Vector3(0.06, 1.15, 1.90), false)
	_solid_box("LandingNorthRail", Vector3(14.80, 3.62, -0.74), Vector3(1.9, 1.15, 0.06), false)
	_solid_box("LandingEastRail", Vector3(15.73, 3.62, -0.24), Vector3(0.06, 1.15, 1.06), false)
	# A thin raised stringer on each side catches feet without blocking bullets.
	for x: float in [14.14, 15.66]:
		var rail: StaticBody3D = _solid_box("StairSideStringer", Vector3(x, 1.66, 3.355), Vector3(0.07, 0.28, 6.99), false)
		rail.rotation.x = atan2(3.0, 6.27)

func _material(key: String, color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.91
	material.metallic = metallic
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = key.hash()
	noise.frequency = 0.082
	noise.fractal_octaves = 3
	var texture: NoiseTexture2D = NoiseTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.seamless = true
	texture.noise = noise
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(0.43, 0.38, 0.31), Color(0.97, 0.91, 0.78)])
	texture.color_ramp = gradient
	material.albedo_texture = texture
	material.uv1_scale = Vector3(2, 2, 2)
	_materials[key] = material
	return material

func _box_visual(label: String, center: Vector3, size: Vector3, material: Material, shadow: bool = true) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = label
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	instance.position = center
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func _build_cover() -> void:
	var concrete: StandardMaterial3D = _material("broken concrete", Color(0.54, 0.49, 0.39))
	var rust: StandardMaterial3D = _material("exposed rust", Color(0.37, 0.22, 0.13), 0.45)
	var wood: StandardMaterial3D = _material("salvage wood", Color(0.42, 0.32, 0.20))
	var paint: StandardMaterial3D = _material("faded road ochre", Color(0.66, 0.51, 0.24))
	for center: Vector3 in [Vector3(-2.8, 0, 6.0), Vector3(3.2, 0, -3.6)]:
		_solid_box("CentralLowCover", center + Vector3(0, 0.59, 0), Vector3(2.8, 1.14, 1.05))
		_box_visual("SalvagedConcreteBarrier", center + Vector3(0, 0.51, 0), Vector3(2.8, 0.96, 1.05), concrete)
		_box_visual("BarrierTopBeam", center + Vector3(0, 1.05, 0), Vector3(2.87, 0.18, 0.94), concrete)
		for x: float in [-1.17, 1.17]:
			_box_visual("SteelBarrierEndStrap", center + Vector3(x, 0.66, 0.544), Vector3(0.12, 0.89, 0.045), rust)
			_box_visual("BarrierWornWarningStripe", center + Vector3(x * 0.64, 0.76, 0.556), Vector3(0.42, 0.16, 0.019), paint, false)
		var crate_center: Vector3 = center + Vector3(-1.02, 1.32, -0.04)
		_solid_box("SalvagedCoverCrate", crate_center, Vector3(0.67, 0.38, 0.73), false)
		_box_visual("SalvagedTimberCrate", crate_center, Vector3(0.67, 0.38, 0.73), wood)
		for x: float in [-0.26, 0.26]:
			_box_visual("CrateIronBand", crate_center + Vector3(x, 0.197, 0), Vector3(0.045, 0.015, 0.75), rust)
		_covers.append(center + Vector3(0, 0.05, 1.16))
		_covers.append(center + Vector3(0, 0.05, -1.16))
	for x: float in [6.0, 10.0, 14.0, 18.0]:
		_covers.append(Vector3(x, 0.05, -8.2))
	# Main route retains a clear two-metre corridor at x=0; side route is east.
	for z: float in [16.0, 10.0, 2.0, -7.0, -18.0]:
		_box_visual("MainRouteFadedDash", Vector3(0, 0.035, z), Vector3(0.12, 0.009, 1.3), paint, false)
	for z: float in [-16.0, -11.0, -5.0, 1.0, 7.0]:
		_box_visual("TruckSideRouteMark", Vector3(21.1, 0.035, z), Vector3(0.16, 0.009, 0.95), paint, false)

func _build_perimeter() -> void:
	var rust: StandardMaterial3D = _material("perimeter steel", Color(0.31, 0.26, 0.20), 0.38)
	var concrete: StandardMaterial3D = _material("perimeter concrete", Color(0.40, 0.36, 0.29))
	var soil: StandardMaterial3D = _material("dust horizon", Color(0.38, 0.31, 0.22))
	_box_visual("DustGroundExtension", Vector3(0, -0.28, -3), Vector3(440, 0.08, 440), soil, false)
	for side: float in [-1.0, 1.0]:
		for i: int in range(13):
			var z: float = -25.0 + i * 4.0
			_box_visual("BoundaryConcreteFoot", Vector3(side * 24.4, 0.48, z), Vector3(0.35, 0.96, 3.93), concrete)
			_box_visual("WeatheredFencePanel", Vector3(side * 24.45, 1.88, z), Vector3(0.09, 1.87, 3.85), rust, false)
			_box_visual("FenceUpright", Vector3(side * 24.46, 1.62, z - 1.9), Vector3(0.15, 3.24, 0.15), rust)
		# Offsite silhouettes establish depth but never enter physics/navigation.
		for i: int in range(6):
			var center: Vector3 = Vector3(side * (31.0 + (i % 3) * 5.0), 1.2, -25.0 + i * 10.0)
			var relic: MeshInstance3D = _box_visual("DistantAbandonedIndustrialShell", center, Vector3(3.6, 2.4 + (i % 2) * 1.0, 6.0), rust, false)
			relic.rotation.y = -0.12 + i * 0.071
			relic.visibility_range_end = 105.0
	# Low southern wall leaves a visually legible exit opening around x=0.
	for x: float in [-14.0, 14.0]:
		_box_visual("SouthBoundaryRemnants", Vector3(x, 0.72, 24.6), Vector3(20, 1.44, 0.40), concrete)

func _build_lighting() -> void:
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.19, 0.25, 0.29)
	sky_material.sky_horizon_color = Color(0.49, 0.48, 0.43)
	sky_material.ground_bottom_color = Color(0.22, 0.20, 0.16)
	sky_material.ground_horizon_color = Color(0.43, 0.41, 0.36)
	sky_material.sun_angle_max = 13.0
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.65, 0.71, 0.76)
	_environment.ambient_light_energy = 0.48
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_exposure = 0.90
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.49, 0.49, 0.45)
	_environment.fog_light_energy = 0.7
	_environment.fog_density = 0.004
	_environment.fog_sky_affect = 0.35
	_environment.fog_height = 0.0
	_environment.fog_height_density = 0.055
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "DustEveningEnvironment"
	world_environment.environment = _environment
	add_child(world_environment)
	_sun = DirectionalLight3D.new()
	_sun.name = "WarmEveningSun"
	_sun.rotation_degrees = Vector3(-32, -34, 0)
	_sun.light_color = Color(1.0, 0.88, 0.71)
	_sun.light_energy = 0.82
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 58.0
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.0
	add_child(_sun)

func _build_power_lights() -> void:
	for z: float in [-3.0, -7.5, -12.0]:
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "ChargingPowerPool"
		light.position = Vector3(-8.85, 2.13, z)
		light.light_color = Color(0.16, 0.92, 0.71)
		light.light_energy = 1.65
		light.omni_range = 5.0
		light.omni_attenuation = 1.7
		light.shadow_enabled = false
		add_child(light)
		_power_lights.append(light)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.045, 0.25, 0.21)
		material.emission_enabled = true
		material.emission = Color(0.10, 0.94, 0.70)
		material.emission_energy_multiplier = 0.0
		_power_materials.append(material)
		_box_visual("ChargingPowerIndicator", Vector3(-9.47, 1.25, z), Vector3(0.035, 0.07, 0.80), material, false)
	_alarm_light = OmniLight3D.new()
	_alarm_light.name = "ResetWarningBeacon"
	_alarm_light.position = Vector3(-9.2, 1.90, 0.63)
	_alarm_light.light_color = Color(1.0, 0.49, 0.06)
	_alarm_light.omni_range = 4.5
	_alarm_light.shadow_enabled = false
	add_child(_alarm_light)
	_alarm_material = StandardMaterial3D.new()
	_alarm_material.albedo_color = Color(0.50, 0.24, 0.03)
	_alarm_material.emission_enabled = true
	_alarm_material.emission = Color(1.0, 0.38, 0.025)
	_box_visual("ResetAmberBeacon", Vector3(-9.87, 1.72, 0.63), Vector3(0.20, 0.17, 0.20), _alarm_material, false)

func set_power(on: bool, alarm: bool = false) -> void:
	_power = on
	_alarm = alarm
	for light: OmniLight3D in _power_lights:
		light.visible = on
		light.light_energy = 1.25 if _low_quality else 1.65
	for material: StandardMaterial3D in _power_materials:
		material.emission_energy_multiplier = 2.2 if on else 0.0
		material.albedo_color = Color(0.12, 0.64, 0.48) if on else Color(0.045, 0.18, 0.15)
	for material: BaseMaterial3D in _source_power_materials:
		material.emission_energy_multiplier = 1.25 if on else 0.0
	if is_instance_valid(_alarm_light):
		_alarm_light.visible = alarm
		_alarm_light.light_energy = 2.1 if alarm else 0.0
	if _alarm_material != null:
		_alarm_material.emission_energy_multiplier = 2.0 if alarm else 0.0
	set_process(alarm)

func _process(delta: float) -> void:
	_time += delta
	if _alarm:
		var pulse: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * TAU * 1.25))
		_alarm_light.light_energy = pulse * 2.2
		_alarm_material.emission_energy_multiplier = pulse * 2.5

func set_quality(low: bool) -> void:
	_low_quality = low
	if is_instance_valid(_sun):
		_sun.shadow_enabled = not low
		_sun.directional_shadow_max_distance = 36.0 if low else 58.0
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	for instance: MeshInstance3D in _render_meshes:
		instance.visibility_range_end = 90.0 if low else 155.0
	set_power(_power, _alarm)

func _build_navigation() -> void:
	_grid.region = Rect2i(Vector2i.ZERO, NAV_SIZE)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = NAV_MIN
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	for x: int in range(NAV_SIZE.x):
		for z: int in range(NAV_SIZE.y):
			var point: Vector2 = NAV_MIN + Vector2(x, z) * CELL
			if not is_walkable(Vector3(point.x, 0.05, point.y)):
				_grid.set_point_solid(Vector2i(x, z))

func is_walkable(point: Vector3) -> bool:
	if point.x < -23.55 or point.x > 23.55 or point.z < -27.55 or point.z > 23.65:
		return false
	var flat: Vector2 = Vector2(point.x, point.z)
	for obstacle: Rect2 in _obstacles:
		if obstacle.has_point(flat):
			return false
	return true

func _nearest_open(point: Vector3) -> Vector2i:
	var cell: Vector2i = Vector2i(roundi((point.x - NAV_MIN.x) / CELL), roundi((point.z - NAV_MIN.y) / CELL))
	cell.x = clampi(cell.x, 0, NAV_SIZE.x - 1)
	cell.y = clampi(cell.y, 0, NAV_SIZE.y - 1)
	if not _grid.is_point_solid(cell):
		return cell
	for radius: int in range(1, 12):
		var best: Vector2i = Vector2i(-1, -1)
		var best_distance: float = INF
		for dx: int in range(-radius, radius + 1):
			for dz: int in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dz) != radius:
					continue
				var candidate: Vector2i = cell + Vector2i(dx, dz)
				if not _grid.region.has_point(candidate) or _grid.is_point_solid(candidate):
					continue
				var distance: float = Vector2(candidate - cell).length_squared()
				if distance < best_distance:
					best_distance = distance
					best = candidate
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if not _built:
		return result
	var start: Vector2i = _nearest_open(from)
	var finish: Vector2i = _nearest_open(to)
	if start.x < 0 or finish.x < 0:
		return result
	var path: PackedVector2Array = _grid.get_point_path(start, finish)
	if path.is_empty():
		return result
	for point: Vector2 in path:
		result.append(Vector3(point.x, 0.05, point.y))
	# Return the exact interactive location when its final short segment is clear.
	if is_walkable(to) and _segment_walkable(result[-1], to):
		result.append(Vector3(to.x, 0.05, to.z))
	return result

func _segment_walkable(a: Vector3, b: Vector3) -> bool:
	var steps: int = maxi(2, ceili(a.distance_to(b) / 0.10))
	for index: int in range(steps + 1):
		if not is_walkable(a.lerp(b, float(index) / float(steps))):
			return false
	return true

func get_cover_points() -> Array[Vector3]:
	return _covers.duplicate()
