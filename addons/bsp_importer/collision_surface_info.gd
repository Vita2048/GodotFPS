extends Resource

class_name CollisionSurfaceInfo

## Class will be stored as a metadata array on the collision shape node
@export var has_alpha_test := false
#var image : Image = null  - this makes a copy, so don't store that.
@export var texture : Texture2D = null
@export var normal : Vector3
@export var verts : Array[Vector3] = [] # There's a bug where PackedVector3Array doesn't save. :( https://github.com/godotengine/godot/issues/77133
@export var uvs : Array[Vector2] = [] # Also bugged.
#var material_type : int # To be used in the future for metal, wood, etc.
