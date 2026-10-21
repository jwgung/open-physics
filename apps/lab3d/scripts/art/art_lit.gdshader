// Grass island look (Task 2c, apps/lab3d/docs/art-direction.md): "baked" two-colour lighting computed
// in the shader, no engine lights or realtime shadows, so Compatibility/low and Mobile/high look
// the same. Colour = vertex colour (ArtMeshBuilder, incl. vertex AO) x tint x light ramp.
// Defaults are the style's values (ArtPalette.LIGHT / SHADE); ArtKit sets them explicitly too.
shader_type spatial;
render_mode unshaded, cull_back, specular_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 sun_dir = vec3(-0.35, 0.85, 0.45);   // world direction towards the light
uniform vec4 lit_color : source_color = vec4(1.0);
uniform vec4 shade_color : source_color = vec4(0.49, 0.557, 0.847, 1.0);
uniform float threshold = 0.55;    // where lit turns into shade (wrapped N.L, 0..1)
uniform float softness = 0.03;     // 0 = hard toon band, larger = smoother ramp
uniform float sky_fill = 0.1;      // upward faces get a little extra light

// Everything is computed per vertex: the meshes are faceted (one normal per triangle), so the
// ramp is constant over a face and the fragment stage only copies the colour (cheap on low).
varying vec3 shaded;

void vertex() {
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float wrap = dot(n, normalize(sun_dir)) * 0.5 + 0.5;
	float t = smoothstep(threshold - softness, threshold + softness, wrap);
	vec3 light = mix(shade_color.rgb, lit_color.rgb, t) + sky_fill * max(n.y, 0.0);
	shaded = COLOR.rgb * tint.rgb * light;
}

void fragment() {
	vec3 color = shaded;
	// The Compatibility renderer writes unshaded ALBEDO to its sRGB output unconverted (measured on
	// SM-P200: colours came out as their linear values); Mobile converts linear -> sRGB itself.
	if (OUTPUT_IS_SRGB) {
		color = mix(1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, color * 12.92, lessThan(color, vec3(0.0031308)));
	}
	ALBEDO = color;
}
