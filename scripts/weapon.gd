extends Node3D
class_name WeaponViewmodel
## AKS-74U FPS viewmodel — transform tuned from the three.js prototype.

## From Wolfenstein3D index.html GUN_DEFAULT (camera-local):
## pos (-0.260, -0.001, 0.078), scale 3.23568, rotY 0
## Godot camera also looks down -Z, so values map 1:1.
const GUN_POS := Vector3(-0.260, -0.001, 0.078)
const GUN_SCALE := 3.23568

const ANIM_FIRE := "armature|Fire_single"
const ANIM_RELOAD := "armature|Reload_t"
const ANIM_RELOAD_FULL := "armature|Reload_f"
const ANIM_EQUIP := "armature|Put_in"
const ANIM_HOLSTER := "armature|Put_out"
const ANIM_FIRE_MODE := "armature|Fire_mode_select"
const ANIM_FIRE_SPRITE := "armature|Fire_sprite"

signal fired
signal reload_finished
signal equip_finished

var _model: Node3D
var _anim: AnimationPlayer
var _reloading: bool = false
var _fire_cd: float = 0.0
## Full-auto fire rate (seconds between shots). Independent of long fire anims.
@export var fire_interval: float = 0.09
var _muzzle: Marker3D
var _flash: OmniLight3D
var _flash_timer: float = 0.0

func _ready() -> void:
	position = GUN_POS
	scale = Vector3.ONE * GUN_SCALE
	rotation = Vector3.ZERO
	_load_model()
	# Viewmodel render layer (2)
	_set_layers_recursive(self, 2)
	# Local fill lights so the gun stays readable
	var key := OmniLight3D.new()
	key.light_energy = 0.9
	key.omni_range = 2.0
	key.position = Vector3(0.04, 0.05, 0.02)
	key.layers = 2
	add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.9, 0.75)
	fill.light_energy = 0.45
	fill.omni_range = 1.8
	fill.position = Vector3(-0.06, 0.02, 0.02)
	fill.layers = 2
	add_child(fill)

	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0.0, 0.05, -0.25)
	add_child(_muzzle)

	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.75, 0.35)
	_flash.light_energy = 0.0
	_flash.omni_range = 4.0
	_flash.layers = 1 # light the world briefly
	_flash.position = Vector3(0, 0.05, -0.35)
	add_child(_flash)


func _process(delta: float) -> void:
	if _fire_cd > 0.0:
		_fire_cd = maxf(0.0, _fire_cd - delta)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		_flash.light_energy = 4.0 * clampf(_flash_timer / 0.05, 0.0, 1.0)
		if _flash_timer <= 0.0:
			_flash.light_energy = 0.0


func _load_model() -> void:
	var path := "res://assets/guns/animated_aks-74u.glb"
	if not ResourceLoader.exists(path):
		push_warning("AKS-74U GLB missing at %s" % path)
		_make_placeholder()
		return
	var packed := load(path)
	if packed == null:
		_make_placeholder()
		return
	if packed is PackedScene:
		_model = (packed as PackedScene).instantiate()
	else:
		_make_placeholder()
		return

	# Strip helper cameras / lights from Sketchfab export
	var to_free: Array[Node] = []
	for n in _model.find_children("*", "", true, false):
		var lname := String(n.name).to_lower()
		if lname.begins_with("hemi") or lname.begins_with("sun") or lname.begins_with("camera") or lname.begins_with("bone_shape"):
			to_free.append(n)
		if n is Light3D or n is Camera3D:
			to_free.append(n)
	for n in to_free:
		if is_instance_valid(n):
			n.queue_free()

	add_child(_model)

	_anim = _find_anim_player(_model)
	if _anim:
		_anim.animation_finished.connect(_on_anim_finished)
		# Rest pose only — do NOT play full equip oneshot (it blocked shooting for seconds).
		if _has_anim(ANIM_FIRE):
			_anim.play(ANIM_FIRE)
			_anim.seek(0.0, true)
			_anim.pause()
		elif _has_anim(ANIM_EQUIP):
			_anim.play(ANIM_EQUIP)
			_anim.seek(0.0, true)
			_anim.pause()

	_configure_materials(_model)


func _make_placeholder() -> void:
	_model = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, 0.35)
	(_model as MeshInstance3D).mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.25, 0.28)
	mat.metallic = 0.6
	(_model as MeshInstance3D).material_override = mat
	add_child(_model)


func _find_anim_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for c in root.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	# search deeper
	var nodes := root.find_children("*", "AnimationPlayer", true, false)
	if nodes.size() > 0:
		return nodes[0] as AnimationPlayer
	return null


func _has_anim(name: String) -> bool:
	return _anim != null and _anim.has_animation(name)


func _play_oneshot(name: String, block_reload: bool = false) -> bool:
	if _anim == null or not _anim.has_animation(name):
		return false
	if block_reload:
		_reloading = true
	_anim.play(name)
	var anim := _anim.get_animation(name)
	if anim:
		anim.loop_mode = Animation.LOOP_NONE
	return true


func _on_anim_finished(anim_name: StringName) -> void:
	var n := String(anim_name)
	if n == ANIM_RELOAD or n == ANIM_RELOAD_FULL:
		_reloading = false
		reload_finished.emit()
	elif n == ANIM_EQUIP:
		equip_finished.emit()
	# Hold last frame as rest pose
	if _anim and _anim.has_animation(n):
		_anim.play(n)
		_anim.seek(_anim.get_animation(n).length, true)
		_anim.pause()


func is_busy() -> bool:
	return _reloading or _fire_cd > 0.0


func try_fire() -> bool:
	if _reloading or _fire_cd > 0.0:
		return false
	if not GameState.try_consume_shot():
		SFX.play_2d(self, "empty", -6.0)
		return false
	SFX.play_2d(self, "shoot", -4.0)
	_flash_timer = 0.05
	_fire_cd = fire_interval
	# Fire anim is visual only — does not block next shot beyond fire_interval
	if _has_anim(ANIM_FIRE):
		_play_oneshot(ANIM_FIRE, false)
	else:
		var tw := create_tween()
		tw.tween_property(self, "position", GUN_POS + Vector3(0, 0.01, 0.03), 0.04)
		tw.tween_property(self, "position", GUN_POS, 0.08)
	fired.emit()
	return true


func try_reload() -> bool:
	if _reloading:
		return false
	if GameState.mag >= GameState.mag_size or GameState.reserve_ammo <= 0:
		return false
	var anim_name := ANIM_RELOAD if _has_anim(ANIM_RELOAD) else ANIM_RELOAD_FULL
	if _has_anim(anim_name):
		_play_oneshot(anim_name, true)
	else:
		_reloading = true
		get_tree().create_timer(1.2).timeout.connect(func():
			GameState.try_reload()
			_reloading = false
			reload_finished.emit()
		)
		return true
	return true


func apply_reload_ammo() -> void:
	GameState.try_reload()


func _configure_materials(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.layers = 2
		# Brighten slightly so hands/gun aren't underlit
		if gi.material_override == null and gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			for si in mi.get_surface_override_material_count():
				pass
	# Traverse mesh materials
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is BaseMaterial3D:
				var bm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				bm.metallic = minf(bm.metallic, 0.35)
				bm.roughness = maxf(bm.roughness, 0.45)
				if bm is StandardMaterial3D:
					var sm := bm as StandardMaterial3D
					if not sm.emission_enabled:
						sm.emission_enabled = true
						sm.emission = Color(0.15, 0.15, 0.15)
						sm.emission_energy_multiplier = 0.35
				mi.set_surface_override_material(s, bm)


func _set_layers_recursive(node: Node, layer_bit: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer_bit
	if node is Light3D:
		(node as Light3D).layers = layer_bit
	for c in node.get_children():
		_set_layers_recursive(c, layer_bit)


func get_muzzle_global() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position
