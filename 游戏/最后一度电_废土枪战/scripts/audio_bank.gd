extends Node

const KEYS: Array[String] = ["rifle", "shotgun", "enemy_shot", "reload", "empty", "hit", "headshot", "footstep", "interact", "power", "alarm", "pickup", "heal", "death", "victory", "metal", "wind"]
const GAINS: Dictionary = {"rifle": -2.0, "shotgun": 0.0, "enemy_shot": -5.0, "reload": -9.0, "empty": -8.0, "hit": -7.0, "headshot": -5.0, "footstep": -14.0, "interact": -11.0, "power": -7.0, "alarm": -9.0, "pickup": -9.0, "heal": -9.0, "death": -6.0, "victory": -6.0, "metal": -13.0}
var streams: Dictionary = {}
var voices_2d: Array[AudioStreamPlayer] = []
var voices_3d: Array[AudioStreamPlayer3D] = []
var ambient: AudioStreamPlayer
var cursor_2d: int = 0
var cursor_3d: int = 0
var master_volume: float = 0.75
var initialized: bool = false
var closed: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func setup() -> void:
	if initialized or closed:
		return
	initialized = true
	rng.randomize()
	for key: String in KEYS:
		var path: String = "res://assets/audio/" + key + ".wav"
		var stream: AudioStreamWAV
		# Imported resources work in exported PCKs, where original WAV files may be remapped.
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStreamWAV
			if stream != null:
				stream = stream.duplicate() as AudioStreamWAV
		elif FileAccess.file_exists(path):
			# Before import, use the fixed PCM header written by generate_audio.py.
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
			if bytes.size() < 44:
				continue
			stream = AudioStreamWAV.new()
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			stream.mix_rate = 22050
			stream.stereo = false
			stream.data = bytes.slice(44)
		if stream == null:
			continue
		if key == "wind":
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = stream.data.size() / 2
		streams[key] = stream
	for i: int in range(6):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.name = "UIAudioVoice%02d" % i
		add_child(voice)
		voices_2d.append(voice)
	for i: int in range(12):
		var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice.name = "WorldAudioVoice%02d" % i
		voice.unit_size = 9.0
		voice.max_distance = 70.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.max_db = 0.0
		voice.panning_strength = 0.8
		add_child(voice)
		voices_3d.append(voice)
	ambient = AudioStreamPlayer.new()
	ambient.name = "YardWindLoop"
	add_child(ambient)
	ambient.stream = streams.get("wind") as AudioStream
	_apply_volume()

func _volume_db(gain: float) -> float:
	return linear_to_db(maxf(master_volume, 0.00001)) + gain

func play(key: String, position: Vector3 = Vector3.INF) -> void:
	if closed:
		return
	if not initialized:
		setup()
	if not streams.has(key) or key == "wind":
		return
	var gain: float = float(GAINS.get(key, -8.0))
	var pitch: float = rng.randf_range(0.94, 1.06) if key in ["rifle", "shotgun", "enemy_shot", "footstep", "metal"] else 1.0
	if position.is_finite():
		var voice: AudioStreamPlayer3D = voices_3d[cursor_3d]
		cursor_3d = (cursor_3d + 1) % voices_3d.size()
		voice.stop()
		voice.stream = streams[key] as AudioStream
		voice.global_position = position
		voice.volume_db = _volume_db(gain)
		voice.set_meta("gain", gain)
		voice.pitch_scale = pitch
		voice.play()
	else:
		var voice: AudioStreamPlayer = voices_2d[cursor_2d]
		cursor_2d = (cursor_2d + 1) % voices_2d.size()
		voice.stop()
		voice.stream = streams[key] as AudioStream
		voice.volume_db = _volume_db(gain)
		voice.set_meta("gain", gain)
		voice.pitch_scale = pitch
		voice.play()

func set_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	if initialized:
		_apply_volume()

func _apply_volume() -> void:
	for voice: AudioStreamPlayer in voices_2d:
		voice.volume_db = _volume_db(float(voice.get_meta("gain", -8.0)))
	for voice: AudioStreamPlayer3D in voices_3d:
		voice.volume_db = _volume_db(float(voice.get_meta("gain", -8.0)))
	ambient.volume_db = _volume_db(-20.0)

func set_ambience(active: bool) -> void:
	if closed:
		return
	if not initialized:
		setup()
	if active and ambient.stream != null and not ambient.playing:
		ambient.play()
	elif not active:
		ambient.stop()

func shutdown() -> void:
	# Final lifecycle cleanup, not a runtime leak workaround. No sleeps in production.
	if closed:
		return
	closed = true
	for voice: AudioStreamPlayer in voices_2d:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	for voice: AudioStreamPlayer3D in voices_3d:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	if is_instance_valid(ambient):
		ambient.stop()
		ambient.stream = null
	streams.clear()

func _exit_tree() -> void:
	shutdown()
