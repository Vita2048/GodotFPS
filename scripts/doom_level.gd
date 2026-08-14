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
## Clips, shells, cells, rockets, backpacks, and weapons (give ammo).
const KEY_TYPES := {
	5: "Blue keycard",
	6: "Yellow keycard",
	13: "Red keycard",
	38: "Red skull key",
	39: "Yellow skull key",
	40: "Blue skull key",
}
const AMMO_TYPES := {
	8: true, 17: true, 2001: true, 2002: true, 2003: true, 2004: true, 2006: true,
	2007: true, 2008: true, 2010: true, 2046: true, 2047: true, 2048: true, 2049: true,
}

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
	loader.textureFiltering = true
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
	_fix_trigger_areas(map_node)
	_quiet_platform_audio(map_node)
	_extract_things(map_name)
	_snap_spawns_to_floor()
	_ensure_ammo_pickups()
	_ensure_easy_health()
	var ammo_n := 0
	for item in pickup_spawns:
		if item.get("type", "") == "ammo":
			ammo_n += 1
	print("[DoomLevel] loaded ", map_name, " spawn=", spawn_pos, " enemies=", enemy_spawns.size(), " ammo=", ammo_n)
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


func _fix_trigger_areas(root: Node) -> void:
	## Importer Area3Ds default to mask layer 1; our player also lives on layer 2.
	if root == null:
		return
	for n in root.find_children("*", "Area3D", true, false):
		var area := n as Area3D
		area.collision_mask |= 1 | 2
		area.monitoring = true


func _quiet_platform_audio(root: Node) -> void:
	if root == null:
		return
	for n in root.find_children("*", "AudioStreamPlayer3D", true, false):
		var p := n as AudioStreamPlayer3D
		var key := (String(p.name) + " " + (p.stream.resource_name if p.stream else "")).to_upper()
		if "STNMOV" in key or "PSTART" in key or "PSTOP" in key or p.name in ["openSound", "closeSound"]:
			# Lifts reuse openSound/closeSound; keep doors a bit louder.
			var parent_script := ""
			if p.get_parent() and p.get_parent().get_script():
				parent_script = String(p.get_parent().get_script().resource_path)
			if "lift" in parent_script or "floor" in parent_script or "STNMOV" in key or "PSTART" in key:
				p.volume_db = minf(p.volume_db, -22.0)
				p.max_distance = 20.0


func _extract_things(map_name: String) -> void:
	if loader == null or not ("maps" in loader):
		return
	var maps: Dictionary = loader.maps
	var key: String = map_name
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
		elif KEY_TYPES.has(typ):
			pickup_spawns.append({"pos": pos, "type": "key", "key_name": KEY_TYPES[typ]})
	if not found_player:
		spawn_pos = Vector3(0, 2, 0)


func _ensure_ammo_pickups() -> void:
	## E1M1 has few bullet clips; seed extras so the rifle doesn't run dry.
	var ammo_n := 0
	for item in pickup_spawns:
		if item.get("type", "") == "ammo":
			ammo_n += 1
	var want := maxi(8, mini(14, enemy_spawns.size() / 2 + 4))
	if ammo_n >= want:
		return
	var used: Array[Vector3] = [spawn_pos]
	for item in pickup_spawns:
		used.append(item["pos"])
	var candidates: Array[Vector3] = []
	for p in enemy_spawns:
		candidates.append(p)
	# Ring around the player start
	for i in 6:
		var a := float(i) / 6.0 * TAU
		candidates.append(spawn_pos + Vector3(cos(a), 0.0, sin(a)) * 4.5)
	if _host == null or not _host.is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = _host.get_world_3d().direct_space_state
	for p in candidates:
		if ammo_n >= want:
			break
		var at := _ray_floor(space, p)
		var too_close := false
		for u in used:
			if Vector3(u.x, 0, u.z).distance_to(Vector3(at.x, 0, at.z)) < 2.2:
				too_close = true
				break
		if too_close:
			continue
		if at.distance_to(spawn_pos) < 1.6:
			continue
		pickup_spawns.append({"pos": at, "type": "ammo"})
		used.append(at)
		ammo_n += 1


func _ensure_easy_health() -> void:
	if GameState == null or GameState.difficulty != GameState.Difficulty.EASY:
		return
	var health_n := 0
	for item in pickup_spawns:
		if item.get("type", "") == "health":
			health_n += 1
	if health_n >= 4:
		return
	if _host == null or not _host.is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = _host.get_world_3d().direct_space_state
	for i in 4:
		var a := float(i) / 4.0 * TAU + 0.4
		var p := _ray_floor(space, spawn_pos + Vector3(cos(a), 0.0, sin(a)) * 3.2)
		if p.distance_to(spawn_pos) < 1.2:
			continue
		pickup_spawns.append({"pos": p, "type": "health"})
		health_n += 1
		if health_n >= 4:
			break


func _thing_matches_difficulty(t: Dictionary) -> bool:
	var flags: int = int(t.get("flags", 0))
	if (flags & 16) != 0:
		return false
	var easy := (flags & 1) != 0
	var medium := (flags & 2) != 0
	var hard := (flags & 4) != 0
	# Things with no skill bits still show in all modes.
	if not easy and not medium and not hard:
		return true
	if GameState == null:
		return easy or medium
	match GameState.difficulty:
		GameState.Difficulty.EASY:
			return easy or medium
		GameState.Difficulty.NORMAL:
			return easy or medium
		_:
			return true


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
	var y := find_walkable_y(space, pos, 80.0, -80.0, [])
	if is_nan(y):
		if pos.y < -1000.0:
			return Vector3(pos.x, 1.0, pos.z)
		return pos
	return Vector3(pos.x, y, pos.z)


static func find_walkable_y(space: PhysicsDirectSpaceState3D, pos: Vector3, start_y: float, end_y: float, extra_exclude: Array) -> float:
	## Skip ceiling / sky hits so we land on the actual sector floor (stairs included).
	var exclude: Array[RID] = []
	for item in extra_exclude:
		if item is CollisionObject3D:
			exclude.append((item as CollisionObject3D).get_rid())
		elif item is RID:
			exclude.append(item)
	for _i in 16:
		var from := Vector3(pos.x, start_y, pos.z)
		var to := Vector3(pos.x, end_y, pos.z)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		var col: Object = hit.get("collider")
		if col is CollisionObject3D:
			exclude.append((col as CollisionObject3D).get_rid())
		if _is_non_walkable_surface(col, hit.get("normal", Vector3.UP)):
			if col is Node:
				var n := col as Node
				if n.get_parent() is CollisionObject3D:
					exclude.append(n.get_parent())
			continue
		return (hit.position as Vector3).y + 0.02
	return NAN


static func _is_non_walkable_surface(col: Object, normal: Vector3) -> bool:
	if normal.y < 0.25:
		return true
	var n: Node = col as Node
	var hops := 0
	while n != null and hops < 6:
		var nm := String(n.name).to_lower()
		if n.has_meta("ceil") or nm.begins_with("ceil") or "skybox" in nm or nm.begins_with("surrounding"):
			return true
		if n.has_meta("floor") or nm.begins_with("floor"):
			return false
		n = n.get_parent()
		hops += 1
	return false
