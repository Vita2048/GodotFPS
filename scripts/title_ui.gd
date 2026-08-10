extends Control

signal start_pressed

@onready var title_label: Label = $Center/VBox/Title
@onready var subtitle: Label = $Center/VBox/Subtitle
@onready var start_btn: Button = $Center/VBox/StartBtn
@onready var controls: Label = $Center/VBox/Controls

func _ready() -> void:
	add_to_group("title_ui")
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	if start_btn:
		start_btn.pressed.connect(_on_start)
		start_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	show_title()


func show_title() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if title_label:
		title_label.text = "GODOT FPS"
	if subtitle:
		subtitle.text = "Procedural Sector Assault"
	if start_btn:
		start_btn.text = "CLICK TO PLAY"
	if controls:
		controls.text = "WASD Move  |  Shift Sprint  |  Mouse Look\nLMB Shoot  |  R Reload  |  E Open Doors  |  Esc Pause\nF10 Quality  |  F11 Fullscreen  |  Q Quit"


func show_paused() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if title_label:
		title_label.text = "PAUSED"
	if subtitle:
		subtitle.text = ""
	if start_btn:
		start_btn.text = "RESUME"
		start_btn.grab_focus()


func show_dead() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if title_label:
		title_label.text = "YOU DIED"
	if subtitle:
		subtitle.text = "Score: %d" % GameState.score
	if start_btn:
		start_btn.text = "RESTART"


func show_win() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if title_label:
		title_label.text = "SECTOR CLEARED"
	if subtitle:
		subtitle.text = "Score: %d" % GameState.score
	if start_btn:
		start_btn.text = "PLAY AGAIN"


func _on_start() -> void:
	visible = false
	# Critical: hidden UI must not keep mouse focus / filter
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if start_btn:
		start_btn.release_focus()
	get_viewport().gui_release_focus()
	start_pressed.emit()
