class_name ProcAnimator
extends Node3D
## Fully procedural, body-form-agnostic animator.
##
## No keyframes and no sine-wave fakery: every foot is tracked as a planted
## world-space anchor and only swings (raycast-placed, parabolic arc) when the
## body has moved too far away from it. Body height/pitch/roll are derived from
## the actual planted feet. Long bodies and tails follow-through world space.
## The head looks at a target within neck limits and asks the torso to turn
## (via `torso_turn_request`) instead of breaking its neck. Hands aim at the
## target and throw procedural strikes.
##
## Works with any ProcBodyPlan: bipeds, centaurs, spiders, centipedes, ...

@export_enum("human", "imp", "centaur", "spider", "centipede") var body_form: String = "human"
@export var auto_build: bool = true
@export var ground_mask: int = 1

## Signed yaw (radians) the body should turn so the head stops straining.
var torso_turn_request: float = 0.0
var plan: ProcBodyPlan

var _rig: ProcBodyBuilder.BuiltRig
var _sk: Skeleton3D
var _body: PhysicsBody3D

var _legs: Array[ProcLeg] = []
var _leg_home_rest: Array[Vector3] = []     ## Body-local ground home per leg.
var _leg_hip_rest: Array[Vector3] = []      ## Body-local hip rest position per leg.
var _leg_neighbors: Array = []              ## Per leg: indices that must not step simultaneously.
var _seg_rest_pos: Array[Vector3] = []      ## Accumulated skeleton-space rest joint positions.
var _seg_world_pos: Array[Vector3] = []     ## Follow-through state for lagging segments.
var _tail_world_pos: Array[Vector3] = []

var _vel: Vector3 = Vector3.ZERO
var _prev_vel: Vector3 = Vector3.ZERO
var _accel_smooth: Vector3 = Vector3.ZERO
var _grounded: bool = true
var _was_grounded: bool = true
var _look_target: Node3D

var _root_h: float = 0.8
var _bounce: float = 0.0                    ## Impulse dip from foot plants / landings.
var _pitch: float = 0.0
var _roll: float = 0.0
var _hip_yaw: float = 0.0
var _head_yaw: float = 0.0
var _head_pitch: float = 0.0
var _prev_body_yaw: float = 0.0
var _yaw_rate: float = 0.0

var _hand_pos: Array[Vector3] = []          ## Smoothed skeleton-space hand targets.
var _hand_override: Array = []              ## Per arm: null or world-space Vector3 (ledge grabs).
var _neck_strained: bool = false
var _attacking: bool = false
var _attack_p: float = 0.0
var _attack_arm: int = 0
var _next_attack_arm: int = 0

var _impact_kick: Vector3 = Vector3.ZERO    ## Skeleton-space root displacement from hits.
var _impact_spin: Vector2 = Vector2.ZERO    ## Pitch/roll kick from hits.

var _noise: FastNoiseLite
var _t: float = 0.0


func _ready() -> void:
	if auto_build and _rig == null:
		build(StringName(body_form))


## Builds (or rebuilds) the body from a plan preset name.
func build(form: StringName) -> void:
	if _sk != null:
		_sk.queue_free()
	body_form = String(form)
	plan = ProcBodyPlan.make(form)
	_rig = ProcBodyBuilder.build(plan, self)
	_sk = _rig.skeleton
	_body = _find_body()
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.frequency = 1.0
	_t = randf() * 100.0
	_root_h = plan.ride_height
	_init_rest_data()
	_init_legs()
	_init_arms()


func set_locomotion(velocity: Vector3, grounded: bool) -> void:
	_vel = velocity
	_grounded = grounded


func set_look_target(target: Node3D) -> void:
	_look_target = target


## Starts a procedural strike (hand punch, or a body lunge for armless forms).
## Returns false while another attack is still playing.
func trigger_attack() -> bool:
	if _attacking or _rig == null:
		return false
	_attacking = true
	_attack_p = 0.0
	if not _rig.arms.is_empty():
		_attack_arm = _next_attack_arm % _rig.arms.size()
		_next_attack_arm += 1
	return true


## Force is emitted to body parts: the nearest segment's follow-through target
## is shoved, the root/pitch/roll take a kick, and feet near the hit lose grip
## and scramble to re-plant. Used by grenades, punches, and anything physical.
func apply_impact(world_pos: Vector3, impulse: Vector3) -> void:
	if _rig == null or _sk == null:
		return
	var to_skel := _sk.global_transform.affine_inverse()
	var local_imp := to_skel.basis * impulse
	var strength := impulse.length()

	# Root kick toward the impulse + a pitch/roll reel.
	_impact_kick = (_impact_kick + local_imp * 0.045).limit_length(0.4)
	_impact_spin.x = clampf(_impact_spin.x - local_imp.z * 0.05, -0.35, 0.35)
	_impact_spin.y = clampf(_impact_spin.y + local_imp.x * 0.05, -0.3, 0.3)

	# Displace the nearest follow-through segment so long bodies whip visibly.
	if not _seg_world_pos.is_empty():
		var nearest := 0
		var best := INF
		for i in _seg_world_pos.size():
			var d := _seg_world_pos[i].distance_squared_to(world_pos)
			if d < best:
				best = d
				nearest = i
		_seg_world_pos[nearest] += impulse.limit_length(3.0) * 0.12

	# Per-foot micro grip: feet near the hit release and must re-plant.
	var break_radius := 0.6 + clampf(strength * 0.12, 0.0, 1.4)
	for leg in _legs:
		if leg.foot_pos.distance_to(world_pos) <= break_radius:
			leg.initialized = false
			leg.stepping = false
	_bounce = maxf(_bounce - clampf(strength * 0.02, 0.02, 0.1), -0.14)


## Full grip override: every planted foot lets go at once (blast knock-offs).
func release_all_feet() -> void:
	for leg in _legs:
		leg.initialized = false
		leg.stepping = false


## Pins one hand to a world-space point (ledge grabbing); pass INF to release.
func set_hand_override(index: int, world_pos: Vector3) -> void:
	if _hand_override.size() != _rig.arms.size():
		_hand_override.resize(_rig.arms.size())
	if index >= 0 and index < _hand_override.size():
		_hand_override[index] = null if world_pos == Vector3.INF else world_pos


func clear_hand_overrides() -> void:
	for i in _hand_override.size():
		_hand_override[i] = null


func arm_count() -> int:
	return 0 if _rig == null else _rig.arms.size()


func _physics_process(delta: float) -> void:
	if _rig == null or _sk == null:
		return
	_t += delta
	if _attacking:
		_attack_p += delta / maxf(plan.attack_time, 0.05)
		if _attack_p >= 1.0:
			_attacking = false
	_accel_smooth = ProcIK.damp_vec(_accel_smooth, (_vel - _prev_vel) / maxf(delta, 0.001), 6.0, delta)
	_prev_vel = _vel
	_impact_kick = ProcIK.damp_vec(_impact_kick, Vector3.ZERO, 5.0, delta)
	_impact_spin = _impact_spin.lerp(Vector2.ZERO, clampf(5.0 * delta, 0.0, 1.0))
	var body_yaw := global_transform.basis.get_euler().y
	_yaw_rate = ProcIK.damp_float(_yaw_rate, wrapf(body_yaw - _prev_body_yaw, -PI, PI) / maxf(delta, 0.001), 8.0, delta)
	_prev_body_yaw = body_yaw

	var to_skel := _sk.global_transform.affine_inverse()

	_update_gait(delta, to_skel)
	var spine := _solve_spine(delta, to_skel)
	_solve_head(delta, to_skel, spine)
	_solve_tail(delta, to_skel, spine)
	_solve_legs(delta, to_skel, spine)
	_solve_arms(delta, to_skel, spine)
	_was_grounded = _grounded


# --- Setup -------------------------------------------------------------------

func _find_body() -> PhysicsBody3D:
	var n: Node = self
	while n != null:
		if n is PhysicsBody3D:
			return n
		n = n.get_parent()
	return null


func _init_rest_data() -> void:
	_seg_rest_pos.clear()
	var acc := Vector3.ZERO
	for seg in plan.segments:
		acc += seg.offset
		_seg_rest_pos.append(acc)
	_seg_world_pos.clear()
	for pos in _seg_rest_pos:
		_seg_world_pos.append(_sk.global_transform * pos)
	_tail_world_pos.clear()
	var tail_acc: Vector3 = _seg_rest_pos[_rig.tail_attach_segment()]
	for off in plan.tail_offsets:
		tail_acc += off
		_tail_world_pos.append(_sk.global_transform * tail_acc)


func _init_legs() -> void:
	_legs.clear()
	_leg_home_rest.clear()
	_leg_hip_rest.clear()
	for i in _rig.legs.size():
		var info: Dictionary = _rig.legs[i]
		var leg_plan: ProcBodyPlan.LegPlan = info["plan"]
		var leg := ProcLeg.new(leg_plan, info, i)
		var hip_rest: Vector3 = _seg_rest_pos[leg_plan.segment] + leg_plan.hip_offset
		var home := Vector3(hip_rest.x + leg_plan.stance.x, 0.0, hip_rest.z + leg_plan.stance.z)
		_leg_hip_rest.append(hip_rest)
		_leg_home_rest.append(home)
		leg.plant_instantly(_sk.global_transform * home, Vector3.UP)
		_legs.append(leg)
	_build_neighbor_rule()


## Gait rule: a leg may not swing while its lateral pair or the nearest legs in
## front/behind on the same side are swinging. One rule, every body plan:
## bipeds alternate, quadrupeds trot, spiders/centipedes ripple in waves.
func _build_neighbor_rule() -> void:
	_leg_neighbors.clear()
	for i in _legs.size():
		var mine: Array[int] = []
		var my_home := _leg_home_rest[i]
		var my_side := _legs[i].side
		var best_pair := -1
		var best_pair_d := INF
		var front := -1
		var front_d := INF
		var back := -1
		var back_d := INF
		for j in _legs.size():
			if j == i:
				continue
			var other := _leg_home_rest[j]
			if _legs[j].side != my_side:
				var d := absf(other.z - my_home.z)
				if d < best_pair_d:
					best_pair_d = d
					best_pair = j
			else:
				var dz := other.z - my_home.z
				if dz < -0.001 and -dz < front_d:
					front_d = -dz
					front = j
				elif dz > 0.001 and dz < back_d:
					back_d = dz
					back = j
		for idx in [best_pair, front, back]:
			if idx >= 0:
				mine.append(idx)
		_leg_neighbors.append(mine)


func _init_arms() -> void:
	_hand_pos.clear()
	_hand_override.clear()
	for i in _rig.arms.size():
		var arm_plan: ProcBodyPlan.ArmPlan = _rig.arms[i]["plan"]
		var rest := _seg_rest_pos[arm_plan.segment] + arm_plan.shoulder_offset + Vector3(0.0, -(arm_plan.upper_len + arm_plan.lower_len) * 0.85, 0.0)
		_hand_pos.append(rest)
		_hand_override.append(null)


# --- Gait --------------------------------------------------------------------

func _update_gait(delta: float, to_skel: Transform3D) -> void:
	if _legs.is_empty():
		return
	if not _grounded:
		for leg in _legs:
			leg.initialized = false
			leg.stepping = false
		return

	var speed := Vector2(_vel.x, _vel.z).length()
	var step_time := plan.step_time * clampf(1.0 - speed * 0.05, 0.55, 1.0)
	var lead := _vel * step_time * 0.7
	if lead.length() > 0.5:
		lead = lead.normalized() * 0.5
	var body_xf := _sk.global_transform

	# Desired ground point per leg (fixed body-local home + velocity lead).
	var just_landed := not _was_grounded
	var desired: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for i in _legs.size():
		var home_world := body_xf * _leg_home_rest[i] + lead
		var hit := _ray_ground(home_world)
		desired.append(hit["pos"])
		normals.append(hit["normal"])
		if not _legs[i].initialized:
			_legs[i].plant_instantly(hit["pos"], hit["normal"])
	if just_landed:
		_bounce = maxf(_bounce - 0.07, -0.12)

	# Trigger steps: worst-drifted legs first, respecting the neighbor rule.
	var order: Array[int] = []
	for i in _legs.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return _legs[a].drift_sq(desired[a]) > _legs[b].drift_sq(desired[b]))
	var swinging := 0
	for leg in _legs:
		if leg.stepping:
			swinging += 1
	var max_swinging: int = maxi(1, int(ceil(_legs.size() * 0.5)))
	for i in order:
		var leg := _legs[i]
		if leg.stepping:
			continue
		var trigger: float = leg.plan.step_trigger
		var drift := leg.drift_sq(desired[i])
		if drift < trigger * trigger:
			continue
		var blocked := false
		for n in _leg_neighbors[i]:
			if _legs[n].stepping and _legs[n].step_p < 0.75:
				blocked = true
				break
		var forced := drift > (trigger * 2.2) * (trigger * 2.2)
		if (blocked and not forced) or (swinging >= max_swinging and not forced):
			continue
		leg.begin_step(desired[i])
		swinging += 1

	# Advance swings; planted feet stay world-anchored for free.
	for i in _legs.size():
		if _legs[i].advance(delta, step_time, desired[i], normals[i]):
			_bounce = maxf(_bounce - 0.015, -0.09)


## Feet probe along the BODY's up axis (not world down), so wall-walking
## bodies plant their feet on walls and ceilings just like floors.
func _ray_ground(around: Vector3) -> Dictionary:
	var up := _sk.global_transform.basis.y.normalized()
	var from := around + up * (plan.ride_height * 0.8 + 0.4)
	var to := around - up * (plan.ride_height + 1.2)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = ground_mask
	if _body != null:
		query.exclude = [_body.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {"pos": around, "normal": up}
	return {"pos": hit["position"], "normal": hit["normal"]}


# --- Spine -------------------------------------------------------------------

## Positions every spine joint (rigid or follow-through), then derives bone
## rotations so parent bones actually carry their children + attached meshes.
## Returns per-segment skeleton-space transforms.
func _solve_spine(delta: float, to_skel: Transform3D) -> Array[Transform3D]:
	var n := plan.segments.size()
	var out: Array[Transform3D] = []
	out.resize(n)

	# Root joint height/tilt from the actual planted feet.
	var target_h := plan.ride_height
	var front_h := 0.0
	var back_h := 0.0
	var left_h := 0.0
	var right_h := 0.0
	var fw := 0.0
	var bw := 0.0
	var lw := 0.0
	var rw := 0.0
	if not _legs.is_empty() and _grounded:
		var avg_y := 0.0
		for i in _legs.size():
			var f := to_skel * _legs[i].foot_pos
			avg_y += f.y
			var home := _leg_home_rest[i]
			if home.z < -0.01:
				front_h += f.y
				fw += 1.0
			elif home.z > 0.01:
				back_h += f.y
				bw += 1.0
			if home.x < 0.0:
				left_h += f.y
				lw += 1.0
			else:
				right_h += f.y
				rw += 1.0
		avg_y /= float(_legs.size())
		target_h = avg_y + plan.ride_height
	elif not _grounded:
		target_h = plan.ride_height * 0.9

	_bounce = ProcIK.damp_float(_bounce, 0.0, 9.0, delta)
	_root_h = ProcIK.damp_float(_root_h, target_h, 10.0, delta)

	var want_pitch := 0.0
	if fw > 0.0 and bw > 0.0:
		var span := absf(_span_z())
		if span > 0.05:
			want_pitch = atan2(front_h / fw - back_h / bw, span) * plan.stance_pitch_gain
	var want_roll := 0.0
	if lw > 0.0 and rw > 0.0:
		var span_x := maxf(_span_x(), 0.15)
		want_roll = atan2(right_h / rw - left_h / lw, span_x) * plan.stance_roll_gain

	# Lean into acceleration + bank into turns (from real velocity deltas).
	var local_acc := global_transform.basis.inverse() * _accel_smooth
	want_pitch += clampf(local_acc.z * 0.02, -0.12, 0.12)
	want_roll += clampf(-_yaw_rate * 0.06, -0.1, 0.1)
	want_pitch += _impact_spin.x
	want_roll += _impact_spin.y
	if _attacking and _rig.arms.is_empty():
		want_pitch -= _strike_curve() * 0.35

	# Idle life: smooth noise (not sine) breathing/weight shifts.
	want_pitch += _noise.get_noise_1d(_t * 0.45) * 0.03
	want_roll += _noise.get_noise_1d(_t * 0.31 + 40.0) * 0.03
	var noise_xz := Vector3(_noise.get_noise_1d(_t * 0.5 + 80.0), 0.0, _noise.get_noise_1d(_t * 0.4 + 120.0)) * 0.015

	_pitch = ProcIK.damp_float(_pitch, clampf(want_pitch, -0.5, 0.5), 8.0, delta)
	_roll = ProcIK.damp_float(_roll, clampf(want_roll, -0.4, 0.4), 8.0, delta)

	# Walk twist: hips yaw with actual foot fore/aft asymmetry, chest counters.
	var want_hip_yaw := 0.0
	if _legs.size() >= 2:
		var lz := 0.0
		var rz := 0.0
		var lc := 0.0
		var rc := 0.0
		for i in _legs.size():
			var rel_z := (to_skel * _legs[i].foot_pos).z - _leg_home_rest[i].z
			if _legs[i].side < 0.0:
				lz += rel_z
				lc += 1.0
			else:
				rz += rel_z
				rc += 1.0
		if lc > 0.0 and rc > 0.0:
			want_hip_yaw = clampf((lz / lc - rz / rc) * 0.35, -0.3, 0.3)
	_hip_yaw = ProcIK.damp_float(_hip_yaw, want_hip_yaw, 10.0, delta)

	# Lunge forward while punching.
	var lunge := Vector3.ZERO
	if _attacking:
		lunge = Vector3(0.0, 0.0, -0.14) * _strike_curve()

	# --- Joint positions -------------------------------------------------
	var pos: Array[Vector3] = []
	pos.resize(n)
	pos[0] = Vector3(_seg_rest_pos[0].x, _root_h + _bounce, _seg_rest_pos[0].z) + noise_xz + lunge + _impact_kick
	var tilt := Basis(Vector3.RIGHT, _pitch) * Basis(Vector3(0, 0, 1), _roll)
	var world := _sk.global_transform
	for i in range(1, n):
		var seg := plan.segments[i]
		if seg.lag > 0.0:
			# World-space follow-through: the joint chases its parent's motion.
			var parent_world: Vector3 = world * pos[i - 1]
			var seg_len: float = seg.offset.length()
			var dir: Vector3 = _seg_world_pos[i] - parent_world
			dir.y *= 0.4
			if dir.length_squared() < 0.000001:
				dir = world.basis * seg.offset
			dir = dir.normalized()
			var target: Vector3 = parent_world + dir * seg_len
			var ground := _ray_ground(target)
			target.y = ground["pos"].y + plan.ride_height + _bounce * 0.5
			_seg_world_pos[i] = ProcIK.damp_vec(_seg_world_pos[i], target, seg.lag, delta)
			_seg_world_pos[i] = parent_world + (_seg_world_pos[i] - parent_world).normalized() * seg_len
			pos[i] = to_skel * _seg_world_pos[i]
		else:
			var rot := tilt * Basis(Vector3.RIGHT, seg.preferred_pitch)
			pos[i] = pos[i - 1] + rot * seg.offset
			_seg_world_pos[i] = world * pos[i]

	# --- Bone rotations from positions ------------------------------------
	var prev_basis := Basis.IDENTITY
	for i in n:
		var g: Basis
		if i < n - 1:
			var rest_off := plan.segments[i + 1].offset
			var cur_off := pos[i + 1] - pos[i]
			g = _segment_basis(rest_off, cur_off, i)
		else:
			g = prev_basis if n > 1 else _segment_basis(Vector3.UP, tilt * Vector3.UP, 0)
		_sk.set_bone_pose_rotation(_rig.spine_bones[i], (prev_basis.transposed() * g).get_rotation_quaternion().normalized())
		if i == 0:
			_sk.set_bone_pose_position(_rig.spine_bones[0], pos[0])
		out[i] = Transform3D(g, pos[i])
		prev_basis = g
	return out


func _segment_basis(rest_off: Vector3, cur_off: Vector3, seg_index: int) -> Basis:
	var vertical := absf(rest_off.normalized().y) > 0.7 if rest_off.length_squared() > 0.000001 else true
	var rest_sec := Vector3.FORWARD if vertical else Vector3.UP
	var yaw := _hip_yaw if seg_index == 0 else -_hip_yaw * 0.7
	var cur_sec := Basis(Vector3.UP, yaw) * (Basis(Vector3.RIGHT, _pitch) * rest_sec) if vertical else Vector3.UP
	return ProcIK.basis_from_pair(rest_off if rest_off.length_squared() > 0.000001 else Vector3.UP, rest_sec, cur_off, cur_sec)


func _span_z() -> float:
	var mn := INF
	var mx := -INF
	for home in _leg_home_rest:
		mn = minf(mn, home.z)
		mx = maxf(mx, home.z)
	return mx - mn if mx > mn else 0.0


func _span_x() -> float:
	var mn := INF
	var mx := -INF
	for home in _leg_home_rest:
		mn = minf(mn, home.x)
		mx = maxf(mx, home.x)
	return mx - mn if mx > mn else 0.0


# --- Head --------------------------------------------------------------------

func _solve_head(delta: float, to_skel: Transform3D, spine: Array[Transform3D]) -> void:
	var seg_t := spine[_rig.head_attach_segment()]
	var neck_pos := seg_t * plan.neck_offset

	var want_yaw := 0.0
	var want_pitch := 0.0
	torso_turn_request = ProcIK.damp_float(torso_turn_request, 0.0, 10.0, delta)
	if _look_target != null:
		var target_pos: Vector3 = to_skel * (_look_target.global_position + Vector3.UP)
		var dir := (target_pos - neck_pos)
		var local_dir := seg_t.basis.transposed() * dir
		var yp := ProcIK.yaw_pitch(local_dir)
		# Hysteresis: once the neck strains past comfort, keep asking the torso
		# to rotate (legs step around) until the head is nicely recentered.
		var comfort := plan.head_yaw_limit * 0.75
		if absf(yp.x) > comfort:
			_neck_strained = true
		elif absf(yp.x) < comfort * 0.3:
			_neck_strained = false
		if _neck_strained:
			torso_turn_request = yp.x
		want_yaw = clampf(yp.x, -plan.head_yaw_limit, plan.head_yaw_limit)
		want_pitch = clampf(yp.y, -plan.head_pitch_limit, plan.head_pitch_limit)
	else:
		_neck_strained = false
		# Idle gaze wander.
		want_yaw = _noise.get_noise_1d(_t * 0.27 + 200.0) * plan.head_yaw_limit * 0.5
		want_pitch = _noise.get_noise_1d(_t * 0.22 + 260.0) * plan.head_pitch_limit * 0.3

	if _attacking and _rig.arms.is_empty():
		want_pitch -= _strike_curve() * 0.5

	_head_yaw = ProcIK.damp_angle(_head_yaw, want_yaw, 9.0, delta)
	_head_pitch = ProcIK.damp_angle(_head_pitch, want_pitch, 9.0, delta)

	var g_neck := seg_t.basis * ProcIK.basis_from_yaw_pitch(_head_yaw * 0.35, _head_pitch * 0.35)
	var g_head := seg_t.basis * ProcIK.basis_from_yaw_pitch(_head_yaw, _head_pitch)
	_sk.set_bone_pose_rotation(_rig.neck_bone, (seg_t.basis.transposed() * g_neck).get_rotation_quaternion().normalized())
	_sk.set_bone_pose_rotation(_rig.head_bone, (g_neck.transposed() * g_head).get_rotation_quaternion().normalized())


# --- Tail --------------------------------------------------------------------

func _solve_tail(delta: float, to_skel: Transform3D, spine: Array[Transform3D]) -> void:
	if _rig.tail_bones.is_empty():
		return
	var world := _sk.global_transform
	var attach := spine[_rig.tail_attach_segment()]
	var prev_pos: Vector3 = world * attach.origin
	var prev_basis := attach.basis
	var swish := 1.0 + (3.0 * _strike_curve() if _attacking else 0.0)
	for t in plan.tail_offsets.size():
		var off: Vector3 = plan.tail_offsets[t]
		var seg_len := off.length()
		var dir: Vector3 = _tail_world_pos[t] - prev_pos
		if dir.length_squared() < 0.000001:
			dir = world.basis * off
		dir = dir.normalized()
		var idle_wave := _noise.get_noise_1d(_t * (1.1 * swish) + float(t) * 7.0) * 0.35
		dir = (dir + world.basis * Vector3(idle_wave * 0.3, 0.0, 0.0)).normalized()
		var target := prev_pos + dir * seg_len
		_tail_world_pos[t] = ProcIK.damp_vec(_tail_world_pos[t], target, 14.0 + 4.0 * float(t), delta)
		_tail_world_pos[t] = prev_pos + (_tail_world_pos[t] - prev_pos).normalized() * seg_len

		var cur_off := to_skel.basis * (_tail_world_pos[t] - prev_pos)
		var g := ProcIK.basis_from_pair(off, Vector3.UP, cur_off, Vector3.UP)
		# The tail link mesh hangs off the PARENT bone, so each bone's rotation
		# is what carries the next joint (and its mesh) into place.
		_sk.set_bone_pose_rotation(_rig.tail_bones[t], (prev_basis.transposed() * g).get_rotation_quaternion().normalized())
		prev_pos = _tail_world_pos[t]
		prev_basis = g


# --- Legs --------------------------------------------------------------------

func _solve_legs(delta: float, to_skel: Transform3D, spine: Array[Transform3D]) -> void:
	for i in _legs.size():
		var leg := _legs[i]
		var leg_plan := leg.plan
		var seg_t := spine[leg_plan.segment]
		var hip_pos := seg_t * leg_plan.hip_offset
		_sk.set_bone_pose_position(leg.hip_bone, leg_plan.hip_offset)

		var target: Vector3
		if _grounded and leg.initialized:
			target = to_skel * leg.foot_pos
		else:
			# Airborne: tuck legs under the body.
			var reach := leg_plan.upper_len + leg_plan.lower_len
			target = hip_pos + Vector3(leg_plan.stance.x * 0.4, -reach * 0.55, -reach * 0.15)

		var bend_z := -1.0 if leg_plan.knee_forward else 1.0
		var pole := hip_pos + Vector3(leg_plan.stance.x * 0.3, 0.0, bend_z * (leg_plan.upper_len + leg_plan.lower_len) * 0.6)
		var hint := Vector3(0.0, 0.0, bend_z)
		var solved := ProcIK.solve_two_bone(
			_sk, leg.hip_bone, leg.knee_bone, leg.foot_bone,
			hip_pos, target, pole, seg_t.basis, hint
		)
		# Keep the foot flat on its ground normal, yawing with the body.
		var normal_skel: Vector3 = (to_skel.basis * leg.ground_normal).normalized()
		var g_foot := Basis(Quaternion(Vector3.UP, normal_skel))
		var basis_b: Basis = solved["basis_b"]
		_sk.set_bone_pose_rotation(leg.foot_bone, (basis_b.transposed() * g_foot).get_rotation_quaternion().normalized())


# --- Arms --------------------------------------------------------------------

func _solve_arms(delta: float, to_skel: Transform3D, spine: Array[Transform3D]) -> void:
	for i in _rig.arms.size():
		var info: Dictionary = _rig.arms[i]
		var arm_plan: ProcBodyPlan.ArmPlan = info["plan"]
		var side: float = info["side"]
		var seg_t := spine[arm_plan.segment]
		var shoulder := seg_t * arm_plan.shoulder_offset
		_sk.set_bone_pose_position(int(info["shoulder"]), arm_plan.shoulder_offset)
		var reach := arm_plan.upper_len + arm_plan.lower_len

		var target: Vector3
		var pole: Vector3
		var snappy := 14.0
		var aim_dir := Vector3.ZERO
		if _look_target != null:
			aim_dir = (to_skel * (_look_target.global_position + Vector3.UP) - shoulder)

		if i < _hand_override.size() and _hand_override[i] != null:
			# Ledge grab: pin the hand to its world-space hold.
			target = to_skel * (_hand_override[i] as Vector3)
			pole = shoulder + Vector3(side * 0.4, 0.3, -0.2)
			snappy = 26.0
		elif _attacking and i == _attack_arm and not _rig.arms.is_empty():
			var strike_to := shoulder + Vector3(side * 0.05, 0.05, -reach * 0.98)
			if aim_dir != Vector3.ZERO:
				strike_to = shoulder + aim_dir.normalized() * minf(aim_dir.length(), reach * 0.98)
			var windup := shoulder + Vector3(side * 0.3, 0.15, reach * 0.45)
			target = _attack_track(windup, strike_to, shoulder)
			pole = shoulder + Vector3(side * 0.5, 0.1, 0.15)
			snappy = 30.0
		elif aim_dir != Vector3.ZERO and aim_dir.length() < plan.attack_reach * 2.5:
			# Hands raise and aim at the target.
			var wobble := Vector3(
				_noise.get_noise_1d(_t * 1.3 + float(i) * 31.0),
				_noise.get_noise_1d(_t * 1.1 + float(i) * 57.0),
				0.0
			) * 0.04
			target = shoulder + aim_dir.normalized() * (reach * 0.72) + wobble
			pole = shoulder + Vector3(side * 0.5, 0.1, 0.15)
		else:
			# Relaxed hang with counter-swing coupled to the OPPOSITE leg's
			# actual foot position (never a sine wave).
			var swing := 0.0
			for li in _legs.size():
				if _legs[li].side != side:
					var rel_z := (to_skel * _legs[li].foot_pos).z - _leg_home_rest[li].z
					swing = clampf(rel_z, -0.35, 0.35) * plan.arm_swing
					break
			target = shoulder + Vector3(side * 0.07, -reach * 0.85 + absf(swing) * 0.25, swing)
			pole = shoulder + Vector3(side * 0.3, -0.2, 0.5)

		_hand_pos[i] = ProcIK.damp_vec(_hand_pos[i], target, snappy, delta)
		ProcIK.solve_two_bone(
			_sk, int(info["shoulder"]), int(info["elbow"]), int(info["hand"]),
			shoulder, _hand_pos[i], pole, seg_t.basis, Vector3(side * 0.4, 0.0, 1.0)
		)


## Windup -> strike -> recover positions along the attack timeline.
func _attack_track(windup: Vector3, strike: Vector3, rest: Vector3) -> Vector3:
	if _attack_p < 0.28:
		return windup
	elif _attack_p < 0.55:
		return strike
	return rest + Vector3(0.0, -0.2, 0.0)


## 0..1..0 strike emphasis, peaking during the hit window.
func _strike_curve() -> float:
	return clampf(1.0 - absf(_attack_p - 0.45) / 0.35, 0.0, 1.0)
