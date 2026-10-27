// The island map's light (MapIsland, home screen): art_lit.gdshader's baked two-colour ramp, with
// the Compatibility renderer's sRGB encode done per vertex instead of per fragment. The map's
// meshes are faceted (one colour per face), so the pixels are the same, and the fragment stage only
// copies a colour: the map covers the whole screen, and on SM-P200 the per-pixel pow() of
// art_lit was a large share of the home's frame (2026-10-27). `encode_srgb` is set from the
// renderer (MapIsland.material), as OUTPUT_IS_SRGB is a fragment built-in.
shader_type spatial;
render_mode unshaded, cull_back, specular_disabled;

uniform vec3 sun_dir = vec3(-0.35, 0.85, 0.45);
uniform vec4 lit_color : source_color = vec4(1.0);
uniform vec4 shade_color : source_color = vec4(0.49, 0.557, 0.847, 1.0);
uniform float threshold = 0.55;
uniform float softness = 0.03;
uniform float sky_fill = 0.1;
uniform bool encode_srgb = false;

varying vec3 shaded;

void vertex() {
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float wrap = dot(n, normalize(sun_dir)) * 0.5 + 0.5;
	float t = smoothstep(threshold - softness, threshold + softness, wrap);
	vec3 light = mix(shade_color.rgb, lit_color.rgb, t) + sky_fill * max(n.y, 0.0);
	vec3 color = COLOR.rgb * light;
	if (encode_srgb) {
		color = mix(1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, color * 12.92, lessThan(color, vec3(0.0031308)));
	}
	shaded = color;
}

void fragment() {
	ALBEDO = shaded;
}
