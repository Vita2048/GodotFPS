@tool
extends EditorPlugin

var dock
var inspectoPluginFlags = preload("res://addons/godotWad/scenes/flagsEditorProperty/EditorInspectorPlugin.gd")

func _enter_tree():
	dock = load("res://addons/gameAssetImporter/scenes/toolbar.tscn").instantiate()
	dock.get_node("createAll").connect("pressed", Callable(self, "openMaker"))
	
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU,dock)
	dock.visible = false
	inspectoPluginFlags = inspectoPluginFlags.new()
	add_inspector_plugin(inspectoPluginFlags)


func openMaker() -> void:
	pass


func _exit_tree() -> void:
	if inspectoPluginFlags:
		remove_inspector_plugin(inspectoPluginFlags)
		inspectoPluginFlags = null
	if dock != null:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, dock)
		dock.queue_free()
		dock = null

