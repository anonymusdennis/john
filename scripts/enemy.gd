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
## Route acquisition is prioritized, all multiplayer-aware (the enemy hunts
## the nearest member of the "nav_target" group — any player or companion):
##   1. direct steering when the target is roughly level and visible
##   2. async NavGraph query to the target's CURRENT ground position (solved
##      on the graph's worker thread — requesting a path never freezes a
##      frame); while a query is pending the enemy keeps closing in
##   3. local reactive probes (step-up hop, jump lip, climb lip) when stuck
##   4. LAST RESORT: the target's own NavPathRecorder trail — only after the
##      graph has repeatedly confirmed it cannot reach, and only when every
##      trail segment validates against THIS body's abilities AND the
##      validated line actually ends near the target (never a blind replay
##      of the player's footsteps).
## When nothing works or the target is out of reach, the enemy returns to
## its home position and roams there instead of pacing a wall.
##
## Wall walking (spiders & friends): the body's up axis follows the surface
## normal, gravity pulls into the wall, feet plant via the animator's
## basis-relative rays, and corners are wrapped with probe rays. Strong hits
## override grip and throw the walker off the wall.

enum State { CHASE, PATH, JUMPING, CLIMBING, LAUNCHED, RECOVER, RETURN_HOME, ROAM }
## What the active/pending path is FOR — home/roam paths must not be
## retargeted at the player, and chase paths must not lead home.
enum PathPurpose { CHASE, HOME, ROAM }

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

@export_group("Territory")
@export var home_position: Vector3 = Vector3.ZERO
@export var roam_radius: float = 10.0
@export var return_distance: float = 30.0       ## ~10 nav cells; player farther => go home.
@export var abandon_trail_height: float = 2.5   ## Player left stairs vertically.
@export var abandon_trail_flat: float = 5.0     ## Player left trail horizontally (m).
@export var max_home_return_attempts: int = 5
@export var roam_goal_interval: float = 4.0
@export var use_trail_following: bool = true

@export_group("Air / Knockback")
@export var air_control: float = 14.0
@export var air_control_jump: float = 18.0
@export var launched_friction: float = 11.0
@export var launched_max_time: float = 2.5

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
var _path_purpose: int = PathPurpose.CHASE  ## What the current path is for.
var _path_pending: bool = false             ## An async graph query is in flight.
var _pending_purpose: int = PathPurpose.CHASE
var _pending_goal: Vector3 = Vector3.INF    ## Goal of the in-flight query.
var _path_gen: int = 0                      ## Request serial; stale results are dropped.
var _pending_timeout: float = 0.0

const PATH_REQUEST_TIMEOUT := 3.0           ## Give up waiting on a query after this.
## Fair pathfinding: a small per-physics-frame budget of query STARTS shared
## by the whole population. Combined with each enemy's randomized repath
## cooldown this gives everyone a turn instead of starving 7/8 of the herd
## (the old instance_id % 8 wave slot did exactly that).
const PATH_STARTS_PER_FRAME := 3
static var _starts_frame: int = -1
static var _starts_used: int = 0
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
var _graph_hooked: bool = false
var _last_pos: Vector3 = Vector3.ZERO
var _progress_timer: float = 0.0
var _route_check_cd: float = 0.0
var _reactive_cd: float = 0.0
var _cached_needs_path: bool = false
var _cached_blocked: bool = false
var _crowded: bool = false
var _crowded_cd: float = 0.0
var _home_return_attempts: int = 0
var _roam_goal: Vector3 = Vector3.ZERO
var _roam_timer: float = 0.0
var _launched_time: float = 0.0
var _jump_fail_streak: int = 0
var _graph_fail_streak: int = 0             ## Consecutive empty chase-path results.
var _graph_fail_time: float = 0.0           ## When the last empty result landed.


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 8          ## Layer "enemy" — does NOT collide with other enemies.
	collision_mask = 1 | 2       ## World + player only.
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
	_last_pos = global_position
	if home_position == Vector3.ZERO:
		home_position = global_position
	_roam_goal = home_position
	call_deferred("_hook_nav_graph")


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
	_route_check_cd = maxf(_route_check_cd - delta, 0.0)
	_reactive_cd = maxf(_reactive_cd - delta, 0.0)
	_crowded_cd = maxf(_crowded_cd - delta, 0.0)
	_grip_damage = maxf(_grip_damage - 1.2 * delta, 0.0)
	if _path_pending:
		_pending_timeout -= delta
		if _pending_timeout <= 0.0:
			_path_pending = false
			_path_gen += 1  # Invalidate the in-flight result so it can't land stale.
	_acquire_target(delta)
	if _graph == null:
		_graph = get_tree().get_first_node_in_group("nav_graph") as NavGraph
		_hook_nav_graph()

	if _update_lod():
		return

	if _update_crowded():
		_idle_move(delta)
		_finish_move(delta)
		return

	_update_territory_brain(delta)
	_roam_timer = maxf(_roam_timer - delta, 0.0)

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
		State.RETURN_HOME:
			_process_return_home(delta)
		State.ROAM:
			_process_roam(delta)


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


## Something (player or another body) is standing on this enemy — skip heavy
## AI/pathing so a dogpile does not hitch the main thread.
func _update_crowded() -> bool:
	if _crowded_cd > 0.0:
		return _crowded
	_crowded_cd = 0.08
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * (animator.plan.collider_height * 0.85)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 1.6)
	q.collision_mask = 2 | 8   ## Player + other enemies.
	q.exclude = [get_rid()]
	_crowded = not space.intersect_ray(q).is_empty()
	return _crowded


## Fair per-frame budget of query starts: first-come-first-served each
## physics frame; the randomized per-enemy repath cooldowns rotate who asks
## first, so nobody is permanently starved into trail-following.
func _may_pathfind() -> bool:
	if _graph == null:
		return false
	var f := Engine.get_physics_frames()
	if f != _starts_frame:
		_starts_frame = f
		_starts_used = 0
	return _starts_used < PATH_STARTS_PER_FRAME


# --- Territory / home --------------------------------------------------------

func _update_territory_brain(_delta: float) -> void:
	if _state in [State.LAUNCHED, State.JUMPING, State.CLIMBING, State.RECOVER]:
		return
	var homing := _state == State.RETURN_HOME or _state == State.ROAM \
			or (_state == State.PATH and _path_purpose != PathPurpose.CHASE)
	if _target == null:
		if not homing:
			_enter_roam()
		return

	var dist := global_position.distance_to(_target.global_position)
	if homing:
		# Hysteresis: re-engage only when clearly back inside reach, so the
		# enemy cannot oscillate between "go home" and "chase" every frame.
		if dist < minf(chase_range, return_distance) * 0.7:
			_clear_path()
			_state = State.CHASE
			_home_return_attempts = 0
			_graph_fail_streak = 0
		return

	if dist > return_distance:
		_enter_return_home()
		return

	if _path_from_trail and _should_abandon_trail():
		_on_route_failed()


## A route attempt definitively failed. Near the target that just means
## "drop it and re-chase"; far away it means "give up and go home". After
## too many failures in a row the enemy adopts its current spot as home.
func _on_route_failed() -> void:
	_clear_path()
	_home_return_attempts += 1
	if _home_return_attempts >= max_home_return_attempts:
		home_position = global_position
		_roam_goal = home_position
		_home_return_attempts = 0
		_enter_roam()
		return
	var near_target := _target != null \
			and global_position.distance_to(_target.global_position) < minf(chase_range, return_distance) * 0.7
	if near_target:
		_state = State.CHASE
	else:
		_enter_return_home()


func _enter_return_home() -> void:
	_clear_path()
	_state = State.RETURN_HOME


func _enter_roam() -> void:
	_clear_path()
	_state = State.ROAM
	_pick_roam_goal()
	_roam_timer = roam_goal_interval * randf_range(0.4, 1.0)


func _pick_roam_goal() -> void:
	var ang := randf() * TAU
	var r := randf_range(1.5, roam_radius)
	_roam_goal = home_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)


## Pre-adoption gate: the recorded trail only leads to the target while the
## target is still near its own trail tip.
func _trail_usable() -> bool:
	if not use_trail_following or _target == null:
		return false
	var rec := NavPathRecorder.find_for(_target)
	if rec == null or rec.size() < 2:
		return false
	return rec.latest().distance_to(_target.global_position) <= 6.0


## While replaying a trail: has the target left the route this path leads to?
## Checks the target against where the path is HEADED (its goal), not just
## the trail tip, and drops the trail the moment direct pursuit works again.
func _should_abandon_trail() -> bool:
	if not use_trail_following or _target == null:
		return true
	var rec := NavPathRecorder.find_for(_target)
	if rec == null or rec.size() < 2:
		return true
	var t := _target.global_position
	if rec.latest().distance_to(t) > 6.0:
		return true
	if _path_goal != Vector3.INF:
		if Vector2(_path_goal.x - t.x, _path_goal.z - t.z).length() > abandon_trail_flat:
			return true
		if absf(_path_goal.y - t.y) > abandon_trail_height:
			return true
	if _route_check_cd <= 0.0:
		_route_check_cd = 0.25
		if _direct_route_viable(t - global_position):
			return true
	return false


func _player_ground_hint() -> Vector3:
	if _target == null:
		return global_position
	var p := _target.global_position
	var space := get_world_3d().direct_space_state
	var from := p + Vector3.UP * 0.6
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0)
	q.collision_mask = SURFACE_MASK | 1
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	return Vector3(p.x, global_position.y, p.z)


func _get_chase_point() -> Vector3:
	if _target == null:
		return home_position
	if _target is CharacterBody3D and not (_target as CharacterBody3D).is_on_floor():
		var hint := _player_ground_hint()
		return Vector3(_target.global_position.x, hint.y, _target.global_position.z)
	return _target.global_position


func _get_face_dir() -> Vector3:
	if _target == null:
		return _desired_fwd
	return Vector3(
		_target.global_position.x - global_position.x,
		0.0,
		_target.global_position.z - global_position.z,
	)


func _air_steer_toward(target: Vector3, delta: float, strength: float) -> void:
	var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if flat.length_squared() < 0.01:
		return
	_face_toward(flat)
	var wish := flat.normalized() * move_speed
	var accel := strength * delta
	velocity.x = move_toward(velocity.x, wish.x, accel)
	velocity.z = move_toward(velocity.z, wish.z, accel)


func _slide_along_walls() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n: Vector3 = col.get_normal()
		if n.y > 0.6:
			continue
		velocity = velocity.slide(n)


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
	var moved := global_position.distance_to(_last_pos)
	if moved > 0.12:
		_progress_timer = 0.0
		_last_pos = global_position
	else:
		_progress_timer += delta
	_last_pos = global_position

	var flat_vel := velocity - _surface_normal * velocity.dot(_surface_normal)
	if remaining > 0.8 and flat_vel.length() < move_speed * 0.3:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(_stuck_timer - delta * 2.5, 0.0)
	if _progress_timer > 0.35:
		_stuck_timer = maxf(_stuck_timer, _progress_timer)


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
	_hop_cd = 0.35


func _hook_nav_graph() -> void:
	if _graph_hooked or _graph == null:
		return
	_graph_hooked = true
	if not _graph.is_ready():
		_graph.build_finished.connect(_on_nav_graph_ready, CONNECT_ONE_SHOT)
	else:
		call_deferred("_on_nav_graph_ready")


func _on_nav_graph_ready() -> void:
	# Stagger repaths so graph-ready does not flood the worker + main thread.
	_repath_timer = randf_range(0.5, 2.5)
	_stuck_timer = 0.0


func _has_direct_los(target_pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3.UP * animator.plan.collider_height * 0.82
	var aim := target_pos + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(eye, aim)
	q.collision_mask = SURFACE_MASK
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	return (hit["position"] as Vector3).distance_to(aim) < 1.4


func _is_blocked_ahead(dir: Vector3) -> bool:
	if dir.length_squared() < 0.001:
		return false
	var space := get_world_3d().direct_space_state
	var r := animator.plan.collider_radius
	# Probe just above step height: anything lower is hoppable by _try_step_up
	# and must not force a smart route.
	var shin_from := global_position + Vector3.UP * (max_step_height + 0.15)
	var q := PhysicsRayQueryParameters3D.create(shin_from, shin_from + dir.normalized() * (r + 0.7))
	q.collision_mask = SURFACE_MASK
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var n: Vector3 = hit["normal"]
	return n.y < 0.55


func _direct_route_viable(to_target: Vector3) -> bool:
	if to_target.y > max_step_height + 0.35:
		return false
	if to_target.y < -(max_drop + 0.5):
		return false
	var flat_dir := Vector3(to_target.x, 0.0, to_target.z)
	if flat_dir.length_squared() < 0.04:
		return absf(to_target.y) <= max_step_height + 0.35
	flat_dir = flat_dir.normalized()
	var allowed_drop := max_drop if to_target.y < -1.5 else maxf(max_step_height + 0.5, 1.2)
	if _void_ahead(flat_dir, allowed_drop):
		return false
	if _is_blocked_ahead(flat_dir):
		return false
	if _target != null and not _has_direct_los(_target.global_position):
		return false
	return true


func _refresh_route_cache(to_target: Vector3, flat_dir: Vector3) -> void:
	if _route_check_cd > 0.0:
		return
	_route_check_cd = 0.12
	_cached_needs_path = not _direct_route_viable(to_target)
	_cached_blocked = flat_dir.length_squared() > 0.001 and _is_blocked_ahead(flat_dir)


## Escalate to path/probe logic ONLY when direct pursuit genuinely cannot
## work: a rise above step height, a drop beyond safety, real lack of
## progress, or a cached "direct route not viable" verdict. Small height
## deltas stay in plain chase — flat-ground pursuit must never pathfind.
func _needs_smart_route(to_target: Vector3) -> bool:
	if to_target.y > max_step_height + 0.25:
		return true
	if to_target.y < -(max_drop + 0.5):
		return true
	if _stuck_timer > 0.8 or _progress_timer > 0.9:
		return true
	return _cached_needs_path


func _is_blocked_cached(dir: Vector3) -> bool:
	if dir.length_squared() < 0.001:
		return false
	return _cached_blocked


func _find_jump_lip(dir: Vector3) -> Vector3:
	if not _profile.can_jump:
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	var r := animator.plan.collider_radius
	var best := Vector3.INF
	var best_score := INF
	for deg in [-30.0, 0.0, 30.0]:
		var probe := dir.rotated(Vector3.UP, deg_to_rad(deg)).normalized()
		var over := global_position + probe * (r + 0.85) + Vector3.UP * (jump_apex + 0.45)
		var down_q := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * (jump_apex + 1.2))
		down_q.collision_mask = SURFACE_MASK
		var top := space.intersect_ray(down_q)
		if top.is_empty():
			continue
		var lip: Vector3 = top["position"]
		var rise := lip.y - global_position.y
		var flat := Vector2(lip.x - global_position.x, lip.z - global_position.z).length()
		if rise < 0.15 or rise > jump_apex + 0.35 or flat > jump_range + 0.5:
			continue
		var head_from := lip + Vector3.UP * 0.05
		var head_q := PhysicsRayQueryParameters3D.create(head_from, head_from + Vector3.UP * animator.plan.collider_height * 0.95)
		head_q.collision_mask = SURFACE_MASK
		if not space.intersect_ray(head_q).is_empty():
			continue
		var score := flat + absf(rise - clampf(_target.global_position.y - global_position.y, 0.0, jump_apex)) * 2.0 if _target else flat
		if score < best_score:
			best_score = score
			best = lip + Vector3.UP * 0.04
	return best


func _find_climb_lip(dir: Vector3) -> Vector3:
	if not _profile.can_parkour:
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	var r := animator.plan.collider_radius
	var shin_from := global_position + Vector3.UP * 0.35
	var q := PhysicsRayQueryParameters3D.create(shin_from, shin_from + dir.normalized() * (r + 0.95))
	q.collision_mask = SURFACE_MASK
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	var n: Vector3 = hit["normal"]
	if n.y > 0.45:
		return Vector3.INF
	var over := (hit["position"] as Vector3) + dir.normalized() * 0.35 + Vector3.UP * (_profile.climb_height + 0.4)
	var down_q := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * (_profile.climb_height + 0.6))
	down_q.collision_mask = SURFACE_MASK
	var top := space.intersect_ray(down_q)
	if top.is_empty():
		return Vector3.INF
	var lip: Vector3 = top["position"]
	var rise := lip.y - global_position.y
	if rise < max_step_height + 0.1 or rise > _profile.climb_height + 0.35:
		return Vector3.INF
	return lip


func _try_reactive_ascent(dir: Vector3) -> bool:
	if not is_on_floor() or _hop_cd > 0.0 or _reactive_cd > 0.0:
		return false
	if _stuck_timer < 0.25 and _progress_timer < 0.25:
		return false
	if dir.length_squared() < 0.001 and _target != null:
		dir = Vector3(_target.global_position.x - global_position.x, 0.0, _target.global_position.z - global_position.z)
	if dir.length_squared() < 0.001:
		return false
	dir = dir.normalized()

	var climb_lip := _find_climb_lip(dir)
	if climb_lip != Vector3.INF and _begin_climb(climb_lip):
		_reactive_cd = 0.35
		return true

	for side in [-1.0, 1.0]:
		var climb_side := _find_climb_lip(dir.rotated(Vector3.UP, deg_to_rad(35.0 * side)))
		if climb_side != Vector3.INF and _begin_climb(climb_side):
			_reactive_cd = 0.35
			return true

	var jump_lip := _find_jump_lip(dir)
	if jump_lip != Vector3.INF and _begin_jump(jump_lip):
		_reactive_cd = 0.35
		return true

	for side in [-1.0, 1.0]:
		var jump_side := _find_jump_lip(dir.rotated(Vector3.UP, deg_to_rad(40.0 * side)))
		if jump_side != Vector3.INF and _begin_jump(jump_side):
			_reactive_cd = 0.35
			return true

	if can_wall_walk and _target != null and _target.global_position.y > global_position.y + 1.2:
		if _try_attach_wall():
			_reactive_cd = 0.35
			return true

	return false


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

	var chase_pt := _get_chase_point()
	var to_target := chase_pt - global_position
	var dist := global_position.distance_to(_target.global_position)
	if dist > chase_range:
		_apply_neck_relief(delta)
		_idle_move(delta)
		_finish_move(delta)
		return

	var flat_dist := Vector2(_target.global_position.x - global_position.x, _target.global_position.z - global_position.z).length()
	if flat_dist <= attack_range and absf(_target.global_position.y - global_position.y) < 2.0 and not _on_wall_surface():
		if _attack_cd <= 0.0 and animator.trigger_attack():
			_attack_cd = attack_cooldown
		_face_toward(_get_face_dir())
		_idle_move(delta)
		_finish_move(delta)
		return

	if _on_wall_surface():
		_process_wall_chase(delta)
		return

	var flat_dir := _get_face_dir()
	if flat_dir.length_squared() > 0.01:
		flat_dir = flat_dir.normalized()

	_refresh_route_cache(to_target, flat_dir)

	if _graph != null and not _graph.is_ready():
		_face_toward(flat_dir)
		_steer_move(chase_pt, delta, 0.85)
		_finish_move(delta)
		return

	if _needs_smart_route(to_target):
		# PRIMARY: graph path to the target's current ground position.
		_try_request_path()
		# LAST RESORT: validated trail replay, only after the graph has
		# repeatedly confirmed it cannot reach (see _try_follow_trail).
		if _try_follow_trail():
			_finish_move(delta)
			return
		if _try_reactive_ascent(flat_dir):
			_finish_move(delta)
			return
		# Confirmed unreachable and beyond this body's vertical reach ->
		# stop pacing the wall, go home.
		if _graph_fail_streak >= 3 and to_target.y > _max_reach_up() + 0.5:
			_on_route_failed()
			_finish_move(delta)
			return
		# Keep closing in while the graph thinks (or between retries).
		_face_toward(flat_dir)
		if _is_blocked_cached(flat_dir):
			for side in [-1.0, 1.0]:
				var flank := flat_dir.rotated(Vector3.UP, deg_to_rad(55.0 * side))
				if not _is_blocked_ahead(flank):
					_steer_move(global_position + flank * 2.0, delta, 0.85)
					_finish_move(delta)
					return
			# Boxed in: keep the stuck clock running so probes still fire.
			_stuck_timer = minf(_stuck_timer + delta, 2.0)
			_idle_move(delta)
		elif is_on_floor() and flat_dir.length_squared() > 0.01 and _void_ahead(flat_dir, max_step_height + 0.5):
			_idle_move(delta)
		else:
			_steer_move(chase_pt, delta, 0.9)
		_finish_move(delta)
		return

	if can_wall_walk and _target.global_position.y > global_position.y + 1.2 and _try_attach_wall():
		_finish_move(delta)
		return

	if is_on_floor() and flat_dir.length_squared() > 0.01:
		var allowed_drop := max_drop if _target.global_position.y < global_position.y - 1.5 else maxf(max_step_height + 0.6, 1.2)
		if _void_ahead(flat_dir, allowed_drop):
			_try_request_path()
			if _try_reactive_ascent(flat_dir):
				_finish_move(delta)
				return
			_face_toward(flat_dir)
			_idle_move(delta)
			_finish_move(delta)
			return

	_steer_move(chase_pt, delta)
	_finish_move(delta)


func _process_return_home(delta: float) -> void:
	var to_home := home_position - global_position
	if Vector2(to_home.x, to_home.z).length() < 1.2 and absf(to_home.y) < 2.0:
		_enter_roam()
		_finish_move(delta)
		return
	# Prefer a real graph route home; steer directly while it is pending.
	_try_request_path()
	_face_toward(to_home)
	if _stuck_timer > 0.6 and _try_reactive_ascent(Vector3(to_home.x, 0.0, to_home.z)):
		_finish_move(delta)
		return
	_steer_move(home_position, delta, 0.9)
	_finish_move(delta)


func _process_roam(delta: float) -> void:
	if _roam_timer <= 0.0:
		_pick_roam_goal()
		_roam_timer = roam_goal_interval * randf_range(0.7, 1.3)
	var to_goal := _roam_goal - global_position
	if Vector2(to_goal.x, to_goal.z).length() < 1.0:
		_idle_move(delta)
	else:
		# Pathfind to far roam goals so obstacles are walked around, not into.
		if Vector2(to_goal.x, to_goal.z).length() > 3.0:
			_try_request_path()
		if _progress_timer > 1.0:
			# Blocked wander goal — just pick another one.
			_pick_roam_goal()
			_progress_timer = 0.0
			_stuck_timer = 0.0
		_face_toward(to_goal)
		_steer_move(_roam_goal, delta, 0.55)
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
	if _path.is_empty() or _path_i >= _path.size():
		_clear_path()
		_finish_move(delta)
		return
	if _path_purpose == PathPurpose.CHASE and _target == null:
		_clear_path()
		_finish_move(delta)
		return

	if _path_purpose == PathPurpose.CHASE:
		# Close enough for direct pursuit — but not if we still need a vertical route.
		var to_target := _target.global_position - global_position
		if Vector2(to_target.x, to_target.z).length() < 5.0 and absf(to_target.y) < 1.4:
			if not _needs_smart_route(to_target):
				_clear_path()
				_finish_move(delta)
				return

		if _path_from_trail:
			# Abandon stale trail paths when the player left the route.
			if _should_abandon_trail():
				_on_route_failed()
				_finish_move(delta)
				return
			# Keep asking the graph so a real route replaces the replay ASAP.
			_try_request_path()
		elif _repath_timer <= 0.0 and _path_goal.distance_to(_target.global_position) > 4.0:
			# Target drifted away from this path's goal -> repath on cadence
			# (async; the current path is followed until the new one lands).
			_try_request_path()

	var wp: Dictionary = _path[_path_i]
	var wp_pos: Vector3 = wp["pos"]
	var move: int = wp["move"]
	var to_wp := wp_pos - global_position

	if _stuck_timer > 0.75:
		_stuck_timer = 0.0
		_jump_fail_streak += 1
		if _jump_fail_streak >= 3:
			_on_route_failed()
			_finish_move(delta)
			return
		if _try_reactive_ascent(Vector3(to_wp.x, 0.0, to_wp.z)):
			_finish_move(delta)
			return
		_clear_path()
		_finish_move(delta)
		return

	# Home/roam paths walk a touch slower than a hot pursuit.
	var pace := 1.0 if _path_purpose == PathPurpose.CHASE else 0.8

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
				_on_route_failed()
				_finish_move(delta)
				return
			_air_steer_toward(wp_pos, delta, air_control)
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
			var spd := pace
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
	var steer_to := _jump_target
	if _target != null:
		steer_to = Vector3(_jump_target.x, _jump_target.y, _jump_target.z)
	_air_steer_toward(steer_to, delta, air_control_jump)
	velocity.y -= _gravity * delta
	move_and_slide()
	_slide_along_walls()
	_align_body(delta)
	animator.set_locomotion(velocity, false)
	animator.set_look_target(_target)
	if (is_on_floor() and _jump_time < 0.35) or _jump_time <= -2.0:
		var land_err := Vector2(global_position.x - _jump_target.x, global_position.z - _jump_target.z).length()
		if land_err > 2.5:
			_jump_fail_streak += 1
			_clear_path()
			if _jump_fail_streak >= 3:
				_on_route_failed()
			_state = State.CHASE
			animator.replant_feet()
			return
		_jump_fail_streak = 0
		animator.replant_feet()
		_state = State.PATH if not _path.is_empty() else _state_after_path()
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
	_jump_fail_streak = 0
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
		_state = State.PATH if not _path.is_empty() else _state_after_path()
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
	_launched_time += delta
	_surface_normal = Vector3.UP
	up_direction = Vector3.UP
	velocity.y -= _gravity * delta
	if is_on_floor():
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		var damp := clampf(launched_friction * delta, 0.0, 1.0)
		hv = hv * (1.0 - damp)
		velocity.x = hv.x
		velocity.z = hv.z
	move_and_slide()
	_align_body(delta)
	var grounded := is_on_floor()
	animator.set_locomotion(velocity, grounded)
	animator.set_look_target(_target)
	if grounded and (Vector3(velocity.x, 0.0, velocity.z).length() < 1.8 or _launched_time > launched_max_time):
		animator.replant_feet()
		velocity.x *= 0.35
		velocity.z *= 0.35
		_state = State.RECOVER
		_recover_timer = 0.45
		_ext_vel = Vector3.ZERO
		_launched_time = 0.0


func _process_recover(delta: float) -> void:
	_recover_timer -= delta
	if is_on_floor():
		animator.replant_feet()
	if _recover_timer <= 0.0:
		_state = State.CHASE
	_idle_move(delta)
	_finish_move(delta)


# --- Pathing -----------------------------------------------------------------

## Queues an async NavGraph query for the current purpose (chase goal = the
## target's ground position plus a small velocity lead; home/roam goals are
## fixed points). The worker thread solves it off-frame; _on_path_result
## adopts it when it lands. Returns true when a request was actually queued.
func _try_request_path() -> bool:
	if _graph == null or _path_pending or _crowded:
		return false
	var purpose := _current_purpose()
	if purpose == PathPurpose.CHASE and _target == null:
		return false
	if _repath_timer > 0.0 or not _graph.can_query():
		return false
	if not _may_pathfind():
		return false
	_repath_timer = 0.75 + randf() * 0.45
	_path_gen += 1
	var goal := global_position
	match purpose:
		PathPurpose.HOME:
			goal = home_position
		PathPurpose.ROAM:
			goal = _roam_goal
		_:
			goal = _get_chase_point()
			if _target is CharacterBody3D:
				var tv := (_target as CharacterBody3D).velocity
				goal += Vector3(tv.x, 0.0, tv.z) * 0.4
	if _graph.request_path(global_position, goal, _profile,
			_on_path_result.bind(_path_gen)):
		_starts_used += 1
		_path_pending = true
		_pending_purpose = purpose
		_pending_goal = goal
		_pending_timeout = PATH_REQUEST_TIMEOUT
		return true
	return false


func _current_purpose() -> int:
	if _state == State.RETURN_HOME:
		return PathPurpose.HOME
	if _state == State.ROAM:
		return PathPurpose.ROAM
	if _state == State.PATH:
		return _path_purpose
	return PathPurpose.CHASE


func _state_after_path() -> int:
	match _path_purpose:
		PathPurpose.HOME:
			return State.RETURN_HOME
		PathPurpose.ROAM:
			return State.ROAM
	return State.CHASE


## Main-thread delivery of a solved path. An empty CHASE result feeds the
## failure streak that eventually unlocks the trail fallback / going home —
## it does NOT trigger trail replay by itself.
func _on_path_result(path: Array, gen: int) -> void:
	if gen != _path_gen:
		return  # Superseded or timed-out request; a fresher one is in charge.
	_path_pending = false
	if _state == State.LAUNCHED or _state == State.RECOVER \
			or _state == State.JUMPING or _state == State.CLIMBING or _on_wall_surface():
		return
	if _pending_purpose != _current_purpose():
		return  # State changed while the worker was solving; result is moot.
	if path.is_empty():
		match _pending_purpose:
			PathPurpose.CHASE:
				var now := Time.get_ticks_msec() / 1000.0
				_graph_fail_streak = 1 if now - _graph_fail_time > 6.0 else _graph_fail_streak + 1
				_graph_fail_time = now
			PathPurpose.HOME:
				_on_route_failed()
			_:
				pass  # Roam just keeps steering; a new goal comes soon anyway.
		return
	if _pending_purpose == PathPurpose.CHASE:
		_graph_fail_streak = 0
		_home_return_attempts = 0
	_adopt_path(path, false, _pending_goal)


func _adopt_path(path: Array, from_trail: bool, goal: Vector3) -> void:
	_path = path
	_path_i = 0
	_path_from_trail = from_trail
	_path_purpose = _pending_purpose if not from_trail else PathPurpose.CHASE
	_path_goal = goal
	_state = State.PATH
	if _graph != null:
		var pts := PackedVector3Array()
		pts.append(global_position)
		for step in path:
			pts.append(step["pos"])
		_graph.set_debug_path(get_instance_id(), pts)


## LAST-RESORT routing: replay the target's own breadcrumb trail. Only used
## once the graph has repeatedly confirmed it cannot reach the target (a
## trail encodes player-only affordances — vaults, sprint arcs, grabbable
## ledges — so it is never trusted before the graph). Every segment is
## classified against THIS body's abilities and the validated line must
## still END near the target; a truncated or stale line is rejected instead
## of blindly adopted.
func _try_follow_trail() -> bool:
	if not use_trail_following or _target == null:
		return false
	if _graph != null:
		if not _graph.is_ready() or _path_pending:
			return false   # The graph has not had its say yet.
		if _graph_fail_streak < 2:
			return false   # Not confirmed unreachable — keep asking the graph.
	if not _trail_usable():
		return false
	var rec := NavPathRecorder.find_for(_target)
	if rec == null or rec.size() < 2:
		return false
	var join := rec.nearest_index(global_position, 8.0, _trail_join_dy())
	if join < 0:
		return false
	var t := _target.global_position
	# The entry segment (enemy -> join crumb) must be traversable too; back
	# up the trail a few crumbs to find one this body can actually reach.
	for back in 4:
		var j := join - back
		if j < 0:
			break
		var wps := _trail_to_waypoints(rec, j)
		if wps.is_empty():
			continue
		# Reject truncated lines that stop short of the target — a replay
		# that cannot arrive is worse than going home.
		var last: Vector3 = (wps[wps.size() - 1] as Dictionary)["pos"]
		if Vector2(last.x - t.x, last.z - t.z).length() > 4.0:
			continue
		if absf(last.y - t.y) > 2.5:
			continue
		_adopt_path(wps, true, rec.latest())
		return true
	return false


## How far above/below a trail crumb this body could join it, from abilities.
func _trail_join_dy() -> float:
	var dy := max_step_height + 1.5
	if _profile.can_jump:
		dy = maxf(dy, jump_apex + 1.0)
	if _profile.can_parkour:
		dy = maxf(dy, _profile.climb_height + 1.0)
	if can_wall_walk:
		dy = maxf(dy, 10.0)
	return dy


## Tallest rise this body can beat with any of its moves.
func _max_reach_up() -> float:
	var reach := max_step_height
	if _profile.can_jump:
		reach = maxf(reach, jump_apex)
	if _profile.can_parkour:
		reach = maxf(reach, _profile.climb_height)
	if can_wall_walk:
		reach = maxf(reach, 15.0)
	return reach


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
		_state = _state_after_path()
	_path_purpose = PathPurpose.CHASE
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
		_launched_time = 0.0
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
	if _target != null and _target.global_position.y - global_position.y > 1.4:
		return
	var request := animator.torso_turn_request
	if absf(request) > 0.02:
		_desired_fwd = _desired_fwd.rotated(_surface_normal, clampf(request, -1.0, 1.0) * turn_speed * 0.6 * delta)
