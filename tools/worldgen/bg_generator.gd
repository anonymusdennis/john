extends VoxelGeneratorScript
## Dev-only live generator adapter for the Big Globe-inspired world model.
##
## NOTE: this file extends VoxelGeneratorScript and therefore only parses on a
## Godot build that includes the godot_voxel module. It lives in tools/ (which
## is excluded from exports) and is only ever load()-ed:
##  - by scripts/voxel/voxel_world.gd when no baked world exists (live dev gen)
##  - by tools/worldgen/bake_world.gd conceptually (the baker uses BGModel
##    directly, this adapter is for in-editor flying around while tuning)
##
## All actual generation math lives in bg_model.gd (stock-Godot safe).

const BGModel := preload("res://tools/worldgen/bg_model.gd")
const CONFIG_PATH := "res://tools/worldgen/bake_config.json"

var model: RefCounted = BGModel.new()


func configure_defaults() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var cfg: Variant = JSON.parse_string(f.get_as_text())
	if cfg is Dictionary:
		model.configure(cfg)


func configure(cfg: Dictionary) -> void:
	model.configure(cfg)


func _get_used_channels_mask() -> int:
	# SDF | INDICES | WEIGHTS
	return (1 << 1) | (1 << 3) | (1 << 4)


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# Called from multiple streaming threads: use a per-call cache (no shared state).
	var cache := {}
	model.fill_block(out_buffer, origin_in_voxels, lod, cache)
