extends SceneTree
## Main-scene integration: actual player, weapons, enemies, static world and UI.
## Test mode is selected after ready; no automatic QA camera or shooting runs.

var game: Variant
var errors: Array[String] = []
var checks: int = 0
var stage: String = "load"

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		errors.append(stage + ": " + label)
		print("PLAYER_PROBE_FAIL ", stage, ": ", label)

func ticks(count: int) -> void:
	for index in range(count):
		await physics_frame
	await process_frame

func release_controls() -> void:
	for action: String in ["move_forward","move_back","move_left","move_right","fire","aim","interact","jump","sprint","crouch","heal","reload","weapon_1","weapon_2","pause_game"]:
		Input.action_release(action)

func key_action(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame

func stop_enemy_ai() -> void:
	for enemy: Node in game.enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)

func place_player(point: Vector3, yaw: float = 0.0) -> void:
	release_controls()
	game.player.global_position = point
	game.player.rotation.y = yaw
	game.player.look_pitch = 0.0
	game.player.velocity = Vector3.ZERO
	await ticks(5)

func aim_at(point: Vector3) -> void:
	var direction: Vector3 = point - game.player.camera.global_position
	game.player.rotation.y = atan2(-direction.x, -direction.z)
	game.player.look_pitch = atan2(direction.y, Vector2(direction.x,direction.z).length())
	Input.action_press("aim")
	await ticks(12)

func one_round() -> void:
	game.player.current_weapon().cooldown = 0.0
	Input.action_press("fire")
	await ticks(2)
	Input.action_release("fire")
	await ticks(2)

func run() -> void:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	if scene == null:
		expect(false,"main scene loads")
		finish()
		return
	game = scene.instantiate()
	root.add_child(game)
	current_scene = game
	# ready begins in the menu. Switch to a non-automatic, non-persistent test mode.
	game.qa = true
	game.qa_mode = "integration"
	game.difficulty = "standard"
	game._begin("power")
	stop_enemy_ai()
	await ticks(3)
	expect(game.can_fight(),"main scene starts a live operation")
	expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"integration probe does not capture desktop input")

	stage = "W movement"
	await place_player(Vector3(0.0,0.15,18.0))
	var beginning: Vector3 = game.player.global_position
	Input.action_press("move_forward")
	await ticks(60)
	Input.action_release("move_forward")
	await ticks(18)
	var finish_position: Vector3 = game.player.global_position
	expect(beginning.z - finish_position.z > 3.5,"W moves the real character forward")
	expect(absf(finish_position.x - beginning.x) < 0.12,"W does not introduce sideways drift")
	expect(game.player.is_on_floor(),"moving character remains supported by the yard")

	stage = "solid wall collision"
	await place_player(Vector3(5.0,0.15,0.0),-PI/2.0)
	Input.action_press("move_forward")
	await ticks(95)
	Input.action_release("move_forward")
	await ticks(12)
	expect(game.player.global_position.x > 6.25,"character reaches the office wall")
	expect(game.player.global_position.x < 6.72,"office collision stops W movement before entering the building")

	stage = "ADS ray hit"
	for enemy: Node in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	await ticks(3)
	var target: Variant = game._spawn_enemy("rifle",Vector3(0.0,0.12,-2.0))
	target.set_physics_process(false)
	await place_player(Vector3(0.0,0.15,8.0))
	await aim_at(target.global_position + Vector3.UP * 1.06)
	expect(game.player.aiming,"right-button action activates ADS in the player")
	var before_health: float = target.health
	var before_ammo: int = game.player.current_weapon().ammo
	var before_hits: int = game.state.hits
	await one_round()
	expect(is_equal_approx(float(target.health),before_health - 24.0),"camera aim deals exactly one rifle body hit to the real enemy collider")
	expect(game.player.current_weapon().ammo == before_ammo - 1,"successful fire consumes exactly one cartridge")
	expect(game.state.hits == before_hits + 1,"real hit updates the mission accuracy statistics")

	stage = "wall blocks gun ray"
	target.global_position = Vector3(17.0,0.12,0.0)
	await place_player(Vector3(5.0,0.15,0.0))
	await aim_at(target.global_position + Vector3.UP * 1.06)
	before_health = target.health
	before_hits = game.state.hits
	await one_round()
	expect(is_equal_approx(float(target.health),before_health),"office stops a shot aimed at an enemy behind its solid shell")
	expect(game.state.hits == before_hits,"blocked shots do not count as enemy hits")
	release_controls()

	stage = "reload"
	var rifle: Variant = game.player.current_weapon()
	rifle.ammo = 2
	rifle.reserve = 3
	rifle.cooldown = 0.0
	await key_action("reload")
	expect(rifle.reload_left > 0.0,"R begins the actual player reload")
	var before_shots: int = game.state.shots
	Input.action_press("fire")
	await ticks(12)
	Input.action_release("fire")
	expect(rifle.ammo == 2 and game.state.shots == before_shots,"reload prevents firing and conserves loaded rounds")
	await ticks(130)
	expect(rifle.ammo == 5 and rifle.reserve == 0,"reload transfers limited reserve without inventing cartridges")

	stage = "weapon switching"
	await key_action("weapon_2")
	expect(game.player.weapon_index == 1 and game.player.current_weapon().kind == "shotgun","2 selects the real shotgun and its rules")
	expect(not game.player.gun_models[0].visible and game.player.gun_models[1].visible,"weapon switch updates visible viewmodels")
	await key_action("weapon_1")
	expect(game.player.weapon_index == 0 and game.player.current_weapon() == rifle,"1 returns to the same rifle inventory")

	stage = "healing"
	game.player.health = 40.0
	game.player.medkits = 2
	game.player.heal_cooldown = 0.0
	await key_action("heal")
	expect(is_equal_approx(float(game.player.health),85.0) and game.player.medkits == 1,"Q restores 45 health and consumes one medkit")
	await key_action("heal")
	expect(is_equal_approx(float(game.player.health),85.0) and game.player.medkits == 1,"healing cooldown prevents a second immediate use")

	stage = "pause"
	rifle.ammo = 1
	rifle.reserve = 10
	rifle.reload_left = 0.0
	await key_action("reload")
	await key_action("pause_game")
	expect(paused,"Escape pauses the actual scene through the game handler")
	var paused_health: float = game.player.health
	var paused_armor: float = game.player.armor
	var paused_reload: float = rifle.reload_left
	var paused_elapsed: float = game.state.elapsed
	var paused_position: Vector3 = game.player.global_position
	before_ammo = rifle.ammo
	game.player.take_damage(25.0,Vector3.ZERO)
	Input.action_press("fire")
	Input.action_press("move_forward")
	await ticks(70)
	expect(is_equal_approx(float(game.player.health),paused_health) and is_equal_approx(float(game.player.armor),paused_armor),"damage cannot update health or armor while paused")
	expect(is_equal_approx(float(rifle.reload_left),paused_reload) and rifle.ammo == before_ammo,"pause freezes reload and firing")
	expect(is_equal_approx(float(game.state.elapsed),paused_elapsed),"pause freezes mission elapsed time")
	expect(game.player.global_position.is_equal_approx(paused_position),"pause freezes movement despite held W")
	release_controls()
	await key_action("pause_game")
	expect(not paused and game.can_fight(),"Escape resumes the operation")
	await ticks(8)
	expect(rifle.reload_left < paused_reload,"reload resumes only after returning to play")

	stage = "restart"
	var previous_player: int = game.player.get_instance_id()
	game._restart()
	stop_enemy_ai()
	await ticks(3)
	expect(game.player.get_instance_id() != previous_player and game.player.is_alive(),"restart replaces the previous character with a living player")
	expect(game.player.current_weapon().ammo == 24 and is_equal_approx(float(game.player.health),100.0),"restart restores full starting health and loaded rifle")
	expect(game.state.phase == "power" and game.player.camera.current,"restart restores first objective and the active FPS camera")
	release_controls()
	# A fixed-FPS probe simulates seconds faster than the audio mixing thread.
	# Stop live voices explicitly, then allow pending mixer releases to drain.
	game.running = false
	game.audio_bank.set_ambience(false)
	for voice: Node in game.audio_bank.get_children():
		if voice is AudioStreamPlayer or voice is AudioStreamPlayer3D:
			voice.call("stop")
			voice.set("stream",null)
	OS.delay_msec(150)
	game.queue_free()
	await ticks(3)
	game = null
	call_deferred("finish")

func finish() -> void:
	print("PLAYER_PROBE_RESULT ",JSON.stringify({"passed":errors.is_empty(),"checks":checks,"errors":errors,"coverage":"actual main scene, physics, camera ray, UI input actions; headless only"}))
	quit(0 if errors.is_empty() else 1)
