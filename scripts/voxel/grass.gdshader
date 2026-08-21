shader_type spatial;
render_mode cull_disabled;
// Grass tuft shader: per-instance COLOR tint + gentle wind sway.
// Vertex COLOR.a carries the sway weight (0 at the root, 1 at the tip);
// the MultiMesh instance color multiplies COLOR.rgb automatically.

uniform float u_sway_strength : hint_range(0.0, 0.5) = 0.09;
uniform float u_sway_speed : hint_range(0.0, 6.0) = 1.6;

varying vec3 v_tint;

void vertex() {
	float w = COLOR.a;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = world_pos.x * 0.35 + world_pos.z * 0.28;
	float sway = sin(TIME * u_sway_speed + phase) + 0.5 * sin(TIME * u_sway_speed * 1.7 + phase * 1.3);
	VERTEX.x += sway * u_sway_strength * w;
	VERTEX.z += sway * u_sway_strength * 0.6 * w;
	// Instance tint, slightly darker at the root.
	v_tint = COLOR.rgb * mix(0.55, 1.15, w);
}

void fragment() {
	ALBEDO = v_tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
