extends Node3D
## Continuous coastal terrain. All near-road vertices use Route.sample(), so the
## visible asphalt, shoulders and simulation share exactly the same centreline.

const ROAD_HALF: float = 4.8
const SEA_LEVEL: float = -1.0
const CHUNK: float = 160.0
const LEFT_OFFSETS: Array[float] = [-4.8, -5.6, -6.3, -7.2, -8.5, -10.0, -12.0, -14.5, -18.0, -22.0, -28.0, -35.0, -43.0, -53.0, -65.0, -78.0, -92.0, -110.0, -130.0, -150.0, -175.0, -200.0, -225.0, -255.0, -290.0, -335.0, -385.0, -460.0, -540.0]
const RIGHT_OFFSETS: Array[float] = [4.8, 5.6, 6.2, 7.0, 8.0, 9.0, 10.2, 11.5, 13.0, 14.5, 16.0, 18.0, 20.0, 22.5, 25.0, 28.0, 31.5, 36.0, 42.0, 49.0, 57.0, 67.0, 79.0, 91.0, 108.0, 125.0, 148.0, 175.0, 210.0, 255.0, 315.0, 380.0, 475.0, 590.0, 720.0, 850.0]
var _route: RefCounted
var _noise: FastNoiseLite
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _terrain_material: ShaderMaterial
var _asphalt_material: ShaderMaterial
var _paint_material: StandardMaterial3D
var _guard_material: StandardMaterial3D
var _foliage_material: ShaderMaterial
var _grass_material: ShaderMaterial
var _bark_material: StandardMaterial3D
var _distant_material: ShaderMaterial
var _rock_mesh: ArrayMesh
var _bush_mesh: ArrayMesh
var _tree_leaf_mesh: ArrayMesh
var _tree_branch_mesh: ArrayMesh
var _grass_cluster_mesh: ArrayMesh
var _chunk_nodes: Array[Dictionary] = []
var _noise_texture: ImageTexture

func build(route: RefCounted) -> void:
	_route = route
	_rng.seed = 907241
	_noise = FastNoiseLite.new()
	_noise.seed = 80926
	_noise.frequency = 0.018
	_noise.fractal_octaves = 4
	_noise_texture = _create_grain()
	_create_materials()
	_build_ocean()
	_build_distant_coast()
	# Photographic panorama and sun are owned by the main environment.
	_build_prototypes()
	var start: float = -80.0
	while start < 2720.0:
		var stop: float = minf(start + CHUNK, 2720.0)
		var chunk: Node3D = Node3D.new()
		chunk.name = "Coast_%04d" % int(start + 80.0)
		add_child(chunk)
		_build_road(chunk, start, stop)
		_build_terrain(chunk, start, stop)
		_build_guardrail(chunk, start, stop)
		_build_vegetation(chunk, start, stop)
		_chunk_nodes.append({"node": chunk, "start": start, "stop": stop})
		start = stop
	_build_signs()
	_build_finish()
	update_view(0.0)

func update_view(s: float) -> void:
	# Keep the distant terrain visible; hide only completely rearward chunks.
	# A generous rear margin also supports the alternate camera and restart.
	for entry: Dictionary in _chunk_nodes:
		var chunk: Node3D = entry.node
		chunk.visible = float(entry.stop) > s - 260.0 and float(entry.start) < s + 1450.0

func _create_grain() -> ImageTexture:
	var img: Image = Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y: int in range(256):
		for x: int in range(256):
			var fx: float = float(x) / 256.0
			var fy: float = float(y) / 256.0
			var a: float = lerpf(_noise.get_noise_2d(x * 2.5, y * 2.5), _noise.get_noise_2d((x - 256) * 2.5, y * 2.5), fx)
			var b: float = lerpf(_noise.get_noise_2d(x * 2.5, (y - 256) * 2.5), _noise.get_noise_2d((x - 256) * 2.5, (y - 256) * 2.5), fx)
			var value: float = clampf(0.5 + lerpf(a, b, fy) * 0.65, 0.0, 1.0)
			img.set_pixel(x, y, Color(value, value, value))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _create_materials() -> void:
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = load("res://assets/environment/photographic_terrain.gdshader")
	for parameter: String in ["rock_diff", "rock_nor", "rock_arm", "ground_diff", "ground_nor"]:
		var files: Dictionary = {
			"rock_diff": "rock_face_diff_2k.jpg", "rock_nor": "rock_face_nor_gl_2k.jpg",
			"rock_arm": "rock_face_arm_2k.jpg", "ground_diff": "aerial_grass_rock_diff_2k.jpg",
			"ground_nor": "aerial_grass_rock_nor_gl_2k.jpg"}
		_terrain_material.set_shader_parameter(parameter, _texture(files[parameter]))
	_asphalt_material = ShaderMaterial.new()
	_asphalt_material.shader = load("res://assets/environment/photographic_asphalt.gdshader")
	_asphalt_material.set_shader_parameter("asphalt_diff", _texture("asphalt_02_diff_2k.jpg"))
	_asphalt_material.set_shader_parameter("asphalt_nor", _texture("asphalt_02_nor_gl_2k.jpg"))
	_asphalt_material.set_shader_parameter("asphalt_arm", _texture("asphalt_02_arm_2k.jpg"))
	_paint_material = _material(Color.WHITE)
	_paint_material.vertex_color_use_as_albedo = true
	_paint_material.vertex_color_is_srgb = true
	_paint_material.roughness = 0.86
	_guard_material = _material(Color(0.52, 0.55, 0.54))
	_guard_material.metallic = 0.72
	_guard_material.roughness = 0.48
	_foliage_material = _cutout_material("tree_small_02_leaves_diff_1k.jpg", "tree_small_02_leaves_alpha_1k.jpg")
	_grass_material = _cutout_material("grass_medium_01_diff_1k.jpg", "grass_medium_01_alpha_1k.jpg")
	_bark_material = _material(Color(0.72, 0.70, 0.66))
	_bark_material.albedo_texture = _texture("bark_willow_diff_1k.jpg")
	_bark_material.normal_enabled = true
	_bark_material.normal_texture = _texture("bark_willow_nor_gl_1k.jpg")
	_bark_material.normal_scale = 0.7
	_bark_material.roughness = 0.92
	_distant_material = ShaderMaterial.new()
	_distant_material.shader = load("res://assets/environment/distant_coast.gdshader")
	_distant_material.set_shader_parameter("landscape_photo", _texture("aerial_grass_rock_diff_2k.jpg"))
	_distant_material.set_shader_parameter("grain_texture", _noise_texture)

func _texture(filename: String) -> Texture2D:
	return load("res://assets/environment/" + filename) as Texture2D

func _cutout_material(diffuse: String, alpha: String) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://assets/environment/photographic_foliage.gdshader")
	material.set_shader_parameter("leaf_diff", _texture(diffuse))
	material.set_shader_parameter("leaf_alpha", _texture(alpha))
	return material

func _material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat

func _build_road(parent: Node3D, start: float, stop: float) -> void:
	var road: SurfaceTool = SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint: SurfaceTool = SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps: int = int(ceil((stop - start) / 2.0))
	for i: int in range(steps):
		var s0: float = lerpf(start, stop, float(i) / steps)
		var s1: float = lerpf(start, stop, float(i + 1) / steps)
		var f0: Dictionary = _route.sample(s0)
		var f1: Dictionary = _route.sample(s1)
		var p0: Vector3 = f0.position
		var p1: Vector3 = f1.position
		var r0: Vector3 = f0.right
		var r1: Vector3 = f1.right
		_quad(road, p0 - r0 * ROAD_HALF, p1 - r1 * ROAD_HALF, p1 + r1 * ROAD_HALF, p0 + r0 * ROAD_HALF, Color.WHITE, Vector2(0.0, s0), Vector2(0.0, s1), Vector2(1.0, s1), Vector2(1.0, s0))
		for stripe: int in range(4):
			var offset: float = [-4.35, -0.21, 0.21, 4.35][stripe]
			var width: float = 0.16 if stripe == 0 or stripe == 3 else 0.135
			var color: Color = Color(0.77, 0.80, 0.73) if stripe == 0 or stripe == 3 else Color(0.78, 0.51, 0.07)
			var up: Vector3 = Vector3.UP * 0.018
			_quad(paint, p0 + r0 * (offset - width * 0.5) + up, p1 + r1 * (offset - width * 0.5) + up, p1 + r1 * (offset + width * 0.5) + up, p0 + r0 * (offset + width * 0.5) + up, color)
	_commit_mesh(parent, road, _asphalt_material, "ContinuousAsphalt")
	_commit_mesh(parent, paint, _paint_material, "DoubleYellowAndEdges")

func _terrain_point(s: float, offset: float) -> Vector3:
	var frame: Dictionary = _route.sample(s)
	var centre: Vector3 = frame.position
	var right: Vector3 = frame.right
	var absolute: float = absf(offset)
	var alignment: float = smoothstep(38.0, 175.0, absolute)
	var direction: Vector3 = right.lerp(Vector3.RIGHT, alignment)
	var point: Vector3 = centre + direction * offset
	point.y = _terrain_height(s, offset, centre.y)
	return point

func _terrain_height(s: float, offset: float, road_height: float) -> float:
	var absolute: float = absf(offset)
	if absolute <= 5.6:
		return road_height - 0.065 - maxf(0.0, absolute - 4.8) * 0.06
	var noise_value: float = _noise.get_noise_2d(s * 0.84, offset * 1.45)
	var broad: float = 0.79 + 0.17 * sin(s * 0.014) + 0.13 * sin(s * 0.033 + 1.7)
	if offset > 0.0:
		var rise: float = absolute - 5.6
		var cliff: float = (1.0 - exp(-rise * 0.058)) * (13.0 + 6.0 * sin(s * 0.008 + 0.4))
		var mountains: float = pow(maxf(0.0, rise - 28.0), 0.67) * 0.67
		var crags: float = noise_value * minf(rise * 0.47, 16.0)
		crags += _noise.get_noise_2d(s * 3.3, offset * 2.8) * minf(rise * 0.6, 5.0)
		# Smooth erosion at several scales, plus slumped ledges close to the road.
		crags += _noise.get_noise_2d(s * 9.0, offset * 9.0) * minf(rise * 0.13, 1.35)
		crags += sin(rise * 0.61 + sin(s * 0.078) * 1.4) * minf(rise * 0.14, 1.5)
		return road_height - 0.14 + cliff * broad + mountains + crags
	var coast_distance: float = 178.0 + 28.0 * sin(s * 0.007) + 19.0 * sin(s * 0.019)
	var coast_t: float = clampf((absolute - 6.0) / coast_distance, 0.0, 1.5)
	var drop: float = pow(minf(coast_t, 1.0), 0.77)
	var terrain_y: float = lerpf(road_height - 0.18, SEA_LEVEL - 3.5, drop)
	terrain_y += noise_value * sin(minf(coast_t, 1.0) * PI) * 10.0
	if coast_t > 1.0:
		terrain_y -= (coast_t - 1.0) * 27.0
	return terrain_y

func _terrain_color(s: float, offset: float) -> Color:
	# R encodes ecological cover; G the gravel verge, independent of lighting.
	var patch: float = _noise.get_noise_2d(s * 1.3 + 335.0, offset * 3.0)
	var cover: float = smoothstep(-0.36, 0.10, patch + 0.13)
	if offset > 0.0:
		cover *= smoothstep(7.5, 17.0, offset) * 0.72 + 0.28
	else:
		cover *= 1.0 - smoothstep(95.0, 210.0, absf(offset))
	var verge: float = 1.0 - smoothstep(5.9, 7.5, absf(offset))
	return Color(cover * (1.0 - verge), verge, 0.0, 1.0)

func _build_terrain(parent: Node3D, start: float, stop: float) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps: int = int(ceil((stop - start) / 2.0))
	for offsets: Array[float] in [LEFT_OFFSETS, RIGHT_OFFSETS]:
		for i: int in range(steps + 1):
			var s: float = lerpf(start, stop, float(i) / steps)
			for offset: float in offsets:
				var point: Vector3 = _terrain_point(s, offset)
				var across: Vector3 = _terrain_point(s, offset + 0.3) - _terrain_point(s, offset - 0.3)
				var along: Vector3 = _terrain_point(s + 0.3, offset) - _terrain_point(s - 0.3, offset)
				surface.set_normal(across.cross(along).normalized())
				surface.set_color(_terrain_color(s, offset))
				surface.set_uv(Vector2(point.x, point.z) * 0.1)
				surface.add_vertex(point)
		var side_base: int = 0 if offsets == LEFT_OFFSETS else (steps + 1) * LEFT_OFFSETS.size()
		for i: int in range(steps):
			for j: int in range(offsets.size() - 1):
				var a: int = side_base + i * offsets.size() + j
				var b: int = a + offsets.size()
				if offsets == LEFT_OFFSETS:
					for index: int in [a, a + 1, b, a + 1, b + 1, b]:
						surface.add_index(index)
				else:
					for index: int in [a, b, a + 1, a + 1, b, b + 1]:
						surface.add_index(index)
	_commit_mesh(parent, surface, _terrain_material, "SandstoneHeadland", false)
	_build_surf(parent, start, stop)

func _build_surf(parent: Node3D, start: float, stop: float) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps: int = int(ceil((stop - start) / 5.0))
	for i: int in range(steps):
		var s0: float = lerpf(start, stop, float(i) / steps)
		var s1: float = lerpf(start, stop, float(i + 1) / steps)
		var p0: Vector3 = _shore_point(s0)
		var p1: Vector3 = _shore_point(s1)
		p0.y = SEA_LEVEL + 0.11
		p1.y = SEA_LEVEL + 0.11
		var color: Color = Color(0.69, 0.90, 0.82)
		_quad(st, p0, p1, p1 + Vector3.LEFT * 5.0, p0 + Vector3.LEFT * 5.0, color)
	_commit_mesh(parent, st, _paint_material, "ShoreBreak")

func _shore_point(s: float) -> Vector3:
	# Intersect the exact rendered cross-section with the sea plane.
	var land: Vector3 = _terrain_point(s, LEFT_OFFSETS[0])
	for offset: float in LEFT_OFFSETS:
		var point: Vector3 = _terrain_point(s, offset)
		if point.y <= SEA_LEVEL:
			var fraction: float = (land.y - SEA_LEVEL) / maxf(0.001, land.y - point.y)
			return land.lerp(point, fraction)
		land = point
	return land

func _build_guardrail(parent: Node3D, start: float, stop: float) -> void:
	var rail: SurfaceTool = SurfaceTool.new()
	rail.begin(Mesh.PRIMITIVE_TRIANGLES)
	var posts: Array[Transform3D] = []
	var reflectors: Array[Transform3D] = []
	var right_posts: Array[Transform3D] = []
	var right_caps: Array[Transform3D] = []
	var step: float = 4.0
	var s: float = start
	while s < stop:
		var sn: float = minf(s + step, stop)
		var f0: Dictionary = _route.sample(s)
		var f1: Dictionary = _route.sample(sn)
		var r0: Vector3 = f0.right
		var r1: Vector3 = f1.right
		var p0: Vector3 = f0.position + r0 * -5.48
		var p1: Vector3 = f1.position + r1 * -5.48
		var heights: Array[float] = [0.53, 0.60, 0.68, 0.76, 0.84]
		var depths: Array[float] = [0.0, 0.065, 0.0, 0.065, 0.0]
		for j: int in range(4):
			_quad(rail, p0 + Vector3.UP * heights[j] + r0 * depths[j], p1 + Vector3.UP * heights[j] + r1 * depths[j], p1 + Vector3.UP * heights[j + 1] + r1 * depths[j + 1], p0 + Vector3.UP * heights[j + 1] + r0 * depths[j + 1], Color.WHITE)
		s = sn
	var pole_s: float = ceil(start / 8.0) * 8.0
	while pole_s < stop:
		var frame: Dictionary = _route.sample(pole_s)
		var position: Vector3 = frame.position
		var right: Vector3 = frame.right
		var basis: Basis = Basis(right, Vector3.UP, -Vector3(frame.forward).normalized())
		posts.append(Transform3D(basis, position + right * -5.52 + Vector3.UP * 0.39))
		if int(pole_s) % 32 == 0:
			reflectors.append(Transform3D(basis, position + right * -5.39 + Vector3.UP * 0.73))
			right_posts.append(Transform3D(basis, position + right * 5.88 + Vector3.UP * 0.46))
			right_caps.append(Transform3D(basis, position + right * 5.88 + Vector3.UP * 0.77))
		pole_s += 8.0
	var rail_mat: StandardMaterial3D = _guard_material.duplicate()
	rail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_commit_mesh(parent, rail, rail_mat, "GalvanizedCoastalRail")
	_multimesh(parent, _box(Vector3(0.10, 0.92, 0.12)), posts, _guard_material, "RailPosts")
	_multimesh(parent, _box(Vector3(0.027, 0.105, 0.15)), reflectors, _material(Color(1.0, 0.75, 0.15)), "AmberRailReflectors")
	_multimesh(parent, _box(Vector3(0.15, 0.99, 0.13)), right_posts, _material(Color(0.91, 0.90, 0.77)), "WhiteDelineators")
	_multimesh(parent, _box(Vector3(0.157, 0.24, 0.137)), right_caps, _material(Color(0.095, 0.13, 0.12)), "DelineatorCaps")

func _build_vegetation(parent: Node3D, start: float, stop: float) -> void:
	var bushes: Array[Transform3D] = []
	var grasses: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	var trees: Array[Transform3D] = []
	for i: int in range(100):
		var s: float = _rng.randf_range(start, stop)
		var offset: float = _rng.randf_range(8.0, 58.0)
		if i % 3 == 0:
			offset = -_rng.randf_range(7.4, 56.0)
		var scale: float = _rng.randf_range(0.7, 1.75)
		var p: Vector3 = _terrain_point(s, offset) - Vector3.UP * 0.08
		bushes.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(scale * 1.15, scale * 0.88, scale)), p))
	for i: int in range(260):
		var s: float = _rng.randf_range(start, stop)
		var offset: float = _rng.randf_range(6.1, 20.0)
		if i % 2 == 0:
			offset = -_rng.randf_range(5.9, 18.0)
		var p: Vector3 = _terrain_point(s, offset) - Vector3.UP * 0.035
		var scale: float = _rng.randf_range(0.55, 1.4)
		grasses.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale), p))
	for i: int in range(19):
		var s: float = _rng.randf_range(start, stop)
		var offset: float = _rng.randf_range(7.8, 36.0) if i % 3 != 0 else -_rng.randf_range(8.0, 65.0)
		var scale: float = _rng.randf_range(0.4, 2.3)
		var basis: Basis = Basis.from_euler(Vector3(_rng.randf() * 0.8, _rng.randf() * TAU, _rng.randf() * 0.6)).scaled(Vector3(scale * 1.4, scale, scale * 1.15))
		var right: Vector3 = _route.sample(s).right
		var radius: float = 1.3 * Vector3(right.dot(basis.x), right.dot(basis.y), right.dot(basis.z)).length()
		offset = signf(offset) * maxf(absf(offset), ROAD_HALF + 1.0 + radius)
		var p: Vector3 = _terrain_point(s, offset) - Vector3.UP * scale * 0.18
		stones.append(Transform3D(basis, p))
	# Interleaved slumped outcrops beside the cut, instead of giant smooth hills.
	var outcrop_s: float = ceil(start / 24.0) * 24.0
	while outcrop_s < stop:
		var offset: float = 10.0 + 1.3 * sin(outcrop_s * 0.14)
		var scale: Vector3 = Vector3(_rng.randf_range(1.65, 2.8), _rng.randf_range(2.0, 3.6), _rng.randf_range(2.8, 4.8))
		var basis: Basis = Basis.from_euler(Vector3(0.17, _rng.randf() * TAU, 0.16)).scaled(scale)
		var right: Vector3 = _route.sample(outcrop_s).right
		var radius: float = 1.3 * Vector3(right.dot(basis.x), right.dot(basis.y), right.dot(basis.z)).length()
		offset = maxf(offset, ROAD_HALF + 1.0 + radius)
		stones.append(Transform3D(basis, _terrain_point(outcrop_s, offset) - Vector3.UP * scale.y * 0.25))
		outcrop_s += 24.0
	for i: int in range(19):
		var s: float = lerpf(start, stop, (float(i) + _rng.randf()) / 19.0)
		var offset: float = _rng.randf_range(13.0, 38.0) if i % 2 == 0 else -_rng.randf_range(9.0, 25.0)
		var scale: float = _rng.randf_range(1.05, 1.85)
		var basis: Basis = Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale)
		trees.append(Transform3D(basis, _terrain_point(s, offset) - Vector3.UP * 0.09))
	_multimesh(parent, _bush_mesh, bushes, _foliage_material, "MediterraneanShrubland")
	_multimesh(parent, _grass_cluster_mesh, grasses, _grass_material, "WildGrass")
	_multimesh(parent, _rock_mesh, stones, _terrain_material, "WeatheredBoulders")
	_multimesh(parent, _tree_leaf_mesh, trees, _foliage_material, "WindShapedCoastalTrees")
	_multimesh(parent, _tree_branch_mesh, trees, _bark_material, "TreeTrunksAndBranches")

func _build_prototypes() -> void:
	# Shared prototypes keep all instances in five draw batches per landscape chunk.
	_rock_mesh = _eroded_rock_mesh()
	_bush_mesh = _leaf_cluster_mesh(42, 710, Vector3(1.12, 0.68, 0.94), 0.7, false)
	_tree_leaf_mesh = _leaf_cluster_mesh(150, 803, Vector3(2.18, 1.35, 1.78), 3.25, true)
	_tree_branch_mesh = _branched_tree_mesh()
	_grass_cluster_mesh = _grass_mesh()

func _rock_point(unit: Vector3) -> Vector3:
	var radius: float = 1.0 + _noise.get_noise_3dv(unit * 105.0 + Vector3(70, 310, 17)) * 0.21
	radius += _noise.get_noise_3dv(unit * 320.0 + Vector3(20, 20, 250)) * 0.09
	radius += _noise.get_noise_3dv(unit * 780.0) * 0.025
	var point: Vector3 = unit * radius
	point.x += (1.0 - unit.y * unit.y) * 0.065 * sin(unit.z * 8.0 + 1.4)
	point.y += (1.0 - unit.y * unit.y) * 0.065 * sin(unit.y * 12.0 + unit.x * 1.7)
	return point

func _eroded_rock_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS: int = 28
	const RINGS: int = 18
	for ring: int in range(RINGS + 1):
		var latitude: float = PI * float(ring) / RINGS
		for segment: int in range(SEGMENTS + 1):
			var angle: float = TAU * float(segment) / SEGMENTS
			var unit: Vector3 = Vector3(sin(latitude) * cos(angle), cos(latitude), sin(latitude) * sin(angle))
			var point: Vector3 = _rock_point(unit)
			# Finite surface derivatives remain continuous at the UV seam and poles.
			var tangent: Vector3 = unit.cross(Vector3.UP).normalized()
			if tangent.length_squared() < 0.1:
				tangent = Vector3.RIGHT
			var bitangent: Vector3 = unit.cross(tangent).normalized()
			var dp: Vector3 = _rock_point((unit + tangent * 0.006).normalized()) - _rock_point((unit - tangent * 0.006).normalized())
			var dq: Vector3 = _rock_point((unit + bitangent * 0.006).normalized()) - _rock_point((unit - bitangent * 0.006).normalized())
			st.set_normal(dp.cross(dq).normalized())
			st.set_color(Color(0.0, 0.0, 0.0, 1.0))
			st.set_uv(Vector2(float(segment) / SEGMENTS, float(ring) / RINGS))
			st.add_vertex(point)
	for ring: int in range(RINGS):
		for segment: int in range(SEGMENTS):
			var a: int = ring * (SEGMENTS + 1) + segment
			var b: int = a + SEGMENTS + 1
			for index: int in [a, b, a + 1, a + 1, b, b + 1]:
				st.add_index(index)
	return st.commit()

func _leaf_cluster_mesh(cards: int, seed_value: int, spread: Vector3, centre_y: float, is_tree: bool) -> ArrayMesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(cards):
		var azimuth: float = rng.randf() * TAU
		var elevation: float = rng.randf_range(-0.65, 0.95)
		var direction: Vector3 = Vector3(cos(azimuth) * sqrt(1.0 - elevation * elevation), elevation, sin(azimuth) * sqrt(1.0 - elevation * elevation))
		var p: Vector3 = direction * spread * pow(rng.randf(), 0.45) + Vector3(0.27, centre_y, 0)
		if is_tree:
			p.x += maxf(0.0, p.y - 2.0) * 0.22
		var card_basis: Basis = Basis.from_euler(Vector3(rng.randf_range(-1.1, 1.1), rng.randf() * TAU, rng.randf_range(-0.8, 0.8)))
		var height: float = rng.randf_range(0.62, 1.17) if is_tree else rng.randf_range(0.43, 0.85)
		var half_side: Vector3 = card_basis.x * height * 0.31
		var up: Vector3 = card_basis.y * height * 0.5
		var shade: float = rng.randf_range(0.67, 1.0)
		var color: Color = Color(shade * 0.9, shade, shade * 0.84)
		# A photographed leafy branch in the right section of the original atlas.
		_quad(st, p - half_side - up, p + half_side - up, p + half_side + up, p - half_side + up, color,
			Vector2(0.533, 0.67), Vector2(0.839, 0.67), Vector2(0.839, 0.022), Vector2(0.533, 0.022))
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

func _branch_segment(st: SurfaceTool, start: Vector3, stop: Vector3, radius_a: float, radius_b: float, sides: int = 7) -> void:
	var direction: Vector3 = (stop - start).normalized()
	var side: Vector3 = direction.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < 0.1:
		side = direction.cross(Vector3.RIGHT).normalized()
	var other: Vector3 = direction.cross(side).normalized()
	for i: int in range(sides):
		var a: float = TAU * float(i) / sides
		var b: float = TAU * float(i + 1) / sides
		var n0: Vector3 = side * cos(a) + other * sin(a)
		var n1: Vector3 = side * cos(b) + other * sin(b)
		_quad(st, start + n0 * radius_a, stop + n0 * radius_b, stop + n1 * radius_b, start + n1 * radius_a, Color.WHITE,
			Vector2(float(i) / sides, start.y), Vector2(float(i) / sides, stop.y), Vector2(float(i + 1) / sides, stop.y), Vector2(float(i + 1) / sides, start.y))

func _branched_tree_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var path: Array[Vector3] = [Vector3.ZERO, Vector3(0.06,0.7,0.04), Vector3(0.18,1.5,-0.05), Vector3(0.38,2.2,0.04), Vector3(0.53,2.9,0.1), Vector3(0.81,3.8,0.07)]
	for i: int in range(path.size() - 1):
		_branch_segment(st, path[i], path[i + 1], 0.20 * pow(0.75, i), 0.20 * pow(0.75, i + 1), 10)
	for i: int in range(9):
		var angle: float = i * 2.399
		var base: Vector3 = path[2 + i % 3]
		var spread: Vector3 = Vector3(cos(angle), 0.28, sin(angle))
		var middle: Vector3 = base + spread * (0.8 + float(i % 3) * 0.21) + Vector3.UP * 0.18
		var tip: Vector3 = middle + spread * 0.65 + Vector3.UP * 0.35
		_branch_segment(st, base, middle, 0.08, 0.047)
		_branch_segment(st, middle, tip, 0.047, 0.012, 6)
		for fork: int in range(2):
			var fork_tip: Vector3 = tip + Vector3(cos(angle + (fork - 0.5) * 1.9), 0.65, sin(angle + (fork - 0.5) * 1.9)) * 0.65
			_branch_segment(st, middle.lerp(tip, 0.55), fork_tip, 0.023, 0.004, 5)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

func _grass_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(3):
		var angle: float = float(i) * PI / 3.0
		var side: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * 0.44
		var base: Vector3 = Vector3(sin(angle), 0.0, cos(angle)) * 0.07
		_quad(st, base - side, base + side, base + side * 0.84 + Vector3.UP * 0.55, base - side * 0.84 + Vector3.UP * 0.55,
			Color(0.78 + float(i) * 0.07, 0.88, 0.65), Vector2(0.21, 0.90), Vector2(0.46, 0.90), Vector2(0.46, 0.74), Vector2(0.21, 0.74))
	st.generate_normals()
	return st.commit()

func _build_ocean() -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://assets/environment/coastal_water.gdshader")
	mat.set_shader_parameter("grain_texture", _noise_texture)
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(19000.0, 19000.0)
	mesh.subdivide_width = 2
	mesh.subdivide_depth = 2
	var ocean: MeshInstance3D = MeshInstance3D.new()
	ocean.name = "PacificBlueOcean"
	ocean.mesh = mesh
	ocean.material_override = mat
	ocean.position = Vector3(-3000.0, SEA_LEVEL, -1700.0)
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)

func _build_distant_coast() -> void:
	var islands: Array[Vector4] = [Vector4(-1850, -3400, 1250, 250), Vector4(-2450, -4850, 1500, 350), Vector4(-970, -4610, 950, 310), Vector4(160, -4500, 1050, 310), Vector4(-3950, -5800, 1800, 390)]
	for island_index: int in range(islands.size()):
		var island: Vector4 = islands[island_index]
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rows: int = 40
		var columns: int = 110
		for row: int in range(rows + 1):
			var u: float = float(row) / rows
			for column: int in range(columns + 1):
				var v: float = float(column) / columns
				var point: Vector3 = _distant_point(u, v, island, island_index)
				var across: Vector3 = _distant_point(u + 0.001, v, island, island_index) - _distant_point(u - 0.001, v, island, island_index)
				var along: Vector3 = _distant_point(u, v + 0.001, island, island_index) - _distant_point(u, v - 0.001, island, island_index)
				st.set_normal(along.cross(across).normalized())
				st.set_color(Color.WHITE)
				st.add_vertex(point)
		for row: int in range(rows):
			for column: int in range(columns):
				var a: int = row * (columns + 1) + column
				var b: int = a + columns + 1
				for index: int in [a, b, a + 1, a + 1, b, b + 1]:
					st.add_index(index)
		_commit_mesh(self, st, _distant_material, "DistantHeadland_%d" % island_index, false)

func _distant_point(u: float, v: float, island: Vector4, island_index: int) -> Vector3:
	var local_x: float = (u * 2.0 - 1.0) * island.z
	var local_z: float = (v * 2.0 - 1.0) * island.z * 0.67
	var ridge: float = pow(maxf(0.0, sin(u * PI)), 1.3) * pow(maxf(0.0, sin(v * PI)), 0.65)
	var peak: float = 0.72 + 0.16 * sin(v * 19.0 + island_index * 2.0) + 0.06 * sin(v * 37.0 + u * 8.0)
	var erosion: float = _noise.get_noise_2d(local_x * 0.18 + island_index * 370.0, local_z * 0.22) * 0.12
	var h: float = -8.0 + ridge * island.w * (peak + erosion)
	return Vector3(island.x + local_x, h, island.y + local_z)

func _build_signs() -> void:
	var sign_material: StandardMaterial3D = _material(Color(0.98, 0.76, 0.15))
	var dark_material: StandardMaterial3D = _material(Color(0.07, 0.12, 0.11))
	for s: float in [210.0, 570.0, 1010.0, 1300.0, 1700.0, 2090.0, 2430.0]:
		var frame: Dictionary = _route.sample(s)
		var right: Vector3 = frame.right
		var node: Node3D = Node3D.new()
		node.name = "BendChevron_%d" % int(s)
		node.position = frame.position + right * 6.65
		node.basis = Basis(right, Vector3.UP, -Vector3(frame.forward))
		add_child(node)
		var pole: MeshInstance3D = MeshInstance3D.new()
		pole.mesh = _box(Vector3(0.08, 1.6, 0.08))
		pole.material_override = _guard_material
		pole.position.y = 0.8
		node.add_child(pole)
		var panel: MeshInstance3D = MeshInstance3D.new()
		panel.mesh = _box(Vector3(1.35, 0.68, 0.08))
		panel.material_override = sign_material
		panel.position.y = 1.65
		node.add_child(panel)
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sign_direction: float = 1.0 if float(frame.curvature) > 0.0 else -1.0
		for arrow: int in range(2):
			var cx: float = -0.34 + arrow * 0.63
			var points: Array[Vector2] = [Vector2(-0.21, -0.25), Vector2(0.0, -0.25), Vector2(0.24, 0.0), Vector2(0.0, 0.25), Vector2(-0.21, 0.25), Vector2(0.03, 0.0)]
			for tri: int in [0, 1, 5, 1, 2, 5, 2, 3, 5, 3, 4, 5]:
				st.set_normal(Vector3.BACK)
				st.add_vertex(Vector3(cx + points[tri].x * sign_direction, 1.65 + points[tri].y, 0.044))
		_commit_mesh(node, st, dark_material, "DirectionArrows")

func _build_finish() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in range(2):
		for column: int in range(16):
			var s0: float = 2595.0 + row * 0.55
			var s1: float = s0 + 0.55
			var f0: Dictionary = _route.sample(s0)
			var f1: Dictionary = _route.sample(s1)
			var offset0: float = -4.3 + column * 8.6 / 16.0
			var offset1: float = offset0 + 8.6 / 16.0
			var color: Color = Color(0.93, 0.90, 0.77) if (row + column) % 2 == 0 else Color(0.07, 0.105, 0.11)
			_quad(st, Vector3(f0.position) + Vector3(f0.right) * offset0 + Vector3.UP * 0.027, Vector3(f1.position) + Vector3(f1.right) * offset0 + Vector3.UP * 0.027, Vector3(f1.position) + Vector3(f1.right) * offset1 + Vector3.UP * 0.027, Vector3(f0.position) + Vector3(f0.right) * offset1 + Vector3.UP * 0.027, color)
	_commit_mesh(self, st, _paint_material, "FinishCheckers")

func _box(size: Vector3) -> BoxMesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return mesh

func _multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], material: Material, node_name: String) -> void:
	if transforms.is_empty():
		return
	var batch: MultiMesh = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.instance_count = transforms.size()
	batch.mesh = mesh
	for i: int in range(transforms.size()):
		batch.set_instance_transform(i, transforms[i])
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = node_name
	node.visibility_range_end = 380.0 if node_name == "WildGrass" else (820.0 if node_name == "MediterraneanShrubland" else 0.0)
	if node_name == "WildGrass":
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.multimesh = batch
	node.material_override = material
	if node_name == "WeatheredBoulders":
		# Retain CPU placement evidence for headless clearance validation. The
		# dummy renderer cannot read instance transforms back from a GPU buffer.
		node.set_meta("placement_transforms", transforms)
	parent.add_child(node)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, uv_a: Vector2 = Vector2.ZERO, uv_b: Vector2 = Vector2(0, 1), uv_c: Vector2 = Vector2.ONE, uv_d: Vector2 = Vector2(1, 0)) -> void:
	var points: Array[Vector3] = [a, b, c, d]
	var uvs: Array[Vector2] = [uv_a, uv_b, uv_c, uv_d]
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	for index: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(color)
		st.set_uv(uvs[index])
		st.set_normal(normal)
		st.add_vertex(points[index])

func _commit_mesh(parent: Node3D, st: SurfaceTool, material: Material, node_name: String, generate_normals: bool = true) -> void:
	if generate_normals:
		st.generate_normals()
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	if node_name == "ContinuousAsphalt":
		st.generate_tangents()
	node.mesh = st.commit()
	node.material_override = material
	parent.add_child(node)
