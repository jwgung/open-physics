// Storybook outline of a character (Task 4g2, art-direction.md section 11 "동화책 스타일"): the
// next pass of the toon material (art_toon_tex.gdshader). An inverted hull: the same mesh grown
// along its normals and drawn with front faces culled, so only its back faces show, as a brown rim
// round the silhouette and in front of farther parts. Needs the character mesh contract (closed
// shells, outward faces, one smooth normal per position) or the hull tears at seams.
//
// Width = max(world_width, screen_width x the view height at the vertex's depth): the Blender
// reference's 0.010 m when the character is big on screen (close or followed), and never thinner
// than screen_width of the view height when it is small (the default front camera shows the cat
// about 130 px tall of 1200, where 0.010 m is under one pixel and the line breaks up).
// screen_width is a fraction of the height, so it does not depend on the render resolution; 0.0035
// is about 1.9 px in the low tier's 540 px 3D buffer (no MSAA), the thinnest that did not break up
// on SM-P200 (ArtKit.OUTLINE_SCREEN sets it).
// Rendering only: nothing here touches the physics.
shader_type spatial;
render_mode unshaded, cull_front, specular_disabled, skip_vertex_transform;

// Defaults only: ArtKit.outline_material sets all three (ArtPalette.OUTLINE, OUTLINE_WORLD, OUTLINE_SCREEN).
uniform vec4 color = vec4(0.156, 0.061, 0.030, 1.0);   // LINEAR (#6e4630), a vector: see art_toon_tex
uniform float world_width = 0.010;                     // m
uniform float screen_width = 0.0035;                   // of the view height

void vertex() {
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	// View units across the full screen height at this depth: 2 w / |P[1][1]| (perspective: w = the
	// depth, P[1][1] = 1 / tan(fov / 2); orthographic: w = 1, P[1][1] = 2 / size). abs: Compatibility
	// flips y when it renders into a SubViewport (the 3D view), so its P[1][1] is negative there
	// (without abs the screen width came out negative and only world_width was left, on SM-P200 low).
	float w = (PROJECTION_MATRIX * vec4(view_pos, 1.0)).w;
	float view_height = 2.0 * w / abs(PROJECTION_MATRIX[1][1]);
	VERTEX = view_pos + n * max(world_width, screen_width * view_height);
	NORMAL = n;
}

void fragment() {
	vec3 c = color.rgb;
	if (OUTPUT_IS_SRGB) {
		c = mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
	}
	ALBEDO = c;
}
