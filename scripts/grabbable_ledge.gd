extends StaticBody3D
## Marks this collider (and optional child EdgeMarker meshes) as vault-grabbable.
## Add this script to any ledge StaticBody3D, or put the body in group "grabbable".


func _ready() -> void:
	add_to_group(&"grabbable")
	collision_layer |= 4 # grabbable layer bit
