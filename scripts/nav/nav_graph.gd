class_name NavGraph
extends Node3D
## Custom voxel-sampled surface navigation graph.
##
## Godot's NavigationServer is floor-only and bakes one mesh per agent size,
## which cannot express what this game needs: wall/ceiling routes for
## spider-like enemies, jump/ledge-climb parkour links, and per-agent "do I
## fit through this hole" filtering. So this graph samples the static world
## (collision layer 6, "nav_surface") into walkable surface nodes annotated
## with clearance, connects them with TYPED edges, and answers A* queries
## filtered by a NavAgentProfile.
##
## Edge types:
##   WALK  flat neighbors            STEP  small rise (tiny-ledge fix)
##   DROP  safe fall                 JUMP  ballistic gap crossing
##   CLIMB wall with grabbable lip (parkour hands)
##   WALL  vertical face traversal (wall walkers only)
##
## The build is chunked across frames so the 10x map never hitches at load.

signal build_finished

enum Edge { WALK, STEP, DROP, JUMP, CLIMB, WALL }
enum BuildPhase { IDLE, SAMPLE, LINK, JUMPS, DONE }

const CELL := 1.5                   ## Horizontal sampling resolution (m).
const SURFACE_MASK := 32            ## Physics layer 6: static nav surfaces only.
const MIN_HEADROOM := 0.72          ## Smallest crawl space worth a node.
const MAX_HEADROOM := 6.0
const MAX_CLEAR_R := 1.6            ## Lateral clearance probe cap.
const WALK_MAX := 0.45              ## |dy| treated as flat.
const STEP_MAX := 0.9               ## Rise crossable by stepping up.
const CLIMB_MAX := 3.0              ## Tallest hand-climbable ledge.
const WALL_MAX := 18.0              ## Tallest wall-walk link.
const DROP_MAX := 6.0               ## Longest recorded drop edge.
const JUMP_DY_UP := 1.4
const JUMP_DY_DOWN := 3.5
const MAX_MARCH_HITS := 8           ## Surface levels per column (tunnels etc).

const SAMPLE_PER_FRAME := 600
const LINK_PER_FRAME := 1200
const JUMPS_PER_FRAME := 250
const ASTAR_MAX_EXPANSIONS := 4500
const QUERY_BUDGET := 2             ## Max A* queries per physics frame.

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _bounds := AABB(Vector3(-60, -6, -60), Vector3(120, 48, 120))
var _nx: int = 0
var _nz: int = 0
var _phase: int = BuildPhase.IDLE
var _cursor: int = 0
var _queries_this_frame: int = 0

## Node storage (index = node id).
var _pos := PackedVector3Array()
var _headroom := PackedFloat32Array()
var _clear_r := PackedFloat32Array()
var _col_nodes := {}                ## Vector2i cell -> PackedInt32Array node ids.
var _edges: Array = []              ## Per node: PackedInt32Array [to, type, to, type, ...].

## Live debug data (F4): enemies publish their current path here.
var debug_enabled := false
var debug_paths := {}               ## instance id -> PackedVector3Array

var _debug_draw: Node3D


func _ready() -> void:
	add_to_group("nav_graph")
	var draw_script: GDScript = load("res://scripts/nav/nav_debug_draw.gd")
	_debug_draw = MeshInstance3D.new()
	_debug_draw.set_script(draw_script)
	_debug_draw.set("graph", self)
	_debug_draw.visible = false
	add_child(_debug_draw)


## Kicks off the asynchronous build over the given world bounds.
func configure(bounds: AABB) -> void:
	_bounds = bounds
	_nx = maxi(int(ceil(bounds.size.x / CELL)), 1)
	_nz = maxi(int(ceil(bounds.size.z / CELL)), 1)
	_phase = BuildPhase.SAMPLE
	_cursor = 0


func is_ready() -> bool:
	return _phase == BuildPhase.DONE


## Per-frame A* budget so a crowd of repathing enemies can't hitch a frame.
func can_query() -> bool:
	return _phase == BuildPhase.DONE and _queries_this_frame < QUERY_BUDGET


func node_count() -> int:
	return _pos.size()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_nav_debug"):
		debug_enabled = not debug_enabled
		_debug_draw.visible = debug_enabled


func _physics_process(_delta: float) -> void:
	_queries_this_frame = 0
	match _phase:
		BuildPhase.SAMPLE:
			var total := _nx * _nz
			var end := mini(_cursor + SAMPLE_PER_FRAME, total)
			var space := get_world_3d().direct_space_state
			while _cursor < end:
				_sample_column(space, _cursor)
				_cursor += 1
			if _cursor >= total:
				_phase = BuildPhase.LINK
				_cursor = 0
		BuildPhase.LINK:
			var end := mini(_cursor + LINK_PER_FRAME, _pos.size())
			var space := get_world_3d().direct_space_state
			while _cursor < end:
				_link_node(space, _cursor)
				_cursor += 1
			if _cursor >= _pos.size():
				_phase = BuildPhase.JUMPS
				_cursor = 0
		BuildPhase.JUMPS:
			var end := mini(_cursor + JUMPS_PER_FRAME, _pos.size())
			var space := get_world_3d().direct_space_state
			while _cursor < end:
				_link_jumps(space, _cursor)
				_cursor += 1
			if _cursor >= _pos.size():
				_phase = BuildPhase.DONE
				var edge_count := 0
				for e in _edges:
					edge_count += (e as PackedInt32Array).size() / 2
				print("NavGraph: %d nodes, %d edges" % [_pos.size(), edge_count])
				build_finished.emit()


# --- Sampling ------------------------------------------------------------

## Ray-marches one grid column top to bottom, creating a node on every
## up-facing surface (ground, platform tops, tunnel floors under ceilings).
func _sample_column(space: PhysicsDirectSpaceState3D, ci: int) -> void:
	@warning_ignore("integer_division")
	var zi := ci / _nx
	var xi := ci % _nx
	var x := _bounds.position.x + (float(xi) + 0.5) * CELL
	var z := _bounds.position.z + (float(zi) + 0.5) * CELL
	var top := _bounds.position.y + _bounds.size.y
	var bottom := _bounds.position.y
	var from := Vector3(x, top, z)
	var col := PackedInt32Array()

	for guard in MAX_MARCH_HITS:
		var query := PhysicsRayQueryParameters3D.create(from, Vector3(x, bottom, z))
		query.collision_mask = SURFACE_MASK
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var p: Vector3 = hit["position"]
		var n: Vector3 = hit["normal"]
		if n.y >= 0.65:
			var id := _try_add_node(space, p)
			if id >= 0:
				col.append(id)
		from = p + Vector3.DOWN * 0.2
		if from.y <= bottom:
			break

	if not col.is_empty():
		_col_nodes[Vector2i(xi, zi)] = col


## Validates and annotates a candidate node: rejects buried points, measures
## vertical headroom and lateral clearance (the "hole size" data).
func _try_add_node(space: PhysicsDirectSpaceState3D, p: Vector3) -> int:
	# Buried check: the point just above must not be inside a solid.
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = p + Vector3.UP * 0.3
	pq.collision_mask = SURFACE_MASK
	if not space.intersect_point(pq, 1).is_empty():
		return -1

	# Headroom: how much vertical space above the surface.
	var hq := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.05, p + Vector3.UP * MAX_HEADROOM)
	hq.collision_mask = SURFACE_MASK
	var hit := space.intersect_ray(hq)
	var headroom := MAX_HEADROOM
	if not hit.is_empty():
		headroom = (hit["position"] as Vector3).y - p.y
	if headroom < MIN_HEADROOM:
		return -1

	# Lateral clearance: shortest free distance to a wall at torso height.
	var probe_h: float = clampf(headroom * 0.5, 0.2, 0.45)
	var origin := p + Vector3.UP * probe_h
	var clear_r := MAX_CLEAR_R
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var cq := PhysicsRayQueryParameters3D.create(origin, origin + dir * MAX_CLEAR_R)
		cq.collision_mask = SURFACE_MASK
		var chit := space.intersect_ray(cq)
		if not chit.is_empty():
			clear_r = minf(clear_r, origin.distance_to(chit["position"]))

	var id := _pos.size()
	_pos.append(p)
	_headroom.append(headroom)
	_clear_r.append(clear_r)
	_edges.append(PackedInt32Array())
	return id


# --- Linking ---------------------------------------------------------------

func _cell_of(i: int) -> Vector2i:
	var p := _pos[i]
	return Vector2i(
		int(floor((p.x - _bounds.position.x) / CELL)),
		int(floor((p.z - _bounds.position.z) / CELL))
	)


## Classifies edges from node i to every node in the 4 neighbor columns.
func _link_node(space: PhysicsDirectSpaceState3D, i: int) -> void:
	var cell := _cell_of(i)
	for dir in DIRS4:
		var col: PackedInt32Array = _col_nodes.get(cell + dir, PackedInt32Array())
		for j in col:
			_classify_edge(space, i, j)


func _classify_edge(space: PhysicsDirectSpaceState3D, i: int, j: int) -> void:
	var a := _pos[i]
	var b := _pos[j]
	var dy := b.y - a.y

	if absf(dy) <= WALK_MAX:
		# Flat walk: knee-height line of sight + ground under the midpoint.
		if not _ray_clear(space, a + Vector3.UP * 0.4, b + Vector3.UP * 0.4):
			return
		var mid := (a + b) * 0.5 + Vector3.UP * 0.3
		if _ray_hits(space, mid, mid + Vector3.DOWN * 1.2):
			_add_edge(i, j, Edge.WALK)
	elif dy > WALK_MAX and dy <= STEP_MAX:
		# Small rise: clear space above the lip to step onto.
		var lip_h := Vector3.UP * (dy + 0.35)
		if _ray_clear(space, a + lip_h, b + Vector3.UP * 0.35):
			_add_edge(i, j, Edge.STEP)
	elif dy < -WALK_MAX and -dy <= DROP_MAX:
		# Drop: walk off the lip with torso clearance.
		var over := Vector3(b.x, a.y + 0.35, b.z)
		if _ray_clear(space, a + Vector3.UP * 0.35, over):
			_add_edge(i, j, Edge.DROP)
	elif dy > STEP_MAX:
		# A wall face separates the levels. If a face really exists, it is a
		# CLIMB (parkour, capped height) and/or a WALL link (wall walkers).
		var face_h := Vector3.UP * minf(dy * 0.5, 1.2)
		var face := _ray_hits(space, a + face_h, Vector3(b.x, a.y + face_h.y, b.z))
		if face:
			if dy <= CLIMB_MAX:
				_add_edge(i, j, Edge.CLIMB)
			if dy <= WALL_MAX:
				_add_edge(i, j, Edge.WALL)
	elif dy < -STEP_MAX and -dy <= WALL_MAX:
		# Descending a tall face: wall walkers stroll straight down it.
		var face_h2 := Vector3.UP * minf(-dy * 0.5, 1.2)
		if _ray_hits(space, b + face_h2, Vector3(a.x, b.y + face_h2.y, a.z)):
			_add_edge(i, j, Edge.WALL)


## Connects ledge rims across gaps with ballistic-feasible JUMP edges.
func _link_jumps(space: PhysicsDirectSpaceState3D, i: int) -> void:
	if not _is_rim(i):
		return
	var cell := _cell_of(i)
	var a := _pos[i]
	var added := 0
	for dir in DIRS8:
		if added >= 6:
			return
		for d in [2, 3, 4]:
			var col: PackedInt32Array = _col_nodes.get(cell + dir * d, PackedInt32Array())
			var linked := false
			for j in col:
				var b := _pos[j]
				var dy := b.y - a.y
				if dy > JUMP_DY_UP or dy < -JUMP_DY_DOWN:
					continue
				if not _gap_between(space, a, b):
					continue
				# Arc clearance: two rays over the apex of the jump.
				var apex := Vector3((a.x + b.x) * 0.5, maxf(a.y, b.y) + 1.15, (a.z + b.z) * 0.5)
				if _ray_clear(space, a + Vector3.UP * 0.55, apex) and _ray_clear(space, apex, b + Vector3.UP * 0.55):
					_add_edge(i, j, Edge.JUMP)
					added += 1
					linked = true
					break
			if linked:
				break


## Rim: a node missing at least one flat connection — a candidate jump lip.
func _is_rim(i: int) -> bool:
	var flat := 0
	var e := _edges[i] as PackedInt32Array
	for k in range(0, e.size(), 2):
		var t := e[k + 1]
		if t == Edge.WALK or t == Edge.STEP:
			flat += 1
	return flat < 4


## True when the straight line between two rims crosses a real void
## (no walkable ground close under the midpoint) — otherwise walking works.
func _gap_between(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var mid := (a + b) * 0.5
	var probe_top := Vector3(mid.x, maxf(a.y, b.y) + 0.4, mid.z)
	var probe_bottom := probe_top + Vector3.DOWN * (1.6 + maxf(a.y, b.y) - minf(a.y, b.y))
	return not _ray_hits(space, probe_top, probe_bottom)


func _add_edge(i: int, j: int, type: int) -> void:
	var e := _edges[i] as PackedInt32Array
	for k in range(0, e.size(), 2):
		if e[k] == j and e[k + 1] == type:
			return
	e.append(j)
	e.append(type)
	_edges[i] = e


func _ray_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = SURFACE_MASK
	return space.intersect_ray(q).is_empty()


func _ray_hits(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = SURFACE_MASK
	return not space.intersect_ray(q).is_empty()


# --- Query -------------------------------------------------------------------

## A* over the typed graph, filtered by the agent profile. Returns waypoints
## as dictionaries: {"pos": Vector3, "move": Edge} where "move" describes how
## to travel from the previous waypoint to this one. Empty when unreachable
## (callers fall back to direct steering).
func find_path(from: Vector3, to: Vector3, prof: NavAgentProfile) -> Array:
	if _phase != BuildPhase.DONE:
		return []
	_queries_this_frame += 1
	var start := _nearest_node(from, prof)
	var goal := _nearest_node(to, prof)
	if start < 0 or goal < 0 or start == goal:
		return []

	var goal_pos := _pos[goal]
	var open: Array[Vector2] = []       # (f, id) binary min-heap.
	var g_score := {}
	var came_from := {}
	var came_move := {}
	var closed := {}
	g_score[start] = 0.0
	_heap_push(open, Vector2(_pos[start].distance_to(goal_pos), float(start)))

	var best := start
	var best_h := _pos[start].distance_to(goal_pos)
	var expansions := 0
	var found := false

	while not open.is_empty():
		var top := _heap_pop(open)
		var current := int(top.y)
		if closed.has(current):
			continue
		closed[current] = true
		expansions += 1
		if current == goal:
			found = true
			break
		if expansions > ASTAR_MAX_EXPANSIONS:
			break

		var cur_pos := _pos[current]
		var cur_g: float = g_score[current]
		var e := _edges[current] as PackedInt32Array
		for k in range(0, e.size(), 2):
			var nb := e[k]
			var type := e[k + 1]
			if closed.has(nb):
				continue
			if not _node_fits(nb, prof):
				continue
			var cost := _edge_cost(current, nb, type, prof)
			if cost < 0.0:
				continue
			var tentative := cur_g + cost
			if tentative < float(g_score.get(nb, INF)):
				g_score[nb] = tentative
				came_from[nb] = current
				came_move[nb] = type
				var h := _pos[nb].distance_to(goal_pos)
				if h < best_h:
					best_h = h
					best = nb
				_heap_push(open, Vector2(tentative + h, float(nb)))

	var end_node := goal if found else best
	if not found:
		# Partial paths are only useful if they get meaningfully closer.
		if _pos[start].distance_to(goal_pos) - best_h < 3.0:
			return []
	return _reconstruct(start, end_node, came_from, came_move)


func _reconstruct(start: int, end_node: int, came_from: Dictionary, came_move: Dictionary) -> Array:
	var chain: Array[int] = []
	var moves: Array[int] = []
	var cur := end_node
	while cur != start:
		chain.append(cur)
		moves.append(int(came_move.get(cur, Edge.WALK)))
		if not came_from.has(cur):
			return []
		cur = came_from[cur]
	chain.reverse()
	moves.reverse()

	var out: Array = []
	for idx in chain.size():
		out.append({"pos": _pos[chain[idx]], "move": moves[idx]})
	return _smooth(out)


## Greedy line-of-sight smoothing across consecutive WALK waypoints only —
## special moves (jump/climb/wall) must keep their exact anchor points.
func _smooth(path: Array) -> Array:
	if path.size() < 3:
		return path
	var space := get_world_3d().direct_space_state
	var out: Array = [path[0]]
	var anchor: Vector3 = (path[0] as Dictionary)["pos"]
	var idx := 1
	while idx < path.size():
		var step: Dictionary = path[idx]
		if int(step["move"]) != Edge.WALK or idx == path.size() - 1:
			out.append(step)
			anchor = step["pos"]
			idx += 1
			continue
		# Look ahead: furthest WALK waypoint still visible from the anchor.
		var far := idx
		for probe in range(idx + 1, mini(idx + 6, path.size())):
			var pstep: Dictionary = path[probe]
			if int(pstep["move"]) != Edge.WALK:
				break
			var a: Vector3 = anchor + Vector3.UP * 0.4
			var b: Vector3 = (pstep["pos"] as Vector3) + Vector3.UP * 0.4
			if absf(a.y - b.y) < 0.6 and _ray_clear(space, a, b):
				far = probe
			else:
				break
		out.append(path[far])
		anchor = (path[far] as Dictionary)["pos"]
		idx = far + 1
	return out


func _node_fits(i: int, prof: NavAgentProfile) -> bool:
	return _headroom[i] >= prof.height * 0.9 and _clear_r[i] >= prof.radius * 0.85


## -1 = edge not allowed for this profile.
func _edge_cost(i: int, j: int, type: int, prof: NavAgentProfile) -> float:
	var a := _pos[i]
	var b := _pos[j]
	var dy := b.y - a.y
	var dist := a.distance_to(b)
	match type:
		Edge.WALK:
			return dist
		Edge.STEP:
			return dist * 1.25 if dy <= prof.max_step + 0.3 else -1.0
		Edge.DROP:
			return dist * 1.15 if -dy <= prof.max_drop else -1.0
		Edge.JUMP:
			if not prof.can_jump:
				return -1.0
			var hdist := Vector2(b.x - a.x, b.z - a.z).length()
			if hdist > prof.jump_range or dy > prof.jump_height:
				return -1.0
			return dist * 1.9
		Edge.CLIMB:
			return dist * 2.2 if prof.can_parkour and dy <= prof.climb_height else -1.0
		Edge.WALL:
			return dist * 1.5 if prof.can_wall_walk else -1.0
	return -1.0


## Closest usable node to a world position (spiral cell search).
func _nearest_node(p: Vector3, prof: NavAgentProfile) -> int:
	var cx := int(floor((p.x - _bounds.position.x) / CELL))
	var cz := int(floor((p.z - _bounds.position.z) / CELL))
	var best := -1
	var best_score := INF
	for r in 4:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var col: PackedInt32Array = _col_nodes.get(Vector2i(cx + dx, cz + dz), PackedInt32Array())
				for id in col:
					if not _node_fits(id, prof):
						continue
					var np := _pos[id]
					var dy := absf(np.y - p.y)
					if dy > 8.0:
						continue
					var score := Vector2(np.x - p.x, np.z - p.z).length() + dy * 1.2
					if score < best_score:
						best_score = score
						best = id
		if best >= 0 and r >= 1:
			break
	return best


## Enemies publish their active path for the F4 debug view.
func set_debug_path(owner_id: int, path: PackedVector3Array) -> void:
	if path.is_empty():
		debug_paths.erase(owner_id)
	else:
		debug_paths[owner_id] = path


# --- Binary min-heap on Vector2(f, id) ----------------------------------------

static func _heap_push(heap: Array[Vector2], item: Vector2) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		@warning_ignore("integer_division")
		var parent := (i - 1) / 2
		if heap[parent].x <= heap[i].x:
			break
		var tmp := heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


static func _heap_pop(heap: Array[Vector2]) -> Vector2:
	var top := heap[0]
	var last: Vector2 = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1
		var r := i * 2 + 2
		var smallest := i
		if l < n and heap[l].x < heap[smallest].x:
			smallest = l
		if r < n and heap[r].x < heap[smallest].x:
			smallest = r
		if smallest == i:
			break
		var tmp := heap[smallest]
		heap[smallest] = heap[i]
		heap[i] = tmp
		i = smallest
	return top
