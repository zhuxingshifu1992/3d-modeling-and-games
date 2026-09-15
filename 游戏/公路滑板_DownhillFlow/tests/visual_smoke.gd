extends SceneTree

var game: Node
var output: String = "res://previews/"

func _initialize() -> void:
	run.call_deferred()

func capture(filename: String) -> void:
	for i in 8: await process_frame
	RenderingServer.force_draw(false)
	var img: Image = root.get_texture().get_image()
	var error: Error = img.save_png(ProjectSettings.globalize_path(output + filename))
	print("VISUAL_CAPTURE ",filename," error=",error," size=",img.get_size())
	assert(error == OK)

func run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await capture("开始菜单.png")
	game.hud.start_requested.emit("challenge")
	game.set_physics_process(false)
	game.ride.distance = 410.0
	game.ride.speed = 19.0
	game.ride.steer = -0.65
	game.ride.tuck = 0.3
	game.ride.drifting = true
	game.ride.elapsed = 23.46
	game.cam_initialized = false
	await capture("压弯滑行.png")
	game.ride.toggle_pause()
	await capture("暂停菜单.png")
	game.ride.toggle_pause()
	game.camera_mode = 2
	game.cam_initialized = false
	await capture("第一人称.png")
	game.camera_mode = 0
	game.cam_initialized = false
	game.ride.phase = "finished"
	game.ride.elapsed = 127.62
	game.ride.top_speed = 26.5
	game.ride.flow = 260.0
	game.best_time = 127.62
	await capture("终点成绩.png")
	game.queue_free()
	for i in 6: await process_frame
	print("VISUAL_SMOKE_COMPLETE")
	quit()
