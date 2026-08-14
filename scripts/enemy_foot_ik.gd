extends Node
## Raycast foot stepping + TwoBoneIK3D setup for both legs.

@export var step_distance: float = 0.55
@export var step_height: float = 0.18
@export var step_speed: float = 6.0
@export var ray_length: float = 2.5
@export var foot_forward_offset: float = 0.2
@export var collision_mask: int = 1

var skeleton: Skeleton3D
var _bones: Dictionary = {}
var _foot_target_l: Node3D
var _foot_target_r: Node3D
var _pole_l: Node3D
var _pole_r: Node3D
var _ik_l: TwoBoneIK3D
var _ik_r: TwoBoneIK3D
var _owner_body: CharacterBody3D

var _left_stepping: bool = false
var _right_stepping: bool = false
var _left_t: float = 1.0
var _right_t: float = 1.0
var _left_from: Vector3
var _left_to: Vector3
var _right_from: Vector3
var _right_to: Vector3
var _move_dir: Vector3 = Vector3.FORWARD


func setup(
	sk: Skeleton3D,
	foot_l: Node3D,
	foot_r: Node3D,
	pole_l: Node3D,
	pole_r: Node3D,
	body: CharacterBody3D,
) -> void:
	skeleton = sk
	_foot_target_l = foot_l
	_foot_target_r = foot_r
	_pole_l = pole_l
	_pole_r = pole_r
	_owner_body = body
	_bones = EnemyBoneMap.resolve(skeleton)
	_setup_ik_modifiers()
	_init_foot_positions()


func set_move_direction(dir: Vector3, speed: float) -> void:
	if dir.length_squared() > 0.001:
		_move_dir = dir.normalized()
	if speed < 0.1:
		_snap_feet_to_ground()
		return
	_try_step(true, speed)
	_try_step(false, speed)


func _physics_process(delta: float) -> void:
	if skeleton == null:
		return
	_update_step(true, delta)
	_update_step(false, delta)
	_update_poles()


func _setup_ik_modifiers() -> void:
	_ik_l = TwoBoneIK3D.new()
	_ik_l.name = "IK_LeftLeg"
	skeleton.add_child(_ik_l)
	_ik_l.setting_count = 1
	_ik_l.set_root_bone_name(0, "lefthip")
	_ik_l.set_middle_bone_name(0, "leftupperleg")
	_ik_l.set_end_bone_name(0, "leftlowerleg")
	_ik_l.set_target_node(0, _foot_target_l.get_path())
	_ik_l.set_pole_node(0, _pole_l.get_path())

	_ik_r = TwoBoneIK3D.new()
	_ik_r.name = "IK_RightLeg"
	skeleton.add_child(_ik_r)
	_ik_r.setting_count = 1
	_ik_r.set_root_bone_name(0, "righthip")
	_ik_r.set_middle_bone_name(0, "rightupperleg")
	_ik_r.set_end_bone_name(0, "rightlowerleg")
	_ik_r.set_target_node(0, _foot_target_r.get_path())
	_ik_r.set_pole_node(0, _pole_r.get_path())


func _init_foot_positions() -> void:
	var left := _desired_foot_global(true)
	var right := _desired_foot_global(false)
	_foot_target_l.global_position = left
	_foot_target_r.global_position = right
	_left_from = left
	_left_to = left
	_right_from = right
	_right_to = right
	_update_poles()


func _snap_feet_to_ground() -> void:
	_foot_target_l.global_position = _desired_foot_global(true)
	_foot_target_r.global_position = _desired_foot_global(false)


func _try_step(is_left: bool, speed: float) -> void:
	if is_left and _left_stepping:
		return
	if not is_left and _right_stepping:
		return
	if is_left and not _right_stepping and _right_t < 1.0:
		return
	if not is_left and not _left_stepping and _left_t < 1.0:
		return

	var foot: Node3D = _foot_target_l if is_left else _foot_target_r
	var desired := _desired_foot_global(is_left, speed)
	if foot.global_position.distance_to(desired) < step_distance:
		return

	if is_left:
		_left_stepping = true
		_left_t = 0.0
		_left_from = foot.global_position
		_left_to = desired
	else:
		_right_stepping = true
		_right_t = 0.0
		_right_from = foot.global_position
		_right_to = desired


func _update_step(is_left: bool, delta: float) -> void:
	var stepping: bool = _left_stepping if is_left else _right_stepping
	if not stepping:
		return
	var t_ref: float = _left_t if is_left else _right_t
	t_ref += delta * step_speed
	if is_left:
		_left_t = t_ref
	else:
		_right_t = t_ref
	if t_ref >= 1.0:
		if is_left:
			_left_stepping = false
			_left_t = 1.0
		else:
			_right_stepping = false
			_right_t = 1.0
	var from: Vector3 = _left_from if is_left else _right_from
	var to: Vector3 = _left_to if is_left else _right_to
	var p := clampf(t_ref, 0.0, 1.0)
	var pos := from.lerp(to, p)
	pos.y += sin(p * PI) * step_height
	var foot: Node3D = _foot_target_l if is_left else _foot_target_r
	foot.global_position = pos


func _desired_foot_global(is_left: bool, speed: float = 0.0) -> Vector3:
	var chain: Array = _bones.get("left_leg" if is_left else "right_leg", [])
	var hip_idx: int = int(chain[0]) if chain.size() > 0 else -1
	var hip_pos := skeleton.global_position
	if hip_idx >= 0:
		hip_pos = skeleton.to_global(skeleton.get_bone_global_pose(hip_idx).origin)

	var side := -1.0 if is_left else 1.0
	var lateral := _owner_body.global_transform.basis.x * 0.18 * side
	var forward := _move_dir * (foot_forward_offset + speed * 0.08)
	var probe := hip_pos + lateral + forward + Vector3.UP * 0.5
	var hit := _raycast_down(probe)
	if hit.is_empty():
		return Vector3(probe.x, _owner_body.global_position.y, probe.z)
	return hit.position + Vector3.UP * 0.03


func _raycast_down(from: Vector3) -> Dictionary:
	var space := skeleton.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		from,
		from + Vector3.DOWN * ray_length
	)
	query.collision_mask = collision_mask
	query.exclude = [_owner_body.get_rid()] if _owner_body else []
	return space.intersect_ray(query)


func _update_poles() -> void:
	if _pole_l and _foot_target_l:
		var mid := (_foot_target_l.global_position + skeleton.global_position) * 0.5
		_pole_l.global_position = mid + _owner_body.global_transform.basis.z * 0.35 + Vector3.UP * 0.2
	if _pole_r and _foot_target_r:
		var mid_r := (_foot_target_r.global_position + skeleton.global_position) * 0.5
		_pole_r.global_position = mid_r + _owner_body.global_transform.basis.z * 0.35 + Vector3.UP * 0.2
