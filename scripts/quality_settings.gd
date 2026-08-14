extends Node
## Runtime graphics quality. Applied on boot; F10 cycles Low → Medium → High.

enum Quality { LOW, MEDIUM, HIGH }

signal quality_changed(level: Quality)

var level: Quality = Quality.LOW

func _ready() -> void:
	apply(Quality.MEDIUM)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("quality_cycle"):
		level = ((int(level) + 1) % 3) as Quality
		apply(level)
		quality_changed.emit(level)


func apply(q: Quality) -> void:
	level = q
	var vp := get_viewport()
	if vp == null:
		return

	match q:
		Quality.LOW:
			vp.scaling_3d_scale = 0.65
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_debanding = false
			_env(false, false, false, 0.0)
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
		Quality.MEDIUM:
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_debanding = false
			_env(false, true, false, 0.25)
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
		Quality.HIGH:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			vp.use_debanding = true
			_env(true, true, false, 0.4)
			RenderingServer.directional_shadow_atlas_set_size(4096, true)

	# Soften anisotropic filtering cost
	if q == Quality.LOW:
		get_tree().call_group("perf_mesh", "set", "cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _env(ssao: bool, glow: bool, ssil: bool, glow_intensity: float) -> void:
	var we := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.ssao_enabled = ssao
	env.ssil_enabled = ssil
	env.glow_enabled = glow
	env.glow_intensity = glow_intensity
	env.fog_enabled = true
	# Cheaper fog on low
	env.fog_density = 0.0035 if level == Quality.LOW else 0.0022


func label() -> String:
	match level:
		Quality.LOW:
			return "LOW"
		Quality.MEDIUM:
			return "MEDIUM"
		_:
			return "HIGH"
