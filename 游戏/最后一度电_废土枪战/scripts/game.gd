extends Node3D

const RunRules = preload("res://scripts/run_state.gd")
const PlayerScript = preload("res://scripts/player.gd")
var world: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var audio_bank: Node
var gameplay: Node3D
var effects: Node3D
var objective_root: Node3D
var menu_camera: Camera3D
var state = RunRules.new()
var running: bool = false
var difficulty: String = "standard"
var settings: Dictionary = {"sensitivity":1.0,"low_quality":false,"volume":.75,"difficulty":"standard"}
var best: Dictionary = {}
var enemies: Array[Node] = []
var wave_queue: Array[Dictionary] = []
var wave_flags: Dictionary = {}
var targets: Array[Dictionary] = []
var active_target: Dictionary = {}
var interaction_progress: float = 0.0
var spawn_clock: float = 0.0
var previous_phase: String = "power"
var checkpoint_data: Dictionary = {}
var rng := RandomNumberGenerator.new()
var qa: bool = false
var qa_mode: String = ""
var qa_elapsed: float = 0.0
var qa_steps: Dictionary = {}
var visuals: Dictionary = {}
var mat_cache: Dictionary = {}
var extraction_timer: float = 0.0
var quitting: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	qa = "--qa" in OS.get_cmdline_user_args() or "--qa-menu" in OS.get_cmdline_user_args()
	qa_mode = "menu" if "--qa-menu" in OS.get_cmdline_user_args() else "combat"
	rng.seed = 1709
	_setup_input(); _load_profile()
	if "--low-quality" in OS.get_cmdline_user_args(): settings.low_quality = true
	gameplay = Node3D.new(); gameplay.name = "Gameplay"; gameplay.process_mode = Node.PROCESS_MODE_PAUSABLE; add_child(gameplay)
	world = load("res://scripts/world.gd").new(); gameplay.add_child(world); world.build()
	effects = Node3D.new(); effects.name = "Temporary effects"; gameplay.add_child(effects)
	objective_root = Node3D.new(); gameplay.add_child(objective_root)
	audio_bank = load("res://scripts/audio_bank.gd").new(); add_child(audio_bank); audio_bank.setup(); audio_bank.set_volume(float(settings.volume))
	hud = load("res://scripts/hud.gd").new(); add_child(hud); hud.setup()
	hud.set_settings(settings)
	hud.start_requested.connect(_start_from_menu); hud.resume_requested.connect(_resume)
	hud.retry_requested.connect(_retry); hud.restart_requested.connect(_restart); hud.quit_requested.connect(_quit)
	hud.settings_changed.connect(_settings_changed)
	menu_camera = Camera3D.new(); add_child(menu_camera); menu_camera.position = Vector3(22,10,23); menu_camera.look_at(Vector3(0,2,-5)); menu_camera.fov = 59; menu_camera.current = true
	world.set_quality(bool(settings.low_quality)); world.set_power(false)
	get_viewport().scaling_3d_scale = .70 if bool(settings.low_quality) else 1.0
	_create_objectives(); hud.show_menu(best); audio_bank.set_ambience(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if qa and qa_mode != "menu": _begin("power")
	print("GAME_READY ", JSON.stringify({"qa":qa,"mode":qa_mode,"engine":Engine.get_version_info().string}))

func _setup_input() -> void:
	var keys: Dictionary = {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"jump":KEY_SPACE,"sprint":KEY_SHIFT,"crouch":KEY_CTRL,"reload":KEY_R,"heal":KEY_Q,"interact":KEY_E,"pause_game":KEY_ESCAPE,"weapon_1":KEY_1,"weapon_2":KEY_2}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var ev := InputEventKey.new(); ev.physical_keycode = keys[action]; InputMap.action_add_event(action,ev)
	for action in {"fire":MOUSE_BUTTON_LEFT,"aim":MOUSE_BUTTON_RIGHT,"next_weapon":MOUSE_BUTTON_WHEEL_DOWN,"prev_weapon":MOUSE_BUTTON_WHEEL_UP}:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var ev := InputEventMouseButton.new(); ev.button_index = {"fire":MOUSE_BUTTON_LEFT,"aim":MOUSE_BUTTON_RIGHT,"next_weapon":MOUSE_BUTTON_WHEEL_DOWN,"prev_weapon":MOUSE_BUTTON_WHEEL_UP}[action]; InputMap.action_add_event(action,ev)

func _settings_changed(value: Dictionary) -> void:
	settings.merge(value,true); difficulty = str(settings.get("difficulty","standard"))
	if is_instance_valid(player): player.sensitivity = float(settings.get("sensitivity",1.0))
	world.set_quality(bool(settings.get("low_quality",false))); audio_bank.set_volume(float(settings.get("volume",.75)))
	get_viewport().scaling_3d_scale = .70 if bool(settings.get("low_quality",false)) else 1.0
	_save_profile()

func _load_profile() -> void:
	if not FileAccess.file_exists("user://profile.json"): return
	var data = JSON.parse_string(FileAccess.get_file_as_string("user://profile.json"))
	if data is Dictionary:
		if data.get("settings") is Dictionary: settings.merge(data.settings,true)
		if data.get("best") is Dictionary: best = data.best

func _save_profile() -> void:
	if qa: return
	var file := FileAccess.open("user://profile.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"settings":settings,"best":best})); file.close()

func _start_from_menu(value: String) -> void:
	difficulty = value; settings.difficulty = value; checkpoint_data.clear(); _begin("power")

func _begin(checkpoint: String) -> void:
	get_tree().paused = false; running = false
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e): e.queue_free()
	for e in get_tree().get_nodes_in_group("enemy_corpses"):
		if is_instance_valid(e): e.queue_free()
	enemies.clear(); wave_queue.clear(); wave_flags.clear(); spawn_clock = 0.0
	if is_instance_valid(player): player.queue_free()
	for e in effects.get_children(): e.queue_free()
	state = RunRules.new(); state.restore_checkpoint(checkpoint); previous_phase = state.phase
	if checkpoint != "power" and not checkpoint_data.is_empty():
		state.elapsed = float(checkpoint_data.get("elapsed",0)); state.kills = int(checkpoint_data.get("kills",0)); state.shots = int(checkpoint_data.get("shots",0)); state.hits = int(checkpoint_data.get("hits",0)); state.headshots = int(checkpoint_data.get("headshots",0))
	player = PlayerScript.new(); gameplay.add_child(player)
	var spawn := Vector3(0,.1,21)
	if checkpoint == "connect": spawn = Vector3(11,3.12,3.45)
	elif checkpoint == "extract": spawn = Vector3(-7.8,.1,-5.8)
	player.setup(self,spawn); player.sensitivity = float(settings.get("sensitivity",1.0)); player.died.connect(_on_player_died)
	if difficulty == "easy": player.medkits = 3; player.armor = 55.0
	player.camera.current = true; hud.hide_panels(); running = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if qa else Input.MOUSE_MODE_CAPTURED
	interaction_progress = 0; active_target = {}; _reset_targets()
	world.set_power(checkpoint != "power")
	if checkpoint == "power":
		_spawn_enemy("rifle",Vector3(-1,.12,-4.5)); _spawn_enemy("rifle",Vector3(7,.12,5.5)); _spawn_enemy("flanker",Vector3(18,.12,-6))
		hud.show_message("电台 · 医务站", "电池只够撑到天亮。先去右侧集装箱楼，沿外楼梯找到总开关。",7.0)
	elif checkpoint == "connect":
		wave_flags.power = true; _queue_wave(["rifle","flanker"],"厂房方向有动静。利用车体掩护，前往 02 号充电桩。")
	else:
		wave_flags.power = true; wave_flags.charge1 = true; wave_flags.charge2 = true; wave_flags.extract = true
		_queue_wave(["rifle","flanker"],"电池在手。撤回南侧道闸，不必再和他们纠缠。")
	_update_target_visibility()

func _retry() -> void:
	var cp: String = str(checkpoint_data.get("phase","power")); _begin(cp)

func _restart() -> void:
	checkpoint_data.clear(); _begin("power")

func _resume() -> void:
	get_tree().paused = false; hud.hide_panels(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if qa else Input.MOUSE_MODE_CAPTURED

func _quit() -> void:
	if quitting: return
	quitting = true; running = false; _save_profile()
	if is_instance_valid(audio_bank): audio_bank.shutdown()
	await get_tree().create_timer(.15,true,false,true).timeout
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and running and state.phase not in ["dead","victory"]:
		if get_tree().paused: _resume()
		else: get_tree().paused = true; hud.show_pause(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()

func can_fight() -> bool:
	return running and not get_tree().paused and is_instance_valid(player) and player.is_alive() and state.phase not in ["victory","dead"]

func play_sound(key: String, position: Vector3 = Vector3.INF) -> void:
	if is_instance_valid(audio_bank): audio_bank.play(key,position)

func _process(delta: float) -> void:
	if not is_instance_valid(hud): return
	if qa: _qa_tick(delta)
	if not running:
		menu_camera.position.x = 22.0+sin(float(Time.get_ticks_msec())*.00010)*1.6
		menu_camera.look_at(Vector3(0,2,-5)); return
	if can_fight():
		state.advance(delta)
		if state.phase != previous_phase: _phase_changed(previous_phase,state.phase); previous_phase = state.phase
		if state.phase == "charge" and not wave_flags.has("charge1"):
			wave_flags.charge1 = true; _queue_wave(["rifle","rifle","flanker"],"充电声把他们引来了。守住掩体，可以离开充电桩作战。")
		if state.charge >= 45.0 and not wave_flags.has("charge2"):
			wave_flags.charge2 = true; _queue_wave(["heavy","rifle","flanker"],"注意，重装守卫进入院内。绕着工程车打，瞄准头部。")
		_process_spawns(delta); _process_interaction(delta)
		_update_objective_marker()
	var w = player.current_weapon()
	var info := _objective_info()
	hud.update_hud({"health":player.health,"armor":player.armor,"ammo":w.ammo,"reserve":w.reserve,"weapon":w.title + ("  · 换弹中" if w.reload_left>0 else ""),"medkits":player.medkits,"objective":info.title,"detail":info.detail,"phase":state.phase,"charge":state.charge/75.0,"stamina":player.stamina,"spread":2.0+player.recoil*9.0+(Vector2(player.velocity.x,player.velocity.z).length()*.65),"aiming":player.aiming,"kills":state.kills,"carrying":state.carrying,"elapsed":state.elapsed})

func _phase_changed(_old: String, phase: String) -> void:
	play_sound("interact")
	match phase:
		"connect":
			world.set_power(true); play_sound("power"); _checkpoint()
			hud.show_message("主电源已接通", "青色指示灯已亮。去充电棚 02 号桩接入储能电池。",6)
			if not wave_flags.has("power"): wave_flags.power = true; _queue_wave(["rifle","flanker"],"")
		"reset":
			world.set_power(false,true); play_sound("alarm")
			hud.show_message("线路跳闸 · 进度已保留", "到售货机旁电箱复位。利用白色充电舱挡住敌人的枪线。",7)
		"charge": world.set_power(true); play_sound("power")
		"collect": hud.show_message("充能完成", "取走 02 号桩上的电池。南侧道闸已经准备接应。",6); play_sound("power")
		"extract":
			world.set_power(false); _checkpoint(); play_sound("pickup")
			hud.show_message("电台 · 返程", "电池到手。沿车棚撤回入口，活着回来比清场更重要。",7)
			if not wave_flags.has("extract"): wave_flags.extract = true; _queue_wave(["rifle","flanker"],"")
		"victory": _finish(true)
	_update_target_visibility()

func _checkpoint() -> void:
	checkpoint_data = state.stats(); checkpoint_data.phase = state.checkpoint

func _objective_info() -> Dictionary:
	match state.phase:
		"power": return {"title":"恢复充电场供电","detail":"右侧集装箱楼 · 沿外楼梯上平台","id":"power_console"}
		"connect": return {"title":"接入储能电池","detail":"前往充电棚 02 号桩","id":"charge_terminal"}
		"charge": return {"title":"守住充电线路","detail":"充能会持续进行 · 利用掩体迎敌","id":"charge_terminal"}
		"reset": return {"title":"复位跳闸电箱","detail":"售货机旁 · 充能进度已保留","id":"reset_breaker"}
		"collect": return {"title":"取走充满的电池","detail":"返回 02 号充电桩","id":"battery"}
		"extract": return {"title":"带电池撤回道闸","detail":"抵达南侧绿灯区 · 按住 E 完成撤离","id":"exit"}
	return {"title":"行动结束","detail":"","id":""}

func _spawn_enemy(kind: String, pos: Vector3) -> Node:
	var e = load("res://scripts/enemy.gd").new(); gameplay.add_child(e); e.setup(self,kind,pos,rng.randi_range(1,999999))
	e.died.connect(_enemy_died); enemies.append(e); return e

func _queue_wave(kinds: Array, message: String) -> void:
	var points: Array[Vector3] = [Vector3(.5,.12,-20),Vector3(20.7,.12,-18),Vector3(20.5,.12,8),Vector3(-1,.12,-18)]
	for i in range(kinds.size()): wave_queue.append({"kind":kinds[i],"position":points[(i+wave_queue.size()+wave_flags.size())%points.size()]})
	spawn_clock = maxf(spawn_clock,2.8)
	if not message.is_empty(): hud.show_message("电台 · 预警",message,5.0)
	play_sound("alarm",Vector3(1,2,-22))

func _process_spawns(delta: float) -> void:
	for i in range(enemies.size()-1,-1,-1):
		if not is_instance_valid(enemies[i]) or not enemies[i].is_alive(): enemies.remove_at(i)
	spawn_clock -= delta
	if wave_queue.is_empty() or enemies.size() >= 5 or spawn_clock > 0.0: return
	var item: Dictionary = wave_queue[0]
	var candidates: Array[Vector3] = [item.position,Vector3(.5,.12,-20),Vector3(20.7,.12,-18),Vector3(20.5,.12,8),Vector3(-1,.12,-18)]
	var chosen: Vector3 = Vector3.INF
	for point in candidates:
		if player.global_position.distance_to(point) < 10.0: continue
		var target: Vector3 = point + Vector3(0,1.1,0)
		var camera: Camera3D = player.camera
		var visible: bool = not camera.is_position_behind(target) and get_viewport().get_visible_rect().has_point(camera.unproject_position(target))
		if visible:
			var ray := PhysicsRayQueryParameters3D.create(camera.global_position,target,1)
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		chosen = point; break
	if chosen == Vector3.INF: spawn_clock = .8; return
	item.position = chosen
	wave_queue.pop_front(); var e = _spawn_enemy(str(item.kind),item.position); e.alert_to(player.global_position); spawn_clock = 2.4

func _enemy_died(enemy: Node, headshot: bool) -> void:
	state.kills += 1
	if headshot: state.headshots += 1
	enemies.erase(enemy)
	if state.kills%3 == 0 and is_instance_valid(enemy): _add_pickup("ammo",enemy.global_position+Vector3(0,.1,0),"拾取弹药")

func _on_player_died() -> void:
	state.phase = "dead"; _finish(false)

func _finish(won: bool) -> void:
	running = false; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; play_sound("victory" if won else "death")
	if won:
		var result: Dictionary = state.stats()
		if best.is_empty() or float(result.elapsed) < float(best.get("elapsed",99999)): best = result; _save_profile()
	hud.show_end(won,state.stats())

func fire_weapon(shooter: Node, w) -> void:
	if not can_fight(): return
	play_sound("shotgun" if w.kind == "shotgun" else "rifle")
	var origin: Vector3 = shooter.camera.global_position
	var basis_value: Basis = shooter.camera.global_transform.basis
	var muzzle: Vector3 = shooter.flashes[shooter.weapon_index].global_position
	var actual_spread: float = float(w.spread) * (.30 if shooter.aiming and w.kind=="rifle" else .80 if shooter.aiming else 1.0)
	for pellet in range(w.pellets):
		state.shots += 1
		var direction: Vector3 = (-basis_value.z + basis_value.x*rng.randf_range(-actual_spread,actual_spread)+basis_value.y*rng.randf_range(-actual_spread,actual_spread)).normalized()
		var endpoint: Vector3 = origin + direction*110
		var query := PhysicsRayQueryParameters3D.create(origin,endpoint,1|4,[shooter.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			endpoint = hit.position
			var body = hit.collider
			if body.has_method("take_damage") and body.is_in_group("enemies"):
				var head: bool = endpoint.y > body.global_position.y + 1.42
				var amount: float = float(w.damage)*(1.85 if head else 1.0)
				if w.kind == "shotgun": amount *= clampf(1.0-origin.distance_to(endpoint)/62.0,.38,1.0)
				body.take_damage(amount,endpoint,head); state.hits += 1; hud.hit_marker(head); play_sound("headshot" if head else "hit",endpoint)
				_spark(endpoint,Color(.85,.48,.20),.09)
			else: _spark(endpoint,Color(.77,.69,.46),.06)
		if pellet < 3: spawn_tracer(muzzle,endpoint,Color(1,.80,.44))
	for e in enemies:
		if is_instance_valid(e) and e.global_position.distance_to(origin)<38: e.alert_to(origin)
	_eject_casing(muzzle)

func _mat(key: String, color: Color, emission: bool = false) -> StandardMaterial3D:
	if mat_cache.has(key): return mat_cache[key]
	var m := StandardMaterial3D.new(); m.albedo_color = color; m.roughness = .8
	if emission: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = 1.6
	mat_cache[key] = m; return m

func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size = size; n.mesh = mesh; n.material_override = material; n.position = pos; parent.add_child(n); return n

func spawn_tracer(a: Vector3, b: Vector3, color: Color) -> void:
	if a.distance_to(b)<.02: return
	var trace := MeshInstance3D.new(); var cylinder := CylinderMesh.new(); cylinder.top_radius = .007; cylinder.bottom_radius = .004; cylinder.height = a.distance_to(b); cylinder.radial_segments = 4
	trace.mesh = cylinder; trace.material_override = _mat("tracer"+color.to_html(),color,true); effects.add_child(trace)
	trace.global_position = (a+b)*.5; trace.quaternion = Quaternion(Vector3.UP,(b-a).normalized()); trace.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().create_timer(.065,false).timeout.connect(func(): if is_instance_valid(trace): trace.queue_free())

func _spark(pos: Vector3, color: Color, size: float) -> void:
	if effects.get_child_count()>130: return
	var n := MeshInstance3D.new(); var sphere := SphereMesh.new(); sphere.radius = size; sphere.height = size*2; sphere.radial_segments = 8; sphere.rings = 4
	n.mesh = sphere; n.material_override = _mat("spark"+color.to_html(),color,true); n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; effects.add_child(n); n.position = pos
	var tween := n.create_tween(); tween.tween_property(n,"scale",Vector3(.05,.05,.05),.14); tween.tween_callback(n.queue_free)

func _eject_casing(pos: Vector3) -> void:
	if effects.get_child_count()>130: return
	var n := _box(effects,pos,Vector3(.023,.023,.075),_mat("brass",Color(.65,.48,.22)))
	var end: Vector3 = pos+Vector3(rng.randf_range(.4,.9),-.8,rng.randf_range(-.2,.5))
	var tween := n.create_tween(); tween.set_parallel(true); tween.tween_property(n,"position",end,.4); tween.tween_property(n,"rotation",Vector3(3,5,2),.4); tween.chain().tween_interval(.6); tween.chain().tween_callback(n.queue_free)

func _create_objectives() -> void:
	for n in objective_root.get_children(): n.queue_free()
	targets.clear(); visuals.clear()
	_add_device("power_console",Vector3(10.9,3.05,3.55),"按住 E · 接通主电源",1.8,"power")
	_add_device("charge_terminal",Vector3(-8.4,0,-7.5),"按住 E · 接入储能电池",1.4,"connect")
	_add_device("reset_breaker",Vector3(-8.9,0,.55),"按住 E · 复位断路器",1.5,"reset")
	_add_device("battery",Vector3(-8.4,0,-7.5),"按住 E · 取走储能电池",1.0,"collect")
	_add_device("exit",Vector3(0,0,20),"按住 E · 带电撤离",3.0,"extract")
	_add_pickup("ammo",Vector3(13,3.09,2.9),"按住 E · 拾取弹药")
	_add_pickup("medkit",Vector3(-8.75,.06,3.55),"按住 E · 领取急救包")
	_add_pickup("ammo",Vector3(16.5,.05,-5.8),"按住 E · 拾取弹药")
	_add_pickup("armor",Vector3(-4,.05,11),"按住 E · 穿戴备用护甲")
	_add_pickup("ammo",Vector3(-2,.05,18),"按住 E · 补充出发弹药")

func _add_device(id: String, pos: Vector3, label: String, hold: float, phase: String) -> void:
	var node := Node3D.new(); node.name = id; objective_root.add_child(node); node.position = pos
	var casing := _mat("device case",Color(.17,.22,.21)); var screen := _mat("device screen",Color(.12,.75,.63),true)
	if id == "exit":
		var ring := MeshInstance3D.new(); var mesh := TorusMesh.new(); mesh.inner_radius = 1.55; mesh.outer_radius = 1.63; mesh.rings = 48; mesh.ring_segments = 6
		ring.mesh = mesh; ring.material_override = screen; ring.position.y = .04; node.add_child(ring)
	elif id == "battery":
		_box(node,Vector3(0,1.0,0),Vector3(.38,.44,.24),_mat("battery",Color(.46,.52,.41)))
		for x in [-.13,.13]: _box(node,Vector3(x,1.0,-.13),Vector3(.035,.32,.012),screen)
		_box(node,Vector3(0,1.24,0),Vector3(.23,.03,.05),casing)
	else:
		_box(node,Vector3(0,.45,0),Vector3(.18,.90,.18),casing)
		_box(node,Vector3(0,.98,0),Vector3(.46,.39,.20),casing)
		_box(node,Vector3(0,1.015,.109),Vector3(.34,.23,.015),screen)
		_box(node,Vector3(0,.875,.117),Vector3(.065,.046,.025),_mat("button",Color(.90,.57,.19),true))
	visuals[id] = node
	targets.append({"id":id,"node":node,"position":pos+Vector3(0,.95,0),"label":label,"hold":hold,"phase":phase,"used":false,"kind":"objective"})

func _add_pickup(kind: String, pos: Vector3, label: String) -> void:
	var node := Node3D.new(); objective_root.add_child(node); node.position = pos
	var color: Color = Color(.48,.40,.23) if kind=="ammo" else Color(.61,.64,.54) if kind=="medkit" else Color(.26,.34,.32)
	_box(node,Vector3(0,.21,0),Vector3(.52,.36,.33),_mat("pickup"+kind,color))
	_box(node,Vector3(0,.395,0),Vector3(.48,.035,.30),_mat("pickup lip",Color(.13,.17,.16)))
	var glow := _mat("pickup strip",Color(.65,.78,.44),true)
	_box(node,Vector3(0,.22,.172),Vector3(.25,.03,.008),glow)
	if kind=="medkit": _box(node,Vector3(0,.22,.174),Vector3(.03,.22,.01),glow)
	targets.append({"id":"supply_"+str(targets.size()),"node":node,"position":pos+Vector3(0,.3,0),"label":label,"hold":.85,"phase":"any","used":false,"kind":kind})

func _reset_targets() -> void:
	_create_objectives()

func _update_target_visibility() -> void:
	for item in targets:
		if item.kind == "objective":
			item.node.visible = (item.id != "battery" or state.phase=="collect") and (item.id != "exit" or state.phase in ["extract","victory"])

func _process_interaction(delta: float) -> void:
	var nearest: Dictionary = {}; var score: float = INF
	for item in targets:
		if item.used or not is_instance_valid(item.node): continue
		if item.phase != "any" and item.phase != state.phase: continue
		var difference: Vector3 = item.position-player.camera.global_position; var distance: float = difference.length()
		if distance > (2.8 if item.id=="exit" else 2.25): continue
		if item.id != "exit" and -player.camera.global_basis.z.dot(difference.normalized()) < .58: continue
		var ray := PhysicsRayQueryParameters3D.create(player.camera.global_position,item.position,1)
		var block: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
		if not block.is_empty() and player.camera.global_position.distance_to(block.position) < distance-.22: continue
		if distance < score: score = distance; nearest = item
	if nearest.is_empty():
		interaction_progress = 0; active_target = {}; hud.set_interaction("",0); return
	if active_target.get("id","") != nearest.id: interaction_progress = 0
	active_target = nearest
	if Input.is_action_pressed("interact"):
		interaction_progress += delta/float(nearest.hold)
		if interaction_progress >= 1.0:
			_activate_target(nearest); interaction_progress = 0; active_target = {}; hud.set_interaction("",0); return
	else: interaction_progress = 0
	hud.set_interaction(str(nearest.label),interaction_progress)

func _activate_target(item: Dictionary) -> bool:
	if item.kind == "objective":
		var old_phase: String = state.phase
		if not state.activate(str(item.id)): return false
		previous_phase = state.phase
		_phase_changed(old_phase,state.phase)
		return true
	if item.used: return false
	item.used = true; item.node.visible = false; player.add_supplies(str(item.kind)); play_sound("pickup")
	hud.show_message("补给已收取",{"ammo":"卡宾枪 +48 · 霰弹枪 +6","medkit":"急救包 +1 · Q 使用","armor":"备用护甲 +35"}.get(str(item.kind),""),2.8)
	return true

func _update_objective_marker() -> void:
	var id: String = _objective_info().id
	for item in targets:
		if item.id != id: continue
		var pos: Vector3 = item.position+Vector3(0,.45,0)
		var behind: bool = player.camera.is_position_behind(pos)
		var screen_pos: Vector2 = player.camera.unproject_position(pos)
		if behind: screen_pos.x = 60 if (player.global_basis.inverse()*(pos-player.global_position)).x<0 else get_viewport().get_visible_rect().size.x-60; screen_pos.y = 140
		if hud.has_method("set_objective_marker"): hud.set_objective_marker(screen_pos,player.global_position.distance_to(item.position),true)
		return

func _qa_tick(delta: float) -> void:
	if quitting: return
	qa_elapsed += delta
	if qa_mode == "menu":
		if qa_elapsed > 1.5 and not qa_steps.has("shot"): qa_steps.shot = true; _save_screenshot("menu.png")
		if qa_elapsed > 3.0: print("QA_MENU_OK"); _quit()
		return
	if not is_instance_valid(player): return
	if qa_mode == "combat":
		if qa_elapsed > .5 and not qa_steps.has("move"):
			qa_steps.move = true; player.global_position = Vector3(0,.12,10); player.rotation.y = .12; player.look_pitch = -.025
		if qa_elapsed > 1.0 and not qa_steps.has("screen"):
			qa_steps.screen = true; _save_screenshot("gameplay.png")
		if qa_elapsed > 2.0 and not qa_steps.has("shot"):
			qa_steps.shot = true; Input.action_press("fire")
		if qa_elapsed > 3.0: Input.action_release("fire")
		if qa_elapsed > 4.5 and not qa_steps.has("screen2"):
			qa_steps.screen2 = true; Input.action_press("aim")
		if qa_elapsed > 5.2 and not qa_steps.has("ads"):
			qa_steps.ads = true; _save_screenshot("combat.png"); Input.action_release("aim")
		if qa_elapsed > 7.5 and not qa_steps.has("clean"):
			qa_steps.clean = true; _save_screenshot("gameplay.png"); player.set_weapon(1)
		if qa_elapsed > 8.2 and not qa_steps.has("shotgun"):
			qa_steps.shotgun = true; _save_screenshot("shotgun.png")
		if qa_elapsed > 8.5:
			print("QA_COMBAT_RESULT ",JSON.stringify({"shots":state.shots,"health":player.health,"enemies":enemies.size(),"phase":state.phase,"ammo":player.current_weapon().ammo,"fps":Engine.get_frames_per_second()})); _quit()

func _save_screenshot(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw(false)
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty(): push_error("QA empty viewport image"); return
	var folder: String = ProjectSettings.globalize_path("res://previews")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="): folder = arg.trim_prefix("--qa-output=")
	DirAccess.make_dir_recursive_absolute(folder)
	var err: Error = image.save_png(folder.path_join(filename))
	print("QA_SCREENSHOT ",filename," ",err," ",image.get_width(),"x",image.get_height())
	print("QA_RENDER ",JSON.stringify({"fps":Engine.get_frames_per_second(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000}))
