class_name VoxelVegetation
extends Node3D
## Streamed vegetation for the voxel terrain: grass + realistic mesh trees.
##
## - Trees are REAL meshes (tapered trunks, branches, foliage crowns / stacked
##   pine skirts) — not voxels. A handful of ArrayMesh variants are built once
##   and shared by every instance, so hundreds of trees cost almost nothing.
##   Trunks get a simple cylinder collider on the world layer.
## - Grass is per-cell MultiMesh tufts with a wind-sway shader, placed only on
##   grassy/mossy ground away from cliffs and water.
## - Everything is deterministic (seeded by world seed + cell coords) and
##   streamed in a budgeted way around the player: a few cells per frame,
##   far cells freed. No spikes, no fabricated content — placement comes
##   straight from the TerrainModel so mappers can rely on it.
##
## Stock-Godot safe: pure Node3D / MultiMesh code, no godot_voxel references.

const TREE_CELL := 48.0
const TREE_RADIUS := 168.0
const GRASS_CELL := 16.0
const GRASS_RADIUS := 56.0
const CELLS_PER_FRAME := 2
const GRASS_PER_CELL := 70
const FREE_MARGIN := 1.35

const CH_GRASS := 8
const CH_DIRT := 7
const CH_MOSS := 13

var _model: TerrainModel = null
var _cache := {}
var _tree_cells := {}                   # Vector2i -> Node3D container
var _grass_cells := {}                  # Vector2i -> Node3D container
var _queue: Array = []                  # [is_tree: bool, cell: Vector2i]
var _queued := {}                       # dedupe set
var _player: Node3D = null
var _scan_timer := 0.0

var _oak_meshes: Array = []
var _pine_meshes: Array = []
var _grass_mesh: Mesh = null
var _bark_mat: StandardMaterial3D = null
var _leaf_mat: StandardMaterial3D = null
var _pine_leaf_mat: StandardMaterial3D = null
var _grass_mat: ShaderMaterial = null


func setup(model: TerrainModel) -> void:
	_model = model


func _ready() -> void:
	if _model == null:
		set_process(false)
		return
	_build_materials()
	var rng := RandomNumberGenerator.new()
	rng.seed = _model.world_seed * 31 + 7
	for i in 4:
		_oak_meshes.append(_build_oak_mesh(rng))
	for i in 3:
		_pine_meshes.append(_build_pine_mesh(rng))
	_grass_mesh = _build_grass_tuft_mesh(rng)


func _process(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.4
		_refresh_focus()
	var budget := CELLS_PER_FRAME
	while budget > 0 and not _queue.is_empty():
		var job: Array = _queue.pop_front()
		_queued.erase(job)
		_build_cell(job[0], job[1])
		budget -= 1
	# Keep the model query cache from growing without bound on long sessions.
	if _cache.size() > 150000:
		_cache.clear()


func _refresh_focus() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var p := _player.global_position
	_scan_grid(true, p, TREE_RADIUS, TREE_CELL, _tree_cells)
	_scan_grid(false, p, GRASS_RADIUS, GRASS_CELL, _grass_cells)
	_free_far(p, TREE_RADIUS * FREE_MARGIN + TREE_CELL, TREE_CELL, _tree_cells)
	_free_far(p, GRASS_RADIUS * FREE_MARGIN + GRASS_CELL, GRASS_CELL, _grass_cells)


func _scan_grid(is_tree: bool, p: Vector3, radius: float, cell: float, cells: Dictionary) -> void:
	var c0x := int(floorf((p.x - radius) / cell))
	var c1x := int(floorf((p.x + radius) / cell))
	var c0z := int(floorf((p.z - radius) / cell))
	var c1z := int(floorf((p.z + radius) / cell))
	var new_jobs: Array = []
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			var key := Vector2i(cx, cz)
			if cells.has(key):
				continue
			var center := Vector2((cx + 0.5) * cell, (cz + 0.5) * cell)
			if center.distance_to(Vector2(p.x, p.z)) > radius + cell:
				continue
			var job := [is_tree, key]
			if _queued.has(job):
				continue
			new_jobs.append(job)
	if new_jobs.is_empty():
		return
	var pp := Vector2(p.x, p.z)
	new_jobs.sort_custom(func(a, b):
		var ca: Vector2i = a[1]
		var cb: Vector2i = b[1]
		return Vector2(ca.x, ca.y).distance_squared_to(pp / cell) \
				< Vector2(cb.x, cb.y).distance_squared_to(pp / cell))
	for job in new_jobs:
		_queued[job] = true
		_queue.append(job)


func _free_far(p: Vector3, max_dist: float, cell: float, cells: Dictionary) -> void:
	var dead: Array = []
	for key: Vector2i in cells:
		var center := Vector2((key.x + 0.5) * cell, (key.y + 0.5) * cell)
		if center.distance_to(Vector2(p.x, p.z)) > max_dist:
			dead.append(key)
	for key: Vector2i in dead:
		var node: Node = cells[key]
		if is_instance_valid(node):
			node.queue_free()
		cells.erase(key)


func _build_cell(is_tree: bool, key: Vector2i) -> void:
	if is_tree:
		if _tree_cells.has(key):
			return
		_tree_cells[key] = _build_tree_cell(key)
	else:
		if _grass_cells.has(key):
			return
		_grass_cells[key] = _build_grass_cell(key)


## --- Trees ----------------------------------------------------------------

func _build_tree_cell(key: Vector2i) -> Node3D:
	var container := Node3D.new()
	container.name = "Trees_%d_%d" % [key.x, key.y]
	add_child(container)
	var x0 := key.x * TREE_CELL
	var z0 := key.y * TREE_CELL
	var trees: Array = _model.trees_in_rect(x0, z0, x0 + TREE_CELL, z0 + TREE_CELL, _cache)
	for t: Dictionary in trees:
		var pos: Vector3 = t["pos"]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(int(pos.x * 8.0), int(pos.z * 8.0), _model.world_seed))
		var is_pine: bool = t["type"] == "tree_pine"
		var variants: Array = _pine_meshes if is_pine else _oak_meshes
		var mesh: ArrayMesh = variants[rng.randi_range(0, variants.size() - 1)]

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var s := rng.randf_range(0.85, 1.35)
		mi.transform = Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
			pos - Vector3.UP * 0.35)
		container.add_child(mi)

		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = (0.30 if is_pine else 0.38) * s
		shape.height = 5.0 * s
		col.shape = shape
		col.position = Vector3.UP * (2.5 * s - 0.35)
		body.add_child(col)
		mi.add_child(body)
	return container


## --- Grass ------------------------------------------------------------------

func _build_grass_cell(key: Vector2i) -> Node3D:
	var container := Node3D.new()
	container.name = "Grass_%d_%d" % [key.x, key.y]
	add_child(container)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, _model.world_seed ^ 0x517CC1B7))
	var x0 := key.x * GRASS_CELL
	var z0 := key.y * GRASS_CELL

	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in GRASS_PER_CELL:
		var wx := x0 + rng.randf() * GRASS_CELL
		var wz := z0 + rng.randf() * GRASS_CELL
		var s: Dictionary = _model.sample_surface(wx, wz, _cache)
		var ch: int = s["surf_ch"]
		if ch != CH_GRASS and ch != CH_MOSS and ch != CH_DIRT:
			continue
		if ch == CH_DIRT and rng.randf() > 0.25:
			continue
		if s["grad"] > 0.85:
			continue
		var h: float = s["h"]
		if h < _model.sea_level + 0.4:
			continue
		if float(s["water_y"]) > -1e8:
			continue
		var sc := rng.randf_range(0.7, 1.5)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc)
		transforms.append(Transform3D(basis, Vector3(wx, h - 0.05, wz)))
		var moist: float = s["moist"]
		var green := Color(0.32, 0.52, 0.18).lerp(Color(0.24, 0.47, 0.23), moist)
		green = green.lerp(Color(0.55, 0.52, 0.22), rng.randf() * 0.35)
		if ch == CH_MOSS:
			green = green.lerp(Color(0.20, 0.42, 0.26), 0.6)
		colors.append(green)
	if transforms.is_empty():
		return container

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _grass_mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	container.add_child(mmi)
	return container


## --- Mesh builders -----------------------------------------------------------

func _build_materials() -> void:
	_bark_mat = StandardMaterial3D.new()
	_bark_mat.vertex_color_use_as_albedo = true
	_bark_mat.roughness = 1.0

	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.vertex_color_use_as_albedo = true
	_leaf_mat.roughness = 1.0
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_pine_leaf_mat = _leaf_mat

	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = load("res://scripts/voxel/grass.gdshader")


## Oak: bent tapered trunk, a few main branches, irregular foliage blobs.
func _build_oak_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf := SurfaceTool.new()
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)

	var height := rng.randf_range(4.2, 5.8)
	var lean := Vector3(rng.randf_range(-0.14, 0.14), 0, rng.randf_range(-0.14, 0.14))
	var bark_col := Color(0.30, 0.22, 0.14).lerp(Color(0.38, 0.29, 0.19), rng.randf())

	# Trunk: stacked rings with a gentle bend.
	var segs := 5
	var prev_center := Vector3.ZERO
	var centers: Array[Vector3] = [Vector3.ZERO]
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var c := prev_center + Vector3(0, height / segs, 0) \
				+ lean * (height / segs) * t \
				+ Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
		centers.append(c)
		prev_center = c
	var radii: Array[float] = []
	for i in range(segs + 1):
		radii.append(lerpf(0.42, 0.14, float(i) / segs) * rng.randf_range(0.9, 1.1))
	_tube(bark, centers, radii, 8, bark_col, rng)

	var top := centers[segs]

	# Branches from the upper trunk.
	var n_branch := rng.randi_range(2, 4)
	var branch_tips: Array[Vector3] = []
	for i in n_branch:
		var t := rng.randf_range(0.55, 0.9)
		var base := centers[int(t * segs)]
		var ang := rng.randf() * TAU
		var up := rng.randf_range(0.5, 1.1)
		var out := rng.randf_range(1.1, 2.0)
		var tip := base + Vector3(cos(ang) * out, up + 0.6, sin(ang) * out)
		_tube(bark, [base, base.lerp(tip, 0.5) + Vector3.UP * 0.15, tip],
				[0.13, 0.09, 0.05], 5, bark_col.darkened(0.08), rng)
		branch_tips.append(tip)

	# Foliage: irregular blobs over the crown and branch tips.
	var leaf_base := Color(0.20, 0.38, 0.12).lerp(Color(0.28, 0.45, 0.16), rng.randf())
	var blob_centers: Array[Vector3] = [top + Vector3.UP * 0.8]
	for tip in branch_tips:
		blob_centers.append(tip + Vector3.UP * 0.35)
	var extra := rng.randi_range(2, 3)
	for i in extra:
		var ang := rng.randf() * TAU
		blob_centers.append(top + Vector3(cos(ang), rng.randf_range(0.2, 1.1), sin(ang)) * rng.randf_range(0.7, 1.4))
	for c in blob_centers:
		var r := rng.randf_range(0.9, 1.6)
		_blob(leaf, c, Vector3(r, r * rng.randf_range(0.62, 0.85), r), leaf_base, rng)

	var mesh := bark.commit()
	mesh = leaf.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, _leaf_mat)
	return mesh


## Pine: tall thin trunk with layered drooping cone skirts.
func _build_pine_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf := SurfaceTool.new()
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)

	var height := rng.randf_range(7.0, 10.5)
	var bark_col := Color(0.26, 0.18, 0.11).lerp(Color(0.33, 0.24, 0.15), rng.randf())
	var centers: Array[Vector3] = []
	var radii: Array[float] = []
	var segs := 4
	for i in range(segs + 1):
		var t := float(i) / segs
		centers.append(Vector3(rng.randf_range(-0.05, 0.05) * t, height * t, rng.randf_range(-0.05, 0.05) * t))
		radii.append(lerpf(0.30, 0.05, t))
	_tube(bark, centers, radii, 7, bark_col, rng)

	var leaf_col := Color(0.10, 0.26, 0.13).lerp(Color(0.16, 0.33, 0.17), rng.randf())
	var skirt_lo := height * 0.22
	var n_skirts := rng.randi_range(5, 7)
	for i in n_skirts:
		var t := float(i) / maxf(1.0, n_skirts - 1)
		var y := lerpf(skirt_lo, height * 0.96, t)
		var r := lerpf(2.1, 0.45, t) * rng.randf_range(0.85, 1.15)
		var droop := r * 0.5
		_cone_skirt(leaf, Vector3(0, y, 0), r, droop, 9,
				leaf_col.lightened(rng.randf() * 0.08), rng)
	# Tip.
	_cone_skirt(leaf, Vector3(0, height * 1.02, 0), 0.3, 0.5, 6, leaf_col, rng)

	var mesh := bark.commit()
	mesh = leaf.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, _pine_leaf_mat)
	return mesh


## Grass tuft: several crossed bent blades, color from per-instance COLOR.
## Vertex COLOR.a carries sway weight for the wind shader.
func _build_grass_tuft_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 6
	for i in blades:
		var ang := (float(i) / blades) * TAU + rng.randf() * 0.7
		var dir := Vector3(cos(ang), 0, sin(ang))
		var base := dir * rng.randf_range(0.02, 0.14)
		var h := rng.randf_range(0.25, 0.55)
		var w := rng.randf_range(0.03, 0.05)
		var bend := dir * rng.randf_range(0.08, 0.2)
		var side := dir.cross(Vector3.UP) * w
		var tip := base + Vector3.UP * h + bend
		var mid := base + Vector3.UP * (h * 0.5) + bend * 0.35
		var n := Vector3.UP
		# Two quads: base->mid, mid->tip (tapered), sway weight in COLOR.a.
		_blade_quad(st, base - side, base + side, mid - side * 0.7, mid + side * 0.7, n, 0.0, 0.45)
		_blade_quad(st, mid - side * 0.7, mid + side * 0.7, tip, tip + side * 0.05, n, 0.45, 1.0)
	var mesh := st.commit()
	return mesh


func _blade_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		n: Vector3, w_lo: float, w_hi: float) -> void:
	# COLOR rgb is multiplied by instance color in the shader; alpha = sway.
	st.set_normal(n)
	st.set_color(Color(1, 1, 1, w_lo)); st.add_vertex(a)
	st.set_color(Color(1, 1, 1, w_lo)); st.add_vertex(b)
	st.set_color(Color(1, 1, 1, w_hi)); st.add_vertex(c)
	st.set_color(Color(1, 1, 1, w_lo)); st.add_vertex(b)
	st.set_color(Color(1, 1, 1, w_hi)); st.add_vertex(d)
	st.set_color(Color(1, 1, 1, w_hi)); st.add_vertex(c)


## Tapered multi-ring tube between successive centers (smooth-ish normals).
func _tube(st: SurfaceTool, centers: Array, radii: Array, sides: int,
		col: Color, rng: RandomNumberGenerator) -> void:
	for i in range(centers.size() - 1):
		var c0: Vector3 = centers[i]
		var c1: Vector3 = centers[i + 1]
		var r0: float = radii[i]
		var r1: float = radii[i + 1]
		for j in sides:
			var a0 := (float(j) / sides) * TAU
			var a1 := (float(j + 1) / sides) * TAU
			var n0 := Vector3(cos(a0), 0, sin(a0))
			var n1 := Vector3(cos(a1), 0, sin(a1))
			var v00 := c0 + n0 * r0
			var v01 := c0 + n1 * r0
			var v10 := c1 + n0 * r1
			var v11 := c1 + n1 * r1
			var cc := col.lightened(rng.randf() * 0.05)
			st.set_color(cc)
			st.set_normal(n0); st.add_vertex(v00)
			st.set_normal(n0); st.add_vertex(v10)
			st.set_normal(n1); st.add_vertex(v01)
			st.set_normal(n1); st.add_vertex(v01)
			st.set_normal(n0); st.add_vertex(v10)
			st.set_normal(n1); st.add_vertex(v11)
	# Cap the top.
	var top: Vector3 = centers[centers.size() - 1]
	var rt: float = radii[radii.size() - 1]
	for j in sides:
		var a0 := (float(j) / sides) * TAU
		var a1 := (float(j + 1) / sides) * TAU
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(top + Vector3(cos(a0), 0, sin(a0)) * rt)
		st.add_vertex(top + Vector3.UP * rt * 0.4)
		st.add_vertex(top + Vector3(cos(a1), 0, sin(a1)) * rt)


## Irregular foliage ellipsoid (perturbed UV-sphere).
func _blob(st: SurfaceTool, center: Vector3, r: Vector3, col: Color,
		rng: RandomNumberGenerator) -> void:
	var rings := 4
	var sides := 6
	var jitter := 0.16
	# Precompute perturbed vertices so shared corners match.
	var verts := {}
	for ri in range(rings + 1):
		for si in range(sides + 1):
			var key := Vector2i(ri, si % sides)
			if verts.has(key):
				continue
			var phi := PI * float(ri) / rings
			var theta := TAU * float(si % sides) / sides
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var wobble := 1.0 + (rng.randf() - 0.5) * 2.0 * jitter
			verts[key] = center + dir * r * wobble
	for ri in rings:
		for si in sides:
			var k00 := Vector2i(ri, si)
			var k01 := Vector2i(ri, (si + 1) % sides)
			var k10 := Vector2i(ri + 1, si)
			var k11 := Vector2i(ri + 1, (si + 1) % sides)
			var v00: Vector3 = verts[k00]
			var v01: Vector3 = verts[k01]
			var v10: Vector3 = verts[k10]
			var v11: Vector3 = verts[k11]
			var cc := col.lightened(rng.randf() * 0.10).darkened(rng.randf() * 0.06)
			st.set_color(cc)
			var n := (v00 - center).normalized()
			st.set_normal(n)
			if ri > 0:
				st.add_vertex(v00); st.add_vertex(v10); st.add_vertex(v01)
			if ri < rings - 1:
				st.add_vertex(v01); st.add_vertex(v10); st.add_vertex(v11)


## Drooping pine skirt: open cone from apex ring down/out to hem.
func _cone_skirt(st: SurfaceTool, apex: Vector3, radius: float, droop: float,
		sides: int, col: Color, rng: RandomNumberGenerator) -> void:
	for j in sides:
		var a0 := (float(j) / sides) * TAU
		var a1 := (float(j + 1) / sides) * TAU
		var r0 := radius * rng.randf_range(0.9, 1.1)
		var r1 := radius * rng.randf_range(0.9, 1.1)
		var hem0 := apex + Vector3(cos(a0) * r0, -droop, sin(a0) * r0)
		var hem1 := apex + Vector3(cos(a1) * r1, -droop, sin(a1) * r1)
		var n := ((hem0 - apex).cross(hem1 - apex)).normalized()
		if n.y < 0.0:
			n = -n
		st.set_color(col.lightened(rng.randf() * 0.06))
		st.set_normal(n)
		st.add_vertex(apex)
		st.add_vertex(hem1)
		st.add_vertex(hem0)
