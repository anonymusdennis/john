extends MeshInstance3D
## F4 navigation debug view: draws sampled nodes (colored by clearance),
## special traversal edges, and each enemy's live path polyline.
## Attached and toggled by NavGraph; heavier than gameplay code but only
## rebuilds a few times a second and only around the camera.

const REBUILD_INTERVAL := 0.45
const VIEW_RADIUS := 32.0
const MAX_DRAW_NODES := 1200

var graph: Node3D                   ## NavGraph (untyped to avoid cycles).

var _mesh := ImmediateMesh.new()
var _timer := 0.0


func _ready() -> void:
	mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 10
	material_override = mat
	top_level = true
	global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	if not visible or graph == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REBUILD_INTERVAL
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := cam.global_position
	var pos: PackedVector3Array = graph.get("_pos")
	var headroom: PackedFloat32Array = graph.get("_headroom")
	var clear_r: PackedFloat32Array = graph.get("_clear_r")
	var edges: Array = graph.get("_edges")
	if pos.is_empty():
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var drew := 0
	var r2 := VIEW_RADIUS * VIEW_RADIUS
	for i in pos.size():
		if drew >= MAX_DRAW_NODES:
			break
		var p := pos[i]
		if p.distance_squared_to(center) > r2:
			continue
		# Node tick: green = spacious, red = tight crawl space.
		var tightness: float = clampf(minf(headroom[i] / 2.2, clear_r[i] / 0.8), 0.0, 1.0)
		var c := Color(1.0 - tightness, tightness, 0.15, 1.0)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p + Vector3.UP * (0.25 + headroom[i] * 0.06))
		drew += 1

		# Special edges from this node (walk edges would be visual noise).
		var e := edges[i] as PackedInt32Array
		for k in range(0, e.size(), 2):
			var j := e[k]
			var t := e[k + 1]
			var col := Color.TRANSPARENT
			match t:
				NavGraph.Edge.STEP: col = Color(0.95, 0.9, 0.2, 1.0)      # yellow
				NavGraph.Edge.JUMP: col = Color(1.0, 0.55, 0.1, 1.0)      # orange
				NavGraph.Edge.CLIMB: col = Color(0.9, 0.2, 0.9, 1.0)      # magenta
				NavGraph.Edge.WALL: col = Color(0.95, 0.15, 0.15, 1.0)    # red
			if col.a <= 0.0:
				continue
			_mesh.surface_set_color(col)
			_mesh.surface_add_vertex(p + Vector3.UP * 0.3)
			_mesh.surface_set_color(col)
			_mesh.surface_add_vertex(pos[j] + Vector3.UP * 0.3)

	# Live enemy paths.
	var paths: Dictionary = graph.get("debug_paths")
	for key in paths:
		var path := paths[key] as PackedVector3Array
		for s in range(path.size() - 1):
			_mesh.surface_set_color(Color(0.2, 0.9, 1.0, 1.0))
			_mesh.surface_add_vertex(path[s] + Vector3.UP * 0.5)
			_mesh.surface_set_color(Color(0.2, 0.9, 1.0, 1.0))
			_mesh.surface_add_vertex(path[s + 1] + Vector3.UP * 0.5)
			drew += 1
	if drew == 0:
		# ImmediateMesh cannot end an empty surface; add a degenerate segment.
		_mesh.surface_add_vertex(center)
		_mesh.surface_add_vertex(center)
	_mesh.surface_end()
