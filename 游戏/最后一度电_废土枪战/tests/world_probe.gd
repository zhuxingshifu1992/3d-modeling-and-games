extends SceneTree

var failures: Array[String] = []
var world: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("WORLD_PROBE: " + message)

func _run() -> void:
	if not ResourceLoader.exists("res://scripts/world.gd"):
		_check(false, "world.gd implementation does not exist yet")
		_finish()
		return
	var script: Script = load("res://scripts/world.gd")
	if script == null or not script.can_instantiate():
		_check(false, "world.gd must compile and instantiate")
		_finish()
		return
	world = Node3D.new()
	world.set_script(script)
	root.add_child(world)
	world.call("build")
	await physics_frame
	await physics_frame
	_check(world.has_node("ReferenceYard"), "original GLB scene is instantiated")
	var batching: Dictionary = world.get_meta("static_batch_stats", {})
	_check(not batching.is_empty(), "static renderer exposes measured batching statistics")
	if not batching.is_empty():
		_check(int(batching.get("batch_surfaces", 9999)) < int(batching.get("source_surfaces", 0)) * 0.55, "material batching substantially reduces static surfaces")
		_check(int(batching.get("source_triangles", -1)) == int(batching.get("batch_triangles", -2)), "batching preserves all reference triangles")
		_check(int(batching.get("source_uv_vertices", -1)) == int(batching.get("batch_uv_vertices", -2)), "batching preserves the original UV vertex count")
	_check(bool(world.call("is_walkable", Vector3(0, 0.05, 21))), "entry spawn is walkable")
	_check(not bool(world.call("is_walkable", Vector3(10, 0.05, 0))), "closed office blocks ground navigation")
	_check(not bool(world.call("is_walkable", Vector3(-10, 0.05, -7.5))), "white charging pod blocks navigation")
	_check(not bool(world.call("is_walkable", Vector3(10, 0.05, -12.5))), "truck blocks navigation")
	_check(not bool(world.call("is_walkable", Vector3(26, 0.05, 0))), "world boundary is closed")
	var routes: Array[Array] = [
		[Vector3(0, 0.05, 21), Vector3(14.9, 0.05, 7.2), "entry to stairs"],
		[Vector3(14.9, 0.05, 7.2), Vector3(-8.3, 0.05, -7.5), "stairs to charge point"],
		[Vector3(-8.3, 0.05, -7.5), Vector3(-8.9, 0.05, 0.55), "charge to reset cabinet"],
		[Vector3(1, 0.05, -20), Vector3(-8.3, 0.05, -7.5), "warehouse reinforcement to charge point"],
		[Vector3(21, 0.05, -17), Vector3(-8.3, 0.05, -7.5), "truck flank to charge point"],
		[Vector3(-8.3, 0.05, -7.5), Vector3(0, 0.05, 20), "charge to extraction"]
	]
	for route: Array in routes:
		var path: PackedVector3Array = world.call("find_path", route[0], route[1])
		_check(path.size() >= 2, String(route[2]) + " produces a path")
		if path.is_empty():
			continue
		_check(path[-1].distance_to(route[1]) < 0.8, String(route[2]) + " ends near requested target")
		for i: int in range(path.size()):
			_check(bool(world.call("is_walkable", path[i])), String(route[2]) + " never enters a solid")
			if i > 0:
				for fraction: float in [0.25, 0.5, 0.75]:
					_check(bool(world.call("is_walkable", path[i - 1].lerp(path[i], fraction))), String(route[2]) + " segments do not cut corners")
	var colliders: Array[Node] = get_nodes_in_group("world_solids")
	print("WORLD_STATS explicit_static_bodies=", colliders.size())
	_check(colliders.size() >= 25 and colliders.size() < 200, "bounded explicit collision set without foliage triangle soup")
	for node: Node in colliders:
		_check(node is StaticBody3D and node.collision_layer == 1 and node.collision_mask == 0, "static collision uses layer 1 / mask 0")
	_check(_ray(Vector3(4, 1.5, 0), Vector3(11, 1.5, 0)).has("position"), "office stops bullets")
	_check(_ray(Vector3(10, 1.2, -8), Vector3(10, 1.2, -13)).has("position"), "truck stops bullets")
	var support: Dictionary = _ray(Vector3(10.9, 5, 3.55), Vector3(10.9, 2, 3.55))
	_check(not support.is_empty(), "power console terrace has support")
	if not support.is_empty():
		_check(absf(Vector3(support["position"]).y - 3.04) < 0.08, "terrace walking surface is at console height")
	var ramp_support: Dictionary = _ray(Vector3(14.9, 5, 3.2), Vector3(14.9, -1, 3.2))
	_check(not ramp_support.is_empty(), "stairs have a continuous supporting ramp")
	if not ramp_support.is_empty():
		_check(Vector3(ramp_support["normal"]).y > 0.75, "ramp is walkable, not discrete steps")
	await _walk_upstairs()
	world.call("set_power", true, false)
	world.call("set_power", false, true)
	world.call("set_quality", true)
	_check(not world.get("_sun").shadow_enabled, "low quality disables expensive sun shadows")
	world.call("set_quality", false)
	_check(world.get("_sun").shadow_enabled and world.get("_sun").directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "normal quality uses one orthogonal shadow pass")
	_finish()

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(a, b, 1)
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func _walk_upstairs() -> void:
	var pawn: CharacterBody3D = CharacterBody3D.new()
	pawn.name = "StairReachabilityCapsule"
	pawn.collision_layer = 2
	pawn.collision_mask = 1
	pawn.floor_snap_length = 0.4
	pawn.floor_max_angle = deg_to_rad(53.0)
	pawn.safe_margin = 0.015
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	shape_node.shape = capsule
	shape_node.position.y = 0.9
	pawn.add_child(shape_node)
	root.add_child(pawn)
	pawn.position = Vector3(14.9, 0.12, 7.15)
	await physics_frame
	var waypoints: Array[Vector3] = [Vector3(14.9, 3.04, 0), Vector3(13.6, 3.04, 0), Vector3(13.6, 3.04, 3.05), Vector3(10.9, 3.04, 3.45)]
	for target: Vector3 in waypoints:
		for frame: int in range(330):
			var delta: float = 1.0 / 60.0
			var direction: Vector3 = target - pawn.position
			direction.y = 0
			if direction.length() < 0.12:
				break
			direction = direction.normalized()
			pawn.velocity.x = direction.x * 3.4
			pawn.velocity.z = direction.z * 3.4
			pawn.velocity.y -= 22.0 * delta
			pawn.move_and_slide()
			await physics_frame
		_check(Vector2(pawn.position.x - target.x, pawn.position.z - target.z).length() < 0.28, "capsule reaches stair waypoint " + str(target) + "; actual " + str(pawn.position))
	_check(pawn.position.y > 2.95, "capsule ascends stairs and reaches the actual office terrace")
	pawn.queue_free()

func _finish() -> void:
	if failures.is_empty():
		print("WORLD_PROBE PASS: routes, physical cover, collider budget, continuous ramp and office terrace reached")
		quit(0)
	else:
		print("WORLD_PROBE FAIL: ", failures.size(), " checks failed")
		quit(1)
