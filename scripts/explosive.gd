extends Node3D
## Swept projectiles avoid tunnelling; blast rays respect walls and floors.
var velocity := Vector3.ZERO
var rocket := false
var remaining := 2.6
var source: PhysicsBody3D
var spent := false
var trail: GPUParticles3D
var bounce_cd := 0.0

func _ready() -> void:
	add_to_group("transient_combat")
	var mesh := MeshInstance3D.new()
	var shape := CapsuleMesh.new()
	shape.radius = 0.075 if rocket else 0.095
	shape.height = 0.5 if rocket else 0.24
	mesh.mesh = shape
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("6f7945")
	mat.metallic = 0.6
	mat.roughness = 0.45
	mesh.material_override = mat
	mesh.rotation.x = PI * 0.5 if rocket else 0.0
	add_child(mesh)
	if rocket:
		remaining = 5.0
		trail = GPUParticles3D.new()
		trail.amount = 28
		trail.lifetime = 0.45
		trail.local_coords = false
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.BACK
		pm.spread = 8
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.8
		pm.gravity = Vector3(0, 0.2, 0)
		pm.scale_min = 0.1
		pm.scale_max = 0.4
		pm.color = Color(0.6, 0.57, 0.5, 0.5)
		trail.process_material = pm
		var puff := SphereMesh.new()
		puff.radius = 0.2
		puff.height = 0.4
		var smoke := StandardMaterial3D.new()
		smoke.albedo_color = Color(0.6, 0.57, 0.5, 0.3)
		smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material = smoke
		trail.draw_pass_1 = puff
		add_child(trail)

func _physics_process(delta: float) -> void:
	if GameState.paused or not GameState.game_started or GameState.player_dead:
		if trail: trail.speed_scale = 0
		return
	if trail: trail.speed_scale = 1
	remaining -= delta
	bounce_cd -= delta
	if remaining <= 0:
		detonate()
		return
	if not rocket:
		velocity.y -= 9.8 * delta
	var start := global_position
	var end := start + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(start, end, 1 | 4 | 8)
	if is_instance_valid(source): query.exclude = [source.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = end
	else:
		global_position = hit.position + hit.normal * 0.11
		if rocket:
			detonate()
			return
		velocity = velocity.bounce(hit.normal) * 0.48
		if hit.normal.y > 0.6 and velocity.length() < 1.2:
			velocity = Vector3.ZERO
		if bounce_cd <= 0 and velocity.length() > 0.8:
			SFX.play_3d(get_parent(), "grenade_bounce", global_position, -16)
			bounce_cd = 0.15
	if rocket and velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP)
	elif not rocket:
		rotation += Vector3(2, 1, 3) * delta * minf(velocity.length(), 3)

func detonate() -> void:
	if spent: return
	spent = true
	blast(get_parent(), global_position, 7.0 if rocket else 6.0, 150 if rocket else 120)
	queue_free()

static func blast(host: Node3D, point: Vector3, radius: float, damage: int, excluded: PhysicsBody3D = null) -> void:
	var tree := host.get_tree()
	var space := host.get_world_3d().direct_space_state
	var targets: Array[Node] = []
	for group in ["enemy", "player", "reactive", "shatterable"]:
		for node in tree.get_nodes_in_group(group):
			if not targets.has(node): targets.append(node)
	for target in targets:
		if not is_instance_valid(target) or target.is_queued_for_deletion() or target == excluded: continue
		var aim: Vector3 = target.global_position
		if target.is_in_group("enemy") or target.is_in_group("player"): aim += Vector3.UP * 0.8
		var distance := aim.distance_to(point)
		if distance > radius: continue
		var q := PhysicsRayQueryParameters3D.create(point, aim, 1)
		if is_instance_valid(excluded): q.exclude = [excluded.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.collider != target and not target.is_ancestor_of(hit.collider): continue
		var dealt := maxi(1, int(damage * pow(1.0 - distance / radius, 1.2)))
		if target.is_in_group("player"):
			target.take_hit(dealt)
		elif target.has_method("take_damage"):
			target.take_damage(dealt, point)
		elif target.has_method("shatter"):
			target.shatter(aim, (aim - point).normalized())
	Enemy.broadcast_gunshot(host, point, 45.0)
	SFX.play_3d(host, "explosion", point, 0)
	var fx := Node3D.new()
	fx.add_to_group("transient_combat")
	host.add_child(fx)
	fx.global_position = point
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.5, 0.15)
	light.light_energy = 9
	light.omni_range = radius * 1.8
	fx.add_child(light)
	for smoke in [false, true]:
		var particles := GPUParticles3D.new()
		particles.amount = 22 if smoke else 32
		particles.lifetime = 1.6 if smoke else 0.5
		particles.one_shot = true
		particles.explosiveness = 1
		var pm := ParticleProcessMaterial.new()
		pm.spread = 180
		pm.initial_velocity_min = 1.0 if smoke else 3.0
		pm.initial_velocity_max = 3.0 if smoke else 11.0
		pm.gravity = Vector3(0, 1 if smoke else -8, 0)
		pm.damping_min = 1
		pm.damping_max = 3
		pm.scale_min = 0.8 if smoke else 0.12
		pm.scale_max = 2.5 if smoke else 0.5
		var ramp := GradientTexture1D.new()
		var grad := Gradient.new()
		grad.set_color(0, Color(0.2, 0.22, 0.24, 0.65) if smoke else Color(1, 0.85, 0.35))
		grad.set_color(1, Color(0.22, 0.23, 0.24, 0))
		ramp.gradient = grad
		pm.color_ramp = ramp
		particles.process_material = pm
		var mesh := SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.44
		mesh.radial_segments = 8
		mesh.rings = 4
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = material
		particles.draw_pass_1 = mesh
		fx.add_child(particles)
		particles.emitting = true
	var tween := fx.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.25)
	tween.tween_interval(2)
	tween.tween_callback(fx.queue_free)
