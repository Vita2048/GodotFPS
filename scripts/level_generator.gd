extends Node3D
class_name LevelGenerator
## Procedural multi-room dungeon with PBR materials, trim, lights, and props.

signal generation_finished(spawn_pos: Vector3, enemy_spawns: Array[Vector3], pickup_spawns: Array)

const CELL := 4.0
const STORY_H := 3.2
const WALL_H := 6.4 ## two full storeys
const FLOOR2_Y := 3.2
const TILE_EMPTY := 0
const TILE_WALL := 1
const TILE_DOOR := 2
const TILE_PILLAR := 3
const TILE_STAIR := 4
const TILE_FLOOR2 := 5
const TILE_VOID := 6
const TILE_LOFT := 5 ## alias kept for older spawn checks

@export var rooms_count: int = 12
@export var map_width: int = 40
@export var map_height: int = 40
@export var seed_value: int = 0
## Huge FPS win: one floor/ceiling, no trims/beads, few lights, no shadows.
@export var performance_mode: bool = true
## Visual theme: 1 = cool concrete, 2 = warm industrial
var sector_theme: int = 1

var grid: Array = [] # 2D ints
var rooms: Array = []
var doors: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _mats: Dictionary = {}
var _enemy_spawns: Array[Vector3] = []
var _pickup_spawns: Array = []
var _spawn_pos := Vector3(CELL * 1.5, 0.0, CELL * 1.5)


func configure_for_sector(sector: int) -> void:
	## Two distinct larger layouts (called before generate).
	sector_theme = sector
	match sector:
		1:
			# Sector Alpha — sprawling facility
			rooms_count = 12
			map_width = 40
			map_height = 40
			seed_value = int(Time.get_unix_time_from_system()) ^ 0xA11A
		2:
			# Sector Beta — larger, denser complex
			rooms_count = 16
			map_width = 48
			map_height = 48
			seed_value = int(Time.get_unix_time_from_system()) ^ 0xBE7A
		_:
			rooms_count = 10
			map_width = 36
			map_height = 36
			seed_value = int(Time.get_unix_time_from_system())


func generate(seed_override: int = -1) -> void:
	for c in get_children():
		c.queue_free()
	doors.clear()
	_enemy_spawns.clear()
	_pickup_spawns.clear()

	if seed_override >= 0:
		seed_value = seed_override
	elif seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system())
	_rng.seed = seed_value

	_build_materials()
	_carve_rooms()
	_build_geometry()
	_place_lights()
	_place_props()
	_place_spawns()
	_add_mountains()
	generation_finished.emit(_spawn_pos, _enemy_spawns, _pickup_spawns)


func _build_materials() -> void:
	var brick_diff := ProceduralTextures.load_or_procedural(
		"res://assets/textures/brick_diff.jpg",
		func(): return ProceduralTextures.brick_albedo()
	)
	var brick_nor := _try_load("res://assets/textures/brick_nor.jpg")
	var brick_rough := _try_load("res://assets/textures/brick_rough.jpg")

	var concrete_diff := ProceduralTextures.load_or_procedural(
		"res://assets/textures/concrete_diff.jpg",
		func(): return ProceduralTextures.concrete_albedo()
	)
	var concrete_nor := _try_load("res://assets/textures/concrete_nor.jpg")
	var concrete_rough := _try_load("res://assets/textures/concrete_rough.jpg")

	var metal_diff := ProceduralTextures.load_or_procedural(
		"res://assets/textures/metal_diff.jpg",
		func(): return ProceduralTextures.metal_panel_albedo()
	)
	var metal_nor := _try_load("res://assets/textures/metal_nor.jpg")
	var metal_rough := _try_load("res://assets/textures/metal_rough.jpg")

	var wood_diff := ProceduralTextures.load_or_procedural(
		"res://assets/textures/wood_diff.jpg",
		func(): return ProceduralTextures.wood_albedo()
	)
	var wood_nor := _try_load("res://assets/textures/wood_nor.jpg")
	var wood_rough := _try_load("res://assets/textures/wood_rough.jpg")

	_mats["brick"] = _pbr(brick_diff, brick_nor, brick_rough, 0.9, 0.0, 1.2)
	_mats["concrete"] = _pbr(concrete_diff, concrete_nor, concrete_rough, 0.92, 0.0, 2.0)
	_mats["metal"] = _pbr(metal_diff, metal_nor, metal_rough, 0.45, 0.85, 1.5)
	_mats["wood"] = _pbr(wood_diff, wood_nor, wood_rough, 0.75, 0.0, 1.5)
	_mats["trim"] = _pbr(metal_diff, metal_nor, metal_rough, 0.35, 0.9, 4.0)
	_mats["warning"] = ProceduralTextures.make_standard_material(
		ProceduralTextures.warning_stripes(), 0.7, 0.0, 1.0
	)
	_mats["emissive"] = StandardMaterial3D.new()
	_mats["emissive"].albedo_color = Color(0.3, 0.7, 1.0)
	_mats["emissive"].emission_enabled = true
	_mats["emissive"].emission = Color(0.4, 0.85, 1.0)
	_mats["emissive"].emission_energy_multiplier = 2.5
	_mats["emissive"].albedo_texture = ProceduralTextures.emissive_strip()

	_mats["glass"] = StandardMaterial3D.new()
	_mats["glass"].albedo_color = Color(0.55, 0.72, 0.85, 0.18)
	_mats["glass"].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats["glass"].metallic = 0.05
	_mats["glass"].roughness = 0.06
	_mats["glass"].cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"].emission_enabled = true
	_mats["glass"].emission = Color(0.45, 0.6, 0.75)
	_mats["glass"].emission_energy_multiplier = 0.12

	_mats["plastic"] = StandardMaterial3D.new()
	_mats["plastic"].albedo_color = Color(0.18, 0.2, 0.22)
	_mats["plastic"].roughness = 0.45
	_mats["plastic"].metallic = 0.05

	_mats["fabric"] = StandardMaterial3D.new()
	_mats["fabric"].albedo_color = Color(0.22, 0.18, 0.16)
	_mats["fabric"].roughness = 0.88

	# Accent wall variant (cooler blue-gray concrete)
	var accent := (_mats["concrete"] as StandardMaterial3D).duplicate() as StandardMaterial3D
	accent.albedo_color = Color(0.75, 0.82, 0.95)
	_mats["accent"] = accent


func _try_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t := load(path)
		if t is Texture2D:
			return t as Texture2D
	return null


func _pbr(albedo: Texture2D, normal: Texture2D, rough: Texture2D, roughness: float, metallic: float, uv: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	if normal:
		m.normal_enabled = true
		m.normal_texture = normal
		m.normal_scale = 1.0
	if rough:
		m.roughness_texture = rough
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_scale = Vector3(uv, uv, uv)
	# Linear mipmaps without heavy anisotropic filtering (cheaper on weak GPUs)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.ao_enabled = false
	return m


func _carve_rooms() -> void:
	grid.clear()
	for z in map_height:
		var row: Array = []
		row.resize(map_width)
		row.fill(TILE_WALL)
		grid.append(row)

	rooms.clear()
	# Larger start room on bigger maps
	var start_sz := 6
	var start := Rect2i(2, 2, start_sz, start_sz)
	rooms.append(start)
	_carve_rect(start, TILE_EMPTY)

	var attempts := 0
	var max_attempts := rooms_count * 40
	while rooms.size() < rooms_count and attempts < max_attempts:
		attempts += 1
		var w := _rng.randi_range(6, 12)
		var h := _rng.randi_range(6, 12)
		var x := _rng.randi_range(1, map_width - w - 2)
		var z := _rng.randi_range(1, map_height - h - 2)
		var candidate := Rect2i(x, z, w, h)
		var padded := Rect2i(x - 1, z - 1, w + 2, h + 2)
		var ok := true
		for r in rooms:
			if padded.intersects(r as Rect2i):
				ok = false
				break
		if not ok:
			continue
		_carve_rect(candidate, TILE_EMPTY)
		var closest: Rect2i = rooms[0]
		var best_d := 999999
		var c_center := candidate.get_center()
		for r in rooms:
			var rc: Rect2i = r
			var d: int = absi(rc.get_center().x - c_center.x) + absi(rc.get_center().y - c_center.y)
			if d < best_d:
				best_d = d
				closest = rc
		_carve_corridor(closest.get_center(), c_center)
		rooms.append(candidate)

	# Always have at least one room east of start so the first door goes somewhere
	if rooms.size() < 3:
		var extra := Rect2i(start.position.x + start.size.x + 3, start.position.y, 7, 7)
		if extra.end.x < map_width - 1 and extra.end.y < map_height - 1:
			_carve_rect(extra, TILE_EMPTY)
			_carve_corridor(start.get_center(), extra.get_center())
			rooms.append(extra)

	# Outer border walls
	for z in map_height:
		for x in map_width:
			if x == 0 or z == 0 or x == map_width - 1 or z == map_height - 1:
				grid[z][x] = TILE_WALL

	# Pillars in larger rooms
	for r in rooms:
		var room: Rect2i = r
		if room.size.x >= 7 and room.size.y >= 7:
			var cx := room.position.x + room.size.x / 2
			var cz := room.position.y + room.size.y / 2
			if grid[cz][cx] == TILE_EMPTY:
				grid[cz][cx] = TILE_PILLAR

	_place_room_doors()
	_carve_upper_floors()
	_mark_exterior_void()

	_spawn_pos = Vector3(
		(start.position.x + start.size.x * 0.5) * CELL,
		0.0,
		(start.position.y + start.size.y * 0.5) * CELL
	)


func _carve_rect(r: Rect2i, tile: int) -> void:
	for z in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if z >= 0 and z < map_height and x >= 0 and x < map_width:
				grid[z][x] = tile


func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
	var x := a.x
	var z := a.y
	while x != b.x:
		grid[z][x] = TILE_EMPTY
		# widen slightly
		if z + 1 < map_height:
			grid[z + 1][x] = TILE_EMPTY
		x += 1 if b.x > x else -1
	while z != b.y:
		grid[z][x] = TILE_EMPTY
		if x + 1 < map_width:
			grid[z][x + 1] = TILE_EMPTY
		z += 1 if b.y > z else -1
	grid[z][x] = TILE_EMPTY


func _build_geometry() -> void:
	var world := Node3D.new()
	world.name = "WorldMeshes"
	add_child(world)

	# One continuous floor + ceiling (orders of magnitude cheaper than per-cell meshes)
	_add_global_floor_ceil(world)
	_add_void_barriers(world)

	for z in map_height:
		for x in map_width:
			var tile: int = grid[z][x]
			var origin := Vector3(x * CELL + CELL * 0.5, 0.0, z * CELL + CELL * 0.5)
			if tile == TILE_VOID:
				continue

			if tile == TILE_WALL:
				_add_wall_block(world, origin, x, z)
			elif tile == TILE_PILLAR:
				_add_pillar(world, origin)
			elif tile == TILE_DOOR:
				_add_door(world, origin, x, z)
			elif tile == TILE_STAIR:
				_add_stairs(world, origin, x, z)
			elif tile == TILE_FLOOR2:
				_add_upper_floor(world, origin)
			elif not performance_mode:
				_maybe_wall_trim(world, origin, x, z)


func _add_global_floor_ceil(parent: Node3D) -> void:
	var w := map_width * CELL
	var h := map_height * CELL
	var center := Vector3(w * 0.5, 0.0, h * 0.5)

	# Outdoor terrain so windows look onto ground + mountains, not a void
	var dirt := MeshInstance3D.new()
	var dbox := BoxMesh.new()
	dbox.size = Vector3(w * 3.0, 0.18, h * 3.0)
	dirt.mesh = dbox
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.22, 0.32, 0.16)
	grass.roughness = 0.95
	dirt.material_override = grass
	dirt.position = center + Vector3(0, -0.22, 0)
	parent.add_child(dirt)
	var dirt_body := StaticBody3D.new()
	dirt_body.position = dirt.position
	var dcol := CollisionShape3D.new()
	var dshape := BoxShape3D.new()
	dshape.size = dbox.size
	dcol.shape = dshape
	dirt_body.add_child(dcol)
	dirt_body.collision_layer = 1
	parent.add_child(dirt_body)

	var floor_mesh := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(w, 0.2, h)
	floor_mesh.mesh = fbox
	floor_mesh.material_override = _mats["concrete"]
	floor_mesh.position = center + Vector3(0, -0.1, 0)
	floor_mesh.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if performance_mode
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)
	floor_mesh.add_to_group("perf_mesh")
	parent.add_child(floor_mesh)

	var floor_body := StaticBody3D.new()
	floor_body.position = floor_mesh.position
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = fbox.size
	col.shape = shape
	floor_body.add_child(col)
	floor_body.collision_layer = 1
	parent.add_child(floor_body)

	var ceil_mesh := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(w, 0.15, h)
	ceil_mesh.mesh = cbox
	ceil_mesh.material_override = _mats["metal"]
	ceil_mesh.position = center + Vector3(0, WALL_H + 0.05, 0)
	ceil_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ceil_mesh)

	# No ceiling collision body in perf mode (saves bodies)
	if not performance_mode:
		var ceil_body := StaticBody3D.new()
		ceil_body.position = ceil_mesh.position
		var ccol := CollisionShape3D.new()
		var cshape := BoxShape3D.new()
		cshape.size = cbox.size
		ccol.shape = cshape
		ceil_body.add_child(ccol)
		parent.add_child(ceil_body)


func _add_wall_block(parent: Node3D, origin: Vector3, x: int, z: int) -> void:
	# Skip fully enclosed interior wall cells (no visible faces) for cleaner silhouettes
	if not _wall_has_exposed_face(x, z):
		return
	if _is_facade_wall(x, z):
		_add_window_wall(parent, origin, x, z)
		return

	var mat: Material = _mats["brick"]
	var style := (x * 3 + z * 7) % 5
	if style == 0:
		mat = _mats["metal"]
	elif style == 1:
		mat = _mats["wood"]
	elif style == 2:
		mat = _mats["accent"]

	# Slightly inset solid for a thicker, architectural read
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CELL, WALL_H, CELL)
	mi.mesh = box
	mi.material_override = mat
	mi.position = origin + Vector3(0, WALL_H * 0.5, 0)
	mi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if performance_mode
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)
	mi.add_to_group("perf_mesh")
	parent.add_child(mi)

	if not performance_mode:
		# Baseboard + cornice only on high quality
		var trim := MeshInstance3D.new()
		var tbox := BoxMesh.new()
		tbox.size = Vector3(CELL + 0.02, 0.18, CELL + 0.02)
		trim.mesh = tbox
		trim.material_override = _mats["trim"]
		trim.position = origin + Vector3(0, 0.09, 0)
		parent.add_child(trim)

		var cornice := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(CELL + 0.04, 0.12, CELL + 0.04)
		cornice.mesh = cbox
		cornice.material_override = _mats["trim"]
		cornice.position = origin + Vector3(0, WALL_H - 0.06, 0)
		parent.add_child(cornice)

	var body := StaticBody3D.new()
	body.position = mi.position
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)
	body.collision_layer = 1
	body.set_meta("is_wall", true)
	parent.add_child(body)


func _wall_has_exposed_face(x: int, z: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if nx < 0 or nz < 0 or nx >= map_width or nz >= map_height:
			return true
		if grid[nz][nx] != TILE_WALL:
			return true
	return false


func _add_pillar(parent: Node3D, origin: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.55
	cyl.height = WALL_H
	cyl.radial_segments = 12
	mi.mesh = cyl
	mi.material_override = _mats["metal"]
	mi.position = origin + Vector3(0, WALL_H * 0.5, 0)
	parent.add_child(mi)

	var body := StaticBody3D.new()
	body.position = mi.position
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = WALL_H
	col.shape = shape
	body.add_child(col)
	body.collision_layer = 1
	parent.add_child(body)

	# Hazard base ring
	var ring := MeshInstance3D.new()
	var rbox := BoxMesh.new()
	rbox.size = Vector3(1.4, 0.08, 1.4)
	ring.mesh = rbox
	ring.material_override = _mats["warning"]
	ring.position = origin + Vector3(0, 0.04, 0)
	parent.add_child(ring)


func _door_is_horizontal(x: int, z: int) -> bool:
	## True = slab spans X (blocks north/south traffic).
	var wall_e := int(grid[z][x + 1] == TILE_WALL)
	var wall_w := int(grid[z][x - 1] == TILE_WALL)
	var wall_n := int(grid[z - 1][x] == TILE_WALL)
	var wall_s := int(grid[z + 1][x] == TILE_WALL)
	if wall_e + wall_w == 2:
		return true
	if wall_n + wall_s == 2:
		return false
	# Room-edge openings: face the outside walkable neighbor
	if _walkable_tile(grid[z - 1][x]) or _walkable_tile(grid[z + 1][x]):
		if not _walkable_tile(grid[z][x - 1]) or not _walkable_tile(grid[z][x + 1]):
			return true
	return wall_e + wall_w >= wall_n + wall_s


func _add_door(parent: Node3D, origin: Vector3, x: int, z: int) -> void:
	var door_root := Node3D.new()
	door_root.name = "Door_%d_%d" % [x, z]
	door_root.set_script(preload("res://scripts/door.gd"))
	door_root.position = origin

	var dh := STORY_H
	# Frame + lintel so the rising slab has somewhere to go
	for side in [-1, 1]:
		var frame := MeshInstance3D.new()
		var fbox := BoxMesh.new()
		var horizontal: bool = _door_is_horizontal(x, z)
		if horizontal:
			fbox.size = Vector3(0.28, dh + 0.2, 0.55)
			frame.position = Vector3(side * (CELL * 0.5 - 0.12), dh * 0.5, 0)
		else:
			fbox.size = Vector3(0.55, dh + 0.2, 0.28)
			frame.position = Vector3(0, dh * 0.5, side * (CELL * 0.5 - 0.12))
		frame.mesh = fbox
		frame.material_override = _mats["trim"]
		door_root.add_child(frame)

	var lintel := MeshInstance3D.new()
	var lbox := BoxMesh.new()
	var horizontal2: bool = _door_is_horizontal(x, z)
	if horizontal2:
		lbox.size = Vector3(CELL, 0.28, 0.55)
		lintel.position = Vector3(0, dh + 0.1, 0)
	else:
		lbox.size = Vector3(0.55, 0.28, CELL)
		lintel.position = Vector3(0, dh + 0.1, 0)
	lintel.mesh = lbox
	lintel.material_override = _mats["trim"]
	door_root.add_child(lintel)

	var slab := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	if horizontal2:
		sbox.size = Vector3(CELL - 0.22, dh - 0.15, 0.16)
	else:
		sbox.size = Vector3(0.16, dh - 0.15, CELL - 0.22)
	slab.mesh = sbox
	slab.material_override = _mats["metal"]
	slab.position = Vector3(0, dh * 0.5 - 0.05, 0)
	slab.name = "Slab"
	door_root.add_child(slab)
	var stripe := MeshInstance3D.new()
	var stbox := BoxMesh.new()
	if horizontal2:
		stbox.size = Vector3(CELL - 0.6, 0.18, 0.2)
	else:
		stbox.size = Vector3(0.2, 0.18, CELL - 0.6)
	stripe.mesh = stbox
	stripe.material_override = _mats["warning"]
	stripe.position = Vector3(0, -0.4, 0)
	slab.add_child(stripe)

	# Viewport window in the slab
	var pane := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	if horizontal2:
		pbox.size = Vector3(CELL - 1.1, 0.55, 0.2)
	else:
		pbox.size = Vector3(0.2, 0.55, CELL - 1.1)
	pane.mesh = pbox
	pane.material_override = _mats["glass"]
	pane.position = Vector3(0, 0.35, 0)
	pane.name = "Pane"
	slab.add_child(pane)

	var body := AnimatableBody3D.new()
	body.name = "DoorBody"
	body.position = slab.position
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sbox.size
	col.shape = shape
	body.add_child(col)
	body.collision_layer = 1
	body.collision_mask = 0
	door_root.add_child(body)

	door_root.horizontal = horizontal2
	door_root.slab = slab
	door_root.body = body
	door_root.door_height = dh
	parent.add_child(door_root)
	door_root.set_process(true)
	doors.append(door_root)


func _maybe_wall_trim(parent: Node3D, origin: Vector3, x: int, z: int) -> void:
	# Light rail on walls adjacent to empty floor
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if nx < 0 or nz < 0 or nx >= map_width or nz >= map_height:
			continue
		if grid[nz][nx] != TILE_WALL:
			continue
		# place thin emissive strip on floor side of wall
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		if d.x != 0:
			box.size = Vector3(0.08, 0.06, CELL * 0.6)
			strip.position = origin + Vector3(d.x * (CELL * 0.5 - 0.2), 2.4, 0)
		else:
			box.size = Vector3(CELL * 0.6, 0.06, 0.08)
			strip.position = origin + Vector3(0, 2.4, d.y * (CELL * 0.5 - 0.2))
		strip.mesh = box
		strip.material_override = _mats["emissive"]
		if (x + z + d.x + d.y) % 4 == 0:
			parent.add_child(strip)


func _walkable_tile(t: int) -> bool:
	return t == TILE_EMPTY or t == TILE_DOOR or t == TILE_STAIR or t == TILE_FLOOR2


func _mark_exterior_void() -> void:
	## Flood from the map border through solid walls so facade walls look outdoors.
	var q: Array[Vector2i] = []
	for z in map_height:
		for x in map_width:
			if x == 0 or z == 0 or x == map_width - 1 or z == map_height - 1:
				if grid[z][x] == TILE_WALL:
					q.append(Vector2i(x, z))
	var seen := {}
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		var key := "%d_%d" % [c.x, c.y]
		if seen.has(key):
			continue
		seen[key] = true
		if c.x < 0 or c.y < 0 or c.x >= map_width or c.y >= map_height:
			continue
		if grid[c.y][c.x] != TILE_WALL:
			continue
		if _adjacent_walkable(c.x, c.y):
			continue # keep as facade
		grid[c.y][c.x] = TILE_VOID
		q.append(Vector2i(c.x + 1, c.y))
		q.append(Vector2i(c.x - 1, c.y))
		q.append(Vector2i(c.x, c.y + 1))
		q.append(Vector2i(c.x, c.y - 1))

	# Invisible shell so you cannot walk out into the empty outdoor dirt
	_seal_exterior()


func _adjacent_walkable(x: int, z: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if nx < 0 or nz < 0 or nx >= map_width or nz >= map_height:
			continue
		if _walkable_tile(grid[nz][nx]):
			return true
	return false


func _seal_exterior() -> void:
	var root := get_node_or_null("WorldMeshes")
	# Called before WorldMeshes exists; stash barriers for _build_geometry
	# Applied in _add_void_barriers after meshes exist.
	pass


func _add_void_barriers(parent: Node3D) -> void:
	for z in map_height:
		for x in map_width:
			if grid[z][x] != TILE_VOID:
				continue
			if not _adjacent_walkable(x, z) and not _adjacent_tile(x, z, TILE_DOOR) and not _adjacent_tile(x, z, TILE_WALL):
				continue
			var origin := Vector3(x * CELL + CELL * 0.5, WALL_H * 0.5, z * CELL + CELL * 0.5)
			var body := StaticBody3D.new()
			body.position = origin
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(CELL, WALL_H, CELL)
			col.shape = shape
			body.add_child(col)
			body.collision_layer = 1
			parent.add_child(body)


func _adjacent_tile(x: int, z: int, tile: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if nx < 0 or nz < 0 or nx >= map_width or nz >= map_height:
			continue
		if grid[nz][nx] == tile:
			return true
	return false


func _is_facade_wall(x: int, z: int) -> bool:
	if not _adjacent_walkable(x, z):
		return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if nx < 0 or nz < 0 or nx >= map_width or nz >= map_height:
			return true
		if grid[nz][nx] == TILE_VOID:
			return true
	return false


func _add_window_wall(parent: Node3D, origin: Vector3, x: int, z: int) -> void:
	## Solid wall with a punched window looking at the mountains.
	var inward := Vector3.ZERO
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if nx < 0 or nz < 0 or nx >= map_width or nz >= map_height:
			continue
		if _walkable_tile(grid[nz][nx]):
			inward = Vector3(d.x, 0, d.y)
			break
	# Two storeys of window
	for storey in 2:
		var base_y := float(storey) * STORY_H
		# Mostly solid wall with a small high window (not a door-sized hole)
		_static_box(parent, origin + Vector3(0, base_y + 0.7, 0), Vector3(CELL, 1.4, CELL), 0.0, _mats["brick"])
		_static_box(parent, origin + Vector3(0, base_y + STORY_H - 0.22, 0), Vector3(CELL, 0.44, CELL), 0.0, _mats["brick"])
		var along := Vector3(inward.z, 0, -inward.x)
		if along.length_squared() < 0.01:
			along = Vector3(1, 0, 0)
		_static_box(parent, origin + along * (CELL * 0.36) + Vector3(0, base_y + STORY_H * 0.5, 0), Vector3(CELL * 0.32, STORY_H, CELL * 0.32), 0.0, _mats["brick"])
		_static_box(parent, origin - along * (CELL * 0.36) + Vector3(0, base_y + STORY_H * 0.5, 0), Vector3(CELL * 0.32, STORY_H, CELL * 0.32), 0.0, _mats["brick"])
		var glass := MeshInstance3D.new()
		var gbox := BoxMesh.new()
		if absf(inward.x) > 0.5:
			gbox.size = Vector3(0.08, 1.05, CELL * 0.42)
		else:
			gbox.size = Vector3(CELL * 0.42, 1.05, 0.08)
		glass.mesh = gbox
		glass.material_override = _mats["glass"]
		glass.position = origin + inward * 0.2 + Vector3(0, base_y + 1.85, 0)
		parent.add_child(glass)

	# Keep the facade solid so you look out but don't walk out
	var body := StaticBody3D.new()
	body.position = origin + Vector3(0, WALL_H * 0.5, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL, WALL_H, CELL)
	col.shape = shape
	body.add_child(col)
	body.collision_layer = 1
	parent.add_child(body)


func _add_mountains() -> void:
	var root := Node3D.new()
	root.name = "Mountains"
	add_child(root)
	var w := map_width * CELL
	var h := map_height * CELL
	var cx := w * 0.5
	var cz := h * 0.5
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.38, 0.36, 0.34)
	rock.roughness = 0.92
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.92, 0.94, 0.97)
	snow.roughness = 0.55
	var rng := _rng
	for i in 18:
		var ang := float(i) / 18.0 * TAU + rng.randf() * 0.2
		var dist := maxf(w, h) * 0.72 + rng.randf_range(8.0, 40.0)
		var peak := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		var rad := rng.randf_range(18.0, 42.0)
		var ht := rng.randf_range(28.0, 70.0)
		cone.top_radius = 0.4
		cone.bottom_radius = rad
		cone.height = ht
		cone.radial_segments = 7
		peak.mesh = cone
		peak.material_override = rock
		peak.position = Vector3(cx + cos(ang) * dist, ht * 0.45, cz + sin(ang) * dist)
		root.add_child(peak)
		var cap := MeshInstance3D.new()
		var capm := CylinderMesh.new()
		capm.top_radius = 0.2
		capm.bottom_radius = rad * 0.28
		capm.height = ht * 0.22
		capm.radial_segments = 6
		cap.mesh = capm
		cap.material_override = snow
		cap.position = peak.position + Vector3(0, ht * 0.38, 0)
		root.add_child(cap)


func _cell_room_index(x: int, z: int) -> int:
	for i in rooms.size():
		if (rooms[i] as Rect2i).has_point(Vector2i(x, z)):
			return i
	return -1


func _place_room_doors() -> void:
	## One doorway per opening that actually enters a room. Hallways stay open.
	for ri in rooms.size():
		var room: Rect2i = rooms[ri]
		var openings: Array[Vector2i] = []
		for z in range(room.position.y, room.position.y + room.size.y):
			for x in range(room.position.x, room.position.x + room.size.x):
				if grid[z][x] != TILE_EMPTY:
					continue
				var on_edge := (
					x == room.position.x
					or z == room.position.y
					or x == room.position.x + room.size.x - 1
					or z == room.position.y + room.size.y - 1
				)
				if not on_edge:
					continue
				if _is_room_exit(room, x, z):
					openings.append(Vector2i(x, z))
		var clusters := _cluster_cells(openings)
		for cluster in clusters:
			var cells: Array = cluster
			# A real doorway is 1–3 cells. Wider shared edges get walled down to 2.
			cells.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
			var keep := mini(2, cells.size())
			var mid := cells.size() / 2
			var start_i := clampi(mid - keep / 2, 0, cells.size() - keep)
			for i in cells.size():
				var c: Vector2i = cells[i]
				if i >= start_i and i < start_i + keep:
					grid[c.y][c.x] = TILE_DOOR
				else:
					grid[c.y][c.x] = TILE_WALL


func _is_room_exit(room: Rect2i, x: int, z: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if nx < 0 or nz < 0 or nx >= map_width or nz >= map_height:
			continue
		if room.has_point(Vector2i(nx, nz)):
			continue
		if not _walkable_tile(grid[nz][nx]):
			continue
		# Neighbour is a corridor or a different room — this is a real entrance.
		return true
	return false


func _cluster_cells(cells: Array[Vector2i]) -> Array:
	var remaining: Array[Vector2i] = cells.duplicate()
	var clusters: Array = []
	while not remaining.is_empty():
		var seed: Vector2i = remaining.pop_back()
		var cluster: Array[Vector2i] = [seed]
		var grew := true
		while grew:
			grew = false
			for i in range(remaining.size() - 1, -1, -1):
				var c: Vector2i = remaining[i]
				for s in cluster:
					if absi(c.x - s.x) + absi(c.y - s.y) == 1:
						cluster.append(c)
						remaining.remove_at(i)
						grew = true
						break
		clusters.append(cluster)
	return clusters


func _carve_upper_floors() -> void:
	## Always build a second storey in the first large rooms so stairs are findable.
	var lofted := 0
	for ri in rooms.size():
		var room: Rect2i = rooms[ri]
		if room.size.x < 6 or room.size.y < 6:
			continue
		if lofted >= 4:
			break
		# Stair run: 2 wide × 4 long along the west interior, climbing +Z.
		var sx := room.position.x + 1
		var sz := room.position.y + 1
		var run := mini(4, room.size.y - 3)
		if run < 3:
			continue
		for i in run:
			var cz := sz + i
			if cz >= room.position.y + room.size.y - 1:
				break
			if grid[cz][sx] != TILE_WALL and grid[cz][sx] != TILE_DOOR:
				grid[cz][sx] = TILE_STAIR
			if sx + 1 < room.position.x + room.size.x - 1 and grid[cz][sx + 1] != TILE_WALL and grid[cz][sx + 1] != TILE_DOOR:
				grid[cz][sx + 1] = TILE_STAIR
		# Upper floor covers the rest of the interior (not the stair strip)
		for z in range(room.position.y + 1, room.position.y + room.size.y - 1):
			for x in range(room.position.x + 1, room.position.x + room.size.x - 1):
				if grid[z][x] == TILE_EMPTY:
					grid[z][x] = TILE_FLOOR2
		lofted += 1


func _add_stairs(parent: Node3D, origin: Vector3, x: int, z: int) -> void:
	# Climb +Z along the carved strip. Only the lowest cell builds the flight.
	var dir_i := Vector2i(0, 1)
	if z + 1 < map_height and grid[z + 1][x] == TILE_STAIR:
		dir_i = Vector2i(0, 1)
	elif z - 1 >= 0 and grid[z - 1][x] == TILE_STAIR:
		dir_i = Vector2i(0, -1)
	elif x + 1 < map_width and grid[z][x + 1] == TILE_STAIR:
		dir_i = Vector2i(1, 0)
	elif x - 1 >= 0 and grid[z][x - 1] == TILE_STAIR:
		dir_i = Vector2i(-1, 0)
	var back := Vector2i(-dir_i.x, -dir_i.y)
	var bx := x + back.x
	var bz := z + back.y
	if bx >= 0 and bz >= 0 and bx < map_width and bz < map_height and grid[bz][bx] == TILE_STAIR:
		return
	# One flight per stairwell (skip the twin cell of a 2-wide run)
	var side_a := Vector2i(-dir_i.y, dir_i.x)
	var sx := x + side_a.x
	var sz := z + side_a.y
	if sx >= 0 and sz >= 0 and sx < map_width and sz < map_height and grid[sz][sx] == TILE_STAIR:
		if sx + sz < x + z:
			return

	var run_cells := 1
	var cx := x + dir_i.x
	var cz := z + dir_i.y
	while cx >= 0 and cz >= 0 and cx < map_width and cz < map_height and grid[cz][cx] == TILE_STAIR and run_cells < 8:
		run_cells += 1
		cx += dir_i.x
		cz += dir_i.y

	var dir := Vector3(float(dir_i.x), 0.0, float(dir_i.y))
	var length := float(run_cells) * CELL
	var width := CELL * 1.85
	# Ramp from the near edge of the first cell up to the far edge of the last.
	var bottom := origin - dir * (CELL * 0.45) + Vector3(0, 0.04, 0)
	var top := origin + dir * (length - CELL * 0.45) + Vector3(0, FLOOR2_Y + 0.02, 0)
	var along := top - bottom
	var hyp := along.length()
	var slope_dir := along / hyp
	var right := Vector3.UP.cross(slope_dir)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var normal := slope_dir.cross(right).normalized()
	if normal.y < 0.0:
		normal = -normal
		right = -right

	var ramp := StaticBody3D.new()
	ramp.name = "StairRamp"
	ramp.transform = Transform3D(Basis(right, normal, slope_dir).orthonormalized(), (bottom + top) * 0.5)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.22, hyp)
	col.shape = shape
	ramp.add_child(col)
	ramp.collision_layer = 1
	parent.add_child(ramp)

	# Visual treads only (no collision — the ramp is what you walk on)
	var steps := run_cells * 5
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var pos := bottom.lerp(top, t) + normal * 0.06
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width * 0.95, 0.08, hyp / float(steps) * 0.9)
		mi.mesh = box
		mi.material_override = _mats["warning"] if i % 2 == 0 else _mats["metal"]
		mi.transform = Transform3D(Basis(right, normal, slope_dir).orthonormalized(), pos)
		parent.add_child(mi)

	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rbox := BoxMesh.new()
		rbox.size = Vector3(0.07, 0.07, hyp)
		rail.mesh = rbox
		rail.material_override = _mats["trim"]
		var side_f := float(side)
		var rail_pos: Vector3 = (bottom + top) * 0.5 + right * (side_f * width * 0.48) + normal * 0.55
		rail.transform = Transform3D(Basis(right, normal, slope_dir).orthonormalized(), rail_pos)
		parent.add_child(rail)


func _add_upper_floor(parent: Node3D, origin: Vector3) -> void:
	var deck := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CELL, 0.16, CELL)
	deck.mesh = box
	deck.material_override = _mats["wood"]
	deck.position = origin + Vector3(0, FLOOR2_Y, 0)
	parent.add_child(deck)

	var body := StaticBody3D.new()
	body.position = deck.position
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)
	body.collision_layer = 1
	parent.add_child(body)

	var rail := MeshInstance3D.new()
	var rbox := BoxMesh.new()
	rbox.size = Vector3(CELL, 0.06, CELL)
	rail.mesh = rbox
	rail.material_override = _mats["trim"]
	rail.position = origin + Vector3(0, FLOOR2_Y + 0.95, 0)
	rail.scale = Vector3(1.02, 1.0, 1.02)
	parent.add_child(rail)


func _place_lights() -> void:
	var lights_root := Node3D.new()
	lights_root.name = "Lights"
	add_child(lights_root)

	# More coverage so character textures aren't pure black in shadows
	var step := 3 if performance_mode else 2
	var chance := 0.7 if performance_mode else 0.85
	var max_lights := 24 if performance_mode else 36
	# Scale light budget with map size
	max_lights = mini(max_lights + int((map_width * map_height) / 160.0), 40)
	var placed := 0
	var warm := sector_theme == 2

	for z in range(2, map_height - 2, step):
		for x in range(2, map_width - 2, step):
			if placed >= max_lights:
				return
			if grid[z][x] == TILE_WALL:
				continue
			if _rng.randf() > chance:
				continue
			var ly := (FLOOR2_Y + STORY_H - 0.35) if grid[z][x] == TILE_FLOOR2 else (STORY_H - 0.35)
			var origin := Vector3(x * CELL + CELL * 0.5, ly, z * CELL + CELL * 0.5)

			if not performance_mode or placed % 3 == 0:
				var fixture := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.9, 0.08, 0.9)
				fixture.mesh = box
				fixture.material_override = _mats["emissive"]
				fixture.position = origin
				lights_root.add_child(fixture)

			var light := OmniLight3D.new()
			if warm:
				light.light_color = Color(1.0, 0.82, 0.62) if _rng.randf() > 0.35 else Color(0.95, 0.75, 0.55)
			else:
				light.light_color = Color(0.85, 0.92, 1.0) if _rng.randf() > 0.3 else Color(1.0, 0.9, 0.75)
			light.light_energy = 2.6 if performance_mode else _rng.randf_range(2.2, 3.1)
			light.omni_range = CELL * (6.0 if performance_mode else 4.5)
			light.omni_attenuation = 0.9
			light.shadow_enabled = false
			light.position = origin + Vector3(0, -0.15, 0)
			light.distance_fade_enabled = true
			light.distance_fade_begin = 32.0
			light.distance_fade_length = 12.0
			lights_root.add_child(light)
			# Wall sconce on an adjacent wall for a more architectural read
			if placed % 2 == 0:
				_add_sconce(lights_root, Vector3(x * CELL + CELL * 0.5, 0.0, z * CELL + CELL * 0.5), x, z, warm)
			placed += 1


func _add_sconce(parent: Node3D, origin: Vector3, x: int, z: int, warm: bool) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if nx < 0 or nz < 0 or nx >= map_width or nz >= map_height:
			continue
		if grid[nz][nx] != TILE_WALL:
			continue
		var pos := origin + Vector3(d.x * (CELL * 0.5 - 0.12), 2.15, d.y * (CELL * 0.5 - 0.12))
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.28, 0.08) if d.x != 0 else Vector3(0.08, 0.28, 0.18)
		plate.mesh = box
		plate.material_override = _mats["trim"]
		plate.position = pos
		parent.add_child(plate)
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.86, 0.62) if warm else Color(0.82, 0.9, 1.0)
		spot.light_energy = 2.4
		spot.spot_range = 8.0
		spot.spot_angle = 48.0
		spot.shadow_enabled = false
		spot.position = pos + Vector3(-d.x * 0.1, -0.05, -d.y * 0.1)
		if d.x != 0:
			spot.rotation_degrees = Vector3(-18, 90.0 if d.x < 0 else -90.0, 0)
		else:
			spot.rotation_degrees = Vector3(-18, 0.0 if d.y > 0 else 180.0, 0)
		parent.add_child(spot)
		return


func _place_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)

	# Furniture clusters per room (tables, chairs, crates, monitors)
	for r in rooms:
		var room: Rect2i = r
		var cx := (room.position.x + room.size.x * 0.5) * CELL
		var cz := (room.position.y + room.size.y * 0.5) * CELL
		var center := Vector3(cx, 0.0, cz)
		if center.distance_to(_spawn_pos) < CELL * 1.2:
			_add_start_briefing(props, center)
			continue
		var roll := _rng.randf()
		if roll < 0.38:
			_add_table_set(props, center, _rng.randf() * TAU)
		elif roll < 0.62:
			_add_crate_stack(props, center + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-1.2, 1.2)))
		else:
			_add_workbench(props, center, _rng.randf() * TAU)
		# Extra chairs along a wall
		if room.size.x >= 7 and _rng.randf() < 0.7:
			var wall_x := (room.position.x + 1) * CELL + 0.7
			var wall_z := cz
			_add_chair(props, Vector3(wall_x, 0, wall_z), PI * 0.5)
			_add_chair(props, Vector3(wall_x, 0, wall_z + 1.1), PI * 0.5)

	# Sparse hallway crates
	for z in range(1, map_height - 1):
		for x in range(1, map_width - 1):
			if grid[z][x] != TILE_EMPTY:
				continue
			if _rng.randf() > 0.018:
				continue
			var origin := Vector3(x * CELL + CELL * 0.5, 0.0, z * CELL + CELL * 0.5)
			if origin.distance_to(_spawn_pos) < CELL * 2.0:
				continue
			_add_crate_stack(props, origin)


func _static_box(parent: Node3D, pos: Vector3, size: Vector3, rot_y: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.collision_layer = 1
	parent.add_child(body)
	return mi


func _add_table_set(parent: Node3D, origin: Vector3, yaw: float) -> void:
	var top_y := 0.78
	_static_box(parent, origin + Vector3(0, top_y, 0), Vector3(1.8, 0.06, 0.9), yaw, _mats["wood"])
	# Legs
	for ox in [-0.78, 0.78]:
		for oz in [-0.35, 0.35]:
			var off := Vector3(ox, top_y * 0.5, oz).rotated(Vector3.UP, yaw)
			_static_box(parent, origin + off, Vector3(0.07, top_y, 0.07), yaw, _mats["metal"])
	_add_table_clutter(parent, origin + Vector3(0, top_y + 0.03, 0), yaw)
	_add_chair(parent, origin + Vector3(0, 0, 0.85).rotated(Vector3.UP, yaw), yaw + PI)
	_add_chair(parent, origin + Vector3(0, 0, -0.85).rotated(Vector3.UP, yaw), yaw)


func _add_workbench(parent: Node3D, origin: Vector3, yaw: float) -> void:
	_static_box(parent, origin + Vector3(0, 0.46, 0), Vector3(2.2, 0.92, 0.72), yaw, _mats["metal"])
	_static_box(parent, origin + Vector3(0, 0.95, 0), Vector3(2.25, 0.05, 0.76), yaw, _mats["trim"])
	_add_table_clutter(parent, origin + Vector3(0, 0.99, 0), yaw)
	# Monitor
	var mon := MeshInstance3D.new()
	var mbox := BoxMesh.new()
	mbox.size = Vector3(0.52, 0.34, 0.04)
	mon.mesh = mbox
	mon.material_override = _mats["emissive"]
	mon.position = origin + Vector3(0.4, 1.28, 0).rotated(Vector3.UP, yaw)
	mon.rotation.y = yaw
	parent.add_child(mon)
	_add_chair(parent, origin + Vector3(0, 0, 0.7).rotated(Vector3.UP, yaw), yaw + PI)


func _add_start_briefing(parent: Node3D, origin: Vector3) -> void:
	_add_table_set(parent, origin + Vector3(1.6, 0, 1.4), 0.2)
	_add_crate_stack(parent, origin + Vector3(-2.0, 0, 1.8))


func _add_table_clutter(parent: Node3D, table_top: Vector3, yaw: float) -> void:
	# Laptop
	_static_box(parent, table_top + Vector3(-0.35, 0.03, 0).rotated(Vector3.UP, yaw), Vector3(0.32, 0.02, 0.22), yaw, _mats["plastic"])
	var screen := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(0.32, 0.2, 0.012)
	screen.mesh = sbox
	screen.material_override = _mats["emissive"]
	screen.position = table_top + Vector3(-0.35, 0.13, -0.08).rotated(Vector3.UP, yaw)
	screen.rotation.y = yaw
	screen.rotation.x = -0.15
	parent.add_child(screen)
	# Coffee mug
	var mug := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.032
	cyl.height = 0.08
	cyl.radial_segments = 10
	mug.mesh = cyl
	var mug_mat := StandardMaterial3D.new()
	mug_mat.albedo_color = Color(0.75, 0.18, 0.14)
	mug_mat.roughness = 0.4
	mug.material_override = mug_mat
	mug.position = table_top + Vector3(0.42, 0.05, 0.12).rotated(Vector3.UP, yaw)
	parent.add_child(mug)
	# Papers
	_static_box(parent, table_top + Vector3(0.15, 0.008, -0.18).rotated(Vector3.UP, yaw), Vector3(0.22, 0.004, 0.28), yaw + 0.3, _mats["accent"])
	# Radio / ammo tin
	_static_box(parent, table_top + Vector3(0.55, 0.04, -0.2).rotated(Vector3.UP, yaw), Vector3(0.14, 0.08, 0.1), yaw, _mats["metal"])


func _add_chair(parent: Node3D, origin: Vector3, yaw: float) -> void:
	_static_box(parent, origin + Vector3(0, 0.46, 0), Vector3(0.42, 0.06, 0.42), yaw, _mats["fabric"])
	_static_box(parent, origin + Vector3(0, 0.23, 0), Vector3(0.07, 0.46, 0.07), yaw, _mats["metal"])
	_static_box(parent, origin + Vector3(0, 0.78, -0.18).rotated(Vector3.UP, yaw), Vector3(0.42, 0.42, 0.05), yaw, _mats["fabric"])


func _add_crate_stack(parent: Node3D, origin: Vector3) -> void:
	var s := _rng.randf_range(0.55, 0.85)
	_static_box(parent, origin + Vector3(0, s * 0.5, 0), Vector3(s, s, s), _rng.randf() * 0.4, _mats["wood"] if _rng.randf() > 0.35 else _mats["metal"])
	if _rng.randf() < 0.55:
		var s2 := s * 0.72
		_static_box(parent, origin + Vector3(0.08, s + s2 * 0.5, -0.05), Vector3(s2, s2, s2), 0.35, _mats["metal"])


func _place_spawns() -> void:
	var min_cells: float = 3.5
	var band := Vector2(3.0, 7.0)
	var enemy_cap := 4
	if GameState:
		min_cells = GameState.min_spawn_distance_cells()
		band = GameState.near_spawn_band()
		enemy_cap = GameState.enemy_count_cap()
	enemy_cap = mini(enemy_cap + 2, 22)

	var candidates: Array[Vector3] = []
	for z in range(1, map_height - 1):
		for x in range(1, map_width - 1):
			if grid[z][x] != TILE_EMPTY and grid[z][x] != TILE_FLOOR2:
				continue
			var py := FLOOR2_Y + 0.1 if grid[z][x] == TILE_FLOOR2 else 0.0
			var p := Vector3(x * CELL + CELL * 0.5, py, z * CELL + CELL * 0.5)
			if p.distance_to(_spawn_pos) < CELL * min_cells:
				continue
			candidates.append(p)
	# Fallback: if we filtered everyone out, take any walkable cell not on the player
	if candidates.is_empty():
		for z in range(1, map_height - 1):
			for x in range(1, map_width - 1):
				if grid[z][x] != TILE_EMPTY and grid[z][x] != TILE_FLOOR2:
					continue
				var p2 := Vector3(x * CELL + CELL * 0.5, 0.0, z * CELL + CELL * 0.5)
				if p2.distance_to(_spawn_pos) < CELL * 1.2:
					continue
				candidates.append(p2)

	candidates.shuffle()
	var near_player: Array[Vector3] = []
	var far_player: Array[Vector3] = []
	for p in candidates:
		var d_cells := p.distance_to(_spawn_pos) / CELL
		if d_cells >= band.x and d_cells <= band.y:
			near_player.append(p)
		else:
			far_player.append(p)
	near_player.shuffle()
	far_player.shuffle()
	var ordered: Array[Vector3] = []
	# Easy: prefer far spawns first so you aren't dogpiled; Hard: near first
	if GameState and GameState.difficulty == GameState.Difficulty.EASY:
		ordered.append_array(far_player)
		ordered.append_array(near_player)
	else:
		ordered.append_array(near_player)
		ordered.append_array(far_player)

	var enemy_count := mini(enemy_cap, maxi(1, ordered.size()))
	for i in ordered.size():
		if _enemy_spawns.size() >= enemy_count:
			break
		var p: Vector3 = ordered[i]
		var already := false
		for e in _enemy_spawns:
			if e.distance_to(p) < 0.1:
				already = true
				break
		if already:
			continue
		_enemy_spawns.append(p)

	var pickup_count := mini(10 if (GameState and GameState.difficulty == GameState.Difficulty.EASY) else 8, maxi(0, candidates.size() / 4))
	var pi := 0
	while _pickup_spawns.size() < pickup_count and pi < candidates.size():
		var pp: Vector3 = candidates[pi]
		pi += 1
		var on_enemy := false
		for e in _enemy_spawns:
			if e.distance_to(pp) < 0.1:
				on_enemy = true
				break
		if on_enemy:
			continue
		var kind := "ammo" if _rng.randf() < 0.55 else "health"
		# Easy: slightly more health packs
		if GameState and GameState.difficulty == GameState.Difficulty.EASY and _rng.randf() < 0.35:
			kind = "health"
		_pickup_spawns.append({"pos": pp, "type": kind})


func is_solid_world_pos(pos: Vector3) -> bool:
	var x := int(floor(pos.x / CELL))
	var z := int(floor(pos.z / CELL))
	if z < 0 or z >= map_height or x < 0 or x >= map_width:
		return true
	var t: int = grid[z][x]
	return t == TILE_WALL or t == TILE_PILLAR


func try_open_door_near(pos: Vector3, look_dir: Vector3) -> bool:
	var target := pos + look_dir.normalized() * 2.0
	for d in doors:
		if d == null or not is_instance_valid(d):
			continue
		if d.global_position.distance_to(target) < CELL * 1.4 or d.global_position.distance_to(pos) < CELL * 1.6:
			if d.has_method("try_open"):
				return d.try_open()
	return false
