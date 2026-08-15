class_name NavPathRecorder
extends Node
## Records the grounded breadcrumb trail of its parent (player, companion —
## any nav target). Every position in the trail is a spot the target actually
## stood on, so the line doubles as a proven traversal template: enemies that
## cannot find a graph route to a floating platform can replay the exact line
## the target took to get there.
##
## The buffer is a generous ring (MAX_POINTS * SPACING ≈ 600 m of movement);
## old crumbs are dropped in chunks so trimming never spikes a frame.
## Each nav target carries its own recorder, so with multiple players or
## companions every enemy can query the trail of *its* current target.

const SPACING := 0.8                ## Min distance between recorded crumbs (m).
const MAX_POINTS := 768             ## Generous cap (~600 m of trail).
const TRIM_CHUNK := 96              ## Crumbs dropped per trim (amortized cost).

var _points := PackedVector3Array()
var _body: Node3D


## Fetches the recorder attached to a target, or null.
static func find_for(target: Node) -> NavPathRecorder:
	if target == null:
		return null
	for child in target.get_children():
		if child is NavPathRecorder:
			return child
	return null


func _ready() -> void:
	_body = get_parent() as Node3D


func _physics_process(_delta: float) -> void:
	if _body == null:
		return
	# Only grounded positions: airborne arcs would not be standable crumbs.
	# Gaps between grounded crumbs are exactly the target's jumps.
	if _body is CharacterBody3D and not (_body as CharacterBody3D).is_on_floor():
		return
	var p := _body.global_position
	if not _points.is_empty() and p.distance_to(_points[_points.size() - 1]) < SPACING:
		return
	_points.append(p)
	if _points.size() > MAX_POINTS:
		_points = _points.slice(TRIM_CHUNK)


func size() -> int:
	return _points.size()


func point(i: int) -> Vector3:
	return _points[i]


## Latest crumb — where the target last stood on ground.
func latest() -> Vector3:
	return _points[_points.size() - 1] if not _points.is_empty() else Vector3.INF


## Index of the crumb nearest to `pos` within `max_dist` and a strict
## vertical band (`max_dy`), so a trail on a roof does not count as "near"
## from the street below. Callers pass an ability-derived `max_dy` — the band
## is always enforced; vertical distance also weighs into the score so the
## most reachable crumb wins. Returns -1 when nothing qualifies.
func nearest_index(pos: Vector3, max_dist: float, max_dy: float = 2.5) -> int:
	var best := -1
	var best_d := max_dist
	for i in _points.size():
		var c := _points[i]
		var dy := absf(c.y - pos.y)
		if dy > max_dy:
			continue
		var d := Vector2(c.x - pos.x, c.z - pos.z).length() + dy * 0.35
		if d < best_d:
			best_d = d
			best = i
	return best
