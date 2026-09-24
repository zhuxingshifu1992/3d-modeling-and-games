extends Node
## Small, self-contained sound controller. Add Audio.new() to the scene tree.

const CUE_STREAMS: Dictionary = {
	"step": preload("res://assets/audio/step.wav"),
	"door": preload("res://assets/audio/door_servo.wav"),
	"door_servo": preload("res://assets/audio/door_servo.wav"),
	"button": preload("res://assets/audio/button.wav"),
	"startup": preload("res://assets/audio/startup.wav"),
	"success": preload("res://assets/audio/success.wav"),
	"elevator_start": preload("res://assets/audio/elevator_start.wav"),
	"elevator_stop": preload("res://assets/audio/elevator_stop.wav"),
}
const CUE_VOLUMES: Dictionary = {
	"step": -8.0,
	"door": -8.0,
	"door_servo": -8.0,
	"button": -11.0,
	"startup": -9.0,
	"success": -9.0,
	"elevator_start": -12.0,
	"elevator_stop": -12.0,
}
const ONE_SHOT_POOL_SIZE := 4

var _ambient: AudioStreamPlayer
var _elevator_hum: AudioStreamPlayer
var _one_shots: Array[AudioStreamPlayer] = []
var _next_one_shot := 0
var _muted := false
var _in_cabin := false
var _elevator_active := false


func _ready() -> void:
	_ambient = _make_loop_player("Ambient", preload("res://assets/audio/ambient_industrial.wav"), -32.0)
	_elevator_hum = _make_loop_player("ElevatorHum", preload("res://assets/audio/elevator_hum.wav"), -80.0)
	for index: int in range(ONE_SHOT_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "OneShot%d" % (index + 1)
		add_child(player)
		_one_shots.append(player)
	_apply_levels()
	_ambient.play()


func play(cue: String) -> void:
	if _muted or not CUE_STREAMS.has(cue) or _one_shots.is_empty():
		return
	var player := _one_shots[_next_one_shot]
	_next_one_shot = (_next_one_shot + 1) % _one_shots.size()
	player.stop()
	player.stream = CUE_STREAMS[cue]
	player.volume_db = float(CUE_VOLUMES.get(cue, -10.0))
	player.play()


func set_cabin(value: bool) -> void:
	_in_cabin = value
	_apply_levels()


func set_muted(value: bool) -> void:
	_muted = value
	for player: AudioStreamPlayer in _one_shots:
		if value:
			player.stop()
	_apply_levels()


func elevator(active: bool) -> void:
	if active == _elevator_active:
		return
	_elevator_active = active
	if active:
		play("elevator_start")
		if not _muted:
			_elevator_hum.play()
	else:
		_elevator_hum.stop()
		play("elevator_stop")
	_apply_levels()


func _make_loop_player(player_name: String, source: AudioStreamWAV, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	var loop_stream := source.duplicate() as AudioStreamWAV
	loop_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	player.stream = loop_stream
	player.volume_db = volume
	add_child(player)
	return player


func _apply_levels() -> void:
	if not is_instance_valid(_ambient) or not is_instance_valid(_elevator_hum):
		return
	_ambient.volume_db = -80.0 if _muted else (-36.0 if _in_cabin else -32.0)
	_elevator_hum.volume_db = -80.0 if _muted else (-25.0 if _in_cabin else -21.0)
	if not _muted and _elevator_active and not _elevator_hum.playing:
		_elevator_hum.play()
	if _muted:
		_elevator_hum.stop()
