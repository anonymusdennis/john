shader_type spatial;
// Voxel terrain shader for the John voxel platform (godot_voxel VoxelMesherTransvoxel).
//
// Space Engineers look: smooth isosurface + muted procedural PBR materials with
// triplanar-style value-noise detail. No image textures — every material channel
// is defined by albedo/roughness parameters plus procedural variation, so there
// is nothing Minecraft-like about the surfaces and no assets to redistribute.
//
// Interface contract with VoxelMesherTransvoxel (texturing_mode = Mixel4):
// - CUSTOM0: transvoxel LOD transition data (secondary positions + border masks).
// - CUSTOM1.x: 4 material indices, one byte each, packed into the float's bits.
// - CUSTOM1.y: 4 material weights, one byte each, packed into the float's bits.
// - u_transition_mask: assigned internally by the voxel engine per mesh block.
// Data layout documented in godot_voxel (storage/mixel4.h, transvoxel mesher) and
// the voxel-tools smooth terrain docs.

// --- Engine-assigned uniforms -------------------------------------------------
group_uniforms voxel;
// Layout: 00000000 00000000 00000000 00xxyyzz (low bits: -x,x,-y,y,-z,z transitions)
uniform int u_transition_mask;
group_uniforms;

// --- Material palette (filled from VoxelBlockRegistry at runtime) -------------
const int CHANNEL_COUNT = 16;
uniform vec4 u_albedo[16];
// x = roughness, y = detail noise scale, z = detail noise strength
uniform vec3 u_params[16];

// Molten core glow: emissive cracks fade in below this world height.
uniform float u_core_top_y = -430.0;
uniform float u_core_fade = 60.0;
uniform vec4 u_core_emission : source_color = vec4(1.0, 0.32, 0.06, 1.0);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_indices;
varying vec4 v_weights;

// --- Transvoxel LOD transition support ----------------------------------------
// Moves seam vertices to their secondary position when a lower-resolution
// neighbor is active, and collapses inactive transition-mesh triangles.
float transvoxel_secondary_factor(int idata) {
	int transition_mask = u_transition_mask & 0xff;
	int cell_border_mask = idata & 63;
	int vertex_border_mask = (idata >> 8) & 63;
	float t = float((transition_mask & cell_border_mask) != 0);
	t *= float((vertex_border_mask & ~transition_mask) == 0);
	return t;
}

vec3 transvoxel_position(vec3 vertex_pos, vec4 fdata) {
	int idata = floatBitsToInt(fdata.a);
	float secondary_factor = transvoxel_secondary_factor(idata);
	vec3 pos = mix(vertex_pos, fdata.xyz, secondary_factor);
	int itransition = (idata >> 16) & 0xff;
	pos *= float(itransition == 0 || (itransition & u_transition_mask) != 0);
	return pos;
}

// Unpack 4 bytes from a float's bit pattern (mesher packs u8 lanes).
vec4 decode_8bit_vec4(float v) {
	uint i = floatBitsToUint(v);
	return vec4(
		float(i & 0xffu),
		float((i >> 8u) & 0xffu),
		float((i >> 16u) & 0xffu),
		float((i >> 24u) & 0xffu));
}

// --- Procedural detail ---------------------------------------------------------
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z);
}

float fbm2(vec3 p) {
	return value_noise(p) * 0.667 + value_noise(p * 2.13) * 0.333;
}

void vertex() {
	VERTEX = transvoxel_position(VERTEX, CUSTOM0);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_indices = decode_8bit_vec4(CUSTOM1.x);
	v_weights = decode_8bit_vec4(CUSTOM1.y) / 255.0;
}

void fragment() {
	vec4 w = v_weights;
	w /= (w.x + w.y + w.z + w.w + 0.00001);

	// Blend the 4 candidate materials of this fragment.
	vec3 albedo = vec3(0.0);
	float roughness = 0.0;
	float detail_scale = 0.0;
	float detail_strength = 0.0;
	for (int i = 0; i < 4; i++) {
		int idx = clamp(int(v_indices[i] + 0.5), 0, CHANNEL_COUNT - 1);
		float wi = w[i];
		albedo += u_albedo[idx].rgb * wi;
		roughness += u_params[idx].x * wi;
		detail_scale += u_params[idx].y * wi;
		detail_strength += u_params[idx].z * wi;
	}

	// Two-scale procedural variation: fine grain + large low-frequency patches
	// that break tiling at Space Engineers scales.
	float fine = fbm2(v_world_pos * detail_scale);
	float macro = value_noise(v_world_pos * 0.02);
	float shade = 1.0 + (fine - 0.5) * 2.0 * detail_strength + (macro - 0.5) * 0.18;
	albedo *= shade;

	// Subtle cavity/ledge accent: horizontal surfaces get a hint of dust,
	// steep faces read slightly darker and rockier.
	float up = clamp(v_world_normal.y, 0.0, 1.0);
	albedo *= mix(0.86, 1.06, up);
	roughness = clamp(roughness + (fine - 0.5) * 0.18, 0.05, 1.0);

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = 0.0;

	// The Core — molten depths glow through crack veins.
	float core_t = clamp((u_core_top_y - v_world_pos.y) / u_core_fade, 0.0, 1.0);
	if (core_t > 0.0) {
		float vein = fbm2(v_world_pos * 0.35);
		vein = smoothstep(0.52, 0.72, vein);
		EMISSION = u_core_emission.rgb * vein * core_t * 3.2;
		ALBEDO = mix(ALBEDO, vec3(0.12, 0.08, 0.07), core_t * 0.7);
	}
}
