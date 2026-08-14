shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 sectorLight : source_color = vec3(1, 1, 1);
uniform float alpha = 1.0;
uniform vec2 scrolling = vec2(0, 0);
uniform vec4 emission : source_color;
uniform sampler2D texture_emission : hint_default_black;
uniform float emission_energy : hint_range(0, 16) = 1.0;

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
	col = mix(vec3(lum), col, 1.28);
	col = (col - 0.5) * 1.18 + 0.52;
	col = clamp(col * 1.14, 0.0, 1.0);
	ALBEDO = col;
	ROUGHNESS = clamp(0.68 - lum * 0.18, 0.38, 0.82);
	METALLIC = 0.05;
	SPECULAR = 0.4;
	float lR = dot(texture(texture_albedo, UV + vec2(0.0035, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
	float lU = dot(texture(texture_albedo, UV + vec2(0.0, 0.0035)).rgb, vec3(0.299, 0.587, 0.114));
	NORMAL_MAP = normalize(vec3((lum - lR) * 5.0, (lum - lU) * 5.0, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.7;
	EMISSION = col * sectorLight * (0.28 * emission_energy);
	ALPHA = tex.a * alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.15;
}
