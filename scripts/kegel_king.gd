extends RigidBody3D
## The Kegel King: a golden royal pin. Topple it and it showers the arena
## with grenade pickups (once per reign — long live the king).

const WorldPickup = preload("res://scripts/world_pickup.gd")

@export var reward_count: int = 6

var _toppled: bool = false


func _physics_process(_delta: float) -> void:
	if _toppled:
		return
	if global_transform.basis.y.dot(Vector3.UP) < 0.45:
		_toppled = true
		_shower_rewards()


func _shower_rewards() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in reward_count:
		var ang := float(i) / float(reward_count) * TAU
		var pickup := Area3D.new()
		pickup.set_script(WorldPickup)
		pickup.item_id = ItemDef.GRENADE
		pickup.respawn_seconds = 9999.0
		parent.add_child(pickup)
		pickup.global_position = global_position + Vector3(cos(ang) * 1.6, 0.8 + float(i) * 0.05, sin(ang) * 1.6)
