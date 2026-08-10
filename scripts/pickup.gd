extends Area3D
class_name Pickup

@export var pickup_type: String = "ammo" # ammo | health
@export var amount: int = 15

var _bob_t: float = 0.0
var _mesh: MeshInstance3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # player
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	shape.shape = sphere
	add_child(shape)

	_mesh = MeshInstance3D.new()
	if pickup_type == "health":
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 0.45, 0.18)
		_mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.95, 0.95)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.15, 0.15)
		mat.emission_energy_multiplier = 1.8
		_mesh.material_override = mat
		amount = 25
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.18
		cyl.height = 0.45
		_mesh.mesh = cyl
		var mat2 := StandardMaterial3D.new()
		mat2.albedo_color = Color(0.75, 0.65, 0.15)
		mat2.metallic = 0.7
		mat2.roughness = 0.35
		mat2.emission_enabled = true
		mat2.emission = Color(0.9, 0.7, 0.1)
		mat2.emission_energy_multiplier = 0.8
		_mesh.material_override = mat2
		amount = 20
	_mesh.position.y = 0.6
	add_child(_mesh)

	# Soft glow (no realtime light on low — emissive material is enough)
	if QualitySettings == null or QualitySettings.level != QualitySettings.Quality.LOW:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.2, 0.2) if pickup_type == "health" else Color(1.0, 0.85, 0.2)
		light.light_energy = 0.45
		light.omni_range = 2.0
		light.shadow_enabled = false
		light.position.y = 0.7
		add_child(light)


func _process(delta: float) -> void:
	_bob_t += delta
	if _mesh:
		_mesh.position.y = 0.55 + sin(_bob_t * 3.0) * 0.1
		_mesh.rotation.y += delta * 1.5


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if pickup_type == "health":
		if GameState.health >= GameState.max_health:
			return
		GameState.heal(amount)
	else:
		GameState.add_ammo(amount)
	_play_pickup()
	queue_free()


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
