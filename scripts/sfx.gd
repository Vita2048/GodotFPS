extends Node
class_name SFX
## Tiny procedural one-shot sound factory (no external audio files needed).

static func play_2d(parent: Node, kind: String, volume_db: float = 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = make_stream(kind)
	p.volume_db = volume_db
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


static func play_3d(parent: Node, kind: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = make_stream(kind)
	p.volume_db = volume_db
	p.max_distance = 30.0
	parent.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


static func make_stream(kind: String) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.15
	var data := PackedByteArray()
	match kind:
		"shoot":
			duration = 0.12
			data = _tone_burst(sample_rate, duration, func(t, d):
				var env := exp(-t * 28.0)
				return sin(TAU * lerpf(220.0, 40.0, t / d) * t) * env * 0.4 \
					+ (randf() * 2.0 - 1.0) * env * 0.25
			)
		"hit":
			duration = 0.18
			data = _tone_burst(sample_rate, duration, func(t, d):
				var env := exp(-t * 16.0)
				return sin(TAU * lerpf(120.0, 30.0, t / d) * t) * env * 0.5
			)
		"empty":
			duration = 0.08
			data = _tone_burst(sample_rate, duration, func(t, d):
				return sin(TAU * 380.0 * t) * (1.0 - t / d) * 0.2
			)
		"hurt":
			duration = 0.2
			data = _tone_burst(sample_rate, duration, func(t, d):
				var env := exp(-t * 10.0)
				return sin(TAU * lerpf(180.0, 60.0, t / d) * t) * env * 0.35
			)
		_:
			duration = 0.1
			data = _tone_burst(sample_rate, duration, func(t, d):
				return sin(TAU * 440.0 * t) * (1.0 - t / d) * 0.2
			)
	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.data = data
	return stream


static func _tone_burst(sample_rate: int, duration: float, sample_fn: Callable) -> PackedByteArray:
	var n := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / sample_rate
		var s: float = sample_fn.call(t, duration)
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return data
