class_name PhysicsObject
extends RigidBody3D
## Weighted physics prop — higher weight = more inertia when pushed by the player.


@export var weight: float = 1.0


func _ready() -> void:
	add_to_group(&"physics_object")
	if weight <= 0.0:
		weight = maxf(mass, 0.1)
	else:
		weight = maxf(weight, 0.1)


static func get_weight(body: RigidBody3D) -> float:
	if body is PhysicsObject:
		return (body as PhysicsObject).weight
	return maxf(body.mass, 0.1)
