extends RefCounted
class_name ProceduralTextures
## High-quality procedural PBR-ish textures used as fallbacks / accents.

static func make_noise_image(size: int, scale: float, seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = scale
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	for y in size:
		for x in size:
			var v := (n.get_noise_2d(x, y) + 1.0) * 0.5
			img.set_pixel(x, y, Color(v, v, v))
	return img


static func brick_albedo(size: int = 512) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var brick_h := size / 8
	var brick_w := size / 4
	var mortar := Color(0.22, 0.20, 0.18)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for y in size:
		var row := y / brick_h
		var offset := (brick_w / 2) if (row % 2 == 1) else 0
		for x in size:
			var local_x := (x + offset) % brick_w
			var local_y := y % brick_h
			var is_mortar := local_x < 3 or local_y < 3
			if is_mortar:
				var m := mortar.darkened(rng.randf_range(0.0, 0.08))
				img.set_pixel(x, y, m)
			else:
				var base := Color(
					rng.randf_range(0.42, 0.58),
					rng.randf_range(0.18, 0.28),
					rng.randf_range(0.12, 0.20)
				)
				# subtle per-brick variation
				var bx := ((x + offset) / brick_w)
				var by := row
				rng.seed = bx * 73856093 ^ by * 19349663
				base = base.lightened(rng.randf_range(-0.05, 0.08))
				# edge wear
				var edge := mini(local_x, mini(local_y, mini(brick_w - local_x, brick_h - local_y)))
				if edge < 6:
					base = base.darkened(0.08)
				# grit
				if rng.randf() < 0.04:
					base = base.lightened(0.12)
				img.set_pixel(x, y, base)
	return ImageTexture.create_from_image(img)


static func concrete_albedo(size: int = 512) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.02
	n.fractal_octaves = 4
	var n2 := FastNoiseLite.new()
	n2.seed = 99
	n2.frequency = 0.08
	for y in size:
		for x in size:
			var a := (n.get_noise_2d(x, y) + 1.0) * 0.5
			var b := (n2.get_noise_2d(x, y) + 1.0) * 0.5
			var v := lerpf(0.28, 0.42, a) + (b - 0.5) * 0.06
			# hairline cracks
			if absf(n.get_noise_2d(x * 0.4, y * 0.4)) > 0.78:
				v *= 0.7
			img.set_pixel(x, y, Color(v, v * 0.98, v * 0.95))
	return ImageTexture.create_from_image(img)


static func metal_panel_albedo(size: int = 512) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var panel := size / 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	for y in size:
		for x in size:
			var px := x % panel
			var py := y % panel
			var base := Color(0.18, 0.20, 0.24)
			if px < 4 or py < 4 or px > panel - 5 or py > panel - 5:
				base = Color(0.12, 0.13, 0.15)
			# rivets
			var cx := panel / 2
			var cy := panel / 2
			var d := Vector2(px - cx, py - cy).length()
			if d < 6.0:
				base = Color(0.35, 0.36, 0.38)
			elif d < 8.0:
				base = Color(0.08, 0.08, 0.09)
			# scratches
			if rng.randf() < 0.01:
				base = base.lightened(0.15)
			# vertical gradient
			base = base.lightened((1.0 - float(py) / panel) * 0.05)
			img.set_pixel(x, y, base)
	return ImageTexture.create_from_image(img)


static func wood_albedo(size: int = 512) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 55
	n.frequency = 0.015
	n.fractal_octaves = 3
	for y in size:
		for x in size:
			var grain := (n.get_noise_2d(x * 0.15, y) + 1.0) * 0.5
			var stripe := sin(y * 0.08 + grain * 4.0) * 0.5 + 0.5
			var r := lerpf(0.28, 0.48, stripe)
			var g := lerpf(0.14, 0.28, stripe)
			var b := lerpf(0.06, 0.12, stripe)
			img.set_pixel(x, y, Color(r, g, b))
	return ImageTexture.create_from_image(img)


static func emissive_strip(size: int = 128) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var cy := absf(y - size * 0.5) / (size * 0.5)
			var intensity := clampf(1.0 - cy * 1.6, 0.0, 1.0)
			intensity = pow(intensity, 1.5)
			img.set_pixel(x, y, Color(0.4 * intensity, 0.85 * intensity, 1.0 * intensity, 1.0))
	return ImageTexture.create_from_image(img)


static func warning_stripes(size: int = 256) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var band := int((x + y) / 24.0) % 2
			if band == 0:
				img.set_pixel(x, y, Color(0.85, 0.65, 0.05))
			else:
				img.set_pixel(x, y, Color(0.08, 0.08, 0.08))
	return ImageTexture.create_from_image(img)


static func make_standard_material(albedo: Texture2D, roughness: float = 0.85, metallic: float = 0.0, uv_scale: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	return mat


static func load_or_procedural(path: String, procedural_callable: Callable) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path)
		if tex is Texture2D:
			return tex as Texture2D
	return procedural_callable.call() as Texture2D
