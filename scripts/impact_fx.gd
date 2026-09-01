extends Node
## Pooled bullet-hole Decals + one-shot GPUParticles3D impact bursts.
## Per-surface hole maps (albedo / normal / opacity / roughness).

const DECAL_POOL := 96
const BURST_POOL := 16
const LIGHT_POOL := 8
# Same world quad on every surface. Metal at this size was the look to match.
const HOLE_QUAD := 0.16
const DECAL_DEPTH := 0.07

enum SurfaceKind { CONCRETE, BRICK, METAL, WOOD }

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
	for kind in [SurfaceKind.CONCRETE, SurfaceKind.BRICK, SurfaceKind.METAL, SurfaceKind.WOOD]:
		var packed: Array = _build_stamp(kind)
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


func _build_stamp(kind: SurfaceKind) -> Array:
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
	rng.seed = 100 + int(kind)
	var cx := S * 0.5
	var cy := S * 0.5

	# Coverage mask we fill per material.
	var mask := Image.create(S, S, false, Image.FORMAT_L8)
	mask.fill(Color(0, 0, 0, 1))

	# Same compact puncture as metal: dark cavity + thin material ring. No filled
	# cookie of the wall texture (that reads as a sticker on brick/wood).
	_stamp_blob(mask, cx, cy, 46, 44, 1.0)
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
			if r2 > 0.55:
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

	if OS.has_feature("editor"):
		var folder := "concrete"
		match kind:
			SurfaceKind.BRICK:
				folder = "brick"
			SurfaceKind.METAL:
				folder = "metal"
			SurfaceKind.WOOD:
				folder = "wood"
		var dir := "res://decals/%s/" % folder
		alb.save_png(dir + "hole_albedo.png")
		var op_out := Image.create(S, S, false, Image.FORMAT_L8)
		for y in S:
			for x in S:
				var a := alb.get_pixel(x, y).a
				op_out.set_pixel(x, y, Color(a, a, a))
		op_out.save_png(dir + "hole_opacity.png")
		var rg_out := Image.create(S, S, false, Image.FORMAT_L8)
		for y in S:
			for x in S:
				var g := orm.get_pixel(x, y).g
				rg_out.set_pixel(x, y, Color(g, g, g))
		rg_out.save_png(dir + "hole_rough.png")
		nrm.save_png(dir + "hole_nor.png")

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
	sparks.amount = 14
	sparks.lifetime = 0.14
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	sparks.visibility_aabb = AABB(Vector3(-0.8, -0.8, -0.8), Vector3(1.6, 1.6, 1.6))
	sparks.process_material = _spark_process()
	sparks.draw_pass_1 = _particle_quad(_spark_tex, true, Color(1.0, 0.72, 0.35), Vector2(0.022, 0.022))
	root.add_child(sparks)

	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 10
	dust.lifetime = 0.55
	dust.one_shot = true
	dust.explosiveness = 0.92
	dust.local_coords = false
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
	chips.local_coords = false
	chips.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	chips.process_material = _chip_process()
	chips.draw_pass_1 = _particle_quad(_dust_tex, false, Color(0.45, 0.42, 0.38))
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
	p.emission_sphere_radius = 0.006
	p.direction = Vector3(0, 1, 0)
	p.spread = 18.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.4
	p.gravity = Vector3(0, -6.0, 0)
	p.damping_min = 8.0
	p.damping_max = 14.0
	p.scale_min = 0.45
	p.scale_max = 1.0
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
	if _decals.is_empty() or _albedo.is_empty():
		return
	var d := _decals[_decal_i]
	_decal_i = (_decal_i + 1) % _decals.size()
	d.visible = true
	d.emission_energy = 0.0
	d.modulate = Color(1.0, 1.0, 1.0)
	var ki := int(kind)
	if ki < 0 or ki >= _albedo.size():
		ki = 0
	d.texture_albedo = _albedo[ki]
	d.texture_normal = _normal[ki]
	d.texture_orm = _orm[ki]
	# Same mix language as metal: stamp is a small dark pit, wall shows around it via alpha.
	d.albedo_mix = 1.0
	d.size = Vector3(HOLE_QUAD, DECAL_DEPTH, HOLE_QUAD)
	d.transform = Transform3D(_basis_from_normal(n), pos + n * 0.008)
	match kind:
		SurfaceKind.WOOD:
			d.rotate(n, _rng.randf_range(-0.2, 0.2))
		SurfaceKind.METAL:
			d.rotate(n, _rng.randf_range(-0.4, 0.4))
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
	match kind:
		SurfaceKind.METAL:
			if sparks:
				sparks.amount = 12 if not low else 7
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


func _aim_burst(p: GPUParticles3D, n: Vector3) -> void:
	if p == null:
		return
	p.global_position = p.get_parent().global_position
	if p.process_material is ParticleProcessMaterial:
		var pm := p.process_material as ParticleProcessMaterial
		pm.direction = n.normalized()
		pm.spread = 16.0 if p.name == "Sparks" else 28.0


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
	if "metal" in t or "trim" in t:
		return SurfaceKind.METAL
	if "wood" in t:
		return SurfaceKind.WOOD
	if "brick" in t or "stone" in t:
		return SurfaceKind.BRICK
	return SurfaceKind.CONCRETE
