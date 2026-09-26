extends RigidBody3D
## Shootable canisters, breakable lamps, and movable cargo.
var kind := "barrel"
var hp := 45
var destroyed := false
var lamp: OmniLight3D
var visual: MeshInstance3D
var _menu_frozen := false
var _saved_linear := Vector3.ZERO
var _saved_angular := Vector3.ZERO

func _physics_process(_delta: float) -> void:
	if kind == "lamp": return
	var menu := GameState.paused or not GameState.game_started or GameState.player_dead
	if menu and not _menu_frozen:
		_saved_linear = linear_velocity
		_saved_angular = angular_velocity
		freeze = true
		_menu_frozen = true
	elif not menu and _menu_frozen:
		freeze = false
		linear_velocity = _saved_linear
		angular_velocity = _saved_angular
		_menu_frozen = false

func _ready() -> void:
	add_to_group("reactive")
	collision_layer = 1
	collision_mask = 1
	mass = 18 if kind == "barrel" else 8
	freeze = kind == "lamp"
	set_meta("surface_kind", "wood" if kind == "crate" else "metal")
	visual = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("aa4430") if kind == "barrel" else Color("75614b")
	mat.metallic = 0.5 if kind == "barrel" else 0.0
	mat.roughness = 0.5
	var shape: Shape3D
	if kind == "barrel":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.4
		cylinder.bottom_radius = 0.4
		cylinder.height = 1.3
		visual.mesh = cylinder
		var collision := CylinderShape3D.new()
		collision.radius = 0.4
		collision.height = 1.3
		shape = collision
		var label := Label3D.new()
		label.text = "VOLATILE\nCAUTION"
		label.font_size = 32
		label.pixel_size = 0.005
		label.position = Vector3(0, 0, 0.41)
		add_child(label)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 0.8, 0.8) if kind == "crate" else Vector3(1.1, 0.2, 0.25)
		visual.mesh = box
		var collision := BoxShape3D.new()
		collision.size = box.size
		shape = collision
		if kind == "lamp":
			hp = 1
			mat.emission_enabled = true
			mat.emission = Color("ffcc85")
			mat.emission_energy_multiplier = 3
			lamp = OmniLight3D.new()
			lamp.light_color = Color("ffcc85")
			lamp.light_energy = 1.6
			lamp.omni_range = 7
			add_child(lamp)
	visual.material_override = mat
	add_child(visual)
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

func take_damage(amount: int, hit_pos: Vector3) -> void:
	if destroyed: return
	hp -= amount
	if not freeze:
		apply_central_impulse((global_position - hit_pos).normalized() * 5 + Vector3.UP)
	if hp > 0: return
	destroyed = true
	if kind == "barrel":
		# Deferred prevents changing physics state during ray/physics callbacks.
		call_deferred("_explode")
	elif kind == "lamp":
		lamp.visible = false
		(visual.material_override as StandardMaterial3D).emission_enabled = false
		SFX.play_3d(get_parent(), "hit_glass", global_position, -7)
	else:
		SFX.play_3d(get_parent(), "wood_break", global_position, -5)
		queue_free()

func _explode() -> void:
	preload("res://scripts/explosive.gd").blast(get_parent(), global_position + Vector3.UP * 0.4, 5.5, 110, self)
	queue_free()
