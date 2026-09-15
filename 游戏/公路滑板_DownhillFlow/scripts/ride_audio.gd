extends Node

var wind: AudioStreamPlayer
var wheels: AudioStreamPlayer
var muted: bool = false

func _ready() -> void:
	wind = AudioStreamPlayer.new()
	wheels = AudioStreamPlayer.new()
	add_child(wind)
	add_child(wheels)
	wind.stream = _noise_stream(9321, true)
	wheels.stream = _noise_stream(422, false)
	wind.volume_db = -60.0
	wheels.volume_db = -60.0
	wind.play()
	wheels.play()

func _noise_stream(seed_value: int, soft: bool) -> AudioStreamWAV:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var rate: int = 22050
	var frames: int = rate * 4
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(frames * 2)
	var smooth: float = 0.0
	for i in frames:
		var t: float = float(i) / float(rate)
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), 0.05 if soft else 0.36)
		var amplitude: float = smooth * (0.66 + 0.12 * sin(TAU * t * 0.5))
		if not soft:
			amplitude += sin(t * TAU * 75.0) * 0.025 + sin(t * TAU * 137.0) * 0.014
		samples.encode_s16(i * 2, int(clampf(amplitude, -1.0, 1.0) * 26000.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = samples
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream

func update_sound(speed: float, active: bool, drift: bool) -> void:
	var level: float = clampf(speed / 30.0, 0.0, 1.0)
	wind.volume_db = lerpf(-36.0, -13.0, level) if active and not muted else -60.0
	wheels.volume_db = lerpf(-29.0, -17.0, level) + (4.0 if drift else 0.0) if active and not muted else -60.0
	wheels.pitch_scale = lerpf(0.65, 1.65, level) + (0.3 if drift else 0.0)

func _exit_tree() -> void:
	for player: AudioStreamPlayer in [wind,wheels]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
