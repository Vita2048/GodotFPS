extends Node3D
## Fire first, delayed smoke second. Visible without glow on the Low preset.
const BILLBOARD := preload("res://shaders/blast_billboard.gdshader")
var blast_radius := 6.0
var elapsed := 0.0
var lobes: Array[MeshInstance3D] = []
var clouds: Array[MeshInstance3D] = []
var ring: MeshInstance3D
var light: OmniLight3D
var sparks: GPUParticles3D
var fragments: GPUParticles3D

func _ready() -> void:
	add_to_group("transient_combat")
	var low := QualitySettings.level == QualitySettings.Quality.LOW
	for i in (5 if low else 8):
		var lobe := _sprite(0, float(i) * 3.7)
		lobe.set_meta("offset", Vector3.ZERO if i == 0 else Vector3(cos(i * 2.4), sin(i * 1.7) * 0.6 + 0.35, sin(i * 2.4)) * 0.65)
		lobes.append(lobe)
	for i in (3 if low else 5):
		var cloud := _sprite(1, float(i) * 5.3)
		cloud.visible = false
		clouds.append(cloud)
	ring = _sprite(2, 0)
	light = OmniLight3D.new()
	light.light_color = Color(1, 0.55, 0.16)
	light.omni_range = blast_radius * 1.8
	light.shadow_enabled = false
	add_child(light)
	sparks = _particles(true, 28 if low else 60)
	fragments = _particles(false, 8 if low else 16)
	_update_visuals()

func _sprite(layer: int, seed_value: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * 2
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = BILLBOARD
	mat.set_shader_parameter("layer", layer)
	mat.set_shader_parameter("seed", seed_value)
	mi.material_override = mat
	add_child(mi)
	return mi

func _particles(embers: bool, count: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.one_shot = true
	p.explosiveness = 1
	p.lifetime = 0.8 if embers else 1.1
	p.visibility_aabb = AABB(Vector3.ONE * -10, Vector3.ONE * 20)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 125
	pm.initial_velocity_min = 5 if embers else 3
	pm.initial_velocity_max = 15 if embers else 7
	pm.gravity = Vector3(0, -12, 0)
	pm.damping_min = 1
	pm.damping_max = 3
	pm.angular_velocity_min = -240
	pm.angular_velocity_max = 240
	var ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.95, 0.65) if embers else Color(0.18, 0.16, 0.14))
	grad.add_point(0.3, Color(1, 0.32, 0.025) if embers else Color(0.16, 0.14, 0.12))
	grad.set_color(1, Color(0.3, 0.04, 0.005, 0))
	ramp.gradient = grad
	pm.color_ramp = ramp
	p.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.018, 0.18) if embers else Vector3(0.065, 0.045, 0.05)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if embers:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material = mat
	p.draw_pass_1 = mesh
	add_child(p)
	p.emitting = true
	return p

func _process(delta: float) -> void:
	var frozen := GameState.paused or not GameState.game_started or GameState.player_dead
	sparks.speed_scale = 0 if frozen else 1
	fragments.speed_scale = 0 if frozen else 1
	if frozen: return
	elapsed += delta
	if elapsed > 1.9:
		queue_free()
		return
	_update_visuals()

func _update_visuals() -> void:
	var size := blast_radius / 6.0
	var expansion := 1.0 - exp(-elapsed * 22.0)
	for i in lobes.size():
		var mi := lobes[i]
		mi.visible = elapsed < 0.65
		mi.position = (mi.get_meta("offset") as Vector3) * expansion * size + Vector3.UP * elapsed * 0.9
		mi.scale = Vector3.ONE * maxf(0.05, (0.2 + expansion * (1.35 if i == 0 else 0.95)) * size)
		(mi.material_override as ShaderMaterial).set_shader_parameter("age", clampf(elapsed / 0.65, 0, 1))
	for i in clouds.size():
		var age := clampf((elapsed - 0.22) / 1.65, 0, 1)
		var mi := clouds[i]
		mi.visible = elapsed > 0.22
		mi.position = Vector3(cos(i * 2.4) * age, 0.4 + age * 1.8, sin(i * 2.4) * age) * size
		mi.scale = Vector3.ONE * (0.5 + age * 1.5) * size
		(mi.material_override as ShaderMaterial).set_shader_parameter("age", age)
	ring.visible = elapsed < 0.28
	ring.scale = Vector3.ONE * maxf(0.02, elapsed * 16 * size)
	(ring.material_override as ShaderMaterial).set_shader_parameter("age", clampf(elapsed / 0.28, 0, 1))
	light.light_energy = 13.0 * exp(-elapsed * 13)
