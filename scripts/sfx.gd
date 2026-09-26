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
		"explosion":
			duration = 0.95
			data = _tone_burst(sample_rate, duration, func(t, _d):
				return sin(TAU * (60.0 * t - 20.0 * t * t)) * exp(-t * 5.0) * 0.75 + (randf() * 2 - 1) * exp(-t * 9) * 0.6
			)
		"rocket":
			duration = 0.4
			data = _tone_burst(sample_rate, duration, func(t, _d):
				return (randf() * 2 - 1) * exp(-t * 8) * 0.65 + sin(TAU * 90 * t) * exp(-t * 15) * 0.4
			)
		"grenade_bounce", "lift":
			duration = 0.2
			data = _tone_burst(sample_rate, duration, func(t, _d):
				return (sin(TAU * 260 * t) * 0.5 + sin(TAU * 730 * t) * 0.2) * exp(-t * 24)
			)
		"hit_glass":
			duration = 0.3
			data = _tone_burst(sample_rate, duration, func(t, _d):
				return (sin(TAU * 3200 * t) * 0.3 + (randf() * 2 - 1) * 0.4) * exp(-t * 16)
			)
		"shoot":
			duration = 0.12
			data = _tone_burst(sample_rate, duration, func(t, d):
				var env := exp(-t * 28.0)
				return sin(TAU * lerpf(220.0, 40.0, t / d) * t) * env * 0.4 \
					+ (randf() * 2.0 - 1.0) * env * 0.25
			)
		"hit", "hit_concrete":
			duration = 0.16
			data = _tone_burst(sample_rate, duration, func(t, d):
				var env := exp(-t * 18.0)
				var pop := sin(TAU * lerpf(160.0, 35.0, t / d) * t) * env * 0.45
				var grit := (randf() * 2.0 - 1.0) * exp(-t * 30.0) * 0.3
				return pop + grit
			)
		"hit_metal":
			duration = 0.22
			data = _tone_burst(sample_rate, duration, func(t, d):
				var env := exp(-t * 14.0)
				var ping := (sin(TAU * 1250.0 * t) + 0.5 * sin(TAU * 2480.0 * t)) * env * 0.4
				var thud := sin(TAU * lerpf(320.0, 80.0, t / d) * t) * exp(-t * 26.0) * 0.35
				var spark := (randf() * 2.0 - 1.0) * exp(-t * 40.0) * 0.2
				return ping + thud + spark
			)
		"hit_wood":
			duration = 0.18
			data = _tone_burst(sample_rate, duration, func(t, d):
				var env := exp(-t * 16.0)
				var thud := sin(TAU * lerpf(240.0, 60.0, t / d) * t) * env * 0.5
				var crack := (randf() * 2.0 - 1.0) * exp(-t * 22.0) * 0.3
				return thud + crack
			)
		"hit_brick":
			duration = 0.17
			data = _tone_burst(sample_rate, duration, func(t, d):
				var env := exp(-t * 17.0)
				var crack := sin(TAU * lerpf(280.0, 50.0, t / d) * t) * env * 0.4
				var crumble := (randf() * 2.0 - 1.0) * exp(-t * 18.0) * 0.38
				return crack + crumble
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
		"wood_break":
			duration = 0.28
			data = _tone_burst(sample_rate, duration, func(t, d):
				var env := exp(-t * 9.0)
				var crack := sin(TAU * lerpf(420.0, 70.0, t / d) * t) * env
				var splinter := (randf() * 2.0 - 1.0) * exp(-t * 22.0)
				return crack * 0.45 + splinter * 0.4
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
