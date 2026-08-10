extends Node3D
class_name LevelGenerator
## Procedural multi-room dungeon with PBR materials, trim, lights, and props.

signal generation_finished(spawn_pos: Vector3, enemy_spawns: Array[Vector3], pickup_spawns: Array)

const CELL := 4.0
const WALL_H := 3.2
const TILE_EMPTY := 0
const TILE_WALL := 1
const TILE_DOOR := 2
const TILE_PILLAR := 3

@export var rooms_count: int = 12
@export var map_width: int = 40
@export var map_height: int = 40
@export var seed_value: int = 0
## Huge FPS win: one floor/ceiling, no trims/beads, few lights, no shadows.
@export var performance_mode: bool = true
## Visual theme: 1 = cool concrete, 2 = warm industrial
var sector_theme: int = 1

var grid: Array = [] # 2D ints
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

	var rooms: Array = []
	# Larger start room on bigger maps
	var start_sz := 8 if map_width >= 36 else 6
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

	# Door markers on corridor junctions (thin wall openings already carved)
	# Mark door tiles: empty cells that separate rooms with single-cell width corridors
	for z in range(1, map_height - 1):
		for x in range(1, map_width - 1):
			if grid[z][x] != TILE_EMPTY:
				continue
			var walls_h := int(grid[z][x - 1] == TILE_WALL) + int(grid[z][x + 1] == TILE_WALL)
			var walls_v := int(grid[z - 1][x] == TILE_WALL) + int(grid[z + 1][x] == TILE_WALL)
			# Corridor cell between rooms
			if (walls_h == 2 and walls_v == 0) or (walls_v == 2 and walls_h == 0):
				# occasional door
				if _rng.randf() < 0.18:
					grid[z][x] = TILE_DOOR

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

	for z in map_height:
		for x in map_width:
			var tile: int = grid[z][x]
			var origin := Vector3(x * CELL + CELL * 0.5, 0.0, z * CELL + CELL * 0.5)

			if tile == TILE_WALL:
				_add_wall_block(world, origin, x, z)
			elif tile == TILE_PILLAR:
				_add_pillar(world, origin)
			elif tile == TILE_DOOR:
				_add_door(world, origin, x, z)
			elif not performance_mode:
				_maybe_wall_trim(world, origin, x, z)


func _add_global_floor_ceil(parent: Node3D) -> void:
	var w := map_width * CELL
	var h := map_height * CELL
	var center := Vector3(w * 0.5, 0.0, h * 0.5)

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


func _add_door(parent: Node3D, origin: Vector3, x: int, z: int) -> void:
	var door_root := Node3D.new()
	door_root.name = "Door_%d_%d" % [x, z]
	door_root.position = origin
	parent.add_child(door_root)

	# Frame
	for side in [-1, 1]:
		var frame := MeshInstance3D.new()
		var fbox := BoxMesh.new()
		# Determine orientation by neighboring walls
		var horizontal: bool = (grid[z][x - 1] == TILE_WALL and grid[z][x + 1] == TILE_WALL)
		if horizontal:
			fbox.size = Vector3(0.25, WALL_H, 0.6)
			frame.position = Vector3(side * (CELL * 0.5 - 0.15), WALL_H * 0.5, 0)
		else:
			fbox.size = Vector3(0.6, WALL_H, 0.25)
			frame.position = Vector3(0, WALL_H * 0.5, side * (CELL * 0.5 - 0.15))
		frame.mesh = fbox
		frame.material_override = _mats["trim"]
		door_root.add_child(frame)

	var slab := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	var horizontal2: bool = (grid[z][x - 1] == TILE_WALL and grid[z][x + 1] == TILE_WALL)
	if horizontal2:
		sbox.size = Vector3(CELL - 0.4, WALL_H - 0.2, 0.18)
	else:
		sbox.size = Vector3(0.18, WALL_H - 0.2, CELL - 0.4)
	slab.mesh = sbox
	slab.material_override = _mats["wood"]
	slab.position = Vector3(0, WALL_H * 0.5 - 0.05, 0)
	slab.name = "Slab"
	door_root.add_child(slab)

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

	door_root.set_script(preload("res://scripts/door.gd"))
	door_root.horizontal = horizontal2
	door_root.slab = slab
	door_root.body = body
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


func _place_lights() -> void:
	var lights_root := Node3D.new()
	lights_root.name = "Lights"
	add_child(lights_root)

	# More coverage so character textures aren't pure black in shadows
	var step := 4 if performance_mode else 3
	var chance := 0.55 if performance_mode else 0.7
	var max_lights := 18 if performance_mode else 28
	# Scale light budget with map size
	max_lights = mini(max_lights + int((map_width * map_height) / 200.0), 32)
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
			var origin := Vector3(x * CELL + CELL * 0.5, WALL_H - 0.35, z * CELL + CELL * 0.5)

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
			light.light_energy = 2.2 if performance_mode else _rng.randf_range(1.8, 2.6)
			light.omni_range = CELL * (5.5 if performance_mode else 4.0)
			light.omni_attenuation = 1.0
			light.shadow_enabled = false
			light.position = origin + Vector3(0, -0.15, 0)
			light.distance_fade_enabled = true
			light.distance_fade_begin = 28.0
			light.distance_fade_length = 12.0
			lights_root.add_child(light)
			placed += 1


func _place_props() -> void:
	if performance_mode:
		return # props are pure eye candy and add physics bodies
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)

	for z in range(1, map_height - 1):
		for x in range(1, map_width - 1):
			if grid[z][x] != TILE_EMPTY:
				continue
			if _rng.randf() > 0.04:
				continue
			var origin := Vector3(x * CELL + CELL * 0.5, 0.0, z * CELL + CELL * 0.5)
			if origin.distance_to(_spawn_pos) < CELL * 2.0:
				continue

			var crate := MeshInstance3D.new()
			var box := BoxMesh.new()
			var s := _rng.randf_range(0.6, 1.1)
			box.size = Vector3(s, s, s)
			crate.mesh = box
			crate.material_override = _mats["wood"] if _rng.randf() > 0.4 else _mats["metal"]
			crate.position = origin + Vector3(_rng.randf_range(-0.8, 0.8), s * 0.5, _rng.randf_range(-0.8, 0.8))
			crate.rotation.y = _rng.randf() * TAU
			props.add_child(crate)

			var body := StaticBody3D.new()
			body.position = crate.position
			body.rotation = crate.rotation
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = box.size
			col.shape = shape
			body.add_child(col)
			body.collision_layer = 1
			props.add_child(body)


func _place_spawns() -> void:
	var min_cells: float = 3.5
	var band := Vector2(3.0, 7.0)
	var enemy_cap := 4
	if GameState:
		min_cells = GameState.min_spawn_distance_cells()
		band = GameState.near_spawn_band()
		enemy_cap = GameState.enemy_count_cap()
	if not performance_mode:
		enemy_cap = mini(enemy_cap + 2, 12)

	var candidates: Array[Vector3] = []
	for z in range(1, map_height - 1):
		for x in range(1, map_width - 1):
			if grid[z][x] != TILE_EMPTY and grid[z][x] != TILE_DOOR:
				continue
			var p := Vector3(x * CELL + CELL * 0.5, 0.0, z * CELL + CELL * 0.5)
			if p.distance_to(_spawn_pos) < CELL * min_cells:
				continue
			candidates.append(p)

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

	var pickup_count := mini(8 if (GameState and GameState.difficulty == GameState.Difficulty.EASY) else 6, maxi(0, candidates.size() / 4))
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
		if d.global_position.distance_to(target) < CELL * 0.85 or d.global_position.distance_to(pos) < CELL * 0.9:
			if d.has_method("try_open"):
				return d.try_open()
	return false
