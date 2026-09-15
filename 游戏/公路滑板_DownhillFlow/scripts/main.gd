extends Node3D

const RouteScript = preload("res://scripts/route.gd")
const WorldScript = preload("res://scripts/world.gd")
const RiderScript = preload("res://scripts/rider.gd")
const RideScript = preload("res://scripts/ride_state.gd")
const HudScript = preload("res://scripts/hud.gd")
const SoundScript = preload("res://scripts/ride_audio.gd")

var route = RouteScript.new()
var ride = RideScript.new()
var coast: Node3D
var rider: Node3D
var camera: Camera3D
var hud: CanvasLayer
var sound: Node
var environment: Environment
var sun: DirectionalLight3D
var camera_mode: int = 0
var clock_time: float = 0.0
var best_time: float = 0.0
var menu_distance: float = 100.0
var cam_initialized: bool = false
var previous_rider_position: Vector3 = Vector3.ZERO
var last_phase: String = "menu"
var low_quality: bool = false
var auto_demo: bool = false
var capture_path: String = ""
var capture_at: float = 0.0
var capture_distance: float = -1.0
var captured: bool = false
var exit_after: float = 0.0
var fps_sum: float = 0.0
var fps_count: int = 0
var benchmark_seconds: float = 0.0
var settings_path: String = "user://settings.cfg"
var skid_root: Node3D
var skid_material: StandardMaterial3D
var skid_points: Array[Vector3] = []
var skid_meshes: Array[MeshInstance3D] = []
var dust: GPUParticles3D
var initial_mode: String = ""

func _ready() -> void:
	Engine.max_fps = 60
	_parse_args()
	_load_settings()
	_setup_environment()
	coast = WorldScript.new()
	add_child(coast)
	coast.build(route)
	rider = RiderScript.new()
	add_child(rider)
	rider.build()
	camera = Camera3D.new()
	camera.near = 0.08
	camera.far = 8000.0
	camera.current = true
	add_child(camera)
	skid_root = Node3D.new()
	add_child(skid_root)
	skid_material = StandardMaterial3D.new()
	skid_material.albedo_color = Color(0.075,0.10,0.11,0.38)
	skid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skid_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_setup_dust()
	hud = HudScript.new()
	add_child(hud)
	hud.start_requested.connect(_start_ride)
	hud.resume_requested.connect(func(): ride.toggle_pause())
	hud.restart_requested.connect(func(): _start_ride(ride.mode))
	hud.menu_requested.connect(func():
		ride.phase = "menu"
		ride.drifting = false
		ride.tuck = 0.0
		skid_points.clear()
		cam_initialized = false
		menu_distance = 100.0
		hud.set_phase("menu")
	)
	sound = SoundScript.new()
	add_child(sound)
	sound.muted = bool(get_meta("muted", false))
	if not initial_mode.is_empty():
		_start_ride(initial_mode)
	print("DOWNHILL_READY renderer=", RenderingServer.get_current_rendering_method(), " low=", low_quality)

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--test": settings_path = "user://test_settings.cfg"
		if arg == "--low": low_quality = true
		if arg == "--demo": auto_demo = true; initial_mode = "challenge"
		if arg == "--free": initial_mode = "free"
		if arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
		if arg.begins_with("--capture-at="): capture_at = arg.trim_prefix("--capture-at=").to_float()
		if arg.begins_with("--distance="): capture_distance = arg.trim_prefix("--distance=").to_float()
		if arg.begins_with("--exit-after="): exit_after = arg.trim_prefix("--exit-after=").to_float()
		if arg.begins_with("--camera="): camera_mode = clampi(arg.trim_prefix("--camera=").to_int(), 0, 2)

func _setup_environment() -> void:
	var setup: Dictionary = preload("res://scripts/lighting.gd").build(self, low_quality)
	environment = setup.environment
	sun = setup.sun

func _setup_dust() -> void:
	dust = GPUParticles3D.new()
	dust.amount = 26 if low_quality else 50
	dust.lifetime = 0.55
	dust.emitting = false
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.18,0.18)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.76,0.80,0.78,0.22)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	dust.draw_pass_1 = quad
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = Vector3(0,0.25,1)
	process.spread = 32.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 1.6
	process.gravity = Vector3(0,0.15,0)
	process.scale_min = 0.25
	process.scale_max = 1.2
	dust.process_material = process
	add_child(dust)

func _start_ride(mode: String) -> void:
	ride.start(mode)
	rider.reset_motion()
	cam_initialized = false
	for mesh in skid_meshes:
		mesh.queue_free()
	skid_meshes.clear()
	skid_points.clear()
	if capture_distance >= 0.0:
		ride.distance = clampf(capture_distance, 0.0, 2599.0)
	hud.set_phase("riding")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ENTER:
			if ride.phase == "menu" or ride.phase == "finished": _start_ride("challenge")
		KEY_P, KEY_ESCAPE:
			ride.toggle_pause()
		KEY_R:
			if ride.phase != "menu": _start_ride(ride.mode)
		KEY_C:
			camera_mode = (camera_mode + 1) % 3
			cam_initialized = false
		KEY_M:
			sound.muted = not sound.muted
			_save_settings()
		KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _controls() -> Dictionary:
	if auto_demo:
		return {"push": true, "tuck": true, "steer": -ride.offset * 0.45}
	return {
		"push": Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP),
		"steer": float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		"brake": Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN),
		"drift": Input.is_physical_key_pressed(KEY_SPACE),
		"tuck": Input.is_physical_key_pressed(KEY_SHIFT)
	}

func _physics_process(delta: float) -> void:
	if not is_instance_valid(camera): return
	var sample: Dictionary = route.sample(ride.distance)
	var old_laps: int = ride.laps
	ride.step(delta, _controls(), sample.slope, sample.curvature)
	if ride.laps != old_laps:
		cam_initialized = false
		skid_points.clear()
	if ride.phase == "finished" and last_phase != "finished":
		if not auto_demo and capture_distance < 0.0:
			if best_time <= 0.0 or ride.elapsed < best_time:
				best_time = ride.elapsed
			_save_settings()
	last_phase = ride.phase

func _process(delta: float) -> void:
	if not is_instance_valid(camera): return
	clock_time += delta
	var display_distance: float = ride.distance
	var display_speed: float = ride.speed
	var display_steer: float = ride.steer
	if ride.phase == "menu":
		menu_distance += delta * 7.0
		display_distance = fmod(menu_distance, 550.0) + 30.0
		display_speed = 13.0
		display_steer = sin(clock_time * 0.8) * 0.12
	var sample: Dictionary = route.sample(display_distance)
	display_steer = clampf(display_steer + float(sample.curvature) * 75.0,-1.0,1.0)
	var forward: Vector3 = sample.forward
	var right: Vector3 = sample.right
	var up: Vector3 = sample.up
	var offset: float = ride.offset if ride.phase != "menu" else 0.45
	var rider_position: Vector3 = sample.position + right * offset + up * 0.07
	rider.position = rider_position
	rider.basis = Basis(right, up, -forward).orthonormalized()
	var frozen: bool = ride.phase == "paused" or ride.phase == "finished"
	rider.visible = camera_mode != 2 or ride.phase == "menu"
	if not frozen:
		rider.set_push_requested(ride.phase == "riding" and bool(_controls().get("push", false)))
		rider.animate(delta, display_speed, display_steer, ride.tuck, maxf(ride.braking, 0.75 if ride.drifting else 0.0), clock_time)
	_update_camera(delta, sample, rider_position, display_speed, display_steer)
	if coast.has_method("update_view"): coast.update_view(display_distance)
	_update_skids(rider_position, right, up, frozen)
	dust.position = rider_position + up * 0.12
	dust.emitting = ride.phase == "riding" and ride.drifting
	hud.update_state(ride, camera_mode, sound.muted, best_time)
	sound.update_sound(display_speed, ride.phase == "riding", ride.drifting)
	if clock_time > 3.0 and delta > 0.0:
		fps_sum += minf(1.0 / delta, 1000.0)
		fps_count += 1
		benchmark_seconds += delta
	if not captured and not capture_path.is_empty() and clock_time >= capture_at:
		captured = true
		_capture.call_deferred()
	if exit_after > 0.0 and clock_time >= exit_after:
		print("BENCHMARK avg_fps=", snappedf(fps_count / maxf(benchmark_seconds,0.01),0.1), " frames=",fps_count," distance=",ride.distance," phase=",ride.phase, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " triangles=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		get_tree().quit()

func _update_camera(delta: float, sample: Dictionary, pos: Vector3, speed: float, steer: float) -> void:
	var f: Vector3 = sample.forward
	var r: Vector3 = sample.right
	var desired: Vector3
	var target: Vector3
	var mode: int = 0 if ride.phase == "menu" else camera_mode
	match mode:
		0:
			desired = pos - f * 2.7 + Vector3.UP * 1.4 + r * 0.2
			target = pos + f * 7.0 + Vector3.UP * 1.2
		1:
			desired = pos - f * 7.4 + Vector3.UP * 3.2 - r * 0.5
			target = pos + f * 5.0 + Vector3.UP * 0.65
		_:
			desired = pos + f * 0.12 + Vector3.UP * 1.25
			target = pos + f * 20.0 + Vector3.UP * 0.8
	if ride.phase == "menu":
		desired -= r * 1.7
		target += r * 0.6
	var smoothing: float = 1.0 - exp(-8.0 * delta)
	if not cam_initialized:
		camera.position = desired
		cam_initialized = true
	else:
		# Carry the camera with the rider before damping offsets; otherwise speed
		# introduces metres of lag and makes the character shrink during acceleration.
		camera.position += pos - previous_rider_position
		camera.position = camera.position.lerp(desired, smoothing)
	previous_rider_position = pos
	var roll: float = -steer * 0.055 - clampf(float(sample.curvature) * 24.0,-0.10,0.10)
	camera.look_at(target, Vector3.UP.rotated(f, roll))
	camera.fov = lerpf(camera.fov, 65.0 + speed * 0.36, smoothing)

func _update_skids(pos: Vector3, right: Vector3, up: Vector3, frozen: bool) -> void:
	if ride.phase != "riding":
		skid_points.clear()
		return
	if frozen: return
	if not ride.drifting:
		skid_points.clear()
		return
	var left: Vector3 = pos - right * 0.17 + up * 0.028
	var other: Vector3 = pos + right * 0.17 + up * 0.028
	if skid_points.size() == 2:
		if left.distance_to(skid_points[0]) < 0.55: return
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for pair in [[skid_points[0],left], [skid_points[1],other]]:
			var width: Vector3 = right * 0.055
			var vertices: Array = [pair[0]-width,pair[0]+width,pair[1]+width,pair[0]-width,pair[1]+width,pair[1]-width]
			for v in vertices:
				surface.set_normal(up)
				surface.add_vertex(v)
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = surface.commit()
		mesh.material_override = skid_material
		skid_root.add_child(mesh)
		skid_meshes.append(mesh)
		if skid_meshes.size() > 140:
			skid_meshes.pop_front().queue_free()
	skid_points = [left,other]

func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(settings_path) == OK:
		best_time = float(config.get_value("records","best_time",0.0))
		set_meta("muted", bool(config.get_value("audio","muted",false)))

func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("records","best_time",best_time)
	config.set_value("audio","muted",sound.muted)
	config.save(settings_path)

func _capture() -> void:
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(capture_path)
	print("CAPTURE path=",capture_path," code=",err)
