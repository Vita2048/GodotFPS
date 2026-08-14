extends Node3D
## Doom-style door: slab rises into the lintel when you walk up or press E.

var horizontal: bool = true
var slab: MeshInstance3D
var body: AnimatableBody3D
var state: String = "closed"
var open_offset: float = 0.0
var _auto_close_timer: float = 0.0
var door_height: float = 3.2

const OPEN_SPEED := 1.6


func _ready() -> void:
	set_process(true)
	if slab == null:
		slab = get_node_or_null("Slab") as MeshInstance3D
	if body == null:
		body = get_node_or_null("DoorBody") as AnimatableBody3D
	var area := Area3D.new()
	area.name = "Trigger"
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 2.6, 5.0)
	col.shape = box
	col.position = Vector3(0, 1.2, 0)
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _on_body_entered(n: Node) -> void:
	if n != null and n.is_in_group("player"):
		try_open()


func try_open() -> bool:
	if slab == null:
		slab = get_node_or_null("Slab") as MeshInstance3D
	if body == null:
		body = get_node_or_null("DoorBody") as AnimatableBody3D
	if state == "closed" or state == "closing":
		state = "opening"
		_play_door_sound()
		return true
	if state == "open":
		_auto_close_timer = 6.0
	return false


func _process(delta: float) -> void:
	if state == "opening":
		open_offset = minf(1.0, open_offset + delta * OPEN_SPEED)
		_apply_offset()
		if open_offset >= 1.0:
			state = "open"
			_auto_close_timer = 6.0
	elif state == "open":
		_auto_close_timer -= delta
		if _auto_close_timer <= 0.0:
			state = "closing"
	elif state == "closing":
		open_offset = maxf(0.0, open_offset - delta * OPEN_SPEED)
		_apply_offset()
		if open_offset <= 0.0:
			state = "closed"


func _apply_offset() -> void:
	var y0 := door_height * 0.5 - 0.05
	var y := y0 + open_offset * (door_height + 0.2)
	if slab:
		slab.position.y = y
	if body:
		body.position.y = y
		body.collision_layer = 0 if open_offset > 0.55 else 1


func _play_door_sound() -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = _make_door_stream()
	player.volume_db = -4.0
	player.max_distance = 24.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _make_door_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.45
	var n := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / sample_rate
		var freq := lerpf(80.0, 170.0, t / duration)
		var env := 1.0 - t / duration
		var s := sin(TAU * freq * t) * env * 0.35
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.data = data
	return stream
