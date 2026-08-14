class_name ProcIK
extends RefCounted
## Analytic IK + rotation helpers that operate directly on Skeleton3D bone poses.
## Engine-version agnostic: no SkeletonModifier3D / TwoBoneIK3D nodes required.
##
## Conventions used by the procedural rig:
## * Every bone rest transform has an IDENTITY basis; only rest origins differ.
##   A bone's "segment direction" is therefore the rest origin of its child.
## * All positions/directions below are in skeleton space unless noted.


## Builds the rotation that maps an (axis, hint) rest frame onto a current frame.
## `main_*` is the primary direction (fully honored), `sec_*` resolves the twist.
static func basis_from_pair(main_rest: Vector3, sec_rest: Vector3, main_cur: Vector3, sec_cur: Vector3) -> Basis:
	var rest := _make_frame(main_rest, sec_rest)
	var cur := _make_frame(main_cur, sec_cur)
	return cur * rest.transposed()


static func _make_frame(main_axis: Vector3, hint: Vector3) -> Basis:
	var x := main_axis.normalized()
	if x.length_squared() < 0.000001:
		x = Vector3.DOWN
	var h := hint - x * hint.dot(x)
	if h.length_squared() < 0.000001:
		h = _any_orthogonal(x)
	var y := h.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _any_orthogonal(v: Vector3) -> Vector3:
	var axis := Vector3.RIGHT if absf(v.x) < 0.9 else Vector3.UP
	return v.cross(axis).normalized()


## Solves a 2-segment chain (a -> b -> end) so the chain tip reaches `target`,
## bending toward `pole`. Rest chain may be perfectly straight; `bend_hint`
## (skeleton-space, roughly perpendicular to the rest chain) disambiguates twist.
##
## `root_pos`     : skeleton-space origin of bone `a` (from the solved parent).
## `parent_basis` : skeleton-space basis of `a`'s parent.
## Returns { "mid": Vector3, "end": Vector3, "basis_a": Basis, "basis_b": Basis }.
static func solve_two_bone(
	skeleton: Skeleton3D,
	bone_a: int,
	bone_b: int,
	bone_end: int,
	root_pos: Vector3,
	target: Vector3,
	pole: Vector3,
	parent_basis: Basis,
	bend_hint: Vector3,
) -> Dictionary:
	var rest_b := skeleton.get_bone_rest(bone_b).origin
	var rest_end := skeleton.get_bone_rest(bone_end).origin
	var l1 := rest_b.length()
	var l2 := rest_end.length()

	var v := target - root_pos
	var d := clampf(v.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.9995)
	var v_n := v.normalized() if v.length_squared() > 0.000001 else Vector3.DOWN
	var reach := root_pos + v_n * d

	# In-plane bend direction: component of the pole offset orthogonal to v.
	var pole_off := pole - root_pos
	var m := pole_off - v_n * pole_off.dot(v_n)
	if m.length_squared() < 0.00001:
		m = _any_orthogonal(v_n)
	m = m.normalized()

	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var ang_a := acos(cos_a)
	var dir1 := (v_n * cos_a + m * sin(ang_a)).normalized()
	var mid := root_pos + dir1 * l1
	var dir2 := (reach - mid).normalized() if reach.distance_squared_to(mid) > 0.000001 else dir1

	var basis_a := basis_from_pair(rest_b, bend_hint, dir1, m)
	var basis_b := basis_from_pair(rest_end, bend_hint, dir2, m)

	skeleton.set_bone_pose_rotation(bone_a, (parent_basis.transposed() * basis_a).get_rotation_quaternion().normalized())
	skeleton.set_bone_pose_rotation(bone_b, (basis_a.transposed() * basis_b).get_rotation_quaternion().normalized())

	return {"mid": mid, "end": reach, "basis_a": basis_a, "basis_b": basis_b}


## Yaw/pitch of a direction expressed in a -Z-forward frame.
## Returns Vector3(yaw, pitch, 0) in radians.
static func yaw_pitch(dir: Vector3) -> Vector3:
	var yaw := 0.0
	if Vector2(dir.x, dir.z).length_squared() > 0.000001:
		yaw = atan2(-dir.x, -dir.z)
	var pitch := asin(clampf(dir.normalized().y, -1.0, 1.0))
	return Vector3(yaw, pitch, 0.0)


## Basis looking along yaw/pitch in a -Z-forward frame (yaw about Y, then pitch about X).
static func basis_from_yaw_pitch(yaw: float, pitch: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


## Frame-rate independent exponential smoothing factor.
static func damp_factor(lambda: float, delta: float) -> float:
	return 1.0 - exp(-lambda * delta)


static func damp_vec(from: Vector3, to: Vector3, lambda: float, delta: float) -> Vector3:
	return from.lerp(to, damp_factor(lambda, delta))


static func damp_float(from: float, to: float, lambda: float, delta: float) -> float:
	return lerpf(from, to, damp_factor(lambda, delta))


static func damp_angle(from: float, to: float, lambda: float, delta: float) -> float:
	return lerp_angle(from, to, damp_factor(lambda, delta))
