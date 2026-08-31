extends Node
## Pooled bullet-hole Decals + one-shot GPUParticles3D impact bursts.
## One generic dent set (albedo / normal / opacity / roughness), skinned per surface.

const DECAL_POOL := 96
const BURST_POOL := 16
const LIGHT_POOL := 8
const DECAL_SIZE := Vector3(0.26, 0.16, 0.26)

enum SurfaceKind { CONCRETE, BRICK, METAL, WOOD }

var _albedo: Texture2D
var _normal: Texture2D
var _normal_brick: Texture2D
var _orm_light: Texture2D
var _orm_wood: Texture2D
var _orm_metal: Texture2D
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
	var albedo_img := _load_image("res://assets/fx/hole_albedo.png")
	var nor_img := _load_image("res://assets/fx/hole_nor.png")
	var opacity_img := _load_image("res://assets/fx/hole_opacity.png")
	var rough_img := _load_image("res://assets/fx/hole_rough.png")
	_pack_maps(albedo_img, nor_img, opacity_img, rough_img)
	_spark_tex = _try_tex("res://assets/fx/spark.png")
	_dust_tex = _try_tex("res://assets/fx/dust_puff.png")


func _try_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _load_image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
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


func _pack_maps(albedo_img: Image, nor_img: Image, opacity_img: Image, rough_img: Image) -> void:
	if albedo_img == null or opacity_img == null:
		_albedo = _fallback_dot()
		_normal = null
		_normal_brick = null
		_orm_light = null
		_orm_wood = null
		_orm_metal = null
		return
	var w := mini(albedo_img.get_width(), 512)
	var h := mini(albedo_img.get_height(), 512)
	albedo_img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	opacity_img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	if nor_img:
		nor_img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	if rough_img:
		rough_img.resize(w, h, Image.INTERPOLATE_LANCZOS)

	var albedo_rgba := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var orm_light := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var orm_wood := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var orm_m := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var nor_std := Image.create(w, h, false, Image.FORMAT_RGBA8) if nor_img else null
	var nor_brk := Image.create(w, h, false, Image.FORMAT_RGBA8) if nor_img else null

	for y in h:
		for x in w:
			var alb := albedo_img.get_pixel(x, y)
			var op := opacity_img.get_pixel(x, y)
			var mask := op.r
			albedo_rgba.set_pixel(x, y, Color(alb.r, alb.g, alb.b, mask))

			var rough := 0.55
			if rough_img:
				rough = rough_img.get_pixel(x, y).r
			# G = roughness, B = metallic, R = AO (leave open so the wall isn't crushed).
			var ao := 1.0
			# Light roughness overlay for masonry; stronger for wood/metal.
			orm_light.set_pixel(x, y, Color(ao, lerpf(0.5, rough, 0.32), 0.0, mask))
			orm_wood.set_pixel(x, y, Color(ao, lerpf(0.5, rough, 0.55), 0.0, mask))
			orm_m.set_pixel(x, y, Color(ao, rough, 1.0, mask))

			if nor_img:
				var n := nor_img.get_pixel(x, y)
				nor_std.set_pixel(x, y, Color(n.r, n.g, n.b, mask))
				var nx := (n.r - 0.5) * 1.35 + 0.5
				var ny := (n.g - 0.5) * 1.35 + 0.5
				nor_brk.set_pixel(x, y, Color(clampf(nx, 0.0, 1.0), clampf(ny, 0.0, 1.0), n.b, mask))

	_albedo = ImageTexture.create_from_image(albedo_rgba)
	_orm_light = ImageTexture.create_from_image(orm_light)
	_orm_wood = ImageTexture.create_from_image(orm_wood)
	_orm_metal = ImageTexture.create_from_image(orm_m)
	if nor_std:
		_normal = ImageTexture.create_from_image(nor_std)
		_normal_brick = ImageTexture.create_from_image(nor_brk)
	else:
		_normal = null
		_normal_brick = null


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
	_decals.clear()
	_bursts.clear()
	_lights.clear()
	for i in DECAL_POOL:
		var d := Decal.new()
		d.size = DECAL_SIZE
		d.cull_mask = 1
		d.upper_fade = 0.35
		d.lower_fade = 0.35
		d.normal_fade = 0.5
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
	sparks.amount = 18
	sparks.lifetime = 0.28
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = true
	sparks.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	sparks.process_material = _spark_process()
	sparks.draw_pass_1 = _particle_quad(_spark_tex, true, Color(1.0, 0.72, 0.35))
	root.add_child(sparks)

	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 10
	dust.lifetime = 0.55
	dust.one_shot = true
	dust.explosiveness = 0.92
	dust.local_coords = true
	dust.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	dust.process_material = _dust_process()
	dust.draw_pass_1 = _particle_quad(_dust_tex, false, Color(0.72, 0.68, 0.62, 0.85))
	root.add_child(dust)

	var chips := GPUParticles3D.new()
	chips.name = "Chips"
	chips.amount = 8
	chips.lifetime = 0.4
	chips.one_shot = true
	chips.explosiveness = 1.0
	chips.local_coords = true
	chips.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	chips.process_material = _chip_process()
	chips.draw_pass_1 = _particle_quad(_dust_tex, false, Color(0.45, 0.42, 0.38))
	root.add_child(chips)

	return root


func _particle_quad(tex: Texture2D, additive: bool, tint: Color) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = tint
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
	p.direction = Vector3(0, 1, 0)
	p.spread = 48.0
	p.initial_velocity_min = 2.4
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = 3.0
	p.damping_max = 6.0
	p.scale_min = 0.35
	p.scale_max = 1.1
	p.color = Color(1.0, 0.85, 0.45)
	return p


func _dust_process() -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -0.4, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_min = 1.4
	p.scale_max = 2.8
	p.color = Color(0.7, 0.66, 0.6, 0.9)
	return p


func _chip_process() -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.direction = Vector3(0, 1, 0)
	p.spread = 40.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.8
	p.gravity = Vector3(0, -12.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.5
	p.scale_min = 0.25
	p.scale_max = 0.7
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
	_place_decal(pos, n, kind)
	_place_burst(pos, n, kind)
	_flash(pos, kind)
	SFX.play_3d(_host, "hit", pos, -12.0)


func _place_decal(pos: Vector3, n: Vector3, kind: SurfaceKind) -> void:
	if _decals.is_empty():
		return
	var d := _decals[_decal_i]
	_decal_i = (_decal_i + 1) % _decals.size()
	d.visible = true
	d.texture_albedo = _albedo
	d.emission_energy = 0.0
	# Shared: normal + opacity (opacity is albedo alpha). Mesh PBR stays on the wall.
	match kind:
		SurfaceKind.METAL:
			d.texture_normal = _normal
			d.texture_orm = _orm_metal
			# Darken / desaturate the gray dent so it reads as scuffed metal.
			d.modulate = Color(0.22, 0.23, 0.25)
			d.albedo_mix = 0.38
			d.size = DECAL_SIZE * _rng.randf_range(0.78, 0.95)
		SurfaceKind.WOOD:
			d.texture_normal = _normal
			d.texture_orm = _orm_wood
			# Puncture, not gray paint: very dark albedo at low mix.
			d.modulate = Color(0.07, 0.055, 0.04)
			d.albedo_mix = 0.14
			d.size = DECAL_SIZE * _rng.randf_range(0.88, 1.08)
		SurfaceKind.BRICK:
			d.texture_normal = _normal_brick if _normal_brick else _normal
			d.texture_orm = _orm_light
			d.modulate = Color(1.0, 1.0, 1.0)
			d.albedo_mix = 0.18
			d.size = DECAL_SIZE * _rng.randf_range(0.72, 0.88)
		_:
			# Concrete (and untagged hits).
			d.texture_normal = _normal
			d.texture_orm = _orm_light
			d.modulate = Color(1.0, 1.0, 1.0)
			d.albedo_mix = 0.22
			d.size = DECAL_SIZE * _rng.randf_range(0.82, 1.02)
	d.transform = Transform3D(_basis_from_normal(n), pos + n * 0.01)
	d.rotate(n, _rng.randf() * TAU)


func _place_burst(pos: Vector3, n: Vector3, kind: SurfaceKind) -> void:
	if _bursts.is_empty():
		return
	var root := _bursts[_burst_i]
	_burst_i = (_burst_i + 1) % _bursts.size()
	root.visible = true
	root.global_transform = Transform3D(_basis_from_normal(n), pos + n * 0.03)
	var sparks := root.get_node("Sparks") as GPUParticles3D
	var dust := root.get_node("Dust") as GPUParticles3D
	var chips := root.get_node("Chips") as GPUParticles3D
	var q := QualitySettings.level if QualitySettings else 0
	var low := q == 0
	match kind:
		SurfaceKind.METAL:
			if sparks:
				sparks.amount = 20 if not low else 12
				_restart(sparks)
			if dust:
				dust.emitting = false
			if chips:
				chips.emitting = false
		SurfaceKind.WOOD:
			if sparks:
				sparks.emitting = false
			if dust:
				dust.amount = 8 if not low else 5
				if dust.process_material is ParticleProcessMaterial:
					(dust.process_material as ParticleProcessMaterial).color = Color(0.58, 0.44, 0.26, 0.9)
				_restart(dust)
			if chips:
				chips.amount = 14 if not low else 8
				if chips.process_material is ParticleProcessMaterial:
					(chips.process_material as ParticleProcessMaterial).color = Color(0.42, 0.3, 0.16)
				_restart(chips)
		_:
			if sparks:
				sparks.emitting = false
			if dust:
				dust.amount = 10 if not low else 6
				var col := Color(0.7, 0.66, 0.6, 0.9)
				if kind == SurfaceKind.BRICK:
					col = Color(0.62, 0.4, 0.3, 0.88)
				if dust.process_material is ParticleProcessMaterial:
					(dust.process_material as ParticleProcessMaterial).color = col
				_restart(dust)
			if chips:
				chips.amount = 6 if not low else 3
				if chips.process_material is ParticleProcessMaterial:
					(chips.process_material as ParticleProcessMaterial).color = Color(0.5, 0.46, 0.4)
				_restart(chips)


func _restart(p: GPUParticles3D) -> void:
	p.emitting = false
	p.restart()
	p.emitting = true


func _flash(pos: Vector3, kind: SurfaceKind) -> void:
	if _lights.is_empty():
		return
	var l := _lights[_light_i]
	_light_i = (_light_i + 1) % _lights.size()
	l.visible = true
	l.global_position = pos
	l.light_color = Color(1.0, 0.72, 0.35) if kind == SurfaceKind.METAL else Color(1.0, 0.85, 0.55)
	l.light_energy = 2.4 if kind == SurfaceKind.METAL else 1.6
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.09)
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
	# Sibling mesh next to a StaticBody
	if collider is Node:
		var p := (collider as Node).get_parent()
		if p:
			for c in p.get_children():
				if c is MeshInstance3D and c.has_meta("surface_kind"):
					return _kind_from_name(str(c.get_meta("surface_kind")))
				if c is MeshInstance3D:
					var mat := (c as MeshInstance3D).material_override
					if mat:
						return _kind_from_name(mat.resource_name)
	return SurfaceKind.CONCRETE


func _kind_from_name(s: String) -> SurfaceKind:
	var t := s.to_lower()
	if "metal" in t or "trim" in t:
		return SurfaceKind.METAL
	if "wood" in t:
		return SurfaceKind.WOOD
	if "brick" in t or "stone" in t:
		return SurfaceKind.BRICK
	return SurfaceKind.CONCRETE
