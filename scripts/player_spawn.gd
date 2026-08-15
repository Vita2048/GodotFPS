extends Resource
class_name PlayerSpawn
## Player start pose for the Duke FBX level (edited by Spawn Tuner).

@export var enabled: bool = false
@export var position: Vector3 = Vector3(0, 1.2, 0)
@export var yaw_degrees: float = 0.0

const PATH := "res://resources/player_spawn.tres"


static func load_or_default() -> PlayerSpawn:
	if ResourceLoader.exists(PATH):
		var res := load(PATH)
		if res is PlayerSpawn:
			return res as PlayerSpawn
	return PlayerSpawn.new()


static func save_spawn(spawn: PlayerSpawn) -> Error:
	return ResourceSaver.save(spawn, PATH)
