extends Control

signal start_pressed
signal difficulty_changed

@onready var title_label: Label = $Center/VBox/Title
@onready var subtitle: Label = $Center/VBox/Subtitle
@onready var start_btn: Button = $Center/VBox/StartBtn
@onready var controls: Label = $Center/VBox/Controls

var _diff_label: Label
var _diff_row: HBoxContainer

func _ready() -> void:
	add_to_group("title_ui")
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	if start_btn:
		start_btn.pressed.connect(_on_start)
		start_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_difficulty_ui()
	if GameState:
		GameState.difficulty_changed.connect(_on_diff_changed)
	show_title()


func _build_difficulty_ui() -> void:
	var vbox := $Center/VBox as VBoxContainer
	if vbox == null or start_btn == null:
		return
	# Insert difficulty row between Start button and controls
	_diff_row = HBoxContainer.new()
	_diff_row.name = "DifficultyRow"
	_diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_diff_row.add_theme_constant_override("separation", 10)

	var caption := Label.new()
	caption.text = "Difficulty:"
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	_diff_row.add_child(caption)

	for item in [
		["Easy", GameState.Difficulty.EASY],
		["Normal", GameState.Difficulty.NORMAL],
		["Hard", GameState.Difficulty.HARD],
	]:
		var btn := Button.new()
		btn.text = item[0]
		btn.custom_minimum_size = Vector2(96, 36)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var level: int = item[1]
		btn.pressed.connect(func(): _select_difficulty(level))
		_diff_row.add_child(btn)

	_diff_label = Label.new()
	_diff_label.name = "DiffHint"
	_diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diff_label.add_theme_font_size_override("font_size", 14)
	_diff_label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.6))

	# Place after StartBtn (index of StartBtn + 1)
	var idx := start_btn.get_index() + 1
	vbox.add_child(_diff_row)
	vbox.move_child(_diff_row, idx)
	vbox.add_child(_diff_label)
	vbox.move_child(_diff_label, idx + 1)
	_refresh_diff_ui()


func _select_difficulty(level: int) -> void:
	if GameState:
		GameState.set_difficulty(level as GameState.Difficulty)
	_refresh_diff_ui()
	difficulty_changed.emit()


func _on_diff_changed(_level: int) -> void:
	_refresh_diff_ui()


func _refresh_diff_ui() -> void:
	if _diff_label == null or GameState == null:
		return
	var name := GameState.difficulty_label()
	var hint := ""
	match GameState.difficulty:
		GameState.Difficulty.EASY:
			hint = "2 enemies · low damage · more health/ammo"
		GameState.Difficulty.NORMAL:
			hint = "4 enemies · balanced"
		GameState.Difficulty.HARD:
			hint = "7 enemies · high damage · aggressive"
	_diff_label.text = "Selected: %s — %s" % [name, hint]
	# Highlight active button
	if _diff_row:
		for c in _diff_row.get_children():
			if c is Button:
				var b := c as Button
				var active := b.text.to_upper() == name
				b.disabled = false
				b.modulate = Color(1.2, 1.2, 0.7) if active else Color.WHITE


func show_title() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if title_label:
		title_label.text = "GODOT FPS"
	if subtitle:
		subtitle.text = "Two sectors · %s" % (GameState.sector_name() if GameState else "SECTOR ALPHA")
	if start_btn:
		start_btn.text = "CLICK TO PLAY"
	if controls:
		controls.text = "WASD Move  |  Shift Sprint  |  Mouse Look\nLMB Shoot  |  R Reload  |  E Open Doors  |  Esc Pause\nF9 Difficulty  |  F10 Quality  |  F11 Fullscreen  |  Q Quit"
	if _diff_row:
		_diff_row.visible = true
	if _diff_label:
		_diff_label.visible = true
	_refresh_diff_ui()


func show_paused() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if title_label:
		title_label.text = "PAUSED"
	if subtitle:
		subtitle.text = "Difficulty: %s" % (GameState.difficulty_label() if GameState else "")
	if start_btn:
		start_btn.text = "RESUME"
		start_btn.grab_focus()
	# Allow changing difficulty only on full restart, not mid-run resume
	if _diff_row:
		_diff_row.visible = false
	if _diff_label:
		_diff_label.visible = false


func show_dead() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if title_label:
		title_label.text = "YOU DIED"
	if subtitle:
		subtitle.text = "Score: %d  |  %s" % [GameState.score, GameState.difficulty_label()]
	if start_btn:
		start_btn.text = "RESTART"
	if _diff_row:
		_diff_row.visible = true
	if _diff_label:
		_diff_label.visible = true
	_refresh_diff_ui()


func show_sector_clear(sector: int, max_sectors: int) -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if title_label:
		title_label.text = "SECTOR %d CLEAR" % sector
	if subtitle:
		subtitle.text = "Score: %d  |  Proceed to sector %d / %d" % [GameState.score, sector + 1, max_sectors]
	if start_btn:
		start_btn.text = "NEXT SECTOR"
	if _diff_row:
		_diff_row.visible = false
	if _diff_label:
		_diff_label.visible = false


func show_win() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if title_label:
		title_label.text = "CAMPAIGN COMPLETE"
	if subtitle:
		subtitle.text = "Score: %d  |  %s" % [GameState.score, GameState.difficulty_label()]
	if start_btn:
		start_btn.text = "PLAY AGAIN"
	if _diff_row:
		_diff_row.visible = true
	if _diff_label:
		_diff_label.visible = true
	_refresh_diff_ui()


func _on_start() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if start_btn:
		start_btn.release_focus()
	get_viewport().gui_release_focus()
	start_pressed.emit()
