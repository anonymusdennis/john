extends Node3D
## VoxelWorld — runtime host for the smooth voxel terrain (godot_voxel module).
##
## Space Engineers-style destructible world:
## - Streams the baked Big Globe-inspired world from a VoxelStreamSQLite database
##   (baked offline by tools/worldgen/bake_world.gd — the generator never ships).
## - Meshes with VoxelMesherTransvoxel (smooth isosurface — no cubes).
## - Exposes carve/place/paint sphere edits used by the player build tool and
##   by potatonades.
## - Persists player edits: the baked database is copied to user:// on first run
##   and modified blocks are saved back into that copy.
##
## IMPORTANT: this script is stock-Godot safe. It never references godot_voxel
## classes statically — everything goes through ClassDB. Without the module the
## game boots normally and keeps the legacy flat Ground.

signal voxel_edited(center: Vector3, radius: float)

const BAKED_DB_PATH := "res://world/world.sqlite"
const BAKED_META_PATH := "res://world/world_meta.json"
const USER_DIR := "user://voxel"
const USER_DB_PATH := "user://voxel/world.sqlite"

## Physics: world (1) + nav_surface (32) so NavGraph column sampling works.
const TERRAIN_COLLISION_LAYER := 33

@export var lod_count: int = 5
@export var lod_distance: float = 64.0
@export var view_distance: int = 512
@export var collision_view_distance: int = 192
## When there is no baked world, generate live using the dev generator in
## res://tools/worldgen/ (present in the repo, excluded from exports).
@export var allow_live_dev_generator: bool = true

var _terrain: Variant = null            # VoxelLodTerrain (duck-typed)
var _viewer: Variant = null             # VoxelViewer (duck-typed)
var _registry: VoxelBlockRegistry = null
var _meta: Dictionary = {}
var _active := false
var _spawn_platform: StaticBody3D = null
var _save_timer: Timer = null


func _ready() -> void:
	add_to_group("voxel_world")
	_registry = VoxelBlockRegistry.create()

	if not ClassDB.class_exists("VoxelLodTerrain"):
		print("[VoxelWorld] godot_voxel module not found — voxel terrain disabled. ",
				"Run a voxel-enabled Godot build (see voxel-platform-handoff/IMPLEMENTATION-NOTES.md). ",
				"Keeping legacy flat Ground.")
		return

	_meta = _load_meta()
	var stream: Variant = _prepare_stream()
	var generator: Variant = null
	if stream == null:
		generator = _load_dev_generator()
		if generator == null:
			print("[VoxelWorld] No baked world at %s and no dev generator available — voxel terrain disabled." % BAKED_DB_PATH)
			return
		print("[VoxelWorld] No baked world found — running LIVE dev generation (slower). ",
				"Bake with tools/worldgen/bake_world.gd for the shipping world.")

	_build_terrain(stream, generator)
	_active = true
	_disable_legacy_ground()
	_setup_spawn_protection()
	_build_water()
	_setup_autosave()
	_spawn_edit_tool()
	print("[VoxelWorld] Voxel terrain active. bounds=%s" % [str(_bounds())])


func is_active() -> bool:
	return _active


## --- Editing API (used by voxel_edit_tool.gd and grenade_projectile.gd) -------

func carve_sphere(center: Vector3, radius: float) -> void:
	if not _active:
		return
	var vt: Variant = _terrain.get_voxel_tool()
	vt.channel = 1                        # VoxelBuffer.CHANNEL_SDF
	vt.mode = 1                           # VoxelTool.MODE_REMOVE
	vt.do_sphere(center, radius)
	voxel_edited.emit(center, radius)


func place_sphere(center: Vector3, radius: float, channel: int) -> void:
	if not _active:
		return
	var vt: Variant = _terrain.get_voxel_tool()
	vt.channel = 1                        # VoxelBuffer.CHANNEL_SDF
	vt.mode = 0                           # VoxelTool.MODE_ADD
	vt.do_sphere(center, radius)
	_paint(vt, center, radius + 1.0, channel)
	voxel_edited.emit(center, radius)


func paint_sphere(center: Vector3, radius: float, channel: int) -> void:
	if not _active:
		return
	var vt: Variant = _terrain.get_voxel_tool()
	_paint(vt, center, radius, channel)
	voxel_edited.emit(center, radius)


## Raycast against voxel SDF data (works even where physics hasn't meshed yet).
## Returns {hit: bool, position: Vector3, inside: Vector3}
func raycast_voxel(origin: Vector3, dir: Vector3, max_distance: float) -> Dictionary:
	if not _active:
		return {"hit": false}
	var vt: Variant = _terrain.get_voxel_tool()
	var res: Variant = vt.raycast(origin, dir, max_distance)
	if res == null:
		return {"hit": false}
	var inside: Vector3 = Vector3(res.position) + Vector3.ONE * 0.5
	var outside: Vector3 = Vector3(res.previous_position) + Vector3.ONE * 0.5
	return {"hit": true, "position": outside, "inside": inside}


func selected_material_name(channel: int) -> String:
	return _registry.channel_name(channel)


func registry() -> VoxelBlockRegistry:
	return _registry


func save_edits() -> void:
	if _active and _terrain.has_method("save_modified_blocks"):
		_terrain.save_modified_blocks()


## --- Setup internals -----------------------------------------------------------

func _paint(vt: Variant, center: Vector3, radius: float, channel: int) -> void:
	vt.mode = 3                           # VoxelTool.MODE_TEXTURE_PAINT
	vt.texture_index = clampi(channel, 0, 15)
	vt.texture_opacity = 1.0
	vt.texture_falloff = 0.35
	vt.do_sphere(center, radius)


func _load_meta() -> Dictionary:
	if not FileAccess.file_exists(BAKED_META_PATH):
		return {}
	var f := FileAccess.open(BAKED_META_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## Copies the shipped baked database into user:// (once) so edits persist
## without touching the shipped data. Returns a VoxelStreamSQLite or null.
func _prepare_stream() -> Variant:
	if not FileAccess.file_exists(BAKED_DB_PATH):
		return null
	if not ClassDB.class_exists("VoxelStreamSQLite"):
		push_warning("[VoxelWorld] VoxelStreamSQLite class missing in this build")
		return null

	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var reset := "--voxel-reset" in OS.get_cmdline_user_args()
	if reset or not FileAccess.file_exists(USER_DB_PATH):
		if not _copy_file(BAKED_DB_PATH, USER_DB_PATH):
			push_warning("[VoxelWorld] Failed to copy baked world to user:// — playing read-only from res:// will not persist edits")
			return null
		print("[VoxelWorld] Baked world copied to ", USER_DB_PATH)

	var stream: Variant = ClassDB.instantiate("VoxelStreamSQLite")
	stream.database_path = USER_DB_PATH
	return stream


func _copy_file(from_path: String, to_path: String) -> bool:
	var src := FileAccess.open(from_path, FileAccess.READ)
	if src == null:
		return false
	var dst := FileAccess.open(to_path, FileAccess.WRITE)
	if dst == null:
		return false
	const CHUNK := 8 * 1024 * 1024
	while src.get_position() < src.get_length():
		dst.store_buffer(src.get_buffer(CHUNK))
	src.close()
	dst.close()
	return true


## Dev-only: live generation straight from the baker's generator script.
## tools/ is excluded from exports, so shipped builds never contain it.
func _load_dev_generator() -> Variant:
	if not allow_live_dev_generator:
		return null
	const GEN_PATH := "res://tools/worldgen/bg_generator.gd"
	if not ResourceLoader.exists(GEN_PATH):
		return null
	var script: Variant = load(GEN_PATH)
	if script == null:
		return null
	var gen: Variant = script.new()
	if gen.has_method("configure_defaults"):
		gen.configure_defaults()
	return gen


func _bounds() -> AABB:
	var b: Dictionary = _meta.get("bounds", {})
	var bmin: Array = b.get("min", [-1024.0, -512.0, -1024.0])
	var bsize: Array = b.get("size", [2048.0, 768.0, 2048.0])
	return AABB(
		Vector3(bmin[0], bmin[1], bmin[2]),
		Vector3(bsize[0], bsize[1], bsize[2]))


func _build_terrain(stream: Variant, generator: Variant) -> void:
	_terrain = ClassDB.instantiate("VoxelLodTerrain")
	_terrain.name = "VoxelTerrain"

	var mesher: Variant = ClassDB.instantiate("VoxelMesherTransvoxel")
	mesher.texturing_mode = 1             # TEXTURES_MIXEL4_S4 (4-blend over 16)
	_terrain.mesher = mesher

	if stream != null:
		_terrain.stream = stream
	if generator != null:
		_terrain.generator = generator

	_terrain.material = _make_terrain_material()
	_terrain.lod_count = lod_count
	_terrain.lod_distance = lod_distance
	if "view_distance" in _terrain:
		_terrain.view_distance = view_distance
	_terrain.voxel_bounds = _bounds()
	_terrain.generate_collisions = true
	_terrain.collision_layer = TERRAIN_COLLISION_LAYER
	_terrain.collision_mask = 0
	add_child(_terrain)

	# Streaming needs a viewer: follow the player.
	_viewer = ClassDB.instantiate("VoxelViewer")
	_viewer.view_distance = view_distance
	_viewer.requires_visuals = true
	_viewer.requires_collisions = true
	if "collision_view_distance" in _viewer:
		_viewer.collision_view_distance = collision_view_distance
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.add_child(_viewer)
	else:
		add_child(_viewer)


func _make_terrain_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/voxel/voxel_terrain.gdshader")
	mat.set_shader_parameter("u_albedo", VoxelBlockRegistry.channel_albedos())
	mat.set_shader_parameter("u_params", VoxelBlockRegistry.channel_params())
	var core_top: float = float(_meta.get("core_top_y", -430.0))
	mat.set_shader_parameter("u_core_top_y", core_top)
	return mat


func _disable_legacy_ground() -> void:
	var ground := get_parent().get_node_or_null("Ground")
	if ground is CollisionObject3D:
		(ground as CollisionObject3D).collision_layer = 0
	if ground is Node3D:
		(ground as Node3D).visible = false
		print("[VoxelWorld] Legacy flat Ground disabled (voxels own the floor now)")


## Terrain streams asynchronously: park the player on an invisible platform at
## the baked spawn point until real voxel collision exists underneath.
func _setup_spawn_protection() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return

	var spawn := _spawn_point()
	player.global_position = spawn + Vector3.UP * 1.5

	_spawn_platform = StaticBody3D.new()
	_spawn_platform.name = "VoxelSpawnPlatform"
	_spawn_platform.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 1, 6)
	col.shape = box
	_spawn_platform.add_child(col)
	add_child(_spawn_platform)
	_spawn_platform.global_position = spawn - Vector3.UP * 0.5

	var poll := Timer.new()
	poll.wait_time = 0.5
	poll.timeout.connect(_check_spawn_ground.bind(poll))
	add_child(poll)
	poll.start()


func _spawn_point() -> Vector3:
	var s: Array = _meta.get("spawn", [])
	if s.size() == 3:
		return Vector3(s[0], s[1], s[2])
	return Vector3(0, 40, 10)


func _check_spawn_ground(poll: Timer) -> void:
	if _spawn_platform == null:
		poll.queue_free()
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var space := get_world_3d().direct_space_state
	var from := player.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 800.0)
	query.collision_mask = 1
	if player is PhysicsBody3D:
		query.exclude = [(player as PhysicsBody3D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Variant = hit.get("collider")
	if collider == _spawn_platform:
		return
	# Real terrain collision below the player — retire the safety platform.
	_spawn_platform.queue_free()
	_spawn_platform = null
	poll.queue_free()
	print("[VoxelWorld] Voxel ground ready under player")


## Static water: merged quads from baked water tiles (visual + future swim hook).
func _build_water() -> void:
	var tiles: Array = _meta.get("water_tiles", [])
	if tiles.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: Array in tiles:
		if t.size() < 4:
			continue
		var x := float(t[0])
		var z := float(t[1])
		var size := float(t[2])
		var y := float(t[3])
		var a := Vector3(x, y, z)
		var b := Vector3(x + size, y, z)
		var c := Vector3(x + size, y, z + size)
		var d := Vector3(x, y, z + size)
		st.set_normal(Vector3.UP)
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/voxel/voxel_water.gdshader")
	mi.material_override = mat
	mi.add_to_group("water_surface")
	add_child(mi)


func _setup_autosave() -> void:
	_save_timer = Timer.new()
	_save_timer.wait_time = 30.0
	_save_timer.timeout.connect(save_edits)
	add_child(_save_timer)
	_save_timer.start()


func _spawn_edit_tool() -> void:
	var tool_script: Variant = load("res://scripts/voxel/voxel_edit_tool.gd")
	if tool_script == null:
		return
	var tool: Node = tool_script.new()
	tool.name = "EditTool"
	add_child(tool)


func _exit_tree() -> void:
	save_edits()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_edits()
