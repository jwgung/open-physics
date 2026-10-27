// Storybook cel shading of a character (Task 4g2, art-direction.md section 11 "동화책 스타일"):
// a textured model with smooth normals (the bread cat; Dugi later) lit in two flat steps by the
// island's baked sun, like the Blender reference renders (one-step colour ramp: lit = the texture
// colour, shade = the warm SHADE multiplier). Unshaded: no engine lights or realtime shadows, so
// low (Compatibility) and high (Mobile) look the same. The brown outline is the next pass
// (art_outline.gdshader). Rendering only: nothing here touches the physics.
shader_type spatial;
render_mode unshaded, cull_back, specular_disabled;

// The atlas is decoded from sRGB here and the colours below are LINEAR vectors (no source_color
// hint), for the same Compatibility reasons as art_lit_tex.gdshader. The defaults below are only
// defaults: ArtKit.toon_material sets them (SUN_DIR, TOON_SHADE, TOON_THRESHOLD).
uniform sampler2D albedo_texture : filter_linear_mipmap, repeat_disable;
uniform vec3 sun_dir = vec3(-0.35, 0.85, 0.45);
// The shade step's multiplier (linear): Blender ramp colour (0.86 x (0.97, 0.90, 0.93)), warm and
// slightly pink, so fur and kraft stay warm on the shade side.
uniform vec4 shade = vec4(0.834, 0.774, 0.8, 1.0);
// N.L where the step sits (Blender: sun 3 W/m2 + world 0.35, ramp edge 0.32 -> N.L ~ -0.03).
uniform float threshold = -0.03;
// The approved trio render's faint warm rim on the lit side (Blender: Layer Weight "Facing", blend
// 0.35, ramp 0.62..0.70, screen-mixed at `rim` with a warm white), so round faces read in 3D.
uniform float rim = 0.12;
uniform vec4 rim_color = vec4(1.0, 0.95, 0.82, 1.0);

varying vec3 world_normal;

void vertex() {
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	// Per pixel (not per vertex like art_lit_tex): a hard step interpolated between vertices would
	// wobble along the edges of the triangles. fwidth keeps the edge one pixel wide (anti-aliased).
	float ndl = dot(normalize(world_normal), normalize(sun_dir)) - threshold;
	float edge = max(fwidth(ndl), 1e-4);
	float lit = smoothstep(-edge, edge, ndl);
	vec3 light = mix(shade.rgb, vec3(1.0), lit);
	vec3 srgb = texture(albedo_texture, UV).rgb;
	vec3 linear = mix(pow((srgb + 0.055) / 1.055, vec3(2.4)), srgb / 12.92, lessThan(srgb, vec3(0.04045)));
	vec3 color = linear * light;
	// Layer Weight facing = (1 - |N.V|)^(2 x blend) for blend < 0.5; NORMAL and VIEW are view space.
	float facing = pow(clamp(1.0 - abs(dot(normalize(NORMAL), VIEW)), 0.0, 1.0), 0.7);
	float r = smoothstep(0.62, 0.70, facing) * lit * rim;
	color = vec3(1.0) - (vec3(1.0) - color) * (vec3(1.0) - r * rim_color.rgb);
	// Compatibility writes unshaded ALBEDO to its sRGB output unconverted (art_lit.gdshader).
	if (OUTPUT_IS_SRGB) {
		color = mix(1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, color * 12.92, lessThan(color, vec3(0.0031308)));
	}
	ALBEDO = color;
}
