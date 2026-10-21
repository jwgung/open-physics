// Toy look for the Task 2c style mockups: "baked" two-tone lighting computed in the shader, no
// engine lights or shadows (identical on Compatibility/low and Mobile/high). Colour comes from the
// vertex colours (ToyMeshBuilder, incl. vertex AO) times `tint`.
shader_type spatial;
render_mode unshaded, cull_back, specular_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 sun_dir = vec3(-0.35, 0.85, 0.45);   // world direction towards the light
uniform vec4 lit_color : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform vec4 shade_color : source_color = vec4(0.62, 0.66, 0.82, 1.0);
uniform float threshold = 0.55;    // where lit turns into shade (wrapped N.L, 0..1)
uniform float softness = 0.12;     // 0 = hard toon band, larger = smoother ramp
uniform float sky_fill = 0.12;     // upward faces get a little extra light
uniform float rim_strength = 0.18; // light edge towards the camera silhouette
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 world_normal;
varying vec3 world_pos;

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float wrap = dot(n, normalize(sun_dir)) * 0.5 + 0.5;
	float t = smoothstep(threshold - softness, threshold + softness, wrap);
	vec3 base = COLOR.rgb * tint.rgb;
	vec3 light = mix(shade_color.rgb, lit_color.rgb, t) + sky_fill * max(n.y, 0.0);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float rim = pow(1.0 - clamp(dot(n, view_dir), 0.0, 1.0), 3.0) * rim_strength;
	vec3 color = base * light + rim * rim_color.rgb;
	// The Compatibility renderer writes unshaded ALBEDO to its sRGB output unconverted (measured on
	// SM-P200: colours came out as their linear values); Mobile converts linear -> sRGB itself.
	if (OUTPUT_IS_SRGB) {
		color = mix(1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, color * 12.92, lessThan(color, vec3(0.0031308)));
	}
	ALBEDO = color;
}
