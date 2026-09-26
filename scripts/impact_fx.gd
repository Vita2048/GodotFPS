extends Node
## Pooled bullet-hole Decals + one-shot GPUParticles3D impact bursts.
## Per-surface hole maps (albedo / normal / opacity / roughness).

const DECAL_POOL := 96
const BURST_POOL := 16
const LIGHT_POOL := 8
# Base diameter; each material has its own physically scaled damage profile.
const HOLE_QUAD := 0.16
const DECAL_DEPTH := 0.07

enum SurfaceKind { CONCRETE, BRICK, METAL, WOOD, GLASS, PLASTER, TILE, RUBBER }
const STAMP_VARIANTS := 3

var _albedo: Array[Texture2D] = []
var _normal: Array[Texture2D] = []
var _orm: Array[Texture2D] = []
var _spark_tex: Texture2D
var _dust_tex: Texture2D
var _decals: Array[Decal] = []
var _decal_i: int = 0
var _bursts: Array[Node3D] = []
var _burst_i: int = 0
var _lights: Array[OmniLight3D] = []
var _light_i: int = 0
var _host: Node3D
var _rng := RandomNumberGenerator.new()
var _glass_marks: Array[MeshInstance3D] = []
var _glass_i := 0


func clear_level() -> void:
	for mark in _glass_marks:
		if is_instance_valid(mark): mark.visible = false
	for decal in _decals:
		if is_instance_valid(decal): decal.visible = false
	for burst in _bursts:
		if is_instance_valid(burst):
			burst.visible = false
			for particle in burst.get_children():
				if particle is GPUParticles3D: particle.emitting = false
	for light in _lights:
		if is_instance_valid(light): light.visible = false


func _ready() -> void:
	_rng.randomize()
	_load_textures()
	call_deferred("_ensure_host")


func _ensure_host() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _host and is_instance_valid(_host) and _host.is_inside_tree():
		return
	var existing := scene.get_node_or_null("ImpactFXHost") as Node3D
	if existing:
		_host = existing
		if _decals.is_empty():
			_build_pools()
		return
	_host = Node3D.new()
	_host.name = "ImpactFXHost"
	scene.add_child(_host)
	_build_pools()


func _load_textures() -> void:
	_albedo.clear()
	_normal.clear()
	_orm.clear()
	# Packed in SurfaceKind order: CONCRETE, BRICK, METAL, WOOD
	for kind in SurfaceKind.values():
		for variant in STAMP_VARIANTS:
			var packed: Array = _build_stamp(kind, variant)
			_albedo.append(packed[0])
			_normal.append(packed[1])
			_orm.append(packed[2])
	_spark_tex = _try_tex("res://assets/fx/spark.png")
	_dust_tex = _try_tex("res://assets/fx/dust_puff.png")


func _try_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _load_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			var img: Image = (res as Texture2D).get_image()
			if img:
				if img.is_compressed():
					img.decompress()
				return img
	var loaded := Image.new()
	if loaded.load(path) == OK:
		return loaded
	return null


func _surf_path(kind: SurfaceKind, suffix: String) -> String:
	var name := "concrete"
	match kind:
		SurfaceKind.BRICK:
			name = "brick"
		SurfaceKind.METAL:
			name = "metal"
		SurfaceKind.WOOD:
			name = "wood"
		_:
			name = "concrete"
	return "res://assets/textures/%s_%s.jpg" % [name, suffix]


func _sample_colors(img: Image, count: int) -> Array[Color]:
	var out: Array[Color] = []
	if img == null:
		out.append(Color(0.35, 0.35, 0.35))
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var w := img.get_width()
	var h := img.get_height()
	for i in count:
		out.append(img.get_pixel(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1)))
	out.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
	return out


func _build_stamp(kind: SurfaceKind, variant: int = 0) -> Array:
	const S := 256
	var hole_nor := _load_image("res://assets/fx/hole_nor.png")
	var hole_op := _load_image("res://assets/fx/hole_opacity.png")
	var hole_alb := _load_image("res://assets/fx/hole_albedo.png")
	var hole_rg := _load_image("res://assets/fx/hole_rough.png")
	var diff := _load_image(_surf_path(kind, "diff"))
	var nor_src := _load_image(_surf_path(kind, "nor"))
	var rough_src := _load_image(_surf_path(kind, "rough"))
	if hole_op:
		hole_op.resize(S, S, Image.INTERPOLATE_LANCZOS)
	if hole_nor:
		hole_nor.resize(S, S, Image.INTERPOLATE_LANCZOS)
	if hole_alb:
		hole_alb.resize(S, S, Image.INTERPOLATE_LANCZOS)
	if hole_rg:
		hole_rg.resize(S, S, Image.INTERPOLATE_LANCZOS)

	var cols := _sample_colors(diff, 24)
	var dark: Color = cols[0] if cols.size() else Color(0.08, 0.07, 0.06)
	var mid: Color = cols[cols.size() / 3] if cols.size() > 3 else Color(0.3, 0.25, 0.2)
	var light: Color = cols[mini(cols.size() - 1, cols.size() * 2 / 3)] if cols.size() else Color(0.5, 0.4, 0.3)
	var pale: Color = cols[cols.size() - 1] if cols.size() else Color(0.7, 0.6, 0.45)

	var alb := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var nrm := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var orm := Image.create(S, S, false, Image.FORMAT_RGBA8)
	alb.fill(Color(0, 0, 0, 0))
	nrm.fill(Color(0.5, 0.5, 1.0, 0.0))
	orm.fill(Color(1, 0.5, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + int(kind) + variant * 7919
	var cx := S * 0.5
	var cy := S * 0.5

	# Coverage mask we fill per material.
	var mask := Image.create(S, S, false, Image.FORMAT_L8)
	mask.fill(Color(0, 0, 0, 1))

	# Same compact puncture as metal: dark cavity + thin material ring. No filled
	# cookie of the wall texture (that reads as a sticker on brick/wood).
	_stamp_blob(mask, cx, cy, 30 if kind == SurfaceKind.WOOD else 46, 63 if kind == SurfaceKind.WOOD else 44, 1.0)
	# Distinct broken edges, rather than the same round puncture everywhere.
	if kind in [SurfaceKind.CONCRETE, SurfaceKind.BRICK, SurfaceKind.PLASTER, SurfaceKind.TILE]:
		for i in 18:
			var angle := rng.randf() * TAU
			var reach := rng.randf_range(28, 49)
			_stamp_blob(mask, cx + cos(angle) * reach, cy + sin(angle) * reach, rng.randf_range(5, 15), rng.randf_range(4, 13), 0.9)
	if kind in [SurfaceKind.GLASS, SurfaceKind.TILE]:
		for i in 7:
			var angle := rng.randf() * TAU
			for j in range(18, 90):
				_stamp_blob(mask, cx + cos(angle) * j, cy + sin(angle) * j, 1.2, 1.2, 0.7)
	if kind == SurfaceKind.WOOD:
		for i in 8:
			_stamp_blob(mask, cx + rng.randf_range(-8, 8), cy + rng.randf_range(-18, 18), rng.randf_range(1.6, 3.2), rng.randf_range(10, 22), 0.85)
	elif kind == SurfaceKind.BRICK:
		for i in 6:
			_stamp_blob(mask, cx + rng.randf_range(-16, 16), cy + rng.randf_range(-14, 14), rng.randf_range(3, 7), rng.randf_range(2.5, 6), 0.75)
	elif kind == SurfaceKind.CONCRETE:
		for i in 5:
			_stamp_blob(mask, cx + rng.randf_range(-12, 12), cy + rng.randf_range(-12, 12), rng.randf_range(3, 6), rng.randf_range(3, 6), 0.7)
	else:
		for i in 5:
			_stamp_blob(mask, cx + rng.randf_range(-10, 10), cy + rng.randf_range(-8, 8), rng.randf_range(3, 6), rng.randf_range(2.5, 5), 0.8)

	var cavity := dark.darkened(0.55)
	var ring: Color
	match kind:
		SurfaceKind.METAL:
			cavity = Color(0.12, 0.11, 0.10)
			ring = Color(dark.r * 0.7 + 0.28, dark.g * 0.45, dark.b * 0.2).lerp(mid, 0.25)
		SurfaceKind.WOOD:
			cavity = dark.darkened(0.62)
			ring = mid.lerp(pale, 0.35)
		SurfaceKind.BRICK:
			cavity = Color(0.12, 0.07, 0.05)
			ring = mid.darkened(0.15)
		SurfaceKind.PLASTER, SurfaceKind.TILE:
			cavity = Color(0.23, 0.22, 0.2)
			ring = Color(0.84, 0.82, 0.75)
		SurfaceKind.GLASS:
			cavity = Color(0.45, 0.55, 0.58)
			ring = Color(0.85, 0.96, 1.0)
		SurfaceKind.RUBBER:
			cavity = Color(0.015, 0.018, 0.02)
			ring = Color(0.12, 0.13, 0.14)
		_:
			cavity = Color(0.16, 0.16, 0.15)
			ring = mid.lerp(light, 0.2)

	for y in S:
		for x in S:
			var m := mask.get_pixel(x, y).r
			if m < 0.04:
				continue
			var dx := (x - cx) / 46.0
			var dy := (y - cy) / 44.0
			var r2 := dx * dx + dy * dy
			var col: Color
			if r2 < 0.32:
				col = cavity
			elif r2 < 0.78:
				col = cavity.lerp(ring, clampf((r2 - 0.32) / 0.46, 0.0, 1.0))
			else:
				col = ring
			if kind == SurfaceKind.WOOD and absf(x - cx) < 5.0 and r2 > 0.2:
				col = pale.lerp(cavity, 0.35)
			if kind == SurfaceKind.CONCRETE and hole_alb:
				col = col.lerp(hole_alb.get_pixel(x, y), 0.35)
			col.a = m
			if kind == SurfaceKind.METAL and r2 > 0.55:
				col.a *= clampf(1.15 - r2, 0.0, 1.0)
			alb.set_pixel(x, y, col)

	# Normals: original crater, masked; extra dip in the puncture.
	for y in S:
		for x in S:
			var m := alb.get_pixel(x, y).a
			if m < 0.04:
				continue
			var n := Color(0.5, 0.5, 1.0)
			if hole_nor:
				n = hole_nor.get_pixel(x, y)
			if nor_src and kind != SurfaceKind.METAL:
				var u := clampi(int(float(x) / S * nor_src.get_width()) % nor_src.get_width(), 0, nor_src.get_width() - 1)
				var v := clampi(int(float(y) / S * nor_src.get_height()) % nor_src.get_height(), 0, nor_src.get_height() - 1)
				var ns := nor_src.get_pixel(u, v)
				n.r = lerpf(n.r, ns.r, 0.28)
				n.g = lerpf(n.g, ns.g, 0.28)
			n.a = m
			nrm.set_pixel(x, y, n)
			var rough := 0.7
			if hole_rg:
				rough = hole_rg.get_pixel(x, y).r
			if rough_src:
				var ur := clampi(int(float(x) / S * rough_src.get_width()) % rough_src.get_width(), 0, rough_src.get_width() - 1)
				var vr := clampi(int(float(y) / S * rough_src.get_height()) % rough_src.get_height(), 0, rough_src.get_height() - 1)
				rough = lerpf(rough, rough_src.get_pixel(ur, vr).r, 0.5)
			var met := 0.0
			if kind == SurfaceKind.METAL:
				var lum := alb.get_pixel(x, y).get_luminance()
				met = clampf((0.22 - lum) * 4.0, 0.0, 1.0) * m
			orm.set_pixel(x, y, Color(1.0, rough, met, m))

	return [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(nrm), ImageTexture.create_from_image(orm)]


func _stamp_blob(mask: Image, cx: float, cy: float, rx: float, ry: float, strength: float) -> void:
	var w := mask.get_width()
	var h := mask.get_height()
	var x0 := clampi(int(cx - rx - 1), 0, w - 1)
	var x1 := clampi(int(cx + rx + 1), 0, w - 1)
	var y0 := clampi(int(cy - ry - 1), 0, h - 1)
	var y1 := clampi(int(cy + ry + 1), 0, h - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := (x - cx) / maxf(rx, 0.001)
			var dy := (y - cy) / maxf(ry, 0.001)
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var v := (1.0 - d) * strength
			var old := mask.get_pixel(x, y).r
			if v > old:
				mask.set_pixel(x, y, Color(v, v, v))


func _fallback_dot() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var c := Vector2(31.5, 31.5)
	for y in 64:
		for x in 64:
			var d := Vector2(x, y).distance_to(c) / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(0.18, 0.17, 0.16, a))
	return ImageTexture.create_from_image(img)


func _build_pools() -> void:
	_glass_marks.clear()
	for i in 24:
		var mark := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 0.28
		mark.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mark.material_override = mat
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.visible = false
		_host.add_child(mark)
		_glass_marks.append(mark)
	_decals.clear()
	_bursts.clear()
	_lights.clear()
	for i in DECAL_POOL:
		var d := Decal.new()
		d.size = Vector3(HOLE_QUAD, DECAL_DEPTH, HOLE_QUAD)
		d.cull_mask = 1
		d.upper_fade = 0.7
		d.lower_fade = 0.7
		d.normal_fade = 0.35
		d.visible = false
		_host.add_child(d)
		_decals.append(d)
	for i in BURST_POOL:
		_bursts.append(_make_burst())
	for i in LIGHT_POOL:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 1.6
		l.shadow_enabled = false
		l.visible = false
		_host.add_child(l)
		_lights.append(l)


func _make_burst() -> Node3D:
	var root := Node3D.new()
	root.visible = false
	_host.add_child(root)

	var sparks := GPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = 24
	sparks.lifetime = 0.20
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	sparks.visibility_aabb = AABB(Vector3(-1.2, -1.2, -1.2), Vector3(2.4, 2.4, 2.4))
	sparks.process_material = _spark_process()
	sparks.draw_pass_1 = _particle_quad(_spark_tex, true, Color(1.0, 0.85, 0.45), Vector2(0.028, 0.028))
	root.add_child(sparks)

	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 16
	dust.lifetime = 0.65
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.local_coords = false
	dust.visibility_aabb = AABB(Vector3(-2.5, -2.5, -2.5), Vector3(5, 5, 5))
	dust.process_material = _dust_process()
	dust.draw_pass_1 = _particle_quad(_dust_tex, false, Color(0.72, 0.68, 0.62, 0.85), Vector2(0.065, 0.065))
	root.add_child(dust)

	var chips := GPUParticles3D.new()
	chips.name = "Chips"
	chips.amount = 18
	chips.lifetime = 0.45
	chips.one_shot = true
	chips.explosiveness = 1.0
	chips.local_coords = false
	chips.visibility_aabb = AABB(Vector3(-2.5, -2.5, -2.5), Vector3(5, 5, 5))
	chips.process_material = _chip_process()
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.045, 0.035, 0.025)
	var chip_mat := StandardMaterial3D.new()
	chip_mat.vertex_color_use_as_albedo = true
	chip_mat.roughness = 0.9
	chip_mesh.material = chip_mat
	chips.draw_pass_1 = chip_mesh
	root.add_child(chips)

	return root


func _particle_quad(tex: Texture2D, additive: bool, tint: Color, quad_size: Vector2 = Vector2(0.05, 0.05)) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = quad_size
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = tint
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.emission_enabled = true
		m.emission = tint
		m.emission_energy_multiplier = 2.2
	q.material = m
	return q


func _spark_process() -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.008
	p.direction = Vector3(0, 1, 0)
	p.spread = 22.0
	p.initial_velocity_min = 2.8
	p.initial_velocity_max = 5.6
	p.gravity = Vector3(0, -7.0, 0)
	p.damping_min = 6.0
	p.damping_max = 12.0
	p.scale_min = 0.5
	p.scale_max = 1.2
	# White-hot core fading to orange
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.75))
	grad.add_point(0.4, Color(1.0, 0.72, 0.3))
	grad.set_color(1, Color(0.8, 0.35, 0.05, 0.0))
	color_ramp.gradient = grad
	p.color_ramp = color_ramp
	p.color = Color(1.0, 0.9, 0.55)
	return p


func _dust_process() -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.direction = Vector3(0, 1, 0)
	p.spread = 60.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -0.3, 0)
	p.damping_min = 1.2
	p.damping_max = 2.8
	p.scale_min = 1.6
	p.scale_max = 3.2
	# Fade-out so the puff dissipates naturally
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.85))
	grad.add_point(0.6, Color(1, 1, 1, 0.5))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	color_ramp.gradient = grad
	p.color_ramp = color_ramp
	p.color = Color(0.72, 0.68, 0.62, 0.9)
	return p


func _chip_process() -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.direction = Vector3(0, 1, 0)
	p.spread = 45.0
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -14.0, 0)
	p.damping_min = 0.8
	p.damping_max = 2.0
	p.scale_min = 0.3
	p.scale_max = 0.85
	p.color = Color(0.5, 0.46, 0.4)
	return p


func spawn(pos: Vector3, normal: Vector3, collider: Object = null) -> void:
	_ensure_host()
	if _host == null:
		return
	var n := normal.normalized()
	if n.length_squared() < 0.01:
		n = Vector3.UP
	var kind := _detect_kind(collider)
	# Pooled world decals must not hover after a movable prop leaves the impact.
	if not collider is RigidBody3D:
		_place_decal(pos, n, kind)
	_place_burst(pos, n, kind)
	_flash(pos, kind)
	var sfx_name := "hit_concrete"
	match kind:
		SurfaceKind.METAL:
			sfx_name = "hit_metal"
		SurfaceKind.WOOD:
			sfx_name = "hit_wood"
		SurfaceKind.BRICK:
			sfx_name = "hit_brick"
		SurfaceKind.GLASS, SurfaceKind.TILE:
			sfx_name = "hit_glass"
		SurfaceKind.RUBBER:
			sfx_name = "hit_wood"
		_:
			sfx_name = "hit_concrete"
	SFX.play_3d(_host, sfx_name, pos, -10.0)


func _place_decal(pos: Vector3, n: Vector3, kind: SurfaceKind) -> void:
	# Godot decals do not project onto transparent materials; glass needs a surface quad.
	if kind == SurfaceKind.GLASS and not _glass_marks.is_empty():
		var mark := _glass_marks[_glass_i]
		_glass_i = (_glass_i + 1) % _glass_marks.size()
		mark.visible = true
		mark.global_position = pos + n * 0.012
		mark.look_at(pos + n, Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD)
		(mark.material_override as StandardMaterial3D).albedo_texture = _albedo[int(kind) * STAMP_VARIANTS + _rng.randi_range(0, STAMP_VARIANTS - 1)]
		return
	if _decals.is_empty() or _albedo.is_empty():
		return
	var d := _decals[_decal_i]
	_decal_i = (_decal_i + 1) % _decals.size()
	d.visible = true
	d.emission_energy = 0.0
	d.modulate = Color(1.0, 1.0, 1.0)
	var ki := int(kind) * STAMP_VARIANTS + _rng.randi_range(0, STAMP_VARIANTS - 1)
	if ki < 0 or ki >= _albedo.size():
		ki = 0
	d.texture_albedo = _albedo[ki]
	d.texture_normal = _normal[ki]
	d.texture_orm = _orm[ki]
	# Same mix language as metal: stamp is a small dark pit, wall shows around it via alpha.
	d.albedo_mix = 1.0
	# Impact diameter is independent of texture tiling.
	var scale_factor := 1.0
	match kind:
		SurfaceKind.CONCRETE, SurfaceKind.PLASTER: scale_factor = 1.5
		SurfaceKind.BRICK, SurfaceKind.TILE: scale_factor = 1.3
		SurfaceKind.WOOD: scale_factor = 1.25
		SurfaceKind.GLASS: scale_factor = 2.0
		SurfaceKind.RUBBER: scale_factor = 0.65
	# ±15 % random variation so impacts don't look cookie-cutter.
	var variation := _rng.randf_range(0.85, 1.15)
	var quad := HOLE_QUAD * scale_factor * variation
	d.size = Vector3(quad, DECAL_DEPTH, quad)
	d.transform = Transform3D(_basis_from_normal(n), pos + n * 0.008)
	# Per-material modulate tint for extra realism
	match kind:
		SurfaceKind.METAL:
			# Subtle scorch darkening around the impact
			d.modulate = Color(0.88, 0.84, 0.78)
			d.rotate(n, _rng.randf_range(-0.4, 0.4))
		SurfaceKind.WOOD:
			d.rotate(n, _rng.randf_range(-0.2, 0.2))
		SurfaceKind.BRICK:
			# Slight warm tint to blend with brick dust
			d.modulate = Color(0.95, 0.90, 0.88)
			d.rotate(n, _rng.randf() * TAU)
		_:
			d.rotate(n, _rng.randf() * TAU)


func _place_burst(pos: Vector3, n: Vector3, kind: SurfaceKind) -> void:
	if _bursts.is_empty():
		return
	var root := _bursts[_burst_i]
	_burst_i = (_burst_i + 1) % _bursts.size()
	root.visible = true
	root.global_transform = Transform3D(_basis_from_normal(n), pos + n * 0.012)
	var sparks := root.get_node("Sparks") as GPUParticles3D
	var dust := root.get_node("Dust") as GPUParticles3D
	var chips := root.get_node("Chips") as GPUParticles3D
	_aim_burst(sparks, n)
	_aim_burst(dust, n)
	_aim_burst(chips, n)
	var q := QualitySettings.level if QualitySettings else 0
	var low := q == 0
	# Every reuse resets properties that another material may have changed.
	(chips.draw_pass_1 as BoxMesh).size = Vector3(0.025, 0.10, 0.012) if kind == SurfaceKind.WOOD else Vector3(0.045, 0.035, 0.025)
	if kind in [SurfaceKind.GLASS, SurfaceKind.TILE]:
		(chips.draw_pass_1 as BoxMesh).size = Vector3(0.055, 0.06, 0.008)
	match kind:
		SurfaceKind.METAL:
			if sparks:
				sparks.amount = 22 if not low else 10
				_restart(sparks)
			if dust:
				dust.emitting = false
			if chips:
				chips.emitting = false
		SurfaceKind.WOOD:
			if sparks:
				sparks.emitting = false
			if dust:
				dust.amount = 8 if not low else 4
				if dust.process_material is ParticleProcessMaterial:
					var pm := dust.process_material as ParticleProcessMaterial
					pm.color = Color(0.68, 0.52, 0.34, 0.85)
					pm.scale_min = 1.2
					pm.scale_max = 2.4
				_restart(dust)
			if chips:
				chips.amount = 16 if not low else 8
				if chips.process_material is ParticleProcessMaterial:
					var pm := chips.process_material as ParticleProcessMaterial
					pm.color = Color(0.48, 0.34, 0.18)
					pm.initial_velocity_min = 2.2
					pm.initial_velocity_max = 5.0
				_restart(chips)
		SurfaceKind.BRICK, SurfaceKind.TILE, SurfaceKind.GLASS:
			if sparks:
				sparks.emitting = false
			if dust:
				dust.amount = 14 if not low else 7
				if dust.process_material is ParticleProcessMaterial:
					var pm := dust.process_material as ParticleProcessMaterial
					pm.color = Color(0.65, 0.38, 0.28, 0.9) if kind == SurfaceKind.BRICK else Color(0.85, 0.9, 0.9, 0.4)
					pm.scale_min = 1.6
					pm.scale_max = 3.2
				_restart(dust)
			if chips:
				chips.amount = 10 if not low else 5
				if chips.process_material is ParticleProcessMaterial:
					var pm := chips.process_material as ParticleProcessMaterial
					pm.color = Color(0.58, 0.30, 0.22) if kind == SurfaceKind.BRICK else Color(0.78, 0.9, 0.94)
					pm.initial_velocity_min = 1.5
					pm.initial_velocity_max = 4.0
					_restart(chips)
		SurfaceKind.RUBBER:
			sparks.emitting = false
			dust.emitting = false
			chips.emitting = false
		_:
			if sparks:
				sparks.emitting = false
			if dust:
				dust.amount = 12 if not low else 6
				if dust.process_material is ParticleProcessMaterial:
					var pm := dust.process_material as ParticleProcessMaterial
					pm.color = Color(0.76, 0.73, 0.68, 0.88)
					pm.scale_min = 1.5
					pm.scale_max = 3.0
				_restart(dust)
			if chips:
				chips.amount = 8 if not low else 4
				if chips.process_material is ParticleProcessMaterial:
					var pm := chips.process_material as ParticleProcessMaterial
					pm.color = Color(0.5, 0.46, 0.4)
					pm.initial_velocity_min = 1.8
					pm.initial_velocity_max = 4.5
				_restart(chips)


func _aim_burst(p: GPUParticles3D, n: Vector3) -> void:
	if p == null:
		return
	p.global_transform = Transform3D(Basis.IDENTITY, p.get_parent().global_position)
	if p.process_material is ParticleProcessMaterial:
		var pm := p.process_material as ParticleProcessMaterial
		pm.direction = n.normalized()
		pm.spread = 18.0 if p.name == "Sparks" else 28.0


func _restart(p: GPUParticles3D) -> void:
	p.emitting = false
	p.restart()
	p.emitting = true


func _flash(pos: Vector3, kind: SurfaceKind) -> void:
	if kind != SurfaceKind.METAL:
		return
	if _lights.is_empty():
		return
	var l := _lights[_light_i]
	if l.has_meta("fade"):
		var previous: Tween = l.get_meta("fade")
		if previous and previous.is_valid(): previous.kill()
	_light_i = (_light_i + 1) % _lights.size()
	l.visible = true
	l.global_position = pos
	match kind:
		SurfaceKind.METAL:
			l.light_color = Color(1.0, 0.82, 0.45)
			l.light_energy = 3.0
			l.omni_range = 2.2
		SurfaceKind.BRICK:
			l.light_color = Color(1.0, 0.70, 0.45)
			l.light_energy = 1.4
			l.omni_range = 1.4
		SurfaceKind.WOOD:
			l.light_color = Color(1.0, 0.85, 0.55)
			l.light_energy = 1.2
			l.omni_range = 1.3
		_:
			l.light_color = Color(1.0, 0.88, 0.65)
			l.light_energy = 1.6
			l.omni_range = 1.5
	var tw := create_tween()
	l.set_meta("fade", tw)
	tw.tween_property(l, "light_energy", 0.0, 0.08)
	tw.tween_callback(func(): l.visible = false)


func _basis_from_normal(n: Vector3) -> Basis:
	var up := Vector3.UP
	if absf(n.dot(up)) > 0.92:
		up = Vector3.FORWARD
	var x := up.cross(n)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(n).normalized()
	return Basis(x, n, z)


func _detect_kind(collider: Object) -> SurfaceKind:
	if collider == null or not (collider is Node):
		return SurfaceKind.CONCRETE
	var n := collider as Node
	var hops := 0
	while n and hops < 6:
		if n.has_meta("surface_kind"):
			return _kind_from_name(str(n.get_meta("surface_kind")))
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.material_override:
				return _kind_from_name(mi.material_override.resource_name)
		n = n.get_parent()
		hops += 1
	# Sibling mesh sharing this body's transform (not "first mesh in the room").
	if collider is Node3D:
		var body := collider as Node3D
		var p := body.get_parent()
		if p:
			var best: MeshInstance3D = null
			var best_d := 0.35
			for c in p.get_children():
				if c is MeshInstance3D:
					var d: float = (c as Node3D).global_position.distance_to(body.global_position)
					if d < best_d:
						best_d = d
						best = c
			if best:
				if best.has_meta("surface_kind"):
					return _kind_from_name(str(best.get_meta("surface_kind")))
				if best.material_override:
					return _kind_from_name(best.material_override.resource_name)
	return SurfaceKind.CONCRETE


func _kind_from_name(s: String) -> SurfaceKind:
	var t := s.to_lower()
	if "glass" in t: return SurfaceKind.GLASS
	if "plaster" in t: return SurfaceKind.PLASTER
	if "tile" in t: return SurfaceKind.TILE
	if "rubber" in t: return SurfaceKind.RUBBER
	if "metal" in t or "trim" in t or "copper" in t:
		return SurfaceKind.METAL
	if "wood" in t:
		return SurfaceKind.WOOD
	if "brick" in t or "stone" in t:
		return SurfaceKind.BRICK
	return SurfaceKind.CONCRETE
