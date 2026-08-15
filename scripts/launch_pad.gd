extends Area3D
## Launch pad: flings anything that touches it along `launch_dir`.
## Enemies get the boost through their knockback API (grip check included —
## strong pads rip wall-walkers straight off surfaces), the player and loose
## physics props are boosted directly.

@export var launch_dir: Vector3 = Vector3.UP
@export var launch_speed: float = 14.0
@export var pad_color: Color = Color(1.0, 0.5, 0.1)

var _cooldowns := {}


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2   # World bodies (enemies, props) + player.
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	_build_visual()


func _build_visual() -> void:
	var mesh_i := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.3
	cyl.height = 0.3
	mesh_i.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = pad_color
	m.emission_enabled = true
	m.emission = pad_color
	m.emission_energy_multiplier = 1.4
	mesh_i.material_override = m
	add_child(mesh_i)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.2
	shape.height = 0.7
	col.shape = shape
	col.position.y = 0.2
	add_child(col)


func _physics_process(delta: float) -> void:
	for key in _cooldowns.keys():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			_cooldowns.erase(key)


func _on_body_entered(body: Node3D) -> void:
	var id := body.get_instance_id()
	if _cooldowns.has(id):
		return
	_cooldowns[id] = 0.6
	var dir := (global_transform.basis * launch_dir).normalized()
	if body.has_method("apply_knockback"):
		# Enemies: huge impulse guarantees a grip break + LAUNCHED tumble.
		body.apply_knockback(dir * launch_speed * body.get("_mass") * 0.25, body.global_position)
	elif body is CharacterBody3D:
		body.velocity = dir * launch_speed + Vector3.UP * 0.1
	elif body is RigidBody3D:
		body.linear_velocity = dir * launch_speed
