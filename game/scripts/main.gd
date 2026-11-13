extends Node3D
## Entry point: input map, lighting/post-processing, world, level, player, HUD.
## The level comes from GameState (main menu) or --level=district|proto.
## Command line (after --): --bench runs the scripted benchmark, --tour takes
## screenshots from fixed viewpoints, --shots=<dir> sets the screenshot folder,
## --cinematic=<all|shot> plays the fly-throughs, --quit exits when a scripted
## run is over, --quality=<0..4>.
## Team deathmatch (menu or --tdm): --tdm_auto watches ten bots, --tdm_test
## takes HUD screenshots, --tdm_limit=<kills> shortens the round.

var world: VoxelWorld
var player: Player
var hud: Hud
var env: Environment
var sun: DirectionalLight3D
var quality := Quality.HIGH
var args := {}
var level  # TestLevel or DistrictLevel
var tdm: TdmMatch


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_setup_input()
	VoxMat.setup()
	var district := GameState.level == GameState.LEVEL_DISTRICT
	_setup_environment(district)

	world = VoxelWorld.new()
	world.name = "World"
	add_child(world)
	var t0 := Time.get_ticks_msec()
	level = DistrictLevel.new(world) if district else TestLevel.new(world)
	level.build()
	world.impacts_after_ms = Time.get_ticks_msec() + 3000
	world.sfx.ambient(district)
	print("[level] %s built in %d ms, %d objects; chunks %d, boxes %d, chunk total %d ms (physics part %d ms)" % [
		GameState.level, Time.get_ticks_msec() - t0, world.objects.size(), VoxelObject.prof.chunks, VoxelObject.prof.boxes,
		VoxelObject.prof.mesh_usec / 1000, VoxelObject.prof.phys_usec / 1000])

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = level.spawn
	player.spawn_point = level.spawn
	player.border = DistrictLevel.HALF - 0.6 if district else 39.4
	if district:
		player.look_at_dir(level.spawn_yaw, 0.0)
	world.player = player

	var hf := GPUParticlesCollisionHeightField3D.new()
	hf.size = Vector3(206, 40, 206) if district else Vector3(84, 30, 84)
	hf.position = Vector3(0, 12, 0)
	hf.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_2048 if district else GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	hf.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(hf)

	hud = Hud.new()
	hud.player = player
	hud.world = world
	add_child(hud)
	add_child(PauseMenu.new())
	if GameState.mode == GameState.MODE_TDM and district:
		_setup_tdm()

	quality = GameState.quality
	if args.has("quality"):
		quality = clampi(int(args.quality), 0, Quality.COUNT - 1)
	_apply_quality()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if args.has("no_occlusion"):
		get_viewport().use_occlusion_culling = false

	if GameState.cinematic != "":
		var c := Cinematic.new()
		c.main = self
		c.shot = GameState.cinematic
		c.quit_when_done = args.has("quit")
		c.shot_dir = args.get("shots", "")
		c.titles = args.has("titles")
		add_child(c)
	elif args.has("audit"):
		var au := CollisionAudit.new()
		au.main = self
		au.quit_when_done = args.has("quit")
		add_child(au)
	elif args.has("bench") or args.has("tour") or args.has("drive") or args.has("tools") or args.has("crater") or args.has("dtour") or args.has("glass"):
		var b := Bench.new()
		b.main = self
		b.mode = "tour" if args.has("tour") else ("drive" if args.has("drive") else ("tools" if args.has("tools") else ("crater" if args.has("crater") else ("dtour" if args.has("dtour") else ("glass" if args.has("glass") else "bench")))))
		b.shot_dir = args.get("shots", "user://shots")
		b.quit_when_done = args.has("quit")
		add_child(b)
	elif tdm == null:
		hud.message("Американский пригород — F1 справка, Esc пауза" if district else "Полигон разрушений — F1 справка, Esc пауза", 4.0)


func _setup_tdm() -> void:
	hud._show_stats = false
	tdm = TdmMatch.new()
	tdm.name = "TdmMatch"
	add_child(tdm)
	var auto := args.has("tdm_auto")
	tdm.setup(self, world, player, auto)
	if args.has("tdm_limit"):
		tdm.score_limit = maxi(int(args.tdm_limit), 1)
	var th := TdmHud.new()
	th.game = tdm
	th.player = player
	add_child(th)
	if auto:
		var cam := SpectatorCam.new()
		cam.game = tdm
		cam.hud = th
		add_child(cam)
	if args.has("tdm_test"):
		var t := TdmTest.new()
		t.game = tdm
		t.player = player
		t.shot_dir = args.get("shots", "user://shots")
		add_child(t)
	if args.has("quit_after"):
		get_tree().create_timer(float(args.quit_after)).timeout.connect(func():
			tdm.print_status()
			get_tree().quit())
	# Deploy once the level's bodies are in the physics space.
	for i in 3:
		await get_tree().physics_frame
	tdm.start()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("quality"):
		quality = (quality + 1) % Quality.COUNT
		GameState.quality = quality
		_apply_quality()
		hud.message("Качество: " + Quality.NAMES[quality])
	elif e.is_action_pressed("reset_level") and tdm == null:
		get_tree().reload_current_scene()
	elif e.is_action_pressed("bench") and not has_node("Bench") and GameState.level == GameState.LEVEL_PROTO:
		var b := Bench.new()
		b.name = "Bench"
		b.main = self
		b.shot_dir = "user://shots"
		add_child(b)


func _apply_quality() -> void:
	Quality.apply(quality, env, sun, get_viewport())
	hud.quality_name = Quality.NAMES[quality]


# ------------------------------------------------------------------ setup

func _setup_environment(district: bool) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.47, 0.55)
	sky_mat.sky_horizon_color = Color(0.86, 0.74, 0.58)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.22, 0.2, 0.17)
	sky_mat.ground_horizon_color = Color(0.78, 0.68, 0.55)
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.08
	sky_mat.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.8, 0.72, 0.62)
	env.fog_density = 0.0018
	env.fog_sun_scatter = 0.35
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.35
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0065
	env.volumetric_fog_albedo = Color(0.92, 0.85, 0.76)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_sky_affect = 0.2
	env.volumetric_fog_ambient_inject = 0.35
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.92
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-26, -138, 0)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 2.6
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 110.0
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)
	if district:
		# Golden hour over the district, like the reference shots.
		sun.rotation_degrees = Vector3(-19, -125, 0)
		sun.light_color = Color(1.0, 0.77, 0.52)
		sun.light_energy = 2.8
		env.fog_density = 0.0007
		env.volumetric_fog_density = 0.0026
		env.fog_aerial_perspective = 0.25
		env.volumetric_fog_length = 120.0


func _setup_input() -> void:
	if InputMap.has_action("move_forward"):
		return  # already set up by an earlier scene
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("crouch", KEY_CTRL)
	_key("crouch", KEY_C)
	_key("grab", KEY_E)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	for i in 7:
		_key("tool_%d" % (i + 1), KEY_1 + i)
	_key("toggle_help", KEY_F1)
	_key("toggle_stats", KEY_F3)
	_key("quality", KEY_F4)
	_key("reset_level", KEY_F5)
	_key("bench", KEY_F6)


func _key(action: String, code: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
