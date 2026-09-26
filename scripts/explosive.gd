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
	if rocket:
		var model := Node3D.new()
		add_child(model)
		preload("res://scripts/ordnance_models.gd").rocket(model)
		model.rotation.x = -PI * 0.5
	else:
		preload("res://scripts/ordnance_models.gd").grenade(self, true)
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
	var fx := preload("res://scripts/blast_effect.gd").new()
	fx.blast_radius = radius
	host.add_child(fx)
	fx.global_position = point
