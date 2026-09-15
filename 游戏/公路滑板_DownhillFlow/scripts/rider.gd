extends Node3D
## Real anatomical skater: licensed meshes, photographic texture maps and
## authored poses, contact IK and an input-driven push cycle. Parent owns travel.

const AVATAR: PackedScene = preload("res://assets/rider_realistic/rider.glb")
var _built: bool = false
var _board: Node3D
var _human: Node3D
var _skeleton: Skeleton3D
var _poses: Dictionary = {}
var _wheels: Array[Node3D] = []
var _wheel_angle: float = 0.0
var _tuck: float = 0.0
var _steer: float = 0.0
var _brake: float = 0.0
var _motion_time: float = 0.0
var _push_requested: bool = false
var _push_active: bool = false
var _push_phase: float = 0.0
var _joints: Dictionary = {}
var _feet: Dictionary = {}
const PUSH_DURATION: float = 1.9
var _silver: StandardMaterial3D
var _red: StandardMaterial3D
var _cream: StandardMaterial3D
var _dark: StandardMaterial3D

func build() -> void:
	if _built:
		return
	_built = true
	_silver = _material(Color("949b9e"), 0.28, 0.75)
	_red = _material(Color("881624"), 0.84)
	_cream = _material(Color("cbb78c"), 0.74)
	_dark = _material(Color("202325"), 0.92)
	_board = _node(self, "Longboard")
	_build_board()
	_human = AVATAR.instantiate() as Node3D
	_human.name = "AnatomicalRider"
	_board.add_child(_human)
	_skeleton = _human.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var players: Array[Node] = _human.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player: AnimationPlayer = players[0] as AnimationPlayer
		for pose_name: String in ["Ride", "Tuck", "Brake", "Push"]:
			for animation_name: StringName in player.get_animation_list():
				if String(animation_name).ends_with(pose_name):
					player.play(animation_name)
					player.seek(0.0, true)
					player.advance(0.0)
					var pose: Array[Transform3D] = []
					for index: int in range(_skeleton.get_bone_count()):
						pose.append(_skeleton.get_bone_pose(index))
					_poses[pose_name] = pose
		player.stop(true)
		player.process_mode = Node.PROCESS_MODE_DISABLED
	if _poses.has("Ride"):
		for index: int in range(_skeleton.get_bone_count()):
			_skeleton.set_bone_pose(index, _poses["Ride"][index])
		_skeleton.force_update_all_bone_transforms()
		for side: String in ["L", "R"]:
			_feet[side] = _skeleton.get_bone_global_pose(_joint(side + " Foot"))
	animate(0.0, 10.0, 0.0, 0.0, 0.0, 0.0)

func set_push_requested(requested: bool) -> void:
	_push_requested = requested

func reset_motion() -> void:
	_tuck = 0.0
	_steer = 0.0
	_brake = 0.0
	_motion_time = 0.0
	_push_requested = false
	_push_active = false
	_push_phase = 0.0
	animate(0.0, 10.0, 0.0, 0.0, 0.0, 0.0)

func animate(delta: float, speed: float, steer: float, tuck: float, brake: float, _time: float) -> void:
	if not _built:
		return
	var dt: float = clampf(delta, 0.0, 0.05)
	_motion_time += dt
	var blend: float = 1.0 - exp(-dt * 7.0)
	_tuck = lerpf(_tuck, clampf(tuck, 0.0, 1.0), blend)
	_steer = lerpf(_steer, clampf(steer, -1.0, 1.0), blend)
	_brake = lerpf(_brake, clampf(brake, 0.0, 1.0), blend)
	_board.rotation.y = -_steer * (0.035 + _brake * 0.19)
	_board.rotation.z = -_steer * 0.025
	_wheel_angle = fmod(_wheel_angle + maxf(speed, 0.0) * dt / 0.063, TAU)
	for wheel: Node3D in _wheels:
		wheel.rotation.x = -_wheel_angle
	if not _poses.has("Ride"):
		return
	# A push is a complete lift / ground stroke / recovery. It starts only on
	# input and finishes on the deck; neither speed nor wall-clock jumps splice it.
	if not _push_active and _push_requested and speed < 7.5 and _brake < 0.15 and _tuck < 0.2:
		_push_active = true
		_push_phase = 0.0
	if _push_active:
		_push_phase += dt / PUSH_DURATION
		if _push_phase >= 1.0:
			_push_phase = 0.0
			_push_active = false
	var push_envelope: float = pow(sin(_push_phase * PI), 2.0) if _push_active else 0.0
	var ride: Array = _poses["Ride"]
	for index: int in range(_skeleton.get_bone_count()):
		var pose: Transform3D = ride[index]
		if _poses.has("Tuck"):
			pose = pose.interpolate_with(_poses["Tuck"][index], _tuck)
		if _poses.has("Brake"):
			pose = pose.interpolate_with(_poses["Brake"][index], _brake * (1.0 - _tuck * 0.6))
		_skeleton.set_bone_pose(index, pose)
	_human.rotation = Vector3.ZERO
	_skeleton.force_update_all_bone_transforms()
	# Move the pelvis over the support line, then let the spine and arms balance.
	# Feet are solved last against the fixed deck contacts instead of rolling
	# the whole avatar, which previously carried the shoes away from the board.
	var pelvis: int = _joint("Pelvis")
	var hip: Vector3 = _skeleton.get_bone_global_pose(pelvis).origin
	hip += Vector3(_steer * 0.045 * (1.0 - _tuck * 0.5), -push_envelope * 0.025, -push_envelope * 0.055)
	_set_global_position(pelvis, hip)
	_add_global_rotation(pelvis, Vector3.BACK, -_steer * 0.025)
	var breathing: float = sin(_motion_time * 1.65) * 0.003 * (1.0 - _tuck * 0.65)
	for bone_name: String in ["Spine", "Spine1", "Spine2"]:
		_add_global_rotation(_joint(bone_name), Vector3.BACK, -_steer * 0.018)
		_add_global_rotation(_joint(bone_name), Vector3.RIGHT, breathing)
	_add_global_rotation(_joint("Head"), Vector3.BACK, _steer * 0.035)
	for side: String in ["L", "R"]:
		var side_sign: float = -1.0 if side == "L" else 1.0
		var shoulder: int = _joint(side + " UpperArm")
		var elbow: int = _joint(side + " Forearm")
		var wrist: int = _joint(side + " Hand")
		var arm_tip: Transform3D = _skeleton.get_bone_global_pose(wrist)
		var arm_pole: Vector3 = _skeleton.get_bone_global_pose(elbow).origin
		var quiet_motion: float = sin(_motion_time * 1.65 + side_sign * 0.5) * 0.006
		var balance: float = 1.0 - _tuck * 0.75
		var hand_offset := Vector3(-_steer * 0.075, absf(_steer) * 0.045 + quiet_motion, side_sign * _steer * 0.05) * balance
		hand_offset += Vector3(0.025 * push_envelope, 0.025 * push_envelope, side_sign * push_envelope * 0.075)
		_solve_limb(shoulder, elbow, wrist, arm_tip.origin + hand_offset, arm_pole, arm_tip.basis, false)
	for side: String in ["L", "R"]:
		var contact: Transform3D = _feet[side]
		var target: Vector3 = contact.origin
		if side == "L" and _push_active:
			target += _push_offset(_push_phase)
		var knee: int = _joint(side + " Calf")
		_solve_limb(_joint(side + " Thigh"), knee, _joint(side + " Foot"),
			target, _skeleton.get_bone_global_pose(knee).origin, contact.basis, true)

func _joint(label: String) -> int:
	if not _joints.has(label):
		var index: int = _skeleton.find_bone("Bip01_" + label.replace(" ", "_"))
		if index < 0: index = _skeleton.find_bone("Bip01 " + label)
		_joints[label] = index
	return int(_joints[label])

func _set_global_position(index: int, position: Vector3) -> void:
	var parent: int = _skeleton.get_bone_parent(index)
	var local: Vector3 = position
	if parent >= 0:
		local = _skeleton.get_bone_global_pose(parent).affine_inverse() * position
	_skeleton.set_bone_pose_position(index, local)
	_skeleton.force_update_all_bone_transforms()

func _set_global_basis(index: int, basis: Basis) -> void:
	var parent: int = _skeleton.get_bone_parent(index)
	var local: Basis = basis
	if parent >= 0:
		local = _skeleton.get_bone_global_pose(parent).basis.inverse() * basis
	_skeleton.set_bone_pose_rotation(index, local.orthonormalized().get_rotation_quaternion())
	_skeleton.force_update_all_bone_transforms()

func _add_global_rotation(index: int, axis: Vector3, angle: float) -> void:
	if index < 0: return
	_set_global_basis(index, Basis(axis, angle) * _skeleton.get_bone_global_pose(index).basis)

func _solve_limb(upper: int, lower: int, end: int, requested: Vector3,
		pole_point: Vector3, end_basis: Basis, lock_end: bool) -> void:
	var a: Transform3D = _skeleton.get_bone_global_pose(upper)
	var b: Transform3D = _skeleton.get_bone_global_pose(lower)
	var c: Transform3D = _skeleton.get_bone_global_pose(end)
	var l1: float = a.origin.distance_to(b.origin)
	var l2: float = b.origin.distance_to(c.origin)
	var reach: Vector3 = requested - a.origin
	var distance: float = clampf(reach.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var axis: Vector3 = reach.normalized()
	var target: Vector3 = a.origin + axis * distance
	var pole: Vector3 = pole_point - a.origin
	pole -= axis * pole.dot(axis)
	if pole.length_squared() < 0.000001:
		pole = Vector3.LEFT - axis * Vector3.LEFT.dot(axis)
	pole = pole.normalized()
	var along: float = (l1 * l1 - l2 * l2 + distance * distance) / (2.0 * distance)
	var height: float = sqrt(maxf(0.0, l1 * l1 - along * along))
	var joint_target: Vector3 = a.origin + axis * along + pole * height
	var upper_arc := Quaternion((b.origin - a.origin).normalized(), (joint_target - a.origin).normalized())
	_set_global_basis(upper, Basis(upper_arc) * a.basis)
	b = _skeleton.get_bone_global_pose(lower)
	c = _skeleton.get_bone_global_pose(end)
	var lower_arc := Quaternion((c.origin - b.origin).normalized(), (target - b.origin).normalized())
	_set_global_basis(lower, Basis(lower_arc) * b.basis)
	if lock_end: _set_global_basis(end, end_basis)

func _push_offset(phase: float) -> Vector3:
	# C2 easing gives zero velocity and acceleration at each contact boundary.
	var times := [0.0, 0.22, 0.40, 0.66, 0.84, 1.0]
	var points := [Vector3.ZERO, Vector3(0.22, 0.075, -0.20),
		Vector3(0.25, -0.165, -0.32), Vector3(0.25, -0.165, 0.14),
		Vector3(0.18, 0.075, 0.10), Vector3.ZERO]
	for index: int in range(times.size() - 1):
		if phase <= float(times[index + 1]):
			var u: float = clampf((phase - float(times[index])) / (float(times[index + 1]) - float(times[index])), 0.0, 1.0)
			var eased: float = u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
			return (points[index] as Vector3).lerp(points[index + 1], eased)
	return Vector3.ZERO


func _build_board() -> void:
	var wood: StandardMaterial3D = _material(Color("b98b58"), 0.7)
	var wood_dark: StandardMaterial3D = _material(Color("6d492d"), 0.8)
	_deck_layer("MapleDeck", 0.142, 0.024, 1.0, wood)
	_deck_layer("LaminateLine1", 0.145, 0.002, 1.003, wood_dark)
	_deck_layer("LaminateLine2", 0.153, 0.0018, 1.003, wood_dark)
	var grip: StandardMaterial3D = _material(Color("242b29"), 1.0)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 442
	noise.frequency = 0.48
	var grip_image: Image = Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y: int in range(128):
		for x: int in range(128):
			var value: float = 0.68 + noise.get_noise_2d(float(x), float(y)) * 0.2
			grip_image.set_pixel(x, y, Color(value, value, value))
	grip.albedo_texture = ImageTexture.create_from_image(grip_image)
	grip.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_deck_layer("GripTape", 0.166, 0.0015, 0.956, grip)
	for z: float in [-0.37, 0.37]:
		var plate: MeshInstance3D = _box(_board, "TruckBasePlate", Vector3(0.087, 0.012, 0.074), _silver)
		plate.position = Vector3(0, 0.134, z)
		_segment(_cylinder(_board, "TruckKingpin", 0.014, _silver), Vector3(0, 0.13, z + 0.022), Vector3(0, 0.087, z - 0.009))
		_segment(_cylinder(_board, "TruckHanger", 0.014, _silver), Vector3(-0.186, 0.072, z), Vector3(0.186, 0.072, z))
		var bushing: MeshInstance3D = _ellipsoid(_board, "RedBushing", Vector3(0.018, 0.014, 0.019), _red)
		bushing.position = Vector3(0, 0.103, z)
		for x: float in [-0.183, 0.183]:
			var wheel_pivot: Node3D = _node(_board, "WheelSpin" + str(_wheels.size()))
			wheel_pivot.position = Vector3(x, 0.065, z)
			_wheels.append(wheel_pivot)
			var wheel: MeshInstance3D = _cylinder(wheel_pivot, "UrethaneWheel", 0.063, _cream)
			wheel.scale.y = 0.047
			wheel.rotation.z = PI / 2.0
			for side: float in [-1.0, 1.0]:
				var hub: MeshInstance3D = _cylinder(wheel_pivot, "WheelHub", 0.023, _dark)
				hub.scale.y = 0.003
				hub.rotation.z = PI / 2.0
				hub.position.x = side * 0.024
				var axle_nut: MeshInstance3D = _cylinder(wheel_pivot, "AxleNut", 0.0085, _silver, 6)
				axle_nut.scale.y = 0.005
				axle_nut.rotation.z = PI / 2.0
				axle_nut.position.x = side * 0.027
		for bx: float in [-0.027, 0.027]:
			for bz: float in [-0.021, 0.021]:
				var bolt: MeshInstance3D = _cylinder(_board, "DeckBolt", 0.0045, _silver, 8)
				bolt.scale.y = 0.002
				bolt.position = Vector3(bx, 0.172, z + bz)
	# Thin contrasting strip follows the kicktail, distinct from the rubber grip.
	var stripe: MeshInstance3D = _box(_board, "TailStripe", Vector3(0.17, 0.002, 0.008), _red)
	stripe.position = Vector3(0, 0.181, 0.465)

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.metallic_specular = 0.25 if metallic < 0.1 else 0.5
	return material

func _node(parent: Node, node_name: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = node_name
	parent.add_child(node)
	return node

func _instance(parent: Node, mesh_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	if _is_shadow_detail(mesh_name):
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _is_shadow_detail(mesh_name: String) -> bool:
	# These overlaid details do not contribute to the rider's silhouette. Their
	# underlying clothing, skin, deck and hardware retain the complete main shadow.
	for token: String in ["Stitch", "Seam", "Shoelace", "Pinstripe", "Strand", "Stud", "BackLabel", "WavePrint", "DeckBolt", "AxleNut", "LaminateLine", "TailStripe", "CapBand", "CapTopButton", "Hem", "Collar", "SockCuff", "Eye", "Mouth"]:
		if mesh_name.contains(token):
			return true
	return false

func _ellipsoid(parent: Node, mesh_name: String, radii: Vector3, material: Material) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 32
	mesh.rings = 18
	var instance: MeshInstance3D = _instance(parent, mesh_name, mesh, material)
	instance.scale = radii
	return instance

func _box(parent: Node, mesh_name: String, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return _instance(parent, mesh_name, mesh, material)

func _cylinder(parent: Node, mesh_name: String, radius: float, material: Material, segments: int = 28) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = segments
	return _instance(parent, mesh_name, mesh, material)

func _segment(instance: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var offset: Vector3 = end - start
	var distance: float = maxf(offset.length(), 0.0001)
	instance.position = start
	instance.basis = Basis(Quaternion(Vector3.UP, offset / distance)) * Basis.from_scale(Vector3(1, distance, 1))
	# CylinderMesh is centered; profile meshes start at y=0.
	if instance.mesh is CylinderMesh:
		instance.position = (start + end) * 0.5

func _deck_layer(mesh_name: String, y: float, thickness: float, width_scale: float, material: Material) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = 64
	for index: int in range(count):
		var angle_a: float = float(index) * TAU / float(count)
		var angle_b: float = float(index + 1) * TAU / float(count)
		var a: Vector3 = _deck_point(angle_a, y + thickness, width_scale)
		var b: Vector3 = _deck_point(angle_b, y + thickness, width_scale)
		var lower_a: Vector3 = a - Vector3(0, thickness, 0)
		var lower_b: Vector3 = b - Vector3(0, thickness, 0)
		for vertex: Vector3 in [Vector3(0, y + thickness, 0), a, b, a, lower_a, b, b, lower_a, lower_b, Vector3(0, y, 0), lower_b, lower_a]:
			st.set_uv(Vector2(vertex.x * 8.0, vertex.z * 8.0))
			st.add_vertex(vertex)
	st.generate_normals()
	st.index()
	_instance(_board, mesh_name, st.commit(), material)

func _deck_point(angle: float, y: float, width_scale: float) -> Vector3:
	var cosine: float = cos(angle)
	var x: float = signf(cosine) * pow(absf(cosine), 0.62) * 0.141 * width_scale
	var z: float = sin(angle) * 0.554
	var kick: float = pow(absf(z) / 0.554, 6.0) * 0.018
	return Vector3(x, y + kick + pow(absf(x) / 0.141, 3.0) * 0.005, z)
