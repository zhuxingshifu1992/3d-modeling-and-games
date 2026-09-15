extends SceneTree
## Regression coverage for imported model joints, two-hand contact and an
## unobstructed centre sightline through the actual first-person triangles.
var game: Node3D
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures.append(label); push_error(label)
func frames(count: int) -> void:
	for i in range(count): await process_frame

func run() -> void:
	game=load("res://main.tscn").instantiate(); root.add_child(game); game.qa=true; game.qa_mode="model_contract"; game._begin("power")
	for actor in game.enemies: actor.set_physics_process(false)
	game.player.set_physics_process(false)
	for role in ["rifle","flanker","heavy"]:
		var actor: Node3D=load("res://scripts/enemy.gd").new(); game.gameplay.add_child(actor); actor.setup(game,role,Vector3(0,.1,16),71); actor.set_physics_process(false)
		check(actor._detailed and actor._forearms.size()==2,role+" imports articulated model")
		for alert in [false,true]:
			actor._animate(1.0,alert)
			for i in range(2):
				var grip: Vector3=Vector3(.037,-.103,.043) if i==1 else Vector3(-.032,-.053,-.42)
				var target: Vector3=actor._gun.to_global(grip*.8)
				var palm: Vector3=actor._forearms[i].to_global(Vector3(0,-.276,0))
				check(palm.distance_to(target)<.035,role+" hand "+str(i)+" contact in pose "+str(alert)+" error="+str(palm.distance_to(target)))
		actor.queue_free()
	for weapon in range(2):
		game.player.set_weapon(weapon); game.player.aiming=true; await frames(60)
		var obstruction: String=centre_obstruction(game.player.gun_models[weapon],game.player.camera)
		check(obstruction.is_empty(),"ADS centre is clear for weapon "+str(weapon)+": "+obstruction)
	check(is_instance_valid(game.player.detailed_magazine),"Carbine magazine is independently animated")
	game.running=false; game.audio_bank.shutdown(); game.queue_free(); await frames(3)
	if DisplayServer.get_name()=="headless": OS.delay_msec(150)
	print("DETAIL_MODEL_PROBE ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()})); quit(0 if failures.is_empty() else 1)

func centre_obstruction(gun: Node3D, camera: Camera3D) -> String:
	for child in gun.find_children("*","MeshInstance3D",true,false):
		if not child.is_visible_in_tree(): continue
		var mesh: Mesh=child.mesh
		var transform: Transform3D=camera.global_transform.affine_inverse()*child.global_transform
		for surface in range(mesh.get_surface_count()):
			var arrays: Array=mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			for k in range(0,indices.size(),3):
				var hit=Geometry3D.segment_intersects_triangle(Vector3.ZERO,Vector3(0,0,-4),transform*vertices[indices[k]],transform*vertices[indices[k+1]],transform*vertices[indices[k+2]])
				if hit!=null: return String(child.name)+" "+str(hit)
	return ""
