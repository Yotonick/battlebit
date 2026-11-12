class_name Quality
## Graphics presets (F4 cycles them).

enum { LOW, MEDIUM, HIGH, ULTRA }
const NAMES := ["Низкое", "Среднее", "Высокое", "Ультра"]


static func apply(level: int, env: Environment, sun: DirectionalLight3D, vp: Viewport) -> void:
	env.ssao_enabled = level >= MEDIUM
	env.ssil_enabled = level >= HIGH
	env.ssr_enabled = level >= ULTRA
	env.volumetric_fog_enabled = level >= MEDIUM
	env.glow_enabled = level >= LOW
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if level == LOW else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = [55.0, 80.0, 110.0, 140.0][level]
	sun.light_angular_distance = 0.0 if level <= MEDIUM else 0.6
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][level], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([1, 2, 3, 4][level] as RenderingServer.ShadowQuality)
	vp.use_taa = level >= MEDIUM
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if level == LOW else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = 1.0
	if env.ssao_enabled:
		RenderingServer.environment_set_ssao_quality([0, 1, 2, 3][level] as RenderingServer.EnvironmentSSAOQuality, true, 0.5, 2, 50.0, 300.0)
