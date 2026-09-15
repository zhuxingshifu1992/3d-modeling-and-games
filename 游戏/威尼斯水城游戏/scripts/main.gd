extends Node3D

const VoyageLogic = preload("res://scripts/voyage.gd")
const HudLayer = preload("res://scripts/harbor_ui.gd")
const Palette = preload("res://scripts/vertex_palette.gd")
const BoatMotion = preload("res://scripts/boat_motion.gd")
const CameraRig = preload("res://scripts/camera_rig.gd")
var voyage: RefCounted
var hud: CanvasLayer
var boat: Node3D
var camera: Camera3D
var water_material: ShaderMaterial
var coins: Array[Node3D] = []
var markers: Array[Node3D] = []
var route_nodes: Array[Vector3] = []
var route_visual: MeshInstance3D
var destination_marker: Node3D
var sounds: Dictionary = {}
var started: bool = false
var paused_game: bool = false
var muted: bool = false
var quality: String = "流畅"
var camera_mode: String = "follow"
var camera_occluders: Array[AABB] = []
var camera_snap: bool = true
# Backward-compatible property for existing scene/test tools.
var overview: bool:
	get: return camera_mode == "overview"
	set(value): camera_mode = "overview" if value else "follow"
var heading: float = 0.0
var speed: float = 0.0
var max_speed: float = 5.2
var elapsed: float = 0.0
var camera_yaw: float = 0.20
var camera_pitch: float = 1.10
var camera_distance: float = 30.0
var first_person_yaw: float = 0.0
var first_person_pitch: float = -0.06
var first_person_fov: float = 75.0
var orbit_timeout: float = 0.0
var rotating_camera: bool = false
var toast_cooldown: float = 0.0
var hud_clock: float = 0.0
var docking_clock: float = 0.0
var last_target: int = -1
var honk_cooldown: float = 0.0
var benchmark: bool = false
var bench_seconds: float = 90.0
var bench_elapsed: float = 0.0
var bench_last_tick: int = 0
var bench_frames: Array[float] = []
var bench_render_calls: Array[float] = []
var bench_done: bool = false
var save_clock: float = 0.0
var game_status: String = ""
var drift_boats: Array[Node3D] = []

func _ready() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_title("水城慢游 · 威尼斯贡多拉")
	voyage = VoyageLogic.new()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	benchmark = "--benchmark" in args
	if not benchmark:
		voyage.load_save()
	quality = "流畅" if "--low" in args else "标准"
	_apply_quality()
	_make_world()
	_make_city()
	_make_boat()
	_make_docks()
	_make_coins()
	_make_sounds()
	_make_camera()
	hud = HudLayer.new()
	add_child(hud)
	hud.action.connect(_hud_action)
	if "--first-person" in args: _set_camera_mode("first_person")
	if benchmark:
		started = true
		hud.hide_start()
		_navigate_to(voyage.target().pos)
	else:
		hud.show_start()
	_update_hud()
	print("GAME_READY renderer=", RenderingServer.get_video_adapter_name(), " quality=", quality)

func _make_world() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("75b9c9")
	sky_mat.sky_horizon_color = Color("d7e6d4")
	sky_mat.ground_bottom_color = Color("287f83")
	sky_mat.ground_horizon_color = Color("c6ddd0")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e2ecd8")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color("8ab9b4")
	env.fog_density = 0.0018
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58,-25,0)
	sun.light_color = Color("fff1d0")
	sun.light_energy = 0.8
	sun.shadow_enabled = false
	add_child(sun)
	var plane := PlaneMesh.new()
	plane.size = Vector2(800,800)
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.position.y = 0.08
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec2 boat_pos = vec2(0.0);
uniform float boat_speed = 0.0;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world_pos.xz;
 float waves=sin(p.x*0.65+TIME*0.42+sin(p.y*0.37))*sin(p.y*0.52-TIME*0.5);
 float shimmer=smoothstep(0.65,0.99,waves)*0.075;
 float d=length(p-boat_pos);
 float wake=sin(d*7.0-TIME*6.0)*exp(-d*0.65)*min(boat_speed*0.022,0.11);
 ALBEDO=mix(vec3(0.025,0.245,0.27),vec3(0.08,0.40,0.40),0.55+waves*0.18)+vec3(shimmer+wake);
}
"""
	water_material = ShaderMaterial.new()
	water_material.shader = shader
	water.material_override = water_material
	add_child(water)

func _make_city() -> void:
	var scene: PackedScene = load("res://assets/city.glb")
	if scene:
		var city: Node3D = scene.instantiate()
		city.name = "VeniceCity"
		Palette.apply(city)
		add_child(city)
	else:
		push_error("City asset failed to load")

func _make_boat() -> void:
	boat = Node3D.new()
	boat.name = "PlayerGondola"
	add_child(boat)
	boat.position = Vector3(0,0.20,34)
	var asset: PackedScene = load("res://assets/gondola.glb")
	if asset:
		var model: Node3D = asset.instantiate()
		Palette.apply(model)
		boat.add_child(model)
		model.scale = Vector3.ONE * 0.64
		model.rotation.y = PI/2
	else:
		var hull := MeshInstance3D.new()
		var shape := CapsuleMesh.new()
		shape.radius = 0.35
		shape.height = 3.6
		hull.mesh = shape
		hull.rotation.x = PI/2
		hull.material_override = _material(Color("20313a"))
		boat.add_child(hull)
	# A soft shadow/selection ring anchors the small player boat to the water.
	var ring := _ring(1.25, Color(0.72,0.92,0.84,0.7))
	ring.position.y = -0.02
	boat.add_child(ring)

func _material(color: Color, unlit: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unlit else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _ring(radius: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius-0.06
	torus.outer_radius = radius+0.06
	torus.rings = 28
	torus.ring_segments = 5
	instance.mesh = torus
	instance.material_override = _material(color)
	return instance

func _make_docks() -> void:
	for dock: Dictionary in VoyageLogic.DOCKS:
		var marker := Node3D.new()
		marker.position = dock.pos
		marker.name = "Dock_"+str(dock.id)
		add_child(marker)
		var ring := _ring(2.0,Color("f3c660"))
		ring.name = "Ring"
		ring.position.y = 0.02
		marker.add_child(ring)
		var pin := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = 0.0
		shape.bottom_radius = 0.35
		shape.height = 0.72
		shape.radial_segments = 5
		pin.mesh = shape
		pin.material_override = _material(Color("f3c660"))
		pin.rotation.z = PI
		pin.position.y = 3.1
		pin.name = "Pin"
		marker.add_child(pin)
		var label := Label3D.new()
		label.text = dock.name
		label.font_size = 38
		label.pixel_size = 0.012
		label.position.y = 4.1
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("fff1cf")
		label.outline_modulate = Color("173c46")
		label.outline_size = 12
		label.no_depth_test = false
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
		label.font = font
		marker.add_child(label)
		markers.append(marker)
	_make_route_visual()

func _make_route_visual() -> void:
	route_visual = MeshInstance3D.new()
	route_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(route_visual)
	destination_marker = Node3D.new()
	add_child(destination_marker)
	destination_marker.add_child(_ring(0.65,Color("aae7dc")))
	destination_marker.visible = false

func _make_coins() -> void:
	var positions: Array[Vector2] = [Vector2(-2,25),Vector2(2,20),Vector2(-2,14),Vector2(2,8),Vector2(-2,2),Vector2(2,-8),Vector2(-2,-18),Vector2(0,-27),Vector2(-12,0),Vector2(-24,0),Vector2(13,0),Vector2(25,0),Vector2(35,20),Vector2(35,0),Vector2(23,29),Vector2(12,31),Vector2(-12,32),Vector2(-33,22),Vector2(-35,1),Vector2(-25,-30),Vector2(22,-30)]
	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = 0.28
	coin_mesh.bottom_radius = 0.28
	coin_mesh.height = 0.08
	coin_mesh.radial_segments = 12
	var coin_mat := _material(Color("ffd86b"))
	for i: int in range(positions.size()):
		var c := MeshInstance3D.new()
		c.mesh = coin_mesh
		c.material_override = coin_mat
		c.position = Vector3(positions[i].x,0.7,positions[i].y)
		c.rotation.x = PI/2
		c.set_meta("coin_id",i)
		add_child(c)
		coins.append(c)

func _make_camera() -> void:
	camera_occluders = CameraRig.load_boxes("res://assets/camera_occluders.json")
	camera = Camera3D.new()
	camera.fov = 55
	camera.near = 0.15
	camera.far = 450
	add_child(camera)
	camera.current = true
	_update_camera(1.0)

func _process(delta: float) -> void:
	delta = minf(delta,0.1)
	elapsed += delta
	toast_cooldown = maxf(0,toast_cooldown-delta)
	honk_cooldown = maxf(0,honk_cooldown-delta)
	orbit_timeout = maxf(0,orbit_timeout-delta)
	if not paused_game:
		for i: int in range(coins.size()):
			var coin: Node3D = coins[i]
			if coin.visible:
				coin.position.y = 0.7+sin(elapsed*2.2+float(i))*.13
				coin.rotation.z += delta*1.2
		for marker: Node3D in markers:
			var active: bool = int(marker.name.get_slice("_",1)) == int(voyage.target_id)
			marker.visible = active
			if active:
				marker.get_node("Pin").position.y = 3.1+sin(elapsed*2.4)*.22
				var scale_ring: float = 1.0+sin(elapsed*2.4)*.06
				marker.get_node("Ring").scale = Vector3(scale_ring,1,scale_ring)
	_update_camera(delta)
	if started and not paused_game:
		_collect_coins()
		save_clock += delta
		if save_clock > 15:
			save_clock = 0
			if not benchmark: voyage.save()
	hud_clock += delta
	if hud_clock > .12:
		hud_clock = 0
		_update_hud()
	if benchmark:
		_benchmark_tick(delta)

func _physics_process(delta: float) -> void:
	if not started or paused_game or boat == null:
		return
	var thrust: float = 0.0
	var steer: float = 0.0
	if not benchmark:
		thrust = float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		steer = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	if absf(thrust)+absf(steer) > .01:
		route_nodes.clear()
		route_visual.visible = false
		destination_marker.visible = false
	max_speed = 5.2+float(voyage.level)*.9
	if route_nodes.size() > 0:
		var direction: Vector3 = route_nodes[0]-boat.position
		direction.y = 0
		var distance: float = direction.length()
		var final: bool = route_nodes.size()==1
		if distance < (0.65 if final else 1.1):
			if final: speed = 0.0
			route_nodes.pop_front()
			if route_nodes.is_empty():
				route_visual.visible = false
				destination_marker.visible = false
			else:
				_update_route_mesh()
		else:
			var angle: float = atan2(direction.x,-direction.z)
			var turn: float = wrapf(angle-heading,-PI,PI)
			heading = rotate_toward(heading,angle,delta*1.9)
			thrust = clampf(1.0-absf(turn)*.75,0.0,1.0)
			if final:
				# Brake far enough ahead even with fully upgraded oars. The
				# 2.5 budget stays below the actual 3.2 deceleration capacity.
				var arrival_speed: float = sqrt(2.0*2.5*maxf(0.0,distance-0.45))
				thrust *= clampf(arrival_speed/max_speed,0.0,1.0)
	else:
		heading += steer*delta*1.8
	var desired: float = thrust*max_speed
	if desired < 0: desired *= .52
	speed = move_toward(speed,desired,delta*(3.2 if thrust!=0.0 else 4.8))
	var forward := Vector3(sin(heading),0,-cos(heading))
	var old_pos: Vector3 = boat.position
	var wanted: Vector3 = old_pos+forward*speed*delta
	var safe: Vector3 = BoatMotion.constrain_motion(voyage,old_pos,wanted,heading)
	if Vector2(safe.x-wanted.x,safe.z-wanted.z).length()>.02:
		speed *= .35
		if toast_cooldown<=0 and not benchmark:
			hud.show_toast("轻轻碰到岸边了，倒一点船再转向就好")
			toast_cooldown = 5.0
	boat.position = Vector3(safe.x,0.20+sin(elapsed*2.2)*.035,safe.z)
	boat.rotation.y = -heading
	boat.rotation.z = -steer*minf(absf(speed)*.009,.04)+sin(elapsed*1.4)*.012
	water_material.set_shader_parameter("boat_pos",Vector2(boat.position.x,boat.position.z))
	water_material.set_shader_parameter("boat_speed",absf(speed))
	var event: Dictionary = voyage.update_at_position(boat.position,absf(speed),delta)
	if not event.is_empty():
		game_status = str(event.get("text",""))
		hud.show_toast(game_status)
		var kind: String = str(event.get("type",""))
		if kind=="pickup": _play_sound("pickup")
		else: _play_sound("delivery")
		if kind=="day_complete": hud.show_milestone(int(voyage.completed))
		if not benchmark: voyage.save()
		if benchmark:
			_navigate_to(voyage.target().pos)
		else:
			route_nodes.clear()
			route_visual.visible = false
			speed = 0
		_update_hud()
	# Benchmark uses the actual steering/collision path, never teleports to pass a mission.
	if benchmark and route_nodes.is_empty() and event.is_empty():
		var to_target: Vector3 = voyage.target().pos-boat.position
		if Vector2(to_target.x,to_target.z).length()>1.4:
			_navigate_to(voyage.target().pos)

func _update_camera(delta: float) -> void:
	if camera==null or boat==null: return
	if camera_mode == "first_person":
		var bow_forward := Vector3(sin(heading),0,-cos(heading))
		var eye: Vector3 = boat.position+bow_forward*0.60+Vector3(0,1.25,0)
		var look_yaw: float = heading+first_person_yaw
		var look := Vector3(sin(look_yaw)*cos(first_person_pitch),sin(first_person_pitch),-cos(look_yaw)*cos(first_person_pitch))
		camera.position = eye
		camera.fov = first_person_fov
		camera.near = 0.06
		camera.look_at(eye+look*10,Vector3.UP)
		camera_snap = false
		return
	camera.fov = 55
	camera.near = 0.15
	var focus: Vector3 = boat.position+Vector3(0,1,0)
	var desired: Vector3
	if overview:
		focus = Vector3(0,2,0)
		desired = Vector3(48,69,76)
	else:
		if orbit_timeout<=0 and not rotating_camera and absf(speed)>.2:
			camera_yaw = lerp_angle(camera_yaw,-heading,delta*.8)
		var horizontal: float = cos(camera_pitch)*camera_distance
		desired = focus+Vector3(sin(camera_yaw)*horizontal,sin(camera_pitch)*camera_distance,cos(camera_yaw)*horizontal)
		desired = CameraRig.safe_follow(focus,desired,camera_occluders)
	var factor: float = 1.0-exp(-delta*6.0)
	if camera_snap or camera.position.length()<.01: factor=1.0
	var next_position: Vector3 = camera.position.lerp(desired,factor)
	if not overview:
		next_position = CameraRig.safe_follow(focus,next_position,camera_occluders)
	camera.position = next_position
	var camera_up := Vector3.UP
	if absf((focus-camera.position).normalized().dot(Vector3.UP)) > 0.995:
		camera_up = Vector3(-sin(camera_yaw),0,-cos(camera_yaw))
	camera.look_at(focus,camera_up)
	camera_snap = false

func _set_camera_mode(mode: String) -> void:
	if mode not in ["follow","first_person","overview"]: return
	camera_mode = mode
	camera_snap = true
	rotating_camera = false
	if mode == "first_person":
		first_person_yaw = 0.0
		first_person_pitch = -0.06
		first_person_fov = 75.0
	elif mode == "follow":
		camera_pitch = 1.10
		camera_distance = maxf(28.0,camera_distance)
		camera_yaw = -heading+0.20
	_update_hud()

func _cycle_camera_mode() -> void:
	var modes: Array[String] = ["follow","first_person","overview"]
	_set_camera_mode(modes[(modes.find(camera_mode)+1)%modes.size()])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if started: _set_pause(not paused_game)
		elif event.keycode==KEY_SPACE and started:
			_honk()
		elif event.keycode==KEY_V and started:
			if not paused_game: _cycle_camera_mode()
		elif event.keycode==KEY_F11:
			var full: bool = DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if not started or paused_game: return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:
			rotating_camera = event.pressed
			orbit_timeout = 20
		elif event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if camera_mode == "first_person":
				first_person_fov = maxf(45,first_person_fov-4)
			else:
				camera_distance = maxf(11.0,camera_distance-2.0)
				overview = false
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if camera_mode == "first_person":
				first_person_fov = minf(90,first_person_fov+4)
			else:
				camera_distance = minf(56.0,camera_distance+2.0)
		elif event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			var origin: Vector3 = camera.project_ray_origin(event.position)
			var direction: Vector3 = camera.project_ray_normal(event.position)
			if direction.y<-.04:
				var point: Vector3 = origin+direction*((.25-origin.y)/direction.y)
				var chosen: Vector3 = point
				if not voyage.is_water(point,1.0):
					var closest: float = INF
					for dock: Dictionary in VoyageLogic.DOCKS:
						var d: float = Vector2(point.x-dock.pos.x,point.z-dock.pos.z).length()
						if d<closest: closest=d;chosen=dock.pos
					if closest>12: return
				_navigate_to(chosen)
	if event is InputEventMouseMotion and rotating_camera:
		if camera_mode == "first_person":
			first_person_yaw = clampf(first_person_yaw+event.relative.x*.004,-PI*.85,PI*.85)
			first_person_pitch = clampf(first_person_pitch-event.relative.y*.003,-.65,.45)
		else:
			overview = false
			camera_yaw -= event.relative.x*.006
			camera_pitch = clampf(camera_pitch+event.relative.y*.004,.32,1.3)
		orbit_timeout = 20

func _navigate_to(point: Vector3) -> void:
	var found: Array[Vector3] = voyage.route(boat.position,point)
	if found.is_empty():
		if not benchmark: hud.show_toast("点一下运河水面，或点“前往码头”")
		return
	route_nodes = found
	if route_nodes[0].distance_to(boat.position)<.8: route_nodes.pop_front()
	if route_nodes.is_empty():
		route_visual.visible = false
		destination_marker.visible = false
		return
	destination_marker.position = Vector3(point.x,.30,point.z)
	destination_marker.visible = true
	_update_route_mesh()

func _update_route_mesh() -> void:
	var immediate := ImmediateMesh.new()
	var m := _material(Color("9ee6d1"))
	immediate.surface_begin(Mesh.PRIMITIVE_LINES,m)
	var prev: Vector3 = boat.position
	prev.y = .23
	for next: Vector3 in route_nodes:
		var endpoint := Vector3(next.x,.23,next.z)
		var length: float = prev.distance_to(endpoint)
		var steps: int = maxi(1,int(length/.9))
		for j: int in range(steps):
			immediate.surface_add_vertex(prev.lerp(endpoint,float(j)/float(steps)))
			immediate.surface_add_vertex(prev.lerp(endpoint,(float(j)+.52)/float(steps)))
		prev = endpoint
	immediate.surface_end()
	route_visual.mesh = immediate
	route_visual.visible = not route_nodes.is_empty()

func _collect_coins() -> void:
	for c: Node3D in coins:
		if not c.visible: continue
		if Vector2(c.position.x-boat.position.x,c.position.z-boat.position.z).length()<1.25+float(voyage.level)*.55:
			var earned: int = voyage.collect_coin(int(c.get_meta("coin_id")))
			c.visible = false
			if earned>0: _play_sound("coin")

func _update_hud() -> void:
	if hud==null: return
	var target: Dictionary = voyage.target()
	var data: Dictionary = voyage.status()
	data.merge({"wallet":int(voyage.wallet),"completed":int(voyage.completed),"level":int(voyage.level),"target_name":str(target.name),"stage":str(voyage.stage),"distance":Vector2(target.pos.x-boat.position.x,target.pos.z-boat.position.z).length(),"speed":absf(speed),"fps":Engine.get_frames_per_second(),"quality":quality,"muted":muted,"boat_pos":boat.position,"target_pos":target.pos,"upgrade_cost":voyage.upgrade_cost(),"auto_nav":not route_nodes.is_empty()},true)
	data["camera_mode"] = camera_mode
	hud.set_hud(data)

func _hud_action(command: String) -> void:
	match command:
		"start":
			started = true
			paused_game = false
			hud.hide_start()
			hud.show_toast("欢迎上船！点“前往码头”，或用 W / ↑ 划向金色光圈")
		"resume": _set_pause(false)
		"pause": _set_pause(not paused_game)
		"view": _cycle_camera_mode()
		"target": _navigate_to(voyage.target().pos)
		"upgrade":
			if voyage.purchase_upgrade():
				_play_sound("delivery")
				hud.show_toast("船桨升级了！划得更快，也能捞到更远的金币")
				if not benchmark: voyage.save()
			elif int(voyage.level)>=3: hud.show_toast("船桨已经升级到最高级")
			else: hud.show_toast("再送几位游客，攒够 %d 金币就能升级" % voyage.upgrade_cost())
		"quality":
			quality = "流畅" if quality=="标准" else "标准"
			_apply_quality()
		"mute": muted = not muted
		"quit":
			if not benchmark: voyage.save()
			get_tree().quit()
	_update_hud()

func _set_pause(value: bool) -> void:
	paused_game = value
	rotating_camera = false
	hud.set_paused(value)
	if value and not benchmark: voyage.save()

func _apply_quality() -> void:
	get_viewport().scaling_3d_scale = .72 if quality=="流畅" else .9
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if quality=="流畅" else Viewport.MSAA_2X
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

func _honk() -> void:
	if honk_cooldown>0: return
	honk_cooldown = 1.4
	_play_sound("honk")
	if toast_cooldown<=0:
		hud.show_toast("嘟——让我们慢慢游过这座水城")
		toast_cooldown = 4

func _make_sounds() -> void:
	for entry: Array in [["coin",880.0,.14],["pickup",523.25,.25],["delivery",659.25,.42],["honk",196.0,.42]]:
		var data := PackedByteArray()
		var samples: int = int(22050*float(entry[2]))
		data.resize(samples*2)
		for i: int in range(samples):
			var time: float = float(i)/22050.0
			var envelope: float = sin(PI*float(i)/samples)
			var frequency: float = float(entry[1])
			var value: float = sin(TAU*frequency*time)+.24*sin(TAU*frequency*2*time)
			data.encode_s16(i*2,int(value*envelope*5000))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		stream.data = data
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = -8
		add_child(player)
		sounds[entry[0]] = player

func _play_sound(kind: String) -> void:
	if not muted and sounds.has(kind): sounds[kind].play()

func _benchmark_tick(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if bench_last_tick == 0:
		bench_last_tick = now
		return
	var delta: float = float(now-bench_last_tick)/1000000.0
	bench_last_tick = now
	bench_elapsed += delta
	if bench_elapsed>4:
		bench_frames.append(delta*1000)
		bench_render_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if bench_elapsed>=bench_seconds and not bench_done:
		bench_done = true
		var sorted: Array[float] = bench_frames.duplicate()
		sorted.sort()
		var total: float = 0.0
		for d: float in sorted: total += d
		var calls: float = 0.0
		for c: float in bench_render_calls: calls += c
		var slow_frames: int = 0
		for d: float in sorted:
			if d > 50.0: slow_frames += 1
		var report: Dictionary = {"renderer":RenderingServer.get_video_adapter_name(),"quality":quality,"window":str(DisplayServer.window_get_size()),"render_scale":get_viewport().scaling_3d_scale,"duration_seconds":bench_elapsed,"frames":sorted.size(),"average_fps":1000.0/(total/maxi(1,sorted.size())),"median_ms":sorted[int(sorted.size()*.5)],"p95_ms":sorted[mini(sorted.size()-1,int(sorted.size()*.95))],"p99_ms":sorted[mini(sorted.size()-1,int(sorted.size()*.99))],"average_draw_calls":calls/maxi(1,bench_render_calls.size()),"completed_trips":voyage.completed,"stage":voyage.stage,"target":voyage.target_id,"position":str(boat.position),"navigation_waypoints":route_nodes.size(),"coins":voyage.wallet}
		report.merge({"timing":"monotonic_wall_clock","warmup_seconds":4,"max_frame_ms":sorted.back(),"frames_over_50ms":slow_frames},true)
		report["camera_mode"] = camera_mode
		report["version"] = "1.1"
		var file := FileAccess.open("res://benchmark_"+("low" if quality=="流畅" else "standard")+"_"+camera_mode+".json",FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report,"\t"))
		print("BENCHMARK_COMPLETE ",JSON.stringify(report))
		get_tree().quit()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if voyage!=null and not benchmark: voyage.save()
