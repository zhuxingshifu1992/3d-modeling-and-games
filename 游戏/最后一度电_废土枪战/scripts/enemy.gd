extends CharacterBody3D
## Ground-level raiders. Geometry is shared by role, batched by material, and
## articulated at real shoulder/hip/knee joints. All gun hits use physics rays.

signal died(enemy: CharacterBody3D, headshot: bool)
signal fired(origin: Vector3, target: Vector3)

var game: Node
var kind: String = "rifle"
var health: float = 80.0
var dead: bool = false
var damage_multiplier: float = 1.0
var accuracy_multiplier: float = 1.0

static var _materials: Dictionary = {}



var _rng := RandomNumberGenerator.new()
var _spawn := Vector3.ZERO
var _last_known := Vector3.ZERO
var _destination := Vector3.ZERO
var _path := PackedVector3Array()
var _path_index: int = 0
var _path_clock: float = 0.0
var _decision_clock: float = 0.0
var _sense_clock: float = 0.0
var _alert_memory: float = 0.0
var _patrol_clock: float = 0.0
var _flank_sign: float = 1.0
var _stuck_clock: float = 0.0
var _stuck_origin := Vector3.ZERO
var _recovery_goal := Vector3.INF
var _recovery_clock: float = 0.0
var _move_speed: float = 2.25
var _preferred_range: float = 13.0
var _maximum_range: float = 25.0
var _round_damage: float = 5.0
var _spread: float = 0.041
var _burst_size: int = 3
var _round_interval: float = 0.28
var _recovery_interval: float = 2.0
var _preparation: float = 0.62
var _burst_left: int = 0
var _aim_clock: float = -1.0
var _shot_clock: float = 0.3
var _aim_point := Vector3.ZERO
var _visible_player: bool = false
var _configured: bool = false
var _walk_phase: float = 0.0
var _raise_blend: float = 0.0
var _flash_clock: float = 0.0
var _hit_clock: float = 0.0
var _hit_side: float = 0.0
var _dead_clock: float = 0.0
var _death_sign: float = 1.0
var _visual: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _gun: Node3D
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _forearms: Array[Node3D] = []
var _detailed: bool = false
var _muzzle: MeshInstance3D
var _warning: MeshInstance3D
var _flash_light: OmniLight3D
var _body_shape: CollisionShape3D


func setup(game_ref: Node, role: String, start: Vector3, seed_value: int) -> void:
	if _configured:
		return
	_configured = true
	game = game_ref
	kind = role if role in ["rifle", "flanker", "heavy"] else "rifle"
	_rng.seed = seed_value
	global_position = start
	_spawn = start
	_last_known = start
	_destination = start
	_stuck_origin = start
	_flank_sign = -1.0 if seed_value % 2 == 0 else 1.0
	_death_sign = _flank_sign
	rotation.y = _rng.randf_range(-PI, PI)
	_patrol_clock = _rng.randf_range(0.3, 1.1)
	_decision_clock = _rng.randf_range(0.0, 0.25)
	if kind == "flanker":
		health = 62.0
		_move_speed = 3.05
		_preferred_range = 7.5
		_maximum_range = 19.0
		_round_damage = 4.0
		_spread = 0.055
		_burst_size = 2
		_round_interval = 0.25
		_recovery_interval = 1.75
		_preparation = 0.52
	elif kind == "heavy":
		health = 155.0
		_move_speed = 1.55
		_preferred_range = 15.0
		_maximum_range = 28.0
		_round_damage = 6.5
		_spread = 0.049
		_burst_size = 4
		_round_interval = 0.38
		_recovery_interval = 2.65
		_preparation = 0.88
	for property: Dictionary in game.get_property_list():
		if str(property.name) == "difficulty" and str(game.get("difficulty")) == "easy":
			damage_multiplier = 0.68
			accuracy_multiplier = 0.78
			_preparation += 0.2
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	safe_margin = 0.015
	_body_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.75
	_body_shape.shape = capsule
	_body_shape.position.y = 0.9
	add_child(_body_shape)
	add_to_group("enemies")
	_build_humanoid()


func is_alive() -> bool:
	return _configured and not dead and health > 0.0


func take_damage(amount: float, hit_position: Vector3, headshot: bool = false) -> void:
	if not is_alive() or not is_finite(amount) or amount <= 0.0:
		return
	# The weapon already applies headshot multipliers. Never multiply a second time.
	health = maxf(0.0, health - amount)
	_hit_clock = 0.25
	_hit_side = clampf(to_local(hit_position).x, -0.2, 0.2)
	var player: Node3D = _player()
	if is_instance_valid(player):
		alert_to(player.global_position)
	if health <= 0.0:
		dead = true
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		_body_shape.set_deferred("disabled", true)
		remove_from_group("enemies")
		add_to_group("enemy_corpses")
		_burst_left = 0
		_aim_clock = -1.0
		_muzzle.visible = false
		_warning.visible = false
		_flash_light.visible = false
		died.emit(self, headshot)


func alert_to(point: Vector3) -> void:
	if not is_alive() or not point.is_finite():
		return
	_last_known = point
	_alert_memory = maxf(_alert_memory, 10.0)
	_decision_clock = 0.0
	_path_clock = 0.0


func _player() -> Node3D:
	if not is_instance_valid(game):
		return null
	return game.get("player") as Node3D


func _world() -> Node3D:
	if not is_instance_valid(game):
		return null
	return game.get("world") as Node3D


func _combat_allowed() -> bool:
	return is_instance_valid(game) and game.has_method("can_fight") and bool(game.call("can_fight"))


func _physics_process(delta: float) -> void:
	if not _configured:
		return
	if dead:
		_dead_clock += delta
		var fall: float = smoothstep(0.0, 0.68, _dead_clock)
		_visual.rotation.x = fall * 1.49 * _death_sign
		_visual.rotation.z = fall * 0.12 * _flank_sign
		_visual.position.y = fall * 0.13
		if _dead_clock > 8.0:
			queue_free()
		return
	_hit_clock = maxf(0.0, _hit_clock - delta)
	_flash_clock = maxf(0.0, _flash_clock - delta)
	_muzzle.visible = _flash_clock > 0.0
	_flash_light.visible = _muzzle.visible
	if not _combat_allowed():
		velocity = Vector3.ZERO
		_burst_left = 0
		_aim_clock = -1.0
		_warning.visible = false
		_animate(delta, false)
		return
	var player: Node3D = _player()
	if not is_instance_valid(player) or not bool(player.call("is_alive")):
		velocity = Vector3.ZERO
		_animate(delta, false)
		return
	_alert_memory = maxf(0.0, _alert_memory - delta)
	_sense_clock -= delta
	_path_clock -= delta
	_decision_clock -= delta
	_patrol_clock -= delta
	_recovery_clock = maxf(0.0, _recovery_clock - delta)
	_shot_clock = maxf(0.0, _shot_clock - delta)
	var difference: Vector3 = player.global_position - global_position
	var horizontal := Vector3(difference.x, 0.0, difference.z)
	var distance: float = horizontal.length()
	if _sense_clock <= 0.0:
		_sense_clock = 0.13
		_visible_player = distance < 31.0 and _has_line_of_sight(player)
		var attention: float = (-global_basis.z).dot(horizontal.normalized()) if distance > 0.01 else 1.0
		if _visible_player and (_alert_memory > 0.0 or distance < 5.0 or attention > 0.12):
			_last_known = player.global_position
			_alert_memory = 9.0
	var alert: bool = _alert_memory > 0.0
	var can_attack: bool = alert and _visible_player and distance <= _maximum_range
	var holding: bool = can_attack and distance >= 7.0 and distance <= _preferred_range + 5.0
	if kind == "flanker":
		holding = can_attack and distance <= 9.5 and _shot_clock < 0.8
	if _decision_clock <= 0.0:
		_decision_clock = _rng.randf_range(0.65, 1.0)
		_choose_destination(player, alert, distance, holding)
	var desired := Vector3.ZERO
	if not holding or (kind == "flanker" and _aim_clock < 0.0 and _burst_left == 0 and _shot_clock > 0.8):
		desired = _navigation_velocity(alert)
	if _aim_clock >= 0.0 or _burst_left > 0:
		desired *= 0.1
	velocity.x = move_toward(velocity.x, desired.x, delta * 8.0)
	velocity.z = move_toward(velocity.z, desired.z, delta * 8.0)
	velocity.y = -1.0 if is_on_floor() else maxf(velocity.y - 18.0 * delta, -28.0)
	move_and_slide()
	_track_stuck(delta, desired)
	var facing: Vector3 = horizontal if alert else Vector3(velocity.x, 0.0, velocity.z)
	if facing.length_squared() > 0.01:
		var target_yaw: float = atan2(-facing.x, -facing.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * (5.5 if alert else 2.4)))
	_attack(delta, can_attack and holding, player)
	_animate(delta, alert)


func _choose_destination(player: Node3D, alert: bool, distance: float, holding: bool) -> void:
	if _recovery_clock > 0.0 and _recovery_goal.is_finite():
		_destination = _recovery_goal
	elif not alert:
		if _patrol_clock <= 0.0:
			_patrol_clock = _rng.randf_range(3.5, 6.0)
			var angle: float = _rng.randf_range(-PI, PI)
			var candidate: Vector3 = _spawn + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(2.0, 5.0)
			_destination = candidate if _walkable(candidate) else _spawn
	elif distance < 7.0 and kind != "flanker":
		var away: Vector3 = global_position - player.global_position
		away.y = 0.0
		_destination = global_position + away.normalized() * 4.0 + Vector3(away.z, 0.0, -away.x).normalized() * _flank_sign * 1.5
	elif kind == "flanker" and distance > 7.0:
		var approach: Vector3 = (_last_known - global_position).normalized()
		var side := Vector3(approach.z, 0.0, -approach.x)
		_destination = _last_known + side * _flank_sign * minf(7.0, distance * 0.4)
	elif holding:
		_destination = global_position
	else:
		_destination = _last_known
		# Cover candidates are navigation points, never permission to shoot a wall.
		var world: Node3D = _world()
		if is_instance_valid(world) and world.has_method("get_cover_points") and kind != "flanker":
			var candidates: Array = world.call("get_cover_points")
			var best_cost: float = INF
			for value: Variant in candidates:
				if not value is Vector3:
					continue
				var point: Vector3 = value
				var travel: float = global_position.distance_to(point)
				var target_distance: float = player.global_position.distance_to(point)
				if travel > 9.0 or travel < 1.5 or target_distance < 6.0 or target_distance > 23.0:
					continue
				var cost: float = travel + absf(target_distance - _preferred_range) * 0.6
				if cost < best_cost and _ray_clear(point + Vector3.UP * 1.48, player.global_position + Vector3.UP * 1.12, player):
					best_cost = cost
					_destination = point
	_destination.y = global_position.y
	if _path_clock <= 0.0:
		_repath()


func _walkable(point: Vector3) -> bool:
	var world: Node3D = _world()
	return is_instance_valid(world) and world.has_method("is_walkable") and bool(world.call("is_walkable", point))


func _repath() -> void:
	_path_clock = _rng.randf_range(0.6, 0.95)
	_path_index = 0
	_path.clear()
	var world: Node3D = _world()
	if is_instance_valid(world) and world.has_method("find_path"):
		var result: Variant = world.call("find_path", global_position, _destination)
		if result is PackedVector3Array:
			_path = result


func _navigation_velocity(alert: bool) -> Vector3:
	while _path_index < _path.size():
		var difference: Vector3 = _path[_path_index] - global_position
		difference.y = 0.0
		if difference.length_squared() < 0.22:
			_path_index += 1
		else:
			return difference.normalized() * _move_speed * (1.0 if alert else 0.45)
	return Vector3.ZERO


func _track_stuck(delta: float, desired: Vector3) -> void:
	if desired.length_squared() < 0.2:
		_stuck_clock = 0.0
		_stuck_origin = global_position
		return
	_stuck_clock += delta
	if _stuck_clock < 0.9:
		return
	var traveled: Vector3 = global_position - _stuck_origin
	traveled.y = 0.0
	if traveled.length() < 0.22:
		var lateral: Vector3 = Vector3(desired.z, 0.0, -desired.x).normalized() * _flank_sign
		for sign_value: float in [1.0, -1.0]:
			var candidate: Vector3 = global_position + lateral * sign_value * 1.8 - desired.normalized() * 0.6
			if _walkable(candidate):
				_recovery_goal = candidate
				_recovery_clock = 1.3
				_destination = candidate
				_repath()
				break
		_flank_sign *= -1.0
	_stuck_clock = 0.0
	_stuck_origin = global_position


func _has_line_of_sight(player: Node3D) -> bool:
	return _ray_clear(global_position + Vector3.UP * 1.5, player.global_position + Vector3.UP * 1.12, player)


func _ray_clear(origin: Vector3, target: Vector3, player: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 2 | 4)
	query.exclude = [get_rid()]
	query.hit_from_inside = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player


func _attack(delta: float, allowed: bool, player: Node3D) -> void:
	# Recheck every attack tick, including an already committed burst: no stale LOS.
	if not allowed or not _has_line_of_sight(player):
		_burst_left = 0
		_aim_clock = -1.0
		_warning.visible = false
		_shot_clock = maxf(_shot_clock, 0.18)
		return
	if _aim_clock >= 0.0:
		_aim_clock -= delta
		_warning.visible = true
		if _aim_clock > 0.16:
			_aim_point = player.global_position + Vector3.UP * 1.12
		if _aim_clock <= 0.0:
			_aim_clock = -1.0
			_burst_left = _burst_size
			_fire_round(player)
	elif _burst_left > 0:
		_warning.visible = false
		if _shot_clock <= 0.0:
			_fire_round(player)
	elif _shot_clock <= 0.0:
		_aim_clock = _preparation + _rng.randf_range(0.0, 0.18)
		_aim_point = player.global_position + Vector3.UP * 1.12
		_warning.visible = true


func _fire_round(player: Node3D) -> void:
	var origin: Vector3 = _gun.to_global(Vector3(0.0, 0.019, -0.795))
	if not _combat_allowed() or not _ray_clear(origin, player.global_position + Vector3.UP * 1.12, player):
		_burst_left = 0
		_shot_clock = 0.45
		return
	# Last 160ms of aim are committed. Strafing can dodge even a well-aimed burst.
	var distance: float = origin.distance_to(_aim_point)
	var spread_radius: float = maxf(0.11, distance * _spread / maxf(0.2, accuracy_multiplier))
	var right: Vector3 = (_aim_point - origin).cross(Vector3.UP).normalized()
	var aim: Vector3 = _aim_point + right * _rng.randf_range(-spread_radius, spread_radius) + Vector3.UP * _rng.randf_range(-spread_radius * 0.7, spread_radius * 0.7)
	var target: Vector3 = origin + (aim - origin).normalized() * 40.0
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 2 | 4)
	query.exclude = [get_rid()]
	query.hit_from_inside = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		target = hit.get("position", target)
		if hit.get("collider") == player:
			player.call("take_damage", _round_damage * damage_multiplier, global_position)
	_flash_clock = 0.055
	_muzzle.visible = true
	_flash_light.visible = true
	_muzzle.rotation.z = _rng.randf_range(-PI, PI)
	if game.has_method("play_sound"):
		game.call("play_sound", "enemy_shot", origin)
	if game.has_method("spawn_tracer"):
		game.call("spawn_tracer", origin, target, Color(1.0, 0.52, 0.19, 0.85))
	fired.emit(origin, target)
	_burst_left -= 1
	_shot_clock = _round_interval if _burst_left > 0 else _recovery_interval + _rng.randf_range(0.0, 0.7)
	_aim_point = player.global_position + Vector3.UP * 1.12
	if _burst_left == 0:
		_warning.visible = false


func _animate(delta: float, alert: bool) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	_walk_phase += delta * speed * 4.3
	var stride: float = clampf(speed / maxf(0.1, _move_speed), 0.0, 1.0)
	_raise_blend = move_toward(_raise_blend, 1.0 if alert else 0.0, delta * 3.8)
	_hips.position.y = 0.9 + absf(sin(_walk_phase)) * 0.025 * stride
	_torso.rotation.x = -0.07 * stride - (_hit_clock * 0.7)
	_torso.rotation.z = sin(_walk_phase) * 0.025 * stride + _hit_side * _hit_clock * 2.0
	_head.rotation.x = _hit_clock * 0.75
	_gun.rotation.x = lerpf(-0.45, 0.0, _raise_blend) - _flash_clock * 1.2
	for i in range(2):
		var wave: float = sin(_walk_phase + float(i) * PI)
		_legs[i].rotation.x = wave * 0.55 * stride
		_knees[i].rotation.x = maxf(0.0, -wave) * 0.56 * stride
		if _detailed:
			_pose_arm(i)
		else:
			_arms[i].rotation.x = lerpf(0.26 + wave * 0.20 * stride, 0.75 + wave * 0.06 * stride, _raise_blend)
			_arms[i].rotation.z = 0.34 if i == 1 else -0.54

func _pose_arm(index: int) -> void:
	var upper: Node3D = _arms[index]
	var lower: Node3D = _forearms[index]
	var grip: Vector3 = Vector3(.037,-.103,.043) if index==1 else Vector3(-.032,-.053,-.42)
	var target: Vector3 = _gun.to_global(grip*.80)
	var start: Vector3 = upper.global_position
	var offset: Vector3 = target-start
	var distance: float = clampf(offset.length(),.025,.274+.276-.001)
	var direction: Vector3 = offset.normalized()
	var preferred: Vector3 = _torso.global_basis * Vector3(-.16 if index==0 else .16,-.32,.16)
	var bend: Vector3 = (preferred-direction*preferred.dot(direction)).normalized()
	var along: float = (.275*.275-.276*.276+distance*distance)/(2*distance)
	var height: float = sqrt(maxf(0.0,.275*.275-along*along))
	var elbow: Vector3 = start+direction*along+bend*height
	var local_upper: Vector3 = upper.get_parent().global_basis.inverse()*(elbow-start)
	upper.quaternion = Quaternion(Vector3.DOWN,local_upper.normalized())
	var local_lower: Vector3 = upper.global_basis.inverse()*(target-lower.global_position)
	lower.quaternion = Quaternion(Vector3.DOWN,local_lower.normalized())


static func _mat(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var colors: Dictionary = {"cloth":Color("625b45"),"flankcloth":Color("473b32"),"heavycloth":Color("3e493a"),
		"plate":Color("444a43"),"metal":Color("65665b"),"black":Color("202525"),"rust":Color("835033"),
		"band":Color("a25236"),"goggle":Color("82663c"),"glove":Color("85715a"),"flash":Color(1.0,0.62,0.15),"warning":Color(1.0,0.35,0.08)}
	var material := StandardMaterial3D.new()
	material.albedo_color = colors.get(key, Color.GRAY)
	material.roughness = 0.9
	if key in ["plate","metal","black"]:
		material.metallic = 0.45 if key != "black" else 0.18
		material.roughness = 0.67
	if key in ["flash","warning"]:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 2.5 if key == "flash" else 1.0
	_materials[key] = material
	return material


func _find_joint(node: Node, key: String) -> Node3D:
	if node is Node3D and node is not MeshInstance3D and String(node.name).begins_with(key): return node
	for child in node.get_children():
		var found: Node3D = _find_joint(child,key)
		if found != null: return found
	return null

func _build_humanoid() -> void:
	var asset: PackedScene = load("res://assets/models/detail/raider_"+kind+".glb")
	_visual = asset.instantiate(); _visual.name = "DetailedRaider_"+kind; add_child(_visual)
	_hips = _find_joint(_visual,"Hips"); _torso = _find_joint(_visual,"Torso"); _head = _find_joint(_visual,"Head"); _gun = _find_joint(_visual,"WeaponPivot")
	for side in ["Left","Right"]:
		_legs.append(_find_joint(_visual,side+"Thigh")); _knees.append(_find_joint(_visual,side+"Shin")); _arms.append(_find_joint(_visual,side+"Arm")); _forearms.append(_find_joint(_visual,side+"Forearm"))
	_detailed = true
	_muzzle = MeshInstance3D.new(); var flash := SphereMesh.new(); flash.radius=.035; flash.height=.07; flash.radial_segments=8; flash.rings=4
	_muzzle.mesh=flash; _muzzle.material_override=_mat("flash"); _muzzle.scale=Vector3(.65,.65,2.2); _muzzle.position=Vector3(0,.019,-.795); _muzzle.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _muzzle.visible=false; _gun.add_child(_muzzle)
	_warning=MeshInstance3D.new(); var warning_mesh:=SphereMesh.new(); warning_mesh.radius=.015; warning_mesh.height=.03; warning_mesh.radial_segments=8; warning_mesh.rings=4
	_warning.mesh=warning_mesh; _warning.material_override=_mat("warning"); _warning.position=Vector3(0,.1,-.13); _warning.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _warning.visible=false; _gun.add_child(_warning)
	_flash_light=OmniLight3D.new(); _flash_light.light_color=Color(1,.56,.23); _flash_light.light_energy=.8; _flash_light.omni_range=1.8; _flash_light.shadow_enabled=false; _flash_light.position=_muzzle.position; _flash_light.visible=false; _gun.add_child(_flash_light)
	_animate(0.0,false)
