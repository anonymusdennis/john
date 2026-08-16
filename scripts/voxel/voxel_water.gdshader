shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
// Simple stylized water surface for ocean/river planes.
// Static volume — no simulation. Gentle normal wobble + depth-tinted fresnel.

uniform vec4 u_shallow_color : source_color = vec4(0.16, 0.42, 0.5, 0.72);
uniform vec4 u_deep_color : source_color = vec4(0.04, 0.14, 0.24, 0.92);
uniform float u_wave_scale = 0.08;
uniform float u_wave_speed = 0.35;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz * u_wave_scale;
	float t = TIME * u_wave_speed;
	float n1 = vnoise(p + vec2(t, t * 0.7));
	float n2 = vnoise(p * 1.7 - vec2(t * 0.6, t));
	vec3 n = normalize(vec3((n1 - 0.5) * 0.35, 1.0, (n2 - 0.5) * 0.35));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec4 col = mix(u_shallow_color, u_deep_color, fresnel);
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
}
