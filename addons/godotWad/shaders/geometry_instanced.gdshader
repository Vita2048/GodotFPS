shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear, repeat_enable;
instance uniform vec3 sectorLight : source_color = vec3(1, 1, 1);
instance uniform float alpha = 1.0;
instance uniform vec2 scrolling = vec2(0, 0);
instance uniform vec4 emission : source_color;
uniform sampler2D texture_emission : hint_default_black;
instance uniform float emission_energy : hint_range(0, 16) = 1.0;

void vertex() {
	if (scrolling.x != 0.0)
		UV.x += -scrolling.x * TIME * 0.15;
	if (scrolling.y != 0.0)
		UV.y += scrolling.y * TIME * 0.15;
}

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	vec3 col = tex.rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, 1.22);
	col = (col - 0.5) * 1.12 + 0.52;
	ALBEDO = clamp(col * sectorLight * 1.18 * emission_energy, vec3(0.0), vec3(1.4));
	ALPHA = tex.a * alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.15;
}
