extends SceneTree

func _init() -> void:
	var ps: PackedScene = load("res://assets/guns/animated_aks-74u.glb")
	if ps == null:
		print("[GUN] failed to load")
		quit(1)
		return
	var n: Node = ps.instantiate()
	var players := n.find_children("*", "AnimationPlayer", true, false)
	print("[GUN] AnimationPlayers=", players.size())
	for p in players:
		var ap := p as AnimationPlayer
		print("[GUN] player=", ap.get_path(), " list=", ap.get_animation_list())
	quit(0)
