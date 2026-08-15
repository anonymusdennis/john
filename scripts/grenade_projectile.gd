extends RigidBody3D
## Thrown potato grenade — short fuse, then impulse blast + flash.

@export var fuse_time: float = 1.35
@export var blast_radius: float = 6.0
@export var blast_force: float = 28.0
@export var blast_up: float = 8.0

var _fuse_left: float = 0.0
var _exploded: bool = false


func _ready() -> void:
	_fuse_left = fuse_time
	collision_layer = 1
	collision_mask = 1 | 2 | 8
	contact_monitor = true
	max_contacts_reported = 4
	_ensure_mesh()


func _ensure_mesh() -> void:
	if get_node_or_null("Visual") != null:
		return

	var visual := PotatoModel.instantiate_visual()
	visual.name = "Visual"
	add_child(visual)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = PotatoModel.collision_radius()
	col.shape = shape
	add_child(col)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_explode()


func _explode() -> void:
	_exploded = true
	var origin := global_position
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = blast_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = 1 | 2 | 8
	var hits := space.intersect_shape(params, 64)
	for hit in hits:
		var collider: Variant = hit.get("collider")
		if collider is RigidBody3D and collider != self:
			var rb := collider as RigidBody3D
			var to := rb.global_position - origin
			var dist := to.length()
			if dist < 0.001:
				to = Vector3.UP
				dist = 0.001
			var falloff := 1.0 - clampf(dist / blast_radius, 0.0, 1.0)
			var impulse := to.normalized() * blast_force * falloff + Vector3.UP * blast_up * falloff
			rb.apply_impulse(impulse)
		elif collider is CharacterBody3D:
			var cb := collider as CharacterBody3D
			var to := cb.global_position - origin
			var dist := maxf(to.length(), 0.001)
			var falloff := 1.0 - clampf(dist / blast_radius, 0.0, 1.0)
			if cb.is_in_group("enemy") and cb.has_method("apply_knockback"):
				# Enemies take real knockback through their impulse channel —
				# steering can no longer erase it, and strong blasts break grip.
				var impulse := to.normalized() * blast_force * 1.7 * falloff + Vector3.UP * blast_up * 1.3 * falloff
				var hit_pos: Vector3 = cb.global_position + (origin - cb.global_position) * 0.35
				cb.apply_knockback(impulse, hit_pos)
			else:
				cb.velocity += to.normalized() * blast_force * 0.45 * falloff + Vector3.UP * blast_up * 0.6 * falloff

	_spawn_flash(origin)
	queue_free()


func _spawn_flash(origin: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.2
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.2, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat
	var scene := get_tree().current_scene
	if scene == null:
		return
	scene.add_child(flash)
	flash.global_position = origin
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * (blast_radius * 0.55), 0.18)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(flash.queue_free)
