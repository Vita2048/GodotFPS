extends Area3D
class_name Pickup

@export var pickup_type: String = "ammo" # ammo | health | key
@export var amount: int = 15
@export var respawn_seconds: float = 22.0
@export var key_name: String = ""

var _bob_t: float = 0.0
var _mesh: MeshInstance3D
var _respawning: bool = false

func _ready() -> void:
	collision_layer = 8
	collision_mask = 2 # player
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	shape.shape = sphere
	add_child(shape)

	_mesh = MeshInstance3D.new()
	_mesh.name = "Visual"
	_mesh.position.y = 0.55
	add_child(_mesh)
	if pickup_type == "health":
		_build_medkit(_mesh)
		amount = 35
	elif pickup_type == "key":
		_build_key(_mesh)
		respawn_seconds = 0.0
	else:
		_build_ammo_crate(_mesh)
		amount = 30

	# Soft glow (no realtime light on low — emissive material is enough)
	if QualitySettings == null or QualitySettings.level != QualitySettings.Quality.LOW:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.85) if pickup_type == "health" else Color(1.0, 0.85, 0.2)
		light.light_energy = 0.45
		light.omni_range = 2.0
		light.shadow_enabled = false
		light.position.y = 0.7
		add_child(light)


func _build_medkit(root: Node3D) -> void:
	## Solid white pack + a crisp 3D red cross. No textured cube (bilinear
	## filtering was bleeding red across the white faces).
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.96, 0.97, 0.98)
	white.metallic = 0.0
	white.roughness = 0.55
	white.emission_enabled = false

	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.80, 0.02, 0.05)
	red.metallic = 0.0
	red.roughness = 0.4
	red.emission_enabled = false

	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.40, 0.40, 0.14)
	body.mesh = box
	body.material_override = white
	root.add_child(body)

	for face_z in [0.085, -0.085]:
		var bar_h := MeshInstance3D.new()
		var hbox := BoxMesh.new()
		hbox.size = Vector3(0.26, 0.08, 0.025)
		bar_h.mesh = hbox
		bar_h.position = Vector3(0, 0, face_z)
		bar_h.material_override = red
		root.add_child(bar_h)
		var bar_v := MeshInstance3D.new()
		var vbox := BoxMesh.new()
		vbox.size = Vector3(0.08, 0.26, 0.025)
		bar_v.mesh = vbox
		bar_v.position = Vector3(0, 0, face_z)
		bar_v.material_override = red
		root.add_child(bar_v)


func _build_key(root: Node3D) -> void:
	var color := Color(0.85, 0.12, 0.12)
	var low := key_name.to_lower()
	if "blue" in low:
		color = Color(0.15, 0.4, 0.95)
	elif "yellow" in low:
		color = Color(0.95, 0.82, 0.12)
	var card := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.32, 0.04)
	card.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.85
	mat.metallic = 0.35
	mat.roughness = 0.35
	card.material_override = mat
	root.add_child(card)
	var chip := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(0.1, 0.08, 0.02)
	chip.mesh = cbox
	chip.position = Vector3(0, 0.08, 0.03)
	var chip_mat := StandardMaterial3D.new()
	chip_mat.albedo_color = Color(0.85, 0.75, 0.35)
	chip_mat.metallic = 0.8
	chip.material_override = chip_mat
	root.add_child(chip)


func _build_ammo_crate(root: Node3D) -> void:
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color(0.28, 0.24, 0.14)
	crate_mat.metallic = 0.15
	crate_mat.roughness = 0.62

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.55, 0.5, 0.32)
	metal.metallic = 0.8
	metal.roughness = 0.32
	metal.emission_enabled = true
	metal.emission = Color(0.85, 0.62, 0.12)
	metal.emission_energy_multiplier = 0.55

	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.82, 0.62, 0.22)
	brass.metallic = 0.9
	brass.roughness = 0.22
	brass.emission_enabled = true
	brass.emission = Color(0.95, 0.7, 0.15)
	brass.emission_energy_multiplier = 0.7

	var crate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.22, 0.28)
	crate.mesh = box
	crate.material_override = crate_mat
	root.add_child(crate)

	var rim := MeshInstance3D.new()
	var rbox := BoxMesh.new()
	rbox.size = Vector3(0.42, 0.03, 0.3)
	rim.mesh = rbox
	rim.position.y = 0.12
	rim.material_override = metal
	root.add_child(rim)

	for i in 4:
		var round := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.018
		cyl.bottom_radius = 0.018
		cyl.height = 0.09
		cyl.radial_segments = 8
		round.mesh = cyl
		round.material_override = brass
		round.rotation_degrees = Vector3(90, 0, 0)
		round.position = Vector3(-0.1 + i * 0.065, 0.16, 0.0)
		root.add_child(round)


func _process(delta: float) -> void:
	_bob_t += delta
	if _mesh:
		_mesh.position.y = 0.55 + sin(_bob_t * 3.0) * 0.1
		_mesh.rotation.y += delta * 1.5


func _physics_process(_delta: float) -> void:
	if _respawning:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and global_position.distance_to(player.global_position) < 1.25:
		_try_collect(player)


func _on_body_entered(body: Node) -> void:
	_try_collect(body)


func _try_collect(body: Node) -> void:
	if _respawning or body == null or not body.is_in_group("player"):
		return
	if pickup_type == "health":
		if GameState.health >= GameState.max_health:
			return
		GameState.heal(amount)
	elif pickup_type == "key":
		if body.has_method("give_key"):
			body.give_key(key_name)
		elif "inventory" in body:
			var inv: Dictionary = body.inventory
			if not inv.has(key_name):
				inv[key_name] = {"count": 0}
			inv[key_name]["count"] = int(inv[key_name]["count"]) + 1
	else:
		GameState.add_ammo(amount)
	_play_pickup()
	_flash_hud()
	_begin_respawn()


func _flash_hud() -> void:
	var hud := get_tree().get_first_node_in_group("player")
	if hud is Node:
		var p := hud as Node
		if p.get("hud") and p.hud.has_method("show_pickup"):
			if pickup_type == "health":
				p.hud.show_pickup("+%d HEALTH" % amount)
			elif pickup_type == "key":
				p.hud.show_pickup(key_name.to_upper())
			else:
				p.hud.show_pickup("+%d AMMO" % amount)


func _begin_respawn() -> void:
	_respawning = true
	monitoring = false
	visible = false
	if respawn_seconds <= 0.0:
		queue_free()
		return
	var tree := get_tree()
	if tree == null:
		queue_free()
		return
	tree.create_timer(respawn_seconds).timeout.connect(_finish_respawn)


func _finish_respawn() -> void:
	if not is_instance_valid(self):
		return
	visible = true
	monitoring = true
	_respawning = false


func _play_pickup() -> void:
	# One-shot at parent so it isn't freed with us
	var parent := get_parent()
	if parent == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = _beep()
	player.global_position = global_position
	parent.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _beep() -> AudioStreamWAV:
	var sample_rate := 22050
	var n := int(sample_rate * 0.18)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / sample_rate
		var freq := 400.0 if t < 0.09 else 800.0
		var env := 1.0 - t / 0.18
		var s := sin(TAU * freq * t) * env * 0.25
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.data = data
	return stream
