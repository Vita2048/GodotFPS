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
	_mesh.name = "Visual"
	_mesh.position.y = 0.55
	add_child(_mesh)
	if pickup_type == "health":
		_build_medkit(_mesh)
		amount = 35
	elif pickup_type == "grenade":
		for x in [-0.14, 0.14]:
			var model := Node3D.new()
			model.position.x = x
			model.scale = Vector3.ONE * 1.6
			_mesh.add_child(model)
			preload("res://scripts/ordnance_models.gd").grenade(model)
	elif pickup_type == "rocket":
		for x in [-0.12, 0.12]:
			var model := Node3D.new()
			model.position.x = x
			_mesh.add_child(model)
			preload("res://scripts/ordnance_models.gd").rocket(model)
	else:
		_build_ammo_crate(_mesh)
		amount = 30
	if pickup_type in ["grenade", "rocket"]:
		var label := Label3D.new()
		label.text = "+2 GRENADES" if pickup_type == "grenade" else "+2 ROCKETS"
		label.font_size = 28
		label.pixel_size = 0.007
		label.position.y = 1.15
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)

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


func _build_ammo_crate(root: Node3D) -> void:
	preload("res://scripts/ordnance_models.gd").ammo(root)


func _process(delta: float) -> void:
	if GameState.paused: return
	_bob_t += delta
	if _mesh:
		_mesh.position.y = 0.55 + sin(_bob_t * 3.0) * 0.1
		_mesh.rotation.y += delta * 0.55


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if not GameState.game_started or GameState.paused or GameState.player_dead:
		return
	if pickup_type == "health":
		if GameState.health >= GameState.max_health:
			return
		GameState.heal(amount)
	elif pickup_type == "grenade":
		GameState.grenades += 2
	elif pickup_type == "rocket":
		GameState.rockets += 2
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
	parent.add_child(player)
	player.global_position = global_position
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
