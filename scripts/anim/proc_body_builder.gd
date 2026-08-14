class_name ProcBodyBuilder
extends RefCounted
## Generates a Skeleton3D (identity-basis rests) + capsule visuals from a
## ProcBodyPlan. Returns a BuiltRig with every bone index the animator needs,
## so bodies with any number of legs/arms/segments work the same way.


class BuiltRig:
	var plan: ProcBodyPlan
	var skeleton: Skeleton3D
	var spine_bones: Array[int] = []      ## Aligned with plan.segments.
	var neck_bone: int = -1
	var head_bone: int = -1
	var tail_bones: Array[int] = []
	var legs: Array[Dictionary] = []      ## {hip, knee, foot, plan(LegPlan), side}
	var arms: Array[Dictionary] = []      ## {shoulder, elbow, hand, plan(ArmPlan), side}

	func head_attach_segment() -> int:
		if plan.head_segment >= 0 and plan.head_segment < spine_bones.size():
			return plan.head_segment
		return spine_bones.size() - 1

	func tail_attach_segment() -> int:
		if plan.tail_segment >= 0 and plan.tail_segment < spine_bones.size():
			return plan.tail_segment
		return spine_bones.size() - 1


static func build(plan: ProcBodyPlan, parent: Node3D) -> BuiltRig:
	var rig := BuiltRig.new()
	rig.plan = plan
	var sk := Skeleton3D.new()
	sk.name = "ProcSkeleton"
	parent.add_child(sk)
	rig.skeleton = sk

	var body_mat := _mat(plan.body_color)
	var accent_mat := _mat(plan.accent_color)

	# --- Spine chain ---------------------------------------------------------
	var prev := -1
	for i in plan.segments.size():
		var seg := plan.segments[i]
		var idx := _add_bone(sk, "spine_%d" % i, prev, seg.offset)
		rig.spine_bones.append(idx)
		_attach_sphere(sk, idx, Vector3.ZERO, seg.radius, body_mat)
		if prev >= 0:
			_attach_link(sk, prev, seg.offset, plan.segments[i - 1].radius * 0.85, body_mat)
		prev = idx

	# --- Neck + head ---------------------------------------------------------
	var head_parent: int = rig.spine_bones[rig.head_attach_segment()]
	rig.neck_bone = _add_bone(sk, "neck", head_parent, plan.neck_offset)
	rig.head_bone = _add_bone(sk, "head", rig.neck_bone, plan.head_offset)
	_attach_link(sk, rig.neck_bone, plan.head_offset, plan.head_radius * 0.4, body_mat)
	_attach_sphere(sk, rig.head_bone, Vector3.ZERO, plan.head_radius, accent_mat)
	_attach_eyes(sk, rig.head_bone, plan.head_radius)

	# --- Tail ----------------------------------------------------------------
	if not plan.tail_offsets.is_empty():
		var tail_parent: int = rig.spine_bones[rig.tail_attach_segment()]
		# Rotation-only root so the first tail link isn't fighting the spine bone.
		var prev_tail := _add_bone(sk, "tail_root", tail_parent, Vector3.ZERO)
		rig.tail_bones.append(prev_tail)
		for t in plan.tail_offsets.size():
			var off: Vector3 = plan.tail_offsets[t]
			var taper := plan.tail_radius * (1.0 - 0.55 * float(t) / maxf(1.0, float(plan.tail_offsets.size())))
			_attach_link(sk, prev_tail, off, taper, body_mat)
			var tidx := _add_bone(sk, "tail_%d" % t, prev_tail, off)
			_attach_sphere(sk, tidx, Vector3.ZERO, taper, body_mat)
			prev_tail = tidx
			rig.tail_bones.append(tidx)

	# --- Legs ----------------------------------------------------------------
	for li in plan.legs.size():
		var leg := plan.legs[li]
		var hip := _add_bone(sk, "leg_%d_hip" % li, rig.spine_bones[leg.segment], leg.hip_offset)
		var knee := _add_bone(sk, "leg_%d_knee" % li, hip, Vector3(0.0, -leg.upper_len, 0.0))
		var foot := _add_bone(sk, "leg_%d_foot" % li, knee, Vector3(0.0, -leg.lower_len, 0.0))
		var thickness := clampf(leg.upper_len * 0.16, 0.035, 0.09)
		_attach_link(sk, hip, Vector3(0.0, -leg.upper_len, 0.0), thickness, body_mat)
		_attach_link(sk, knee, Vector3(0.0, -leg.lower_len, 0.0), thickness * 0.85, body_mat)
		_attach_foot(sk, foot, leg.foot_len, thickness, accent_mat)
		rig.legs.append({
			"hip": hip, "knee": knee, "foot": foot,
			"plan": leg,
			"side": signf(leg.hip_offset.x + leg.stance.x) if absf(leg.hip_offset.x + leg.stance.x) > 0.001 else 1.0,
		})

	# --- Arms ----------------------------------------------------------------
	for ai in plan.arms.size():
		var arm := plan.arms[ai]
		var shoulder := _add_bone(sk, "arm_%d_shoulder" % ai, rig.spine_bones[arm.segment], arm.shoulder_offset)
		var elbow := _add_bone(sk, "arm_%d_elbow" % ai, shoulder, Vector3(0.0, -arm.upper_len, 0.0))
		var hand := _add_bone(sk, "arm_%d_hand" % ai, elbow, Vector3(0.0, -arm.lower_len, 0.0))
		var thickness := clampf(arm.upper_len * 0.15, 0.03, 0.07)
		_attach_sphere(sk, shoulder, Vector3.ZERO, thickness * 1.5, body_mat)
		_attach_link(sk, shoulder, Vector3(0.0, -arm.upper_len, 0.0), thickness, body_mat)
		_attach_link(sk, elbow, Vector3(0.0, -arm.lower_len, 0.0), thickness * 0.85, body_mat)
		_attach_sphere(sk, hand, Vector3.ZERO, arm.hand_radius, accent_mat)
		rig.arms.append({
			"shoulder": shoulder, "elbow": elbow, "hand": hand,
			"plan": arm,
			"side": signf(arm.shoulder_offset.x) if absf(arm.shoulder_offset.x) > 0.001 else 1.0,
		})

	sk.reset_bone_poses()
	return rig


static func _add_bone(sk: Skeleton3D, bone_name: String, parent: int, offset: Vector3) -> int:
	var idx := sk.get_bone_count()
	sk.add_bone(bone_name)
	if parent >= 0:
		sk.set_bone_parent(idx, parent)
	sk.set_bone_rest(idx, Transform3D(Basis.IDENTITY, offset))
	sk.set_bone_pose_position(idx, offset)
	return idx


static func _attachment(sk: Skeleton3D, bone: int) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.name = "att_%s_%d" % [sk.get_bone_name(bone), sk.get_child_count()]
	sk.add_child(att)
	att.bone_idx = bone
	return att


static func _attach_sphere(sk: Skeleton3D, bone: int, local_pos: Vector3, radius: float, mat: Material) -> void:
	var att := _attachment(sk, bone)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = local_pos
	att.add_child(mi)


## Capsule spanning from a bone's origin along `seg` (its child's rest offset).
static func _attach_link(sk: Skeleton3D, bone: int, seg: Vector3, radius: float, mat: Material) -> void:
	var length := seg.length()
	if length < 0.01:
		return
	var att := _attachment(sk, bone)
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(length + radius, radius * 2.0)
	mi.mesh = mesh
	mi.material_override = mat
	var dir := seg / length
	var y := dir
	var x := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := (x.cross(y)).normalized()
	x = (y.cross(z)).normalized()
	mi.basis = Basis(x, y, z)
	mi.position = seg * 0.5
	att.add_child(mi)


static func _attach_foot(sk: Skeleton3D, bone: int, foot_len: float, radius: float, mat: Material) -> void:
	var att := _attachment(sk, bone)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(radius * 2.2, radius * 1.4, maxf(foot_len, radius * 2.0))
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0.0, radius * 0.5, -foot_len * 0.25)
	att.add_child(mi)


static func _attach_eyes(sk: Skeleton3D, head_bone: int, head_radius: float) -> void:
	var eye_mat := _mat(Color(1.0, 1.0, 1.0))
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.95, 0.8)
	eye_mat.emission_energy_multiplier = 1.4
	var pupil_mat := _mat(Color(0.05, 0.05, 0.08))
	for side in [-1.0, 1.0]:
		var att := _attachment(sk, head_bone)
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = head_radius * 0.28
		eye_mesh.height = head_radius * 0.56
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(head_radius * 0.42 * side, head_radius * 0.15, -head_radius * 0.78)
		att.add_child(eye)
		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = head_radius * 0.13
		pupil_mesh.height = head_radius * 0.26
		pupil.mesh = pupil_mesh
		pupil.material_override = pupil_mat
		pupil.position = eye.position + Vector3(0.0, 0.0, -head_radius * 0.2)
		att.add_child(pupil)


static func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	return mat
