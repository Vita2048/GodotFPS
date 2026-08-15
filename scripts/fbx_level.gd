extends Node3D
## Instantiates assets/levels/Level.fbx (Duke Nukem 3D E1L2) as the playable map.

const LEVEL_PATH := "res://assets/levels/Level.fbx"
const FLOOR_NORMAL_Y := 0.62
const BUCKET := 0.45
const MIN_FLOOR_AREA := 0.8
const ROOM_MIN := 2.6
const ROOM_MAX := 6.0
const SPAWN_LIFT := 0.4

var map_node: Node3D
var spawn_pos := Vector3(0, 1.2, 0)
var enemy_spawns: Array[Vector3] = []
var pickup_spawns: Array = []
var map_names: Array[String] = ["E1L2"]
var current_map_name: String = "E1L2"

var _aabb := AABB()
var _floors: Array[Dictionary] = [] # {pos: Vector3, area: float}
var _ceilings: Array[Dictionary] = [] # {a,b,c: Vector3}


func setup(parent: Node) -> void:
	if parent and get_parent() != parent:
		parent.add_child(self)


func map_count() -> int:
	return 1


func load_index(_index: int) -> bool:
	return load_map("E1L2")


func load_map(_map_name: String) -> bool:
	_free_previous()
	if not ResourceLoader.exists(LEVEL_PATH):
		push_warning("[FbxLevel] missing %s" % LEVEL_PATH)
		return false
	var packed: PackedScene = load(LEVEL_PATH) as PackedScene
	if packed == null:
		return false
	var inst := packed.instantiate()
	if inst == null:
		return false
	map_node = inst as Node3D
	if map_node == null:
		map_node = Node3D.new()
		map_node.add_child(inst)
	map_node.name = "LevelFBX"
	add_child(map_node)

	_disable_imported_cameras_and_lights(map_node)
	var mi := _find_mesh(map_node)
	if mi == null or mi.mesh == null:
		push_warning("[FbxLevel] no mesh in FBX")
		return false

	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.layers = 1
	mi.visible = true
	mi.extra_cull_margin = 80.0
	mi.custom_aabb = mi.mesh.get_aabb()
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		if mat is BaseMaterial3D:
			var bm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			bm.cull_mode = BaseMaterial3D.CULL_DISABLED
			bm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.set_surface_override_material(s, bm)

	_aabb = _world_aabb(mi)
	var shift := Vector3(_aabb.get_center().x, _aabb.position.y, _aabb.get_center().z)
	map_node.global_position -= shift
	_aabb.position -= shift

	_add_world_collision(mi)
	_collect_floors(mi)
	_place_spawns()
	_apply_saved_player_spawn()
	current_map_name = "E1L2"
	print("[FbxLevel] AABB=", _aabb, " floors=", _floors.size(), " spawn=", spawn_pos)
	return true


func _apply_saved_player_spawn() -> void:
	if not ResourceLoader.exists("res://resources/player_spawn.tres"):
		return
	var res = load("res://resources/player_spawn.tres")
	if res == null or not res.get("enabled"):
		return
	var p: Vector3 = res.position
	if p.length_squared() < 0.0001:
		return
	spawn_pos = p
	print("[FbxLevel] using tuned spawn ", spawn_pos)


func snap_spawns_to_floor(world: World3D) -> void:
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	if not _saved_spawn_enabled():
		spawn_pos = _ray_floor(space, spawn_pos)
	for i in enemy_spawns.size():
		enemy_spawns[i] = _ray_floor(space, enemy_spawns[i])
	for item in pickup_spawns:
		item["pos"] = _ray_floor(space, item["pos"])


func _saved_spawn_enabled() -> bool:
	if not ResourceLoader.exists("res://resources/player_spawn.tres"):
		return false
	var res = load("res://resources/player_spawn.tres")
	return res != null and bool(res.get("enabled"))


func _free_previous() -> void:
	for c in get_children():
		c.queue_free()
	map_node = null
	enemy_spawns.clear()
	pickup_spawns.clear()
	_floors.clear()
	_ceilings.clear()


func _disable_imported_cameras_and_lights(n: Node) -> void:
	if n is Camera3D:
		var cam := n as Camera3D
		cam.current = false
		cam.clear_current(false)
	if n is Light3D:
		(n as Light3D).visible = false
	for c in n.get_children():
		_disable_imported_cameras_and_lights(c)


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		return n as MeshInstance3D
	for c in n.get_children():
		var found := _find_mesh(c)
		if found:
			return found
	return null


func _world_aabb(mi: MeshInstance3D) -> AABB:
	var local := mi.mesh.get_aabb()
	var xf := mi.global_transform
	var out := AABB(xf * local.position, Vector3.ZERO)
	for i in 8:
		var corner := local.position + Vector3(
			local.size.x if (i & 1) else 0.0,
			local.size.y if (i & 2) else 0.0,
			local.size.z if (i & 4) else 0.0
		)
		out = out.expand(xf * corner)
	return out


func _add_world_collision(mi: MeshInstance3D) -> void:
	## Bake triangles into unscaled world space (one-sided).
	## Two-sided faces bury the capsule inside thick floor/wall slabs.
	var faces := PackedVector3Array()
	var mesh := mi.mesh
	var xf := mi.global_transform
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if indices.size() >= 3:
			var i := 0
			while i + 2 < indices.size():
				var a: Vector3 = xf * verts[indices[i]]
				var b: Vector3 = xf * verts[indices[i + 1]]
				var c: Vector3 = xf * verts[indices[i + 2]]
				faces.append(a)
				faces.append(b)
				faces.append(c)
				i += 3
		else:
			var i := 0
			while i + 2 < verts.size():
				var a: Vector3 = xf * verts[i]
				var b: Vector3 = xf * verts[i + 1]
				var c: Vector3 = xf * verts[i + 2]
				faces.append(a)
				faces.append(b)
				faces.append(c)
				i += 3
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = false
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "LevelCol"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _collect_floors(mi: MeshInstance3D) -> void:
	_floors.clear()
	_ceilings.clear()
	var mesh := mi.mesh
	var xf := mi.global_transform
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if indices.size() >= 3:
			var i := 0
			while i + 2 < indices.size():
				_classify_tri(xf * verts[indices[i]], xf * verts[indices[i + 1]], xf * verts[indices[i + 2]])
				i += 3
		else:
			var i := 0
			while i + 2 < verts.size():
				_classify_tri(xf * verts[i], xf * verts[i + 1], xf * verts[i + 2])
				i += 3


func _classify_tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var cr := (b - a).cross(c - a)
	var twice_area := cr.length()
	if twice_area < 0.08:
		return
	var ny := cr.y / twice_area
	if ny > FLOOR_NORMAL_Y:
		if twice_area * 0.5 >= MIN_FLOOR_AREA:
			_floors.append({"pos": (a + b + c) / 3.0, "area": twice_area * 0.5})
	elif ny < -0.45:
		_ceilings.append({"a": a, "b": b, "c": c, "y": (a.y + b.y + c.y) / 3.0})


func _place_spawns() -> void:
	var main_floors := _main_floor_level()
	if main_floors.is_empty():
		spawn_pos = Vector3(_aabb.get_center().x, _aabb.position.y + _aabb.size.y * 0.35, _aabb.get_center().z)
		return

	var centroid := Vector3.ZERO
	var area_sum := 0.0
	for f in main_floors:
		centroid += f["pos"] * f["area"]
		area_sum += f["area"]
	if area_sum > 0.0:
		centroid /= area_sum
	else:
		centroid = main_floors[0]["pos"]

	spawn_pos = _closest_floor(main_floors, centroid) + Vector3(0, SPAWN_LIFT, 0)
	var count := 5
	var used: Array[Vector3] = [spawn_pos]
	var candidates := main_floors.duplicate()
	candidates.sort_custom(func(a, b): return a["area"] > b["area"])
	for f in candidates:
		if enemy_spawns.size() >= count:
			break
		var p: Vector3 = f["pos"]
		var far_enough := true
		for u in used:
			if Vector2(p.x - u.x, p.z - u.z).length() < 4.0:
				far_enough = false
				break
		if not far_enough:
			continue
		enemy_spawns.append(p + Vector3(0, SPAWN_LIFT, 0))
		used.append(p)
	while enemy_spawns.size() < count and candidates.size() > 0:
		var p2: Vector3 = candidates[enemy_spawns.size() % candidates.size()]["pos"]
		enemy_spawns.append(p2 + Vector3(0, SPAWN_LIFT, 0))

	pickup_spawns.append({"type": "ammo", "pos": _closest_floor(main_floors, spawn_pos + Vector3(2.0, 0, 0)) + Vector3(0, 0.2, 0)})
	pickup_spawns.append({"type": "health", "pos": _closest_floor(main_floors, spawn_pos + Vector3(-2.0, 0, 1.5)) + Vector3(0, 0.2, 0)})


func _roof_y() -> float:
	return _aabb.position.y + _aabb.size.y - 1.4


func _has_ceiling_above(pos: Vector3) -> bool:
	for ceil in _ceilings:
		var cy: float = ceil["y"]
		if cy < pos.y + ROOM_MIN or cy > pos.y + ROOM_MAX:
			continue
		if _point_in_tri_xz(pos, ceil["a"], ceil["b"], ceil["c"]):
			return true
	return false


func _point_in_tri_xz(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var v0 := Vector2(c.x - a.x, c.z - a.z)
	var v1 := Vector2(b.x - a.x, b.z - a.z)
	var v2 := Vector2(p.x - a.x, p.z - a.z)
	var dot00 := v0.dot(v0)
	var dot01 := v0.dot(v1)
	var dot02 := v0.dot(v2)
	var dot11 := v1.dot(v1)
	var dot12 := v1.dot(v2)
	var denom := dot00 * dot11 - dot01 * dot01
	if absf(denom) < 0.000001:
		return false
	var u := (dot11 * dot02 - dot01 * dot12) / denom
	var v := (dot00 * dot12 - dot01 * dot02) / denom
	return u >= -0.02 and v >= -0.02 and (u + v) <= 1.02


func _main_floor_level() -> Array:
	if _floors.is_empty():
		return []
	var roof := _roof_y()
	var indoor: Array = []
	for f in _floors:
		var p: Vector3 = f["pos"]
		if p.y >= roof:
			continue
		if _has_ceiling_above(p):
			indoor.append(f)
	var use: Array = indoor
	if use.is_empty():
		for f in _floors:
			var p: Vector3 = f["pos"]
			if p.y < roof and f["area"] >= 2.0:
				use.append(f)
	if use.is_empty():
		use = _floors
	var buckets: Dictionary = {}
	for f in use:
		var y: float = f["pos"].y
		var key := int(floor(y / BUCKET))
		if not buckets.has(key):
			buckets[key] = {"area": 0.0, "items": []}
		buckets[key]["area"] += f["area"]
		buckets[key]["items"].append(f)
	var best_key := 0
	var best_area := -1.0
	for k in buckets.keys():
		var a: float = buckets[k]["area"]
		if a > best_area:
			best_area = a
			best_key = int(k)
	return buckets[best_key]["items"]


func _closest_floor(floors: Array, guess: Vector3) -> Vector3:
	var best: Vector3 = floors[0]["pos"]
	var best_d := INF
	for f in floors:
		var p: Vector3 = f["pos"]
		var d := Vector2(p.x - guess.x, p.z - guess.z).length_squared()
		if d < best_d:
			best_d = d
			best = p
	return best


func _has_physics_ceiling(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.25, 0), pos + Vector3(0, 6.5, 0))
	q.collision_mask = 1
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var nrm: Vector3 = hit.get("normal", Vector3.DOWN)
	return nrm.y < -0.25 or (hit.position as Vector3).y > pos.y + 1.2


func _ray_floor(space: PhysicsDirectSpaceState3D, guess: Vector3) -> Vector3:
	var roof := _roof_y()
	var start_y := minf(guess.y + 2.2, roof - 0.15)
	if start_y < guess.y + 0.4:
		start_y = guess.y + 2.2
	var to := Vector3(guess.x, _aabb.position.y - 2.0, guess.z)
	var from := Vector3(guess.x, start_y, guess.z)
	var exclude: Array[RID] = []
	var fallback: Vector3 = guess
	for _i in 14:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.collide_with_areas = false
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var pos: Vector3 = hit.position
		var nrm: Vector3 = hit.get("normal", Vector3.UP)
		var col: Object = hit.get("collider")
		if col is CollisionObject3D:
			exclude.append((col as CollisionObject3D).get_rid())
		from = pos + Vector3(0, -0.04, 0)
		if nrm.y < 0.45:
			continue
		if pos.y >= roof:
			continue
		if _has_physics_ceiling(space, pos):
			return pos + Vector3(0, SPAWN_LIFT, 0)
		fallback = pos
	if fallback.y < roof:
		return fallback + Vector3(0, SPAWN_LIFT, 0)
	return guess + Vector3(0, SPAWN_LIFT, 0)
