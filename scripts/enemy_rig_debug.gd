extends Node
## Logs bone map on spawn; optional debug draw for foot targets.

@export var log_bones_on_ready: bool = true
@export var draw_debug: bool = false

var skeleton: Skeleton3D
var _f6_was_pressed: bool = false


func setup(sk: Skeleton3D) -> void:
	skeleton = sk
	if log_bones_on_ready:
		_log_bones()


func _log_bones() -> void:
	if skeleton == null:
		return
	print("=== Enemy rig bones (%d) ===" % skeleton.get_bone_count())
	for i in skeleton.get_bone_count():
		print("  [%d] %s parent=%d" % [i, skeleton.get_bone_name(i), skeleton.get_bone_parent(i)])
	var map := EnemyBoneMap.resolve(skeleton)
	if not map.get("missing", []).is_empty():
		push_warning("EnemyRigDebug missing bones: %s" % str(map["missing"]))


func _process(_delta: float) -> void:
	if Input.is_key_pressed(KEY_F6) and not _f6_was_pressed:
		draw_debug = not draw_debug
		print("Enemy rig debug: %s" % ("ON" if draw_debug else "OFF"))
	_f6_was_pressed = Input.is_key_pressed(KEY_F6)
