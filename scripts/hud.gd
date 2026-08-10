extends CanvasLayer

@onready var health_label: Label = $Root/BottomBar/HealthBox/VBox/HealthVal
@onready var ammo_label: Label = $Root/BottomBar/AmmoBox/VBox/AmmoVal
@onready var score_label: Label = $Root/BottomBar/ScoreBox/VBox/ScoreVal
@onready var enemies_label: Label = $Root/BottomBar/EnemyBox/VBox/EnemyVal
@onready var face_label: Label = $Root/BottomBar/FaceBox/Face
@onready var message_label: Label = $Root/Message

@onready var fps_label: Label = null

func _ready() -> void:
	GameState.health_changed.connect(_on_health)
	GameState.ammo_changed.connect(_on_ammo)
	GameState.score_changed.connect(_on_score)
	GameState.enemy_killed.connect(_on_enemies)
	GameState.level_cleared.connect(_on_cleared)
	_on_health(GameState.health)
	_on_ammo(GameState.mag, GameState.reserve_ammo)
	_on_score(GameState.score)
	if message_label:
		message_label.text = ""
	# Lightweight FPS / quality readout
	fps_label = Label.new()
	fps_label.position = Vector2(12, 10)
	fps_label.add_theme_font_size_override("font_size", 14)
	fps_label.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75, 0.85))
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(fps_label)
	if QualitySettings:
		QualitySettings.quality_changed.connect(func(_q): _update_fps_label())


func _process(_delta: float) -> void:
	_update_fps_label()


func _update_fps_label() -> void:
	if fps_label == null:
		return
	var q := "LOW"
	if QualitySettings:
		q = QualitySettings.label()
	fps_label.text = "%d FPS  |  Quality %s (F10)" % [Engine.get_frames_per_second(), q]


func _on_health(v: int) -> void:
	if health_label:
		health_label.text = str(v)
	if face_label:
		if v > 75:
			face_label.text = "😐"
		elif v > 40:
			face_label.text = "😟"
		elif v > 0:
			face_label.text = "🤕"
		else:
			face_label.text = "💀"


func _on_ammo(mag: int, reserve: int) -> void:
	if ammo_label:
		ammo_label.text = "%d / %d" % [mag, reserve]


func _on_score(v: int) -> void:
	if score_label:
		score_label.text = str(v)


func _on_enemies(remaining: int) -> void:
	if enemies_label:
		enemies_label.text = str(remaining)


func _on_cleared() -> void:
	if message_label:
		message_label.text = "SECTOR CLEARED"
		var tw := create_tween()
		tw.tween_property(message_label, "modulate:a", 1.0, 0.2)
		tw.tween_interval(2.5)
		tw.tween_property(message_label, "modulate:a", 0.0, 1.0)
