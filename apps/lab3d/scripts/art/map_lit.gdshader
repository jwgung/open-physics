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
// Extra night on one material only (the sky backdrop: StoryDirector darkens it to a night sky).
uniform vec3 own_tint = vec3(1.0);

// The night map's spots (2026-10-28 explore in a fixed order): the map's spot vertices carry their
// spot's tag in UV.x (1..11, MapIsland._add_spot; 0 = not a spot, and meshes without UVs read 0).
// A found spot is lit at night (its bit in lit_mask): its colours take at least lit_tint, a warm
// light, instead of the night (by day story_tint is 1 and nothing changes). The tapped locked spot
// (shake_spot) moves by shake_offset (IslandHomeScreen's little shake). Vertex work only.
uniform int lit_mask = 0;
uniform vec3 lit_tint = vec3(1.0, 0.88, 0.62);
uniform int shake_spot = 0;
uniform vec3 shake_offset = vec3(0.0);

// The story's night (StoryDirector, 2026-10-28): a global multiplier, (1, 1, 1) by day.
global uniform vec3 story_tint;
varying vec3 shaded;

void vertex() {
	int tag = int(UV.x + 0.5);
	vec3 night = story_tint;
	if (tag > 0) {
		if (((lit_mask >> (tag - 1)) & 1) == 1) {
			night = max(story_tint, lit_tint);
		}
		if (tag == shake_spot) {
			VERTEX += shake_offset;
		}
	}
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float wrap = dot(n, normalize(sun_dir)) * 0.5 + 0.5;
	float t = smoothstep(threshold - softness, threshold + softness, wrap);
	vec3 light = mix(shade_color.rgb, lit_color.rgb, t) + sky_fill * max(n.y, 0.0);
	vec3 color = COLOR.rgb * light * night * own_tint;
	if (encode_srgb) {
		color = mix(1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, color * 12.92, lessThan(color, vec3(0.0031308)));
	}
	shaded = color;
}

void fragment() {
	ALBEDO = shaded;
}
