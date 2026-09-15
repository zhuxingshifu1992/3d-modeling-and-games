extends Node

var volume: float = 0.55
var active: bool = false
var player: AudioStreamPlayer
var steps: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var phase: float = 0.0
var wind: float = 0.0
var random: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	random.seed = 524317
	player = AudioStreamPlayer.new()
	var generator: AudioStreamGenerator = AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.22
	player.stream = generator
	add_child(player)
	player.play()
	playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	steps = AudioStreamPlayer.new()
	var wave: AudioStreamWAV = AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(4000)
	for i: int in range(2000):
		var t: float = float(i) / 2000.0
		var sample: float = random.randf_range(-1, 1) * pow(1.0 - t, 4) * 0.13
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	wave.data = bytes
	steps.stream = wave
	add_child(steps)

func _process(_delta: float) -> void:
	player.volume_db = linear_to_db(maxf(0.0001, volume * (0.65 if active else 0.25)))
	if playback == null:
		return
	var available: int = playback.get_frames_available()
	for i: int in range(available):
		wind = wind * 0.984 + random.randf_range(-1, 1) * 0.016
		phase += 1.0 / 22050.0
		var bird_window: float = maxf(0.0, sin(phase * 0.55) - 0.87) * 4.0
		var bird: float = sin(phase * 6600.0 + sin(phase * 28.0) * 9.0) * bird_window * 0.013
		var sample: float = wind * 0.18 + bird
		playback.push_frame(Vector2(sample, sample * 0.93))

func step() -> void:
	if active and volume > 0.001:
		steps.volume_db = linear_to_db(volume * 0.45)
		steps.pitch_scale = random.randf_range(0.88, 1.12)
		steps.play()

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.stop()
	if is_instance_valid(steps):
		steps.stop()
	playback = null
	if is_instance_valid(player):
		player.stream = null
	if is_instance_valid(steps):
		steps.stream = null
