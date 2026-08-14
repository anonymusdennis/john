class_name PotatoModel
extends RefCounted
## Shared potato mesh setup for pickups and thrown grenades.

const SCENE_PATH := "res://assets/models/potato.glb"
const TEXTURE_PATH := "res://assets/models/potato_albedo.png"
const POTATO_TEXTURE: Texture2D = preload("res://assets/models/potato_albedo.png")
const TARGET_SIZE := 0.42


static func instantiate_visual() -> Node3D:
	var packed: PackedScene = load(SCENE_PATH)
	var visual := packed.instantiate() as Node3D
	_normalize(visual)
	_apply_texture(visual)
	return visual


static func collision_radius() -> float:
	return TARGET_SIZE * 0.52


static func _normalize(root: Node3D) -> void:
	var aabb := _mesh_aabb(root)
	if aabb.size == Vector3.ZERO:
		return
	var max_dim := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var s := TARGET_SIZE / max_dim
	root.scale = Vector3(s, s, s)
	root.position = -aabb.get_center() * s


static func _apply_texture(root: Node3D) -> void:
	if POTATO_TEXTURE == null:
		push_warning("PotatoModel: missing albedo texture at %s" % TEXTURE_PATH)
		return

	var mat := _make_potato_material()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	for mesh_i in meshes:
		if mesh_i.mesh == null:
			continue
		for i in mesh_i.mesh.get_surface_count():
			mesh_i.set_surface_override_material(i, mat)


static func _make_potato_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = POTATO_TEXTURE
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.58
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


static func _mesh_aabb(root: Node) -> AABB:
	var combined := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := node as MeshInstance3D
		if mesh_i.mesh == null:
			continue
		var local := mesh_i.transform * mesh_i.get_aabb()
		if first:
			combined = local
			first = false
		else:
			combined = combined.merge(local)
	if first:
		return AABB(Vector3(-0.21, -0.21, -0.21), Vector3(0.42, 0.42, 0.42))
	return combined
