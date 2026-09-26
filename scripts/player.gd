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
var _launcher: Node3D
var _rocket_cd := 0.0
var _grenade_cd := 0.0

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
	_build_launcher()

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
	_select_weapon(GameState.selected_weapon)
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
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: _select_weapon(0)
			KEY_2: _select_weapon(1)
			KEY_G: _throw_grenade()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_fire_held = mb.pressed
			if mb.pressed:
				_try_shoot()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("reload"):
		if _weapon and GameState.selected_weapon == 0:
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
	if not _active or GameState.player_dead or GameState.paused:
		_fire_held = false
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Full-auto while LMB held (also tracks OS button state if focus returned)
	_rocket_cd = maxf(0, _rocket_cd - delta)
	_grenade_cd = maxf(0, _grenade_cd - delta)
	_launcher.position = _launcher.position.lerp(Vector3(0.28, -0.25, -0.55), delta * 8)
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
	if global_position.y < -6.0:
		take_hit(GameState.health)
		return
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
	if GameState.selected_weapon == 1:
		_fire_rocket()
		return
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
			if collider.has_method("take_damage"):
				collider.take_damage(28, hit_pos)
				ImpactFX.spawn(hit_pos, hit_n, collider)
				return
			var prop := _find_shatterable(collider)
			if prop and prop.has_method("shatter"):
				prop.shatter(hit_pos, hit_n)
			else:
				ImpactFX.spawn(hit_pos, hit_n, collider)


func _find_enemy(node: Node) -> Node:
	var n := node
	while n:
		if n.is_in_group("enemy"):
			return n
		n = n.get_parent()
	return null


func _find_shatterable(node: Node) -> Node:
	var n := node
	while n:
		if n.is_in_group("shatterable"):
			return n
		n = n.get_parent()
	return null


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
	for item in get_tree().get_nodes_in_group("interactable"):
		if item.interaction_text(global_position) != "":
			item.interact(global_position)
			return
	if _level == null:
		return
	var dir := -camera.global_transform.basis.z
	_level.try_open_door_near(global_position, dir)


func _select_weapon(index: int) -> void:
	if _weapon and _weapon._reloading: return
	GameState.selected_weapon = index
	_weapon.visible = index == 0
	_launcher.visible = index == 1


func _build_launcher() -> void:
	_launcher = Node3D.new()
	camera.add_child(_launcher)
	_launcher.position = Vector3(0.28, -0.25, -0.55)
	_launcher.visible = false
	# Layered tube, collars, wooden heat shield, grip, and iron sights.
	for spec in [[0.075, 1.0, 0.1, Color("293c32")], [0.09, 0.4, 0.18, Color("80593a")], [0.10, 0.08, -0.38, Color("343d3d")], [0.11, 0.12, 0.55, Color("343d3d")]]:
		var mesh := MeshInstance3D.new()
		var tube := CylinderMesh.new()
		tube.top_radius = spec[0]
		tube.bottom_radius = spec[0]
		tube.height = spec[1]
		mesh.mesh = tube
		mesh.rotation.x = PI * 0.5
		mesh.position.z = spec[2]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[3]
		mat.roughness = 0.72
		mat.metallic = 0.45
		if spec[1] == 0.4:
			mat.albedo_texture = load("res://assets/textures/wood_diff.jpg")
			mat.albedo_color = Color(0.5, 0.45, 0.38)
			mat.metallic = 0
		mesh.material_override = mat
		_launcher.add_child(mesh)
	for pos in [Vector3(0, -0.13, 0.2), Vector3(0, 0.11, -0.27)]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.045, 0.17, 0.06)
		mesh.mesh = box
		mesh.position = pos
		var sight_material := StandardMaterial3D.new()
		sight_material.albedo_color = Color("1c2323")
		sight_material.roughness = 0.7
		mesh.material_override = sight_material
		_launcher.add_child(mesh)
	var warhead := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.018
	cone.bottom_radius = 0.105
	cone.height = 0.28
	warhead.mesh = cone
	warhead.rotation.x = -PI * 0.5
	warhead.position.z = -0.53
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color("677140")
	olive.metallic = 0.4
	olive.roughness = 0.45
	warhead.material_override = olive
	_launcher.add_child(warhead)
	_set_viewmodel_no_depth_clip(_launcher)


func _launch(rocket: bool) -> void:
	var projectile := preload("res://scripts/explosive.gd").new()
	projectile.rocket = rocket
	projectile.source = self
	var direction := -camera.global_basis.z
	projectile.velocity = direction * (38.0 if rocket else 13.0) + (Vector3.ZERO if rocket else Vector3.UP * 3)
	get_parent().add_child(projectile)
	# Start at the camera: the first sweep tests nearby walls rather than spawning through them.
	projectile.global_position = camera.global_position


func _fire_rocket() -> void:
	if _rocket_cd > 0: return
	if GameState.rockets <= 0:
		_rocket_cd = 0.4
		SFX.play_2d(self, "empty", -9)
		return
	GameState.rockets -= 1
	_rocket_cd = 1.8
	_launch(true)
	_launcher.position.z += 0.17
	SFX.play_2d(self, "rocket", -3)


func _throw_grenade() -> void:
	if _grenade_cd > 0 or GameState.grenades <= 0: return
	GameState.grenades -= 1
	_grenade_cd = 0.8
	_launch(false)
	SFX.play_2d(self, "grenade_bounce", -12)


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
