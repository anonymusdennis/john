extends Node3D
## Procedurally builds expanded parkour + physics playground content.

const WorldPickup = preload("res://scripts/world_pickup.gd")
const GrabbableLedge = preload("res://scripts/grabbable_ledge.gd")
const PhysicsObject = preload("res://scripts/physics_object.gd")
const EnemyScene = preload("res://scenes/enemy.tscn")
const NavGraphScene = preload("res://scripts/nav/nav_graph.gd")

@export var seed_value: int = 42
@export var enemy_count: int = 12


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_build_platforms()
	_build_tower()
	_spawn_grenade_pickups()
	_build_jenga(Vector3(18, 0, 8), rng)
	_build_cube_pile(Vector3(22, 0, -4), rng)
	_build_ball_pit(Vector3(-18, 0, 6), rng)
	_build_kegel_set(Vector3(-12, 0, -10))
	_build_ramps_and_decor()
	_spawn_enemies()
	_start_nav_graph()


## The smart navigation system: samples every static surface (layer 6) into
## a typed graph. Runs asynchronously; enemies fall back to direct chase
## until the build finishes.
func _start_nav_graph() -> void:
	var graph := NavGraphScene.new()
	graph.name = "NavGraph"
	add_child(graph)
	graph.configure(AABB(Vector3(-62, -8, -62), Vector3(124, 52, 124)))


func _mat(color: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _static_box(parent: Node, pos: Vector3, size: Vector3, mat: Material, grabbable: bool = false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	# Bit 32 (layer 6) marks static geometry that the NavGraph samples.
	body.collision_layer = (5 if grabbable else 1) | 32
	body.collision_mask = 0
	if grabbable:
		body.set_script(GrabbableLedge)
	var mesh_i := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_i.mesh = box
	mesh_i.material_override = mat
	body.add_child(mesh_i)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


func _rigid_box(parent: Node, pos: Vector3, size: Vector3, mat: Material, mass: float = 1.0, weight: float = -1.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(PhysicsObject)
	body.position = pos
	body.mass = mass
	body.set("weight", weight if weight > 0.0 else mass)
	body.collision_layer = 1
	body.collision_mask = 1 | 2
	var mesh_i := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_i.mesh = box
	mesh_i.material_override = mat
	body.add_child(mesh_i)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


func _rigid_sphere(parent: Node, pos: Vector3, radius: float, mat: Material, mass: float = 0.4, weight: float = -1.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(PhysicsObject)
	body.position = pos
	body.mass = mass
	body.set("weight", weight if weight > 0.0 else mass)
	body.collision_layer = 1
	body.collision_mask = 1 | 2
	var mesh_i := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh_i.mesh = sphere
	mesh_i.material_override = mat
	body.add_child(mesh_i)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


func _build_platforms() -> void:
	var platforms := Node3D.new()
	platforms.name = "Platforms"
	add_child(platforms)

	var gold := _mat(Color(0.85, 0.62, 0.25), 0.55, 0.15)
	var stone := _mat(Color(0.45, 0.42, 0.38))
	var teal := _mat(Color(0.25, 0.55, 0.58))
	var red := _mat(Color(0.65, 0.28, 0.28))

	# Low vault ledges near spawn
	_static_box(platforms, Vector3(-4, 0.6, -2), Vector3(4, 1.2, 4), gold, true)
	_static_box(platforms, Vector3(4, 1.1, -2), Vector3(4, 2.2, 4), gold, true)
	_static_box(platforms, Vector3(0, 1.6, -8), Vector3(5, 3.2, 5), gold, true)
	_static_box(platforms, Vector3(-10, 2.0, 2), Vector3(6, 4.0, 1.2), gold, true)

	# Stairs / bridge path going up
	for i in 8:
		var y := 0.45 + i * 0.85
		var z := 4.0 + i * 2.2
		_static_box(platforms, Vector3(10, y, z), Vector3(2.6, 0.9, 2.6), stone)

	# Floating trail climbing higher
	var trail := [
		Vector3(6, 4.5, 18), Vector3(2, 5.8, 22), Vector3(-3, 7.2, 24),
		Vector3(-8, 8.8, 22), Vector3(-12, 10.5, 18), Vector3(-10, 12.2, 12),
		Vector3(-5, 14.0, 8), Vector3(0, 15.8, 4), Vector3(5, 17.5, 0),
		Vector3(8, 19.5, -6), Vector3(4, 21.5, -12), Vector3(-2, 24.0, -14),
		Vector3(-8, 26.5, -10), Vector3(-6, 29.0, -4), Vector3(0, 32.0, 0),
	]
	for i in trail.size():
		var size := Vector3(3.2, 0.7, 3.2) if i % 3 != 0 else Vector3(4.5, 0.8, 3.0)
		var mat := gold if i % 2 == 0 else teal
		_static_box(platforms, trail[i], size, mat, i % 2 == 0)

	# High balcony
	_static_box(platforms, Vector3(0, 32.5, 0), Vector3(10, 1.0, 10), red)
	_static_box(platforms, Vector3(0, 34.0, -6), Vector3(3, 2.0, 3), gold, true)

	# Side parkour islands
	for i in 6:
		var ang := i * TAU / 6.0
		var pos := Vector3(cos(ang) * 28.0, 3.0 + i * 1.5, sin(ang) * 28.0)
		_static_box(platforms, pos, Vector3(4, 1, 4), teal if i % 2 else stone, true)

	# Long sky bridge
	_static_box(platforms, Vector3(20, 8, -15), Vector3(24, 0.8, 2.5), stone)
	_static_box(platforms, Vector3(32, 9.5, -15), Vector3(4, 3, 4), gold, true)
	_static_box(platforms, Vector3(8, 9.5, -15), Vector3(4, 3, 4), gold, true)


func _build_tower() -> void:
	var tower := Node3D.new()
	tower.name = "ClimbTower"
	add_child(tower)
	var mat := _mat(Color(0.5, 0.35, 0.3))
	var gold := _mat(Color(0.85, 0.62, 0.25), 0.55, 0.15)
	# Stepped spiral tower
	for i in 16:
		var ang := i * 0.7
		var y := 1.0 + i * 1.35
		var r := 6.0
		var pos := Vector3(25 + cos(ang) * r, y, 20 + sin(ang) * r)
		_static_box(tower, pos, Vector3(3.2, 0.7, 2.4), gold if i % 2 == 0 else mat, true)
	_static_box(tower, Vector3(25, 23, 20), Vector3(8, 1, 8), mat)


func _spawn_grenade_pickups() -> void:
	var root := Node3D.new()
	root.name = "Pickups"
	add_child(root)
	var spots := [
		Vector3(2, 1.2, 4),
		Vector3(-6, 1.2, -4),
		Vector3(12, 2.0, 6),
		Vector3(0, 17.0, 4),
		Vector3(25, 24.2, 20),
		Vector3(-18, 1.2, 2),
		Vector3(20, 9.2, -15),
	]
	for p in spots:
		var pickup := Area3D.new()
		pickup.set_script(WorldPickup)
		pickup.position = p
		pickup.item_id = ItemDef.GRENADE
		pickup.respawn_seconds = 4.0
		root.add_child(pickup)


func _build_jenga(origin: Vector3, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "Jenga"
	root.position = origin
	add_child(root)
	# Plinth
	_static_box(root, Vector3(0, 0.25, 0), Vector3(3.2, 0.5, 3.2), _mat(Color(0.3, 0.3, 0.28)))
	var wood := _mat(Color(0.72, 0.5, 0.28), 0.7)
	var brick := Vector3(0.75, 0.2, 0.25)
	var layers := 14
	for layer in layers:
		var y := 0.6 + layer * (brick.y + 0.01)
		var alternate := layer % 2 == 0
		for i in 3:
			var pos: Vector3
			if alternate:
				pos = Vector3((i - 1) * 0.78, y, 0)
			else:
				pos = Vector3(0, y, (i - 1) * 0.78)
			var body := _rigid_box(root, pos, brick if alternate else Vector3(brick.z, brick.y, brick.x), wood, 0.35, 0.45)
			body.rotation.y = rng.randf_range(-0.02, 0.02)


func _build_cube_pile(origin: Vector3, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "CubePile"
	root.position = origin
	add_child(root)
	_static_box(root, Vector3(0, 0.2, 0), Vector3(5, 0.4, 5), _mat(Color(0.35, 0.35, 0.4)))
	for i in 40:
		var s := rng.randf_range(0.25, 0.7)
		var color := Color(rng.randf(), rng.randf(), rng.randf())
		var pos := Vector3(rng.randf_range(-1.8, 1.8), 1.0 + i * 0.15, rng.randf_range(-1.8, 1.8))
		var vol := s * s * s
		_rigid_box(root, pos, Vector3(s, s, s), _mat(color, 0.5), vol, vol * 1.2)


func _build_ball_pit(origin: Vector3, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "BallPit"
	root.position = origin
	add_child(root)
	var wall_mat := _mat(Color(0.2, 0.45, 0.7))
	# Floor + walls (open-top box)
	_static_box(root, Vector3(0, 0.15, 0), Vector3(8, 0.3, 8), wall_mat)
	_static_box(root, Vector3(0, 1.2, -3.85), Vector3(8, 2.2, 0.3), wall_mat)
	_static_box(root, Vector3(0, 1.2, 3.85), Vector3(8, 2.2, 0.3), wall_mat)
	_static_box(root, Vector3(-3.85, 1.2, 0), Vector3(0.3, 2.2, 8), wall_mat)
	_static_box(root, Vector3(3.85, 1.2, 0), Vector3(0.3, 2.2, 8), wall_mat)
	for i in 90:
		var r := rng.randf_range(0.18, 0.32)
		var color := Color.from_hsv(rng.randf(), 0.75, 0.95)
		var pos := Vector3(rng.randf_range(-3.2, 3.2), 1.5 + i * 0.08, rng.randf_range(-3.2, 3.2))
		_rigid_sphere(root, pos, r, _mat(color, 0.35), 0.25, 0.35)


func _build_kegel_set(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "KegelSet"
	root.position = origin
	add_child(root)
	_static_box(root, Vector3(0, 0.1, 0), Vector3(10, 0.2, 16), _mat(Color(0.55, 0.5, 0.42)))

	# Bowling lane markers
	var lane := _mat(Color(0.7, 0.62, 0.45))
	_static_box(root, Vector3(0, 0.22, -2), Vector3(1.4, 0.05, 12), lane)

	# Pins (kegels) in triangle
	var pin_mat := _mat(Color(0.95, 0.95, 0.92), 0.4)
	var stripe := _mat(Color(0.85, 0.15, 0.15), 0.4)
	var rows := [1, 2, 3, 4]
	var pin_i := 0
	var z0 := 4.5
	for row_i in rows.size():
		var count: int = rows[row_i]
		var z := z0 + row_i * 0.55
		for c in count:
			var x := (c - (count - 1) * 0.5) * 0.5
			_make_pin(root, Vector3(x, 0.55, z), pin_mat, stripe)
			pin_i += 1

	# Bowling ball
	var ball_mat := _mat(Color(0.12, 0.12, 0.14), 0.25, 0.2)
	_rigid_sphere(root, Vector3(0, 0.55, -6), 0.42, ball_mat, 3.5, 5.0)


func _make_pin(parent: Node, pos: Vector3, body_mat: Material, stripe_mat: Material) -> void:
	var body := RigidBody3D.new()
	body.set_script(PhysicsObject)
	body.position = pos
	body.mass = 0.7
	body.set("weight", 0.85)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3(0, -0.25, 0)
	body.collision_layer = 1
	body.collision_mask = 1 | 2

	var mesh_i := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.16
	cyl.height = 0.7
	mesh_i.mesh = cyl
	mesh_i.material_override = body_mat
	body.add_child(mesh_i)

	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.125
	band_mesh.bottom_radius = 0.125
	band_mesh.height = 0.08
	band.mesh = band_mesh
	band.position.y = 0.12
	band.material_override = stripe_mat
	body.add_child(band)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.14
	shape.height = 0.7
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)


func _build_ramps_and_decor() -> void:
	var root := Node3D.new()
	root.name = "Decor"
	add_child(root)
	var mat := _mat(Color(0.4, 0.45, 0.35))

	# Ramp toward ball pit
	var ramp := StaticBody3D.new()
	ramp.position = Vector3(-12, 0.8, 6)
	ramp.rotation_degrees = Vector3(0, 0, -18)
	ramp.collision_layer = 1 | 32
	var mesh_i := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8, 0.4, 4)
	mesh_i.mesh = box
	mesh_i.material_override = mat
	ramp.add_child(mesh_i)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	ramp.add_child(col)
	root.add_child(ramp)

	# Pillars
	for i in 5:
		_static_box(root, Vector3(-25 + i * 3.5, 3, -25), Vector3(1.2, 6, 1.2), _mat(Color(0.35, 0.32, 0.3)))

	# Seesaw plank (rigid on hinges via just resting — free plank)
	_rigid_box(root, Vector3(15, 1.2, 15), Vector3(6, 0.2, 1.2), _mat(Color(0.55, 0.4, 0.25)), 2.0, 3.5)
	_static_box(root, Vector3(15, 0.5, 15), Vector3(0.8, 1.0, 0.8), mat)


func _spawn_enemies() -> void:
	var root := Node3D.new()
	root.name = "Enemies"
	add_child(root)
	var forms := ["human", "imp", "centaur", "spider", "centipede"]
	var spawns: Array[Dictionary] = [
		# Near player start — you should see these right away.
		{"form": "human", "pos": Vector3(5, 0.1, 8)},
		{"form": "imp", "pos": Vector3(-4, 0.1, 11)},
		{"form": "spider", "pos": Vector3(2, 0.1, 14)},
		# Around the playground.
		{"form": "centaur", "pos": Vector3(8, 0.1, -6)},
		{"form": "imp", "pos": Vector3(-8, 0.1, -18)},
		{"form": "centaur", "pos": Vector3(14, 0.1, 4)},
		{"form": "spider", "pos": Vector3(-6, 0.1, 14)},
		{"form": "centipede", "pos": Vector3(0, 0.1, -16)},
		{"form": "human", "pos": Vector3(18, 0.1, 8)},
		{"form": "centipede", "pos": Vector3(-18, 0.1, 6)},
		{"form": "imp", "pos": Vector3(22, 0.1, -4)},
		{"form": "spider", "pos": Vector3(-12, 0.1, -10)},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 9001
	while spawns.size() < enemy_count:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(14.0, 38.0)
		spawns.append({
			"form": forms[rng.randi_range(0, forms.size() - 1)],
			"pos": Vector3(cos(ang) * r, 0.1, sin(ang) * r),
		})
	for s in spawns.slice(0, enemy_count):
		var enemy := EnemyScene.instantiate()
		enemy.body_form = s["form"]
		root.add_child(enemy)
		enemy.global_position = s["pos"]
