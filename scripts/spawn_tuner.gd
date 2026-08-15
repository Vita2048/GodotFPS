extends Node3D
## Visual tool to place the player spawn on the Duke Nukem FBX level.
## Run this scene (F6 or Project → Run Specific Scene → spawn_tuner.tscn).
##
## Controls:
##   Left-click floor — place spawn
##   Mouse drag       — orbit camera
##   Wheel            — zoom
##   W/Z A/D          — nudge XZ (Shift = faster)
##   Q / E            — lower / raise
##   [ / ]            — rotate yaw
##   F                — snap Y to floor under marker
##   G                — look-at marker
##   S                — save (game uses this on next play)
##   C                — copy Vector3 to clipboard
##   R                — reset to auto-detected spawn
##   Esc              — quit tuner

const FbxLevel := preload("res://scripts/fbx_level.gd")
const SpawnRes := preload("res://scripts/player_spawn.gd")

var _level: Node3D
var _spawn: PlayerSpawn
var _auto_pos := Vector3.ZERO

var _marker: Node3D
var _arrow: MeshInstance3D
var _cam_pivot: Node3D
var _camera: Camera3D
var _orbit_yaw := 40.0
var _orbit_pitch := -28.0
var _orbit_dist := 18.0
var _dragging := false
var _last_mouse := Vector2.ZERO

var _spin_pos: Array[SpinBox] = []
var _spin_yaw: SpinBox
var _chk_enabled: CheckBox
var _lbl_status: Label
var _updating_ui := false


func _ready() -> void:
	_spawn = SpawnRes.load_or_default()
	_build_world()
	_load_level()
	_build_marker()
	_build_ui()
	if _spawn.enabled:
		_apply_marker_from_spawn()
	else:
		_spawn.position = _auto_pos
		_apply_marker_from_spawn()
	_focus_camera_on_marker()
	_sync_ui()
	print("[SpawnTuner] Click the floor to place spawn. S to save.")


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.76, 0.8)
	e.ambient_light_energy = 1.15
	e.fog_enabled = false
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-40, 120, 0)
	add_child(sun)

	_cam_pivot = Node3D.new()
	_cam_pivot.name = "CamPivot"
	add_child(_cam_pivot)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 800.0
	_camera.fov = 70.0
	_cam_pivot.add_child(_camera)
	_update_camera()


func _load_level() -> void:
	_level = FbxLevel.new()
	_level.name = "FbxLevel"
	add_child(_level)
	if not _level.load_map("E1L2"):
		_lbl_warn("Failed to load Level.fbx")
		return
	# Physics rays need a frame after collision is added.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if _level.has_method("snap_spawns_to_floor"):
		_level.snap_spawns_to_floor(get_world_3d())
	_auto_pos = _level.spawn_pos
	print("[SpawnTuner] auto spawn=", _auto_pos)


func _build_marker() -> void:
	_marker = Node3D.new()
	_marker.name = "SpawnMarker"
	add_child(_marker)

	var capsule := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.6
	capsule.mesh = cap
	capsule.position = Vector3(0, 0.8, 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.15, 0.95, 0.35, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	capsule.material_override = mat
	_marker.add_child(capsule)

	# Facing arrow (player looks -Z in Godot).
	_arrow = MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.35, 0.12, 0.7)
	_arrow.mesh = prism
	_arrow.position = Vector3(0, 1.55, -0.55)
	_arrow.rotation_degrees = Vector3(90, 180, 0)
	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.albedo_color = Color(1.0, 0.85, 0.1)
	amat.no_depth_test = true
	_arrow.material_override = amat
	_marker.add_child(_arrow)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.52
	ring.mesh = torus
	ring.position = Vector3(0, 0.04, 0)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(1.0, 0.2, 0.15)
	rmat.no_depth_test = true
	ring.material_override = rmat
	_marker.add_child(ring)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(320, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var title := Label.new()
	title.text = "SPAWN TUNER"
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)

	_chk_enabled = CheckBox.new()
	_chk_enabled.text = "Use this spawn in game"
	_chk_enabled.toggled.connect(_on_enabled)
	v.add_child(_chk_enabled)

	for axis in ["X", "Y", "Z"]:
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = axis
		lab.custom_minimum_size.x = 20
		row.add_child(lab)
		var spin := SpinBox.new()
		spin.min_value = -500.0
		spin.max_value = 500.0
		spin.step = 0.05
		spin.custom_arrow_step = 0.1
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_on_spin_changed)
		row.add_child(spin)
		v.add_child(row)
		_spin_pos.append(spin)

	var yaw_row := HBoxContainer.new()
	var yaw_l := Label.new()
	yaw_l.text = "Yaw"
	yaw_l.custom_minimum_size.x = 32
	yaw_row.add_child(yaw_l)
	_spin_yaw = SpinBox.new()
	_spin_yaw.min_value = -180.0
	_spin_yaw.max_value = 180.0
	_spin_yaw.step = 1.0
	_spin_yaw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_yaw.value_changed.connect(_on_spin_changed)
	yaw_row.add_child(_spin_yaw)
	v.add_child(yaw_row)

	var btns := HBoxContainer.new()
	btns.add_child(_mk_btn("Save (S)", _save))
	btns.add_child(_mk_btn("Snap floor (F)", _snap_floor))
	btns.add_child(_mk_btn("Auto (R)", _reset_auto))
	v.add_child(btns)

	_lbl_status = Label.new()
	_lbl_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_status.custom_minimum_size.x = 290
	_lbl_status.text = "Click a floor to place the green capsule.\nW/Z A/D nudge · Q/E height · [/] yaw · S save"
	v.add_child(_lbl_status)


func _mk_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_orbit_dist = clampf(_orbit_dist * 0.88, 3.0, 120.0)
			_update_camera()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_orbit_dist = clampf(_orbit_dist * 1.14, 3.0, 120.0)
			_update_camera()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _try_place_at_mouse():
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			_last_mouse = mb.position
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_orbit_yaw -= mm.relative.x * 0.35
		_orbit_pitch = clampf(_orbit_pitch - mm.relative.y * 0.3, -85.0, -8.0)
		_update_camera()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.physical_keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_S:
				_save()
			KEY_F:
				_snap_floor()
			KEY_G:
				_focus_camera_on_marker()
			KEY_R:
				_reset_auto()
			KEY_C:
				DisplayServer.clipboard_set("Vector3(%.3f, %.3f, %.3f)" % [
					_spawn.position.x, _spawn.position.y, _spawn.position.z
				])
				_status("Copied position to clipboard.")
			KEY_BRACKETLEFT:
				_spawn.yaw_degrees = wrapf(_spawn.yaw_degrees - 15.0, -180.0, 180.0)
				_apply_marker_from_spawn()
				_sync_ui()
			KEY_BRACKETRIGHT:
				_spawn.yaw_degrees = wrapf(_spawn.yaw_degrees + 15.0, -180.0, 180.0)
				_apply_marker_from_spawn()
				_sync_ui()


func _process(delta: float) -> void:
	var step := 6.0 * delta
	if Input.is_key_pressed(KEY_SHIFT):
		step *= 3.0
	var moved := false
	var yaw_rad := deg_to_rad(_orbit_yaw)
	var forward := Vector3(-sin(yaw_rad), 0.0, -cos(yaw_rad))
	var right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
	if Input.is_physical_key_pressed(KEY_W):
		_spawn.position += forward * step
		moved = true
	if Input.is_physical_key_pressed(KEY_Z):
		_spawn.position -= forward * step
		moved = true
	if Input.is_physical_key_pressed(KEY_A):
		_spawn.position -= right * step
		moved = true
	if Input.is_physical_key_pressed(KEY_D):
		_spawn.position += right * step
		moved = true
	if Input.is_physical_key_pressed(KEY_E):
		_spawn.position.y += step
		moved = true
	if Input.is_physical_key_pressed(KEY_Q):
		_spawn.position.y -= step
		moved = true
	if moved:
		_apply_marker_from_spawn()
		_sync_ui()


func _try_place_at_mouse() -> bool:
	var mouse := get_viewport().get_mouse_position()
	# Ignore clicks on the left panel.
	if mouse.x < 340.0 and mouse.y < 420.0:
		return false
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var pos: Vector3 = hit.position
	var nrm: Vector3 = hit.get("normal", Vector3.UP)
	if nrm.y < 0.35:
		_status("Hit a wall — click a floor.")
		return true
	_spawn.position = pos + Vector3(0, 0.4, 0)
	_apply_marker_from_spawn()
	_sync_ui()
	_status("Placed at %s" % _fmt(_spawn.position))
	return true


func _snap_floor() -> void:
	var space := get_world_3d().direct_space_state
	var from := _spawn.position + Vector3(0, 8.0, 0)
	var to := _spawn.position + Vector3(0, -40.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_status("No floor under marker.")
		return
	_spawn.position = (hit.position as Vector3) + Vector3(0, 0.4, 0)
	_apply_marker_from_spawn()
	_sync_ui()
	_status("Snapped to floor %s" % _fmt(_spawn.position))


func _reset_auto() -> void:
	_spawn.position = _auto_pos
	_spawn.yaw_degrees = 0.0
	_apply_marker_from_spawn()
	_sync_ui()
	_status("Reset to auto-detected spawn.")


func _save() -> void:
	_spawn.enabled = _chk_enabled.button_pressed
	var err := SpawnRes.save_spawn(_spawn)
	if err == OK:
		_status("Saved %s  enabled=%s" % [_fmt(_spawn.position), str(_spawn.enabled)])
	else:
		_status("Save failed: %s" % error_string(err))


func _on_enabled(on: bool) -> void:
	_spawn.enabled = on


func _on_spin_changed(_v: float) -> void:
	if _updating_ui:
		return
	_spawn.position = Vector3(_spin_pos[0].value, _spin_pos[1].value, _spin_pos[2].value)
	_spawn.yaw_degrees = _spin_yaw.value
	_apply_marker_from_spawn()


func _apply_marker_from_spawn() -> void:
	if _marker == null:
		return
	_marker.global_position = _spawn.position
	_marker.rotation_degrees = Vector3(0, _spawn.yaw_degrees, 0)


func _sync_ui() -> void:
	if _spin_pos.is_empty():
		return
	_updating_ui = true
	_spin_pos[0].value = _spawn.position.x
	_spin_pos[1].value = _spawn.position.y
	_spin_pos[2].value = _spawn.position.z
	_spin_yaw.value = _spawn.yaw_degrees
	_chk_enabled.button_pressed = _spawn.enabled
	_updating_ui = false


func _focus_camera_on_marker() -> void:
	if _marker:
		_cam_pivot.global_position = _marker.global_position + Vector3(0, 1.0, 0)
	_update_camera()


func _update_camera() -> void:
	if _camera == null:
		return
	var yaw := deg_to_rad(_orbit_yaw)
	var pitch := deg_to_rad(_orbit_pitch)
	var offset := Vector3(
		_orbit_dist * cos(pitch) * sin(yaw),
		_orbit_dist * -sin(pitch),
		_orbit_dist * cos(pitch) * cos(yaw)
	)
	_camera.position = offset
	_camera.look_at(_cam_pivot.global_position, Vector3.UP)


func _status(msg: String) -> void:
	if _lbl_status:
		_lbl_status.text = msg
	print("[SpawnTuner] ", msg)


func _lbl_warn(msg: String) -> void:
	push_warning("[SpawnTuner] " + msg)


func _fmt(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]
