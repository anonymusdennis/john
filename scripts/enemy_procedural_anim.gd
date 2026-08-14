extends Node
## Sin-wave procedural animation for torso/arms/hips. Legs are driven by foot IK.

enum AnimState { IDLE, WALK, ATTACK }

@export var walk_cycle_speed: float = 9.0
@export var leg_swing_deg: float = 22.0
@export var arm_swing_deg: float = 30.0
@export var idle_bob_deg: float = 3.0
@export var attack_swing_deg: float = 50.0
@export var attack_duration: float = 0.45
@export var bend_axis: Vector3 = Vector3(1.0, 0.0, 0.0)

var skeleton: Skeleton3D
var bones: Dictionary = {}

var _time: float = 0.0
var _move_amount: float = 0.0
var _state: AnimState = AnimState.IDLE
var _attack_t: float = 0.0


func setup(sk: Skeleton3D) -> void:
	skeleton = sk
	bones = EnemyBoneMap.resolve(skeleton)
	for n in bones.get("missing", []):
		push_warning("EnemyProceduralAnim missing bone: %s" % n)


func set_move_amount(speed: float) -> void:
	_move_amount = clampf(speed / 6.0, 0.0, 1.5)


func trigger_attack() -> void:
	_state = AnimState.ATTACK
	_attack_t = 0.0


func _process(delta: float) -> void:
	if skeleton == null:
		return
	_time += delta
	if _state == AnimState.ATTACK:
		_attack_t += delta
		if _attack_t >= attack_duration:
			_state = AnimState.IDLE
	_apply_pose()


func _apply_pose() -> void:
	skeleton.reset_bone_poses()
	if _state == AnimState.ATTACK:
		_apply_attack(_attack_t / attack_duration)
		return

	var t := _time * walk_cycle_speed
	var move := _move_amount

	# Idle torso/head bob.
	_rotate_bone(int(bones.get("torso", -1)), Vector3(deg_to_rad(idle_bob_deg) * sin(_time * 2.2), 0.0, 0.0))
	_rotate_bone(int(bones.get("head", -1)), Vector3(deg_to_rad(idle_bob_deg * 0.5) * sin(_time * 2.2 + 0.4), 0.0, 0.0))

	if move < 0.05:
		return

	# Hip sway (thigh driver) — IK handles lower leg to foot.
	_apply_leg_chain(bones.get("left_leg", []), sin(t) * deg_to_rad(leg_swing_deg) * move)
	_apply_leg_chain(bones.get("right_leg", []), sin(t + PI) * deg_to_rad(leg_swing_deg) * move)

	# Arms opposite to legs.
	_apply_arm_chain(bones.get("left_arm", []), sin(t + PI) * deg_to_rad(arm_swing_deg) * move)
	_apply_arm_chain(bones.get("right_arm", []), sin(t) * deg_to_rad(arm_swing_deg) * move)


func _apply_leg_chain(chain: Array, hip_angle: float) -> void:
	if chain.is_empty():
		return
	# Hip sway only — TwoBoneIK3D drives upper/lower leg to foot targets.
	_rotate_bone(int(chain[0]), Vector3(hip_angle, 0.0, 0.0))


func _apply_arm_chain(chain: Array, shoulder_angle: float) -> void:
	if chain.is_empty():
		return
	_rotate_bone(int(chain[0]), Vector3(shoulder_angle, 0.0, 0.0))
	if chain.size() > 1:
		_rotate_bone(int(chain[1]), Vector3(shoulder_angle * 0.65, 0.0, 0.0))
	if chain.size() > 2:
		_rotate_bone(int(chain[2]), Vector3(shoulder_angle * 0.25, 0.0, 0.0))


func _apply_attack(progress: float) -> void:
	var swing := sin(progress * PI) * deg_to_rad(attack_swing_deg)
	var chain: Array = bones.get("right_arm", [])
	if chain.is_empty():
		return
	_rotate_bone(int(chain[0]), Vector3(-swing, 0.0, swing * 0.25))
	if chain.size() > 1:
		_rotate_bone(int(chain[1]), Vector3(-swing * 0.85, 0.0, 0.0))


func _rotate_bone(bone_idx: int, euler: Vector3) -> void:
	if bone_idx < 0:
		return
	var axis := bend_axis.normalized()
	var angle := euler.x
	if absf(angle) < 0.0001:
		return
	var pose_rot := skeleton.get_bone_pose_rotation(bone_idx)
	skeleton.set_bone_pose_rotation(
		bone_idx,
		(pose_rot * Quaternion(axis, angle)).normalized()
	)
