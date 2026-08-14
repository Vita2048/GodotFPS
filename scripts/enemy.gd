extends CharacterBody3D
class_name Enemy
## Police enemy: cleverly combines FBX animation clips (walk / run / pistol-walk / shoot / die).

enum State { IDLE, CHASE, ATTACK, DEAD }

@export var max_hp: int = 80
@export var walk_speed: float = 2.2
@export var run_speed: float = 4.0
@export var attack_range: float = 12.0
@export var melee_range: float = 2.2
@export var sight_range: float = 22.0
@export var damage: int = 8
@export var attack_cooldown: float = 1.1

var hp: int
var state: State = State.IDLE
var _player: Node3D
var _model_root: Node3D
var _anim: AnimationPlayer
var _attack_cd: float = 0.0
var _current_anim: String = ""
var _aware: bool = false
var _rng := RandomNumberGenerator.new()
var _patrol_target := Vector3.ZERO
var _patrol_wait: float = 0.0
var _has_patrol_target: bool = false
var _death_base_model_y: float = 0.0
var _death_drop: float = 0.0
var _death_len: float = 1.0
var _corpse_settled: bool = false
var _los_time: float = 0.0
## Surface materials we set in _prepare_meshes (restored after hurt flash / on death)
var _surface_mats: Array = [] # Array of { "mi": MeshInstance3D, "surface": int, "mat": Material }

# Mapped animation names after import/retarget
var anim_idle: String = ""
var anim_walk: String = ""
var anim_run: String = ""
var anim_pistol_walk: String = ""
var anim_shoot: String = ""
var anim_die: String = ""

## Optional override set by the spawner so each enemy can use a different mesh.
@export var model_path: String = ""

# Mixamo-style bodies. Anim clips retarget onto whichever skeleton is present.
const MODEL_PATHS := [
	"res://assets/characters/police.glb",
	"res://assets/characters/swat.fbx",
	"res://assets/characters/Alex.fbx",
	"res://assets/characters/Swat1.fbx",
	"res://assets/characters/swat.glb",
	"res://assets/characters/Alex.glb",
	"res://assets/characters/Swat1.glb",
]
const ANIM_PATHS := {
	"walk": "res://assets/characters/Walking.glb",
	"run": "res://assets/characters/Running.glb",
	"pistol_walk": "res://assets/characters/PistolWalk.glb",
	"shoot": "res://assets/characters/Shooting.glb",
	"die": "res://assets/characters/Dying.glb",
}
## Separate hand weapon (holstered gun is baked into the body mesh and can't be moved).
const WEAPON_PATH := "res://assets/guns/handgun.glb"
## Defaults if resources/enemy_weapon_pose.tres is missing (use Weapon Tuner to edit).
const WEAPON_TARGET_LENGTH_CM := 22.0
const WEAPON_POS := Vector3(6.7, 17.6, 4.5)
const WEAPON_ROT_DEG := Vector3(10.0, -2.0, -92.0)

func _ready() -> void:
	add_to_group("enemy")
	_apply_difficulty_stats()
	hp = max_hp
	collision_layer = 4
	collision_mask = 1
	_rng.randomize()
	GameState.register_enemy()
	_setup_body()
	_load_visuals_and_anims()
	call_deferred("_find_player")
	call_deferred("_unstuck")


func _apply_difficulty_stats() -> void:
	if GameState == null:
		return
	max_hp = GameState.enemy_max_hp()
	damage = GameState.enemy_damage()
	attack_cooldown = GameState.enemy_attack_cooldown()
	sight_range = GameState.enemy_sight_range()
	attack_range = GameState.enemy_attack_range()
	var spd: float = GameState.enemy_speed_scale()
	walk_speed = 2.2 * spd
	run_speed = 4.0 * spd


func _setup_body() -> void:
	var col := get_node_or_null("CollisionShape3D")
	if col == null:
		col = CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.32
		shape.height = 1.6
		col.shape = shape
		# Center at height/2 so the capsule sits on the origin (feet on the floor).
		col.position.y = 0.8
		add_child(col)
	floor_snap_length = 0.55
	floor_max_angle = deg_to_rad(60.0)
	safe_margin = 0.08
	max_slides = 6
	floor_stop_on_slope = false
	floor_constant_speed = true
	floor_block_on_wall = false


func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _load_visuals_and_anims() -> void:
	_model_root = Node3D.new()
	_model_root.name = "Model"
	add_child(_model_root)

	var model: Node3D = null
	var tried: Array[String] = []
	if model_path != "":
		tried.append(model_path)
	for path in MODEL_PATHS:
		if path not in tried:
			tried.append(path)
	for path in tried:
		if not ResourceLoader.exists(path):
			continue
		var ps = load(path)
		if ps is PackedScene:
			model = (ps as PackedScene).instantiate()
			print("[Enemy] loaded model from ", path)
			break
	if model == null:
		push_warning("[Enemy] No character model; using placeholder capsule")
		model = _placeholder_mesh()
	_model_root.add_child(model)
	_fit_character_scale(model)

	_anim = _find_anim_player(model)
	if _anim == null:
		_anim = AnimationPlayer.new()
		_anim.name = "AnimationPlayer"
		model.add_child(_anim)

	# Reparent AnimationPlayer next to Skeleton3D so bone tracks resolve as "Skeleton3D:Bone"
	var skeleton := _find_skeleton(model)
	if skeleton and _anim.get_parent() != skeleton.get_parent():
		var host: Node = skeleton.get_parent()
		_anim.reparent(host)
	elif skeleton and _anim.get_parent() == null:
		skeleton.get_parent().add_child(_anim)

	# Attach a real handgun to the right hand (holster mesh is painted on, not movable)
	if skeleton:
		_attach_hand_weapon(skeleton)

	# Import external clips into our AnimationPlayer (retarget Mixamo colon bones)
	_import_external_anims()
	_resolve_anim_names()
	if anim_idle != "":
		_play(anim_idle, 0.5)
	elif anim_walk != "":
		_play(anim_walk, 0.5)

	# World layer, no shadows; fix skinned-mesh frustum culling (common invisible-enemy cause)
	_set_layers(_model_root, 1)
	_disable_shadows(_model_root)
	_prepare_meshes(_model_root)
	print("[Enemy] spawned at ", global_position, " scale=", model.scale)


func _attach_hand_weapon(skeleton: Skeleton3D) -> void:
	var bone_name := "mixamorigRightHand"
	if skeleton.find_bone(bone_name) < 0:
		for cand in ["mixamorig_RightHand", "mixamorig:RightHand", "RightHand", "Hand_R", "hand_r"]:
			if skeleton.find_bone(cand) >= 0:
				bone_name = cand
				break
	if skeleton.find_bone(bone_name) < 0:
		push_warning("[Enemy] No right-hand bone for weapon attach")
		return

	var attach := BoneAttachment3D.new()
	attach.name = "WeaponAttach"
	attach.bone_name = bone_name
	skeleton.add_child(attach)

	# Pose from Weapon Tuner resource (res://resources/enemy_weapon_pose.tres)
	const WeaponPoseScript = preload("res://scripts/enemy_weapon_pose.gd")
	var pose: Resource = WeaponPoseScript.load_or_default()
	var wpos: Vector3 = WEAPON_POS
	var wrot: Vector3 = WEAPON_ROT_DEG
	var wlen: float = WEAPON_TARGET_LENGTH_CM
	if pose != null:
		wpos = pose.get("position") as Vector3
		wrot = pose.get("rotation_degrees") as Vector3
		wlen = float(pose.get("length_cm"))
		if wlen <= 0.0:
			wlen = WEAPON_TARGET_LENGTH_CM

	var holder := Node3D.new()
	holder.name = "WeaponHolder"
	attach.add_child(holder)
	# Pose is authored in Mixamo-cm space (police.glb). Meter-scale skeletons need 1cm = 0.01m.
	var pose_scale := _skeleton_pose_scale(skeleton)
	holder.position = wpos * pose_scale
	holder.rotation_degrees = wrot

	var gun: Node3D = null
	if ResourceLoader.exists(WEAPON_PATH):
		var ps = load(WEAPON_PATH)
		if ps is PackedScene:
			gun = (ps as PackedScene).instantiate() as Node3D
	if gun == null:
		gun = _make_procedural_pistol()
		print("[Enemy] using procedural pistol fallback")
	else:
		_strip_sketchfab_helpers(gun)
		print("[Enemy] equipped ", WEAPON_PATH, " on ", bone_name, " pose=", wpos, wrot, " len=", wlen)

	holder.add_child(gun)
	gun.position = Vector3.ZERO
	gun.rotation = Vector3.ZERO
	gun.scale = Vector3.ONE

	# Fit gun length in the skeleton's local units (cm or meters).
	var aabb := _weapon_local_aabb(gun)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest > 0.0001:
		var target_len: float = wlen * pose_scale
		var s: float = target_len / longest
		gun.scale = Vector3.ONE * s
		var center: Vector3 = (aabb.position + aabb.size * 0.5) * s
		gun.position = -center

	_set_layers(gun, 1)
	_disable_shadows(gun)
	for n in gun.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		gi.layers = 1
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.extra_cull_margin = 1.5
		gi.custom_aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh == null:
				continue
			for s_i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s_i)
				if mat is StandardMaterial3D:
					var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					sm.cull_mode = BaseMaterial3D.CULL_DISABLED
					sm.metallic = minf(sm.metallic, 0.65)
					sm.roughness = clampf(sm.roughness, 0.25, 0.7)
					sm.albedo_color = Color(1.1, 1.1, 1.12)
					sm.emission_enabled = true
					if sm.albedo_texture:
						sm.emission_texture = sm.albedo_texture
						sm.emission = Color(1, 1, 1)
						sm.emission_energy_multiplier = 0.2
						sm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
					else:
						sm.emission = Color(0.12, 0.12, 0.14)
						sm.emission_energy_multiplier = 0.2
					mi.set_surface_override_material(s_i, sm)


func _strip_sketchfab_helpers(root: Node) -> void:
	var to_free: Array[Node] = []
	for n in root.find_children("*", "", true, false):
		var lname := String(n.name).to_lower()
		if n is Camera3D or n is Light3D:
			to_free.append(n)
		elif lname.begins_with("camera") or lname.begins_with("sun") or lname.begins_with("hemi"):
			to_free.append(n)
	for n in to_free:
		if is_instance_valid(n):
			n.queue_free()


func _weapon_local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var a := vi.get_aabb()
		var xf: Transform3D
		if root.is_inside_tree() and vi.is_inside_tree():
			xf = root.global_transform.affine_inverse() * vi.global_transform
		else:
			xf = _local_xform_to(root, vi)
		var corners := [
			xf * a.position,
			xf * (a.position + Vector3(a.size.x, 0, 0)),
			xf * (a.position + Vector3(0, a.size.y, 0)),
			xf * (a.position + Vector3(0, 0, a.size.z)),
			xf * (a.position + a.size),
		]
		for c in corners:
			if first:
				result = AABB(c, Vector3.ZERO)
				first = false
			else:
				result = result.expand(c)
	if first:
		return AABB(Vector3(-0.1, -0.05, -0.2), Vector3(0.2, 0.1, 0.4))
	return result


func _local_xform_to(root: Node, node: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xform = (cur as Node3D).transform * xform
		cur = cur.get_parent()
	return xform


func _make_procedural_pistol() -> Node3D:
	## Fallback if GLB missing: simple metal sidearm (still bone-attached).
	var root := Node3D.new()
	root.name = "ProceduralPistol"
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.08, 0.22)
	body.mesh = box
	body.position = Vector3(0, 0.02, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.13, 0.15)
	mat.metallic = 0.7
	mat.roughness = 0.3
	body.material_override = mat
	root.add_child(body)
	var grip := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(0.035, 0.1, 0.05)
	grip.mesh = gbox
	grip.position = Vector3(0, -0.04, 0.0)
	grip.material_override = mat
	root.add_child(grip)
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 0.12
	barrel.mesh = cyl
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0.03, 0.2)
	barrel.material_override = mat
	root.add_child(barrel)
	return root


func _prepare_meshes(root: Node) -> void:
	_surface_mats.clear()
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		gi.layers = 1
		gi.visible = true
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Skinned meshes often report a tiny/wrong AABB and get frustum-culled → "invisible but shooting"
		gi.extra_cull_margin = 12.0
		gi.custom_aabb = AABB(Vector3(-3.0, -1.0, -3.0), Vector3(6.0, 5.0, 6.0))
		gi.visibility_range_end = 0.0
		gi.visibility_range_begin = 0.0
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			mi.material_override = null # never leave a solid-color override stuck
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat is StandardMaterial3D:
					var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					sm.cull_mode = BaseMaterial3D.CULL_DISABLED
					# Dark police uniforms read as pure black under sparse lights — lift response
					sm.albedo_color = Color(1.35, 1.35, 1.4) # brighten textured albedo
					sm.metallic = minf(sm.metallic, 0.15)
					sm.roughness = maxf(sm.roughness, 0.55)
					sm.specular = 0.35
					# Bake a little self-illumination from the albedo map so silhouettes stay readable
					sm.emission_enabled = true
					if sm.albedo_texture:
						sm.emission_texture = sm.albedo_texture
						sm.emission = Color(1, 1, 1)
						sm.emission_energy_multiplier = 0.35
						sm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
					else:
						sm.emission = Color(0.25, 0.28, 0.35)
						sm.emission_energy_multiplier = 0.4
					mi.set_surface_override_material(s, sm)
					_surface_mats.append({"mi": mi, "surface": s, "mat": sm})
				elif mat is BaseMaterial3D:
					var bm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					bm.cull_mode = BaseMaterial3D.CULL_DISABLED
					mi.set_surface_override_material(s, bm)
					_surface_mats.append({"mi": mi, "surface": s, "mat": bm})


func _fit_character_scale(model: Node3D) -> void:
	## Police.glb is Mixamo-cm. Godot-imported Mixamo FBX is already meters / Y-up.
	## Do not AABB-fit skinned meshes (bind-pose AABB is often empty or huge).
	var sk := _find_skeleton(model)
	if _skeleton_is_meters(sk):
		model.scale = Vector3.ONE
	else:
		model.scale = Vector3.ONE * 0.01
	# Mixamo soles sit slightly under y=0 — lift so boots aren't buried.
	model.position = Vector3(0.0, 0.05, 0.0)


func _hips_rest_origin(skeleton: Skeleton3D) -> Vector3:
	if skeleton == null or skeleton.get_bone_count() == 0:
		return Vector3.ZERO
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i).to_lower().replace(":", "").replace("_", "")
		if n.ends_with("hips") or n.ends_with("hip"):
			return skeleton.get_bone_rest(i).origin
	return skeleton.get_bone_rest(0).origin


func _skeleton_is_meters(skeleton: Skeleton3D) -> bool:
	## Hips around y=1 → meters. Hips around y=100 → centimeters.
	var o := _hips_rest_origin(skeleton)
	return o.length() < 20.0


func _scale_position_tracks(anim: Animation, factor: float) -> void:
	if anim == null or is_equal_approx(factor, 1.0):
		return
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		for k in anim.track_get_key_count(i):
			var v: Variant = anim.track_get_key_value(i, k)
			if v is Vector3:
				anim.track_set_key_value(i, k, (v as Vector3) * factor)


func _skeleton_pose_scale(skeleton: Skeleton3D) -> float:
	## Weapon Tuner pose is in centimeters.
	return 0.01 if _skeleton_is_meters(skeleton) else 1.0


func _placeholder_mesh() -> Node3D:
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.5
	mi.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.2, 0.45)
	mi.material_override = mat
	mi.position.y = 1.0
	return mi


func _find_anim_player(root: Node) -> AnimationPlayer:
	var nodes := root.find_children("*", "AnimationPlayer", true, false)
	if nodes.size() > 0:
		return nodes[0] as AnimationPlayer
	return null


func _import_external_anims() -> void:
	if _anim == null:
		return
	# Ensure a writable library exists on the target player
	var target_lib_name := &"enemy_clips"
	if not _anim.has_animation_library(target_lib_name):
		_anim.add_animation_library(target_lib_name, AnimationLibrary.new())
	var target_lib: AnimationLibrary = _anim.get_animation_library(target_lib_name)

	# Discover how this model names Mixamo bones (colon vs no-colon, Skeleton path prefix)
	var skeleton := _find_skeleton(_model_root)
	var bone_sample := ""
	if skeleton and skeleton.get_bone_count() > 0:
		bone_sample = skeleton.get_bone_name(0)
	print("[Enemy] skeleton bones=", skeleton.get_bone_count() if skeleton else 0, " first=", bone_sample)

	for key in ANIM_PATHS.keys():
		var path: String = ANIM_PATHS[key]
		if not ResourceLoader.exists(path):
			push_warning("Missing anim: " + path)
			continue
		var res = load(path)
		if res == null:
			continue
		var temp: Node = null
		if res is PackedScene:
			temp = (res as PackedScene).instantiate()
		else:
			continue
		var src_ap := _find_anim_player(temp)
		if src_ap == null:
			temp.queue_free()
			continue
		for anim_name in src_ap.get_animation_list():
			var clip: Animation = src_ap.get_animation(anim_name)
			if clip == null:
				continue
			var copied := clip.duplicate(true) as Animation
			# Clever combination: loop locomotion, one-shot combat/death
			if key == "shoot" or key == "die":
				copied.loop_mode = Animation.LOOP_NONE
			else:
				copied.loop_mode = Animation.LOOP_LINEAR
			_retarget_mixamo_tracks(copied, skeleton)
			# Keep hip Y on death so the body actually drops to the floor.
			# Locomotion stays in-place (root XZ/Y stripped).
			if key == "die":
				_keep_death_hip_drop(copied)
			else:
				_strip_root_motion(copied)
			# Only convert cm Mixamo keys onto a meter-scale body. Dying.glb (and
			# some FBX) already import in meters — scaling those by 0.01 plants
			# standing hips at ~1cm and the torso sinks to the waist.
			if _skeleton_is_meters(skeleton) and _clip_positions_are_cm(copied):
				_scale_position_tracks(copied, 0.01)
			if key == "die":
				_rebias_death_hips(copied, skeleton)
			var safe_name := "%s__%s" % [key, String(anim_name).get_file().replace("|", "_").replace(" ", "_")]
			if target_lib.has_animation(safe_name):
				target_lib.remove_animation(safe_name)
			target_lib.add_animation(safe_name, copied)
		temp.queue_free()


func _find_skeleton(root: Node) -> Skeleton3D:
	var nodes := root.find_children("*", "Skeleton3D", true, false)
	if nodes.size() > 0:
		return nodes[0] as Skeleton3D
	return null


func _retarget_mixamo_tracks(anim: Animation, skeleton: Skeleton3D) -> void:
	## Map Mixamo clip tracks (mixamorig:Hips) onto the police mesh skeleton (mixamorigHips).
	if skeleton == null or _anim == null:
		return
	# Path from AnimationPlayer to Skeleton3D (should be a sibling name after reparent)
	var skel_path := _anim.get_path_to(skeleton)
	if String(skel_path).is_empty() or String(skel_path).begins_with(".."):
		# Fallback: same-parent sibling by node name
		skel_path = NodePath(skeleton.name)

	for i in anim.get_track_count():
		var path := String(anim.track_get_path(i))
		# Pull bone token out of paths like "Armature/Skeleton3D:mixamorig:Hips"
		var bone := path
		if path.contains(":"):
			var after := path.substr(path.find(":") + 1)
			# Handle "mixamorig:Hips" still containing a colon
			if after.begins_with("mixamorig:") or after.begins_with("mixamorig"):
				bone = after
			else:
				bone = after
		bone = bone.get_file() # strip any leftover node path

		var candidates: Array[String] = [
			bone,
			bone.replace("mixamorig:", "mixamorig_"),
			bone.replace("mixamorig:", "mixamorig"),
			bone.replace(":", ""),
			bone.replace("mixamorig_", "mixamorig"),
			bone.replace("mixamorig", "mixamorig_").replace("mixamorig__", "mixamorig_"),
		]
		# Explicit Mixamo colon → no-colon (police.glb style)
		if bone.begins_with("mixamorig:"):
			candidates.insert(0, bone.replace("mixamorig:", "mixamorig"))

		var resolved := ""
		for c in candidates:
			if c != "" and skeleton.find_bone(c) >= 0:
				resolved = c
				break
		if resolved == "":
			var compact := bone.replace(":", "").replace("_", "").to_lower()
			for bi in skeleton.get_bone_count():
				var bn := skeleton.get_bone_name(bi)
				if bn.replace(":", "").replace("_", "").to_lower() == compact:
					resolved = bn
					break
		if resolved == "":
			continue

		# Godot bone animation path format: NodePathToSkeleton:BoneName
		anim.track_set_path(i, NodePath("%s:%s" % [String(skel_path), resolved]))


func _strip_root_motion(anim: Animation) -> void:
	# REMOVE hips/root POSITION tracks (do not write Vector3.ZERO — that collapses
	# the hips to the skeleton origin and makes the mesh a flat blob on the floor).
	# Rotations stay; rest-pose hip height keeps the body upright.
	for i in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(anim.track_get_path(i)).to_lower()
		if "hips" in path or path.ends_with(":root") or "/root" in path:
			anim.remove_track(i)


func _clip_positions_are_cm(anim: Animation) -> bool:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		for k in anim.track_get_key_count(i):
			var v: Variant = anim.track_get_key_value(i, k)
			if v is Vector3 and (v as Vector3).length() > 20.0:
				return true
	return false


func _keep_death_hip_drop(anim: Animation) -> void:
	## Death needs the hips to fall. Zero out XZ (no slide) but keep Y keys.
	for i in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(anim.track_get_path(i)).to_lower()
		if not ("hips" in path or path.ends_with(":root") or "/root" in path):
			continue
		for k in anim.track_get_key_count(i):
			var v: Variant = anim.track_get_key_value(i, k)
			if v is Vector3:
				var p := v as Vector3
				anim.track_set_key_value(i, k, Vector3(0.0, p.y, 0.0))


func _rebias_death_hips(anim: Animation, skeleton: Skeleton3D) -> void:
	## Make frame 0 match the standing rest hip height; keep the clip's Y drop.
	if skeleton == null:
		return
	var rest_y := _hips_rest_origin(skeleton).y
	if absf(rest_y) < 0.001:
		return
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(anim.track_get_path(i)).to_lower()
		if not ("hips" in path or path.ends_with(":root") or "/root" in path):
			continue
		if anim.track_get_key_count(i) == 0:
			continue
		var first: Variant = anim.track_get_key_value(i, 0)
		if not (first is Vector3):
			continue
		var delta := rest_y - (first as Vector3).y
		if is_zero_approx(delta):
			continue
		for k in anim.track_get_key_count(i):
			var v: Variant = anim.track_get_key_value(i, k)
			if v is Vector3:
				var p := v as Vector3
				anim.track_set_key_value(i, k, Vector3(p.x, p.y + delta, p.z))


func _resolve_anim_names() -> void:
	var all := _anim.get_animation_list() if _anim else PackedStringArray()
	anim_walk = _pick_anim(all, ["walk"])
	anim_run = _pick_anim(all, ["run"])
	anim_pistol_walk = _pick_anim(all, ["pistol"])
	anim_shoot = _pick_anim(all, ["shoot", "fire"])
	anim_die = _pick_anim(all, ["die", "dying", "death"])
	anim_idle = _pick_anim(all, ["idle", "tpose", "bind"])
	# Fallbacks
	if anim_idle == "" and anim_walk != "":
		anim_idle = anim_walk
	if anim_run == "":
		anim_run = anim_walk
	if anim_pistol_walk == "":
		anim_pistol_walk = anim_walk
	# Log for debugging
	print("[Enemy] anims walk=%s run=%s pistol=%s shoot=%s die=%s | all=%s" % [
		anim_walk, anim_run, anim_pistol_walk, anim_shoot, anim_die, all
	])


func _pick_anim(all: PackedStringArray, keywords: Array) -> String:
	# Prefer names that start with the keyword folder/prefix (walk__ not pistol_walk__)
	for k in keywords:
		var key := String(k).to_lower()
		for a in all:
			var low := String(a).to_lower()
			var base := low.get_file()
			if base.begins_with(key + "__") or base.begins_with(key + "/") or base == key:
				return String(a)
	for k in keywords:
		var key := String(k).to_lower()
		for a in all:
			var low := String(a).to_lower()
			# Avoid false positives: "walk" inside "pistol_walk"
			if key == "walk" and "pistol" in low:
				continue
			if key in low:
				return String(a)
	return ""


func _play(anim_name: String, speed: float = 1.0) -> void:
	if _anim == null or anim_name == "":
		return
	_anim.speed_scale = 1.0
	if anim_name == _current_anim and _anim.is_playing():
		_anim.speed_scale = speed
		return
	if not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name, 0.25, speed)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_update_death_drop()
		return
	# Freeze combat while pause / menus are up
	if GameState == null or GameState.paused or not GameState.game_started or GameState.player_dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if _player == null or not is_instance_valid(_player):
		_find_player()
		return
	if GameState.player_dead:
		_play(anim_idle)
		velocity = Vector3.ZERO
		move_and_slide()
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var can_see := dist < sight_range and _has_line_of_sight()
	if can_see:
		_los_time = minf(_los_time + delta, 1.0)
		_aware = true
	else:
		_los_time = maxf(0.0, _los_time - delta * 2.0)

	if not _aware:
		_patrol(delta)
		return

	# Face player (Mixamo faces +Z; look_at aims -Z → flip 180°)
	if dist > 0.15:
		var look_target := _player.global_position
		look_target.y = global_position.y
		var flat := look_target - global_position
		flat.y = 0.0
		if flat.length_squared() > 0.001:
			look_at(global_position + flat, Vector3.UP)
			rotate_y(PI)

	if dist <= melee_range * 0.9 and can_see:
		state = State.ATTACK
		velocity = Vector3.ZERO
		_try_attack()
	elif dist <= attack_range and can_see and _los_time > 0.22:
		# Strafe / cautious advance with pistol walk, shoot periodically
		state = State.ATTACK
		var dir := to_player.normalized()
		# Keep optimal mid-range
		if dist > 7.0:
			velocity = dir * walk_speed
			_play(anim_pistol_walk if anim_pistol_walk != "" else anim_walk, 1.0)
		elif dist < 4.0:
			velocity = -dir * walk_speed * 0.6
			_play(anim_pistol_walk if anim_pistol_walk != "" else anim_walk, 0.9)
		else:
			# sidestep
			var side := dir.cross(Vector3.UP).normalized()
			velocity = side * walk_speed * 0.7 * (1.0 if _rng.randf() > 0.5 else -1.0)
			_play(anim_pistol_walk if anim_pistol_walk != "" else anim_walk, 0.95)
		_try_attack()
	else:
		state = State.CHASE
		var dir := to_player.normalized()
		var spd := run_speed if dist > 10.0 else walk_speed
		velocity = dir * spd
		if dist > 10.0:
			_play(anim_run if anim_run != "" else anim_walk, 1.15)
		else:
			_play(anim_walk, 1.0)

	_apply_gravity(delta)
	move_and_slide()
	_stick_to_floor()


func _patrol(delta: float) -> void:
	state = State.IDLE
	_patrol_wait = maxf(0.0, _patrol_wait - delta)
	if _patrol_wait > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		_stick_to_floor()
		# No real idle clip — pause so they don't moonwalk in place
		if _anim != null and _anim.is_playing() and anim_idle == anim_walk:
			_anim.speed_scale = 0.0
		return

	if not _has_patrol_target or global_position.distance_to(_patrol_target) < 0.7:
		_pick_patrol_target()
		if _rng.randf() < 0.35:
			_patrol_wait = _rng.randf_range(0.8, 2.2)
			_has_patrol_target = false
			velocity.x = 0.0
			velocity.z = 0.0
			_apply_gravity(delta)
			move_and_slide()
			_stick_to_floor()
			return

	var to := _patrol_target - global_position
	to.y = 0.0
	if to.length_squared() < 0.04:
		_has_patrol_target = false
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		_stick_to_floor()
		return

	var dir := to.normalized()
	velocity = dir * walk_speed
	_apply_gravity(delta)

	if to.length_squared() > 0.001:
		look_at(global_position + dir, Vector3.UP)
		rotate_y(PI)

	_play(anim_walk if anim_walk != "" else anim_idle, 1.0)
	if _anim != null:
		_anim.speed_scale = 1.0
	var before := global_position
	move_and_slide()
	# Stuck against a wall — pick a new heading
	_stick_to_floor()
	var moved := Vector3(global_position.x - before.x, 0.0, global_position.z - before.z)
	if moved.length() < walk_speed * delta * 0.15:
		_has_patrol_target = false


func _pick_patrol_target() -> void:
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(3.0, 10.0)
	var dest := global_position + Vector3(cos(angle), 0.0, sin(angle)) * dist
	dest.y = global_position.y
	# Prefer destinations that don't immediately hit a wall
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.8, 0)
	var to := dest + Vector3(0, 0.8, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [self]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var p: Vector3 = hit.position
		var back := (from - to).normalized() * 0.8
		dest = Vector3(p.x + back.x, global_position.y, p.z + back.z)
	_patrol_target = dest
	_has_patrol_target = true


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta


func _stick_to_floor() -> void:
	## Drop from ceiling tops / step edges onto the real walkable floor.
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var y: float = DoomLevel.find_walkable_y(space, global_position, global_position.y + 0.6, global_position.y - 8.0, [self])
	if is_nan(y):
		return
	var dy := global_position.y - y
	if dy > 0.06 and dy < 6.5:
		global_position.y = y
		velocity.y = 0.0
	elif dy < -0.15 and dy > -0.9:
		# Slightly in the floor (stair mesh) — lift to the tread.
		global_position.y = y
		velocity.y = 0.0


func _unstuck() -> void:
	if not is_inside_tree() or state == State.DEAD:
		return
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null or col.shape == null:
		return
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = col.shape
	params.transform = col.global_transform
	params.collision_mask = 1
	params.exclude = [get_rid()]
	var info := space.get_rest_info(params)
	if info.is_empty():
		return
	var n: Vector3 = info.get("normal", Vector3.ZERO)
	n.y = 0.0
	if n.length_squared() < 0.0001:
		n = Vector3(1, 0, 0)
	else:
		n = n.normalized()
	global_position += n * 0.22


func _has_line_of_sight() -> bool:
	if _player == null:
		return false
	# Thick sweep so thin Doom walls actually block shots (zero-width rays slip through).
	if not _clear_shot(Vector3(0, 1.35, 0), Vector3(0, 1.35, 0)):
		return false
	if not _clear_shot(Vector3(0, 1.05, 0), Vector3(0, 0.9, 0)):
		return false
	return true


func _clear_shot(from_off: Vector3, to_off: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + from_off
	var to := _player.global_position + to_off
	var motion := to - from
	if motion.length_squared() < 0.01:
		return true
	var ball := SphereShape3D.new()
	ball.radius = 0.2
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = ball
	params.transform = Transform3D(Basis(), from)
	params.motion = motion
	params.collision_mask = 1
	params.exclude = [get_rid(), _player.get_rid()]
	var frac: PackedFloat32Array = space.cast_motion(params)
	if frac.size() < 2:
		# Fallback ray
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = [self, _player]
		q.hit_from_inside = true
		return space.intersect_ray(q).is_empty()
	# safe fraction of 1.0 means the sphere reached the player
	return frac[0] > 0.985


func _try_attack() -> void:
	if GameState == null or GameState.paused or not GameState.game_started or GameState.player_dead:
		return
	if _attack_cd > 0.0:
		return
	if not _has_line_of_sight():
		return
	_attack_cd = attack_cooldown + _rng.randf_range(-0.15, 0.25)
	_play(anim_shoot if anim_shoot != "" else anim_idle, 1.0)
	# Delay damage slightly to match muzzle
	get_tree().create_timer(0.25).timeout.connect(_deal_damage_to_player)


func _deal_damage_to_player() -> void:
	if state == State.DEAD or _player == null:
		return
	if GameState == null or GameState.paused or not GameState.game_started or GameState.player_dead:
		return
	if not _has_line_of_sight():
		return
	var dist := global_position.distance_to(_player.global_position)
	if dist > attack_range * 1.1:
		return
	if _player.has_method("take_hit"):
		_player.take_hit(damage)
	# Muzzle flash fx
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.4)
	flash.light_energy = 3.0
	flash.omni_range = 3.0
	flash.position = Vector3(0, 1.3, -0.6)
	add_child(flash)
	get_tree().create_timer(0.06).timeout.connect(flash.queue_free)
	SFX.play_3d(get_parent(), "shoot", global_position + Vector3(0, 1.3, 0), -10.0)
	broadcast_gunshot(self, global_position)


func take_damage(amount: int, hit_pos: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	_aware = true
	var at := hit_pos
	if at == Vector3.ZERO:
		at = global_position + Vector3(0, 1.2, 0)
	_spawn_blood(at, hp <= 0)
	if hp <= 0:
		# Restore textures first so the death anim keeps original look
		_restore_materials()
		_die()
	else:
		_flash_hurt()


func _spawn_blood(pos: Vector3, fatal: bool) -> void:
	var host := get_parent()
	if host == null:
		host = self
	var burst := CPUParticles3D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 42 if fatal else 26
	burst.lifetime = 0.55 if fatal else 0.4
	burst.local_coords = false
	burst.direction = Vector3(0, 0.35, 0)
	burst.spread = 62.0
	burst.initial_velocity_min = 2.4 if fatal else 1.8
	burst.initial_velocity_max = 7.5 if fatal else 5.2
	burst.gravity = Vector3(0, -14.0, 0)
	burst.damping_min = 1.0
	burst.damping_max = 3.0
	burst.scale_amount_min = 0.35
	burst.scale_amount_max = 1.15
	burst.color = Color(0.62, 0.02, 0.04)
	var drop := SphereMesh.new()
	drop.radius = 0.028
	drop.height = 0.056
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.01, 0.03)
	mat.roughness = 0.45
	mat.metallic = 0.0
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.0, 0.02)
	mat.emission_energy_multiplier = 0.45
	drop.material = mat
	burst.mesh = drop
	host.add_child(burst)
	burst.global_position = pos
	burst.emitting = true

	# Fast expanding splash so the hit reads even at a distance
	var splash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	splash.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.5, 0.0, 0.02, 0.7)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.emission_enabled = true
	smat.emission = Color(0.4, 0.0, 0.02)
	smat.emission_energy_multiplier = 0.8
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	splash.material_override = smat
	host.add_child(splash)
	splash.global_position = pos
	var tw := splash.create_tween()
	var end_s := 3.2 if fatal else 2.1
	tw.tween_property(splash, "scale", Vector3.ONE * end_s, 0.16)
	tw.parallel().tween_property(smat, "albedo_color:a", 0.0, 0.16)
	tw.tween_callback(splash.queue_free)

	get_tree().create_timer(burst.lifetime + 0.2).timeout.connect(burst.queue_free)


func _flash_hurt() -> void:
	# Brief red emission pulse WITHOUT replacing albedo textures
	for entry in _surface_mats:
		var mat: Material = entry["mat"]
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			sm.emission_enabled = true
			sm.emission = Color(1.0, 0.15, 0.1)
			sm.emission_energy_multiplier = 1.8
			if sm.emission_texture == null and sm.albedo_texture:
				sm.emission_texture = sm.albedo_texture
	get_tree().create_timer(0.1).timeout.connect(_restore_materials)


func _restore_materials() -> void:
	# Clear any solid override and put back prepared textured materials
	for n in _model_root.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = null
	for entry in _surface_mats:
		var mi: MeshInstance3D = entry["mi"]
		var s: int = entry["surface"]
		var mat: Material = entry["mat"]
		if not is_instance_valid(mi):
			continue
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			# Reset hurt emission to the normal “readable” look
			sm.emission_enabled = true
			if sm.albedo_texture:
				sm.emission_texture = sm.albedo_texture
				sm.emission = Color(1, 1, 1)
				sm.emission_energy_multiplier = 0.35
				sm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			else:
				sm.emission = Color(0.25, 0.28, 0.35)
				sm.emission_energy_multiplier = 0.4
		mi.set_surface_override_material(s, mat)


func hear_gunshot(at: Vector3, radius: float = -1.0) -> void:
	if state == State.DEAD:
		return
	if radius < 0.0 and GameState:
		radius = GameState.hear_radius()
	elif radius < 0.0:
		radius = 16.0
	if global_position.distance_to(at) <= radius:
		_aware = true


static func broadcast_gunshot(from: Node, at: Vector3, radius: float = -1.0) -> void:
	if from == null or not from.is_inside_tree():
		return
	if radius < 0.0 and GameState:
		radius = GameState.hear_radius()
	for n in from.get_tree().get_nodes_in_group("enemy"):
		if n != from and n.has_method("hear_gunshot"):
			n.hear_gunshot(at, radius)


func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_restore_materials() # keep original textures during death animation
	GameState.add_score(100)
	GameState.unregister_enemy()
	_prepare_death_drop()
	_play(anim_die if anim_die != "" else "")
	SFX.play_3d(get_parent(), "hit", global_position, -6.0)
	if _anim and not _anim.animation_finished.is_connected(_on_death_anim_finished):
		_anim.animation_finished.connect(_on_death_anim_finished)
	var delay := 2.8
	if _anim and anim_die != "" and _anim.has_animation(anim_die):
		delay = _anim.get_animation(anim_die).length + 0.05
	get_tree().create_timer(delay).timeout.connect(_settle_corpse)


func _prepare_death_drop() -> void:
	## Sample this skeleton's last death pose and see how far it still is from
	## the floor. That offset is eased in during playback so every mesh lands,
	## regardless of Mixamo units or rest-pose hip height.
	_death_drop = 0.0
	_corpse_settled = false
	if _model_root == null:
		return
	_death_base_model_y = _model_root.position.y
	if _anim == null or anim_die == "" or not _anim.has_animation(anim_die):
		return
	var clip := _anim.get_animation(anim_die)
	_death_len = maxf(clip.length, 0.01)
	_anim.play(anim_die)
	_anim.seek(_death_len, true)
	var end_min := _lowest_bone_world_y()
	_anim.seek(0.0, true)
	if end_min < INF:
		_death_drop = 0.02 - end_min


func _update_death_drop() -> void:
	if _corpse_settled or _model_root == null:
		return
	var t := 1.0
	if _anim and _death_len > 0.0:
		t = clampf(_anim.current_animation_position / _death_len, 0.0, 1.0)
	var w := t * t * (3.0 - 2.0 * t)
	_model_root.position.y = _death_base_model_y + _death_drop * w
	if t >= 0.999:
		_settle_corpse()


func _lowest_bone_world_y() -> float:
	var skeleton := _find_skeleton(_model_root)
	if skeleton == null:
		return INF
	skeleton.force_update_all_bone_transforms()
	var min_y := INF
	for i in skeleton.get_bone_count():
		var local := skeleton.get_bone_global_pose(i).origin
		var world := skeleton.global_transform * local
		if world.y < min_y:
			min_y = world.y
	return min_y


func _on_death_anim_finished(anim_name: StringName) -> void:
	if state != State.DEAD:
		return
	if anim_die != "" and String(anim_name) != anim_die and not String(anim_name).contains("die"):
		return
	_settle_corpse()


func _settle_corpse() -> void:
	if not is_instance_valid(self) or state != State.DEAD:
		return
	if _anim:
		if anim_die != "" and _anim.has_animation(anim_die):
			_anim.play(anim_die)
			_anim.seek(_anim.get_animation(anim_die).length, true)
		_anim.pause()
	var min_y := _lowest_bone_world_y()
	if min_y < INF:
		_model_root.global_position.y += 0.02 - min_y
	_corpse_settled = true


func _set_layers(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer
	for c in node.get_children():
		_set_layers(c, layer)


func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_disable_shadows(c)
