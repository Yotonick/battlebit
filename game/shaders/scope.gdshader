shader_type canvas_item;
// Sniper scope: black mask with a soft lens edge and a mil-dot reticle.

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = FRAGCOORD.xy;
	vec2 c = res * 0.5;
	float r = res.y * 0.46;
	float d = length(px - c);
	float a = smoothstep(r - 2.0, r + 1.5, d);
	a = max(a, smoothstep(r * 0.72, r, d) * 0.45);
	vec2 o = abs(px - c);
	float thin = (step(o.y, 0.8) * step(r * 0.06, o.x) + step(o.x, 0.8) * step(r * 0.06, o.y));
	float thick = (step(o.y, 2.6) * step(r * 0.5, o.x) + step(o.x, 2.6) * step(r * 0.5, o.y));
	float dots = 0.0;
	for (int i = 1; i < 5; i++) {
		float k = r * 0.1 * float(i);
		dots += step(length(vec2(o.x - k, o.y)), 2.2) + step(length(vec2(o.x, o.y - k)), 2.2);
	}
	a = max(a, clamp(thin + thick + dots, 0.0, 1.0) * 0.92);
	vec3 col = vec3(0.0);
	if (d < 1.8) {
		col = vec3(1.0, 0.1, 0.05);
		a = 1.0;
	}
	COLOR = vec4(col, a);
}
