extends SceneTree
## Offline world baker — generates the FULL shippable voxel world into an
## SQLite database. The generator never ships; players only get the data.
##
## Run with a voxel-enabled Godot build (module master / v1.6.1-dev+ for the
## headless fix, see IMPLEMENTATION-NOTES.md):
##
##   godot --headless --path . --script res://tools/worldgen/bake_world.gd \
##       -- [--config res://tools/worldgen/bake_config.json] [--force] \
##          [--seed N] [--size N] [--lods N]
##
## Output (out_dir from config, default res://world/):
##   world.sqlite      — all voxel blocks, LODs 0..N-1 (VoxelStreamSQLite)
##   world_meta.json   — bounds, spawn point, water tiles, seed
##
## Resumable: progress is checkpointed to bake_progress.json; re-running
## continues where it stopped. --force restarts from scratch.
##
## Stock-Godot safe (duck-typed voxel classes) — it just refuses politely.

const BLOCK := 16
const FLUSH_EVERY := 4096
const META_VERSION := 2

var _model: TerrainModel
var _stream: Variant
var _out_dir := "res://world"
var _cfg: Dictionary = {}


func _initialize() -> void:
	var code := _run()
	quit(code)


func _run() -> int:
	print("=== John voxel world baker (steered fantasy terrain) ===")
	if not ClassDB.class_exists("VoxelStreamSQLite") or not ClassDB.class_exists("VoxelBuffer"):
		printerr("This Godot build has no godot_voxel module — cannot bake.")
		printerr("Build/download a voxel-enabled Godot first (see voxel-platform-handoff/IMPLEMENTATION-NOTES.md).")
		return 1

	var args := OS.get_cmdline_user_args()
	var config_path := _arg_value(args, "--config", "res://tools/worldgen/bake_config.json")
	var force := "--force" in args

	_cfg = _load_json(config_path)
	if _cfg.is_empty():
		printerr("Missing/invalid config: ", config_path)
		return 1
	var seed_override := _arg_value(args, "--seed", "")
	if not seed_override.is_empty():
		_cfg["seed"] = int(seed_override)
	var size_override := _arg_value(args, "--size", "")
	if not size_override.is_empty():
		_cfg["size_x"] = int(size_override)
		_cfg["size_z"] = int(size_override)
	var lods_override := _arg_value(args, "--lods", "")
	if not lods_override.is_empty():
		_cfg["lods"] = int(lods_override)

	_model = TerrainModel.new()
	_model.configure(_cfg)
	_out_dir = String(_cfg.get("out_dir", "res://world"))
	DirAccess.make_dir_recursive_absolute(_out_dir)

	var db_path := _out_dir.path_join("world.sqlite")
	var progress_path := _out_dir.path_join("bake_progress.json")
	var progress := _load_json(progress_path)
	if force:
		progress = {}
		for suffix in ["", "-wal", "-shm"]:
			var p: String = db_path + suffix
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	elif FileAccess.file_exists(db_path) and progress.is_empty():
		printerr("A finished bake already exists at %s — use --force to re-bake." % db_path)
		return 1

	_stream = ClassDB.instantiate("VoxelStreamSQLite")
	_stream.database_path = db_path

	var lods := int(_cfg.get("lods", 5))
	var t_start := Time.get_ticks_msec()
	var total_blocks := 0
	var lod_ranges: Array = []
	for lod in lods:
		var r := _block_range(lod)
		lod_ranges.append(r)
		total_blocks += r["count"]
	print("World: %dx%dm, y %d..%d, seed %d, %d LODs, %d blocks total"
			% [_model.size_x, _model.size_z, _model.y_min, _model.y_max,
			_model.world_seed, lods, total_blocks])

	var done_before := 0
	var blocks_done := 0
	for lod in lods:
		var r: Dictionary = lod_ranges[lod]
		var resume := int(progress.get(str(lod), 0))
		if resume >= int(r["count"]):
			done_before += int(r["count"])
			blocks_done += int(r["count"])
			continue
		blocks_done += resume
		done_before += resume
		var res := _bake_lod(lod, r, resume, progress, progress_path,
				blocks_done, total_blocks, t_start, done_before)
		blocks_done = res
	_stream.flush()

	_write_meta()
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress_path))
	var mins := (Time.get_ticks_msec() - t_start) / 60000.0
	print("DONE in %.1f min → %s" % [mins, db_path])
	print("Ship res://world/ with the game; the runtime copies it to user:// on first launch.")
	return 0


func _bake_lod(lod: int, r: Dictionary, resume: int, progress: Dictionary,
		progress_path: String, blocks_done_global: int, total_blocks: int,
		t_start: int, _done_before: int) -> int:
	var bx0: int = r["bx0"]; var bx1: int = r["bx1"]
	var by0: int = r["by0"]; var by1: int = r["by1"]
	var bz0: int = r["bz0"]; var bz1: int = r["bz1"]
	var nx := bx1 - bx0
	var ny := by1 - by0
	var count: int = r["count"]
	print("LOD %d: %d blocks (%dx%dx%d)" % [lod, count, nx, ny, bz1 - bz0])

	var cache := {}
	var since_flush := 0
	var done := blocks_done_global
	for linear in range(resume, count):
		var bz := bz0 + linear / (nx * ny)
		var rem := linear % (nx * ny)
		var by := by0 + rem / nx
		var bx := bx0 + rem % nx
		var origin := Vector3i(bx, by, bz) * (BLOCK << lod)

		var buffer: Variant = ClassDB.instantiate("VoxelBuffer")
		buffer.create(BLOCK, BLOCK, BLOCK)
		_model.fill_block(buffer, origin, lod, cache)
		_stream.save_voxel_block(buffer, Vector3i(bx, by, bz), lod)

		done += 1
		since_flush += 1
		if since_flush >= FLUSH_EVERY:
			since_flush = 0
			_stream.flush()
			progress[str(lod)] = linear + 1
			_save_json(progress_path, progress)
			cache.clear()
			var elapsed := (Time.get_ticks_msec() - t_start) / 1000.0
			var rate := done / maxf(elapsed, 0.001)
			var eta := (total_blocks - done) / maxf(rate, 0.001) / 60.0
			print("  %d / %d blocks (%.1f%%) — %.0f blocks/s — ETA %.1f min"
					% [done, total_blocks, 100.0 * done / total_blocks, rate, eta])
	_stream.flush()
	progress[str(lod)] = count
	_save_json(progress_path, progress)
	return done


func _block_range(lod: int) -> Dictionary:
	var bs := BLOCK << lod
	var bx0 := floori(-_model.size_x / 2.0 / bs)
	var bx1 := ceili(_model.size_x / 2.0 / bs)
	var bz0 := floori(-_model.size_z / 2.0 / bs)
	var bz1 := ceili(_model.size_z / 2.0 / bs)
	var by0 := floori(float(_model.y_min) / bs)
	var by1 := ceili(float(_model.y_max) / bs)
	return {
		"bx0": bx0, "bx1": bx1, "by0": by0, "by1": by1, "bz0": bz0, "bz1": bz1,
		"count": (bx1 - bx0) * (by1 - by0) * (bz1 - bz0),
	}


func _write_meta() -> void:
	var cache := {}
	print("Finding spawn + collecting water tiles…")
	var spawn: Vector3 = _model.find_spawn(cache)
	var tiles: Array = _model.water_tiles(cache)
	var b: AABB = _model.bounds_aabb()
	var meta := {
		"version": META_VERSION,
		"seed": _model.world_seed,
		"bounds": {
			"min": [b.position.x, b.position.y, b.position.z],
			"size": [b.size.x, b.size.y, b.size.z],
		},
		"sea_level": _model.sea_level,
		"bedrock_top_y": _model.bedrock_top_y,
		"config": _model.config_dict(),
		"lods": int(_cfg.get("lods", 5)),
		"spawn": [spawn.x, spawn.y, spawn.z],
		"water_tiles": tiles,
		"generated_at": Time.get_datetime_string_from_system(true),
	}
	_save_json(_out_dir.path_join("world_meta.json"), meta)
	print("Meta written: spawn=%s, %d water tiles" % [spawn, tiles.size()])


func _arg_value(args: PackedStringArray, key: String, fallback: String) -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return fallback


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _save_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()
