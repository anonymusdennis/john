extends Area3D
## World collectible potato grenade. Adds to inventory and respawns after a delay.

@export var item_id: StringName = &"grenade"
@export var amount: int = 1
@export var respawn_seconds: float = 4.0
@export var bob_height: float = 0.2
@export var bob_speed: float = 2.5
@export var spin_speed: float = 1.6

var _visual: Node3D
var _collision: CollisionShape3D
var _available: bool = true
var _base_y: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # player
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	_ensure_visual()
	_base_y = position.y


func _ensure_visual() -> void:
	if _visual == null:
		_visual = PotatoModel.instantiate_visual()
		_visual.name = "Visual"
		add_child(_visual)

	_collision = get_node_or_null("Collision") as CollisionShape3D
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "Collision"
		var shape := SphereShape3D.new()
		shape.radius = PotatoModel.collision_radius()
		_collision.shape = shape
		add_child(_collision)


func _process(delta: float) -> void:
	if not _available:
		return
	_t += delta
	position.y = _base_y + sin(_t * bob_speed) * bob_height
	rotate_y(spin_speed * delta)


func _on_body_entered(body: Node3D) -> void:
	if not _available:
		return
	if not body.is_in_group("player"):
		return
	Inventory.add_item(item_id, amount)
	_collect()


func _collect() -> void:
	_available = false
	visible = false
	set_deferred("monitoring", false)
	await get_tree().create_timer(respawn_seconds).timeout
	_respawn()


func _respawn() -> void:
	_available = true
	visible = true
	position.y = _base_y
	monitoring = true
