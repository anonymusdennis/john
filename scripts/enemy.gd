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

@onready var animator: ProcAnimator = $Animator
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _attack_cd: float = 0.0
var _player: Node3D


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 1
	collision_mask = 1 | 2
	if animator.plan == null or animator.body_form != body_form:
		animator.build(StringName(body_form))
	_fit_collider()


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

	# Gravity keeps enemies on the ground instead of floating in the sky.
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var flat_vel := Vector3.ZERO
	if _player != null:
		flat_vel = _think(delta)

	velocity.x = flat_vel.x
	velocity.z = flat_vel.z
	move_and_slide()

	animator.set_locomotion(velocity, is_on_floor())
	animator.set_look_target(_player)


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
