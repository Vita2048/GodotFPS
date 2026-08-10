extends Resource
class_name EnemyWeaponPose
## Shared pose for the enemy handgun (edited by Weapon Tuner scene).

@export var position: Vector3 = Vector3(6.7, 17.6, 4.5)
@export var rotation_degrees: Vector3 = Vector3(10.0, -2.0, -92.0)
## Target length in skeleton-cm space (model root is scaled ×0.01).
@export var length_cm: float = 22.0

const PATH := "res://resources/enemy_weapon_pose.tres"


static func load_or_default() -> EnemyWeaponPose:
	if ResourceLoader.exists(PATH):
		var res := load(PATH)
		if res is EnemyWeaponPose:
			return res as EnemyWeaponPose
	return EnemyWeaponPose.new()


static func save_pose(pose: EnemyWeaponPose) -> Error:
	return ResourceSaver.save(pose, PATH)
