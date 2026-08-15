extends AnimatableBody3D
## Constantly rotating platform (windmill sails, carousels). Uses
## AnimatableBody3D + sync_to_physics so riders are carried properly.

@export var spin_axis: Vector3 = Vector3.UP
@export var degrees_per_second: float = 20.0


func _ready() -> void:
	sync_to_physics = true
	# Layer 1 only: moving surfaces must NOT be baked into the nav graph.
	collision_layer = 1
	collision_mask = 0


func _physics_process(delta: float) -> void:
	rotate(spin_axis.normalized(), deg_to_rad(degrees_per_second) * delta)
