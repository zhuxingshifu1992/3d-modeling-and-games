extends CharacterBody3D

signal died
const WeaponRules = preload("res://scripts/weapon_state.gd")
var game: Node
var camera: Camera3D
var shape_node: CollisionShape3D
var capsule: CapsuleShape3D
var weapon_rig: Node3D
var gun_models: Array[Node3D] = []
var flashes: Array[Node3D] = []
var weapons: Array = []
var weapon_index: int = 0
var health: float = 100.0
var armor: float = 35.0
var medkits: int = 2
var stamina: float = 100.0
var sensitivity: float = 1.0
var aiming: bool = false
var crouching: bool = false
var sprinting: bool = false
var look_pitch: float = 0.0
var recoil: float = 0.0
var flash_left: float = 0.0
var step_clock: float = 0.0
var bob_clock: float = 0.0
var heal_cooldown: float = 0.0
var empty_clock: float = 0.0
var dead: bool = false
var switch_lerp: float = 0.0
var sway: Vector2 = Vector2.ZERO
var mats: Dictionary = {}
var detailed_magazine: Node3D
var magazine_rest := Vector3.ZERO

func setup(owner_game: Node, spawn: Vector3) -> void:
	game = owner_game; name = "Player"; global_position = spawn
	collision_layer = 2; collision_mask = 1 | 4
	add_to_group("player")
	floor_snap_length = 0.32; floor_max_angle = deg_to_rad(48.0)
	capsule = CapsuleShape3D.new(); capsule.radius = .31; capsule.height = 1.75
	shape_node = CollisionShape3D.new(); shape_node.shape = capsule; shape_node.position.y = .88; add_child(shape_node)
	camera = Camera3D.new(); camera.name = "Eyes"; camera.position.y = 1.64; camera.fov = 78.0; camera.near = .035; camera.far = 400; add_child(camera)
	weapon_rig = Node3D.new(); camera.add_child(weapon_rig)
	weapon_rig.scale = Vector3.ONE * .83
	for kind in ["rifle", "shotgun"]:
		var w = WeaponRules.new(); w.configure(kind); weapons.append(w)
	_build_viewmodels()
	set_weapon(0)

func _material(key: String, color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	if mats.has(key): return mats[key]
	var m := StandardMaterial3D.new(); m.albedo_color = color; m.roughness = .76; m.metallic = metallic
	mats[key] = m; return m

func _build_viewmodels() -> void:
	for filename in ["r7_view", "shotgun_view"]:
		var asset: PackedScene = load("res://assets/models/detail/" + filename + ".glb")
		var gun: Node3D = asset.instantiate(); weapon_rig.add_child(gun); gun_models.append(gun)
		for child in gun.find_children("*","MeshInstance3D",true,false):
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if filename == "r7_view":
			for child in gun.find_children("Magazine*","Node3D",true,false):
				if child is not MeshInstance3D:
					detailed_magazine = child; magazine_rest = child.position; break
		var f := Node3D.new(); f.position = Vector3(0,.025,-.994 if filename=="r7_view" else -.96); gun.add_child(f); flashes.append(f)
		var burst := MeshInstance3D.new(); var sphere := SphereMesh.new(); sphere.radius = .027; sphere.height = .13; sphere.radial_segments = 10; sphere.rings = 5
		var glow := _material("flash",Color(1,.73,.23)); glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		burst.mesh = sphere; burst.rotation.x = PI/2; burst.material_override = glow; burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; f.add_child(burst); f.visible = false

func current_weapon():
	return weapons[weapon_index]

func set_weapon(index: int) -> void:
	if weapons.is_empty(): return
	weapon_index = posmod(index, weapons.size())
	for i in range(gun_models.size()): gun_models[i].visible = i == weapon_index
	switch_lerp = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if game == null or not game.can_fight(): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var amount: float = .0022 * sensitivity * (.68 if aiming else 1.0)
		rotation.y -= event.relative.x * amount; look_pitch = clampf(look_pitch - event.relative.y * amount, -1.45,1.40)
		sway = Vector2(clampf(event.relative.x,-20,20),clampf(event.relative.y,-20,20)) * .001
	if event.is_action_pressed("reload"): reload_weapon()
	if event.is_action_pressed("heal"): heal()
	if event.is_action_pressed("weapon_1"): set_weapon(0)
	if event.is_action_pressed("weapon_2"): set_weapon(1)
	if event.is_action_pressed("next_weapon"): set_weapon(weapon_index+1)
	if event.is_action_pressed("prev_weapon"): set_weapon(weapon_index-1)

func reload_weapon() -> bool:
	if current_weapon().request_reload(): game.play_sound("reload"); return true
	return false

func heal() -> bool:
	if medkits <= 0 or health >= 100.0 or heal_cooldown > 0.0 or dead: return false
	medkits -= 1; health = minf(100.0,health+45.0); heal_cooldown = 1.5; game.play_sound("heal"); return true

func _physics_process(delta: float) -> void:
	if game == null or not game.can_fight(): return
	for w in weapons: w.advance(delta)
	heal_cooldown = maxf(0.0,heal_cooldown-delta); empty_clock = maxf(0.0,empty_clock-delta)
	var input_vector := Input.get_vector("move_left","move_right","move_forward","move_back")
	var wants_crouch: bool = Input.is_action_pressed("crouch")
	if not wants_crouch and crouching:
		var q := PhysicsRayQueryParameters3D.create(global_position+Vector3(0,1.05,0),global_position+Vector3(0,1.85,0),1)
		wants_crouch = not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	crouching = wants_crouch
	capsule.height = 1.12 if crouching else 1.75; shape_node.position.y = .565 if crouching else .88
	sprinting = Input.is_action_pressed("sprint") and input_vector.y < -.1 and not crouching and stamina > 2.0 and not Input.is_action_pressed("aim")
	aiming = Input.is_action_pressed("aim") and not sprinting and current_weapon().reload_left <= 0.0
	stamina = clampf(stamina + (-25.0 if sprinting else 18.0)*delta,0,100)
	var speed: float = 7.0 if sprinting else (2.3 if crouching else 4.5)
	if aiming: speed *= .72
	if game.state.carrying: speed *= .90
	var direction: Vector3 = (global_transform.basis * Vector3(input_vector.x,0,input_vector.y)).normalized()
	velocity.x = move_toward(velocity.x,direction.x*speed,delta*24.0)
	velocity.z = move_toward(velocity.z,direction.z*speed,delta*24.0)
	if not is_on_floor(): velocity.y -= 18.0*delta
	elif Input.is_action_just_pressed("jump") and not crouching: velocity.y = 5.7
	move_and_slide()
	if global_position.y < -8.0: global_position = Vector3(0,.15,21); velocity = Vector3.ZERO
	var horizontal_speed: float = Vector2(velocity.x,velocity.z).length()
	if horizontal_speed > .5 and is_on_floor():
		step_clock -= delta; bob_clock += delta*(13.5 if sprinting else 9.5)
		if step_clock <= 0.0: game.play_sound("footstep"); step_clock = .32 if sprinting else .47
	else: step_clock = .08
	if Input.is_action_pressed("fire") and not sprinting:
		if current_weapon().trigger():
			game.fire_weapon(self,current_weapon()); recoil = 1.0; flash_left = .05
			look_pitch = clampf(look_pitch + (.017 if weapon_index == 0 else .048)*(0.62 if aiming else 1.0),-1.45,1.40)
		elif current_weapon().ammo == 0 and empty_clock <= 0.0:
			game.play_sound("empty"); empty_clock = .65

func _process(delta: float) -> void:
	if camera == null: return
	var moving: bool = Vector2(velocity.x,velocity.z).length() > .5 and is_on_floor()
	var bob: float = sin(bob_clock)*(.018 if not sprinting else .034) if moving else 0.0
	camera.position.y = lerpf(camera.position.y, (1.02 if crouching else 1.64)+bob, minf(1.0,delta*12.0))
	camera.rotation.x = look_pitch
	camera.fov = lerpf(camera.fov, 57.0 if aiming else (82.0 if sprinting else 78.0),minf(1.0,delta*10.0))
	recoil = move_toward(recoil,0.0,delta*8.0); flash_left = maxf(0.0,flash_left-delta); switch_lerp = move_toward(switch_lerp,0.0,delta*4.0)
	sway = sway.lerp(Vector2.ZERO,minf(1.0,delta*9.0))
	var aim_pos := Vector3(0.0,-.104 if weapon_index==0 else -.075,-.18) if aiming else Vector3(.19,-.19,-.19)
	var reload_offset: float = sin(current_weapon().reload_left/current_weapon().reload_duration*PI) if not weapons.is_empty() else 0.0
	weapon_rig.position = weapon_rig.position.lerp(aim_pos+Vector3(-sway.x,bob*.7-sway.y-.20*switch_lerp,.065*recoil),minf(1.0,delta*14.0))
	weapon_rig.rotation = Vector3(.035*recoil-.15*reload_offset,0,-.72*reload_offset+.2*switch_lerp)
	if is_instance_valid(detailed_magazine): detailed_magazine.position = magazine_rest + Vector3(0,-.11*reload_offset if weapon_index==0 else 0.0,0)
	for i in range(flashes.size()): flashes[i].visible = i == weapon_index and flash_left > 0.0

func take_damage(amount: float, source: Vector3) -> void:
	if dead or game == null or not game.can_fight(): return
	var blocked: float = minf(armor,amount*.6); armor -= blocked; health = maxf(0,health-(amount-blocked))
	var local_dir: Vector3 = global_transform.basis.inverse()*(source-global_position)
	game.hud.damage_flash(atan2(local_dir.x,-local_dir.z)); game.play_sound("hit")
	if health <= 0.0: dead = true; died.emit()

func is_alive() -> bool:
	return not dead and health > 0.0

func add_supplies(kind: String) -> void:
	match kind:
		"ammo":
			weapons[0].reserve += 48; weapons[1].reserve += 6
		"medkit": medkits = mini(medkits+1,5)
		"armor": armor = minf(75.0,armor+35.0)
