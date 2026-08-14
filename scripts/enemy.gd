extends CharacterBody3D
## Chase enemy with procedural animation + foot IK.

@export var move_speed: float = 3.5
@export var chase_range: float = 40.0
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.2
@export var ground_clearance: float = 0.02

@onready var model: Node3D = $Model
@onready var procedural_anim: Node = $ProceduralAnim
@onready var foot_ik: Node = $FootIK
@onready var rig_debug: Node = $RigDebug
@onready var foot_target_l: Node3D = $FootTarget_L
@onready var foot_target_r: Node3D = $FootTarget_R
@onready var pole_l: Node3D = $KneePole_L
@onready var pole_r: Node3D = $KneePole_R
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _skeleton: Skeleton3D
var _attack_cd: float = 0.0
var _player: Node3D


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 1
	collision_mask = 1 | 2
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_skeleton = EnemyBoneMap.find_skeleton(model)
	if _skeleton == null:
		push_error("Enemy: no Skeleton3D found in model")
		return
	_snap_model_to_ground()
	_ensure_collision()
	if procedural_anim.has_method("setup"):
		procedural_anim.setup(_skeleton)
	if foot_ik.has_method("setup"):
		foot_ik.setup(_skeleton, foot_target_l, foot_target_r, pole_l, pole_r, self)
	if rig_debug.has_method("setup"):
		rig_debug.setup(_skeleton)


func _snap_model_to_ground() -> void:
	var lowest_y := INF
	for i in _skeleton.get_bone_count():
		var rest_origin := _skeleton.get_bone_rest(i).origin
		lowest_y = minf(lowest_y, rest_origin.y)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := node as MeshInstance3D
		if mesh_i.mesh == null:
			continue
		var aabb := mesh_i.get_aabb()
		var base_y := mesh_i.position.y + aabb.position.y
		lowest_y = minf(lowest_y, base_y)
	if lowest_y < INF:
		model.position.y = -lowest_y + ground_clearance
	if collision_shape.shape is CapsuleShape3D:
		var cap := collision_shape.shape as CapsuleShape3D
		collision_shape.position.y = cap.height * 0.5 + ground_clearance


func _ensure_collision() -> void:
	if collision_shape.shape != null:
		return
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.6
	collision_shape.shape = shape
	collision_shape.position.y = shape.height * 0.5 + ground_clearance


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		_set_move(0.0, Vector3.ZERO)
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > chase_range:
		velocity = Vector3.ZERO
		_set_move(0.0, global_transform.basis.z)
		move_and_slide()
		return

	if dist <= attack_range and _attack_cd <= 0.0:
		if procedural_anim.has_method("trigger_attack"):
			procedural_anim.trigger_attack()
		_attack_cd = attack_cooldown
		velocity = Vector3.ZERO
		_set_move(0.0, global_transform.basis.z)
		move_and_slide()
		return

	var dir := to_player / maxf(dist, 0.001)
	velocity = dir * move_speed
	if dir.length_squared() > 0.0:
		look_at(global_position + dir, Vector3.UP)
	move_and_slide()
	_set_move(Vector2(velocity.x, velocity.z).length(), dir)


func _set_move(speed: float, move_dir: Vector3) -> void:
	if procedural_anim.has_method("set_move_amount"):
		procedural_anim.set_move_amount(speed)
	if foot_ik.has_method("set_move_direction"):
		foot_ik.set_move_direction(move_dir, speed)
