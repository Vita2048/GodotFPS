extends Node3D
## Physics-driven platform; CharacterBody3D carries its riders automatically.
var platform: AnimatableBody3D
var target_y: float = 0.0
var moving := false
var gate: StaticBody3D

func _ready() -> void:
	add_to_group("interactable")
	platform = AnimatableBody3D.new()
	platform.sync_to_physics = false
	platform.set_meta("surface_kind", "metal")
	add_child(platform)
	_make_box(platform, Vector3(0, -0.16, 0), Vector3(3.8, 0.32, 3.8), Color("d3a64b"))
	for x in [-1.85, 1.85]:
		_make_box(platform, Vector3(x, 0.55, 0), Vector3(0.08, 1.1, 3.8), Color("294b50"))
	_make_box(platform, Vector3(0, 0.55, -1.85), Vector3(3.8, 1.1, 0.08), Color("294b50"))
	# A permanent landing gate prevents falling down the empty shaft.
	gate = StaticBody3D.new()
	gate.position = Vector3(0, 4.2, 2)
	add_child(gate)
	_make_box(gate, Vector3(0, 0.55, 0), Vector3(3.8, 1.1, 0.09), Color("d3a64b"))

func _make_box(body: PhysicsBody3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.6
	mat.roughness = 0.5
	mesh.material_override = mat
	mesh.position = pos
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)

func interaction_text(player_pos: Vector3) -> String:
	if Vector2(player_pos.x - global_position.x, player_pos.z - global_position.z).length() > 4.5:
		return ""
	return "LIFT IN TRANSIT" if moving else "[E] CALL / RIDE FREIGHT LIFT"

func interact(player_pos: Vector3) -> void:
	if moving:
		return
	var floor_y := 4.2 if player_pos.y > 2.2 else 0.0
	target_y = floor_y if absf(platform.position.y - floor_y) > 0.2 else 4.2 - floor_y
	moving = true
	SFX.play_3d(self, "lift", global_position, -10)

func _physics_process(delta: float) -> void:
	if GameState.paused or not GameState.game_started or GameState.player_dead:
		return
	if moving:
		platform.position.y = move_toward(platform.position.y, target_y, delta * 1.5)
		moving = absf(platform.position.y - target_y) > 0.005
	var open := not moving and platform.position.y > 4.19
	gate.visible = not open
	gate.collision_layer = 0 if open else 1
