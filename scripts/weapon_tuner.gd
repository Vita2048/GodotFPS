extends Node3D
## Visual tool to align the enemy handgun on the Mixamo right hand.
## Run this scene (F6 or Project → Run Specific Scene → weapon_tuner.tscn).
##
## Controls:
##   Mouse drag     — orbit camera
##   Wheel          — zoom
##   Sliders / spin — pose
##   1–5            — play idle/walk/pistol/shoot/die preview
##   S              — save pose (used by the game)
##   C              — copy GDScript constants to clipboard
##   R              — reset to defaults
##   Esc            — quit tuner

const MODEL_PATH := "res://assets/characters/police.glb"
const WEAPON_PATH := "res://assets/guns/handgun.glb"
const ANIM_PATHS := {
	"walk": "res://assets/characters/Walking.glb",
	"run": "res://assets/characters/Running.glb",
	"pistol_walk": "res://assets/characters/PistolWalk.glb",
	"shoot": "res://assets/characters/Shooting.glb",
	"die": "res://assets/characters/Dying.glb",
}

const PoseScript := preload("res://scripts/enemy_weapon_pose.gd")
var _pose: Resource
var _holder: Node3D
var _gun_root: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _model: Node3D
var _cam_pivot: Node3D
var _camera: Camera3D
var _orbit_yaw := 35.0
var _orbit_pitch := -15.0
var _orbit_dist := 2.2
var _dragging := false
var _last_mouse := Vector2.ZERO

# UI refs
var _lbl_status: Label
var _lbl_code: Label
var _spin_pos: Array[SpinBox] = []
var _spin_rot: Array[SpinBox] = []
var _spin_len: SpinBox
var _updating_ui := false
var _anim_names: Dictionary = {} # key -> full anim path


func _ready() -> void:
	_pose = PoseScript.load_or_default()
	_build_world()
	_build_character()
	_build_ui()
	_sync_ui_from_pose()
	_apply_pose_to_holder()
	_update_camera()
	print("[WeaponTuner] Ready — adjust sliders, press S to save for the game.")


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.8)
	e.ambient_light_energy = 1.2
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.0
	sun.rotation_degrees = Vector3(-40, 40, 0)
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.light_energy = 1.5
	fill.omni_range = 8.0
	fill.position = Vector3(0.5, 1.6, 1.2)
	add_child(fill)

	# Ground grid
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.2, 0.22, 0.25)
	ground.material_override = gmat
	add_child(ground)

	_cam_pivot = Node3D.new()
	_cam_pivot.position = Vector3(0, 1.2, 0)
	add_child(_cam_pivot)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 50.0
	_cam_pivot.add_child(_camera)


func _build_character() -> void:
	var root := Node3D.new()
	root.name = "Character"
	add_child(root)

	if not ResourceLoader.exists(MODEL_PATH):
		push_error("Missing police model")
		return
	_model = (load(MODEL_PATH) as PackedScene).instantiate()
	root.add_child(_model)
	_model.scale = Vector3.ONE * 0.01
	_model.position = Vector3.ZERO

	_skeleton = _find_skeleton(_model)
	_anim = _find_anim_player(_model)
	if _anim == null:
		_anim = AnimationPlayer.new()
		_model.add_child(_anim)
	if _skeleton and _anim.get_parent() != _skeleton.get_parent():
		_anim.reparent(_skeleton.get_parent())

	_import_anims()
	_attach_weapon()
	_prepare_visuals(_model)

	# Start with shoot pose so grip is easy to judge
	if _anim_names.has("shoot"):
		_play_anim("shoot")
	elif _anim_names.has("pistol_walk"):
		_play_anim("pistol_walk")


func _attach_weapon() -> void:
	if _skeleton == null:
		return
	var bone := "mixamorigRightHand"
	if _skeleton.find_bone(bone) < 0:
		for cand in ["mixamorig:RightHand", "RightHand"]:
			if _skeleton.find_bone(cand) >= 0:
				bone = cand
				break

	var attach := BoneAttachment3D.new()
	attach.name = "WeaponAttach"
	attach.bone_name = bone
	_skeleton.add_child(attach)

	_holder = Node3D.new()
	_holder.name = "WeaponHolder"
	attach.add_child(_holder)

	if ResourceLoader.exists(WEAPON_PATH):
		_gun_root = (load(WEAPON_PATH) as PackedScene).instantiate()
	else:
		_gun_root = _make_box_gun()
	_holder.add_child(_gun_root)
	_strip_helpers(_gun_root)
	_prepare_visuals(_gun_root)
	_refit_gun_mesh()


func _refit_gun_mesh() -> void:
	if _gun_root == null:
		return
	_gun_root.position = Vector3.ZERO
	_gun_root.rotation = Vector3.ZERO
	_gun_root.scale = Vector3.ONE
	var aabb := _local_aabb(_gun_root)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest > 0.0001:
		var s: float = float(_pose.get("length_cm")) / longest
		_gun_root.scale = Vector3.ONE * s
		var center: Vector3 = (aabb.position + aabb.size * 0.5) * s
		_gun_root.position = -center


func _apply_pose_to_holder() -> void:
	if _holder == null or _pose == null:
		return
	_holder.position = _pose.get("position") as Vector3
	_holder.rotation_degrees = _pose.get("rotation_degrees") as Vector3
	_refit_gun_mesh()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(360, 0)
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Enemy Weapon Tuner"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var help := Label.new()
	help.text = "Drag mouse = orbit · Wheel = zoom\n1–5 = anims · S = save · C = copy · R = reset · Esc = quit"
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(0.75, 0.8, 0.9)
	vbox.add_child(help)

	vbox.add_child(_section("Position (cm, bone space)"))
	var p0: Vector3 = _pose.get("position") as Vector3
	var r0: Vector3 = _pose.get("rotation_degrees") as Vector3
	var l0: float = float(_pose.get("length_cm"))
	_spin_pos = [
		_add_spin(vbox, "Pos X", -30, 30, 0.1, p0.x, func(v): _set_pos_comp(0, v)),
		_add_spin(vbox, "Pos Y", -30, 30, 0.1, p0.y, func(v): _set_pos_comp(1, v)),
		_add_spin(vbox, "Pos Z", -30, 30, 0.1, p0.z, func(v): _set_pos_comp(2, v)),
	]

	vbox.add_child(_section("Rotation (degrees)"))
	_spin_rot = [
		_add_spin(vbox, "Rot X", -180, 180, 1.0, r0.x, func(v): _set_rot_comp(0, v)),
		_add_spin(vbox, "Rot Y", -180, 180, 1.0, r0.y, func(v): _set_rot_comp(1, v)),
		_add_spin(vbox, "Rot Z", -180, 180, 1.0, r0.z, func(v): _set_rot_comp(2, v)),
	]

	vbox.add_child(_section("Size"))
	_spin_len = _add_spin(vbox, "Length cm", 5, 60, 0.5, l0, func(v):
		_pose.set("length_cm", v)
		_apply_pose_to_holder()
	)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	_add_btn(btn_row, "Save (S)", _save_pose)
	_add_btn(btn_row, "Copy (C)", _copy_constants)
	_add_btn(btn_row, "Reset (R)", _reset_pose)

	var anim_row := HBoxContainer.new()
	vbox.add_child(anim_row)
	_add_btn(anim_row, "1 Idle/Walk", func(): _play_anim("walk"))
	_add_btn(anim_row, "2 Pistol", func(): _play_anim("pistol_walk"))
	_add_btn(anim_row, "3 Shoot", func(): _play_anim("shoot"))
	_add_btn(anim_row, "4 Run", func(): _play_anim("run"))
	_add_btn(anim_row, "5 Die", func(): _play_anim("die"))

	_lbl_status = Label.new()
	_lbl_status.text = "Pose loaded from resources/enemy_weapon_pose.tres"
	_lbl_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_status.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_lbl_status)

	_lbl_code = Label.new()
	_lbl_code.name = "CodePreview"
	_lbl_code.add_theme_font_size_override("font_size", 11)
	_lbl_code.modulate = Color(0.6, 1.0, 0.7)
	_lbl_code.text = _format_constants()
	vbox.add_child(_lbl_code)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.modulate = Color(1.0, 0.85, 0.4)
	return l


func _add_spin(parent: Control, label: String, mn: float, mx: float, step: float, value: float, on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	var spin := SpinBox.new()
	spin.min_value = mn
	spin.max_value = mx
	spin.step = step
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v: float):
		if _updating_ui:
			return
		on_change.call(v)
		_refresh_code_preview()
	)
	row.add_child(spin)
	# Slider under for coarse drag
	var slider := HSlider.new()
	slider.min_value = mn
	slider.max_value = mx
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slider)
	slider.value_changed.connect(func(v: float):
		if _updating_ui:
			return
		spin.value = v
	)
	spin.value_changed.connect(func(v: float):
		if absf(slider.value - v) > 0.0001:
			_updating_ui = true
			slider.value = v
			_updating_ui = false
	)
	return spin


func _add_btn(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _set_pos_comp(i: int, v: float) -> void:
	var p: Vector3 = _pose.get("position") as Vector3
	match i:
		0: p.x = v
		1: p.y = v
		2: p.z = v
	_pose.set("position", p)
	_apply_pose_to_holder()


func _set_rot_comp(i: int, v: float) -> void:
	var r: Vector3 = _pose.get("rotation_degrees") as Vector3
	match i:
		0: r.x = v
		1: r.y = v
		2: r.z = v
	_pose.set("rotation_degrees", r)
	_apply_pose_to_holder()


func _sync_ui_from_pose() -> void:
	_updating_ui = true
	var p: Vector3 = _pose.get("position") as Vector3
	var r: Vector3 = _pose.get("rotation_degrees") as Vector3
	var l: float = float(_pose.get("length_cm"))
	if _spin_pos.size() == 3:
		_spin_pos[0].value = p.x
		_spin_pos[1].value = p.y
		_spin_pos[2].value = p.z
	if _spin_rot.size() == 3:
		_spin_rot[0].value = r.x
		_spin_rot[1].value = r.y
		_spin_rot[2].value = r.z
	if _spin_len:
		_spin_len.value = l
	_updating_ui = false
	_refresh_code_preview()


func _refresh_code_preview() -> void:
	if _lbl_code:
		_lbl_code.text = _format_constants()


func _format_constants() -> String:
	var p: Vector3 = _pose.get("position") as Vector3
	var r: Vector3 = _pose.get("rotation_degrees") as Vector3
	var l: float = float(_pose.get("length_cm"))
	return "position = Vector3(%.2f, %.2f, %.2f)\nrotation_degrees = Vector3(%.1f, %.1f, %.1f)\nlength_cm = %.1f" % [
		p.x, p.y, p.z, r.x, r.y, r.z, l,
	]


func _save_pose() -> void:
	var err: int = PoseScript.save_pose(_pose)
	if err == OK:
		_lbl_status.text = "Saved → res://resources/enemy_weapon_pose.tres\n(Game enemies load this automatically)"
		_lbl_status.modulate = Color(0.5, 1.0, 0.6)
		print("[WeaponTuner] Saved pose:\n", _format_constants())
	else:
		_lbl_status.text = "Save failed: %s" % error_string(err)
		_lbl_status.modulate = Color(1, 0.4, 0.4)


func _copy_constants() -> void:
	var text := _format_constants()
	DisplayServer.clipboard_set(text)
	_lbl_status.text = "Copied to clipboard:\n" + text
	_lbl_status.modulate = Color(0.7, 0.9, 1.0)


func _reset_pose() -> void:
	_pose = PoseScript.new()
	_sync_ui_from_pose()
	_apply_pose_to_holder()
	_lbl_status.text = "Reset to defaults (not saved yet)"
	_lbl_status.modulate = Color(1, 0.9, 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_last_mouse = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_orbit_dist = maxf(0.6, _orbit_dist * 0.9)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_orbit_dist = minf(8.0, _orbit_dist * 1.1)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_orbit_yaw -= mm.relative.x * 0.4
		_orbit_pitch = clampf(_orbit_pitch - mm.relative.y * 0.4, -80.0, 80.0)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.physical_keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_S:
				_save_pose()
			KEY_C:
				_copy_constants()
			KEY_R:
				_reset_pose()
			KEY_1:
				_play_anim("walk")
			KEY_2:
				_play_anim("pistol_walk")
			KEY_3:
				_play_anim("shoot")
			KEY_4:
				_play_anim("run")
			KEY_5:
				_play_anim("die")
			# Fine position nudge (hold Shift for larger steps)
			KEY_A:
				_nudge_pos(Vector3(-1.0 if k.shift_pressed else -0.25, 0, 0))
			KEY_D:
				_nudge_pos(Vector3(1.0 if k.shift_pressed else 0.25, 0, 0))
			KEY_W:
				_nudge_pos(Vector3(0, 0, -1.0 if k.shift_pressed else -0.25))
			KEY_X:
				_nudge_pos(Vector3(0, 0, 1.0 if k.shift_pressed else 0.25))
			KEY_Q:
				_nudge_pos(Vector3(0, 1.0 if k.shift_pressed else 0.25, 0))
			KEY_E:
				_nudge_pos(Vector3(0, -1.0 if k.shift_pressed else -0.25, 0))
			# Rotation nudge
			KEY_I:
				_nudge_rot(Vector3(-15.0 if k.shift_pressed else -5.0, 0, 0))
			KEY_O:
				_nudge_rot(Vector3(15.0 if k.shift_pressed else 5.0, 0, 0))
			KEY_J:
				_nudge_rot(Vector3(0, -15.0 if k.shift_pressed else -5.0, 0))
			KEY_L:
				_nudge_rot(Vector3(0, 15.0 if k.shift_pressed else 5.0, 0))
			KEY_U:
				_nudge_rot(Vector3(0, 0, -15.0 if k.shift_pressed else -5.0))
			KEY_P:
				_nudge_rot(Vector3(0, 0, 15.0 if k.shift_pressed else 5.0))


func _nudge_pos(d: Vector3) -> void:
	var p: Vector3 = _pose.get("position") as Vector3
	_pose.set("position", p + d)
	_sync_ui_from_pose()
	_apply_pose_to_holder()


func _nudge_rot(d: Vector3) -> void:
	var r: Vector3 = _pose.get("rotation_degrees") as Vector3
	_pose.set("rotation_degrees", r + d)
	_sync_ui_from_pose()
	_apply_pose_to_holder()


func _update_camera() -> void:
	if _camera == null or _cam_pivot == null:
		return
	_cam_pivot.rotation_degrees = Vector3(_orbit_pitch, _orbit_yaw, 0)
	_camera.position = Vector3(0, 0, _orbit_dist)
	_camera.look_at(_cam_pivot.global_position)


func _import_anims() -> void:
	if _anim == null or _skeleton == null:
		return
	var lib := AnimationLibrary.new()
	var lib_name := &"tuner"
	if _anim.has_animation_library(lib_name):
		_anim.remove_animation_library(lib_name)
	for key in ANIM_PATHS.keys():
		var path: String = ANIM_PATHS[key]
		if not ResourceLoader.exists(path):
			continue
		var temp := (load(path) as PackedScene).instantiate()
		var src := _find_anim_player(temp)
		if src == null:
			temp.queue_free()
			continue
		for anim_name in src.get_animation_list():
			var clip: Animation = src.get_animation(anim_name).duplicate(true)
			if key == "shoot" or key == "die":
				clip.loop_mode = Animation.LOOP_NONE
			else:
				clip.loop_mode = Animation.LOOP_LINEAR
			_retarget_tracks(clip)
			_strip_hip_pos(clip)
			var safe := "%s__clip" % key
			lib.add_animation(safe, clip)
			_anim_names[key] = "tuner/%s" % safe
		temp.queue_free()
	_anim.add_animation_library(lib_name, lib)


func _retarget_tracks(anim: Animation) -> void:
	var skel_path := _anim.get_path_to(_skeleton)
	if String(skel_path).is_empty() or String(skel_path).begins_with(".."):
		skel_path = NodePath(_skeleton.name)
	for i in anim.get_track_count():
		var path := String(anim.track_get_path(i))
		var bone := path
		if path.contains(":"):
			bone = path.substr(path.find(":") + 1)
		bone = bone.get_file().replace("mixamorig:", "mixamorig")
		var resolved := bone.replace(":", "")
		if _skeleton.find_bone(resolved) < 0:
			var compact := resolved.replace("_", "").to_lower()
			resolved = ""
			for bi in _skeleton.get_bone_count():
				var bn := _skeleton.get_bone_name(bi)
				if bn.replace(":", "").replace("_", "").to_lower() == compact:
					resolved = bn
					break
		if resolved == "":
			continue
		anim.track_set_path(i, NodePath("%s:%s" % [String(skel_path), resolved]))


func _strip_hip_pos(anim: Animation) -> void:
	for i in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var p := String(anim.track_get_path(i)).to_lower()
		if "hips" in p or "root" in p:
			anim.remove_track(i)


func _play_anim(key: String) -> void:
	if _anim == null or not _anim_names.has(key):
		if _lbl_status:
			_lbl_status.text = "Anim not available: %s" % key
		return
	var name: String = _anim_names[key]
	_anim.play(name)
	if _lbl_status:
		_lbl_status.text = "Playing: %s" % key
		_lbl_status.modulate = Color(0.85, 0.9, 1.0)


func _find_skeleton(root: Node) -> Skeleton3D:
	var nodes := root.find_children("*", "Skeleton3D", true, false)
	return nodes[0] as Skeleton3D if nodes.size() > 0 else null


func _find_anim_player(root: Node) -> AnimationPlayer:
	var nodes := root.find_children("*", "AnimationPlayer", true, false)
	return nodes[0] as AnimationPlayer if nodes.size() > 0 else null


func _strip_helpers(root: Node) -> void:
	var to_free: Array[Node] = []
	for n in root.find_children("*", "", true, false):
		if n is Camera3D or n is Light3D:
			to_free.append(n)
	for n in to_free:
		n.queue_free()


func _prepare_visuals(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		gi.layers = 1
		gi.extra_cull_margin = 2.0
		gi.custom_aabb = AABB(Vector3(-2, 0, -2), Vector3(4, 3, 4))
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat is StandardMaterial3D:
					var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					sm.cull_mode = BaseMaterial3D.CULL_DISABLED
					sm.albedo_color = Color(1.25, 1.25, 1.3)
					sm.metallic = minf(sm.metallic, 0.4)
					sm.emission_enabled = true
					if sm.albedo_texture:
						sm.emission_texture = sm.albedo_texture
						sm.emission = Color(1, 1, 1)
						sm.emission_energy_multiplier = 0.25
						sm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
					mi.set_surface_override_material(s, sm)


func _local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var a := vi.get_aabb()
		var xf: Transform3D
		if root.is_inside_tree() and vi.is_inside_tree():
			xf = root.global_transform.affine_inverse() * vi.global_transform
		else:
			xf = Transform3D.IDENTITY
			var cur: Node = vi
			while cur != null and cur != root:
				if cur is Node3D:
					xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
		for c in [xf * a.position, xf * (a.position + a.size)]:
			if first:
				result = AABB(c, Vector3.ZERO)
				first = false
			else:
				result = result.expand(c)
	if first:
		return AABB(Vector3(-0.1, -0.05, -0.2), Vector3(0.2, 0.1, 0.4))
	return result


func _make_box_gun() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.1, 0.25)
	mi.mesh = box
	root.add_child(mi)
	return root
