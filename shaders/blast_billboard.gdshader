shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float age = 0.0;
uniform float seed = 0.0;
uniform int layer = 0; // fire, smoke, pressure ring

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
	// Camera-facing sprite preserving the node's animated world scale.
	vec3 center = (VIEW_MATRIX * MODEL_MATRIX * vec4(0,0,0,1)).xyz;
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	POSITION = PROJECTION_MATRIX * vec4(center + VERTEX * scale, 1.0);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 flow = p * 3.5 + vec2(seed, -age*2.5);
	float n = noise(flow)*0.55 + noise(flow*2.1)*0.3 + noise(flow*4.3)*0.15;
	float radius = length(p);
	float body = 1.0-smoothstep(0.42, 0.98, radius + (n-0.5)*0.42);
	if (layer == 0) {
		float heat = clamp(1.0-radius*0.65-age*0.7+(n-0.5)*0.8,0.0,1.0);
		vec3 fire = mix(vec3(0.48,0.018,0.002), vec3(1.0,0.24,0.012), smoothstep(0.05,0.48,heat));
		fire = mix(fire, vec3(1.0,0.82,0.24), smoothstep(0.45,0.82,heat));
		fire = mix(fire, vec3(1.0,0.98,0.78), smoothstep(0.8,1.0,heat));
		ALBEDO = fire;
		EMISSION = fire * (1.7 + 2.0 * (1.0-age));
		ALPHA = body * (1.0-smoothstep(0.3,1.0,age));
	} else if (layer == 1) {
		ALBEDO = mix(vec3(0.07,0.065,0.06), vec3(0.22,0.20,0.18), n);
		ALPHA = body * smoothstep(0.0,0.18,age) * (1.0-age) * 0.42;
	} else {
		float ring = smoothstep(0.70,0.81,radius)*(1.0-smoothstep(0.82,0.96,radius));
		ALBEDO = vec3(1.0,0.63,0.22);
		EMISSION = ALBEDO * 2.0;
		ALPHA = ring * pow(1.0-age,2.0) * 0.4;
	}
}
