extends Node
class_name DoomLevel
## Loads the imported Quake BSP (`basetohell.bsp`) and extracts spawn/thing data.

const LEVELS_DIR := "res://assets/levels"
const UNIT_SCALE := 1.0 / 32.0

const MONSTER_PREFIXES := [
	"monster_",
]
const AMMO_CLASSES := {
	"item_shells": true,
	"item_spikes": true,
	"item_rockets": true,
	"item_cells": true,
	"item_weapon": true,
	"weapon_supershotgun": true,
	"weapon_nailgun": true,
	"weapon_supernailgun": true,
	"weapon_grenadelauncher": true,
	"weapon_rocketlauncher": true,
	"weapon_lightning": true,
}
const HEALTH_CLASSES := {
	"item_health": true,
	"item_armor1": true,
	"item_armor2": true,
	"item_armorInv": true,
}
const KEY_CLASSES := {
	"item_key1": "Silver key",
	"item_key2": "Gold key",
	"item_sigil": "Sigil",
}

var map_node: Node3D
var spawn_pos := Vector3(0, 1, 0)
var enemy_spawns: Array[Vector3] = []
var pickup_spawns: Array = []
var map_names: Array[String] = []
var current_map_name: String = ""
var _host: Node
var _entities: Array[Dictionary] = []


func setup(host: Node) -> void:
	_host = host
	_scan_maps()


func _scan_maps() -> void:
	map_names.clear()
	var dir := DirAccess.open(LEVELS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension().to_lower() == "bsp":
			map_names.append(fname.get_basename())
		fname = dir.get_next()
	dir.list_dir_end()
	map_names.sort()
	if map_names.is_empty():
		map_names.append("basetohell")


func _bsp_path(map_name: String) -> String:
	return "%s/%s.bsp" % [LEVELS_DIR, map_name]


func _instantiate_bsp(scene_path: String) -> Node3D:
	var res = load(scene_path)
	if res is PackedScene:
		return (res as PackedScene).instantiate() as Node3D
	return _read_bsp_runtime(scene_path)


func _read_bsp_runtime(scene_path: String) -> Node3D:
	var reader := BSPReader.new()
	reader.unit_scale = UNIT_SCALE
	reader.import_lights = false
	reader.generate_occlusion_culling = false
	reader.generate_shadow_mesh = false
	reader.generate_lightmap_uv2 = false
	reader.use_triangle_collision = true
	reader.ignore_missing_entities = true
	reader.save_separate_materials = false
	reader.generate_texture_materials = true
	reader.overwrite_existing_materials = false
	reader.overwrite_existing_textures = false
	reader.include_sky_surfaces = true
	reader.material_path_pattern = "res://materials/{texture_name}_material.tres"
	reader.texture_path_pattern = "res://textures/{texture_name}.png"
	reader.texture_emission_path_pattern = "res://textures/{texture_name}_emission.png"
	reader.texture_palette_path = "res://textures/palette.lmp"
	reader.transparent_texture_prefix = "{"
	reader.entity_path_pattern = "res://entities/{classname}.tscn"
	reader.entity_remap = {
		&"func_door": preload("res://entities/brush_entity.tscn"),
		&"func_door_secret": preload("res://entities/brush_entity.tscn"),
		&"func_plat": preload("res://entities/brush_entity.tscn"),
		&"func_button": preload("res://entities/brush_entity.tscn"),
		&"func_wall": preload("res://entities/brush_entity.tscn"),
		&"func_illusionary": preload("res://entities/brush_entity.tscn"),
		&"func_train": preload("res://entities/brush_entity.tscn"),
		&"func_episodegate": preload("res://entities/brush_entity.tscn"),
		&"func_bossgate": preload("res://entities/brush_entity.tscn"),
		&"trigger_once": preload("res://entities/brush_entity.tscn"),
		&"trigger_multiple": preload("res://entities/brush_entity.tscn"),
		&"trigger_teleport": preload("res://entities/brush_entity.tscn"),
		&"trigger_changelevel": preload("res://entities/brush_entity.tscn"),
		&"trigger_hurt": preload("res://entities/brush_entity.tscn"),
		&"trigger_secret": preload("res://entities/brush_entity.tscn"),
	}
	reader.water_template = load("res://addons/bsp_importer/examples/water_example_template.tscn")
	reader.slime_template = load("res://addons/bsp_importer/examples/slime_example_template.tscn")
	reader.lava_template = load("res://addons/bsp_importer/examples/lava_example_template.tscn")
	var node := reader.read_bsp(scene_path) as Node3D
	reader.free()
	return node


func map_count() -> int:
	return map_names.size()


func load_index(index: int) -> bool:
	index = clampi(index, 0, maxi(0, map_names.size() - 1))
	return load_map(map_names[index] if map_names.size() > 0 else "basetohell")


func load_map(map_name: String) -> bool:
	_free_previous_maps()
	enemy_spawns.clear()
	pickup_spawns.clear()
	current_map_name = map_name
	var scene_path := _bsp_path(map_name)
	if not FileAccess.file_exists(scene_path) and not ResourceLoader.exists(scene_path):
		push_error("[DoomLevel] Missing BSP %s" % scene_path)
		return false
	map_node = _instantiate_bsp(scene_path)
	if map_node == null:
		push_error("[DoomLevel] Failed to load %s" % scene_path)
		return false
	map_node.name = "BspLevel"
	map_node.set_meta("map", current_map_name)
	if _host:
		_host.add_child(map_node)
	_fix_trigger_areas(map_node)
	_optimize_bsp_runtime(map_node)
	_entities = _parse_bsp_entities(scene_path)
	_extract_things()
	return true


func _optimize_bsp_runtime(root: Node) -> void:
	if root == null:
		return
	var lights: Array[Node] = root.find_children("*", "Light3D", true, false)
	var keep := 6 if QualitySettings == null or QualitySettings.level != QualitySettings.Quality.LOW else 0
	var i := 0
	for n in lights:
		var light := n as Light3D
		light.shadow_enabled = false
		if i >= keep:
			light.visible = false
			light.queue_free()
		else:
			if light is OmniLight3D:
				(light as OmniLight3D).omni_range = minf((light as OmniLight3D).omni_range, 8.0)
			light.light_energy = minf(light.light_energy, 0.35)
		i += 1
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for n in root.find_children("*", "OccluderInstance3D", true, false):
		(n as OccluderInstance3D).visible = QualitySettings != null and QualitySettings.level == QualitySettings.Quality.HIGH


func finalize_after_physics() -> void:
	## Collision is not queryable the same frame the BSP is added.
	if _host and _host.is_inside_tree():
		await _host.get_tree().physics_frame
		await _host.get_tree().physics_frame
	_snap_spawns_to_floor()
	_ensure_ammo_pickups()
	_ensure_easy_health()
	var ammo_n := 0
	for item in pickup_spawns:
		if item.get("type", "") == "ammo":
			ammo_n += 1
	print("[DoomLevel] loaded ", current_map_name, " spawn=", spawn_pos, " enemies=", enemy_spawns.size(), " ammo=", ammo_n)


func _free_previous_maps() -> void:
	if map_node and is_instance_valid(map_node):
		map_node.queue_free()
	if _host == null:
		return
	for c in _host.get_children():
		if c.has_meta("map") or String(c.name) == "BspLevel":
			if c != map_node:
				c.queue_free()
	map_node = null


func _fix_trigger_areas(root: Node) -> void:
	if root == null:
		return
	for n in root.find_children("*", "Area3D", true, false):
		var area := n as Area3D
		area.collision_mask |= 1 | 2
		area.monitoring = true


func _extract_things() -> void:
	var found_player := false
	var dm_fallback := Vector3.ZERO
	var found_dm := false
	for t in _entities:
		var classname := String(t.get("classname", "")).to_lower()
		if classname.is_empty():
			continue
		if not _thing_matches_difficulty(t):
			continue
		var pos := _entity_origin(t)
		if classname == "info_player_start":
			spawn_pos = pos
			found_player = true
		elif classname == "info_player_deathmatch":
			dm_fallback = pos
			found_dm = true
		elif _is_monster(classname):
			enemy_spawns.append(pos)
		elif HEALTH_CLASSES.has(classname):
			pickup_spawns.append({"pos": pos, "type": "health"})
		elif AMMO_CLASSES.has(classname) or classname.begins_with("weapon_"):
			pickup_spawns.append({"pos": pos, "type": "ammo"})
		elif KEY_CLASSES.has(classname):
			pickup_spawns.append({"pos": pos, "type": "key", "key_name": KEY_CLASSES[classname]})
	if not found_player:
		spawn_pos = dm_fallback if found_dm else Vector3(0, 2, 0)


func _is_monster(classname: String) -> bool:
	for p in MONSTER_PREFIXES:
		if classname.begins_with(p):
			return true
	return false


func _entity_origin(t: Dictionary) -> Vector3:
	var origin_s := String(t.get("origin", "0 0 0"))
	return BSPReader.string_to_origin(origin_s, UNIT_SCALE)


func _ensure_ammo_pickups() -> void:
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
	var flags: int = int(String(t.get("spawnflags", "0")).to_int())
	# Quake: 256 not easy, 512 not medium, 1024 not hard, 2048 not deathmatch
	if GameState == null:
		return (flags & 256) == 0
	match GameState.difficulty:
		GameState.Difficulty.EASY:
			return (flags & 256) == 0
		GameState.Difficulty.NORMAL:
			return (flags & 512) == 0
		_:
			return (flags & 1024) == 0


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
	## Start just above the Quake origin so we do not land on the world roof.
	var y := find_walkable_y(space, pos, pos.y + 1.8, pos.y - 20.0, [])
	if is_nan(y):
		return pos
	if y > pos.y + 2.5:
		return pos
	return Vector3(pos.x, y, pos.z)


func _parse_bsp_entities(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		push_warning("[DoomLevel] BSP file missing: %s" % path)
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	f.big_endian = false
	var version := f.get_32()
	# Quake BSP v29 lumps: 15 * {offset, length}; entity lump is 0
	if version != 29 and version != 30:
		# Still try lump 0 — Quake / Half-Life style
		pass
	var ent_off := f.get_32()
	var ent_len := f.get_32()
	if ent_len <= 0 or ent_off < 0:
		return out
	f.seek(ent_off)
	var raw := f.get_buffer(ent_len).get_string_from_ascii()
	var current: Dictionary = {}
	var in_ent := false
	for line in raw.split("\n"):
		var s := line.strip_edges()
		if s == "{":
			current = {}
			in_ent = true
			continue
		if s == "}":
			if in_ent and not current.is_empty():
				out.append(current)
			in_ent = false
			continue
		if not in_ent:
			continue
		# "key" "value"
		var first := s.find("\"")
		if first < 0:
			continue
		var second := s.find("\"", first + 1)
		if second < 0:
			continue
		var third := s.find("\"", second + 1)
		if third < 0:
			continue
		var fourth := s.find("\"", third + 1)
		if fourth < 0:
			continue
		var key := s.substr(first + 1, second - first - 1)
		var val := s.substr(third + 1, fourth - third - 1)
		current[key] = val
	return out


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
