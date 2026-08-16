extends SceneTree
## Environment validator for the voxel pipeline.
##
##   godot --headless --path . --script res://tools/worldgen/validate_voxel_build.gd
##
## Checks that the running Godot build has everything the voxel platform needs
## (godot_voxel classes, SQLite stream save/load roundtrip). Exit 0 = ready.

const REQUIRED_CLASSES := [
	"VoxelLodTerrain", "VoxelViewer", "VoxelMesherTransvoxel",
	"VoxelStreamSQLite", "VoxelGeneratorScript", "VoxelBuffer", "VoxelTool",
]


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	print("Godot: ", Engine.get_version_info()["string"])
	var ok := true
	for cls: String in REQUIRED_CLASSES:
		var have := ClassDB.class_exists(cls)
		print("  %s %s" % ["[ok]" if have else "[MISSING]", cls])
		ok = ok and have
	if not ok:
		printerr("godot_voxel module missing — game falls back to flat Ground; baking impossible.")
		printerr("Use a voxel-enabled build (see voxel-platform-handoff/IMPLEMENTATION-NOTES.md).")
		return 1

	var mesher: Variant = ClassDB.instantiate("VoxelMesherTransvoxel")
	if not ("texturing_mode" in mesher):
		printerr("VoxelMesherTransvoxel has no texturing_mode — module too old for Mixel4 texturing.")
		return 1
	print("  [ok] Transvoxel Mixel4 texturing available")

	# SQLite stream roundtrip (this is what the baker + runtime rely on).
	var tmp := "user://voxel_validate_tmp.sqlite"
	var stream: Variant = ClassDB.instantiate("VoxelStreamSQLite")
	stream.database_path = tmp
	var buffer: Variant = ClassDB.instantiate("VoxelBuffer")
	buffer.create(16, 16, 16)
	buffer.fill_f(-1.0, 1)
	stream.save_voxel_block(buffer, Vector3i(1, 2, 3), 0)
	stream.flush()
	var back: Variant = ClassDB.instantiate("VoxelBuffer")
	back.create(16, 16, 16)
	stream.load_voxel_block(back, Vector3i(1, 2, 3), 0)
	var v: float = back.get_voxel_f(8, 8, 8, 1)
	stream = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	if v >= 0.0:
		printerr("SQLite stream roundtrip FAILED (read back %f, expected < 0)" % v)
		return 1
	print("  [ok] VoxelStreamSQLite save/load roundtrip")
	print("Voxel environment READY — you can bake and play.")
	return 0
