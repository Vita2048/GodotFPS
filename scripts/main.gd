extends Node3D

@onready var level: LevelGenerator = $Level
@onready var player: Player = $Player
@onready var entities: Node3D = $Entities
@onready var title_ui: Control = $UI/TitleUI
@onready var world_env: WorldEnvironment = $WorldEnvironment
var doom

func _ready() -> void:
	# Prefer fullscreen so the game fills the monitor (toggle with F11).
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if world_env:
		world_env.add_to_group("world_env")
	_setup_environment()
	# Apply Low quality after env exists (also runs from autoload, this refreshes env refs)
	if QualitySettings:
		QualitySettings.apply(QualitySettings.Quality.MEDIUM)
	if GameState:
		GameState.set_difficulty(GameState.Difficulty.EASY)
	if title_ui:
		title_ui.start_pressed.connect(_on_start)
		if title_ui.has_signal("difficulty_changed"):
			title_ui.difficulty_changed.connect(_on_difficulty_changed)
	get_tree().set_meta("fps_campaign", true)
	doom = preload("res://scripts/doom_level.gd").new()
	doom.name = "DoomLevel"
	add_child(doom)
	doom.setup(self)
	if doom.map_count() > 0:
		GameState.max_sectors = doom.map_count()
	if title_ui and title_ui.has_method("set_maps"):
		title_ui.set_maps(doom.map_names)
	_build_level()
	if player:
		player.set_level(level)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()
	elif event.is_action_pressed("difficulty_cycle"):
		# Menu only — do not retarget mid-fight
		if _can_change_difficulty():
			GameState.cycle_difficulty()
			_build_level()


func _can_change_difficulty() -> bool:
	return not GameState.game_started or GameState.player_dead or (title_ui != null and title_ui.visible and not player._active)


func _on_difficulty_changed() -> void:
	if _can_change_difficulty():
		_build_level()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	if ResourceLoader.exists("res://assets/textures/mountains_sky.jpg"):
		sky_mat.panorama = load("res://assets/textures/mountains_sky.jpg")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.18
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssil_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.58, 0.62)
	env.fog_density = 0.0014
	env.fog_aerial_perspective = 0.35
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.06
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.08
	if world_env:
		world_env.environment = env

	var sun := get_node_or_null("FillSun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "FillSun"
		add_child(sun)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.55
	sun.rotation_degrees = Vector3(-28, 130, 0)
	sun.shadow_enabled = false


func _build_level() -> void:
	for c in entities.get_children():
		c.queue_free()
	if level:
		level.visible = false
		for c in level.get_children():
			c.queue_free()

	var spawn := Vector3(0, 1, 0)
	var enemy_pts: Array[Vector3] = []
	var pick_pts: Array = []
	if doom and doom.load_index(GameState.current_sector - 1):
		GameState.current_map_name = doom.current_map_name
		spawn = doom.spawn_pos
		enemy_pts = doom.enemy_spawns
		pick_pts = doom.pickup_spawns
	else:
		if level.has_method("configure_for_sector"):
			level.configure_for_sector(GameState.current_sector)
		level.visible = true
		level.generate()
		spawn = level._spawn_pos
		enemy_pts = level._enemy_spawns
		pick_pts = level._pickup_spawns

	player.global_position = spawn + Vector3(0, 0.15, 0)
	player.velocity = Vector3.ZERO
	if player.has_method("clear_inventory"):
		player.clear_inventory()

	var model_pool: Array[String] = [
		"res://assets/characters/police.glb",
		"res://assets/characters/swat.fbx",
		"res://assets/characters/Alex.fbx",
		"res://assets/characters/Swat1.fbx",
	]
	var usable: Array[String] = []
	for path in model_pool:
		if ResourceLoader.exists(path):
			usable.append(path)
	if usable.is_empty():
		usable.append("res://assets/characters/police.glb")

	usable.shuffle()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for p in enemy_pts:
		var e := Enemy.new()
		e.model_path = usable[rng.randi_range(0, usable.size() - 1)]
		e.position = Vector3(p.x, p.y, p.z)
		entities.add_child(e)

	for item in pick_pts:
		var pk := Pickup.new()
		pk.pickup_type = item["type"]
		if item.has("key_name"):
			pk.key_name = String(item["key_name"])
		pk.position = item["pos"] + Vector3(0, 0.35, 0)
		entities.add_child(pk)

	await get_tree().process_frame
	if has_node("Player/HUD") and player.hud.has_method("_on_enemies"):
		player.hud._on_enemies(GameState.enemies_alive)
	if has_node("Player/HUD") and player.hud.has_method("_on_sector"):
		player.hud._on_sector(GameState.current_sector, GameState.max_sectors)


func _on_start() -> void:
	var btn_text := ""
	if title_ui and title_ui.start_btn:
		btn_text = title_ui.start_btn.text
	var restarting := GameState.player_dead or btn_text in ["RESTART", "PLAY AGAIN", "NEXT SECTOR"]
	if restarting:
		if btn_text == "NEXT SECTOR":
			GameState.advance_sector()
			var kept_score := GameState.score
			GameState.reset(true)
			GameState.score = kept_score
			GameState.score_changed.emit(GameState.score)
		else:
			if title_ui and title_ui.has_method("selected_map_index"):
				GameState.current_sector = title_ui.selected_map_index() + 1
			else:
				GameState.current_sector = 1
			GameState.reset(true)
			GameState.score = 0
			GameState.score_changed.emit(0)
		_build_level()
	elif not GameState.game_started:
		if title_ui and title_ui.has_method("selected_map_index"):
			GameState.current_sector = title_ui.selected_map_index() + 1
		GameState.reset(true)
		_build_level()
		var count := 0
		for c in entities.get_children():
			if c is Enemy:
				count += 1
		GameState.enemies_alive = count
		if player and player.hud:
			player.hud._on_enemies(GameState.enemies_alive)
			player.hud._on_health(GameState.health)
			player.hud._on_ammo(GameState.mag, GameState.reserve_ammo)
			player.hud._on_score(GameState.score)
			if player.hud.has_method("_on_sector"):
				player.hud._on_sector(GameState.current_sector, GameState.max_sectors)
	GameState.game_started = true
	GameState.paused = false
	player.activate()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if not GameState.level_cleared.is_connected(_on_level_cleared):
		GameState.level_cleared.connect(_on_level_cleared)


func _on_level_cleared() -> void:
	await get_tree().create_timer(1.0).timeout
	GameState.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player._active = false
		player._fire_held = false
	if GameState.current_sector < GameState.max_sectors:
		if title_ui and title_ui.has_method("show_sector_clear"):
			title_ui.show_sector_clear(GameState.current_sector, GameState.max_sectors)
	else:
		if title_ui and title_ui.has_method("show_win"):
			title_ui.show_win()
