extends Node3D
## Run: Godot --headless --path . res://tests/showcase_smoke.tscn
## Omit --headless to also capture rendered previews into build/validation.
var failures := 0
var game: Node3D
var player: Player

class BlastTarget extends Node3D:
	var health := 1000
	func take_damage(amount: int, _point: Vector3) -> void:
		health -= amount

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _ready() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	player = game.player
	player.set_physics_process(false)
	player.set_process_input(false)
	game.title_ui.hide()
	GameState.game_started = true
	GameState.paused = false
	for enemy in get_tree().get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
	await frames(5)
	check(QualitySettings.level == QualitySettings.Quality.LOW, "game defaults to Low rendering")
	if DisplayServer.get_name() != "headless" and not "--full" in OS.get_cmdline_user_args():
		await previews()
		get_tree().quit()
		return
	var blast_visual := preload("res://scripts/blast_effect.gd").new()
	game.add_child(blast_visual)
	blast_visual.set_process(false)
	blast_visual._process(0.12)
	check(blast_visual.lobes[0].visible and not blast_visual.clouds[0].visible, "explosion starts with fire before smoke on Low")
	GameState.paused = true
	blast_visual._process(0.5)
	check(is_equal_approx(blast_visual.elapsed, 0.12), "explosion animation pauses with menu")
	GameState.paused = false
	blast_visual._process(0.7)
	check(not blast_visual.lobes[0].visible and blast_visual.clouds[0].visible, "explosion fire gives way to delayed smoke")
	blast_visual._process(1.2)
	await frames(1)
	check(not is_instance_valid(blast_visual), "explosion effect cleans itself up")
	var facility := get_tree().get_first_node_in_group("facility")
	check(facility != null, "facility constructed")
	var map := get_world_3d().navigation_map
	var route := NavigationServer3D.map_get_path(map, Vector3(24, 0, 39), Vector3(24, 4.2, -2), true)
	check(route.size() > 2 and route[-1].distance_to(Vector3(24, 4.2, -2)) < 1, "ground-to-balcony navigation path")
	for entry in [[Vector3(14.5, 0.15, 31.5), Vector3(0, 0, -1)], [Vector3(33.5, 0.15, 16.5), Vector3(0, 0, 1)]]:
		player.position = entry[0]
		player.velocity = Vector3.ZERO
		for i in 205:
			await get_tree().physics_frame
			player.velocity.x = 0
			player.velocity.z = entry[1].z * 5
			player.velocity.y -= 9.8 / 60
			player.move_and_slide()
		check(player.position.y > 4.1, "walk up stair flight at x=" + str(entry[0].x))
		print("STAIR END ", player.position)
	var lift := get_tree().get_first_node_in_group("interactable")
	player.position = Vector3(8, 0.15, 32)
	player.velocity = Vector3.ZERO
	for i in 15:
		await get_tree().physics_frame
		player.velocity = Vector3(0, -1, 0)
		player.move_and_slide()
	lift.interact(player.position)
	for i in 190:
		await get_tree().physics_frame
		player.velocity = Vector3(0, -1, 0)
		player.move_and_slide()
	check(not lift.moving and absf(lift.platform.position.y - 4.2) < 0.01, "lift reaches upper floor")
	check(player.position.y > 4.1, "lift carries standing player")
	print("LIFT RIDER ", player.position)
	check(lift.gate.collision_layer == 0, "upper landing gate opens on arrival")
	lift.interact(Vector3(8, 0, 35))
	await frames(190)
	check(lift.platform.position.y < 0.01 and lift.gate.collision_layer == 1, "remote call returns lift and secures shaft")
	player.position = Vector3(24, 0.1, 40)
	player.velocity = Vector3.ZERO
	# A hidden target across the operations partition must not take blast damage.
	var open_target := BlastTarget.new()
	var hidden_target := BlastTarget.new()
	var far_target := BlastTarget.new()
	for target in [open_target, hidden_target, far_target]:
		add_child(target)
		target.add_to_group("reactive")
	open_target.position = Vector3(10, 1, 4)
	hidden_target.position = Vector3(13, 1, 4)
	far_target.position = Vector3(6, 1, 4)
	preload("res://scripts/explosive.gd").blast(self, Vector3(11, 1, 4), 6, 120)
	check(open_target.health < far_target.health and far_target.health < 1000, "blast damage falls off with distance")
	check(hidden_target.health == 1000, "wall blocks blast damage")
	for target in [open_target, hidden_target, far_target]: target.queue_free()
	# Swept rocket hits the floor at speed, grenades bounce and freeze during menus.
	var grenade := preload("res://scripts/explosive.gd").new()
	game.add_child(grenade)
	grenade.position = Vector3(24, 1, 38)
	grenade.velocity = Vector3(0, -6, 0)
	await frames(15)
	check(is_instance_valid(grenade) and grenade.position.y > 0, "grenade bounces above floor")
	GameState.paused = true
	var fuse: float = grenade.remaining
	await frames(10)
	check(grenade.remaining == fuse, "grenade fuse pauses with menu")
	GameState.paused = false
	await frames(170)
	check(not is_instance_valid(grenade), "grenade detonates after fuse")
	GameState.health = 10000
	GameState.player_dead = false
	var rocket := preload("res://scripts/explosive.gd").new()
	rocket.rocket = true
	game.add_child(rocket)
	rocket.position = Vector3(24, 1, 38)
	rocket.velocity = Vector3(0, -400, 0)
	await frames(3)
	check(not is_instance_valid(rocket), "fast rocket cannot tunnel through floor")
	# Exercise all surface effects and pooled reuse beyond pool capacity.
	var surface := StaticBody3D.new()
	add_child(surface)
	for i in 110:
		surface.set_meta("surface_kind", ["concrete", "brick", "metal", "wood", "glass", "plaster", "tile", "rubber"][i % 8])
		ImpactFX.spawn(Vector3(24, 0.05, 20), Vector3.UP, surface)
	check(ImpactFX._decals.size() == 96, "impact pool remains bounded after sustained fire")
	surface.queue_free()
	for prop in get_tree().get_nodes_in_group("reactive"):
		if prop.get("kind") == "lamp":
			prop.take_damage(28, prop.global_position)
			check(not prop.lamp.visible, "shootable lamp switches off")
			break
	var props: Array = get_tree().get_nodes_in_group("reactive").filter(func(p): return p.get("kind") == "barrel")
	if props.size() > 1:
		props[0].freeze = true
		props[1].freeze = true
		props[0].position = Vector3(20, 0.65, 38)
		props[1].position = Vector3(21.5, 0.65, 38)
		await frames(2)
		props[0].take_damage(100, Vector3(20, 0.65, 39))
		await frames(5)
		check(not is_instance_valid(props[0]) and not is_instance_valid(props[1]), "explosive canisters chain react")
	if DisplayServer.get_name() != "headless":
		await previews()
	var runner := get_tree().get_nodes_in_group("enemy")[0] as Enemy
	runner.position = Vector3(24, 0.1, 39)
	runner._aware = true
	runner.sight_range = 0
	runner.attack_range = 0
	runner.melee_range = 0
	player.position = Vector3(24, 4.3, -2)
	GameState.player_dead = false
	for i in 1800:
		await get_tree().physics_frame
		runner._physics_process(1.0 / 60.0)
		if runner.position.distance_to(player.position) < 1.5: break
	check(runner.position.distance_to(player.position) < 1.5, "enemy follows navigation up stairs to balcony")
	print("CHASE END ", runner.position)
	print("CHASE NEXT ", runner._navigator.get_next_path_position(), " PATH ", runner._navigator.get_current_navigation_path())
	GameState.rockets = 3
	GameState.grenades = 4
	player._select_weapon(1)
	player._fire_rocket()
	player._fire_rocket()
	check(GameState.rockets == 2 and player._launcher.visible and not player._weapon.visible, "RPG selection, ammo consumption and cooldown")
	player._throw_grenade()
	player._throw_grenade()
	check(GameState.grenades == 3, "grenade input consumes once during cooldown")
	# Restart flushes projectiles; second sector keeps the procedural campaign.
	game._build_level()
	await frames(4)
	check(get_tree().get_nodes_in_group("facility").size() == 1, "restart replaces facility without duplicates")
	check(get_tree().get_nodes_in_group("transient_combat").is_empty(), "restart clears projectiles and blast effects")
	check(GameState.enemies_alive == game.level._enemy_spawns.size(), "rebuild enemy count matches live spawns")
	check(not ImpactFX._decals.any(func(d): return d.visible), "restart clears old impact marks")
	GameState.reset()
	check(GameState.grenades == 4 and GameState.rockets == 3 and GameState.selected_weapon == 0, "restart restores loadout")
	GameState.current_sector = 2
	game._build_level()
	await frames(4)
	check(get_tree().get_nodes_in_group("facility").is_empty() and not game.level.grid.is_empty(), "second sector retains procedural campaign")
	print("SMOKE RESULT: ", failures, " failures")
	get_tree().quit(1 if failures else 0)

func previews() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/validation")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	QualitySettings.apply(QualitySettings.Quality.HIGH)
	game.title_ui.hide()
	player.hud.hide()
	player._weapon.hide()
	player._launcher.hide()
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.current = true
	camera.fov = 78
	for view in [["atrium", Vector3(24, 2, 32), Vector3(24, 3, 15)], ["gallery", Vector3(29, 5.8, 14), Vector3(20, 2, 28)], ["terrace", Vector3(22, 5.8, -1), Vector3(22, 5.8, -20)]]:
		camera.position = view[1]
		camera.look_at(view[2])
		await frames(8)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/validation/%s.png" % view[0])
	player.position = Vector3(24, 0.1, 32)
	player.camera.current = true
	player.hud.show()
	player._select_weapon(1)
	await frames(8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/validation/rpg.png")
	player.hud.hide()
	player._launcher.hide()
	camera.current = true
	var facility := get_tree().get_first_node_in_group("facility")
	var surfaces := ["concrete", "brick", "metal", "wood", "glass", "plaster", "tile", "rubber"]
	for i in surfaces.size():
		var pos := Vector3(23 + (i % 4), 21 + (i / 4), 20)
		var panel: MeshInstance3D = facility.box(pos, Vector3(0.92, 0.9, 0.1), surfaces[i])
		facility.sign_text(surfaces[i].to_upper(), pos + Vector3(0, 0.34, 0.08), 0, 12)
		for offset in [Vector3(-0.2, -0.1, 0.06), Vector3(0.15, 0.0, 0.06)]:
			ImpactFX.spawn(pos + offset, Vector3.BACK, panel.get_child(0))
	camera.position = Vector3(24.5, 21.5, 23.2)
	camera.look_at(Vector3(24.5, 21.5, 20))
	camera.fov = 50
	await frames(12)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/validation/impacts.png")
	await ordnance_previews(camera)

func ordnance_previews(camera: Camera3D) -> void:
	QualitySettings.apply(QualitySettings.Quality.LOW)
	var models := preload("res://scripts/ordnance_models.gd")
	var display := Node3D.new()
	game.add_child(display)
	display.position = Vector3(24, 1.2, 31)
	for i in 3:
		var root := Node3D.new()
		display.add_child(root)
		root.position.x = (i - 1) * 0.9
		root.rotation.y = -0.3
		if i == 0:
			models.ammo(root)
		elif i == 1:
			root.scale = Vector3.ONE * 2
			models.grenade(root)
		else:
			root.scale = Vector3.ONE * 1.3
			models.rocket(root)
		var label := Label3D.new()
		label.text = ["RIFLE AMMO", "GRENADE", "ROCKET"][i]
		label.font_size = 26
		label.pixel_size = 0.004
		label.position = Vector3((i - 1) * 0.9, -0.46, 0)
		display.add_child(label)
	camera.position = Vector3(24, 2.1, 33.8)
	camera.look_at(Vector3(24, 1.3, 31))
	camera.fov = 55
	await frames(8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/validation/ordnance-low.png")
	display.queue_free()
	camera.position = Vector3(24, 2.4, 31)
	camera.look_at(Vector3(24, 1.1, 23))
	var explosion := preload("res://scripts/blast_effect.gd").new()
	game.add_child(explosion)
	explosion.position = Vector3(24, 1.1, 23)
	for stage in ["flash", "fireball", "dissipation"]:
		await frames(6 if stage != "dissipation" else 17)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/validation/explosion-%s-low.png" % stage)
