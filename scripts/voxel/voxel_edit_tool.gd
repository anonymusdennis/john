extends Node
## VoxelEditTool — creative build/mine tool for the voxel world.
##
## B ................ toggle build mode (frees LMB/RMB from combat/items)
## LMB (hold) ....... carve spheres (fast creative mining)
## RMB (hold) ....... place spheres of the selected material
## R ................ cycle material
## Mouse wheel ...... brush radius (consumed only while in build mode)
##
## Spawned as a child of VoxelWorld when the voxel terrain is active.
## Sets `build_mode_active` meta on the player so player.gd suppresses
## punching / item use while building. Stock-Godot safe (duck-typed world).

const MINE_INTERVAL := 0.12
const PLACE_INTERVAL := 0.15
const MIN_BRUSH := 1.5
const MAX_BRUSH := 6.0
const REACH := 60.0

var _world: Node = null                 # VoxelWorld (owner)
var _build_mode := false
var _brush_radius := 3.0
var _material_index := 0                # index into registry.placeable
var _cooldown := 0.0
var _ghost: MeshInstance3D = null
var _hud: CanvasLayer = null
var _hud_label: Label = null


func _ready() -> void:
	_world = get_parent()
	_make_ghost()
	_make_hud()
	set_physics_process(true)


func _exit_tree() -> void:
	_set_build_mode(false)


func _unhandled_input(event: InputEvent) -> void:
	if Inventory.is_open:
		return
	if event.is_action_pressed("build_mode_toggle"):
		_set_build_mode(not _build_mode)
		get_viewport().set_input_as_handled()
		return
	if not _build_mode:
		return
	if event.is_action_pressed("build_cycle_material"):
		var count := _palette_size()
		if count > 0:
			_material_index = (_material_index + 1) % count
			_refresh_hud()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_brush_up"):
		_brush_radius = minf(_brush_radius + 0.5, MAX_BRUSH)
		_refresh_hud()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_brush_down"):
		_brush_radius = maxf(_brush_radius - 0.5, MIN_BRUSH)
		_refresh_hud()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not _build_mode:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)

	var aim := _aim()
	if not bool(aim.get("hit", false)):
		_ghost.visible = false
		return

	var mine_point: Vector3 = aim["inside"]
	var place_point: Vector3 = aim["position"]
	_ghost.visible = true
	_ghost.global_position = place_point
	var s := _brush_radius * 2.0
	_ghost.scale = Vector3(s, s, s)

	if Inventory.is_open or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if _cooldown > 0.0:
		return
	if Input.is_action_pressed("use_item"):
		_world.carve_sphere(mine_point, _brush_radius)
		_cooldown = MINE_INTERVAL
	elif Input.is_action_pressed("punch"):
		_world.place_sphere(place_point, _brush_radius, _selected_channel())
		_cooldown = PLACE_INTERVAL


func _aim() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {"hit": false}
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	return _world.raycast_voxel(origin, dir, REACH)


func _set_build_mode(enabled: bool) -> void:
	_build_mode = enabled
	_ghost.visible = false
	_hud.visible = enabled
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.set_meta("build_mode_active", enabled)
	if enabled:
		_refresh_hud()


func _selected_channel() -> int:
	var reg: VoxelBlockRegistry = _world.registry()
	if reg.placeable.is_empty():
		return VoxelBlockRegistry.STONE
	return int(reg.placeable[_material_index % reg.placeable.size()]["channel"])


func _palette_size() -> int:
	var reg: VoxelBlockRegistry = _world.registry()
	return reg.placeable.size()


func _make_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.name = "BrushGhost"
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 12
	_ghost.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.9, 1.0, 0.25)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	_ghost.material_override = mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


func _make_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 21
	_hud.visible = false
	add_child(_hud)
	_hud_label = Label.new()
	_hud_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hud_label.offset_top = -140
	_hud_label.offset_bottom = -112
	_hud_label.offset_left = -420
	_hud_label.offset_right = 420
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_hud_label.add_theme_constant_override("outline_size", 6)
	_hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_child(_hud_label)


func _refresh_hud() -> void:
	var reg: VoxelBlockRegistry = _world.registry()
	var mat_name := "Stone"
	if not reg.placeable.is_empty():
		var entry: Dictionary = reg.placeable[_material_index % reg.placeable.size()]
		mat_name = String(entry["name"])
	_hud_label.text = "BUILD MODE — %s · brush %.1fm\nLMB mine · RMB place · R material · wheel size · B exit" % [mat_name, _brush_radius]
