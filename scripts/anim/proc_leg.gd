class_name ProcLeg
extends RefCounted
## Runtime state for one leg: keeps the foot PLANTED at a fixed world position
## while the body moves, and swings it to a new raycast ground target only when
## it drifts too far from its home. Distance/velocity driven — no sine waves.

var plan: ProcBodyPlan.LegPlan
var hip_bone: int = -1
var knee_bone: int = -1
var foot_bone: int = -1
var side: float = 1.0
var index: int = 0

## World-space state.
var anchor: Vector3            ## Where the foot is planted.
var foot_pos: Vector3          ## Current (possibly mid-swing) foot position.
var ground_normal: Vector3 = Vector3.UP

var stepping: bool = false
var step_p: float = 1.0
var step_from: Vector3
var step_to: Vector3
var time_since_step: float = 100.0
var initialized: bool = false


func _init(p_plan: ProcBodyPlan.LegPlan, bones: Dictionary, p_index: int) -> void:
	plan = p_plan
	hip_bone = bones["hip"]
	knee_bone = bones["knee"]
	foot_bone = bones["foot"]
	side = bones["side"]
	index = p_index


func plant_instantly(world_pos: Vector3, normal: Vector3) -> void:
	anchor = world_pos
	foot_pos = world_pos
	ground_normal = normal
	stepping = false
	step_p = 1.0
	initialized = true


func drift_sq(desired: Vector3) -> float:
	return anchor.distance_squared_to(desired)


func begin_step(target: Vector3) -> void:
	stepping = true
	step_p = 0.0
	step_from = foot_pos
	step_to = target
	time_since_step = 0.0


## Advances an in-flight step. `target` may keep moving (tracks a turning body).
## Returns true on the frame the foot plants.
func advance(delta: float, step_time: float, target: Vector3, normal: Vector3) -> bool:
	time_since_step += delta
	if not stepping:
		foot_pos = anchor
		return false
	step_to = step_to.lerp(target, 0.35)
	step_p = minf(step_p + delta / maxf(step_time, 0.05), 1.0)
	var p := smoothstep(0.0, 1.0, step_p)
	var pos := step_from.lerp(step_to, p)
	# Parabolic lift: 4p(1-p) peaks mid-swing, zero at both contacts.
	pos.y += plan.step_lift * 4.0 * p * (1.0 - p)
	foot_pos = pos
	if step_p >= 1.0:
		stepping = false
		anchor = step_to
		foot_pos = step_to
		ground_normal = normal
		return true
	return false
