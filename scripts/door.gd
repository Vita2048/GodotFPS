extends Node3D
## Sliding door (drops into floor like the three.js prototype).

var horizontal: bool = true
var slab: MeshInstance3D
var body: AnimatableBody3D
var state: String = "closed" # closed, opening, open, closing
var open_offset: float = 0.0
var _auto_close_timer: float = 0.0

const OPEN_SPEED := 1.6
const OPEN_HEIGHT := 3.0

func try_open() -> bool:
	if state == "closed" or state == "closing":
		state = "opening"
		_play_door_sound()
		return true
	return false


func _process(delta: float) -> void:
	if state == "opening":
		open_offset = minf(1.0, open_offset + delta * OPEN_SPEED)
		_apply_offset()
		if open_offset >= 1.0:
			state = "open"
			_auto_close_timer = 4.0
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
	var y := -open_offset * OPEN_HEIGHT
	if slab:
		slab.position.y = (3.2 * 0.5 - 0.05) + y
	if body:
		body.position.y = (3.2 * 0.5 - 0.05) + y
		# Disable collision when mostly open
		body.collision_layer = 0 if open_offset > 0.85 else 1


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
	var duration := 0.55
	var n := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / sample_rate
		var freq := lerpf(60.0, 140.0, t / duration)
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
