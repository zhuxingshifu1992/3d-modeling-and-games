extends Node3D

const State = preload("res://scripts/bay_state.gd")
var info: Dictionary
var state
var platform: Node3D
var gate: StaticBody3D
var door_left: Node3D
var door_right: Node3D
var door_collision: CollisionShape3D
var cabin: Node3D
var monitor_viewport: SubViewport
var sensor: Camera3D
var screens: Array[MeshInstance3D] = []
var screen_labels: Array[Label3D] = []
var mats := {}
var font: Font
var portal_z: float
var top_y: float
var door_amount := 0.0
var indicator: Label3D
var floor_gate: StaticBody3D
var monitor_panels: Array[Node3D] = []
var access_tween: Tween
var cabin_light: OmniLight3D
var panorama := false
var transfer_active := false
var cockpit := {}
var compact := false
var exterior_hatch: Node3D
var hatch_closed := Transform3D.IDENTITY
var boarding_step: MeshInstance3D

func setup(data: Dictionary) -> void:
	info = data
	name = "Bay_" + info.id
	position = info.position
	rotation.y = info.yaw
	cockpit = info.get("cockpit", {})
	compact = not cockpit.is_empty()
	top_y = float(cockpit.get("floor_y", float(info.height) * 0.60))
	portal_z = float(cockpit.get("portal_z", -float(info.height) * 0.11))
	state = State.new(top_y)
	panorama = info.id in ["nu", "unicorn"]
	font = load("res://assets/fonts/NotoSansSC.ttf")
	_material("steel", Color("33444f"), 0.6)
	_material("dark", Color("101b24"), 0.35)
	_material("edge", Color("71818b"), 0.6)
	_material("amber", Color("e8ac4b"), 0.3)
	_material("white", Color("c4cdd1"), 0.3)
	_material("seat", Color("18242d"), 0.0)
	_material("accent", info.color, 0.4)
	_material("glow", info.color * 0.8, 0.0, true)
	_material("green", Color("75dcc7"), 0.0, true)
	_material("black_screen", Color("071218"), 0.0, true)
	_material("diagnostic_screen", Color("0b2630"), 0.0, true)
	_build_lift()
	_build_bridge()
	_build_cabin()

func bind_machine(machine: Node3D) -> void:
	if not compact or machine == null:
		return
	exterior_hatch = machine.find_child("CockpitHatch", true, false) as Node3D
	if exterior_hatch != null:
		hatch_closed = exterior_hatch.transform

func _material(key: String, tint: Color, metal: float, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = metal
	m.roughness = 0.63
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats[key] = m
	return m

func _box(parent: Node3D, at: Vector3, size: Vector3, material: String, solid: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.material_override = mats[material]
	mesh.position = at
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		mesh.add_child(body)
	return mesh

func _label(parent: Node3D, text: String, at: Vector3, size: int, color: Color = Color.WHITE, yaw: float = 0.0) -> Label3D:
	var l := Label3D.new()
	l.font = font
	l.text = text
	l.font_size = size
	l.pixel_size = 0.008
	l.position = at
	l.rotation.y = yaw
	l.modulate = color
	l.outline_size = 2
	l.outline_modulate = Color("10202a")
	l.no_depth_test = false
	l.double_sided = false
	parent.add_child(l)
	return l

func _rail(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var center := (a + b) * 0.5
	var length := a.distance_to(b)
	var rail := _box(parent, center + Vector3.UP * 1.08, Vector3(0.055, 0.055, length), "amber")
	rail.look_at_from_position(rail.global_position, parent.to_global(b + Vector3.UP * 1.08), Vector3.UP)
	for p in [a, b]:
		_box(parent, p + Vector3.UP * 0.53, Vector3(0.06, 1.06, 0.06), "amber")
	# Invisible continuous guard avoids falling between thin posts.
	var wall := _box(parent, center + Vector3.UP * 0.52, Vector3(0.065, 1.04, length), "steel", true)
	wall.rotation = rail.rotation
	wall.visible = false

func _build_lift() -> void:
	# Guide columns are clear of both the central entrance and cockpit approach.
	for x in [-1.93, 1.93]:
		_box(self, Vector3(x, (top_y + 2.9) * 0.5, -7.8), Vector3(0.24, top_y + 2.9, 0.3), "steel", true)
		_box(self, Vector3(x, top_y * 0.5, -7.60), Vector3(0.055, top_y, 0.06), "edge")
		_box(self, Vector3(x, top_y * 0.5, -7.52), Vector3(0.028, top_y, 0.028), "glow")
	_box(self, Vector3(0, top_y + 2.8, -7.8), Vector3(4.2, 0.3, 0.5), "steel")
	_label(self, info.bay + "  /  PILOT ACCESS", Vector3(0, top_y + 2.83, -8.08), 26, Color("d9e4e8"), PI)
	platform = Node3D.new()
	platform.name = "LiftPlatform"
	add_child(platform)
	_box(platform, Vector3(0, 0.02, -7.8), Vector3(3.7, 0.20, 3.0), "steel", true)
	_box(platform, Vector3(0, 0.124, -7.8), Vector3(3.5, 0.006, 2.86), "dark")
	for x in [-1.73, 1.73]:
		_box(platform, Vector3(x, 0.135, -7.8), Vector3(0.10, 0.02, 2.86), "amber")
		_rail(platform, Vector3(x, 0.14, -9.25), Vector3(x, 0.14, -6.35))
	for z in [-9.16, -6.43]:
		_box(platform, Vector3(0, 0.135, z), Vector3(3.46, 0.02, 0.12), "amber")
	for z in range(12):
		_box(platform, Vector3(0, 0.134, -9.0 + z * 0.21), Vector3(2.9, 0.01, 0.025), "edge")
	gate = StaticBody3D.new()
	gate.position = Vector3(0, 0, -9.25)
	platform.add_child(gate)
	_box(gate, Vector3(0, 0.95, 0), Vector3(3.45, 0.06, 0.06), "amber")
	_box(gate, Vector3(0, 0.50, 0), Vector3(3.45, 0.05, 0.05), "amber")
	gate.visible = false
	gate.collision_layer = 0
	var gate_shape := CollisionShape3D.new()
	var gate_box := BoxShape3D.new()
	gate_box.size = Vector3(3.45, 1.4, 0.08)
	gate_shape.shape = gate_box
	gate_shape.position.y = 0.75
	gate.add_child(gate_shape)
	_box(platform, Vector3(1.43, 0.86, -7.48), Vector3(0.24, 1.45, 0.20), "dark")
	_box(platform, Vector3(1.43, 1.45, -7.59), Vector3(0.30, 0.24, 0.04), "glow")
	_label(platform, "E\n升降", Vector3(1.43, 1.45, -7.62), 15, Color("092128"), PI)
	indicator = _label(self, "01  /  地面待命", Vector3(2.43, 1.45, -9.18), 25, Color("9ee4dd"), PI)
	_box(self, Vector3(2.45, 1.36, -9.12), Vector3(1.4, 0.8, 0.08), "dark")
	# Small bevel-like entrance ramp, climbable without jump.
	var ramp := _box(self, Vector3(0, 0.015, -9.62), Vector3(3.3, 0.08, 0.7), "steel", true)
	ramp.rotation.x = -0.12

func _build_bridge() -> void:
	# A downward hatch may need the fixed bridge to stop before the armor sweep.
	# Keep the physical portal for pilot interaction; the step spans the gap only
	# after the hatch is completely open, using the existing visibility/collision gate.
	var bridge_end := float(cockpit.get("bridge_end_z", portal_z))
	var length := absf(bridge_end + 6.3)
	var center := (bridge_end - 6.3) * 0.5
	_box(self, Vector3(0, top_y + 0.025, center), Vector3(2.05, 0.19, length + 0.1), "steel", true)
	_box(self, Vector3(0, top_y + 0.125, center), Vector3(1.85, 0.01, length), "dark")
	for x in [-1.0, 1.0]:
		_rail(self, Vector3(x, top_y + 0.13, -6.26), Vector3(x, top_y + 0.13, bridge_end - 0.10))
		_box(self, Vector3(x, top_y + 0.14, center), Vector3(0.08, 0.015, length), "glow")
	if compact:
		var inner_front := float(cockpit.get("interior_front_z", portal_z))
		var docking_width := float(cockpit.get("docking_width", 1.12))
		boarding_step = _box(self, Vector3(0, top_y + 0.025, (bridge_end + inner_front) * 0.5), Vector3(docking_width, 0.19, inner_front - bridge_end + 0.08), "steel", true)
		boarding_step.name = "DockingStep"
		boarding_step.visible = false
		(boarding_step.get_child(0) as StaticBody3D).collision_layer = 0
	# Guard bridge end when the platform is below it.
	floor_gate = StaticBody3D.new()
	floor_gate.position = Vector3(0, top_y + 0.75, -6.27)
	add_child(floor_gate)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.04, 1.4, 0.08)
	shape.shape = box
	floor_gate.add_child(shape)
	_box(floor_gate, Vector3(0, 0.30, 0), Vector3(2.04, 0.05, 0.05), "amber")

func _build_cabin() -> void:
	cabin = Node3D.new()
	cabin.name = "Cockpit"
	cabin.position.y = top_y
	add_child(cabin)
	var rear := float(cockpit.get("rear_z", 1.3))
	var width := 1.20 if compact else 2.55
	var height := 2.08 if compact else 2.6
	var inner_front := float(cockpit.get("interior_front_z", portal_z))
	var depth := rear - inner_front
	var center_z := (rear + inner_front) * 0.5
	var wall_x := 0.58 if compact else 1.28
	_box(cabin, Vector3(0, 0.02, center_z), Vector3(width, 0.20, depth), "dark", true)
	_box(cabin, Vector3(0, height - 0.035, center_z), Vector3(width, 0.07, depth), "dark")
	_box(cabin, Vector3(0, height * 0.5, rear), Vector3(width, height, 0.06), "dark")
	for x in [-wall_x, wall_x]:
		_box(cabin, Vector3(x, height * 0.5, center_z), Vector3(0.04 if compact else 0.10, height, depth), "dark")
		_box(cabin, Vector3(x * 0.96, height - 0.15, center_z), Vector3(0.02, 0.03, depth * 0.65), "glow")
	if compact:
		_build_hatch_safety_gate()
	else:
		_build_standard_door()
	_build_pilot_equipment()

func _build_standard_door() -> void:
	# Door frame and two sliding halves.
	for x in [-1.25, 1.25]:
		_box(cabin, Vector3(x, 1.32, portal_z - 0.04), Vector3(0.11, 2.64, 0.22), "edge")
	_box(cabin, Vector3(0, 2.62, portal_z - 0.04), Vector3(2.60, 0.10, 0.22), "edge")
	for x in [-1.0, 1.0]:
		var half := Node3D.new()
		half.position = Vector3(x * 0.60, 0, portal_z - 0.07)
		cabin.add_child(half)
		_box(half, Vector3(0, 1.32, 0), Vector3(1.18, 2.56, 0.18), "steel")
		_box(half, Vector3(0, 1.30, -0.105), Vector3(1.05, 1.90, 0.045), "accent")
		_box(half, Vector3(-x * 0.48, 1.25, -0.135), Vector3(0.035, 2.0, 0.035), "glow")
		_label(half, "PILOT\n" + info.bay, Vector3(0, 1.45, -0.138), 24, Color("dfe8e9"), PI)
		if x < 0:
			door_left = half
		else:
			door_right = half
	var door_body := StaticBody3D.new()
	cabin.add_child(door_body)
	door_collision = CollisionShape3D.new()
	var door_shape := BoxShape3D.new()
	door_shape.size = Vector3(2.42, 2.6, 0.2)
	door_collision.shape = door_shape
	door_collision.position = Vector3(0, 1.35, portal_z)
	door_body.add_child(door_collision)

func _build_hatch_safety_gate() -> void:
	var barrier := StaticBody3D.new()
	barrier.name = "HatchSweepGuard"
	cabin.add_child(barrier)
	door_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.04, 2.1, 0.06)
	door_collision.shape = shape
	door_collision.position = Vector3(0, 1.15, float(cockpit.get("gate_z", -4.45)))
	barrier.add_child(door_collision)
	_box(self, Vector3(0, top_y + 0.14, float(cockpit.get("gate_z", -4.45))), Vector3(1.92, 0.02, 0.14), "amber")

func _build_pilot_equipment() -> void:
	# Human size seat, padded back and headrest.
	var seat_offset := float(cockpit.get("seat_offset_z", 0.0))
	_box(cabin, Vector3(0, 0.29, 0.56 + seat_offset), Vector3(0.52, 0.4, 0.70), "steel").name = "PilotSeatBase"
	_box(cabin, Vector3(0, 0.57, 0.43 + seat_offset), Vector3(0.68, 0.18, 0.67), "seat").name = "PilotSeatPad"
	var back := _box(cabin, Vector3(0, 1.05, 0.88 + seat_offset), Vector3(0.72, 1.02, 0.23), "seat")
	back.name = "PilotSeatBack"
	back.rotation.x = -0.12
	_box(cabin, Vector3(0, 1.70, 0.91 + seat_offset), Vector3(0.48, 0.28, 0.18), "seat").name = "PilotHeadrest"
	for x in [-0.42, 0.42]:
		var side_name := "Left" if x < 0 else "Right"
		_box(cabin, Vector3(x, 0.82, 0.38 + seat_offset), Vector3(0.15, 0.12, 0.73), "edge").name = "PilotArmrest" + side_name
		_box(cabin, Vector3(x, 0.95, 0.12 + seat_offset), Vector3(0.075, 0.24, 0.10), "dark").name = "PilotLever" + side_name
		_box(cabin, Vector3(x, 1.07, 0.08 + seat_offset), Vector3(0.095, 0.08, 0.16), "seat").name = "PilotGrip" + side_name
		_box(cabin, Vector3(x, 1.12, 0.06 + seat_offset), Vector3(0.025, 0.022, 0.026), "amber").name = "PilotButton" + side_name
	var console_x := float(cockpit.get("console_x", 0.50 if compact else 0.84))
	var console_offset := seat_offset + float(cockpit.get("console_offset_z", 0.0))
	for x in [-console_x, console_x]:
		var console_name := "ConsoleLeft" if x < 0 else "ConsoleRight"
		var console := _box(cabin, Vector3(x, 0.73, -0.39 + console_offset), Vector3(0.12 if compact else 0.51, 0.25, 1.13), "steel")
		console.name = console_name
		console.rotation.z = -signf(x) * 0.12
		for row in range(5):
			for col in range(1 if compact else 3):
				_box(cabin, Vector3(x + (0.0 if compact else -0.15 + col * 0.145), 0.88, -0.82 + row * 0.16 + console_offset), Vector3(0.055, 0.025, 0.055), "glow" if (row + col) % 4 == 0 else "edge").name = console_name + "Button_" + str(row) + "_" + str(col)
	monitor_viewport = SubViewport.new()
	monitor_viewport.name = "ExternalSensor"
	monitor_viewport.size = Vector2i(768, 432)
	if panorama:
		monitor_viewport.size = Vector2i(1280, 432)
	monitor_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	monitor_viewport.world_3d = get_viewport().world_3d
	add_child(monitor_viewport)
	sensor = Camera3D.new()
	sensor.cull_mask = 1
	sensor.fov = 60.0 if panorama else 76.0
	sensor.near = 0.15
	sensor.far = 230.0
	monitor_viewport.add_child(sensor)
	sensor.position = to_global(Vector3(0, float(info.height) * 0.93, -float(info.height) * 0.16 - 0.4))
	sensor.rotation.y = rotation.y
	sensor.rotation.x = deg_to_rad(-10)
	for side in [-1, 0, 1]:
		var panel := Node3D.new()
		panel.name = ["ScreenPanelLeft", "ScreenPanelCenter", "ScreenPanelRight"][side + 1]
		var front_screen_z := float(cockpit.get("screen_z", -1.45))
		var screen_side_x := float(cockpit.get("screen_side_x", 0.43 if compact else 0.78))
		panel.position = Vector3(side * screen_side_x, 1.48 if compact else 1.57, front_screen_z + (0.20 if compact else 0.45) if side != 0 else front_screen_z)
		panel.rotation.y = side * -0.55
		panel.set_meta("deployed_yaw", panel.rotation.y)
		cabin.add_child(panel)
		monitor_panels.append(panel)
		var size := (Vector2(0.26, 0.48) if side != 0 else Vector2(0.68, 0.52)) if compact else (Vector2(0.72, 0.74) if side != 0 else Vector2(1.40, 0.86))
		_box(panel, Vector3.ZERO, Vector3(size.x + 0.1, size.y + 0.10, 0.08), "edge").name = "ScreenFrame"
		var screen := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = size
		screen.mesh = quad
		screen.position.z = 0.045
		screen.material_override = mats.black_screen
		panel.add_child(screen)
		screens.append(screen)
		var l := _label(panel, "STANDBY" if side == 0 else "SYS / " + ("L" if side < 0 else "R"), Vector3(0, 0, 0.052), 20, info.color)
		l.pixel_size = 0.002 if compact else 0.004
		screen_labels.append(l)
	var plaque := _label(cabin, info.model + "   /   " + info.bay, Vector3(0, 1.93 if compact else 2.10, float(cockpit.get("screen_z", -1.45))), 20, info.color)
	plaque.pixel_size = 0.002 if compact else 0.003
	cabin_light = OmniLight3D.new()
	cabin_light.position = Vector3(0, 1.94 if compact else 2.18, -0.40)
	cabin_light.light_color = Color("8bc6d4") if info.id != "rx78" else Color("e9c797")
	cabin_light.light_energy = 1.1
	cabin_light.omni_range = 3.5
	cabin_light.light_cull_mask = 2
	cabin_light.visible = false
	cabin.add_child(cabin_light)
	# Cockpit excluded from its own sensor view, preventing screen recursion.
	for mesh in cabin.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 2
	for label in cabin.find_children("*", "Label3D", true, false):
		label.layers = 2

func tick(delta: float) -> void:
	platform.position.y = state.y
	gate.visible = state.moving or state.at_top
	gate.collision_layer = 1 if gate.visible else 0
	floor_gate.collision_layer = 0 if state.at_top and not state.moving else 1
	floor_gate.visible = not state.at_top or state.moving
	door_amount = move_toward(door_amount, 1.0 if state.hatch_open and (not state.seated or transfer_active) else 0.0, delta * 0.85)
	cabin_light.visible = state.hatch_open or state.seated
	if exterior_hatch != null:
		# Pull the armor clear of its collar before lifting; reverse this sequence on closing.
		var extension := float(cockpit.get("hatch_travel", 0.55)) * clampf(door_amount / 0.25, 0.0, 1.0)
		var angle := deg_to_rad(float(cockpit.get("hatch_angle", 90.0))) * clampf((door_amount - 0.25) / 0.75, 0.0, 1.0)
		exterior_hatch.transform = hatch_closed * Transform3D(Basis(Vector3.RIGHT, angle), Vector3(0, 0, -extension))
	elif not compact:
		door_left.position.x = -0.60 - door_amount * 1.24
		door_right.position.x = 0.60 + door_amount * 1.24
	door_collision.disabled = door_amount > (0.999 if compact else 0.92)
	if boarding_step != null:
		boarding_step.visible = door_amount > 0.999
		(boarding_step.get_child(0) as StaticBody3D).collision_layer = 1 if boarding_step.visible else 0
	indicator.text = "%s  /  %s\n高度 %.1f m" % [info.bay, "升降中" if state.moving else ("登舱层" if state.at_top else "地面待命"), state.y]

func set_power(stage: int) -> void:
	monitor_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if stage >= 2 else SubViewport.UPDATE_DISABLED
	for i in range(screens.size()):
		var video := StandardMaterial3D.new()
		video.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		video.albedo_texture = monitor_viewport.get_texture()
		if panorama:
			video.uv1_scale.x = 0.48 if i == 1 else 0.26
			video.uv1_offset.x = [0.0, 0.26, 0.74][i]
		var external := stage >= 2 and (panorama or i == 1)
		screens[i].material_override = video if external else (mats.diagnostic_screen if stage > 0 else mats.black_screen)
		screen_labels[i].visible = not external
		if i == 1:
			screen_labels[i].text = "AUX POWER\n辅助供电接通" if stage == 1 else "STANDBY\n等待驾驶员"
		elif stage > 0:
			var system: String = {"rx78": "CORE BLOCK", "freedom": "DRAGOON", "wing": "ZERO SYSTEM", "exia": "GN DRIVE"}.get(info.id, "PSYCHO FRAME")
			screen_labels[i].text = (system + "\n\nPOWER  ONLINE\nLINK   ACTIVE\n\n■■■■■■■■\nAUX    100%") if i == 0 else ("PILOT  SYSTEM\n\nSEAT  LOCKED\nBAY  " + info.bay + "\n\n" + ("ALL CHECKS OK" if stage == 3 else "STANDBY"))
			screen_labels[i].font_size = 15
		else:
			screen_labels[i].text = "SYS / STANDBY"

func set_access(open: bool, immediate: bool = false) -> void:
	# Instrument cluster retracts above the entry path before the pilot walks through.
	if access_tween != null and access_tween.is_valid():
		access_tween.kill()
	var fold_yaw_zero := compact and bool(cockpit.get("screen_fold_yaw_zero", false))
	var fold_height := float(cockpit.get("screen_fold_height", 1.98 if compact else 2.42))
	if immediate:
		for panel in monitor_panels:
			panel.position.y = fold_height if open else (1.48 if compact else 1.57)
			panel.rotation.x = -PI * 0.5 if compact and open else 0.0
			if fold_yaw_zero:
				panel.rotation.y = 0.0 if open else float(panel.get_meta("deployed_yaw", 0.0))
		return
	access_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	for panel in monitor_panels:
		if fold_yaw_zero:
			# Clear side-wall width before folding; reverse the order when deploying.
			var fold_delay := 0.15 if open else 0.0
			var yaw_delay := 0.0 if open else 0.30
			access_tween.tween_property(panel, "rotation:y", 0.0 if open else float(panel.get_meta("deployed_yaw", 0.0)), 0.15).set_delay(yaw_delay).set_trans(Tween.TRANS_SINE)
			access_tween.tween_property(panel, "position:y", fold_height if open else 1.48, 0.30).set_delay(fold_delay).set_trans(Tween.TRANS_SINE)
			access_tween.tween_property(panel, "rotation:x", -PI * 0.5 if open else 0.0, 0.30).set_delay(fold_delay).set_trans(Tween.TRANS_SINE)
			continue
		access_tween.tween_property(panel, "position:y", fold_height if open else (1.48 if compact else 1.57), 0.45).set_trans(Tween.TRANS_SINE)
		if compact:
			access_tween.tween_property(panel, "rotation:x", -PI * 0.5 if open else 0.0, 0.45)

func on_platform(world_point: Vector3) -> bool:
	var p := to_local(world_point)
	return absf(p.x) < 1.6 and p.z > -9.15 and p.z < -6.45 and absf(p.y - state.y - 0.12) < 0.45

func near_hatch(world_point: Vector3) -> bool:
	var p := to_local(world_point)
	var inside_width := absf(p.x) < (0.9 if compact else 1.8)
	if compact and cockpit.has("entry_half_width"):
		# Configured edges are inclusive; tolerate floating-point world/local conversion.
		inside_width = absf(p.x) <= float(cockpit.entry_half_width) + 0.00001
	return inside_width and absf(p.y - top_y - 0.12) < 0.6 and p.z > portal_z - (2.8 if compact else 2.1) and p.z < portal_z + 0.4

func seat_position() -> Vector3:
	return to_global(Vector3(0, top_y + 0.14, 0.38 + float(cockpit.get("seat_offset_z", 0.0))))

func exit_position() -> Vector3:
	return to_global(Vector3(0, top_y + 0.14, float(cockpit.get("wait_z", portal_z - 0.8))))
