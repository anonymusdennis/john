extends CharacterBody3D
## Smart chase enemy driven entirely by the procedural animation system.
##
## Locomotion brain: a small state machine on top of the NavGraph.
##   CHASE     direct steering + reactive step-up hops (tiny ledges never stall)
##   PATH      follows typed waypoints (walk/step/drop/jump/climb/wall) from
##             either the NavGraph or the target's recorded breadcrumb trail
##   JUMPING   ballistic gap crossing computed from the jump edge
##   CLIMBING  parkour ledge grab: hands pin to the lip, body clambers over
##   LAUNCHED  knockback broke this body's grip - ballistic tumble, no steering
##   RECOVER   brief stagger after landing
##
## Route acquisition is a three-tier fallback, all multiplayer-aware (the
## enemy hunts the nearest member of the "nav_target" group — any player or
## companion):
##   1. direct steering when the target is roughly level and visible
##   2. async NavGraph query (solved on the graph's worker thread — requesting
##      a path never freezes a frame)
##   3. the target's own NavPathRecorder trail: if the graph cannot reach a
##      floating platform but the target walked/jumped there, the enemy
##      replays the target's proven line, classifying each trail segment
##      against its own abilities (jump / ledge-climb / wall-walk).
##
## Wall walking (spiders & friends): the body's up axis follows the surface
## normal, gravity pulls into the wall, feet plant via the animator's
## basis-relative rays, and corners are wrapped with probe rays. Strong hits
## override grip and throw the walker off the wall.

enum State { CHASE, PATH, JUMPING, CLIMBING, LAUNCHED, RECOVER }

const TARGET_GROUP := "nav_target"  ## Players AND companions register here.

@export_enum("human", "imp", "centaur", "spider", "centipede") var body_form: String = "human"
@export var move_speed: float = 3.5
@export var turn_speed: float = 6.0
@export var chase_range: float = 40.0
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.2

@export_group("Navigation")
## basic = ground routes only; parkour = may also jump gaps and climb ledges.
@export_enum("basic", "parkour") var nav_mode: String = "basic"
## Spider-like surface grip: walks straight up walls (and across ceilings).
@export var can_wall_walk: bool = false
@export var max_step_height: float = 0.6
@export var max_drop: float = 5.0
@export var jump_apex: float = 1.5
@export var jump_range: float = 6.5
## Beyond this distance from the player the enemy sleeps (animation + AI off).
@export var activation_range: float = 80.0

@export_group("Physique")
## Kg-ish inertia; -1 = derive from the body plan's collider volume.
## Light imps fly across the yard, heavy centaurs barely stumble.
@export var body_mass_override: float = -1.0
## Delta-v (m/s) this body shrugs off before feet grip breaks and it is
## thrown into a ballistic LAUNCHED tumble. Repeated hits wear grip down.
@export var grip_strength: float = 4.5

@onready var animator: ProcAnimator = $Animator
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

const SURFACE_MASK := 32            ## Static nav geometry (layer 6).

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _attack_cd: float = 0.0
var _target: Node3D                         ## Nearest nav target (player/companion).
var _retarget_timer: float = 0.0
var _state: int = State.CHASE
var _recover_timer: float = 0.0
var _ext_vel: Vector3 = Vector3.ZERO        ## Decaying external impulse channel.
var _mass: float = 20.0
var _grip_damage: float = 0.0               ## Recent hits wear grip down.

var _graph: NavGraph
var _profile: NavAgentProfile
var _path: Array = []
var _path_i: int = 0
var _path_from_trail: bool = false          ## Current path replays the target's trail.
var _path_pending: bool = false             ## An async graph query is in flight.
var _path_gen: int = 0                      ## Request serial; stale results are dropped.
var _pending_timeout: float = 0.0

const PATH_REQUEST_TIMEOUT := 3.0           ## Give up waiting on a query after this.
var _repath_timer: float = 0.0
var _path_goal: Vector3 = Vector3.INF
var _stuck_timer: float = 0.0
var _hop_cd: float = 0.0

var _surface_normal: Vector3 = Vector3.UP   ## Current "up" (wall walking).
var _desired_fwd: Vector3 = Vector3.FORWARD

var _jump_target: Vector3 = Vector3.ZERO
var _jump_time: float = 0.0
var _climb_from: Vector3 = Vector3.ZERO
var _climb_to: Vector3 = Vector3.ZERO
var _climb_p: float = 0.0
var _climb_dur: float = 0.6

var _sleeping: bool = false


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 1
	collision_mask = 1 | 2
	if animator.plan == null or animator.body_form != body_form:
		animator.build(StringName(body_form))
	_fit_collider()
	_mass = body_mass_override if body_mass_override > 0.0 else _derived_mass()
	_desired_fwd = -global_transform.basis.z
	_repath_timer = randf()   # Staggers repaths across the population.

	_profile = NavAgentProfile.for_plan(animator.plan)
	_profile.max_step = max_step_height
	_profile.max_drop = max_drop
	_profile.jump_height = jump_apex
	_profile.jump_range = jump_range
	if nav_mode == "parkour":
		_profile.can_jump = true
		_profile.can_parkour = animator.arm_count() >= 2   # Climbing needs hands.
	_profile.can_wall_walk = can_wall_walk


func _exit_tree() -> void:
	if _graph != null and is_instance_valid(_graph):
		_graph.set_debug_path(get_instance_id(), PackedVector3Array())


func _derived_mass() -> float:
	var r := animator.plan.collider_radius
	var h := animator.plan.collider_height
	return clampf(r * r * h * 60.0, 8.0, 400.0)


## Sizes the capsule from the generated body so nothing floats or sinks.
func _fit_collider() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = animator.plan.collider_radius
	shape.height = maxf(animator.plan.collider_height, shape.radius * 2.0)
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, shape.height * 0.5 + 0.01, 0.0)


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_hop_cd = maxf(_hop_cd - delta, 0.0)
	_repath_timer = maxf(_repath_timer - delta, 0.0)
	_grip_damage = maxf(_grip_damage - 1.2 * delta, 0.0)
	if _path_pending:
		_pending_timeout -= delta
		if _pending_timeout <= 0.0:
			_path_pending = false
			_path_gen += 1  # Invalidate the in-flight result so it can't land stale.
	_acquire_target(delta)
	if _graph == null:
		_graph = get_tree().get_first_node_in_group("nav_graph") as NavGraph

	if _update_lod():
		return

	match _state:
		State.LAUNCHED:
			_process_launched(delta)
		State.RECOVER:
			_process_recover(delta)
		State.JUMPING:
			_process_jumping(delta)
		State.CLIMBING:
			_process_climbing(delta)
		State.CHASE:
			_process_chase(delta)
		State.PATH:
			_process_path(delta)


## Multiplayer-aware target selection: hunt the nearest "nav_target" (any
## player or companion). Rescans on a cadence with light stickiness so two
## equidistant targets don't cause flip-flopping.
func _acquire_target(delta: float) -> void:
	_retarget_timer -= delta
	if _target != null and is_instance_valid(_target) and _retarget_timer > 0.0:
		return
	_retarget_timer = 0.7
	if _target != null and not is_instance_valid(_target):
		_target = null
	var candidates := get_tree().get_nodes_in_group(TARGET_GROUP)
	if candidates.is_empty():
		candidates = get_tree().get_nodes_in_group("player")
	var best: Node3D = null
	var best_d := INF
	for c in candidates:
		var n := c as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var d := global_position.distance_squared_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		_target = null
		return
	# Keep the current target unless the new one is meaningfully closer.
	if _target != null and _target != best:
		var cur_d := global_position.distance_squared_to(_target.global_position)
		if cur_d <= best_d * 1.25:
			return
	_target = best


## Animation/AI LOD: far-away enemies freeze (big-map guardrail).
func _update_lod() -> bool:
	var far := _target == null or global_position.distance_to(_target.global_position) > activation_range
	if far and _state != State.LAUNCHED:
		if not _sleeping:
			_sleeping = true
			animator.set_physics_process(false)
		return true
	if _sleeping:
		_sleeping = false
		animator.set_physics_process(true)
	return false


# --- Shared movement helpers ---------------------------------------------------

func _on_wall_surface() -> bool:
	return _surface_normal.y < 0.8


func _apply_gravity(delta: float) -> void:
	up_direction = _surface_normal
	if _on_wall_surface():
		# Stickiness: gravity pulls INTO the wall while attached.
		velocity += -_surface_normal * _gravity * 1.2 * delta
	elif not is_on_floor():
		velocity.y -= _gravity * delta


## Smoothly aligns the whole body (and its collider) to the surface normal,
## yawing toward the desired forward direction.
func _align_body(delta: float) -> void:
	var up := _surface_normal
	var fwd := _desired_fwd - up * _desired_fwd.dot(up)
	if fwd.length_squared() < 0.0001:
		var cur := -global_transform.basis.z
		fwd = cur - up * cur.dot(up)
	if fwd.length_squared() < 0.0001:
		fwd = global_transform.basis.x.cross(up)
	fwd = fwd.normalized()
	var right := fwd.cross(up).normalized()
	var target := Basis(right, up, -fwd).orthonormalized()
	var t := clampf(turn_speed * delta, 0.0, 1.0)
	var q := global_transform.basis.get_rotation_quaternion().slerp(target.get_rotation_quaternion(), t)
	global_transform.basis = Basis(q)


func _face_toward(dir: Vector3) -> void:
	var flat := dir - _surface_normal * dir.dot(_surface_normal)
	if flat.length_squared() > 0.0001:
		_desired_fwd = flat.normalized()


## Steers along the current surface toward a target and moves.
func _steer_move(target: Vector3, delta: float, speed_scale: float = 1.0) -> void:
	var to_target := target - global_position
	var along := to_target - _surface_normal * to_target.dot(_surface_normal)
	var dist := along.length()
	var dir := along / maxf(dist, 0.001)
	_face_toward(dir)

	var wish := dir * move_speed * speed_scale
	if _on_wall_surface():
		# Full-plane movement on walls (climbs straight up the face).
		var v_norm := _surface_normal * velocity.dot(_surface_normal)
		var v_along := velocity - v_norm
		v_along = v_along.move_toward(wish, 30.0 * delta)
		velocity = v_along + v_norm
	else:
		velocity.x = wish.x + _ext_vel.x
		velocity.z = wish.z + _ext_vel.z
		_try_step_up(dir)
	_track_stuck(delta, dist)


func _idle_move(delta: float) -> void:
	if not _on_wall_surface():
		velocity.x = _ext_vel.x
		velocity.z = _ext_vel.z


func _finish_move(delta: float) -> void:
	_ext_vel = _ext_vel.move_toward(Vector3.ZERO, (10.0 if is_on_floor() else 1.5) * delta)
	_apply_gravity(delta)
	move_and_slide()
	if _on_wall_surface():
		_update_wall_stick(delta)
	_align_body(delta)
	animator.set_locomotion(velocity, is_on_floor())
	animator.set_look_target(_target)


## Watches for lack of progress while trying to move -> triggers repaths.
func _track_stuck(delta: float, remaining: float) -> void:
	var flat_vel := velocity - _surface_normal * velocity.dot(_surface_normal)
	if remaining > 1.0 and flat_vel.length() < move_speed * 0.25:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(_stuck_timer - delta * 2.0, 0.0)


## Reactive tiny-ledge fix: shin probe + lip probe + headroom probe, then a
## small hop so obstacles under max_step_height never stall an enemy.
func _try_step_up(dir: Vector3) -> void:
	if _hop_cd > 0.0 or not is_on_floor():
		return
	var space := get_world_3d().direct_space_state
	var r := animator.plan.collider_radius
	var shin_from := global_position + Vector3.UP * 0.12
	var q := PhysicsRayQueryParameters3D.create(shin_from, shin_from + dir * (r + 0.55))
	q.collision_mask = SURFACE_MASK
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	if (hit["normal"] as Vector3).y > 0.5:
		return   # Ramp - walkable without a hop.

	# Where is the obstacle's top?
	var over := global_position + dir * (r + 0.5) + Vector3.UP * (max_step_height + 0.35)
	var down_q := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * (max_step_height + 0.4))
	down_q.collision_mask = SURFACE_MASK
	var top := space.intersect_ray(down_q)
	if top.is_empty():
		return
	var rise := (top["position"] as Vector3).y - global_position.y
	if rise < 0.04 or rise > max_step_height:
		return

	# Headroom over the lip for this body's height.
	var head_from := (top["position"] as Vector3) + Vector3.UP * 0.05
	var head_q := PhysicsRayQueryParameters3D.create(head_from, head_from + Vector3.UP * animator.plan.collider_height * 0.9)
	head_q.collision_mask = SURFACE_MASK
	if not space.intersect_ray(head_q).is_empty():
		return

	velocity.y = sqrt(2.0 * _gravity * (rise + 0.3))
	_hop_cd = 0.4


## True when the ground ahead ends in a drop deeper than `allowed_drop` —
## used to brake at lips during direct chase instead of lemming off them.
func _void_ahead(dir: Vector3, allowed_drop: float) -> bool:
	var space := get_world_3d().direct_space_state
	var ahead := global_position + dir * (animator.plan.collider_radius + 0.65) + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * (allowed_drop + 0.9))
	q.collision_mask = SURFACE_MASK
	return space.intersect_ray(q).is_empty()


# --- States ------------------------------------------------------------------

func _process_chase(delta: float) -> void:
	if _target == null:
		_idle_move(delta)
		_finish_move(delta)
		return

	var to_target := _target.global_position - global_position
	var dist := to_target.length()
	if dist > chase_range:
		_apply_neck_relief(delta)
		_idle_move(delta)
		_finish_move(delta)
		return

	var flat_dist := Vector2(to_target.x, to_target.z).length()
	if flat_dist <= attack_range and absf(to_target.y) < 2.0 and not _on_wall_surface():
		if _attack_cd <= 0.0 and animator.trigger_attack():
			_attack_cd = attack_cooldown
		_face_toward(to_target)
		_idle_move(delta)
		_finish_move(delta)
		return

	if _on_wall_surface():
		_process_wall_chase(delta)
		return

	# Does direct steering suffice, or do we need the smart path? The query
	# is async (worker thread) — keep steering while it is being solved.
	var needs_path := absf(to_target.y) > 1.6 or _stuck_timer > 0.8
	if needs_path:
		_try_request_path()

	# Wall walkers: player above and a face in front -> just climb it.
	if can_wall_walk and to_target.y > 1.6 and _try_attach_wall():
		_finish_move(delta)
		return

	# Void-ahead guard: never blindly run off a lip when falling would strand
	# us — brake at the edge and plan a smart route instead of dropping into
	# the gap and (formerly) mega-jumping back up from the very ground.
	# Deep drops are only taken when the target is actually below us.
	var flat_dir := Vector3(to_target.x, 0.0, to_target.z)
	if is_on_floor() and flat_dir.length_squared() > 0.01:
		var allowed_drop := max_drop if to_target.y < -1.5 else maxf(max_step_height + 0.6, 1.2)
		if _void_ahead(flat_dir.normalized(), allowed_drop):
			_try_request_path()
			_face_toward(to_target)
			_idle_move(delta)
			_finish_move(delta)
			return

	_steer_move(_target.global_position, delta)
	_finish_move(delta)


## Crawling on a wall/ceiling toward the target; drop when they are below.
func _process_wall_chase(delta: float) -> void:
	var to_target := _target.global_position - global_position
	if to_target.y < -1.0 and _surface_normal.dot(to_target.normalized()) > 0.25:
		_detach_wall()
	else:
		_steer_move(_target.global_position + Vector3.UP * 0.5, delta, 0.85)
	_finish_move(delta)


func _process_path(delta: float) -> void:
	if _target == null or _path.is_empty() or _path_i >= _path.size():
		_clear_path()
		_process_chase(delta)
		return

	# Close enough for direct pursuit again?
	var to_target := _target.global_position - global_position
	if Vector2(to_target.x, to_target.z).length() < 5.0 and absf(to_target.y) < 1.4:
		_clear_path()
		_process_chase(delta)
		return

	# Target drifted away from this path's goal -> repath on cadence (async;
	# the current path keeps being followed until the new one lands).
	if _repath_timer <= 0.0 and _path_goal.distance_to(_target.global_position) > 4.0:
		_try_request_path()

	if _stuck_timer > 1.1:
		_stuck_timer = 0.0
		_clear_path()
		_finish_move(delta)
		return

	var wp: Dictionary = _path[_path_i]
	var wp_pos: Vector3 = wp["pos"]
	var move: int = wp["move"]
	var to_wp := wp_pos - global_position

	# Anticipated takeoff: when the NEXT waypoint is a jump, launch as soon
	# as this lip waypoint is close instead of overshooting it at full speed
	# and sliding off the ledge before the jump triggers.
	if move != NavGraph.Edge.JUMP and is_on_floor() and _path_i + 1 < _path.size():
		var nxt: Dictionary = _path[_path_i + 1]
		if int(nxt["move"]) == NavGraph.Edge.JUMP:
			var flat_to_lip := Vector2(to_wp.x, to_wp.z).length()
			if flat_to_lip < 1.25 and absf(to_wp.y) < 1.1:
				_path_i += 1
				if _begin_jump(nxt["pos"]):
					_finish_move(delta)
					return
				_clear_path()
				_finish_move(delta)
				return

	match move:
		NavGraph.Edge.JUMP:
			if is_on_floor():
				if not _begin_jump(wp_pos):
					_clear_path()
				_finish_move(delta)
				return
			# Missed the takeoff and now falling: abort before the fall turns
			# into an impossible ground-to-rooftop mega jump from below.
			if velocity.y < -3.0 or global_position.y < wp_pos.y - max_drop - 1.0:
				_clear_path()
				_finish_move(delta)
				return
			_steer_move(wp_pos, delta)
		NavGraph.Edge.CLIMB:
			var flat := Vector2(to_wp.x, to_wp.z).length()
			# Stuck against the face still counts as "arrived" — grab anyway.
			var arrived := flat < 1.7 or (_stuck_timer > 0.45 and flat < 2.5)
			if arrived and to_wp.y > 0.3 and is_on_floor():
				if not _begin_climb(wp_pos):
					_clear_path()
				_finish_move(delta)
				return
			_steer_move(Vector3(wp_pos.x, global_position.y, wp_pos.z), delta, 0.9)
		NavGraph.Edge.WALL:
			if to_wp.y > 0.4 and not _on_wall_surface():
				# Need to get onto the face first.
				if not _try_attach_wall(wp_pos):
					_steer_move(Vector3(wp_pos.x, global_position.y, wp_pos.z), delta)
			else:
				_steer_move(wp_pos, delta)
		_:
			# Slow down on the approach to a takeoff lip for a clean jump.
			var spd := 1.0
			if _path_i + 1 < _path.size() and int((_path[_path_i + 1] as Dictionary)["move"]) == NavGraph.Edge.JUMP:
				if Vector2(to_wp.x, to_wp.z).length() < 3.0:
					spd = 0.75
			_steer_move(wp_pos, delta, spd)

	if _waypoint_reached(wp_pos, move):
		_path_i += 1
		if _path_i >= _path.size():
			_clear_path()
	_finish_move(delta)


func _waypoint_reached(wp_pos: Vector3, move: int) -> bool:
	var to_wp := wp_pos - global_position
	if move == NavGraph.Edge.WALL or _on_wall_surface():
		return to_wp.length() < 1.3
	return Vector2(to_wp.x, to_wp.z).length() < 0.95 and to_wp.y > -2.5 and to_wp.y < 1.6


func _process_jumping(delta: float) -> void:
	_jump_time -= delta
	velocity.y -= _gravity * delta
	move_and_slide()
	animator.set_locomotion(velocity, false)
	animator.set_look_target(_target)
	if (is_on_floor() and _jump_time < 0.35) or _jump_time <= -2.0:
		# Landed far from the intended lip -> the rest of the path is stale.
		if global_position.distance_to(_jump_target) > 3.0:
			_clear_path()
			_state = State.CHASE
			return
		_state = State.PATH if not _path.is_empty() else State.CHASE
		if not _path.is_empty() and _path_i < _path.size():
			var wp: Dictionary = _path[_path_i]
			if global_position.distance_to(wp["pos"]) < 1.8:
				_path_i += 1
				if _path_i >= _path.size():
					_clear_path()


## Ballistic gap jump: solve the arc that lands exactly on the target lip.
## Refuses infeasible jumps (too high / too far — e.g. after having fallen
## off the takeoff ledge) so the enemy repaths instead of mega-jumping.
func _begin_jump(target: Vector3) -> bool:
	var dy := target.y - global_position.y
	var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if dy > jump_apex + 0.45 or flat.length() > jump_range + 1.5 or dy < -(max_drop + 2.0):
		return false
	var apex := maxf(dy, 0.0) + 1.1
	var v_y := sqrt(2.0 * _gravity * apex)
	var t_up := v_y / _gravity
	var t_down := sqrt(2.0 * maxf(apex - dy, 0.05) / _gravity)
	var t_total := maxf(t_up + t_down, 0.15)
	var hv := flat / t_total
	if hv.length() > 15.0:
		hv = hv.normalized() * 15.0
	velocity = hv + Vector3.UP * v_y
	_face_toward(flat)
	_jump_target = target
	_jump_time = t_total + 0.4
	_state = State.JUMPING
	animator.release_all_feet()
	return true


func _process_climbing(delta: float) -> void:
	_climb_p = minf(_climb_p + delta / _climb_dur, 1.0)
	var t := smoothstep(0.0, 1.0, _climb_p)
	# Bezier: rise along the wall, then over the lip.
	var mid := Vector3(_climb_from.x, _climb_to.y + 0.35, _climb_from.z)
	var a := _climb_from.lerp(mid, t)
	var b := mid.lerp(_climb_to, t)
	global_position = a.lerp(b, t)
	velocity = Vector3.ZERO
	animator.set_locomotion((_climb_to - _climb_from) / maxf(_climb_dur, 0.1), false)
	animator.set_look_target(_target)
	if _climb_p >= 1.0:
		animator.clear_hand_overrides()
		_state = State.PATH if not _path.is_empty() else State.CHASE
		if not _path.is_empty() and _path_i < _path.size():
			var wp: Dictionary = _path[_path_i]
			if global_position.distance_to(wp["pos"]) < 1.5:
				_path_i += 1
				if _path_i >= _path.size():
					_clear_path()


## Parkour ledge grab: pin both hands to the lip while the body clambers.
## Refuses ledges taller than this body can actually climb.
func _begin_climb(target: Vector3) -> bool:
	var rise := target.y - global_position.y
	if rise > _profile.climb_height + 0.5:
		return false
	_climb_from = global_position
	_climb_to = target + Vector3.UP * 0.05
	var dy := maxf(_climb_to.y - _climb_from.y, 0.3)
	_climb_dur = 0.45 + dy * 0.22
	_climb_p = 0.0
	_state = State.CLIMBING
	_face_toward(target - global_position)
	animator.release_all_feet()
	if animator.arm_count() >= 2:
		var fwd := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z).normalized()
		var side := fwd.cross(Vector3.UP)
		var lip := target - fwd * 0.15
		animator.set_hand_override(0, lip - side * 0.24)
		animator.set_hand_override(1, lip + side * 0.24)
	return true


## Ballistic tumble after a grip-breaking hit: no steering until landing.
func _process_launched(delta: float) -> void:
	_surface_normal = Vector3.UP
	up_direction = Vector3.UP
	velocity.y -= _gravity * delta
	move_and_slide()
	_align_body(delta)
	animator.set_locomotion(velocity, false)
	animator.set_look_target(_target)
	if is_on_floor() and Vector3(velocity.x, 0.0, velocity.z).length() < 6.0:
		velocity.x *= 0.4
		velocity.z *= 0.4
		_state = State.RECOVER
		_recover_timer = 0.55
		_ext_vel = Vector3.ZERO


func _process_recover(delta: float) -> void:
	_recover_timer -= delta
	if _recover_timer <= 0.0:
		_state = State.CHASE
	_idle_move(delta)
	_finish_move(delta)


# --- Pathing -----------------------------------------------------------------

## Queues an async NavGraph query toward the current target. The worker
## thread solves it off-frame; _on_path_result adopts it when it lands.
## Returns true when a request was actually queued.
func _try_request_path() -> bool:
	if _graph == null or _target == null or _path_pending:
		return false
	if _repath_timer > 0.0 or not _graph.can_query():
		return false
	_repath_timer = 0.9 + randf() * 0.5
	_path_gen += 1
	if _graph.request_path(global_position, _target.global_position, _profile,
			_on_path_result.bind(_path_gen)):
		_path_pending = true
		_pending_timeout = PATH_REQUEST_TIMEOUT
		return true
	return false


## Main-thread delivery of a solved path. Empty result = the graph cannot
## reach the target -> fall back to replaying the target's recorded trail.
func _on_path_result(path: Array, gen: int) -> void:
	if gen != _path_gen:
		return  # Superseded or timed-out request; a fresher one is in charge.
	_path_pending = false
	if _state == State.LAUNCHED or _state == State.RECOVER \
			or _state == State.JUMPING or _state == State.CLIMBING or _on_wall_surface():
		return
	if path.is_empty():
		_try_follow_trail()
		return
	_adopt_path(path, false)


func _adopt_path(path: Array, from_trail: bool) -> void:
	_path = path
	_path_i = 0
	_path_from_trail = from_trail
	_path_goal = _target.global_position if _target != null else Vector3.INF
	_state = State.PATH
	if _graph != null:
		var pts := PackedVector3Array()
		pts.append(global_position)
		for step in path:
			pts.append(step["pos"])
		_graph.set_debug_path(get_instance_id(), pts)


## Third routing option: replay the target's own breadcrumb trail. Used when
## the graph has no route (e.g. floating platforms the target jumped across)
## but the target's recorded line still ends near them and passes near this
## enemy. Each trail segment is classified against THIS body's abilities —
## jumps for parkour bodies, ledge climbs for bodies with hands, wall links
## for wall walkers — so every AI type gets its own valid interpretation.
func _try_follow_trail() -> bool:
	if _target == null:
		return false
	var rec := NavPathRecorder.find_for(_target)
	if rec == null or rec.size() < 2:
		return false
	# The trail is only a template while it still leads to the target.
	if rec.latest().distance_to(_target.global_position) > 6.0:
		return false
	var join := rec.nearest_index(global_position, 6.0, 3.5)
	if join < 0:
		return false
	# The entry segment (enemy -> join crumb) must be traversable too; back
	# up the trail a few crumbs to find one this body can actually reach.
	for back in 4:
		var j := join - back
		if j < 0:
			break
		var wps := _trail_to_waypoints(rec, j)
		if not wps.is_empty():
			_adopt_path(wps, true)
			return true
	return false


## Converts the trail from crumb `join` onward into typed waypoints this body
## can execute (including how to reach the join crumb itself), stopping at
## the first segment beyond its abilities. Empty when even the entry fails.
func _trail_to_waypoints(rec: NavPathRecorder, join: int) -> Array:
	var entry := _classify_trail_move(global_position, rec.point(join), false)
	if entry < 0:
		return []
	var wps: Array = [{"pos": rec.point(join), "move": entry}]
	var prev := rec.point(join)
	var since_kept := 0
	for i in range(join + 1, rec.size()):
		var c := rec.point(i)
		var move := _classify_trail_move(prev, c, true)
		if move < 0:
			break   # Beyond this body's skills — use the trail up to here.
		# Thin dense walk crumbs; always keep special moves and the last crumb.
		since_kept += 1
		if move != NavGraph.Edge.WALK or since_kept >= 2 or i == rec.size() - 1:
			wps.append({"pos": c, "move": move})
			since_kept = 0
		prev = c
	return wps


## How would THIS body travel from `a` to `b`? Returns a NavGraph.Edge or -1
## when the segment exceeds its abilities. `gap_is_jump` applies only between
## consecutive crumbs, where a wide grounded-crumb gap means the target
## jumped/launched across a void (the entry segment is just approach walking).
func _classify_trail_move(a: Vector3, b: Vector3, gap_is_jump: bool) -> int:
	var dy := b.y - a.y
	var flat := Vector2(b.x - a.x, b.z - a.z).length()
	if dy > max_step_height:
		if _profile.can_jump and dy <= jump_apex and flat <= jump_range:
			return NavGraph.Edge.JUMP
		if _profile.can_parkour and dy <= _profile.climb_height:
			return NavGraph.Edge.CLIMB
		if can_wall_walk:
			return NavGraph.Edge.WALL
		return -1
	if dy < -max_step_height:
		if -dy <= max_drop:
			return NavGraph.Edge.DROP
		if can_wall_walk:
			return NavGraph.Edge.WALL
		return -1
	if gap_is_jump and flat > NavPathRecorder.SPACING * 2.4:
		if _profile.can_jump and flat <= jump_range:
			return NavGraph.Edge.JUMP
		return -1
	return NavGraph.Edge.WALK


func _clear_path() -> void:
	_path = []
	_path_i = 0
	_path_from_trail = false
	if _state == State.PATH:
		_state = State.CHASE
	if _graph != null:
		_graph.set_debug_path(get_instance_id(), PackedVector3Array())


# --- Wall walking ----------------------------------------------------------------

## Attaches to a steep face ahead (toward `hint`, or toward the target).
func _try_attach_wall(hint: Vector3 = Vector3.INF) -> bool:
	if not can_wall_walk:
		return false
	var toward := _desired_fwd
	if hint != Vector3.INF:
		toward = Vector3(hint.x - global_position.x, 0.0, hint.z - global_position.z)
	elif _target != null:
		toward = Vector3(_target.global_position.x - global_position.x, 0.0, _target.global_position.z - global_position.z)
	if toward.length_squared() < 0.001:
		return false
	toward = toward.normalized()
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * (animator.plan.collider_height * 0.4)
	var q := PhysicsRayQueryParameters3D.create(from, from + toward * (animator.plan.collider_radius + 1.3))
	q.collision_mask = SURFACE_MASK
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var n: Vector3 = hit["normal"]
	if n.y > 0.5:
		return false
	_surface_normal = n
	velocity = -n * 3.0 + Vector3.UP * 1.5
	return true


func _detach_wall() -> void:
	_surface_normal = Vector3.UP
	up_direction = Vector3.UP
	animator.release_all_feet()


## Keeps the body glued to the surface, wraps convex corners, and lets go
## when the surface truly ends.
func _update_wall_stick(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var center := global_position + _surface_normal * (animator.plan.collider_radius * 0.6)
	var q := PhysicsRayQueryParameters3D.create(center, center - _surface_normal * (animator.plan.collider_radius + 1.1))
	q.collision_mask = SURFACE_MASK
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var n: Vector3 = hit["normal"]
		_surface_normal = _surface_normal.slerp(n, clampf(10.0 * delta, 0.0, 1.0)).normalized()
		if _surface_normal.y > 0.85:
			_surface_normal = Vector3.UP
		return

	# Lost the face - probe around the lip (outer corner wrap, wall -> top).
	var fwd := -global_transform.basis.z
	var probe_from := center + fwd * 0.7 - _surface_normal * 0.4
	var q2 := PhysicsRayQueryParameters3D.create(probe_from, probe_from - fwd * 1.0)
	q2.collision_mask = SURFACE_MASK
	var hit2 := space.intersect_ray(q2)
	if not hit2.is_empty():
		var n2: Vector3 = hit2["normal"]
		_surface_normal = _surface_normal.slerp(n2, clampf(6.0 * delta, 0.0, 1.0)).normalized()
		velocity += fwd * 1.5 * delta
		if _surface_normal.y > 0.85:
			_surface_normal = Vector3.UP
		return

	_detach_wall()


# --- Knockback ---------------------------------------------------------------

## Public knockback API - impulse is in N*s; heavier bodies move less.
## The animator always reels at the hit point; if the delta-v (plus recent
## accumulated hits) beats this body's grip, every foot lets go and the enemy
## detaches from whatever surface it was on, tumbling until it lands.
func apply_knockback(impulse: Vector3, hit_pos: Vector3 = Vector3.INF) -> void:
	var dv := impulse * (4.0 / _mass)
	if hit_pos == Vector3.INF:
		hit_pos = global_position + Vector3.UP * animator.plan.collider_height * 0.5
	animator.apply_impact(hit_pos, dv)

	var force := dv.length() + _grip_damage * 0.8
	_grip_damage = minf(_grip_damage + dv.length(), grip_strength * 2.0)

	if force >= grip_strength:
		# Grip override: feet release, body detaches and tumbles.
		animator.release_all_feet()
		animator.clear_hand_overrides()
		_surface_normal = Vector3.UP
		up_direction = Vector3.UP
		_clear_path()
		_state = State.LAUNCHED
		velocity += dv
		if velocity.y < dv.length() * 0.25:
			velocity.y = dv.length() * 0.35
	elif _state != State.LAUNCHED:
		_ext_vel += Vector3(dv.x, 0.0, dv.z)
		if not _on_wall_surface():
			velocity.y += dv.y


# --- Misc ----------------------------------------------------------------------

## The head asked for help: rotate the torso (legs step around) so the
## enemy can keep watching the player without breaking its neck.
func _apply_neck_relief(delta: float) -> void:
	var request := animator.torso_turn_request
	if absf(request) > 0.02:
		_desired_fwd = _desired_fwd.rotated(_surface_normal, clampf(request, -1.0, 1.0) * turn_speed * 0.6 * delta)
