// The grass island light (art_lit.gdshader) on a textured model (Task 4g: the yarn ball and the
// parcel box glbs, one texture atlas each; the characters use art_toon_tex.gdshader since Task 4g2):
// the same "baked" two-colour ramp from the same sun, no engine lights or realtime shadows,
// so low (Compatibility) and high (Mobile) look the same. Colour = texture x tint x light.
// The model's normals are smooth (rounded models, not the faceted props), so the light is
// per vertex and the ramp is softer (ArtKit.lit_texture_material sets `softness`).
shader_type spatial;
render_mode unshaded, cull_back, specular_disabled;

// No source_color hint: the Compatibility renderer did not decode the atlas from sRGB with it (on
// SM-P200 the colours came out encoded twice, too light), so the shader decodes it itself.
uniform sampler2D albedo_texture : filter_linear_mipmap, repeat_disable;
// tint / accent are LINEAR colours ArtKit sets as vectors (no source_color hint: the Compatibility
// renderer did not convert a hinted colour, so a red tint came out pink on SM-P200 low, and Mobile
// converts a Color value even without the hint; a Vector4 reaches both as it is).
uniform vec4 tint = vec4(1.0);
// Where the texture's alpha is 0 the colour is multiplied by `accent` instead of `tint` (the parcel
// box's tape and label stripe, Task 4g); alpha 1 everywhere else and in the other models.
uniform vec4 accent = vec4(1.0);
uniform vec3 sun_dir = vec3(-0.35, 0.85, 0.45);
uniform vec4 lit_color : source_color = vec4(1.0);
uniform vec4 shade_color : source_color = vec4(0.49, 0.557, 0.847, 1.0);
uniform float threshold = 0.55;
uniform float softness = 0.03;
uniform float sky_fill = 0.1;
uniform float shade_mix = 1.0;     // 1 = the props' shade, < 1 = a lighter shade side (a soft character)

varying vec3 light;

void vertex() {
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float wrap = dot(n, normalize(sun_dir)) * 0.5 + 0.5;
	float t = smoothstep(threshold - softness, threshold + softness, wrap);
	vec3 shade = mix(lit_color.rgb, shade_color.rgb, shade_mix);
	light = mix(shade, lit_color.rgb, t) + sky_fill * max(n.y, 0.0);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 srgb = tex.rgb;
	vec3 linear = mix(pow((srgb + 0.055) / 1.055, vec3(2.4)), srgb / 12.92, lessThan(srgb, vec3(0.04045)));
	vec3 color = linear * mix(accent.rgb, tint.rgb, tex.a) * light;
	// Compatibility writes unshaded ALBEDO to its sRGB output unconverted (art_lit.gdshader).
	if (OUTPUT_IS_SRGB) {
		color = mix(1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, color * 12.92, lessThan(color, vec3(0.0031308)));
	}
	ALBEDO = color;
}
