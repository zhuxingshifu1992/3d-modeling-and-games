extends RefCounted

const REAL_SKY: String = "res://assets/environment/kloofendal_48d_partly_cloudy_puresky_2k.hdr"

static func build(parent: Node3D, low_quality: bool) -> Dictionary:
	var advanced: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("1765ba")
	sky_material.sky_horizon_color = Color("b3dbe5")
	sky_material.sky_curve = 0.16
	sky_material.ground_bottom_color = Color("557c8c")
	sky_material.ground_horizon_color = Color("b3dbe5")
	sky_material.sun_angle_max = 8.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	if ResourceLoader.exists(REAL_SKY):
		var panorama: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
		panorama.panorama = load(REAL_SKY)
		panorama.energy_multiplier = 0.75
		sky.sky_material = panorama
		if not advanced:
			var display_sky: ShaderMaterial = ShaderMaterial.new()
			display_sky.shader = load("res://assets/environment/compatibility_sky.gdshader")
			display_sky.set_shader_parameter("panorama", load(REAL_SKY))
			sky.sky_material = display_sky
		sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	environment.sky_rotation = Vector3(0,deg_to_rad(125.0),0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color("b6d6ee")
	environment.ambient_light_sky_contribution = 0.82
	environment.ambient_light_energy = 0.6 if advanced else 0.45
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.9
	environment.ssao_enabled = advanced and not low_quality
	environment.ssao_radius = 0.65
	environment.ssao_intensity = 1.6
	environment.ssao_power = 1.4
	environment.ssao_detail = 0.6
	environment.ssil_enabled = advanced and not low_quality
	environment.ssil_radius = 2.0
	environment.ssil_intensity = 0.4
	environment.ssil_sharpness = 0.8
	environment.fog_enabled = true
	environment.fog_light_color = Color("b8c8cf")
	environment.fog_light_energy = 0.65
	environment.fog_density = 0.00012
	environment.fog_sky_affect = 0.0
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = environment
	parent.add_child(world_env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43.0,-35.0,0.0)
	sun.light_color = Color("fff6e8")
	sun.light_energy = 1.8 if advanced else 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0 if low_quality else 180.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.5
	parent.add_child(sun)
	if low_quality:
		parent.get_viewport().scaling_3d_scale = 0.75
		parent.get_viewport().msaa_3d = Viewport.MSAA_2X
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 55.0
		RenderingServer.directional_shadow_atlas_set_size(1024, true)
	else:
		parent.get_viewport().scaling_3d_scale = 0.85
		RenderingServer.directional_shadow_atlas_set_size(2048, true)

	return {"environment":environment,"sun":sun}
