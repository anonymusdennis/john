class_name NavAgentProfile
extends RefCounted
## Describes what one agent can traverse: its physical size (the maximum hole
## it can fit through), stepping/jumping/dropping limits, and special skills
## (parkour ledge climbing, wall walking). NavGraph filters nodes and edges
## against this profile so every body form finds only paths it can really use.

var radius: float = 0.35            ## Capsule radius — lateral clearance needed.
var height: float = 1.6             ## Capsule height — headroom needed.
var max_step: float = 0.6           ## Highest rise crossed without jumping.
var max_drop: float = 4.0           ## Highest safe fall.
var can_jump: bool = false          ## May use JUMP edges (gaps between ledges).
var jump_range: float = 6.0         ## Longest gap jumpable.
var jump_height: float = 1.4        ## Highest upward jump.
var can_parkour: bool = false       ## May use CLIMB edges (ledge grab + clamber).
var climb_height: float = 2.8       ## Tallest wall climbable with hands.
var can_wall_walk: bool = false     ## May use WALL edges (walk straight up faces).


## Convenience: derive size directly from a procedural body plan, so the
## "maximum hole I fit through" always matches the actual collider.
static func for_plan(plan: ProcBodyPlan) -> NavAgentProfile:
	var p := NavAgentProfile.new()
	p.radius = plan.collider_radius
	p.height = plan.collider_height
	return p
