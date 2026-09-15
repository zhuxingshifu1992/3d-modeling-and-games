extends SceneTree
## CPU-only behavioral motion checks. All contact measurements are relative to
## the moving board, so route movement cannot masquerade as foot sliding.

const STEP := 1.0 / 120.0
const CONTACT_POSITION_LIMIT := 0.010
const CONTACT_ANGLE_LIMIT := deg_to_rad(2.0)
const PAUSE_STEP_LIMIT := 0.015
const PUSH_ACCELERATION_LIMIT := 35.0

var rider: Node3D
var board: Node3D
var skeleton: Skeleton3D
var foot_ids: Dictionary = {}
var reference: Dictionary = {}
var failures: Array[String] = []
var metrics: Dictionary = {}
var max_cache_error := 0.0
var max_cache_angle := 0.0
var sample_time := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := load("res://scripts/rider.gd") as Script
	_check(source != null and source.can_instantiate(), "rider script instantiates")
	if source == null or not source.can_instantiate():
		_finish()
		return
	rider = source.new() as Node3D
	root.add_child(rider)
	rider.call("build")
	board = rider.find_child("Longboard", true, false) as Node3D
	var rigs := rider.find_children("*", "Skeleton3D", true, false)
	_check(board != null and rigs.size() == 1, "one board and skeleton")
	if board == null or rigs.size() != 1:
		_finish()
		return
	skeleton = rigs[0] as Skeleton3D
	for side: String in ["L", "R"]:
		var index := skeleton.find_bone("Bip01_" + side + "_Foot")
		if index < 0:
			index = skeleton.find_bone("Bip01 " + side + " Foot")
		_check(index >= 0, side + " foot bone exists")
		foot_ids[side] = index
	if not failures.is_empty():
		_finish()
		return
	_set_push(false)
	for frame: int in range(240):
		_step(12.0, 0.0, 0.0, 0.0)
	reference = _feet()
	if OS.get_cmdline_user_args().has("--diagnose-push"):
		_diagnose_push(source)
		return
	_contact_sweeps()
	_idle_without_push()
	_active_push_cycle()
	_pause_resume()
	metrics["cache_position_error_m"] = max_cache_error
	metrics["cache_angle_error_deg"] = rad_to_deg(max_cache_angle)
	_check(max_cache_error <= 0.000001 and max_cache_angle <= 0.001,
		"immediate bone global poses equal explicitly updated poses")
	_finish()


func _set_push(requested: bool) -> void:
	_check(rider.has_method("set_push_requested"), "explicit push-request API exists")
	if rider.has_method("set_push_requested"):
		rider.call("set_push_requested", requested)


func _step(speed: float, steer: float, tuck: float, brake: float) -> void:
	sample_time += STEP
	rider.call("animate", STEP, speed, steer, tuck, brake, sample_time)
	# Skeleton getters should resolve dirty parent chains, not return last frame.
	var before: Array[Transform3D] = []
	for bone: int in range(skeleton.get_bone_count()):
		before.append(skeleton.get_bone_global_pose(bone))
	skeleton.force_update_all_bone_transforms()
	for bone: int in range(skeleton.get_bone_count()):
		var after := skeleton.get_bone_global_pose(bone)
		max_cache_error = maxf(max_cache_error, before[bone].origin.distance_to(after.origin))
		max_cache_angle = maxf(max_cache_angle, _angle(before[bone], after))


func _feet() -> Dictionary:
	var result := {}
	var to_board := board.global_transform.affine_inverse() * skeleton.global_transform
	for side: String in ["L", "R"]:
		result[side] = to_board * skeleton.get_bone_global_pose(foot_ids[side])
	return result


func _angle(a: Transform3D, b: Transform3D) -> float:
	# angle_to uses acos; float rounding otherwise reports ~0.08 degrees even
	# for bit-identical matrices, creating a false dirty-cache diagnosis.
	if a.basis.is_equal_approx(b.basis):
		return 0.0
	return a.basis.orthonormalized().get_rotation_quaternion().angle_to(
		b.basis.orthonormalized().get_rotation_quaternion())


func _contact_sweeps() -> void:
	var max_position := 0.0
	var max_angle := 0.0
	# Include transitions and simultaneous tuck/brake/steer extremes, rather
	# than checking only the four authored endpoint poses.
	for mode: int in range(4):
		for frame: int in range(480):
			var phase := float(frame) / 479.0
			var wave := 0.5 - 0.5 * cos(phase * TAU)
			var tuck := wave if mode == 0 or mode == 3 else 0.0
			var brake := wave if mode == 1 or mode == 3 else 0.0
			var steer := sin(phase * TAU) if mode >= 2 else 0.0
			_step(12.0, steer, tuck, brake)
			var feet := _feet()
			for side: String in ["L", "R"]:
				var actual: Transform3D = feet[side]
				var expected: Transform3D = reference[side]
				max_position = maxf(max_position, actual.origin.distance_to(expected.origin))
				max_angle = maxf(max_angle, _angle(actual, expected))
	metrics["contact_max_position_m"] = max_position
	metrics["contact_max_angle_deg"] = rad_to_deg(max_angle)
	_check(max_position <= CONTACT_POSITION_LIMIT, "planted ankle stays within 10 mm through posture and steer blends")
	_check(max_angle <= CONTACT_ANGLE_LIMIT, "planted ankle orientation stays within 2 degrees through blends")


func _idle_without_push() -> void:
	_set_push(false)
	for frame: int in range(240):
		_step(12.0, 0.0, 0.0, 0.0)
	var worst := 0.0
	for frame: int in range(360):
		_step(2.0, 0.0, 0.0, 0.0)
		var feet := _feet()
		for side: String in ["L", "R"]:
			var actual: Transform3D = feet[side]
			var expected: Transform3D = reference[side]
			worst = maxf(worst, actual.origin.distance_to(expected.origin))
	metrics["idle_no_push_max_displacement_m"] = worst
	_check(worst <= CONTACT_POSITION_LIMIT, "low speed without push input keeps both feet planted for 3 seconds")


func _active_push_cycle() -> void:
	_set_push(true)
	var excursion := 0.0
	var best_return := INF
	var support_drift := 0.0
	var max_acceleration := 0.0
	var previous_position: Vector3 = (_feet()["L"] as Transform3D).origin
	var previous_velocity := Vector3.ZERO
	for frame: int in range(480):
		_step(2.0, 0.0, 0.0, 0.0)
		var feet := _feet()
		var left: Transform3D = feet["L"]
		var right: Transform3D = feet["R"]
		var left_reference: Transform3D = reference["L"]
		var right_reference: Transform3D = reference["R"]
		var displacement := left.origin.distance_to(left_reference.origin)
		excursion = maxf(excursion, displacement)
		if frame > 120:
			best_return = minf(best_return, displacement)
		support_drift = maxf(support_drift, right.origin.distance_to(right_reference.origin))
		var velocity := (left.origin - previous_position) / STEP
		if frame > 1:
			# Second differences detect a derivative kink when a periodic push
			# wraps or a half-wave sine is abruptly clamped at zero.
			max_acceleration = maxf(max_acceleration, (velocity - previous_velocity).length() / STEP)
		previous_velocity = velocity
		previous_position = left.origin
	_set_push(false)
	for frame: int in range(240):
		_step(2.0, 0.0, 0.0, 0.0)
	var released: Transform3D = _feet()["L"]
	var rest: Transform3D = reference["L"]
	metrics["push_left_excursion_m"] = excursion
	metrics["push_left_closest_return_m"] = best_return
	metrics["push_support_foot_drift_m"] = support_drift
	metrics["push_peak_acceleration_m_s2"] = max_acceleration
	metrics["push_release_contact_error_m"] = released.origin.distance_to(rest.origin)
	_check(excursion >= 0.030, "push input creates a rear-foot stroke of at least 30 mm")
	_check(best_return <= CONTACT_POSITION_LIMIT, "rear foot returns to deck between push strokes")
	_check(support_drift <= CONTACT_POSITION_LIMIT, "front support foot stays planted throughout push")
	_check(max_acceleration <= PUSH_ACCELERATION_LIMIT, "push cycle has no phase-wrap acceleration spike above 35 m/s squared")
	_check(released.origin.distance_to(rest.origin) <= CONTACT_POSITION_LIMIT, "releasing push settles rear foot onto deck")


func _pause_resume() -> void:
	var source := load("res://scripts/rider.gd") as Script
	var subject := source.new() as Node3D
	var control := source.new() as Node3D
	root.add_child(subject)
	root.add_child(control)
	for instance: Node3D in [subject, control]:
		instance.call("build")
		if instance.has_method("set_push_requested"):
			instance.call("set_push_requested", true)
	var subject_rig := subject.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var control_rig := control.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var subject_clock := 0.0
	var control_clock := 0.0
	var worst_step := 0.0
	var worst_position_error := 0.0
	var worst_angle_error := 0.0
	# Both instances receive identical simulation deltas and control inputs.
	# Only the subject's external presentation clock jumps during each pause.
	# Ordinary fast foot recovery must not masquerade as clock dependence.
	for trial: int in range(10):
		for frame: int in range(23):
			subject_clock += STEP
			control_clock += STEP
			subject.call("animate", STEP, 2.0, 0.0, 0.0, 0.0, subject_clock)
			control.call("animate", STEP, 2.0, 0.0, 0.0, 0.0, control_clock)
		var before := {}
		for side: String in ["L", "R"]:
			before[side] = subject_rig.get_bone_global_pose(foot_ids[side]).origin
		subject_clock += 5.0 + STEP
		control_clock += STEP
		subject.call("animate", STEP, 2.0, 0.0, 0.0, 0.0, subject_clock)
		control.call("animate", STEP, 2.0, 0.0, 0.0, 0.0, control_clock)
		subject_rig.force_update_all_bone_transforms()
		control_rig.force_update_all_bone_transforms()
		for side: String in ["L", "R"]:
			var after := subject_rig.get_bone_global_pose(foot_ids[side]).origin
			worst_step = maxf(worst_step, (before[side] as Vector3).distance_to(after))
		for bone: int in range(subject_rig.get_bone_count()):
			var a := subject_rig.get_bone_global_pose(bone)
			var b := control_rig.get_bone_global_pose(bone)
			worst_position_error = maxf(worst_position_error, a.origin.distance_to(b.origin))
			worst_angle_error = maxf(worst_angle_error, _angle(a, b))
	metrics["pause_resume_max_step_m"] = worst_step
	metrics["pause_resume_step_diagnostic_limit_m"] = PAUSE_STEP_LIMIT
	metrics["pause_clock_ab_position_error_m"] = worst_position_error
	metrics["pause_clock_ab_angle_error_rad"] = worst_angle_error
	_check(worst_position_error <= 0.000001, "wall-clock pause preserves equal-delta bone positions within 1 micrometre")
	_check(worst_angle_error <= 0.0001, "wall-clock pause preserves equal-delta bone rotations within 0.0001 radians")
	subject.queue_free()
	control.queue_free()


func _check(condition: bool, description: String) -> void:
	if not condition and not failures.has(description):
		failures.append(description)


func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _diagnose_push(source: Script) -> void:
	# Replay the same deltas on a second rider while only the external clock
	# differs. This separates pause dependence from ordinary fast foot motion.
	var control := source.new() as Node3D
	root.add_child(control)
	control.call("build")
	control.call("set_push_requested", false)
	for frame: int in range(240):
		control.call("animate", STEP, 12.0, 0.0, 0.0, 0.0, float(frame + 1) * STEP)
	var control_skeleton := control.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	control.call("set_push_requested", true)
	_set_push(true)
	var records: Array[Dictionary] = []
	var previous := Vector3.ZERO
	var previous_target := Vector3.ZERO
	var previous_velocity := Vector3.ZERO
	var previous_target_velocity := Vector3.ZERO
	var max_clock_position_error := 0.0
	var max_clock_angle_error := 0.0
	var peak_frame := -1
	var peak_acceleration := -1.0
	var target_peak := 0.0
	var max_target_error := 0.0
	var control_time := 2.0
	var thigh_id: int = rider.call("_joint", "L Thigh")
	var calf_id: int = rider.call("_joint", "L Calf")
	for frame: int in range(600):
		if frame % 23 == 0:
			sample_time += 5.0
		_step(2.0, 0.0, 0.0, 0.0)
		control_time += STEP
		control.call("animate", STEP, 2.0, 0.0, 0.0, 0.0, control_time)
		control_skeleton.force_update_all_bone_transforms()
		for bone: int in range(skeleton.get_bone_count()):
			var a := skeleton.get_bone_global_pose(bone)
			var b := control_skeleton.get_bone_global_pose(bone)
			max_clock_position_error = maxf(max_clock_position_error, a.origin.distance_to(b.origin))
			max_clock_angle_error = maxf(max_clock_angle_error, _angle(a, b))
		var thigh := skeleton.get_bone_global_pose(thigh_id).origin
		var calf := skeleton.get_bone_global_pose(calf_id).origin
		var actual := skeleton.get_bone_global_pose(foot_ids["L"]).origin
		var contact: Transform3D = (rider.get("_feet") as Dictionary)["L"]
		var phase: float = rider.get("_push_phase")
		var active: bool = rider.get("_push_active")
		var offset: Vector3 = rider.call("_push_offset", phase) if active else Vector3.ZERO
		var target := contact.origin + offset
		var l1 := thigh.distance_to(calf)
		var l2 := calf.distance_to(actual)
		var velocity := (actual - previous) / STEP if frame > 0 else Vector3.ZERO
		var target_velocity := (target - previous_target) / STEP if frame > 0 else Vector3.ZERO
		var acceleration := (velocity - previous_velocity) / STEP if frame > 1 else Vector3.ZERO
		var target_acceleration := (target_velocity - previous_target_velocity) / STEP if frame > 1 else Vector3.ZERO
		var error := actual.distance_to(target)
		var row := {"frame": frame, "phase": phase, "active": active,
			"target": _vector(target), "actual": _vector(actual), "thigh": _vector(thigh),
			"target_error_m": error, "requested_reach_m": thigh.distance_to(target),
			"leg_length_m": l1 + l2, "reach_margin_m": l1 + l2 - 0.001 - thigh.distance_to(target),
			"velocity_m_s": _vector(velocity), "speed_m_s": velocity.length(),
			"acceleration_m_s2": _vector(acceleration), "acceleration_magnitude_m_s2": acceleration.length(),
			"target_acceleration_m_s2": target_acceleration.length()}
		records.append(row)
		if acceleration.length() > peak_acceleration:
			peak_acceleration = acceleration.length()
			peak_frame = frame
		target_peak = maxf(target_peak, target_acceleration.length())
		max_target_error = maxf(max_target_error, error)
		previous = actual
		previous_target = target
		previous_velocity = velocity
		previous_target_velocity = target_velocity
	var result := {"runtime_sha256": FileAccess.get_sha256("res://scripts/rider.gd"),
		"step_seconds": STEP, "peak_frame": peak_frame, "peak_actual_acceleration_m_s2": peak_acceleration,
		"peak_target_acceleration_m_s2": target_peak, "max_target_error_m": max_target_error,
		"clock_ab_position_error_m": max_clock_position_error, "clock_ab_angle_error_deg": rad_to_deg(max_clock_angle_error),
		"peak_neighborhood": records.slice(maxi(0, peak_frame - 3), mini(records.size(), peak_frame + 4)),
		"frames": records}
	DirAccess.make_dir_recursive_absolute("res://previews/motion")
	var file := FileAccess.open("res://previews/motion/push_diagnosis.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	result.erase("frames")
	print("PUSH_DIAGNOSIS ", JSON.stringify(result))
	control.queue_free()
	quit(0)


func _finish() -> void:
	print("MOTION_PROBE_METRICS ", JSON.stringify(metrics))
	for failure: String in failures:
		printerr("MOTION_PROBE_FAILED ", failure)
	if failures.is_empty():
		print("MOTION_PROBE_OK")
	quit(0 if failures.is_empty() else 1)
