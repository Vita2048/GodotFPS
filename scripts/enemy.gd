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
		shape.radius = 0.4
		shape.height = 1.6
		col.shape = shape
		col.position.y = 1.0
		add_child(col)


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
	model.position = Vector3.ZERO


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
			_strip_root_motion(copied)
			# Mixamo clips are authored in centimeters. Meter-scale FBX skeletons
			# need position keys scaled down or the mesh explodes and gets culled.
			if _skeleton_is_meters(skeleton):
				_scale_position_tracks(copied, 0.01)
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
	if anim_name == _current_anim and _anim.is_playing():
		return
	if not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name, 0.25, speed)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
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
		_aware = true

	if not _aware:
		state = State.IDLE
		velocity = Vector3.ZERO
		_play(anim_idle if anim_idle != "" else anim_walk, 0.4)
		move_and_slide()
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

	if dist <= melee_range * 0.9:
		state = State.ATTACK
		velocity = Vector3.ZERO
		_try_attack()
	elif dist <= attack_range and can_see:
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

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _has_line_of_sight() -> bool:
	if _player == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.4, 0)
	var to := _player.global_position + Vector3(0, 1.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 # world only
	q.exclude = [self]
	var hit := space.intersect_ray(q)
	return hit.is_empty()


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


func take_damage(amount: int, _hit_pos: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	_aware = true
	if hp <= 0:
		# Restore textures first so the death anim keeps original look
		_restore_materials()
		_die()
	else:
		_flash_hurt()


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


func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_restore_materials() # keep original textures during death animation
	GameState.add_score(100)
	GameState.unregister_enemy()
	_play(anim_die if anim_die != "" else "")
	SFX.play_3d(get_parent(), "hit", global_position, -6.0)
	var delay := 2.8
	if _anim and anim_die != "" and _anim.has_animation(anim_die):
		delay = maxf(2.0, _anim.get_animation(anim_die).length + 0.3)
	get_tree().create_timer(delay).timeout.connect(queue_free)


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
