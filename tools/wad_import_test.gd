extends SceneTree

func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	print("[WADTEST] start")
	var wad_path := "res://assets/levels/doom1.WAD"
	if not FileAccess.file_exists(wad_path):
		print("[WADTEST] missing ", wad_path)
		quit(1)
		return
	var ps: PackedScene = load("res://addons/godotWad/WAD_Loader.tscn")
	if ps == null:
		print("[WADTEST] failed to load WAD_Loader.tscn")
		quit(1)
		return
	var loader: Node = ps.instantiate()
	root.add_child(loader)
	print("[WADTEST] loader ready, initializing")
	if loader.has_method("initialize"):
		loader.initialize([wad_path], "Doom", "doom")
	else:
		print("[WADTEST] no initialize")
		quit(1)
		return
	print("[WADTEST] maps=", loader.maps.keys() if "maps" in loader else "?")
	var map: Node = loader.createMap("E1M1", {"blankMap": true})
	print("[WADTEST] createMap result=", map)
	if map:
		print("[WADTEST] children=", map.get_child_count(), " name=", map.name)
	quit(0)
