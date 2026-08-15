extends Node3D
## Procedurally builds expanded parkour + physics playground content.

const WorldPickup = preload("res://scripts/world_pickup.gd")
const GrabbableLedge = preload("res://scripts/grabbable_ledge.gd")
const PhysicsObject = preload("res://scripts/physics_object.gd")
const EnemyScene = preload("res://scenes/enemy.tscn")
const NavGraphScene = preload("res://scripts/nav/nav_graph.gd")
const LaunchPad = preload("res://scripts/launch_pad.gd")
const RotatingPlatform = preload("res://scripts/rotating_platform.gd")
const KegelKing = preload("res://scripts/kegel_king.gd")

@export var seed_value: int = 42
@export var enemy_count: int = 12

## Per-form navigation & physique presets: spiders wall-walk, imps and humans
## parkour (jump + ledge climb), heavy centaurs can still hop low obstacles.
const ENEMY_DEFAULTS := {
	"human": {"nav_mode": "parkour", "grip_strength": 4.5, "move_speed": 4.2, "turn_speed": 8.5, "jump_apex": 1.9, "jump_range": 7.2, "max_step_height": 0.75},
	"imp": {"nav_mode": "parkour", "grip_strength": 3.8, "move_speed": 4.8, "turn_speed": 9.0, "jump_apex": 2.2, "jump_range": 8.0, "max_step_height": 0.8},
	"centaur": {"nav_mode": "parkour", "grip_strength": 7.0, "move_speed": 4.6, "jump_apex": 1.2, "jump_range": 4.5, "max_step_height": 0.9},
	"spider": {"nav_mode": "basic", "can_wall_walk": true, "grip_strength": 6.5, "move_speed": 4.2, "turn_speed": 7.5},
	"centipede": {"nav_mode": "basic", "can_wall_walk": true, "grip_strength": 5.5, "move_speed": 3.6},
}


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Central spawn plaza (the original playground).
	_build_platforms()
	_build_tower()
	_spawn_grenade_pickups()
	_build_jenga(Vector3(18, 0, 8), rng)
	_build_cube_pile(Vector3(22, 0, -4), rng)
	_build_ball_pit(Vector3(-18, 0, 6), rng)
	_build_kegel_set(Vector3(-12, 0, -10))
	_build_ramps_and_decor()
	_start_nav_graph()
	# Feature-showcase districts on the 400x400 map.
	_build_zones(rng)
	_spawn_enemies()


## Feature districts, each demonstrating one system from the smart-nav update.
func _build_zones(rng: RandomNumberGenerator) -> void:
	_build_roads_and_signs()
	_zone_ledge_field(Vector3(85, 0, -50))
	_zone_parkour_gauntlet(Vector3(-95, 0, -70))
	_zone_spider_canyon(Vector3(0, 0, -140))
	_zone_crawl_warren(Vector3(-110, 0, 40))
	_zone_silo(Vector3(120, 0, 70))
	_zone_knockback_range(Vector3(85, 0, 130), rng)
	_zone_rooftops(Vector3(-100, 0, 130))
	_zone_windmill(Vector3(-30, 0, 90))
	_zone_potato_shrine(Vector3(30, 0, 170))
	_build_launch_pads()


## The smart navigation system: samples every static surface (layer 6) into
## a typed graph. Runs asynchronously; enemies fall back to direct chase
## until the build finishes.
func _start_nav_graph() -> void:
	var graph := NavGraphScene.new()
	graph.name = "NavGraph"
	add_child(graph)
	# Covers the plaza AND every feature district (they sit within ±180), so
	# zone enemies get real graph routes instead of trail-only fallbacks.
	# The build is time-budgeted per frame, so the larger bake streams in
	# progressively instead of freezing the main thread like the old
	# monolithic 400×400 bake did.
	graph.configure(AABB(Vector3(-180, -6, -180), Vector3(360, 56, 360)))


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
		_spawn_enemy(root, s["form"], s["pos"], s.get("cfg", {}))


## Instantiates one enemy with per-form navigation/physique defaults;
## `overrides` may tweak any exported property (nav_mode, grip_strength, ...).
func _spawn_enemy(root: Node3D, form: String, pos: Vector3, overrides: Dictionary = {}) -> Node3D:
	var enemy := EnemyScene.instantiate()
	enemy.body_form = form
	var cfg: Dictionary = ENEMY_DEFAULTS.get(form, {}).duplicate()
	cfg.merge(overrides, true)
	for key in cfg:
		enemy.set(key, cfg[key])
	enemy.home_position = pos
	root.add_child(enemy)
	enemy.global_position = pos
	return enemy

# --- Feature-showcase zones (the x10 map) --------------------------------------

## Signpost with a floating label, readable when approaching from the plaza.
func _sign(parent: Node, pos: Vector3, text: String) -> void:
	_static_box(parent, pos + Vector3(0, 1.0, 0), Vector3(0.25, 2.0, 0.25), _mat(Color(0.4, 0.3, 0.2)))
	var label := Label3D.new()
	label.text = text
	label.font_size = 220
	label.pixel_size = 0.004
	label.modulate = Color(1.0, 0.95, 0.8)
	label.outline_size = 24
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = pos + Vector3(0, 2.6, 0)
	parent.add_child(label)


## Flat roads connecting the plaza to every district, with signposts.
func _build_roads_and_signs() -> void:
	var root := Node3D.new()
	root.name = "Roads"
	add_child(root)
	var road_mat := _mat(Color(0.32, 0.3, 0.28))
	var targets := [
		Vector3(85, 0, -50), Vector3(-95, 0, -70), Vector3(0, 0, -140),
		Vector3(-110, 0, 40), Vector3(120, 0, 70), Vector3(85, 0, 130),
		Vector3(-100, 0, 130), Vector3(-30, 0, 90),
	]
	for t in targets:
		var flat := Vector3(t.x, 0.0, t.z)
		var dist := flat.length()
		var dir := flat / maxf(dist, 0.01)
		var start := dir * 42.0
		var span := dist - 46.0
		if span <= 0.0:
			continue
		var center := start + dir * span * 0.5
		var road := _static_box(root, Vector3(center.x, 0.03, center.z), Vector3(3.0, 0.06, span), road_mat)
		road.rotation.y = atan2(-dir.x, -dir.z)
	_sign(root, Vector3(58, 0, -34), "LEDGE STEPS ->\ntiny ledges never stall anyone")
	_sign(root, Vector3(-64, 0, -47), "PARKOUR GAUNTLET ->\nimps jump gaps + climb ledges")
	_sign(root, Vector3(-3, 0, -105), "SPIDER CANYON ->\nblast them off the walls!")
	_sign(root, Vector3(-75, 0, 27), "CRAWL WARREN ->\nonly small bodies fit through")
	_sign(root, Vector3(83, 0, 48), "THE SILO ->\nsomething big lives inside...")
	_sign(root, Vector3(58, 0, 89), "KNOCKBACK RANGE ->\npunch (Q / RMB) + grenades")
	_sign(root, Vector3(-68, 0, 88), "ROOFTOP DISTRICT ->\nparkour chases up high")
	_sign(root, Vector3(-22, 0, 66), "WINDMILL\nride the sails")


## Zone 1: fields of 0.2-0.6 m micro-ledges — the step-up system showcase.
func _zone_ledge_field(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "LedgeField"
	root.position = origin
	add_child(root)
	var mats := [_mat(Color(0.6, 0.55, 0.45)), _mat(Color(0.5, 0.48, 0.42)), _mat(Color(0.66, 0.6, 0.5))]
	# Rows of long micro-ledges with varied heights.
	var heights := [0.25, 0.45, 0.3, 0.6, 0.4, 0.55, 0.25, 0.5]
	for i in heights.size():
		var h: float = heights[i]
		_static_box(root, Vector3(0, h * 0.5, -14 + i * 4.0), Vector3(26.0, h, 1.6), mats[i % 3])
	# Step pyramids (0.4 m per tier) on both flanks.
	for p in 2:
		var px := -9.0 + p * 18.0
		for tier in 5:
			var s := 9.0 - tier * 1.7
			_static_box(root, Vector3(px, 0.2 + tier * 0.4, 22), Vector3(s, 0.42, s), mats[tier % 3])
	_spawn_enemy(root, "centaur", origin + Vector3(-4, 0.1, 26))
	_spawn_enemy(root, "human", origin + Vector3(4, 0.1, 26))
	_spawn_enemy(root, "centipede", origin + Vector3(0, 0.1, 18))
	_spawn_enemy(root, "centaur", origin + Vector3(9, 2.3, 22))


## Zone 2: gap jumps, staggered ledges and climb walls for parkour enemies.
func _zone_parkour_gauntlet(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "ParkourGauntlet"
	root.position = origin
	add_child(root)
	var teal := _mat(Color(0.25, 0.55, 0.58))
	var stone := _mat(Color(0.45, 0.42, 0.38))
	# Gap-jump islands (3.2-4.5 m gaps, only JUMP edges link them).
	var islands := [
		Vector3(0, 1.0, 0), Vector3(4.6, 1.4, -2.5), Vector3(9.4, 1.9, 0.5),
		Vector3(13.8, 2.4, -2.0), Vector3(18.5, 2.9, 0.8),
	]
	for i in islands.size():
		_static_box(root, islands[i], Vector3(3.0, 0.8, 3.0), teal if i % 2 == 0 else stone, true)
	# Staggered climb ledges (1.4-2.6 m faces -> CLIMB edges).
	for i in 4:
		var h := 1.4 + i * 1.3
		_static_box(root, Vector3(-6.0 - i * 4.2, h * 0.5, 2.0), Vector3(3.4, h, 3.4), stone, true)
	# Finish plateau.
	_static_box(root, Vector3(-24, 3.2, 2.0), Vector3(6, 6.4, 6), teal, true)
	_spawn_enemy(root, "imp", origin + Vector3(18.5, 3.6, 0.8))
	_spawn_enemy(root, "imp", origin + Vector3(-24, 6.6, 2.0))
	_spawn_enemy(root, "imp", origin + Vector3(0, 1.6, 0))
	_spawn_enemy(root, "human", origin + Vector3(-10, 0.1, -6))


## Zone 3: sheer-walled canyon patrolled by wall-walking spiders, with a
## rickety plank bridge and grenade caches to blast them off.
func _zone_spider_canyon(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "SpiderCanyon"
	root.position = origin
	add_child(root)
	var rock := _mat(Color(0.38, 0.33, 0.3))
	var wood := _mat(Color(0.6, 0.42, 0.24), 0.7)
	# Two sheer walls, 10 m tall, 7 m apart.
	_static_box(root, Vector3(0, 5.0, -5.0), Vector3(30, 10, 3), rock)
	_static_box(root, Vector3(0, 5.0, 5.0), Vector3(30, 10, 3), rock)
	# Rim walkways.
	_static_box(root, Vector3(0, 10.2, -7.5), Vector3(30, 0.4, 2.0), rock)
	_static_box(root, Vector3(0, 10.2, 7.5), Vector3(30, 0.4, 2.0), rock)
	# Rickety plank bridge: static rails + loose rigid planks.
	_static_box(root, Vector3(-1.4, 10.15, 0), Vector3(0.5, 0.3, 10.4), wood)
	_static_box(root, Vector3(1.4, 10.15, 0), Vector3(0.5, 0.3, 10.4), wood)
	for i in 7:
		_rigid_box(root, Vector3(0, 10.5, -4.2 + i * 1.4), Vector3(3.4, 0.12, 1.1), wood, 0.8, 1.1)
	# Grenade practice caches.
	for p in [Vector3(-8, 0.8, 0), Vector3(8, 0.8, 0), Vector3(0, 11.0, -7.5), Vector3(0, 11.0, 7.5)]:
		_grenade_pickup(root, p)
	# Wall-walking ambushers.
	_spawn_enemy(root, "spider", origin + Vector3(-9, 0.1, -2.5))
	_spawn_enemy(root, "spider", origin + Vector3(9, 0.1, 2.5))
	_spawn_enemy(root, "spider", origin + Vector3(0, 10.6, -7.5))
	_spawn_enemy(root, "spider", origin + Vector3(-4, 10.6, 7.5))
	# Escape pad out of the crevasse.
	_launch_pad(root, Vector3(12, 0.2, 0), Vector3.UP, 16.0)


## Zone 4: crawl tunnels with graded hole sizes — clearance-aware pathing.
## Tall bodies must route around; small bodies cut straight through.
func _zone_crawl_warren(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "CrawlWarren"
	root.position = origin
	add_child(root)
	var rock := _mat(Color(0.42, 0.4, 0.45))
	var block_h := 3.6
	var depth := 12.0
	# Wall segments between three graded tunnels (x spans between gaps).
	var solid := [
		Vector2(-9.0, -6.6),   # edge .. tunnel A
		Vector2(-3.4, -1.5),   # A .. B
		Vector2(1.5, 3.9),     # B .. C
		Vector2(6.1, 9.0),     # C .. edge
	]
	for seg in solid:
		var w: float = seg.y - seg.x
		_static_box(root, Vector3((seg.x + seg.y) * 0.5, block_h * 0.5, 0), Vector3(w, block_h, depth), rock)
	# Tunnel roofs set each tunnel's height: A=3.0 (everyone), B=1.35
	# (no centaurs), C=1.05 (crawlers only).
	_static_box(root, Vector3(-5.0, 3.0 + (block_h - 3.0) * 0.5, 0), Vector3(3.2, block_h - 3.0, depth), rock)
	_static_box(root, Vector3(0.0, 1.35 + (block_h - 1.35) * 0.5, 0), Vector3(3.0, block_h - 1.35, depth), rock)
	_static_box(root, Vector3(5.0, 1.05 + (block_h - 1.05) * 0.5, 0), Vector3(2.2, block_h - 1.05, depth), rock)
	# Chasers behind the warren: watch them pick size-appropriate routes (F4).
	_spawn_enemy(root, "centaur", origin + Vector3(0, 0.1, 10))
	_spawn_enemy(root, "imp", origin + Vector3(-3, 0.1, 12))
	_spawn_enemy(root, "centipede", origin + Vector3(3, 0.1, 12))
	_spawn_enemy(root, "spider", origin + Vector3(6, 0.1, 10))


## Zone 5: hollow tower — exterior spiral for the player, interior walls are
## the spider highway. The Broodmother lives inside (heavy grip: chain
## several grenades to rip her off).
func _zone_silo(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Silo"
	root.position = origin
	add_child(root)
	var metal := _mat(Color(0.45, 0.47, 0.52), 0.5, 0.4)
	var gold := _mat(Color(0.85, 0.62, 0.25), 0.55, 0.15)
	var radius := 9.0
	var height := 26.0
	var segments := 10
	for i in segments:
		var ang := float(i) / float(segments) * TAU
		var pos := Vector3(cos(ang) * radius, height * 0.5, sin(ang) * radius)
		var seg := _static_box(root, pos, Vector3(6.4, height, 1.0), metal)
		seg.rotation.y = -ang + PI * 0.5
		if i == 0:
			# Door: shrink this segment to a lintel above a 5 m opening.
			seg.position.y = height * 0.5 + 2.5
			var mesh_node: MeshInstance3D = seg.get_child(0)
			var col_node: CollisionShape3D = seg.get_child(1)
			(mesh_node.mesh as BoxMesh).size = Vector3(6.4, height - 5.0, 1.0)
			(col_node.shape as BoxShape3D).size = Vector3(6.4, height - 5.0, 1.0)
	# Roof with a skylight slot.
	_static_box(root, Vector3(0, height + 0.3, -5.0), Vector3(20, 0.6, 8.0), metal)
	_static_box(root, Vector3(0, height + 0.3, 5.0), Vector3(20, 0.6, 8.0), metal)
	# Exterior spiral of grabbable ledges.
	for i in 18:
		var ang := i * 0.62
		var y := 1.2 + i * 1.35
		var pos := Vector3(cos(ang) * (radius + 2.2), y, sin(ang) * (radius + 2.2))
		_static_box(root, pos, Vector3(3.0, 0.6, 2.2), gold if i % 2 == 0 else metal, true)
	# The Broodmother: massive grip — needs sustained bombardment.
	_spawn_enemy(root, "spider", origin + Vector3(0, 0.1, 2), {
		"body_mass_override": 60.0, "grip_strength": 8.0, "move_speed": 2.6,
		"chase_range": 55.0, "activation_range": 140.0, "turn_speed": 4.0,
	})
	_spawn_enemy(root, "spider", origin + Vector3(-3, 0.1, -3))
	_spawn_enemy(root, "spider", origin + Vector3(3, 0.1, -3))
	for p in [Vector3(radius + 3.0, 0.8, 0), Vector3(0, height + 1.2, -9.5), Vector3(0, 0.8, -4)]:
		_grenade_pickup(root, p)


## Zone 6: shelves of kegel pins + enemies on ledges — chain-reaction alley.
func _zone_knockback_range(origin: Vector3, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "KnockbackRange"
	root.position = origin
	add_child(root)
	var stone := _mat(Color(0.5, 0.46, 0.4))
	var pin_mat := _mat(Color(0.95, 0.95, 0.92), 0.4)
	var stripe := _mat(Color(0.85, 0.15, 0.15), 0.4)
	# Backwall with three pin-lined shelves.
	_static_box(root, Vector3(0, 4.0, 8.0), Vector3(24, 8, 1.2), stone)
	for shelf in 3:
		var y := 1.6 + shelf * 2.2
		_static_box(root, Vector3(0, y, 6.9), Vector3(22, 0.3, 1.4), stone)
		for i in 8:
			_make_pin(root, Vector3(-9.0 + i * 2.6 + rng.randf_range(-0.2, 0.2), y + 0.55, 6.9), pin_mat, stripe)
	# Target pillars with enemies perched on top.
	for i in 2:
		var px := -7.0 + i * 14.0
		_static_box(root, Vector3(px, 1.25, 0), Vector3(2.4, 2.5, 2.4), stone, true)
		_spawn_enemy(root, "human", origin + Vector3(px, 2.7, 0))
	_spawn_enemy(root, "imp", origin + Vector3(0, 0.1, -4))
	# The Kegel King: golden royal pin — topple it for a grenade shower.
	_static_box(root, Vector3(0, 0.45, 4.0), Vector3(1.6, 0.9, 1.6), stone)
	_make_king_pin(root, Vector3(0, 1.6, 4.0))
	for p in [Vector3(-6, 0.8, -6), Vector3(6, 0.8, -6)]:
		_grenade_pickup(root, p)


func _make_king_pin(parent: Node, pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.set_script(KegelKing)
	body.position = pos
	body.mass = 2.2
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3(0, -0.5, 0)
	body.collision_layer = 1
	body.collision_mask = 1 | 2
	var gold := _mat(Color(0.95, 0.78, 0.2), 0.3, 0.8)
	var mesh_i := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.34
	cyl.height = 1.5
	mesh_i.mesh = cyl
	mesh_i.material_override = gold
	body.add_child(mesh_i)
	var crown := MeshInstance3D.new()
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.3
	crown_mesh.bottom_radius = 0.2
	crown_mesh.height = 0.22
	crown.mesh = crown_mesh
	crown.position.y = 0.85
	crown.material_override = gold
	body.add_child(crown)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 1.5
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)


## Zone 7: flat-roofed buildings linked only by JUMP edges — rooftop chases.
func _zone_rooftops(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "RooftopDistrict"
	root.position = origin
	add_child(root)
	var brickmats := [_mat(Color(0.55, 0.35, 0.3)), _mat(Color(0.4, 0.42, 0.5)), _mat(Color(0.5, 0.45, 0.35))]
	var buildings := [
		{"pos": Vector3(0, 0, 0), "size": Vector3(9, 6.0, 9)},
		{"pos": Vector3(12.4, 0, 1.0), "size": Vector3(8, 7.2, 8)},
		{"pos": Vector3(23.6, 0, -1.0), "size": Vector3(8, 8.4, 8)},
		{"pos": Vector3(11.0, 0, 12.6), "size": Vector3(8, 9.6, 8)},
		{"pos": Vector3(-1.0, 0, 12.0), "size": Vector3(8, 7.8, 9)},
		{"pos": Vector3(22.0, 0, 11.0), "size": Vector3(7, 10.4, 7)},
	]
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		var size: Vector3 = b["size"]
		var pos: Vector3 = b["pos"]
		_static_box(root, pos + Vector3(0, size.y * 0.5, 0), size, brickmats[i % 3], true)
	# Access stairs onto the first roof (0.55 m steps — hoppable by anyone).
	for i in 11:
		_static_box(root, Vector3(-6.4 - i * 1.35, 5.45 - i * 0.55, 0), Vector3(1.4, 0.5, 4.0), brickmats[2])
	# Parkour pursuers up top.
	_spawn_enemy(root, "imp", origin + Vector3(0, 6.3, 0))
	_spawn_enemy(root, "imp", origin + Vector3(23.6, 8.7, -1.0))
	_spawn_enemy(root, "human", origin + Vector3(11.0, 9.9, 12.6))
	_grenade_pickup(root, Vector3(22.0, 10.9, 11.0))


## Zone 8: windmill with rotating sails + a rideable carousel disc.
func _zone_windmill(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Windmill"
	root.position = origin
	add_child(root)
	var stone := _mat(Color(0.55, 0.5, 0.45))
	var wood := _mat(Color(0.6, 0.42, 0.24), 0.7)
	_static_box(root, Vector3(0, 4.5, 0), Vector3(3.4, 9.0, 3.4), stone, true)
	# Rotating sails (AnimatableBody3D hub spinning around Z).
	var hub := AnimatableBody3D.new()
	hub.set_script(RotatingPlatform)
	hub.set("spin_axis", Vector3(0, 0, 1))
	hub.set("degrees_per_second", 24.0)
	hub.position = Vector3(0, 8.0, 2.1)
	for s in 4:
		var sail := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.6, 7.0, 0.3)
		sail.mesh = box
		sail.material_override = wood
		sail.position = Vector3(0, 3.5, 0).rotated(Vector3(0, 0, 1), s * PI * 0.5)
		sail.rotation.z = s * PI * 0.5
		hub.add_child(sail)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		col.shape = shape
		col.position = sail.position
		col.rotation = sail.rotation
		hub.add_child(col)
	root.add_child(hub)
	# Ground carousel disc — hop on for a ride.
	var disc := AnimatableBody3D.new()
	disc.set_script(RotatingPlatform)
	disc.set("degrees_per_second", 14.0)
	disc.position = Vector3(9.0, 0.3, 0)
	var disc_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.4
	cyl.bottom_radius = 3.4
	cyl.height = 0.5
	disc_mesh.mesh = cyl
	disc_mesh.material_override = wood
	disc.add_child(disc_mesh)
	var disc_col := CollisionShape3D.new()
	var disc_shape := CylinderShape3D.new()
	disc_shape.radius = 3.4
	disc_shape.height = 0.5
	disc_col.shape = disc_shape
	disc.add_child(disc_col)
	root.add_child(disc)
	# Surprise: a wall-walking centipede guards the windmill.
	_spawn_enemy(root, "centipede", origin + Vector3(-4, 0.1, -4), {"can_wall_walk": true, "grip_strength": 6.0})


## Hidden surprise: an unmarked potato shrine with a one-time grenade cache.
func _zone_potato_shrine(origin: Vector3) -> void:
	var root := Node3D.new()
	root.name = "PotatoShrine"
	root.position = origin
	add_child(root)
	var sand := _mat(Color(0.7, 0.6, 0.42))
	var gold := _mat(Color(0.95, 0.78, 0.2), 0.3, 0.8)
	# Stepped pyramid mound with a hollow heart.
	var tiers := [Vector3(20, 1.2, 20), Vector3(16, 1.2, 16), Vector3(12, 1.2, 12), Vector3(8, 1.2, 8)]
	for i in tiers.size():
		var size: Vector3 = tiers[i]
		var y := 1.2 * i + 0.6
		if i == 0:
			# Ground tier is split to leave an entrance corridor (2.2 m wide)
			# facing away from the plaza.
			_static_box(root, Vector3(-5.55, y, 0), Vector3(8.9, 1.2, 20), sand)
			_static_box(root, Vector3(5.55, y, 0), Vector3(8.9, 1.2, 20), sand)
			_static_box(root, Vector3(0, y, -5.55), Vector3(2.2, 1.2, 8.9), sand)
		elif i == 1:
			_static_box(root, Vector3(-4.55, y, 0), Vector3(6.9, 1.2, 16), sand)
			_static_box(root, Vector3(4.55, y, 0), Vector3(6.9, 1.2, 16), sand)
			_static_box(root, Vector3(0, y, -4.55), Vector3(2.2, 1.2, 6.9), sand)
		else:
			_static_box(root, Vector3(0, y, 0), size, sand)
	# Inner sanctum: the Golden Potato on a plinth + cache.
	_static_box(root, Vector3(0, 0.35, 2.0), Vector3(1.0, 0.7, 1.0), gold)
	_rigid_sphere(root, Vector3(0, 1.1, 2.0), 0.34, gold, 0.6, 0.8)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.3)
	lamp.omni_range = 9.0
	lamp.position = Vector3(0, 1.8, 2.0)
	root.add_child(lamp)
	for i in 5:
		var ang := float(i) / 5.0 * TAU
		var pickup := _grenade_pickup(root, Vector3(cos(ang) * 1.8, 0.6, 2.0 + sin(ang) * 1.8))
		pickup.respawn_seconds = 9999.0


## Trampoline pads around the map (impulse volumes).
func _build_launch_pads() -> void:
	var root := Node3D.new()
	root.name = "LaunchPads"
	add_child(root)
	_launch_pad(root, Vector3(14, 0.2, 26), Vector3.UP, 15.0)
	_launch_pad(root, Vector3(-34, 0.2, -20), Vector3(0.3, 1, 0).normalized(), 17.0)
	_launch_pad(root, Vector3(60, 0.2, 100), Vector3.UP, 14.0)


func _launch_pad(parent: Node, pos: Vector3, dir: Vector3, speed: float) -> void:
	var pad := Area3D.new()
	pad.set_script(LaunchPad)
	pad.set("launch_dir", dir)
	pad.set("launch_speed", speed)
	pad.position = pos
	parent.add_child(pad)


func _grenade_pickup(parent: Node, pos: Vector3) -> Area3D:
	var pickup := Area3D.new()
	pickup.set_script(WorldPickup)
	pickup.position = pos
	pickup.item_id = ItemDef.GRENADE
	pickup.respawn_seconds = 6.0
	parent.add_child(pickup)
	return pickup
