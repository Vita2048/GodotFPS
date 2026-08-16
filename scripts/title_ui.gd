extends Control

signal start_pressed
signal difficulty_changed
signal map_changed

@onready var title_label: Label = $Center/VBox/Title
@onready var subtitle: Label = $Center/VBox/Subtitle
@onready var start_btn: Button = $Center/VBox/StartBtn
@onready var controls: Label = $Center/VBox/Controls

var _diff_label: Label
var _diff_row: HBoxContainer
var _map_row: HBoxContainer
var _map_label: Label
var _map_names: Array[String] = []
var _map_index: int = 0

func _ready() -> void:
	add_to_group("title_ui")
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	if start_btn:
		start_btn.pressed.connect(_on_start)
		start_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_difficulty_ui()
	_build_map_ui()
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


func set_maps(names: Array) -> void:
	_map_names.clear()
	for n in names:
		_map_names.append(String(n))
	_map_index = clampi(_map_index, 0, maxi(0, _map_names.size() - 1))
	_refresh_map_ui()


func selected_map_index() -> int:
	return _map_index


func _build_map_ui() -> void:
	var vbox := $Center/VBox as VBoxContainer
	if vbox == null or start_btn == null:
		return
	_map_row = HBoxContainer.new()
	_map_row.name = "MapRow"
	_map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_map_row.add_theme_constant_override("separation", 12)
	var cap := Label.new()
	cap.text = "Start map:"
	cap.add_theme_font_size_override("font_size", 16)
	cap.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	_map_row.add_child(cap)
	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(44, 36)
	prev.pressed.connect(func(): _shift_map(-1))
	_map_row.add_child(prev)
	_map_label = Label.new()
	_map_label.custom_minimum_size = Vector2(280, 0)
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_label.add_theme_font_size_override("font_size", 20)
	_map_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_map_row.add_child(_map_label)
	var nxt := Button.new()
	nxt.text = ">"
	nxt.custom_minimum_size = Vector2(44, 36)
	nxt.pressed.connect(func(): _shift_map(1))
	_map_row.add_child(nxt)
	var idx := start_btn.get_index() + 1
	if _diff_row:
		idx = _diff_row.get_index()
	vbox.add_child(_map_row)
	vbox.move_child(_map_row, idx)
	_refresh_map_ui()


func _shift_map(delta: int) -> void:
	if _map_names.is_empty():
		return
	_map_index = posmod(_map_index + delta, _map_names.size())
	_refresh_map_ui()
	map_changed.emit()


func _refresh_map_ui() -> void:
	if _map_label == null:
		return
	if _map_names.is_empty():
		_map_label.text = "E1M1"
		return
	_map_index = clampi(_map_index, 0, _map_names.size() - 1)
	_map_label.text = _map_names[_map_index]


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
			hint = "fewer monsters, lighter hits, extra HP/ammo"
		GameState.Difficulty.NORMAL:
			hint = "full mid-skill roster, balanced fight"
		GameState.Difficulty.HARD:
			hint = "UV roster, tougher and faster"
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
		var map_n := GameState.current_map_name if GameState else "E1M1"
		subtitle.text = "Quake BSP · %s" % map_n
	if start_btn:
		start_btn.text = "CLICK TO PLAY"
	if controls:
		controls.text = "WASD Move  |  Shift Sprint  |  Mouse Look\nHold LMB Fire  |  R Reload  |  E Open Doors  |  Esc Pause\nF9 Difficulty  |  F10 Quality  |  F11 Fullscreen  |  Q Quit"
	if _diff_row:
		_diff_row.visible = true
	if _diff_label:
		_diff_label.visible = true
	if _map_row:
		_map_row.visible = true
	_refresh_diff_ui()
	_refresh_map_ui()


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
	if _map_row:
		_map_row.visible = false


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
	if _map_row:
		_map_row.visible = true
	_refresh_diff_ui()
	_refresh_map_ui()


func show_sector_clear(sector: int, max_sectors: int) -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if title_label:
		title_label.text = "%s CLEAR" % (GameState.current_map_name if GameState else ("MAP %d" % sector))
	if subtitle:
		subtitle.text = "Score: %d  |  Proceed to map %d / %d" % [GameState.score, sector + 1, max_sectors]
	if start_btn:
		start_btn.text = "NEXT SECTOR"
	if _diff_row:
		_diff_row.visible = false
	if _diff_label:
		_diff_label.visible = false
	if _map_row:
		_map_row.visible = false


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
	if _map_row:
		_map_row.visible = true
	_refresh_diff_ui()
	_refresh_map_ui()


func _on_start() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if start_btn:
		start_btn.release_focus()
	get_viewport().gui_release_focus()
	start_pressed.emit()
