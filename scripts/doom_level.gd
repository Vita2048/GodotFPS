extends Node
class_name DoomLevel
## Runtime wrapper around GodotWadImporter: loads doom1.WAD maps into the scene.

const WAD_PATH := "res://assets/levels/doom1.WAD"
const LOADER_SCENE := "res://addons/godotWad/WAD_Loader.tscn"

const MONSTER_TYPES := {
	7: true, 9: true, 16: true, 58: true, 64: true, 65: true, 66: true,
	67: true, 68: true, 69: true, 71: true, 72: true, 84: true, 88: true,
	3001: true, 3002: true, 3003: true, 3004: true, 3005: true, 3006: true,
}
const HEALTH_TYPES := {2011: true, 2012: true, 2014: true, 83: true}
const AMMO_TYPES := {8: true, 17: true, 2007: true, 2008: true, 2010: true, 2046: true, 2047: true, 2048: true}

var loader: Node
var map_node: Node3D
var spawn_pos := Vector3(0, 1, 0)
var enemy_spawns: Array[Vector3] = []
var pickup_spawns: Array = []
var map_names: Array[String] = []
var current_map_name: String = "E1M1"
var _host: Node


func setup(host: Node) -> void:
	_host = host
	if loader != null:
		return
	var ps: PackedScene = load(LOADER_SCENE)
	if ps == null:
		push_error("[DoomLevel] Missing WAD_Loader.tscn")
		return
	loader = ps.instantiate()
	loader.name = "WadLoader"
	host.add_child(loader)
	loader.npcsDisabled = true
	loader.generateNav = 0
	loader.addOccluder = false
	loader.unwrapLightmap = false
	loader.mergeMesh = 3
	if loader.has_method("initialize"):
		loader.initialize([WAD_PATH], "Doom", "doom")
	_refresh_map_list()


func _refresh_map_list() -> void:
	map_names.clear()
	if loader == null or not ("maps" in loader):
		return
	var keys: Array = []
	for k in loader.maps.keys():
		keys.append(String(k))
	keys.sort_custom(func(a: String, b: String) -> bool:
		return _map_order(a) < _map_order(b)
	)
	for k in keys:
		map_names.append(k)


func _map_order(n: String) -> int:
	n = n.to_upper()
	if n.length() >= 4 and n[0] == "E" and n.contains("M"):
		var ep := n.substr(1, 1).to_int()
		var mp := n.get_slice("M", 1).to_int()
		return ep * 100 + mp
	if n.begins_with("MAP"):
		return 1000 + n.substr(3).to_int()
	return 9000


func map_count() -> int:
	return map_names.size()


func load_index(index: int) -> bool:
	if loader == null:
		return false
	if map_names.is_empty():
		_refresh_map_list()
	if map_names.is_empty():
		return false
	index = clampi(index, 0, map_names.size() - 1)
	return load_map(map_names[index])


func load_map(map_name: String) -> bool:
	if loader == null:
		return false
	_free_previous_maps()
	enemy_spawns.clear()
	pickup_spawns.clear()
	current_map_name = map_name
	var created: Node = loader.createMap(map_name, {"blankMap": true, "reloadWads": false})
	if created == null:
		push_warning("[DoomLevel] createMap failed for %s" % map_name)
		return false
	map_node = created as Node3D
	_extract_things(map_name)
	_snap_spawns_to_floor()
	print("[DoomLevel] loaded ", map_name, " spawn=", spawn_pos, " enemies=", enemy_spawns.size())
	return true


func _free_previous_maps() -> void:
	if _host == null:
		return
	for c in _host.get_children():
		if c == loader:
			continue
		if c.has_meta("map") or (c.get_script() != null and String(c.get_script().resource_path).ends_with("levelNode.gd")):
			c.queue_free()
	map_node = null


func _extract_things(map_name: String) -> void:
	if loader == null or not ("maps" in loader):
		return
	var maps: Dictionary = loader.maps
	var key := map_name
	if not maps.has(key):
		for k in maps.keys():
			if String(k).to_upper() == map_name.to_upper():
				key = k
				break
	if not maps.has(key):
		return
	var things: Array = maps[key].get("thingsParsed", [])
	var found_player := false
	for thing in things:
		if typeof(thing) != TYPE_DICTIONARY:
			continue
		var t: Dictionary = thing
		if not _thing_matches_difficulty(t):
			continue
		var typ: int = int(t.get("type", 0))
		var pos: Vector3 = t.get("pos", Vector3.ZERO)
		if typ == 1:
			spawn_pos = pos
			found_player = true
		elif MONSTER_TYPES.has(typ):
			enemy_spawns.append(pos)
		elif HEALTH_TYPES.has(typ):
			pickup_spawns.append({"pos": pos, "type": "health"})
		elif AMMO_TYPES.has(typ):
			pickup_spawns.append({"pos": pos, "type": "ammo"})
	if not found_player:
		spawn_pos = Vector3(0, 2, 0)


func _thing_matches_difficulty(t: Dictionary) -> bool:
	var flags: int = int(t.get("flags", 0))
	var easy := (flags & 1) != 0
	var medium := (flags & 2) != 0
	var hard := (flags & 4) != 0
	if GameState == null:
		return easy or medium
	match GameState.difficulty:
		GameState.Difficulty.EASY:
			return easy
		GameState.Difficulty.NORMAL:
			return medium or easy
		_:
			return hard or medium or easy


func _snap_spawns_to_floor() -> void:
	if _host == null or not _host.is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = _host.get_world_3d().direct_space_state
	spawn_pos = _ray_floor(space, spawn_pos)
	for i in enemy_spawns.size():
		enemy_spawns[i] = _ray_floor(space, enemy_spawns[i])
	for item in pickup_spawns:
		item["pos"] = _ray_floor(space, item["pos"])


func _ray_floor(space: PhysicsDirectSpaceState3D, pos: Vector3) -> Vector3:
	var from := Vector3(pos.x, 80.0, pos.z)
	var to := Vector3(pos.x, -80.0, pos.z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		if pos.y < -1000.0:
			return Vector3(pos.x, 1.0, pos.z)
		return pos
	return hit.position + Vector3(0, 0.05, 0)
