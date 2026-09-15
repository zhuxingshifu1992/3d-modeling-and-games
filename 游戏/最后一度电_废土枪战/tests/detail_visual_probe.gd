extends SceneTree
## Actual imported assets, actual enemy posing, actual OpenGL screenshots.
class DisplayGame extends Node3D:
	var difficulty: String = "standard"
	var player: Node3D
	var world: Node3D
	func can_fight() -> bool: return false

var stage: DisplayGame
var camera: Camera3D
var caption: Label
var actors: Array[Node3D] = []
var weapons: Array[Node3D] = []

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.msaa_3d=Viewport.MSAA_4X
	stage=DisplayGame.new(); root.add_child(stage)
	var env:=WorldEnvironment.new(); var e:=Environment.new(); e.background_mode=Environment.BG_COLOR; e.background_color=Color(.045,.057,.057); e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color=Color(.73,.80,.83); e.ambient_light_energy=.55; e.tonemap_mode=Environment.TONE_MAPPER_FILMIC; env.environment=e; stage.add_child(env)
	var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-38,-28,0); key.light_color=Color(1,.94,.84); key.light_energy=1.05; key.shadow_enabled=true; key.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL; stage.add_child(key)
	var rim:=OmniLight3D.new(); rim.position=Vector3(-1,2.1,-1); rim.light_color=Color(.47,.68,.73); rim.light_energy=1.5; rim.omni_range=5; stage.add_child(rim)
	var fill:=OmniLight3D.new(); fill.position=Vector3(1,1.6,2.5); fill.light_color=Color(.85,.87,1); fill.light_energy=.85; fill.omni_range=5; stage.add_child(fill)
	var floor_mesh:=MeshInstance3D.new(); var plane:=PlaneMesh.new(); plane.size=Vector2(200,200); floor_mesh.mesh=plane; var floor_mat:=StandardMaterial3D.new(); floor_mat.albedo_color=Color(.075,.085,.082); floor_mat.roughness=.85; floor_mesh.material_override=floor_mat; stage.add_child(floor_mesh)
	camera=Camera3D.new(); stage.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=2.65; camera.position=Vector3(2.4,1.9,5.5); camera.look_at(Vector3(0,.94,0)); camera.current=true
	var layer:=CanvasLayer.new(); root.add_child(layer); caption=Label.new(); caption.position=Vector2(40,24); caption.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf")); caption.add_theme_font_size_override("font_size",24); caption.add_theme_color_override("font_color",Color(.80,.82,.76)); layer.add_child(caption)
	for i in range(3):
		var actor: Node3D=load("res://scripts/enemy.gd").new(); stage.add_child(actor); actor.setup(stage,["flanker","rifle","heavy"][i],Vector3((i-1)*1.06,.025,0),16+i); actor.rotation.y=PI; actor.set_physics_process(false); actor._animate(1.0,true); actors.append(actor)
	await capture("characters.png","人物精修 / 侧袭者 · 射手 · 重装守卫")
	actors[0].visible=false; actors[2].visible=false
	camera.size=1.38; camera.position=Vector3(.66,1.75,1.65); camera.look_at(Vector3(0,1.27,0))
	await capture("character_close.png","人物近景 / 服装、护具与持枪姿态")
	for actor in actors: actor.visible=false
	for i in range(2):
		var gun: Node3D=load("res://assets/models/detail/"+(["r7_view","shotgun_view"][i])+".glb").instantiate(); stage.add_child(gun); gun.position=Vector3(0,.85-i*.38,0); weapons.append(gun)
		for child in gun.find_children("*","Node3D",true,false):
			if String(child.name).begins_with("LeftHand") or String(child.name).begins_with("RightHand") or String(child.name).begins_with("LeftSleeve") or String(child.name).begins_with("RightSleeve"): child.visible=false
	camera.size=1.06; camera.position=Vector3(1.8,1.13,.50); camera.look_at(Vector3(0,.66,-.31))
	await capture("weapons.png","枪械精修 / R7 卡宾枪 · 破门者霰弹枪")
	print("DETAIL_VISUAL_PROBE_OK"); quit(0)

func capture(filename: String, title: String) -> void:
	caption.text=title
	for i in range(8): await process_frame
	if DisplayServer.get_name()=="headless": return
	RenderingServer.force_draw(false)
	var img: Image=root.get_texture().get_image()
	var output: String=ProjectSettings.globalize_path("res://previews/detail")
	DirAccess.make_dir_recursive_absolute(output)
	var result: Error=img.save_png(output.path_join(filename))
	print("DETAIL_CAPTURE ",filename," ",result)
