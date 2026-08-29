extends Node3D
class_name ShatterableProp
## Intact furniture that shatters into cheap box-collider debris.

const DEBRIS_LAYER := 8
const FREEZE_AFTER := 1.15

static var _SCENE_CACHE: Dictionary = {}
static var _PIECE_CACHE: Dictionary = {} # fractured_path -> Array[Dictionary]

@export_file("*.glb") var intact_path: String = ""
@export_file("*.glb") var fractured_path: String = ""
@export var piece_mass: float = 1.2
@export var impulse_strength: float = 9.5
@export var debris_lifetime: float = 8.0
@export var max_phys_pieces: int = 20
@export var fit_width: float = 0.0

var _shattered: bool = false
var _loose: bool = false
var _visual_offset: Vector3 = Vector3.ZERO
var _intact_root: Node3D
var _hit_body: StaticBody3D
var _loose_body: RigidBody3D
var _resting: Array = []


func setup(intact: String, fractured: String, mass: float = 1.2, pieces: int = 20, width: float = 0.0) -> void:
	intact_path = intact
	fractured_path = fractured
	piece_mass = mass
	max_phys_pieces = pieces
	fit_width = width


func register_resting(prop: Node) -> void:
	if prop:
		_resting.append(prop)


func _ready() -> void:
	add_to_group("shatterable")
	_spawn_intact()
	# Bake piece templates during load, not on the shot frame.
	_bake_pieces(fractured_path)


func shatter(hit_pos: Vector3, hit_normal: Vector3) -> void:
	if _shattered:
		return
	_shattered = true
	_drop_resting(hit_pos, hit_normal)
	var model_xf := global_transform * Transform3D(Basis(), _visual_offset)
	if is_instance_valid(_intact_root):
		model_xf = _intact_root.global_transform
	if is_instance_valid(_hit_body):
		_hit_body.queue_free()
		_hit_body = null
	if is_instance_valid(_intact_root):
		_intact_root.queue_free()
		_intact_root = null
	if is_instance_valid(_loose_body):
		_loose_body.queue_free()
		_loose_body = null
	_spawn_debris(hit_pos, hit_normal, model_xf)
	SFX.play_3d(get_parent(), "wood_break", hit_pos, -4.0)


func drop_from_support(hit_pos: Vector3, hit_normal: Vector3) -> void:
	if _shattered or _loose:
		return
	_loose = true
	if is_instance_valid(_hit_body):
		_hit_body.queue_free()
		_hit_body = null
	if not is_instance_valid(_intact_root):
		return

	var aabb := _world_aabb(_intact_root)
	var model_gxf := _intact_root.global_transform
	_loose_body = RigidBody3D.new()
	_loose_body.mass = maxf(piece_mass, 0.4)
	# Layer 1 so the player's shoot ray still hits it after it falls.
	_loose_body.collision_layer = 1
	_loose_body.collision_mask = 1
	_loose_body.can_sleep = true
	_loose_body.linear_damp = 0.4
	_loose_body.angular_damp = 0.6
	# Independent of this node's scale — RigidBody3D ignores scaled parents.
	_loose_body.top_level = true
	add_child(_loose_body)
	var center := aabb.get_center() if aabb.size != Vector3.ZERO else global_position
	_loose_body.global_transform = Transform3D(global_transform.basis.orthonormalized(), center)

	var from := _intact_root.get_parent()
	if from:
		from.remove_child(_intact_root)
	_loose_body.add_child(_intact_root)
	_intact_root.global_transform = model_gxf

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size.clamp(Vector3(0.05, 0.02, 0.05), Vector3(4, 4, 4))
	col.shape = box
	_loose_body.add_child(col)

	var nrm := hit_normal.normalized() if hit_normal.length_squared() > 0.01 else Vector3.UP
	var away := (_loose_body.global_position - hit_pos)
	if away.length_squared() < 0.0004:
		away = nrm
	away = away.normalized()
	_loose_body.apply_central_impulse(away * 2.4 + Vector3.UP * 1.1 + nrm * 0.8)
	_loose_body.apply_torque_impulse(away.cross(Vector3.UP) * 0.35)
	get_tree().create_timer(2.8).timeout.connect(func():
		if is_instance_valid(_loose_body) and not _shattered:
			_loose_body.freeze = true
			_loose_body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	)


func _drop_resting(hit_pos: Vector3, hit_normal: Vector3) -> void:
	for n in _resting:
		if n and is_instance_valid(n) and n.has_method("drop_from_support"):
			n.drop_from_support(hit_pos, hit_normal)
	_resting.clear()


func _spawn_intact() -> void:
	var scene := _load_scene(intact_path)
	if scene == null:
		return
	_intact_root = scene.instantiate() as Node3D
	add_child(_intact_root)
	_strip_extras(_intact_root)
	_apply_fit_width()
	_visual_offset = _ground_center_offset(_intact_root)
	_intact_root.position += _visual_offset
	_disable_expensive_draw(_intact_root)
	_add_aabb_collision(_intact_root)


func _spawn_debris(hit_pos: Vector3, hit_normal: Vector3, model_xf: Transform3D) -> void:
	var pieces: Array = _bake_pieces(fractured_path)
	if pieces.is_empty():
		return

	var debris := Node3D.new()
	debris.name = "Debris"
	add_child(debris)

	var n := mini(pieces.size(), max_phys_pieces)
	var nrm := hit_normal.normalized() if hit_normal.length_squared() > 0.01 else Vector3.UP

	for i in n:
		var spec: Dictionary = pieces[i]

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
		rb.global_transform = model_xf * spec["xf"]

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


func _apply_fit_width() -> void:
	if fit_width <= 0.0 or _intact_root == null:
		return
	var aabb := _world_aabb(_intact_root)
	var horiz := maxf(aabb.size.x, aabb.size.z)
	if horiz < 0.0001:
		return
	# Scale the mesh root, not this node — physics bodies drop parent scale.
	_intact_root.scale *= fit_width / horiz


func _world_aabb(root: Node3D) -> AABB:
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
	return aabb


func _add_aabb_collision(root: Node3D) -> void:
	var aabb := _world_aabb(root)
	if aabb.size == Vector3.ZERO:
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
	var aabb := _world_aabb(root)
	if aabb.size == Vector3.ZERO:
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
			"xf": _xform_relative(mi, frac),
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


static func _xform_relative(n: Node3D, root: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


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
