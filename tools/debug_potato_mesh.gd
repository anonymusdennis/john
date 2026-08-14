@tool
extends EditorScript

func _run() -> void:
	var packed: PackedScene = load("res://assets/models/potato.glb")
	var root := packed.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	for m in meshes:
		print("Mesh: ", m.name)
		if m.mesh:
			print("  surfaces: ", m.mesh.get_surface_count())
			for i in m.mesh.get_surface_count():
				var arrays = m.mesh.surface_get_arrays(i)
				print("  surface ", i, " ARRAY_TEX_UV size: ", (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() if arrays[Mesh.ARRAY_TEX_UV] else 0)
				print("  surface ", i, " ARRAY_COLOR size: ", (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() if arrays[Mesh.ARRAY_COLOR] else 0)


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
