extends CharacterBody3D
## Chase enemy driven entirely by the procedural animation system.
## Pick any body form (human/imp/centaur/spider/centipede) — the same brain
## and animator handle all of them.

@export_enum("human", "imp", "centaur", "spider", "centipede") var body_form: String = "human"
@export var move_speed: float = 3.5
@export var turn_speed: float = 6.0
@export var chase_range: float = 40.0
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.2

@export_group("Physique")
## Kg-ish inertia; -1 = derive from the body plan's collider volume.
## Light imps fly across the yard, heavy centaurs barely stumble.
@export var body_mass_override: float = -1.0
## Impulse-per-mass (delta-v, m/s) this body shrugs off before feet grip breaks
## and it is thrown into a ballistic LAUNCHED tumble.
@export var grip_strength: float = 3.5

@onready var animator: ProcAnimator = $Animator
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

enum State { NORMAL, LAUNCHED, RECOVER }

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _attack_cd: float = 0.0
var _player: Node3D
var _state: int = State.NORMAL
var _recover_timer: float = 0.0
var _ext_vel: Vector3 = Vector3.ZERO        ## Decaying external impulse channel.
var _mass: float = 20.0


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 1
	collision_mask = 1 | 2
	if animator.plan == null or animator.body_form != body_form:
		animator.build(StringName(body_form))
	_fit_collider()
	_mass = body_mass_override if body_mass_override > 0.0 else _derived_mass()


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
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D

	if _state == State.LAUNCHED:
		_process_launched(delta)
		return
	if _state == State.RECOVER:
		_recover_timer -= delta
		if _recover_timer <= 0.0:
			_state = State.NORMAL

	# Gravity keeps enemies on the ground instead of floating in the sky.
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var flat_vel := Vector3.ZERO
	if _player != null and _state == State.NORMAL:
		flat_vel = _think(delta)

	# External impulses (grenades, punches) stack on top of steering and decay.
	_ext_vel = _ext_vel.move_toward(Vector3.ZERO, (10.0 if is_on_floor() else 1.5) * delta)
	velocity.x = flat_vel.x + _ext_vel.x
	velocity.z = flat_vel.z + _ext_vel.z
	move_and_slide()

	animator.set_locomotion(velocity, is_on_floor())
	animator.set_look_target(_player)


## Ballistic tumble after a big hit: no steering until the body lands.
func _process_launched(delta: float) -> void:
	velocity.y -= _gravity * delta
	move_and_slide()
	animator.set_locomotion(velocity, false)
	animator.set_look_target(_player)
	if is_on_floor() and Vector3(velocity.x, 0.0, velocity.z).length() < 6.0:
		velocity.x *= 0.4
		velocity.z *= 0.4
		_state = State.RECOVER
		_recover_timer = 0.55
		_ext_vel = Vector3.ZERO


## Public knockback API — impulse is in N·s; heavier bodies move less.
## The animator always reels at the hit point; if the delta-v beats this
## body's grip, every foot lets go and the enemy is launched ballistically.
func apply_knockback(impulse: Vector3, hit_pos: Vector3 = Vector3.INF) -> void:
	var dv := impulse * (4.0 / _mass)
	if hit_pos == Vector3.INF:
		hit_pos = global_position + Vector3.UP * animator.plan.collider_height * 0.5
	animator.apply_impact(hit_pos, dv)

	if dv.length() >= grip_strength:
		# Grip override: feet release, body detaches and tumbles.
		animator.release_all_feet()
		_state = State.LAUNCHED
		velocity += dv
		if velocity.y < dv.length() * 0.25:
			velocity.y = dv.length() * 0.35
	else:
		_ext_vel += Vector3(dv.x, 0.0, dv.z)
		velocity.y += dv.y


func _think(delta: float) -> Vector3:
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > chase_range:
		_apply_neck_relief(delta)
		return Vector3.ZERO

	var dir := to_player / maxf(dist, 0.001)
	if dist <= attack_range:
		if _attack_cd <= 0.0 and animator.trigger_attack():
			_attack_cd = attack_cooldown
		_face_toward(dir, delta)
		return Vector3.ZERO

	_face_toward(dir, delta)
	return dir * move_speed


## Smooth yaw toward a direction; stepping legs follow the rotating body.
func _face_toward(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


## The head asked for help: rotate the torso (legs step around) so the
## enemy can keep watching the player without breaking its neck.
func _apply_neck_relief(delta: float) -> void:
	var request := animator.torso_turn_request
	if absf(request) > 0.02:
		rotation.y += clampf(request, -1.0, 1.0) * turn_speed * 0.6 * delta
