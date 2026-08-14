extends CharacterBody3D
## First/third-person 3D platformer controller with sprint, crouch, coyote jump,
## jump buffering, and automatic vaulting onto grabbable ledges while ascending.

enum CameraMode { FIRST_PERSON, THIRD_PERSON }

const GROUP_GRABBABLE := &"grabbable"

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var crouch_speed: float = 2.5
@export var acceleration: float = 40.0
@export var air_acceleration: float = 18.0
@export var friction: float = 28.0
@export var air_friction: float = 4.0

@export_group("Jump")
@export var jump_velocity: float = 7.2
@export var gravity_multiplier: float = 1.35
@export var fall_multiplier: float = 1.75
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12

@export_group("Crouch")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.0
@export var crouch_transition_speed: float = 12.0

@export_group("Camera")
@export var camera_mode: CameraMode = CameraMode.FIRST_PERSON
@export var mouse_sensitivity: float = 0.0025
@export var gamepad_look_sensitivity: float = 2.5
@export var min_pitch: float = -1.5707963
@export var max_pitch: float = 1.5707963
@export var camera_distance: float = 5.5
@export var first_person_eye_ratio: float = 0.88
@export var third_person_pivot_ratio: float = 0.78

@export_group("Physics Push")
@export var push_strength: float = 14.0
@export var push_min_player_speed: float = 0.15

@export_group("Vault")
@export var vault_enabled: bool = true
@export var vault_forward_reach: float = 0.85
@export var vault_min_ledge_height: float = 0.45
@export var vault_max_ledge_height: float = 1.35
@export var vault_overhang: float = 0.55
@export var vault_duration: float = 0.28
@export var vault_cooldown: float = 0.35
@export var vault_upward_min_speed: float = 0.15

@onready var pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var vault_wall_ray: RayCast3D = $VaultSensors/WallRay
@onready var vault_ledge_ray: RayCast3D = $VaultSensors/LedgeRay
@onready var vault_clearance_ray: RayCast3D = $VaultSensors/ClearanceRay

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var _is_crouching: bool = false
var _capsule: CapsuleShape3D

var _is_vaulting: bool = false
var _vault_cooldown_timer: float = 0.0
var _vault_tween: Tween


const GrenadeProjectile = preload("res://scripts/grenade_projectile.gd")
const PhysicsObject = preload("res://scripts/physics_object.gd")

var _throw_cooldown: float = 0.0


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_capsule = collision_shape.shape as CapsuleShape3D
	_configure_vault_rays()
	_apply_camera_mode()


func _unhandled_input(event: InputEvent) -> void:
	if Inventory.is_open:
		return

	if event.is_action_pressed("toggle_camera_view"):
		_toggle_camera_mode()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_mouse_capture"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event.is_action_pressed("use_item"):
		_try_use_selected_item()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		_look(event.relative.x * mouse_sensitivity, event.relative.y * mouse_sensitivity)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_vault_cooldown_timer = maxf(_vault_cooldown_timer - delta, 0.0)
	_throw_cooldown = maxf(_throw_cooldown - delta, 0.0)

	if _is_vaulting:
		return

	if not Inventory.is_open:
		_apply_gamepad_look(delta)
	_update_floor_timers(delta)
	_update_crouch(delta)
	_apply_gravity(delta)
	_handle_jump()
	_handle_move(delta)

	move_and_slide()
	_push_physics_objects(delta)

	if vault_enabled:
		_try_auto_vault()

	_was_on_floor = is_on_floor()


func _try_use_selected_item() -> void:
	if _throw_cooldown > 0.0:
		return
	var stack := Inventory.get_selected_stack()
	if Inventory.is_slot_empty(stack):
		return
	var id: StringName = stack["id"]
	if not ItemDef.is_usable(id):
		return
	if id == ItemDef.GRENADE:
		if not Inventory.consume_selected(1):
			return
		_throw_grenade()
		_throw_cooldown = 0.35


func _throw_grenade() -> void:
	var grenade := RigidBody3D.new()
	grenade.set_script(GrenadeProjectile)
	var origin := global_position + Vector3.UP * 1.35 - global_transform.basis.z * 0.6
	var aim := -camera.global_transform.basis.z
	get_tree().current_scene.add_child(grenade)
	grenade.global_position = origin
	var force := ItemDef.throw_force(ItemDef.GRENADE)
	grenade.linear_velocity = velocity * 0.35 + aim * force + Vector3.UP * 2.5
	grenade.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))


func _toggle_camera_mode() -> void:
	camera_mode = CameraMode.THIRD_PERSON if camera_mode == CameraMode.FIRST_PERSON else CameraMode.FIRST_PERSON
	_apply_camera_mode()


func _push_physics_objects(delta: float) -> void:
	var player_horiz := Vector3(velocity.x, 0.0, velocity.z)
	var player_speed := player_horiz.length()
	if player_speed < push_min_player_speed:
		return

	var push_dir := player_horiz / player_speed
	var max_push_speed := player_speed * 0.5

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider is RigidBody3D:
			_apply_push_to_body(collider as RigidBody3D, collision, push_dir, max_push_speed, delta)


func _apply_push_to_body(
	body: RigidBody3D,
	collision: KinematicCollision3D,
	push_dir: Vector3,
	max_push_speed: float,
	delta: float,
) -> void:
	var normal := collision.get_normal()
	if push_dir.dot(normal) >= 0.0:
		return

	var weight: float = PhysicsObject.get_weight(body)
	var body_horiz := Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
	var target := push_dir * max_push_speed
	var responsiveness: float = push_strength / weight
	var new_horiz := body_horiz.move_toward(target, responsiveness * delta)

	if new_horiz.length() > max_push_speed:
		new_horiz = new_horiz.normalized() * max_push_speed

	body.linear_velocity.x = new_horiz.x
	body.linear_velocity.z = new_horiz.z


func _apply_camera_mode() -> void:
	var first_person := camera_mode == CameraMode.FIRST_PERSON
	spring_arm.spring_length = 0.0 if first_person else camera_distance
	spring_arm.collision_mask = 0 if first_person else 1
	mesh.visible = not first_person
	_update_camera_pivot_height()


func _update_camera_pivot_height() -> void:
	var ratio := first_person_eye_ratio if camera_mode == CameraMode.FIRST_PERSON else third_person_pivot_ratio
	pivot.position.y = _capsule.height * ratio


func _look(yaw: float, pitch: float) -> void:
	rotate_y(-yaw)
	pivot.rotation.x = clampf(pivot.rotation.x - pitch, min_pitch, max_pitch)


func _apply_gamepad_look(delta: float) -> void:
	var look := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	# Prefer dedicated look axes if present; otherwise skip keyboard ui_* spam.
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) < 0.2 and absf(ry) < 0.2:
		return
	_look(rx * gamepad_look_sensitivity * delta, ry * gamepad_look_sensitivity * delta)


func _update_floor_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var mult := gravity_multiplier
	if velocity.y < 0.0:
		mult *= fall_multiplier
	elif not Input.is_action_pressed("jump"):
		# Short hop when jump is released early.
		mult *= 1.9
	velocity.y -= g * mult * delta


func _handle_jump() -> void:
	if _jump_buffer_timer <= 0.0:
		return
	if _coyote_timer <= 0.0:
		return
	if _is_crouching and not _can_stand():
		return

	velocity.y = jump_velocity
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0


func _handle_move(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var target_speed := walk_speed
	if _is_crouching:
		target_speed = crouch_speed
	elif Input.is_action_pressed("sprint") and is_on_floor():
		target_speed = sprint_speed

	var target_vel := wish * target_speed
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var accel := acceleration if is_on_floor() else air_acceleration
	var fric := friction if is_on_floor() else air_friction

	if wish.length_squared() > 0.0:
		horiz = horiz.move_toward(target_vel, accel * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, fric * delta)

	velocity.x = horiz.x
	velocity.z = horiz.z


func _update_crouch(delta: float) -> void:
	var want_crouch := Input.is_action_pressed("crouch")
	if not want_crouch and _is_crouching and not _can_stand():
		want_crouch = true

	_is_crouching = want_crouch
	var target_h := crouch_height if _is_crouching else stand_height
	_capsule.height = move_toward(_capsule.height, target_h, crouch_transition_speed * delta)
	collision_shape.position.y = _capsule.height * 0.5

	# Keep visual capsule roughly matching collider.
	if mesh.mesh is CapsuleMesh:
		var visual := mesh.mesh as CapsuleMesh
		visual.height = _capsule.height
		visual.radius = _capsule.radius
		mesh.position.y = _capsule.height * 0.5

	_update_camera_pivot_height()


func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * (crouch_height + 0.05)
	var to := global_position + Vector3.UP * (stand_height + 0.05)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1 # world
	return space.intersect_ray(query).is_empty()


func _configure_vault_rays() -> void:
	vault_wall_ray.enabled = true
	vault_ledge_ray.enabled = true
	vault_clearance_ray.enabled = true
	vault_wall_ray.collision_mask = 1 | 4 # world + grabbable
	vault_ledge_ray.collision_mask = 1 | 4
	vault_clearance_ray.collision_mask = 1 | 4
	vault_wall_ray.target_position = Vector3(0.0, 0.0, -vault_forward_reach)
	vault_ledge_ray.target_position = Vector3(0.0, -vault_max_ledge_height - 0.4, 0.0)
	vault_clearance_ray.target_position = Vector3(0.0, stand_height + 0.2, 0.0)


func _try_auto_vault() -> void:
	if _vault_cooldown_timer > 0.0:
		return
	# Only vault while ascending (jumping / moving up), never while falling.
	if velocity.y <= vault_upward_min_speed:
		return
	if is_on_floor():
		return

	var edge := _detect_grabbable_edge()
	if edge == Vector3.INF:
		return

	_start_vault(edge)


func _detect_grabbable_edge() -> Vector3:
	# Wall probe at mid-torso while airborne.
	vault_wall_ray.position = Vector3(0.0, crouch_height * 0.85, 0.0)
	vault_wall_ray.force_raycast_update()
	if not vault_wall_ray.is_colliding():
		return Vector3.INF

	var wall_point := vault_wall_ray.get_collision_point()
	var wall_normal := vault_wall_ray.get_collision_normal()
	var collider := vault_wall_ray.get_collider()

	# Prefer explicitly tagged grabbable geometry; still allow generic world edges
	# that form a ledge (auto ledge detection).
	var is_tagged: bool = false
	if collider != null:
		is_tagged = collider.is_in_group(GROUP_GRABBABLE)
		if not is_tagged and collider.get_parent() != null:
			is_tagged = collider.get_parent().is_in_group(GROUP_GRABBABLE)

	# Place ledge ray just past the wall face, high enough to drop onto the top.
	var over_point := wall_point - wall_normal * vault_overhang + Vector3.UP * (vault_max_ledge_height + 0.15)
	vault_ledge_ray.global_position = over_point
	vault_ledge_ray.force_raycast_update()
	if not vault_ledge_ray.is_colliding():
		return Vector3.INF

	var ledge_point := vault_ledge_ray.get_collision_point()
	var ledge_normal := vault_ledge_ray.get_collision_normal()
	if ledge_normal.dot(Vector3.UP) < 0.7:
		return Vector3.INF

	var height_delta := ledge_point.y - global_position.y
	if height_delta < vault_min_ledge_height or height_delta > vault_max_ledge_height:
		return Vector3.INF

	# Landing clearance: enough headroom above the ledge.
	vault_clearance_ray.global_position = ledge_point + Vector3.UP * 0.05
	vault_clearance_ray.force_raycast_update()
	if vault_clearance_ray.is_colliding():
		return Vector3.INF

	# If not tagged, still accept when the wall face is vertical enough (ledge).
	if not is_tagged and absf(wall_normal.y) > 0.35:
		return Vector3.INF

	# Landing target: on top of ledge, slightly inward from the lip.
	return ledge_point - wall_normal * 0.35 + Vector3.UP * 0.02


func _start_vault(target: Vector3) -> void:
	_is_vaulting = true
	_vault_cooldown_timer = vault_cooldown
	velocity = Vector3.ZERO

	if _vault_tween and _vault_tween.is_running():
		_vault_tween.kill()

	var start := global_position
	var mid := Vector3(
		lerpf(start.x, target.x, 0.45),
		maxf(start.y, target.y) + 0.35,
		lerpf(start.z, target.z, 0.45)
	)

	_vault_tween = create_tween()
	_vault_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_vault_tween.tween_method(_vault_step.bind(start, mid, target), 0.0, 1.0, vault_duration)
	_vault_tween.finished.connect(_finish_vault)


func _vault_step(t: float, start: Vector3, mid: Vector3, target: Vector3) -> void:
	# Quadratic Bezier arc over the lip.
	var a := start.lerp(mid, t)
	var b := mid.lerp(target, t)
	global_position = a.lerp(b, t)


func _finish_vault() -> void:
	_is_vaulting = false
	velocity = Vector3.ZERO
	_coyote_timer = coyote_time
