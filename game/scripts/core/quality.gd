class_name Quality
## Graphics presets (F4 cycles them, the menu picks one, the choice is saved).
## MINIMUM is for integrated GPUs: half render resolution upscaled with FSR,
## short view distance hidden by depth fog, no sun shadows. MINIMUM and LOW use
## a flat ambient colour instead of sky light, so shaded sides never go black.

enum { MINIMUM, LOW, MEDIUM, HIGH, ULTRA }
const NAMES := ["Минимум", "Низкое", "Среднее", "Высокое", "Ультра"]
const COUNT := 5

## Camera far plane per preset (the district is 205 m across).
const VIEW_DISTANCE := [130.0, 220.0, 600.0, 600.0, 600.0]
## Share of the screen resolution the 3D scene is rendered at.
const RENDER_SCALE := [0.5, 0.67, 1.0, 1.0, 1.0]


## Default preset for this machine: integrated / software GPUs start at MINIMUM.
static func detect_default() -> int:
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_CPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return MINIMUM
	return HIGH


static func view_distance(level: int) -> float:
	return VIEW_DISTANCE[clampi(level, 0, COUNT - 1)]


static func apply(level: int, env: Environment, sun: DirectionalLight3D, vp: Viewport) -> void:
	level = clampi(level, 0, COUNT - 1)
	env.ssao_enabled = level >= MEDIUM
	env.ssil_enabled = level >= HIGH
	env.ssr_enabled = level >= ULTRA
	env.volumetric_fog_enabled = level >= MEDIUM
	env.glow_enabled = level >= LOW
	# Short view distance: depth fog fades the world into the horizon colour
	# before the far plane cuts it off.
	if level <= LOW:
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = view_distance(level) * 0.35
		env.fog_depth_end = view_distance(level) * 0.97
		env.fog_depth_curve = 1.6
		env.fog_density = 1.0
	else:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = 0.0018
	# Sky light depends on the radiance map; a flat warm colour is cheaper and
	# keeps shadowed walls readable on weak GPUs.
	if level <= LOW:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.78, 0.74, 0.68)
		env.ambient_light_energy = 0.75 if level == MINIMUM else 0.6
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.85
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Shadows render the scene a second time: off on MINIMUM.
	sun.shadow_enabled = level >= LOW
	if level <= LOW:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = [35.0, 40.0, 80.0, 110.0, 140.0][level]
	sun.light_angular_distance = 0.0 if level <= MEDIUM else 0.6
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096, 4096, 8192][level], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([0, 1, 2, 3, 4][level] as RenderingServer.ShadowQuality)
	vp.use_taa = level >= MEDIUM
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if level <= LOW else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = RENDER_SCALE[level]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if RENDER_SCALE[level] < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	var cam := vp.get_camera_3d()
	if cam:
		cam.far = view_distance(level)
	if env.ssao_enabled:
		RenderingServer.environment_set_ssao_quality([0, 0, 1, 2, 3][level] as RenderingServer.EnvironmentSSAOQuality, true, 0.5, 2, 50.0, 300.0)
