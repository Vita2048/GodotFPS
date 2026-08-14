extends CharacterBody3D
class_name Player

@export var walk_speed: float = 5.5
@export var sprint_speed: float = 8.5
@export var jump_speed: float = 5.2
@export var mouse_sens: float = 0.0025
@export var bob_amount: float = 0.03
@export var bob_speed: float = 10.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_anchor: Node3D = $Head/Camera3D/WeaponAnchor
@onready var shoot_ray: RayCast3D = $Head/Camera3D/ShootRay
@onready var hurt_overlay: ColorRect = $HUD/HurtOverlay
@onready var hud: CanvasLayer = $HUD

var _weapon: WeaponViewmodel
var _pitch: float = 0.0
var _yaw: float = 0.0
var _bob_t: float = 0.0
var _hurt_flash: float = 0.0
var _level: LevelGenerator
var _active: bool = false
var _fire_held: bool = false
## Read by GodotWadImporter door / switch / exit triggers.
var interactPressed: bool = false

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(62.0)
	floor_stop_on_slope = false
	floor_constant_speed = true
	floor_block_on_wall = false
	if not InputMap.has_action("jump"):
		InputMap.add_action("jump")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_SPACE
		InputMap.action_add_event("jump", ev)

	_weapon = WeaponViewmodel.new()
	_weapon.name = "Weapon"
	weapon_anchor.add_child(_weapon)
	_weapon.reload_finished.connect(_on_reload_finished)

	shoot_ray.target_position = Vector3(0, 0, -80)
	shoot_ray.collision_mask = 1 | 4
	shoot_ray.enabled = true

	# World on layer 1, viewmodel on layer 2 — both drawn by the main camera (no SubViewport).
	# SubViewport overlays were eating mouse events and could letterbox the game view.
	camera.cull_mask = 1 | 2
	camera.current = true
	camera.far = 800.0
	_set_viewmodel_no_depth_clip(_weapon)

	# Soft flashlight so nearby enemies/textures stay lit
	var torch := OmniLight3D.new()
	torch.name = "Flashlight"
	torch.light_color = Color(1.0, 0.95, 0.88)
	torch.light_energy = 1.4
	torch.omni_range = 14.0
	torch.omni_attenuation = 1.1
	torch.shadow_enabled = false
	torch.position = Vector3(0.15, -0.05, -0.2)
	camera.add_child(torch)

	GameState.player_died.connect(_on_player_died)

	if hurt_overlay:
		hurt_overlay.color = Color(0.8, 0, 0, 0)
		hurt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# HUD must never steal mouse while playing
	_ignore_mouse_on_controls(hud)


func _set_viewmodel_no_depth_clip(root: Node) -> void:
	# Keep gun on layer 2; slightly disable depth test via render priority so walls rarely eat it.
	if root is VisualInstance3D:
		var vi := root as VisualInstance3D
		vi.layers = 2
		vi.sorting_offset = 10.0
	for c in root.get_children():
		_set_viewmodel_no_depth_clip(c)


func _ignore_mouse_on_controls(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_ignore_mouse_on_controls(c)


func activate() -> void:
	_active = true
	_fire_held = false
	GameState.paused = false
	# Capture must happen after the UI click is fully processed
	call_deferred("_capture_mouse")


func _capture_mouse() -> void:
	if not _active or GameState.player_dead:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_viewport().gui_release_focus()


func set_level(level: LevelGenerator) -> void:
	_level = level


## Use _input (not _unhandled_input) so look/shoot still work if a Control had focus.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen_toggle"):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	if not _active or GameState.player_dead or GameState.paused:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_fire_held = false
		return

	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * mouse_sens
		_pitch -= mm.relative.y * mouse_sens
		_pitch = clampf(_pitch, deg_to_rad(-85.0), deg_to_rad(85.0))
		rotation.y = _yaw
		head.rotation.x = _pitch
		get_viewport().set_input_as_handled()
		return

	# Hold LMB for continuous fire
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_fire_held = mb.pressed
			if mb.pressed:
				_try_shoot()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("reload"):
		if _weapon:
			_weapon.try_reload()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_menu"):
		_pause_game()
		get_viewport().set_input_as_handled()


func _pause_game() -> void:
	_fire_held = false
	_active = false
	GameState.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var ui := get_tree().get_first_node_in_group("title_ui")
	if ui and ui.has_method("show_paused"):
		ui.show_paused()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _physics_process(delta: float) -> void:
	interactPressed = _active and not GameState.player_dead and not GameState.paused and Input.is_action_pressed("interact")
	if not _active or GameState.player_dead or GameState.paused:
		_fire_held = false
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Full-auto while LMB held (also tracks OS button state if focus returned)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_fire_held = true
	else:
		_fire_held = false
	if _fire_held:
		_try_shoot()

	# Re-assert capture if something stole the cursor (alt-tab recovery on click)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		_bob_t += delta * bob_speed * (speed / walk_speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_speed
	elif not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	if direction != Vector3.ZERO:
		_try_step_up(direction)

	if _weapon and is_instance_valid(_weapon):
		var bob_y := sin(_bob_t) * bob_amount if direction != Vector3.ZERO else 0.0
		var bob_x := cos(_bob_t * 0.5) * bob_amount * 0.5 if direction != Vector3.ZERO else 0.0
		var target := WeaponViewmodel.GUN_POS + Vector3(bob_x, bob_y, 0)
		_weapon.position = _weapon.position.lerp(target, clampf(delta * 12.0, 0.0, 1.0))

	if _hurt_flash > 0.0:
		_hurt_flash = maxf(0.0, _hurt_flash - delta * 3.0)
		if hurt_overlay:
			hurt_overlay.color.a = _hurt_flash * 0.45


func _try_shoot() -> void:
	if _weapon == null:
		return
	if not _weapon.try_fire():
		return
	Enemy.broadcast_gunshot(self, global_position, 24.0)
	shoot_ray.force_raycast_update()
	if shoot_ray.is_colliding():
		var collider := shoot_ray.get_collider()
		var hit_pos := shoot_ray.get_collision_point()
		var hit_n := shoot_ray.get_collision_normal()
		var enemy := _find_enemy(collider)
		if enemy and enemy.has_method("take_damage"):
			enemy.take_damage(28, hit_pos)
			SFX.play_2d(self, "hit", -8.0)
		else:
			_spawn_impact(hit_pos, hit_n)


func _find_enemy(node: Node) -> Node:
	var n := node
	while n:
		if n.is_in_group("enemy"):
			return n
		n = n.get_parent()
	return null


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var decal := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	decal.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 2.0
	decal.material_override = mat
	decal.position = pos + normal * 0.02
	get_tree().current_scene.add_child(decal)
	var tw := create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.2)
	tw.tween_callback(decal.queue_free).set_delay(2.5)


func _try_step_up(dir: Vector3) -> void:
	## Lift over short risers if the ramp is missed. Capsules cannot stair-step.
	if not is_on_wall():
		return
	var forward := Vector3(dir.x, 0.0, dir.z).normalized() * 0.28
	if not test_move(global_transform, forward):
		return
	var lift := 0.42
	var raised := global_transform.translated(Vector3(0, lift, 0))
	if test_move(raised, forward):
		return
	global_position.y += lift
	global_position += forward * 0.12


func _try_interact() -> void:
	interactPressed = true
	if _level != null and _level.has_method("try_open_door_near"):
		var dir := -camera.global_transform.basis.z
		_level.try_open_door_near(global_position, dir)


func _on_reload_finished() -> void:
	if _weapon:
		_weapon.apply_reload_ammo()


func take_hit(amount: int) -> void:
	GameState.apply_damage(amount)
	_hurt_flash = 1.0
	SFX.play_2d(self, "hurt", -2.0)
	var tw := create_tween()
	tw.tween_property(camera, "rotation:z", deg_to_rad(1.5), 0.04)
	tw.tween_property(camera, "rotation:z", 0.0, 0.12)


func _on_player_died() -> void:
	_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var ui := get_tree().get_first_node_in_group("title_ui")
	if ui and ui.has_method("show_dead"):
		ui.show_dead()
