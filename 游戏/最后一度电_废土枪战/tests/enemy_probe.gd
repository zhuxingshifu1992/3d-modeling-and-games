extends SceneTree
# Regression probe: real CharacterBody3D enemies and real wall/player ray hits.
# Would fail if damage heals on negative input, death emits twice, cover is
# ignored, a cancelled windup still fires, or a clear target is never engaged.

class ProbePlayer extends CharacterBody3D:
	var health: float = 10000.0
	var damage_events: int = 0
	func take_damage(amount: float, _source: Vector3) -> void:
		health -= amount
		damage_events += 1
	func is_alive() -> bool:
		return health > 0.0

class ProbeWorld extends Node3D:
	var routes_enabled: bool = false
	func find_path(_from: Vector3, _to: Vector3) -> PackedVector3Array:
		# No route is intentional: isolate stationary ranged behavior from nav.
		return PackedVector3Array([_to]) if routes_enabled else PackedVector3Array()
	func is_walkable(_point: Vector3) -> bool:
		return true
	func get_cover_points() -> Array[Vector3]:
		return []

class ProbeGame extends Node3D:
	var player: ProbePlayer
	var world: ProbeWorld
	var fighting: bool = true
	var difficulty: String = "standard"
	func can_fight() -> bool:
		return fighting
	func play_sound(_key: String, _position: Vector3 = Vector3.INF) -> void:
		pass
	func spawn_tracer(_a: Vector3, _b: Vector3, _color: Color) -> void:
		pass

var failures: Array[String] = []
var checks: int = 0
var death_count: int = 0
var lethal_headshot: bool = false
var fired_count: int = 0
var geometry_report: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("ENEMY_PROBE_FAIL ", message)

func solid(parent: Node3D, size: Vector3, point: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.position = point
	return body

func ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame

func on_died(_enemy: CharacterBody3D, headshot: bool) -> void:
	death_count += 1
	lethal_headshot = headshot

func on_fired(_origin: Vector3, _target: Vector3) -> void:
	fired_count += 1

func run() -> void:
	var path: String = get_script().resource_path.get_base_dir().path_join("../scripts/enemy.gd").simplify_path()
	if not FileAccess.file_exists(path):
		check(false, "Enemy module must implement damage, death and physical occlusion contract")
		finish()
		return
	var script: Script = load(path) as Script
	if script == null or not script.can_instantiate():
		check(false, "Enemy script must be executable")
		finish()
		return
	var game := ProbeGame.new()
	root.add_child(game)
	game.world = ProbeWorld.new()
	game.add_child(game.world)
	solid(game.world, Vector3(100.0, 0.2, 100.0), Vector3(0.0, -0.1, 0.0), 1)
	game.player = ProbePlayer.new()
	game.player.collision_layer = 2
	game.player.collision_mask = 0
	var player_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.75
	player_shape.shape = capsule
	player_shape.position.y = 0.9
	game.player.add_child(player_shape)
	game.add_child(game.player)
	game.player.position = Vector3(0.0, 0.1, -11.0)
	var enemy: CharacterBody3D = script.new() as CharacterBody3D
	game.add_child(enemy)
	enemy.call("setup", game, "rifle", Vector3(0.0, 0.1, 0.0), 517)
	enemy.connect("died", on_died)
	var initial_health: float = float(enemy.get("health"))
	enemy.call("take_damage", -20.0, Vector3.ZERO, false)
	check(is_equal_approx(float(enemy.get("health")), initial_health), "Negative damage cannot heal an enemy")
	enemy.call("take_damage", NAN, Vector3.ZERO, false)
	check(is_equal_approx(float(enemy.get("health")), initial_health), "Nonfinite damage cannot corrupt enemy health")
	enemy.call("take_damage", 20.0, Vector3(0.0, 1.0, 0.0), false)
	check(is_equal_approx(float(enemy.get("health")), initial_health - 20.0), "Weapon damage is applied exactly once without hidden multiplier")
	enemy.call("take_damage", 999.0, Vector3(0.0, 1.7, 0.0), true)
	enemy.call("take_damage", 999.0, Vector3(0.0, 1.0, 0.0), false)
	check(not bool(enemy.call("is_alive")), "Lethal damage leaves a dead enemy")
	check(death_count == 1 and lethal_headshot, "Death signal occurs exactly once and preserves lethal headshot")
	check(enemy.collision_layer == 0, "Dead bodies cannot block later bullets or movement")
	enemy.queue_free()
	await ticks(2)
	var shooter: CharacterBody3D = script.new() as CharacterBody3D
	game.add_child(shooter)
	shooter.call("setup", game, "rifle", Vector3(0.0, 0.1, 0.0), 29)
	shooter.connect("fired", on_fired)
	var wall: StaticBody3D = solid(game.world, Vector3(70.0, 4.0, 0.7), Vector3(0.0, 1.8, -5.0), 1)
	await ticks(3)
	shooter.call("alert_to", game.player.global_position)
	await ticks(360)
	check(fired_count == 0 and game.player.damage_events == 0, "Opaque world wall prevents attacks despite alert memory")
	wall.queue_free()
	await ticks(3)
	shooter.call("alert_to", game.player.global_position)
	await ticks(12)
	check(fired_count == 0, "Newly exposed target receives a readable preparation interval")
	await ticks(420)
	check(fired_count > 0, "An exposed living target is engaged after preparation")
	check(game.player.damage_events > 0, "Actual player collider can receive ray-confirmed hits")
	var shots_before: int = fired_count
	var damage_before: int = game.player.damage_events
	wall = solid(game.world, Vector3(70.0, 4.0, 0.7), Vector3(0.0, 1.8, -5.0), 1)
	await ticks(3)
	shots_before = fired_count
	damage_before = game.player.damage_events
	await ticks(240)
	check(fired_count == shots_before and game.player.damage_events == damage_before, "New cover cancels an active burst and prevents stale aim hits")
	wall.queue_free()
	game.fighting = false
	await ticks(120)
	check(fired_count == shots_before, "Paused or non-combat game state prevents enemy firing")
	shooter.queue_free()
	await ticks(2)
	game.fighting = true
	game.world.routes_enabled = true
	game.player.position = Vector3(0.0,0.1,-25.0)
	var raiders: Array[CharacterBody3D] = []
	var positions: Array[Vector3] = []
	for i in range(3):
		var raider: CharacterBody3D = script.new() as CharacterBody3D
		game.add_child(raider)
		var role: String = ["rifle","flanker","heavy"][i]
		var point := Vector3(float(i-1)*5.0,0.1,8.0)
		raider.call("setup",game,role,point,220+i)
		raider.call("alert_to",game.player.global_position)
		raiders.append(raider)
		positions.append(point)
		var surfaces: int = 0
		var mesh_count: int = 0
		for child: Node in raider.find_children("*","MeshInstance3D",true,false):
			var visual: MeshInstance3D = child as MeshInstance3D
			surfaces += visual.mesh.get_surface_count()
			mesh_count += 1
		geometry_report.append({"role":role,"mesh_instances":mesh_count,"material_surfaces":surfaces})
	check(float(raiders[2].get("health")) > float(raiders[0].get("health")), "Heavy guard survives more ordinary damage than rifleman")
	await ticks(120)
	for i in range(3):
		var raider: CharacterBody3D = raiders[i]
		check(raider.global_position.distance_to(positions[i]) > 1.0, "Alerted " + str(raider.get("kind")) + " follows supplied ground path")
		check(raider.is_on_floor(), "Moving " + str(raider.get("kind")) + " remains on physical ground")
	check(raiders[1].global_position.distance_to(positions[1]) > raiders[2].global_position.distance_to(positions[2]), "Flanker actually approaches faster than heavy guard")
	var corpse: CharacterBody3D = raiders[2]
	corpse.call("take_damage",999.0,corpse.global_position + Vector3.UP,false)
	await ticks(495)
	check(not is_instance_valid(corpse), "Corpse removes itself before the ten-second limit")
	game.queue_free()
	await ticks(2)
	finish()

func finish() -> void:
	print("ENEMY_PROBE_RESULT ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "shots": fired_count,"geometry":geometry_report}))
	quit(0 if failures.is_empty() else 1)
