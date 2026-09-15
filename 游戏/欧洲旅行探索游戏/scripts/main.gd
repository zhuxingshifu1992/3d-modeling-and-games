extends Node3D

const TravelState = preload("res://scripts/travel_state.gd")
const Traveler = preload("res://scripts/player.gd")
const Ambience = preload("res://scripts/ambience.gd")
const GameUI = preload("res://scripts/game_ui.gd")

var state = TravelState.new()
var player: CharacterBody3D
var ui: CanvasLayer
var ambience: Node
var manifest: Dictionary = {}
var actions: Array = []
var region_nodes: Array = []
var interiors: Array = []
var room_lights: Array = []
var markers: Array = []
var world_ready := false
var load_failed := false
var load_errors: Array[String] = []
var save_path := "user://journey.json"
var can_continue := false
var playing := false
var modal := "title"
var nearest: Dictionary = {}
var current_region: Dictionary = {}
var current_building: Dictionary = {}
var update_timer := 0.0
var autosave_timer := 0.0
var environment: WorldEnvironment
var sun: DirectionalLight3D
var photo_busy := false
var automated_test := false
var window_initialized := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fit_game_window()
	setup_inputs()
	setup_environment()
	player = Traveler.new()
	add_child(player)
	player.teleport(Vector3(-90, 0.26, -47))
	ambience = Ambience.new()
	add_child(ambience)
	player.footstep.connect(ambience.step)
	ui = GameUI.new()
	add_child(ui)
	ui.action_requested.connect(handle_action)
	ui.show_loading("正在准备四国旅行路线与建筑室内…")
	load_world.call_deferred()

func setup_inputs() -> void:
	var bindings := {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"run":KEY_SHIFT,"jump":KEY_SPACE,"interact":KEY_E,"map":KEY_M,"photo":KEY_F,"pause":KEY_ESCAPE}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = bindings[action]
		InputMap.action_add_event(action, event)

func setup_environment() -> void:
	environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color("577b9c")
	material.sky_horizon_color = Color("c8d8df")
	material.ground_bottom_color = Color("566351")
	material.ground_horizon_color = Color("b9c9c5")
	sky.sky_material = material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d8e2ed")
	env.ambient_light_energy = 0.58
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color("c4d4d9")
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.12
	env.fog_height = 0.0
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("fff1d9")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func load_world() -> void:
	if not FileAccess.file_exists("res://assets/world_manifest.json"):
		fail_load("缺少旅行世界清单。请完整解压游戏文件。")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world_manifest.json"))
	if not parsed is Dictionary or not parsed.has("regions"):
		fail_load("旅行世界清单无法读取。")
		return
	manifest = parsed
	var landmark_ids: Array = []
	var building_ids: Array = []
	for landmark: Dictionary in manifest.get("landmarks", []):
		landmark_ids.append(str(landmark.id))
	for building: Dictionary in manifest.get("buildings", []):
		building_ids.append(str(building.id))
	state.configure(landmark_ids, building_ids)
	state.reset(vector(manifest.spawn))
	can_continue = state.load_from(save_path)
	load_preferences()
	for region: Dictionary in manifest.regions:
		ui.show_loading("正在载入 " + str(region.name) + " · 建筑、室内与步行碰撞…")
		await get_tree().process_frame
		var container := Node3D.new()
		container.name = str(region.id)
		container.position = vector(region.position)
		add_child(container)
		var full = load_scene(str(region.model))
		var low = load_scene(str(region.get("lod", region.model)))
		if full == null or low == null:
			return
		container.add_child(full)
		container.add_child(low)
		low.visible = false
		var collision = load_scene(str(region.collision))
		if collision == null:
			return
		container.add_child(collision)
		install_collision(collision)
		index_interiors(full)
		region_nodes.append({"region":region,"full":full,"low":low})
	if manifest.has("world_model"):
		var world = load_scene(str(manifest.world_model))
		if world == null:
			return
		add_child(world)
	if manifest.has("world_collision"):
		var collision = load_scene(str(manifest.world_collision))
		if collision == null:
			return
		add_child(collision)
		install_collision(collision)
	for item: Dictionary in manifest.get("interactions", []):
		actions.append(item)
	for landmark: Dictionary in manifest.get("landmarks", []):
		var action := landmark.duplicate(true)
		action["kind"] = "stamp"
		actions.append(action)
	for action: Dictionary in actions:
		add_marker(action)
	for item: Dictionary in manifest.get("lights", []):
		var light := OmniLight3D.new()
		light.position = vector(item.position)
		light.light_color = Color(float(item.color[0]),float(item.color[1]),float(item.color[2]))
		light.light_energy = float(item.energy)
		light.omni_range = float(item.range)
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		room_lights.append({"light":light,"building":str(item.building)})
	apply_settings(state.settings)
	world_ready = true
	player.teleport(vector(manifest.spawn))
	update_proximity()
	ui.show_title(can_continue, "四国街区 · 自由步行 · 建筑室内 · 旅行手记")
	if not state.last_warning.is_empty():
		ui.toast(state.last_warning, 7.0)

func load_scene(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		fail_load("无法找到场景：" + path)
		return null
	var resource = load(path)
	if not resource is PackedScene:
		fail_load("无法载入场景：" + path)
		return null
	return resource.instantiate() as Node3D

func fail_load(message: String) -> void:
	load_failed = true
	load_errors.append(message)
	ui.show_error(message)
	push_error(message)

func install_collision(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		mesh_node.visible = false
		if mesh_node.mesh:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 2
			var shape := CollisionShape3D.new()
			var geometry := mesh_node.mesh.create_trimesh_shape()
			geometry.backface_collision = true
			shape.shape = geometry
			body.add_child(shape)
			mesh_node.add_child(body)
	for child: Node in node.get_children():
		if not child is StaticBody3D:
			install_collision(child)

func index_interiors(node: Node) -> void:
	if node is MeshInstance3D and str(node.name).begins_with("IN_"):
		var owner_building: Dictionary = {}
		for building: Dictionary in manifest.buildings:
			if str(node.name).begins_with("IN_" + str(building.id) + "_"):
				# CH_CHURCH_TOWER also starts with CH_CHURCH_; use the
				# longest matching identifier, as the model exporter does.
				if str(building.id).length() > str(owner_building.get("id", "")).length():
					owner_building = building
		if not owner_building.is_empty():
			interiors.append({"node":node,"building":owner_building})
	for child: Node in node.get_children():
		index_interiors(child)

func add_marker(action: Dictionary) -> void:
	var marker := Node3D.new()
	marker.position = vector(action.position)
	add_child(marker)
	var pole := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.045
	mesh.bottom_radius = 0.055
	mesh.height = 1.8
	pole.mesh = mesh
	pole.position = Vector3(0.6, 0.9, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("a88650")
	material.metallic = 0.55
	material.roughness = 0.42
	pole.material_override = material
	marker.add_child(pole)
	var label := Label3D.new()
	label.text = str(action.label) + "\n[E] " + ("旅行盖章" if action.kind == "stamp" else "互动")
	label.position = Vector3(0.6, 2.2, 0)
	label.font_size = 38
	label.pixel_size = 0.005
	label.outline_size = 8
	label.modulate = Color("fff0c8")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		var readable := FontVariation.new()
		readable.base_font = load("res://assets/fonts/NotoSansSC.ttf")
		readable.variation_opentype = {"wght":450.0}
		label.font = readable
	marker.add_child(label)
	markers.append({"node":marker,"action":action})

func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not world_ready:
		return
	update_timer += delta
	if playing and modal == "":
		state.elapsed += delta
		autosave_timer += delta
		if autosave_timer >= 20:
			autosave_timer = 0
			save_progress()
		if player.global_position.y < -12 or absf(player.global_position.x)>190 or absf(player.global_position.z)>170:
			travel_to(current_region if not current_region.is_empty() else manifest.regions[0])
			ui.toast("已返回附近车站，可以继续探索。")
	if update_timer >= 0.22:
		update_timer = 0
		update_proximity()

func update_proximity() -> void:
	if not world_ready:
		return
	var pos: Vector3 = player.global_position
	var closest := INF
	for region: Dictionary in manifest.regions:
		var center := vector(region.position)
		var distance := Vector2(pos.x-center.x,pos.z-center.z).length()
		if distance < closest:
			closest = distance
			current_region = region
	current_building = {}
	var active_interiors: Dictionary = {}
	for building: Dictionary in manifest.buildings:
		var center := vector(building.bounds.center)
		var size := vector(building.bounds.size)
		var bounds := AABB(center-size*0.5,size)
		var inside := bounds.has_point(pos+Vector3.UP*0.7)
		if inside:
			current_building = building
			if playing and state.visit_building(str(building.id)):
				ui.toast("进入 " + str(building.label) + " · 探索 " + str(state.visited.size()) + "/" + str(manifest.buildings.size()))
		active_interiors[str(building.id)] = bounds.grow(2.5).has_point(pos) or pos.distance_to(vector(building.entrance))<9.0
	for item: Dictionary in interiors:
		item.node.visible = active_interiors.get(str(item.building.id), false)
	for item: Dictionary in room_lights:
		item.light.visible = active_interiors.get(item.building,false) and absf(item.light.position.y-pos.y)<4.0 and item.light.position.distance_to(pos)<17.0
	for item: Dictionary in region_nodes:
		var center := vector(item.region.position)
		var bounds := AABB(center-Vector3(70,6,60),Vector3(140,140,120)).grow(24.0)
		var near_region := bounds.has_point(pos)
		item.full.visible = near_region
		item.low.visible = not near_region
	for item: Dictionary in markers:
		var point := vector(item.action.position)
		item.node.visible = pos.distance_to(point)<34 and absf(pos.y-point.y)<6
	nearest = state.nearest_interaction(actions,pos,3.0)
	var prompt := ""
	if not nearest.is_empty():
		prompt = "E  ·  " + str(nearest.label)
	var location := str(current_region.get("name","欧洲大道"))
	if not current_building.is_empty():
		location += "  /  " + str(current_building.label)
	ui.update_hud(location,state.stamps.size(),manifest.landmarks.size(),state.visited.size(),manifest.buildings.size(),prompt)
	if modal == "map":
		ui.update_map_player(pos,player.rotation.y)

func _unhandled_input(event: InputEvent) -> void:
	if not world_ready:
		return
	if event.is_action_pressed("pause"):
		if not playing and modal == "settings":
			handle_action("back")
		elif modal != "" and playing:
			resume_game()
		elif playing:
			pause_game()
	elif event.is_action_pressed("map") and playing:
		if modal == "map":
			resume_game()
		else:
			show_map()
	elif event.is_action_pressed("interact") and player.enabled and not nearest.is_empty():
		activate_interaction(nearest)
	elif event.is_action_pressed("photo") and player.enabled:
		take_photo()

func handle_action(action: String, payload: Variant = null) -> void:
	match action:
		"back":
			if playing:
				pause_game()
			else:
				modal = "title"
				ui.show_title(can_continue,"四国街区 · 自由步行 · 旅行手记")
		"reload": get_tree().reload_current_scene()
		"new_trip": start_new_trip()
		"continue": continue_trip()
		"resume": resume_game()
		"travel": travel_to(payload)
		"map": show_map()
		"open_map": show_map()
		"open_settings":
			modal = "settings"
			player.enabled = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			ui.show_settings(state.settings)
		"photo":
			resume_game()
			take_photo()
		"settings":
			if payload is Dictionary:
				apply_settings(payload)
				save_progress()
			else:
				modal = "settings"
				player.enabled = false
				ui.show_settings(state.settings)
		"title":
			save_progress()
			playing = false
			player.enabled = false
			modal = "title"
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			ui.show_title(can_continue,"旅行已保存，随时回来继续探索。")
		"quit":
			save_progress()
			get_tree().quit()

func start_new_trip() -> void:
	state.reset(vector(manifest.spawn))
	player.teleport(state.position)
	player.eye.rotation.x = 0
	playing = true
	can_continue = true
	resume_game()
	save_progress()
	ui.toast("WASD 行走，按住鼠标右键观察；鼠标可自由移出窗口。M 查看地图。",8.0)

func continue_trip() -> void:
	player.teleport(state.position,state.yaw)
	player.eye.rotation.x = state.pitch
	playing = true
	resume_game()

func resume_game() -> void:
	if not playing:
		ui.show_title(can_continue,"四国街区 · 自由步行 · 旅行手记")
		return
	modal = ""
	player.enabled = true
	ambience.active = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.hide_modal()
	ui.set_game_visible(true)

func pause_game() -> void:
	modal = "pause"
	player.enabled = false
	ambience.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	save_progress()
	ui.show_pause()

func show_map() -> void:
	modal = "map"
	player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_map(manifest,player.global_position,player.rotation.y,state.stamps,state.visited.size())

func travel_to(region: Dictionary) -> void:
	if region.is_empty():
		return
	player.teleport(vector(region.spawn))
	player.eye.rotation.x = 0.0
	playing = true
	resume_game()
	update_proximity()
	save_progress()
	ui.toast("已到达 " + str(region.name) + "，也可沿欧洲大道步行前往其他景区。",5.0)

func activate_interaction(action: Dictionary) -> bool:
	if action.is_empty() or not action.has("position") or player.global_position.distance_to(vector(action.position))>3.05:
		return false
	match str(action.get("kind","")):
		"stamp":
			if state.collect_stamp(str(action.id)):
				ui.toast("旅行印章：" + str(action.label) + (" · 四国旅行护照已集齐！" if state.journey_complete() else ""),6.0)
				save_progress()
			else:
				ui.toast("已收集这里的旅行印章。")
		"station", "travel": show_map()
		"lift":
			player.teleport(vector(action.target),player.rotation.y)
			update_proximity()
			ui.toast(str(action.label) + " · 已到达")
			save_progress()
		_: return false
	return true

func save_progress() -> void:
	if not world_ready or not can_continue:
		return
	if playing:
		state.position = player.global_position
		state.yaw = player.rotation.y
		state.pitch = player.eye.rotation.x
	if not state.save_to(save_path):
		ui.toast(state.last_warning,6.0)

func apply_settings(options: Dictionary) -> void:
	for key: Variant in options:
		state.settings[key] = options[key]
	state.settings.fullscreen = false
	save_preferences()
	player.sensitivity = float(state.settings.sensitivity)
	ambience.volume = 0.0 if automated_test else float(state.settings.volume)
	var quality := int(state.settings.quality)
	sun.shadow_enabled = quality>0
	environment.environment.ssao_enabled = quality>0
	sun.directional_shadow_max_distance = 70.0 if quality==1 else 130.0
	get_viewport().msaa_3d = Viewport.MSAA_2X if quality==2 else Viewport.MSAA_DISABLED
	fit_game_window()

func desired_window_rect(work_area: Rect2i, requested: Vector2i) -> Rect2i:
	if work_area.size.x <= 0 or work_area.size.y <= 0:
		return Rect2i(work_area.position, Vector2i.ZERO)
	if requested.x <= 0 or requested.y <= 0:
		requested = Vector2i(1280,800)
	var available := Vector2i(maxi(mini(100,work_area.size.x),work_area.size.x-48),maxi(mini(100,work_area.size.y),work_area.size.y-72))
	var scale := minf(1.0,minf(float(available.x)/requested.x,float(available.y)/requested.y))
	var fitted := Vector2i(Vector2(requested)*scale)
	fitted = fitted.max(Vector2i.ONE).min(work_area.size)
	return Rect2i(work_area.position+(work_area.size-fitted)/2,fitted)

func fit_game_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var resolutions := [Vector2i(1280,800),Vector2i(1600,900),Vector2i(1920,1080)]
	var rect := desired_window_rect(DisplayServer.screen_get_usable_rect(),resolutions[clampi(int(state.settings.resolution),0,2)])
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if not window_initialized or DisplayServer.window_get_size()!=rect.size:
		DisplayServer.window_set_size(rect.size)
		DisplayServer.window_set_position(rect.position)
		window_initialized = true

func save_preferences() -> void:
	var config := ConfigFile.new()
	for key: String in state.settings:
		config.set_value("preferences",key,state.settings[key])
	config.save(save_path + ".settings.cfg")

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(save_path + ".settings.cfg") != OK:
		return
	var options: Dictionary = {}
	for key: String in state.settings:
		options[key] = config.get_value("preferences",key,state.settings[key])
	var clean := TravelState.new()
	clean.apply_save({"version":1,"position":[0,0,0],"stamps":[],"settings":options})
	state.settings = clean.settings

func take_photo() -> void:
	if photo_busy or DisplayServer.get_name()=="headless":
		return
	photo_busy = true
	ui.set_photo_mode(true)
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://photos"))
	var path := "user://photos/travel_" + str(int(Time.get_unix_time_from_system())) + "_" + str(Time.get_ticks_msec()) + ".png"
	var error := screenshot.save_png(ProjectSettings.globalize_path(path))
	ui.set_photo_mode(false)
	if error == OK:
		state.photos.append(path)
		save_progress()
		ui.toast("照片已保存 · " + ProjectSettings.globalize_path("user://photos"),6.0)
	else:
		ui.toast("照片保存失败，请检查存储空间。")
	photo_busy = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_progress()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and playing and modal == "" and not automated_test:
		pause_game()
