shader_type canvas_item;
// Team deathmatch screen effect: suppression (blur, desaturation, dark edges),
// low health (red pulsing edges), damage flash and the death tint.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float suppression = 0.0;
uniform float low_health = 0.0;
uniform float hurt = 0.0;
uniform float dead = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = (uv - 0.5) * vec2(1.6, 1.0);
	float r = length(d);
	float vig = smoothstep(0.32, 1.0, r);
	vec3 c = textureLod(screen_tex, uv, suppression * vig * 2.5).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g), clamp(suppression * 0.5 + low_health * 0.55 + dead * 0.8, 0.0, 1.0));
	c *= 1.0 - vig * (0.15 + suppression * 0.6 + dead * 0.35);
	float pulse = 0.6 + 0.4 * sin(TIME * 5.0);
	c = mix(c, vec3(0.5, 0.02, 0.0), clamp(vig * (low_health * 0.55 * pulse + hurt * 0.5), 0.0, 0.85));
	COLOR = vec4(c, 1.0);
}
