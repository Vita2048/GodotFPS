extends RefCounted
## Shared readable silhouettes for thrown ordnance and world pickups.
static func material(color: String, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.metallic = metal
	m.roughness = 0.48 if metal > 0 else 0.8
	return m

static func part(root: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
	return mi

static func box(root: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return part(root, mesh, pos, mat)

static func cylinder(root: Node3D, pos: Vector3, radius: float, height: float, mat: Material, tip: float = -1) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if tip < 0 else tip
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	return part(root, mesh, pos, mat)

static func grenade(root: Node3D, armed: bool = false) -> void:
	var green := material("465435", 0.25)
	var dark := material("222a23", 0.35)
	var steel := material("939b94", 0.75)
	var yellow := material("cca64f", 0.2)
	var core := SphereMesh.new()
	core.radius = 0.087
	core.height = 0.22
	core.radial_segments = 16
	core.rings = 8
	part(root, core, Vector3.ZERO, dark)
	# Cast segmented shell with visible recessed grooves.
	var shell := MultiMeshInstance3D.new()
	var segments := MultiMesh.new()
	segments.transform_format = MultiMesh.TRANSFORM_3D
	var segment_mesh := BoxMesh.new()
	segment_mesh.size = Vector3(0.043, 0.04, 0.023)
	segment_mesh.material = green
	segments.mesh = segment_mesh
	segments.instance_count = 40
	shell.multimesh = segments
	root.add_child(shell)
	for row in 4:
		var y := -0.073 + row * 0.047
		var radius := 0.068 if row == 0 or row == 3 else 0.082
		for column in 10:
			var angle := column * TAU / 10
			segments.set_instance_transform(row * 10 + column, Transform3D(Basis(Vector3.UP, angle), Vector3(sin(angle)*radius, y, cos(angle)*radius)))
	cylinder(root, Vector3(0, 0.12, 0), 0.034, 0.035, steel)
	cylinder(root, Vector3(0, 0.088, 0), 0.051, 0.012, yellow)
	if not armed:
		box(root, Vector3(0.025, 0.149, 0), Vector3(0.1, 0.014, 0.028), steel)
		var spoon := box(root, Vector3(0.082, 0.04, 0), Vector3(0.017, 0.21, 0.028), steel)
		spoon.rotation.z = 0.18
		var ring := TorusMesh.new()
		ring.inner_radius = 0.022
		ring.outer_radius = 0.028
		ring.rings = 12
		ring.ring_segments = 6
		part(root, ring, Vector3(-0.061, 0.125, 0), steel).rotation.x = PI * 0.5

static func rocket(root: Node3D) -> void:
	var olive := material("546344", 0.35)
	var steel := material("4b5456", 0.65)
	var yellow := material("d7b354", 0.35)
	cylinder(root, Vector3(0, 0, 0), 0.028, 0.42, steel)
	cylinder(root, Vector3(0, 0.25, 0), 0.072, 0.19, olive, 0.008)
	cylinder(root, Vector3(0, 0.12, 0), 0.042, 0.07, olive, 0.072)
	cylinder(root, Vector3(0, 0.153, 0), 0.073, 0.018, yellow)
	for i in 4:
		var fin := box(root, Vector3.ZERO, Vector3(0.008, 0.12, 0.13), steel)
		fin.position.y = -0.16
		fin.rotation.y = i * PI * 0.5

static func ammo(root: Node3D) -> void:
	var olive := material("3c4c3a", 0.3)
	var edge := material("222b28", 0.55)
	var steel := material("9ba297", 0.7)
	var brass := material("b99344", 0.75)
	var copper := material("9c6042", 0.65)
	box(root, Vector3.ZERO, Vector3(0.48, 0.27, 0.3), olive)
	box(root, Vector3(0, -0.14, 0), Vector3(0.5, 0.025, 0.32), edge)
	box(root, Vector3(0, 0.143, 0), Vector3(0.51, 0.035, 0.33), edge)
	# Raised open lid, hinge and handle.
	var lid := box(root, Vector3(0, 0.29, -0.15), Vector3(0.51, 0.3, 0.025), olive)
	lid.rotation.x = -0.15
	box(root, Vector3(0, 0.35, -0.18), Vector3(0.16, 0.022, 0.025), steel)
	for x in [-0.08, 0.08]:
		box(root, Vector3(x, 0.32, -0.18), Vector3(0.022, 0.06, 0.025), steel)
	for x in [-0.18, 0.18]:
		box(root, Vector3(x, 0, 0.157), Vector3(0.042, 0.09, 0.018), steel)
	for i in 6:
		var x := -0.175 + i * 0.07
		cylinder(root, Vector3(x, 0.21, 0.025), 0.022, 0.12, brass)
		cylinder(root, Vector3(x, 0.296, 0.025), 0.021, 0.052, copper, 0.004)
	var label := Label3D.new()
	label.text = "5.45\n30 ROUNDS"
	label.font_size = 28
	label.pixel_size = 0.0017
	label.position = Vector3(0, 0, 0.155)
	label.modulate = Color("e0d6ac")
	root.add_child(label)
