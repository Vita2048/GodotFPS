extends Node3D

@onready var level: LevelGenerator = $Level
@onready var player: Player = $Player
@onready var entities: Node3D = $Entities
@onready var title_ui: Control = $UI/TitleUI
@onready var world_env: WorldEnvironment = $WorldEnvironment

func _ready() -> void:
	# Prefer fullscreen so the game fills the monitor (toggle with F11).
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if world_env:
		world_env.add_to_group("world_env")
	_setup_environment()
	# Apply Low quality after env exists (also runs from autoload, this refreshes env refs)
	if QualitySettings:
		QualitySettings.apply(QualitySettings.Quality.LOW)
	if title_ui:
		title_ui.start_pressed.connect(_on_start)
		if title_ui.controls:
			title_ui.controls.text += "\nF10 Quality  |  F11 Fullscreen  |  Q Quit"
	_build_level()
	if player:
		player.set_level(level)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.018, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.32, 0.42)
	env.ambient_light_energy = 0.75 # brighter ambient so we can use fewer omni lights
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	# Heavy effects off by default — QualitySettings enables them on Medium/High
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.glow_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.12)
	env.fog_density = 0.016
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = false
	if world_env:
		world_env.environment = env

	var sun := DirectionalLight3D.new()
	sun.name = "FillSun"
	sun.light_color = Color(0.55, 0.65, 0.9)
	sun.light_energy = 0.25
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = false
	add_child(sun)


func _build_level() -> void:
	for c in entities.get_children():
		c.queue_free()
	level.generate()
	# Wait one frame for generation_finished if connected; we call spawns directly
	var spawn: Vector3 = level._spawn_pos
	player.global_position = spawn + Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO

	for p in level._enemy_spawns:
		var e := Enemy.new()
		# Floor top is y=0; CharacterBody origin at ground
		e.position = Vector3(p.x, 0.0, p.z)
		entities.add_child(e)
		print("[Main] enemy at ", e.position)

	for item in level._pickup_spawns:
		var pk := Pickup.new()
		pk.pickup_type = item["type"]
		pk.position = item["pos"] + Vector3(0, 0.0, 0)
		entities.add_child(pk)

	# Update enemy count label after spawns
	await get_tree().process_frame
	if has_node("Player/HUD") and player.hud.has_method("_on_enemies"):
		player.hud._on_enemies(GameState.enemies_alive)


func _on_start() -> void:
	if GameState.player_dead or (title_ui and title_ui.start_btn and title_ui.start_btn.text in ["RESTART", "PLAY AGAIN"]):
		GameState.reset(true)
		_build_level()
	elif not GameState.game_started:
		# Keep pre-built level and enemy registrations; only refresh player stats.
		GameState.reset(false)
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
	GameState.game_started = true
	player.activate()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if not GameState.level_cleared.is_connected(_on_level_cleared):
		GameState.level_cleared.connect(_on_level_cleared)


func _on_level_cleared() -> void:
	await get_tree().create_timer(1.2).timeout
	if title_ui and title_ui.has_method("show_win"):
		title_ui.show_win()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player._active = false
