extends Node3D
## Deliberately connected two-storey facility. Dimensions are metres.

const UPPER := 4.2
var mats: Dictionary
var world: Node3D
var level: Node3D
var nav: NavigationRegion3D

func build(owner_level: Node3D) -> void:
	level = owner_level
	mats = level._mats.duplicate()
	_materials()
	world = Node3D.new()
	world.name = "Architecture"
	add_child(world)
	_shell()
	_galleries()
	_stair(Vector3(14.5, 0, 30), -1.0)
	_stair(Vector3(33.5, 0, 18), 1.0)
	_rooms()
	_details()
	_spawns()
	var lift := preload("res://scripts/facility_lift.gd").new()
	lift.position = Vector3(8, 0, 32)
	add_child(lift)
	nav = NavigationRegion3D.new()
	nav.name = "FacilityNavigation"
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.25
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	nav.navigation_mesh = mesh
	add_child(nav)
	remove_child(world)
	nav.add_child(world)
	nav.bake_navigation_mesh(false)
	add_to_group("facility")

func _materials() -> void:
	for spec in [["plaster", Color("c1c6bc"), 0.86, 0.0], ["painted_metal", Color("23474c"), 0.42, 0.55], ["rubber", Color("252c2d"), 0.96, 0.0], ["tile", Color("87948d"), 0.36, 0.0], ["copper", Color("b17045"), 0.32, 0.8]]:
		var m := StandardMaterial3D.new()
		m.resource_name = spec[0]
		m.albedo_color = spec[1]
		m.roughness = spec[2]
		m.metallic = spec[3]
		mats[spec[0]] = m
	# World-aligned metres prevent stretching large walls and floor slabs.
	for key in ["concrete", "brick", "wood", "metal"]:
		var m := mats[key].duplicate() as StandardMaterial3D
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * (0.4 if key != "wood" else 0.8)
		mats[key] = m
	# Fine stone grain on plaster and rubber; tile joints at a human scale.
	for key in ["plaster", "rubber"]:
		var m := mats[key] as StandardMaterial3D
		m.normal_enabled = true
		m.normal_texture = (mats["concrete"] as StandardMaterial3D).normal_texture
		m.normal_scale = 0.2
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE
	var tile := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var joint := x < 2 or y < 2
			var grain := float((x * 17 + y * 31) % 13) / 500.0
			tile.set_pixel(x, y, Color(0.23, 0.27, 0.26) if joint else Color(0.68 + grain, 0.73 + grain, 0.69 + grain))
	(mats["tile"] as StandardMaterial3D).albedo_texture = ImageTexture.create_from_image(tile)
	(mats["tile"] as StandardMaterial3D).uv1_triplanar = true
	(mats["tile"] as StandardMaterial3D).uv1_world_triplanar = true
	(mats["tile"] as StandardMaterial3D).uv1_scale = Vector3.ONE * 1.5

func box(pos: Vector3, size: Vector3, material: String, solid: bool = true, parent: Node3D = null) -> MeshInstance3D:
	var host := parent if parent != null else world
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mats[material]
	mi.position = pos
	host.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.set_meta("surface_kind", material)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		mi.add_child(body)
	return mi

func _shell() -> void:
	box(Vector3(24, -8, 22), Vector3(280, 2, 280), "rubber", false)
	box(Vector3(24, -0.22, 22), Vector3(48, 0.44, 44), "concrete")
	box(Vector3(24, 4.05, -2.5), Vector3(20, 0.3, 5), "concrete")
	# Walls with a broad upper opening onto the observation terrace.
	box(Vector3(0, 4.5, 22), Vector3(0.4, 9, 44), "brick")
	box(Vector3(48, 4.5, 22), Vector3(0.4, 9, 44), "brick")
	box(Vector3(24, 4.5, 44), Vector3(48, 9, 0.4), "plaster")
	box(Vector3(24, 2, 0), Vector3(48, 4, 0.4), "concrete")
	box(Vector3(10, 6.5, 0), Vector3(20, 5, 0.4), "plaster")
	box(Vector3(38, 6.5, 0), Vector3(20, 5, 0.4), "plaster")
	box(Vector3(24, 8.6, 0), Vector3(8, 0.8, 0.4), "painted_metal")
	for x in [6.0, 42.0]:
		box(Vector3(x, 9, 22), Vector3(12, 0.35, 44), "plaster")
	for z in [6.0, 39.0]:
		box(Vector3(24, 9, z), Vector3(24, 0.35, 12 if z == 6.0 else 10), "plaster")
	# Glazed atrium roof and visible steel trusses.
	box(Vector3(24, 9.1, 23), Vector3(24, 0.12, 22), "glass")
	for z in [12.0, 18.0, 24.0, 30.0, 34.0]:
		box(Vector3(24, 8.7, z), Vector3(24, 0.3, 0.18), "painted_metal", false)
	for x in [12.0, 36.0]:
		for z in [12.0, 34.0]:
			box(Vector3(x, 4.3, z), Vector3(0.5, 8.6, 0.5), "concrete")
	_rail(Vector3(14, UPPER, -5), Vector3(34, UPPER, -5))
	_rail(Vector3(14, UPPER, -5), Vector3(14, UPPER, 0))
	_rail(Vector3(34, UPPER, -5), Vector3(34, UPPER, 0))

func _galleries() -> void:
	# Continuous north/south galleries and side wings, with a lift aperture.
	box(Vector3(24, 4.05, 6), Vector3(48, 0.3, 12), "concrete")
	box(Vector3(24, 4.05, 39), Vector3(48, 0.3, 10), "concrete")
	box(Vector3(42, 4.05, 23), Vector3(12, 0.3, 22), "concrete")
	box(Vector3(6, 4.05, 21), Vector3(12, 0.3, 18), "concrete")
	box(Vector3(3, 4.05, 32), Vector3(6, 0.3, 4), "concrete")
	box(Vector3(11, 4.05, 32), Vector3(2, 0.3, 4), "concrete")
	box(Vector3(24, 4.05, 14.5), Vector3(24, 0.3, 5), "concrete")
	box(Vector3(24, 4.05, 32), Vector3(24, 0.3, 4), "concrete")
	# Stair wells remain open above the flights.
	box(Vector3(14.5, 4.05, 17.5), Vector3(5, 0.3, 1), "concrete")
	box(Vector3(33.5, 4.05, 17.5), Vector3(5, 0.3, 1), "concrete")
	_rail(Vector3(17, UPPER, 17), Vector3(31, UPPER, 17))
	_rail(Vector3(17, UPPER, 30), Vector3(31, UPPER, 30))
	# Guard both edges of each open stairwell at gallery height.
	for x in [12.0, 17.0, 31.0, 36.0]:
		_rail(Vector3(x, UPPER, 18), Vector3(x, UPPER, 30))
	# Lift aperture has guards on three sides; access is from the south landing.
	_rail(Vector3(6, UPPER, 30), Vector3(10, UPPER, 30))
	_rail(Vector3(6, UPPER, 30), Vector3(6, UPPER, 34))
	_rail(Vector3(10, UPPER, 30), Vector3(10, UPPER, 34))

func _rail(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var side := absf(a.x - b.x) > absf(a.z - b.z)
	for h in [0.5, 1.1]:
		box((a + b) * 0.5 + Vector3.UP * h, Vector3(length, 0.07, 0.07) if side else Vector3(0.07, 0.07, length), "painted_metal", false)
	for i in range(int(ceil(length / 2)) + 1):
		var t := float(i) / ceilf(length / 2)
		box(a.lerp(b, t) + Vector3.UP * 0.55, Vector3(0.08, 1.1, 0.08), "painted_metal", false)
	# Invisible solid glass-height blocker keeps characters from slipping between bars.
	var guard := box((a + b) * 0.5 + Vector3.UP * 0.55, Vector3(length, 1.1, 0.08) if side else Vector3(0.08, 1.1, length), "metal")
	guard.visible = false

func _stair(base: Vector3, direction: float) -> void:
	const STEPS := 28
	for i in STEPS:
		var rise := UPPER * float(i + 1) / STEPS
		var z := direction * (float(i) + 0.5) * 12.0 / STEPS
		box(base + Vector3(0, rise * 0.5, z), Vector3(3.8, rise, 12.0 / STEPS), "concrete", false)
		box(base + Vector3(0, rise + 0.006, z - direction * 0.18), Vector3(3.8, 0.012, 0.06), "warning", false)
	# Smooth convex ramp under the visible treads, usable by player and navigation.
	var body := StaticBody3D.new()
	body.set_meta("surface_kind", "concrete")
	var shape := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for x in [-1.9, 1.9]:
		pts.append(base + Vector3(x, -0.15, 0))
		pts.append(base + Vector3(x, 0.0, 0))
		pts.append(base + Vector3(x, UPPER, direction * 12))
		pts.append(base + Vector3(x, -0.15, direction * 12))
	shape.points = pts
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	world.add_child(body)
	for x in [-2.0, 2.0]:
		for i in 7:
			var t := float(i) / 6.0
			box(base + Vector3(x, UPPER * t + 0.5, direction * 12 * t), Vector3(0.06, 1, 0.06), "painted_metal", false)
		var bar := box(base + Vector3(x, UPPER * 0.5 + 1, direction * 6), Vector3(0.07, 0.07, sqrt(144 + UPPER * UPPER)), "painted_metal", false)
		bar.rotation.x = -direction * atan(UPPER / 12.0)

func _rooms() -> void:
	# Wide doorways keep both circulation loops readable and navigable.
	for x in [12.0, 36.0]:
		for z in [4.0, 22.0, 40.0]:
			box(Vector3(x, 1.95, z), Vector3(0.25, 3.9, 8), "plaster" if x == 12 else "brick")
			box(Vector3(x, 6.25, z), Vector3(0.25, 4.1, 8), "plaster")
	for x in [6.0, 42.0]:
		for z in [14.0, 30.0]:
			box(Vector3(x - 4, 1.95, z), Vector3(4, 3.9, 0.25), "plaster")
			box(Vector3(x + 4, 1.95, z), Vector3(4, 3.9, 0.25), "plaster")
	# Material zoning, thresholds, and durable skirting.
	for spec in [[Vector3(6, 0.012, 7), Vector3(11.5, 0.024, 13), "wood"], [Vector3(42, 0.012, 7), Vector3(11.5, 0.024, 13), "rubber"], [Vector3(42, 0.012, 22), Vector3(11.5, 0.024, 15), "tile"]]:
		box(spec[0], spec[1], spec[2])
	for x in [0.25, 47.75]:
		box(Vector3(x, 0.2, 22), Vector3(0.08, 0.4, 44), "painted_metal", false)
	for z in [11.5, 34.5]:
		box(Vector3(24, 0.015, z), Vector3(18, 0.03, 0.12), "warning", false)

func sign_text(text: String, pos: Vector3, yaw: float = 0.0, size: int = 64) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.008
	label.modulate = Color("daf0d8")
	label.outline_size = 5
	label.position = pos
	label.rotation.y = yaw
	world.add_child(label)

func _details() -> void:
	sign_text("NORTH RIDGE / RESEARCH STATION", Vector3(24, 7.4, 0.3))
	sign_text("01   ATRIUM", Vector3(24, 3.1, 11.9))
	sign_text("OBSERVATION TERRACE", Vector3(24, 7.8, 0.4), 0, 44)
	sign_text("WORKSHOP  /  02", Vector3(35.8, 2.7, 22), -PI * 0.5, 40)
	sign_text("OPERATIONS  /  03", Vector3(12.2, 2.7, 4), PI * 0.5, 40)
	sign_text("FREIGHT LIFT   [E]", Vector3(8, 2.7, 30), 0, 36)
	sign_text("FREIGHT LIFT   [E]", Vector3(8, 6.9, 30), 0, 36)
	sign_text("ARMORY   /   GRENADES + ROCKETS", Vector3(42, 2.8, 30.2), 0, 28)
	for y in [0.0, UPPER]:
		for z in [7.0, 22.0, 39.0]:
			for x in [6.0, 42.0]:
				box(Vector3(x, y + 3.4, z), Vector3(3, 0.12, 0.3), "emissive", false)
				var light := OmniLight3D.new()
				light.position = Vector3(x, y + 3, z)
				light.light_color = Color("ffe2af") if x == 6 else Color("b5e1ed")
				light.light_energy = 1.1
				light.omni_range = 9
				add_child(light)
	for z in [14.0, 32.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(24, 7, z)
		light.light_color = Color("dfedff")
		light.light_energy = 2.2
		light.omni_range = 18
		add_child(light)
	# Workbenches, server racks, ductwork, and storage arranged along room edges.
	for z in [17.0, 23.0, 27.0]:
		level._add_workbench(world, Vector3(45.5, 0, z), PI * 0.5)
	for z in [3.0, 7.0, 11.0]:
		box(Vector3(45.5, 1.2, z), Vector3(1.2, 2.4, 1.7), "painted_metal")
		for h in [0.5, 1.0, 1.5, 2.0]:
			box(Vector3(44.88, h, z), Vector3(0.03, 0.07, 1.3), "emissive", false)
	for z in [4.0, 10.0]:
		level._add_table_set(world, Vector3(5, 0, z), 0)
	for pos in [Vector3(5, UPPER, 7), Vector3(43, UPPER, 7), Vector3(42, UPPER, 27)]:
		level._add_workbench(world, pos, 0)
	# Reception counter and timber slat backdrop anchor the far end of the atrium.
	box(Vector3(24, 0.6, 10), Vector3(7, 1.2, 1.2), "painted_metal")
	box(Vector3(24, 1.24, 10), Vector3(7.2, 0.08, 1.4), "wood")
	for x in range(19, 30):
		box(Vector3(x, 1.6, 7.2), Vector3(0.12, 3.2, 0.16), "wood")
	box(Vector3(24, 3.3, 7.2), Vector3(11, 0.12, 0.4), "emissive", false)
	# Repeating wall bands tie the room palette and upper gallery together.
	for x in [0.24, 47.76]:
		for y in [1.1, 5.3]:
			box(Vector3(x, y, 22), Vector3(0.06, 0.25, 43), "painted_metal", false)
	for x in [18.0, 30.0]:
		box(Vector3(x, UPPER + 0.35, -2.3), Vector3(1.5, 0.7, 1.5), "painted_metal")
		# Compact architectural planters stay below the mountain sightline.
		for i in 5:
			box(Vector3(x - 0.45 + i * 0.22, UPPER + 1.0, -2.3), Vector3(0.14, 0.7, 0.35), "rubber", false)
	# Upper operations glazing overlooks the atrium; the lower opening stays clear.
	box(Vector3(12, 6.2, 16), Vector3(0.10, 2.6, 3.5), "glass")
	box(Vector3(12, 4.7, 16), Vector3(0.18, 1.0, 3.5), "painted_metal")
	for pos in [Vector3(4, 0, 20), Vector3(4, 0, 26), Vector3(44, 0, 38), Vector3(4, UPPER, 20)]:
		level._add_crate_stack(world, pos)
	for x in [2.0, 46.0]:
		box(Vector3(x, 3.3, 22), Vector3(0.4, 0.4, 43), "copper")
	# Low cover in the atrium leaves the central axis and stair approaches clear.
	for pos in [Vector3(21, 0.55, 21), Vector3(27, 0.55, 27)]:
		box(pos, Vector3(3.5, 1.1, 1.1), "concrete")
		box(pos + Vector3(0, 0.59, 0), Vector3(3.6, 0.08, 1.2), "wood")
	for pos in [Vector3(39, 0, 24), Vector3(29, 0, 15), Vector3(4, 0, 23), Vector3(40, UPPER, 24)]:
		var prop := preload("res://scripts/reactive_prop.gd").new()
		prop.position = pos + Vector3.UP * 0.65
		add_child(prop)
	for pos in [Vector3(19, 2.7, 12), Vector3(29, 2.7, 34)]:
		var lamp := preload("res://scripts/reactive_prop.gd").new()
		lamp.kind = "lamp"
		lamp.position = pos
		add_child(lamp)
	for pos in [Vector3(39, 0.45, 20), Vector3(10, 0.45, 24)]:
		var crate := preload("res://scripts/reactive_prop.gd").new()
		crate.kind = "crate"
		crate.position = pos
		add_child(crate)

func _spawns() -> void:
	level._spawn_pos = Vector3(24, 0.1, 40)
	var points: Array[Vector3] = [Vector3(40, 0, 25), Vector3(6, 0, 22), Vector3(24, 0, 16), Vector3(42, 0, 8), Vector3(6, 0, 6), Vector3(42, 0, 39), Vector3(22, UPPER, 9), Vector3(40, UPPER, 22), Vector3(6, UPPER, 20), Vector3(26, UPPER, 32), Vector3(30, 0, 23), Vector3(24, UPPER, -2), Vector3(42, UPPER, 38), Vector3(7, UPPER, 7), Vector3(40, 0, 18), Vector3(20, UPPER, 14)]
	var count := mini(GameState.enemy_count_cap(), points.size())
	for i in count:
		level._enemy_spawns.append(points[i] + Vector3.UP * 0.1)
	for spec in [[Vector3(22, 0, 38), "grenade"], [Vector3(26, 0, 38), "rocket"], [Vector3(42, 0, 34), "rocket"], [Vector3(40, 0, 34), "grenade"], [Vector3(5, 0, 11), "health"], [Vector3(24, UPPER, -3), "health"], [Vector3(7, UPPER, 25), "ammo"], [Vector3(26, 0, 10), "ammo"]]:
		level._pickup_spawns.append({"pos": spec[0], "type": spec[1]})
