extends Node3D
class_name ShatterableProp
## Intact furniture that shatters into cheap box-collider debris.

const DEBRIS_LAYER := 8
const MAX_PHYS_PIECES := 22
const FREEZE_AFTER := 1.15

static var _SCENE_CACHE: Dictionary = {}
static var _PIECE_CACHE: Dictionary = {} # fractured_path -> Array[Dictionary]

@export_file("*.glb") var intact_path: String = ""
@export_file("*.glb") var fractured_path: String = ""
@export var piece_mass: float = 1.2
@export var impulse_strength: float = 9.5
@export var debris_lifetime: float = 8.0

var _shattered: bool = false
var _visual_offset: Vector3 = Vector3.ZERO
var _intact_root: Node3D
var _hit_body: StaticBody3D


func setup(intact: String, fractured: String, mass: float = 1.2) -> void:
	intact_path = intact
	fractured_path = fractured
	piece_mass = mass


func _ready() -> void:
	add_to_group("shatterable")
	_spawn_intact()
	# Bake piece templates during load, not on the shot frame.
	_bake_pieces(fractured_path)


func shatter(hit_pos: Vector3, hit_normal: Vector3) -> void:
	if _shattered:
		return
	_shattered = true
	if is_instance_valid(_hit_body):
		_hit_body.queue_free()
		_hit_body = null
	if is_instance_valid(_intact_root):
		_intact_root.queue_free()
		_intact_root = null
	_spawn_debris(hit_pos, hit_normal)
	SFX.play_3d(get_parent(), "wood_break", hit_pos, -4.0)


func _spawn_intact() -> void:
	var scene := _load_scene(intact_path)
	if scene == null:
		return
	_intact_root = scene.instantiate() as Node3D
	add_child(_intact_root)
	_strip_extras(_intact_root)
	_visual_offset = _ground_center_offset(_intact_root)
	_intact_root.position += _visual_offset
	_disable_expensive_draw(_intact_root)
	_add_aabb_collision(_intact_root)


func _spawn_debris(hit_pos: Vector3, hit_normal: Vector3) -> void:
	var pieces: Array = _bake_pieces(fractured_path)
	if pieces.is_empty():
		return

	var debris := Node3D.new()
	debris.name = "Debris"
	add_child(debris)

	var n := mini(pieces.size(), MAX_PHYS_PIECES)
	var nrm := hit_normal.normalized() if hit_normal.length_squared() > 0.01 else Vector3.UP

	for i in n:
		var spec: Dictionary = pieces[i]
		var local_xf: Transform3D = spec["xf"]
		local_xf.origin += _visual_offset

		var rb := RigidBody3D.new()
		rb.mass = maxf(piece_mass * float(spec["volume"]), 0.15)
		rb.collision_layer = DEBRIS_LAYER
		rb.collision_mask = 1 # world only — no shard-vs-shard contacts
		rb.can_sleep = true
		rb.linear_damp = 1.1
		rb.angular_damp = 1.4
		rb.continuous_cd = false
		rb.contact_monitor = false
		rb.max_contacts_reported = 0
		debris.add_child(rb)
		rb.transform = local_xf

		var mi := MeshInstance3D.new()
		mi.mesh = spec["mesh"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		rb.add_child(mi)

		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec["size"]
		col.shape = box
		col.position = spec["center"]
		rb.add_child(col)

		var piece_pos := rb.global_position
		var away := piece_pos - hit_pos
		if away.length_squared() < 0.0004:
			away = nrm
		away = away.normalized()
		var dist := piece_pos.distance_to(hit_pos)
		var falloff := 1.0 / (1.0 + dist * dist * 1.8)
		var impulse := away * impulse_strength * falloff + nrm * (impulse_strength * 0.28)
		impulse.y += 1.4 * falloff
		rb.apply_central_impulse(impulse)
		rb.apply_torque_impulse(away.cross(Vector3.UP) * 0.55 * falloff)

	get_tree().create_timer(FREEZE_AFTER).timeout.connect(func():
		if not is_instance_valid(debris):
			return
		for c in debris.get_children():
			var rb := c as RigidBody3D
			if rb:
				rb.freeze = true
				rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	)
	if debris_lifetime > 0.0:
		get_tree().create_timer(debris_lifetime).timeout.connect(func():
			if is_instance_valid(debris):
				debris.queue_free()
		)


func _add_aabb_collision(root: Node3D) -> void:
	var aabb := AABB()
	var started := false
	var meshes: Array[MeshInstance3D] = []
	_collect_all_meshes(root, meshes)
	for mi in meshes:
		var a: AABB = mi.global_transform * mi.get_aabb()
		if not started:
			aabb = a
			started = true
		else:
			aabb = aabb.merge(a)
	if not started:
		return
	_hit_body = StaticBody3D.new()
	_hit_body.name = "HitBody"
	_hit_body.collision_layer = 1
	_hit_body.collision_mask = 0
	add_child(_hit_body)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	col.shape = box
	_hit_body.add_child(col)
	col.global_position = aabb.get_center()


func _ground_center_offset(root: Node3D) -> Vector3:
	var aabb := AABB()
	var started := false
	var meshes: Array[MeshInstance3D] = []
	_collect_all_meshes(root, meshes)
	for mi in meshes:
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.get_aabb()
		if not started:
			aabb = a
			started = true
		else:
			aabb = aabb.merge(a)
	if not started:
		return Vector3.ZERO
	var world_delta := Vector3(
		global_position.x - aabb.get_center().x,
		global_position.y - aabb.position.y,
		global_position.z - aabb.get_center().z
	)
	return global_transform.basis.inverse() * world_delta


static func _bake_pieces(path: String) -> Array:
	if path.is_empty():
		return []
	if _PIECE_CACHE.has(path):
		return _PIECE_CACHE[path]
	var scene := _load_scene(path)
	if scene == null:
		_PIECE_CACHE[path] = []
		return []
	var frac := scene.instantiate() as Node3D
	var meshes: Array[MeshInstance3D] = []
	_collect_cell_meshes(frac, meshes)
	if meshes.is_empty():
		_collect_all_meshes(frac, meshes)
	var specs: Array = []
	for mi in meshes:
		if mi.mesh == null:
			continue
		var aabb := mi.get_aabb()
		var volume: float = maxf(aabb.size.x * aabb.size.y * aabb.size.z, 0.0001)
		specs.append({
			"mesh": mi.mesh,
			"xf": mi.transform,
			"size": aabb.size.clamp(Vector3(0.04, 0.04, 0.04), Vector3(4, 4, 4)),
			"center": aabb.get_center(),
			"volume": volume,
		})
	specs.sort_custom(func(a, b): return a["volume"] > b["volume"])
	frac.free()
	_PIECE_CACHE[path] = specs
	return specs


func _disable_expensive_draw(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if QualitySettings and QualitySettings.level == QualitySettings.Quality.LOW:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_disable_expensive_draw(c)


func _strip_extras(n: Node) -> void:
	var to_free: Array[Node] = []
	for c in n.find_children("*", "", true, false):
		if c is Light3D or c is Camera3D or c is AnimationPlayer:
			to_free.append(c)
	for c in to_free:
		if is_instance_valid(c):
			c.queue_free()


static func _collect_cell_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		var lname := String(n.name).to_lower()
		if lname.contains("cell"):
			out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_cell_meshes(c, out)


static func _collect_all_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_all_meshes(c, out)


static func _load_scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _SCENE_CACHE.has(path):
		return _SCENE_CACHE[path]
	if not ResourceLoader.exists(path):
		push_warning("ShatterableProp: missing %s" % path)
		return null
	var res := load(path)
	if res is PackedScene:
		_SCENE_CACHE[path] = res
		return res
	return null
