extends Node3D
## Meter-scale industrial hangar. Static geometry is merged by material.
## The bay-local front is -Z. Its center lane is reserved for the elevator.

var _materials: Dictionary = {}
var _surfaces: Dictionary = {}
var _frame := Transform3D.IDENTITY
var _font: Font
var _collision_root: StaticBody3D
var geometry_stats: Dictionary = {}

func build(catalog: Array) -> void:
	name = "HangarWorld"
	_make_materials()
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		_font = load("res://assets/fonts/NotoSansSC.ttf")
	_collision_root = StaticBody3D.new()
	_collision_root.name = "ArchitectureCollision"
	add_child(_collision_root)
	_lighting()
	_architecture()
	_crane()
	for info in catalog:
		_frame = Transform3D(Basis(Vector3.UP, float(info.yaw)), info.position)
		_berth(info)
		_machine(info)
	for info in preload("res://scripts/catalog.gd").exhibits():
		_frame = Transform3D(Basis(Vector3.UP, float(info.yaw)), info.position)
		_exhibit(info)
	_frame = Transform3D.IDENTITY
	_entry()
	_finish_geometry()

func _make_materials() -> void:
	_material("floor", Color("28333c"), 0.90, 0.20)
	_material("pad", Color("34414a"), 0.82, 0.30)
	_material("steel", Color("344758"), 0.60, 0.65)
	_material("dark", Color("17232e"), 0.68, 0.50)
	_material("ceiling", Color("17232e"), 0.85, 0.20)
	_material("wall", Color("35444d"), 0.86, 0.25)
	_material("panel", Color("60727b"), 0.78, 0.40)
	_material("silver", Color("9aabb3"), 0.42, 0.80)
	_material("rubber", Color("101a20"), 0.95, 0.10)
	_material("amber", Color("d99528"), 0.64, 0.30)
	_material("paint", Color("c4c7b2"), 0.85, 0.0)
	_material("red", Color("a94638"), 0.65, 0.20)
	_material("suit", Color("dc7831"), 0.93, 0.0)
	_material("helmet", Color("ede0b0"), 0.72, 0.0)
	_material("skin", Color("a78872"), 0.90, 0.0)
	_material("cyan", Color("53d5e4"), 0.35, 0.15, 2.0)
	_material("lamp", Color("cedee7"), 0.35, 0.10, 3.0)
	_material("warm_lamp", Color("ffcd70"), 0.30, 0.10, 2.0)
	_material("red_lamp", Color("ff5234"), 0.35, 0.10, 1.7)

func _material(key: String, color: Color, rough: float, metal: float, emission: float = 0.0) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.metallic = metal
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	_materials[key] = material
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	_surfaces[key] = surface

func _part(mesh: Mesh, pos: Vector3, key: String, rotation: Basis = Basis.IDENTITY) -> void:
	var surface: SurfaceTool = _surfaces[key]
	surface.append_from(mesh, 0, _frame * Transform3D(rotation, pos))

func _box(size: Vector3, pos: Vector3, key: String, rotation: Basis = Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_part(mesh, pos, key, rotation)

func _cylinder(radius: float, length: float, pos: Vector3, key: String, rotation: Basis = Basis.IDENTITY, top: float = -1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top < 0.0 else top
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1
	_part(mesh, pos, key, rotation)

func _beam(a: Vector3, b: Vector3, width: float, key: String, depth: float = -1.0) -> void:
	var direction := b - a
	var up := direction.normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var basis := Basis(side, up, side.cross(up).normalized())
	_box(Vector3(width, direction.length(), width if depth < 0.0 else depth), (a + b) * 0.5, key, basis)

func _solid(size: Vector3, pos: Vector3, label: String = "Blocker") -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.name = label
	collider.shape = shape
	collider.transform = _frame * Transform3D(Basis.IDENTITY, pos)
	_collision_root.add_child(collider)

func _label(text: String, pos: Vector3, size: int, pixel: float, color: Color, yaw: float = 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_modulate = Color("101b24")
	label.outline_size = 5
	label.no_depth_test = false
	label.shaded = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _font != null:
		label.font = _font
	label.transform = _frame * Transform3D(Basis(Vector3.UP, yaw), pos)
	add_child(label)

func _lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("2a3b4d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6c5cc")
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("71879a")
	environment.fog_light_energy = 0.45
	environment.fog_density = 0.0017
	var world_environment := WorldEnvironment.new()
	world_environment.name = "ColdSteelAtmosphere"
	world_environment.environment = environment
	add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.name = "CeilingKey"
	key.rotation_degrees = Vector3(-63, -24, 0)
	key.light_color = Color("d4e6ff")
	key.light_energy = 1.35
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 105.0
	key.shadow_bias = 0.08
	key.shadow_normal_bias = 1.6
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(key)
	for z in [-30.0, 0.0, 30.0]:
		for x in [-20.0, 20.0]:
			var light := OmniLight3D.new()
			light.name = "BerthWorkLight"
			light.position = Vector3(x, 16.0, z - 5.0)
			light.light_color = Color("ffd899")
			light.light_energy = 2.6
			light.omni_range = 27.0
			light.omni_attenuation = 1.3
			light.shadow_enabled = false
			add_child(light)

func _architecture() -> void:
	_box(Vector3(84, 0.6, 110), Vector3(0, -0.30, 0), "floor")
	_solid(Vector3(84, 0.6, 110), Vector3(0, -0.30, 0), "Floor")
	_box(Vector3(84, 0.65, 110), Vector3(0, 34.32, 0), "ceiling")
	_solid(Vector3(84, 0.65, 110), Vector3(0, 34.32, 0), "Roof")
	for x in [-42.4, 42.4]:
		_box(Vector3(0.8, 34, 110), Vector3(x, 17, 0), "wall")
		_solid(Vector3(0.8, 34, 111), Vector3(x, 17, 0), "SideWall")
	for z in [-55.4, 55.4]:
		_box(Vector3(84, 34, 0.8), Vector3(0, 17, z), "wall")
		_solid(Vector3(85, 34, 0.8), Vector3(0, 17, z), "EndWall")
	# Slab seams and vehicle lanes give the eye familiar scale at ground level.
	for z in range(-50, 55, 5):
		_box(Vector3(83.8, 0.012, 0.025), Vector3(0, 0.008, z), "dark")
	for x in range(-40, 45, 5):
		_box(Vector3(0.025, 0.012, 109.8), Vector3(x, 0.009, 0), "dark")
	for x in [-8.4, 8.4]:
		_box(Vector3(0.14, 0.018, 99), Vector3(x, 0.018, 0), "amber")
		_box(Vector3(0.06, 0.018, 99), Vector3(x + signf(x) * 0.35, 0.018, 0), "paint")
	for z in range(-47, 46, 6):
		_box(Vector3(0.12, 0.018, 2.8), Vector3(0, 0.018, z), "paint")
		for x in [-7.5, 7.5]:
			_box(Vector3(0.06, 0.035, 0.9), Vector3(x, 0.025, z), "cyan")
	# Seven transverse structural frames, with real depth and diagonal webs.
	for z in [-49.0, -33.0, -17.0, -1.0, 15.0, 31.0, 47.0]:
		for x in [-39.5, 39.5]:
			_box(Vector3(1.25, 33.6, 1.25), Vector3(x, 16.8, z), "steel")
			_box(Vector3(1.7, 0.4, 1.7), Vector3(x, 0.2, z), "dark")
			_solid(Vector3(1.3, 33.6, 1.3), Vector3(x, 16.8, z), "Column")
			_box(Vector3(1.3, 1.6, 1.3), Vector3(x, 1.3, z), "amber")
			for height in [8.0, 19.0, 27.0]:
				_beam(Vector3(x, height - 3, z), Vector3(x - signf(x) * 3, height, z), 0.32, "steel")
		_box(Vector3(79, 0.45, 0.65), Vector3(0, 30.2, z), "steel")
		_box(Vector3(79, 0.45, 0.65), Vector3(0, 33.3, z), "steel")
		for x in range(-39, 39, 6):
			_beam(Vector3(x, 30.2, z), Vector3(x + 3, 33.3, z), 0.22, "steel")
			_beam(Vector3(x + 3, 33.3, z), Vector3(x + 6, 30.2, z), 0.22, "steel")
		for x in [-28.0, -11.0, 11.0, 28.0]:
			_box(Vector3(6.0, 0.22, 0.85), Vector3(x, 29.6, z), "dark")
			_box(Vector3(5.5, 0.08, 0.56), Vector3(x, 29.43, z), "lamp")
	for x in [-33.0, -17.0, 0.0, 17.0, 33.0]:
		_box(Vector3(0.32, 0.4, 108), Vector3(x, 32.2, 0), "steel")
	# Long side galleries and bundled utility mains.
	for side in [-1.0, 1.0]:
		var x: float = side * 37.5
		_box(Vector3(4.6, 0.32, 102), Vector3(x, 8.1, 0), "dark")
		_box(Vector3(0.12, 0.12, 102), Vector3(x - side * 2.25, 9.3, 0), "amber")
		_box(Vector3(0.10, 0.10, 102), Vector3(x - side * 2.25, 8.75, 0), "steel")
		for z in range(-50, 51, 4):
			_box(Vector3(0.09, 1.1, 0.09), Vector3(x - side * 2.25, 8.75, z), "steel")
		for y in [12.0, 13.0, 14.0]:
			_cylinder(0.23, 108, Vector3(side * 40.8, y, 0), "silver", Basis(Vector3.RIGHT, PI * 0.5))
		for z in [-40.0, -10.0, 20.0, 45.0]:
			_box(Vector3(0.5, 5, 2.8), Vector3(side * 41.7, 21, z), "dark")
			for offset in range(-4, 5):
				_box(Vector3(0.6, 0.13, 2.55), Vector3(side * 41.3, 21 + offset * 0.45, z), "silver")
			_box(Vector3(0.28, 2.1, 1.15), Vector3(side * 41.9, 1.05, z), "dark")
			_box(Vector3(0.30, 0.12, 1.3), Vector3(side * 41.7, 2.27, z), "cyan")
			_label("人员通道\nPERSONNEL", Vector3(side * 41.68, 2.9, z), 30, 0.008, Color("c5e4e9"), -side * PI * 0.5)
	# Northern blast door: folded steel, structural braces and oversized typography.
	_box(Vector3(25, 28, 0.55), Vector3(0, 14, -54.8), "dark")
	for x in [-9.0, -3.0, 3.0, 9.0]:
		_box(Vector3(5.7, 26, 0.4), Vector3(x, 13, -54.4), "panel")
		for y in [4.0, 11.0, 18.0, 25.0]:
			_box(Vector3(5.5, 0.23, 0.18), Vector3(x, y, -54.1), "steel")
	_beam(Vector3(-12, 1, -54), Vector3(-1, 26, -54), 0.40, "steel")
	_beam(Vector3(12, 1, -54), Vector3(1, 26, -54), 0.40, "steel")
	_box(Vector3(28, 1.4, 1.3), Vector3(0, 28.6, -54.3), "amber")
	_label("07  /  MOBILE SUIT HANGAR", Vector3(0, 30.8, -54.6), 70, 0.030, Color("dce7e7"))
	_label("巨 构 机 库", Vector3(0, 20.5, -53.9), 90, 0.037, Color("d2dadc"))
	_label("出 击 闸 门  ·  整 备 期 间 封 闭", Vector3(0, 3.8, -53.95), 50, 0.023, Color("f1c06b"))
	for x in [-13.2, 13.2]:
		_box(Vector3(0.13, 23, 0.18), Vector3(x, 13.0, -53.65), "warm_lamp")
		_box(Vector3(0.32, 0.45, 0.25), Vector3(x, 3.4, -53.5), "red_lamp")
	# End-wall plant rooms break the large flat wall into functional volumes.
	for side in [-1.0, 1.0]:
		var x: float = side * 28.0
		_box(Vector3(18, 7, 0.65), Vector3(x, 20, -54.65), "dark")
		for offset in range(-6, 7):
			_box(Vector3(16.5, 0.17, 0.35), Vector3(x, 20 + offset * 0.44, -54.1), "panel")
		_box(Vector3(18, 0.3, 0.8), Vector3(x, 15.8, -54.35), "steel")
		_box(Vector3(18, 0.08, 0.10), Vector3(x, 15.55, -53.9), "cyan")
		for dx in [-7.0, 7.0]:
			_box(Vector3(0.45, 31, 0.9), Vector3(x + dx, 15.5, -54.4), "steel")
		_cylinder(0.65, 17, Vector3(x, 27, -53.9), "steel", Basis(Vector3.FORWARD, PI * 0.5))
		for dx in [-5.0, 0.0, 5.0]:
			_box(Vector3(0.24, 1.65, 1.6), Vector3(x + dx, 27, -53.9), "silver")
		_label("A" if side < 0 else "B", Vector3(x, 11, -53.85), 120, 0.045, Color("9bb3c2"))
		_label("MECHANICAL SERVICES\nAUTHORIZED PERSONNEL", Vector3(x, 6.6, -53.8), 36, 0.018, Color("bdced5"))

func _crane() -> void:
	# Elevated travelling bridge, independent of the human access bridges.
	for x in [-36.0, 36.0]:
		_box(Vector3(0.7, 0.7, 103), Vector3(x, 27.4, 0), "steel")
	for z in [-13.8, -10.2]:
		_box(Vector3(74, 1.6, 0.8), Vector3(0, 28.2, z), "amber")
		_box(Vector3(74, 0.18, 1.1), Vector3(0, 29.05, z), "dark")
		for x in range(-34, 35, 4):
			_box(Vector3(1.3, 1.62, 0.025), Vector3(x, 28.2, z + 0.42), "dark", Basis(Vector3.FORWARD, -0.32))
	for x in [-35.0, -20.0, -5.0, 10.0, 25.0, 35.0]:
		_box(Vector3(0.45, 0.4, 4.5), Vector3(x, 29.0, -12), "steel")
	_box(Vector3(6, 1.5, 5.5), Vector3(4, 28.5, -12), "steel")
	_box(Vector3(3.0, 1.2, 2), Vector3(4, 27.5, -12), "amber")
	for x in [3.25, 4.75]:
		_cylinder(0.035, 5, Vector3(x, 24.6, -12), "dark")
	_box(Vector3(2.1, 0.6, 0.9), Vector3(4, 22.0, -12), "amber")
	_beam(Vector3(4, 21.8, -12), Vector3(4, 20.9, -12), 0.20, "silver")
	_beam(Vector3(4, 20.9, -12), Vector3(4.45, 20.7, -12), 0.20, "silver")
	_beam(Vector3(4.45, 20.7, -12), Vector3(4.65, 21.1, -12), 0.20, "silver")
	_label("OVERHEAD SERVICE  /  120 t", Vector3(-14, 28.25, -9.72), 46, 0.025, Color("17232e"))

func _berth(info: Dictionary) -> void:
	var h: float = float(info.height)
	var service_offset_z := float(info.get("rear_service_offset_z", 0.0))
	_box(Vector3(22, 0.028, 21), Vector3(0, 0.018, 0.8), "pad")
	for x in [-10.5, 10.5]:
		_box(Vector3(0.13, 0.018, 21), Vector3(x, 0.041, 0.8), "amber")
	for z in [-9.7, 11.3]:
		_box(Vector3(21, 0.018, 0.13), Vector3(0, 0.041, z), "amber")
	for side in [-1.0, 1.0]:
		# Back service mast, outside all feet and access walkways.
		_box(Vector3(0.7, h * 0.82, 0.8), Vector3(side * 7.8, h * 0.41, 7.0 + service_offset_z), "steel")
		_box(Vector3(1.7, 0.3, 1.7), Vector3(side * 7.8, 0.15, 7.0 + service_offset_z), "dark")
		_solid(Vector3(0.8, h * 0.82, 0.9), Vector3(side * 7.8, h * 0.41, 7.0 + service_offset_z), "ServiceMast")
		for height in [h * 0.34, h * 0.65]:
			_box(Vector3(2.4, 0.24, 2.8), Vector3(side * 7.0, height, 6.6 + service_offset_z), "dark")
			_box(Vector3(0.10, 0.10, 2.8), Vector3(side * 8.0, height + 1.1, 6.6 + service_offset_z), "amber")
			_beam(Vector3(side * 7.8, height - 2, 7.0 + service_offset_z), Vector3(side * 5.8, height, 7.0 + service_offset_z), 0.25, "steel")
		_box(Vector3(0.07, h * 0.75, 0.08), Vector3(side * 7.8, h * 0.44, 6.55 + service_offset_z), "cyan")
		# Ladder has human-scale rung spacing, and stays behind the machine.
		for dx in [-0.26, 0.26]:
			_box(Vector3(0.065, h * 0.68, 0.07), Vector3(side * 7.8 + dx, h * 0.34, 6.48 + service_offset_z), "silver")
		for y in range(1, int(h * 0.68 / 0.32)):
			_box(Vector3(0.60, 0.045, 0.045), Vector3(side * 7.8, float(y) * 0.32, 6.43 + service_offset_z), "silver")
		_tool_cabinet(Vector3(side * 6.5, 0, 3.5))
		for offset in range(8):
			_box(Vector3(1.0, 0.020, 0.22), Vector3(side * 9, 0.045, -8 + offset * 0.55), "amber", Basis(Vector3.UP, side * 0.55))
	_cart(Vector3(-5.8, 0, -3.9))
	_person(Vector3(float(info.get("service_person_x", -3.8)), 0, -1.2), 0.25)
	_person(Vector3(6.0, 0, 2.0), -0.65)
	# Bright, readable berth header at a structural height, not across the cockpit.
	_box(Vector3(13, 1.65, 0.26), Vector3(0, h + 2.2, 7.2 + service_offset_z), "dark")
	_box(Vector3(12.8, 0.06, 0.08), Vector3(0, h + 1.38, 6.99 + service_offset_z), "warm_lamp")
	_label(str(info.bay) + "  /  " + str(info.model), Vector3(0, h + 2.2, 7.02 + service_offset_z), 50, 0.027, Color("d6e5e9"), PI)
	# Human-scale front information board faces the central aisle.
	_box(Vector3(2.6, 1.40, 0.18), Vector3(4.2, 1.9, -8.0), "dark")
	_box(Vector3(2.55, 0.06, 0.2), Vector3(4.2, 2.64, -8.0), "warm_lamp")
	for x in [3.2, 5.2]:
		_box(Vector3(0.10, 1.2, 0.1), Vector3(x, 0.6, -8.0), "steel")
	_solid(Vector3(2.6, 2.6, 0.20), Vector3(4.2, 1.3, -8.0), "InformationBoard")
	_label(str(info.bay) + "  " + str(info.name) + "\n" + str(info.model) + "\n整备高度 %.1f m  ·  乘梯登舱" % h, Vector3(4.2, 1.93, -8.11), 34, 0.0030, Color("e0e9e8"), PI)
	for z in [-7.0, -5.0, -3.0]:
		for x in [-2.2, 2.2]:
			_box(Vector3(0.04, 0.025, 0.65), Vector3(x, 0.045, z), "cyan")
	# Work fixtures visibly belong to the servicing infrastructure.
	var work_fixture_z := float(info.get("work_fixture_z", 4.5))
	for x in [-6.0, 6.0]:
		_box(Vector3(0.18, 6.0, 0.18), Vector3(x, 3.0, work_fixture_z), "steel")
		_box(Vector3(1.4, 0.22, 0.65), Vector3(x, 6.0, work_fixture_z), "dark")
		_box(Vector3(1.15, 0.10, 0.08), Vector3(x, 5.93, work_fixture_z - 0.37), "warm_lamp")

func _tool_cabinet(pos: Vector3) -> void:
	_box(Vector3(1.1, 1.8, 0.65), pos + Vector3(0, 0.9, 0), "red")
	_box(Vector3(1.13, 0.07, 0.69), pos + Vector3(0, 1.82, 0), "silver")
	for height in [0.3, 0.65, 1.0, 1.35, 1.65]:
		_box(Vector3(1.0, 0.024, 0.025), pos + Vector3(0, height, -0.34), "dark")
		_box(Vector3(0.3, 0.045, 0.045), pos + Vector3(0, height - 0.09, -0.35), "silver")
	_solid(Vector3(1.1, 1.8, 0.65), pos + Vector3(0, 0.9, 0), "ToolCabinet")

func _cart(pos: Vector3) -> void:
	_box(Vector3(1.65, 0.33, 2.3), pos + Vector3(0, 0.4, 0), "amber")
	_box(Vector3(1.25, 0.4, 0.95), pos + Vector3(0, 0.74, 0.45), "steel")
	_box(Vector3(0.75, 0.1, 0.55), pos + Vector3(0, 0.95, -0.6), "rubber")
	_box(Vector3(0.75, 0.65, 0.10), pos + Vector3(0, 1.20, -0.9), "rubber")
	for x in [-0.83, 0.83]:
		for z in [-0.75, 0.75]:
			_cylinder(0.25, 0.18, pos + Vector3(x, 0.26, z), "rubber", Basis(Vector3.FORWARD, PI * 0.5))
	for x in [-0.6, 0.6]:
		_box(Vector3(0.2, 0.11, 0.05), pos + Vector3(x, 0.50, -1.18), "lamp")
	_solid(Vector3(1.8, 1.4, 2.4), pos + Vector3(0, 0.7, 0), "MaintenanceCart")

func _person(pos: Vector3, yaw: float) -> void:
	var saved := _frame
	_frame = _frame * Transform3D(Basis(Vector3.UP, yaw), pos)
	# Boots, trouser legs, torso, articulated arms, head and helmet: 1.75 m.
	for side in [-1.0, 1.0]:
		_box(Vector3(0.18, 0.13, 0.31), Vector3(side * 0.12, 0.065, -0.055), "rubber")
		_box(Vector3(0.18, 0.67, 0.20), Vector3(side * 0.12, 0.46, 0), "steel")
		_beam(Vector3(side * 0.25, 1.34, 0), Vector3(side * 0.32, 1.03, -0.06), 0.15, "suit")
		_beam(Vector3(side * 0.32, 1.03, -0.06), Vector3(side * 0.24, 0.91, -0.17), 0.13, "suit")
		_box(Vector3(0.115, 0.14, 0.13), Vector3(side * 0.24, 0.89, -0.18), "rubber")
	_box(Vector3(0.43, 0.57, 0.25), Vector3(0, 1.10, 0), "suit")
	_box(Vector3(0.45, 0.055, 0.26), Vector3(0, 1.05, 0), "paint")
	_box(Vector3(0.045, 0.45, 0.015), Vector3(-0.12, 1.15, -0.132), "paint")
	_box(Vector3(0.045, 0.45, 0.015), Vector3(0.12, 1.15, -0.132), "paint")
	_cylinder(0.11, 0.11, Vector3(0, 1.43, 0), "skin")
	_cylinder(0.125, 0.22, Vector3(0, 1.56, 0), "skin")
	_cylinder(0.15, 0.105, Vector3(0, 1.6975, 0), "helmet", Basis.IDENTITY, 0.095)
	_cylinder(0.17, 0.025, Vector3(0, 1.65, -0.012), "helmet")
	_box(Vector3(0.18, 0.07, 0.03), Vector3(0, 1.58, -0.125), "dark")
	_solid(Vector3(0.55, 1.75, 0.40), Vector3(0, 0.875, 0), "Technician")
	_frame = saved

func _machine(info: Dictionary) -> void:
	var path: String = str(info.get("model_path", "res://assets/models/" + str(info.id) + ".glb"))
	if ResourceLoader.exists(path):
		var packed: PackedScene = load(path)
		var machine: Node3D = packed.instantiate()
		machine.name = str(info.id)
		machine.transform = _frame
		add_child(machine)
		if bool(info.get("refined", false)):
			var hatch := machine.find_child("CockpitHatch", true, false)
			for mesh: MeshInstance3D in machine.find_children("*", "MeshInstance3D", true, false):
				if mesh != hatch and (hatch == null or not hatch.is_ancestor_of(mesh)):
					mesh.create_trimesh_collision()
			return
	else:
		push_warning("Hangar model missing: " + path)
	# Conservative separate feet/legs, with an open central approach and chest.
	var h: float = float(info.height)
	for side in [-1.0, 1.0]:
		_solid(Vector3(h * 0.085, h * 0.055, h * 0.145), Vector3(side * h * 0.080, h * 0.0275, -h * 0.025), "MachineFoot_" + str(info.id))
		_solid(Vector3(h * 0.077, h * 0.35, h * 0.083), Vector3(side * h * 0.080, h * 0.23, 0), "MachineLeg_" + str(info.id))
	_solid(Vector3(h * 0.23, h * 0.13, h * 0.11), Vector3(0, h * 0.46, 0), "MachineWaist_" + str(info.id))
	# Only rear/side chest volumes: the playable cockpit remains hollow.
	_solid(Vector3(h * 0.28, h * 0.19, 0.45), Vector3(0, h * 0.63, h * 0.07), "MachineBack_" + str(info.id))
	for side in [-1.0, 1.0]:
		_solid(Vector3(0.40, h * 0.18, h * 0.12), Vector3(side * h * 0.14, h * 0.63, 0), "MachineChestSide_" + str(info.id))

func _exhibit(info: Dictionary) -> void:
	if not ResourceLoader.exists(info.model_path):
		return
	var model: Node3D = (load(info.model_path) as PackedScene).instantiate()
	model.name = info.id
	model.transform = _frame
	add_child(model)
	# Static exhibit collisions follow the authored feet, armor and weapon geometry.
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.create_trimesh_collision()
	_box(Vector3(14.0, 0.025, 18.0), Vector3(0, 0.0125, 1.0), "pad")
	for x in [-7.0, 7.0]:
		_box(Vector3(0.1, 0.015, 18.0), Vector3(x, 0.035, 1.0), "amber")
	_person(Vector3(-4.5, 0, -4.0), 0.4)
	_box(Vector3(2.8, 1.5, 0.15), Vector3(4.0, 1.8, -6.0), "dark")
	_solid(Vector3(2.8, 2.6, 0.18), Vector3(4.0, 1.3, -6.0), "ExhibitBoard")
	_label("沙漠扎古 / DESERT CUSTOM\n展示头高 17.5 m\n观摩展位 · 驾驶舱整备中", Vector3(4.0, 1.85, -6.09), 32, 0.003, Color("e0e9e8"), PI)

func _entry() -> void:
	# Low entry furniture frames the initial view but never blocks the center.
	for x in [-5.7, 5.7]:
		_box(Vector3(0.24, 1.0, 0.24), Vector3(x, 0.5, 44.5), "amber")
		_box(Vector3(0.28, 0.09, 0.28), Vector3(x, 1.05, 44.5), "cyan")
		_solid(Vector3(0.3, 1.1, 0.3), Vector3(x, 0.55, 44.5), "EntryBollard")
	_box(Vector3(4.5, 0.75, 1.4), Vector3(-11, 0.375, 47), "steel")
	_box(Vector3(4.65, 0.08, 1.5), Vector3(-11, 0.79, 47), "silver")
	_solid(Vector3(4.7, 0.86, 1.6), Vector3(-11, 0.43, 47), "ReceptionDesk")
	for x in [-12.2, -10.3]:
		_box(Vector3(0.65, 0.42, 0.10), Vector3(x, 1.15, 47), "dark")
		_box(Vector3(0.55, 0.32, 0.012), Vector3(x, 1.15, 47.06), "cyan")
	_person(Vector3(-11, 0, 48), PI)
	_label("驾驶员整备区  /  PILOT ACCESS", Vector3(0, 4.3, 54.9), 56, 0.018, Color("d7e8ec"), PI)
	_label("01 → 06   巡检通道", Vector3(0, 0.04, 42), 40, 0.005, Color("9aadaf"))
	(get_child(get_child_count() - 1) as Label3D).rotation.x = -PI * 0.5
	# Closed 2.1m personnel entrance gives a direct height reference.
	_box(Vector3(1.25, 2.1, 0.12), Vector3(0, 1.05, 54.86), "dark")
	_box(Vector3(1.45, 0.10, 0.18), Vector3(0, 2.25, 54.8), "cyan")
	for x in [-0.67, 0.67]:
		_box(Vector3(0.10, 2.2, 0.15), Vector3(x, 1.1, 54.8), "silver")

func _finish_geometry() -> void:
	var triangles := 0
	var batches := 0
	for key in _surfaces:
		var surface: SurfaceTool = _surfaces[key]
		var mesh: ArrayMesh = surface.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var instance := MeshInstance3D.new()
		instance.name = "Static_" + str(key)
		instance.mesh = mesh
		if key in ["ceiling", "lamp", "warm_lamp", "cyan", "red_lamp", "paint"]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		var arrays := mesh.surface_get_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size() / 3
		batches += 1
	geometry_stats = {"static_material_batches": batches, "static_triangles": triangles, "collision_shapes": _collision_root.get_child_count(), "dynamic_omnis": 6}
	set_meta("geometry_stats", geometry_stats)
	print("HANGAR_GEOMETRY ", JSON.stringify(geometry_stats))
	_surfaces.clear()
