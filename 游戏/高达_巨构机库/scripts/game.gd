extends Node3D

const Catalog = preload("res://scripts/catalog.gd")
const Player = preload("res://scripts/player.gd")
const Bay = preload("res://scripts/bay.gd")
const HUD = preload("res://scripts/hud.gd")
const Profile = preload("res://scripts/profile.gd")
var catalog: Array[Dictionary]
var bays: Array = []
var player
var hud
var audio
var world: Node3D
var profile
var started := false
var paused := false
var transition := false
var riding = null
var seated_bay = null
var target_index := 0
var nearest_bay = null
var interaction := ""
var interaction_bay = null
var _save_warning := false
var _motion_tween: Tween
var _transfer_generation := 0
var _alignment_active := false
var automated_test := DisplayServer.get_name() == "headless" or "--automated-test" in OS.get_cmdline_user_args()

func _set_mouse_mode(mode: int) -> void:
	# Automated scene transitions must not acquire, warp, hide, or release the desktop cursor.
	if not automated_test:
		_apply_mouse_mode(mode)

func _apply_mouse_mode(mode: int) -> void:
	Input.mouse_mode = mode

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if automated_test:
		get_window().unfocusable = true
	_register_inputs()
	catalog = Catalog.machines()
	profile = Profile.new()
	profile.read()
	world = load("res://scripts/world.gd").new()
	add_child(world)
	world.build(catalog)
	for data in catalog:
		var bay = Bay.new()
		add_child(bay)
		bay.setup(data)
		bay.bind_machine(world.get_node_or_null(str(data.id)))
		bays.append(bay)
	player = Player.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	if automated_test:
		player.set_process_unhandled_input(false)
	player.set_view(Vector3(0, 0.2, 46), 0.67, 0.30)
	player.sensitivity = float(profile.settings.sensitivity) * 0.0021
	player.camera.fov = float(profile.settings.fov)
	audio = load("res://scripts/audio.gd").new()
	audio.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(audio)
	audio.set_muted(not bool(profile.settings.sound))
	player.footstep.connect(func(): audio.play("step"))
	hud = HUD.new()
	add_child(hud)
	hud.build(catalog)
	hud.sync_settings(profile.settings)
	hud.start_pressed.connect(start)
	hud.resume_pressed.connect(resume)
	hud.home_pressed.connect(return_to_entry)
	hud.quit_pressed.connect(quit_game)
	hud.bay_selected.connect(select_bay)
	hud.setting_changed.connect(change_setting)
	_set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_window().min_size = Vector2i(960, 600)
	if "--low" in OS.get_cmdline_user_args():
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		for light in world.find_children("*", "Light3D", true, false):
			light.shadow_enabled = false
		for bay in bays:
			bay.monitor_viewport.size = Vector2i(640, 216) if bay.panorama else Vector2i(384, 216)

func _register_inputs() -> void:
	var keys := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "sprint": KEY_SHIFT, "crouch": KEY_CTRL, "interact": KEY_E, "lamp": KEY_F, "guide": KEY_TAB, "pause": KEY_ESCAPE, "hide_ui": KEY_F2, "exit_cabin": KEY_Q}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)

func start() -> void:
	started = true
	paused = false
	get_tree().paused = false
	player.enabled = true
	player.look_enabled = true
	player.set_view(Vector3(0, 0.15, 46), 0.40, 0.16)
	hud.show_game()
	_set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hud.toast("驾驶员，欢迎进入机库。跟随导航前往 %s 泊位。" % catalog[target_index].bay, 6.0)
	audio.play("button")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if not started:
			hud.show_menu()
		elif paused:
			resume()
		else:
			pause_game()
		get_viewport().set_input_as_handled()
		return
	if not started or paused:
		return
	if event.is_action_pressed("guide"):
		pause_game(true)
	elif event.is_action_pressed("lamp"):
		player.lamp.visible = not player.lamp.visible
	elif event.is_action_pressed("hide_ui"):
		hud.game_ui.visible = not hud.game_ui.visible
	elif event.is_action_pressed("exit_cabin") and seated_bay != null and not transition:
		exit_cockpit()
	elif event.is_action_pressed("interact") and not transition:
		interact()

func _physics_process(delta: float) -> void:
	if paused or not is_instance_valid(player):
		return
	for bay in bays:
		var was_moving: bool = bay.state.moving
		var change: float = bay.state.advance(delta)
		bay.tick(delta)
		if riding == bay:
			player.global_position.y += change
			if was_moving and not bay.state.moving:
				player.global_position.y = bay.state.y + 0.15
				player.enabled = true
				riding = null
				audio.elevator(false)
				audio.play("success")
				hud.toast("已到登舱层。沿检修桥走向舱门。" if bay.state.at_top else "已返回地面。可继续观摩其他机体。")
	if started:
		_update_interaction()
		_update_hud()
		if player.global_position.y < -4:
			return_to_entry()

func _update_interaction() -> void:
	interaction = ""
	interaction_bay = null
	var nearest := INF
	for bay in bays:
		var distance: float = player.global_position.distance_to(bay.global_position)
		if distance < nearest:
			nearest = distance
			nearest_bay = bay
	if transition:
		return
	if seated_bay != null:
		interaction = "boot" if seated_bay.state.boot_stage < 3 else "exit"
		interaction_bay = seated_bay
		return
	if riding != null:
		return
	for bay in bays:
		if bay.on_platform(player.global_position):
			interaction = "lift"
			interaction_bay = bay
			return
		if bay.near_hatch(player.global_position):
			interaction_bay = bay
			if not bay.state.hatch_open:
				interaction = "hatch"
			elif bay.door_amount > (0.999 if bay.compact else 0.92):
				interaction = "board"
			else:
				interaction = "opening"
			return
		if bay.compact and bay.cockpit.has("entry_half_width"):
			var p: Vector3 = bay.to_local(player.global_position)
			if absf(p.x) < 0.9 and absf(p.y - bay.top_y - 0.12) < 0.6 and p.z > bay.portal_z - 2.8 and p.z < bay.portal_z + 0.4:
				# Center on the wide fixed bridge before using the narrow armor opening.
				if _can_align_on_bridge(bay):
					interaction = "align_assist"
					interaction_bay = bay
				else:
					interaction = "align"
				return

func _can_align_on_bridge(bay) -> bool:
	var p: Vector3 = bay.to_local(player.global_position)
	var bridge_end := float(bay.cockpit.get("bridge_end_z", bay.portal_z))
	var guard_z := float(bay.cockpit.get("gate_z", bay.portal_z))
	# The 28 cm capsule must stay on the fixed deck and outside the armor guard.
	return bay.state.at_top and not bay.state.moving and absf(p.x) < 0.70 and p.z <= minf(bridge_end - 0.28, guard_z - 0.30)

func align_for_hatch(bay) -> void:
	if not _can_align_on_bridge(bay):
		return
	transition = true
	_alignment_active = true
	_transfer_generation += 1
	var generation := _transfer_generation
	player.enabled = false
	player.velocity = Vector3.ZERO
	var blocked := false
	while true:
		await get_tree().physics_frame
		if generation != _transfer_generation:
			return
		if paused:
			continue
		var p: Vector3 = bay.to_local(player.global_position)
		var target: Vector3 = bay.to_global(Vector3(0, p.y, p.z))
		var motion: Vector3 = target - player.global_position
		if motion.length() < 0.001:
			break
		# Keep capsule collisions active; never teleport an offset body through armor.
		var collision: KinematicCollision3D = player.move_and_collide(motion.limit_length(1.2 * get_physics_process_delta_time()))
		if collision != null:
			blocked = true
			break
	_alignment_active = false
	transition = false
	player.enabled = true
	if blocked:
		hud.toast("对齐路线受阻，请退回检修桥后重试。")
		return
	interact()

func interact() -> void:
	_update_interaction()
	if interaction_bay == null:
		return
	var bay = interaction_bay
	match interaction:
		"align_assist":
			align_for_hatch(bay)
		"lift":
			if bay.state.request_lift():
				riding = bay
				player.enabled = false
				player.velocity = Vector3.ZERO
				audio.elevator(true)
		"hatch":
			if bay.state.open_hatch():
				bay.set_access(true)
				audio.play("door_servo")
		"board":
			enter_cockpit(bay)
		"boot":
			var stage: int = bay.state.boot()
			bay.set_power(stage)
			audio.play("startup" if stage == 2 else "button")
			if stage == 3:
				profile.mark_complete(bay.info.id)
				_save()
				audio.play("success")
				hud.toast("%s · 自检完成。机体处于停泊状态。" % bay.info.name, 5.0)
		"exit":
			exit_cockpit()

func enter_cockpit(bay) -> void:
	if not bay.state.board():
		return
	transition = true
	_transfer_generation += 1
	bay.transfer_active = true
	seated_bay = bay
	player.enabled = false
	player.look_enabled = false
	player.collision_layer = 0
	player.collision_mask = 0
	audio.play("door_servo")
	audio.set_cabin(true)
	var from_yaw: float = player.rotation.y
	var target_yaw: float = bay.rotation.y
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_motion_tween = tween
	tween.tween_property(player, "global_position", bay.seat_position(), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player.camera, "position:y", 1.16, 2.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(player.camera, "rotation:x", 0.10, 2.0)
	tween.tween_method(func(t: float): player.rotation.y = lerp_angle(from_yaw, target_yaw, t), 0.0, 1.0, 2.0)
	await tween.finished
	transition = false
	bay.transfer_active = false
	player.look_enabled = true
	bay.set_access(false)
	hud.toast("已落座。按 E 依次接通供电、外部监视器和系统自检。", 6.0)

func exit_cockpit() -> void:
	if seated_bay == null:
		return
	var bay = seated_bay
	if not bay.state.leave():
		return
	transition = true
	_transfer_generation += 1
	var generation := _transfer_generation
	player.look_enabled = false
	bay.set_power(0)
	bay.set_access(true)
	audio.set_cabin(false)
	audio.play("door_servo")
	# Stay inside the seat until the moving armor has completely cleared the doorway.
	while bay.door_amount < 0.999:
		await get_tree().physics_frame
		if generation != _transfer_generation:
			return
	var from_yaw: float = player.rotation.y
	var target_yaw: float = bay.rotation.y
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_motion_tween = tween
	tween.tween_property(player, "global_position", bay.exit_position(), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player.camera, "position:y", 1.65, 2.0)
	tween.tween_property(player.camera, "rotation:x", 0.0, 2.0)
	tween.tween_method(func(t: float): player.rotation.y = lerp_angle(from_yaw, target_yaw, t), 0.0, 1.0, 2.0)
	await tween.finished
	seated_bay = null
	transition = false
	player.enabled = true
	player.look_enabled = true
	player.collision_layer = 1
	player.collision_mask = 1
	hud.toast("已离舱。沿检修桥返回升降平台，按 E 下行。", 5.0)

func _update_hud() -> void:
	var prompt_text := ""
	match interaction:
		"lift": prompt_text = "[ E ]  下降至地面" if interaction_bay.state.at_top else "[ E ]  乘升降平台前往驾驶舱"
		"hatch": prompt_text = "[ E ]  打开驾驶舱"
		"board": prompt_text = "[ E ]  进入驾驶舱并落座"
		"opening": prompt_text = "舱门正在开启…"
		"align": prompt_text = "请移到桥面中央，对准舱口"
		"align_assist": prompt_text = "[ E ]  对准舱口并登舱" if interaction_bay.state.hatch_open else "[ E ]  对准舱口并开舱"
		"boot": prompt_text = ["[ E ]  接通辅助供电", "[ E ]  启动外部监视器", "[ E ]  执行系统自检"][interaction_bay.state.boot_stage]
		"exit": prompt_text = "[ E / Q ]  关机并离开驾驶舱"
	if seated_bay != null and seated_bay.state.boot_stage < 3:
		prompt_text += "     [ Q ]  离舱"
	if riding != null:
		prompt_text = "升降平台运行中  ·  可自由观察"
	if transition:
		prompt_text = "正在进入驾驶舱…" if seated_bay != null and seated_bay.state.seated else "正在离开驾驶舱…"
		if _alignment_active:
			prompt_text = "正在对准舱口…"
	var data: Dictionary = catalog[target_index]
	var dest: Vector3 = bays[target_index].to_global(Vector3(0, 0, -7.8))
	var distance := Vector2(dest.x - player.global_position.x, dest.z - player.global_position.z).length()
	var direction: Vector3 = player.to_local(dest)
	var arrow := "前方" if direction.z < 0 else "后方"
	if absf(direction.x) > absf(direction.z) * 0.6:
		arrow = "右侧" if direction.x > 0 else "左侧"
	var location := "PILOT  /  中央整备通道"
	if nearest_bay != null and player.global_position.distance_to(nearest_bay.global_position) < 18:
		location = "%s  /  %s" % [nearest_bay.info.bay, nearest_bay.info.name]
	var cabin_text := ""
	var target_text := "%s · %s  /  %.0f m" % [data.bay, data.name, distance]
	var hint_text := arrow + " · 黄色平台可抵达登舱层"
	if riding != null:
		target_text = "%s · %s" % [riding.info.bay, "正在前往登舱层" if not riding.state.at_top else "正在返回地面"]
		hint_text = "平台运行中，可自由抬头观察机体"
	elif nearest_bay != null and player.global_position.y > nearest_bay.top_y - 0.3:
		target_text = nearest_bay.info.bay + " · 胸部检修层"
		hint_text = "沿检修桥返回平台可下行" if nearest_bay.info.id in profile.completed else "沿检修桥走近舱门，按 E 登舱"
	if seated_bay != null:
		cabin_text = "%s  /  %s\n%s" % [seated_bay.info.model, seated_bay.info.name, ["等待供电", "辅助供电在线  ·  01 / 03", "外部监视器在线  ·  02 / 03", "自检完成  ·  停泊锁定"][seated_bay.state.boot_stage]]
		target_text = seated_bay.info.bay + " · 驾驶舱"
		hint_text = "E 操作仪表  ·  Q 随时关机离舱"
	hud.update_view({"prompt": prompt_text, "location": location, "altitude": player.camera.global_position.y, "visited": profile.completed.size(), "target": target_text, "hint": hint_text, "cabin": seated_bay != null, "cabin_text": cabin_text})

func pause_game(show_directory: bool = false) -> void:
	paused = true
	get_tree().paused = true
	_set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if show_directory:
		hud.show_guide()
	else:
		hud.show_pause()

func resume() -> void:
	if not started:
		hud.show_menu()
		return
	paused = false
	get_tree().paused = false
	hud.show_game()
	_set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func select_bay(index: int) -> void:
	target_index = clampi(index, 0, catalog.size() - 1)
	if not started:
		start()
	else:
		resume()
	hud.toast("导航已设置：" + catalog[target_index].bay + " · " + catalog[target_index].name)

func return_to_entry() -> void:
	# Always restore a stable state, including paused lifts and seated pilots.
	_transfer_generation += 1
	_alignment_active = false
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	for bay in bays:
		bay.transfer_active = false
		bay.state = load("res://scripts/bay_state.gd").new(bay.top_y)
		bay.set_power(0)
		bay.set_access(false, true)
		bay.door_amount = 0.0
		bay.tick(0.0)
	riding = null
	seated_bay = null
	transition = false
	player.collision_layer = 1
	player.collision_mask = 1
	player.enabled = true
	player.look_enabled = true
	player.set_view(Vector3(0, 0.15, 46), 0.4, 0.16)
	audio.elevator(false)
	audio.set_cabin(false)
	resume()
	hud.toast("已返回入口，启动记录已保留。")

func change_setting(key: String, value: float) -> void:
	match key:
		"sensitivity":
			profile.settings.sensitivity = value
			player.sensitivity = value * 0.0021
		"fov":
			profile.settings.fov = value
			player.camera.fov = value
		"sound":
			profile.settings.sound = value > 0.5
			audio.set_muted(value < 0.5)
	_save()

func _save() -> void:
	if not profile.write() and not _save_warning:
		_save_warning = true
		hud.toast("记录暂时无法保存；本次体验仍可继续。", 6.0)

func quit_game() -> void:
	_save()
	get_tree().paused = false
	_set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().quit()
