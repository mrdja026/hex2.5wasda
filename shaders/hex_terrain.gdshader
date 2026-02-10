shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.18, 0.45, 0.2, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.12, 0.32, 0.16, 1.0);
uniform float blend_scale = 0.6;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float wave = sin(world_pos.x * blend_scale) + sin(world_pos.z * blend_scale);
	float t = clamp(wave * 0.25 + 0.5, 0.0, 1.0);
	ALBEDO = mix(base_color.rgb, highlight_color.rgb, t);
}
