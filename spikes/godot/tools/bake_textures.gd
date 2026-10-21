## Bakes procedural planet albedo + normal maps (FastNoiseLite): 2048 px into assets/generated/
## (Android) and 1024 px into assets/generated/web/ (web export).
## Run: godot --headless --path spikes/godot -s res://tools/bake_textures.gd
## Writes .import files requesting VRAM compression (ETC2/ASTC on mobile, S3TC/BPTC on desktop/web).
extends SceneTree


func _init() -> void:
	for web in [false, true]:
		await _bake_set(web)
	quit()


func _bake_set(web: bool) -> void:
	var size := PlanetPalette.WEB_TEXTURE_SIZE if web else PlanetPalette.TEXTURE_SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlanetPalette.texture_dir(web)))
	for index in PlanetPalette.PLANETS.size():
		var planet: Dictionary = PlanetPalette.PLANETS[index]
		var noise := FastNoiseLite.new()
		noise.seed = 1000 + index
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 6
		noise.frequency = 0.0025 if index >= 4 else 0.004
		if index >= 4:
			# Gas giants: stretch along x for banding.
			noise.domain_warp_enabled = true
			noise.domain_warp_amplitude = 40.0
		var gradient := Gradient.new()
		var colors: Array = planet.colors
		gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		gradient.colors = PackedColorArray(colors)
		# Same features at both sizes: scale frequency with resolution.
		noise.frequency *= float(PlanetPalette.TEXTURE_SIZE) / size
		noise.domain_warp_amplitude *= float(size) / PlanetPalette.TEXTURE_SIZE
		await _bake(noise, gradient, false, PlanetPalette.albedo_path(index, web), size)
		await _bake(noise, null, true, PlanetPalette.normal_path(index, web), size)
		print("baked planet %d (%d px)" % [index, size])


func _bake(noise: FastNoiseLite, gradient: Gradient, normal: bool, path: String, size: int) -> void:
	var texture := NoiseTexture2D.new()
	texture.width = size
	texture.height = size
	texture.seamless = true
	texture.noise = noise
	if normal:
		texture.as_normal_map = true
		texture.bump_strength = 6.0
	else:
		texture.color_ramp = gradient
	await texture.changed
	var image := texture.get_image()
	if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	image.save_png(path)
	var import_file := FileAccess.open(path + ".import", FileAccess.WRITE)
	import_file.store_string(
		"[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
		+ "compress/mode=2\ncompress/high_quality=false\n"
		+ "compress/normal_map=%d\n" % (1 if normal else 2)
		+ "mipmaps/generate=true\ndetect_3d/compress_to=0\n")
