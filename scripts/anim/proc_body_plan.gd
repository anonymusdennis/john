class_name ProcBodyPlan
extends Resource
## Data-driven description of a creature body for the procedural animation system.
##
## A plan is a list of joints with roles + settings, from which ProcBodyBuilder
## generates a Skeleton3D and ProcAnimator drives fully procedural motion.
## Any body form works: bipeds, quadrupeds/centaurs, spiders, centipedes, ...
##
## Conventions: character forward is -Z, up is +Y. Sizes in meters.


## One spine/body segment. Segment 0 is the root (its offset = rest position
## above the ground). Later segments chain off the previous one.
class SegmentPlan:
	var offset: Vector3 = Vector3.ZERO      ## From previous segment (segment 0: from ground origin).
	var radius: float = 0.15                ## Visual thickness.
	var preferred_pitch: float = 0.0        ## "Try to keep this joint at angle X" (radians, about +X).
	var stiffness: float = 10.0             ## How strongly the joint returns to its preferred angle.
	var lag: float = 0.0                    ## 0 = rigid; >0 = world-space follow-through (snake/centipede).

	func _init(p_offset: Vector3 = Vector3.ZERO, p_radius: float = 0.15, p_pitch: float = 0.0, p_lag: float = 0.0) -> void:
		offset = p_offset
		radius = p_radius
		preferred_pitch = p_pitch
		lag = p_lag


## One leg: a 2-segment IK chain that steps to stay planted under the body.
class LegPlan:
	var segment: int = 0                    ## Spine segment the hip attaches to.
	var hip_offset: Vector3 = Vector3.ZERO  ## From that segment's joint.
	var upper_len: float = 0.4
	var lower_len: float = 0.4
	var foot_len: float = 0.12              ## Visual foot size.
	var stance: Vector3 = Vector3.ZERO      ## Ground home offset from below-hip (x = splay, z = fore/aft).
	var step_trigger: float = 0.35          ## Step when the foot drifts further than this from home.
	var step_lift: float = 0.16             ## Step arc apex height.
	var knee_forward: bool = true           ## Knee bends toward -Z (true) or +Z (false, e.g. bird/spider rear).

	func _init(p_segment: int = 0, p_hip: Vector3 = Vector3.ZERO, p_upper: float = 0.4, p_lower: float = 0.4, p_stance: Vector3 = Vector3.ZERO) -> void:
		segment = p_segment
		hip_offset = p_hip
		upper_len = p_upper
		lower_len = p_lower
		stance = p_stance


## One arm/hand: rest-hangs with walk counter-swing, aims at targets, attacks.
class ArmPlan:
	var segment: int = 0                    ## Spine segment the shoulder attaches to.
	var shoulder_offset: Vector3 = Vector3.ZERO
	var upper_len: float = 0.3
	var lower_len: float = 0.3
	var hand_radius: float = 0.07

	func _init(p_segment: int = 0, p_shoulder: Vector3 = Vector3.ZERO, p_upper: float = 0.3, p_lower: float = 0.3) -> void:
		segment = p_segment
		shoulder_offset = p_shoulder
		upper_len = p_upper
		lower_len = p_lower


var form_name: StringName = &"custom"
var segments: Array[SegmentPlan] = []
var legs: Array[LegPlan] = []
var arms: Array[ArmPlan] = []

## Head: attached to a spine segment through a neck joint (-1 = last segment).
var head_segment: int = -1
var neck_offset: Vector3 = Vector3(0.0, 0.12, 0.0)
var head_offset: Vector3 = Vector3(0.0, 0.12, -0.02)
var head_radius: float = 0.13
var head_yaw_limit: float = deg_to_rad(70.0)    ## "Look at the player without breaking your neck."
var head_pitch_limit: float = deg_to_rad(40.0)

## Tail: optional follow-through chain (+Z is backwards; -1 = last segment).
var tail_segment: int = 0
var tail_offsets: Array[Vector3] = []
var tail_radius: float = 0.06

## Locomotion feel.
var ride_height: float = 0.85               ## Root joint height above the planted feet plane.
var step_time: float = 0.22                 ## Seconds per step at walk speed (scales down when fast).
var stance_pitch_gain: float = 0.7          ## How much body pitch follows front/back foot heights.
var stance_roll_gain: float = 0.5           ## How much body roll follows left/right foot heights.
var arm_swing: float = 0.55                 ## Walk counter-swing amount for arms.
var attack_time: float = 0.5
var attack_reach: float = 1.3

## Colors + collision capsule for the owning CharacterBody3D.
var body_color: Color = Color(0.6, 0.3, 0.3)
var accent_color: Color = Color(0.9, 0.85, 0.7)
var collider_radius: float = 0.35
var collider_height: float = 1.6


func total_height() -> float:
	var h := 0.0
	for seg in segments:
		h += maxf(seg.offset.y, 0.0)
	return h + maxf(neck_offset.y, 0.0) + maxf(head_offset.y, 0.0) + head_radius


static func available_forms() -> PackedStringArray:
	return PackedStringArray(["human", "imp", "centaur", "spider", "centipede"])


static func make(form: StringName) -> ProcBodyPlan:
	match form:
		&"human":
			return make_human()
		&"imp":
			return make_imp()
		&"centaur":
			return make_centaur()
		&"spider":
			return make_spider()
		&"centipede":
			return make_centipede()
	push_warning("ProcBodyPlan: unknown form '%s', using human" % form)
	return make_human()


## Upright biped: pelvis -> belly -> chest spine, two legs, two arms.
static func make_human() -> ProcBodyPlan:
	var p := ProcBodyPlan.new()
	p.form_name = &"human"
	p.segments = [
		SegmentPlan.new(Vector3(0.0, 0.82, 0.0), 0.16),
		SegmentPlan.new(Vector3(0.0, 0.24, 0.0), 0.145, deg_to_rad(3.0)),
		SegmentPlan.new(Vector3(0.0, 0.26, 0.0), 0.17, deg_to_rad(-2.0)),
	]
	p.legs = [
		LegPlan.new(0, Vector3(-0.11, -0.02, 0.0), 0.45, 0.45, Vector3(-0.14, 0.0, 0.0)),
		LegPlan.new(0, Vector3(0.11, -0.02, 0.0), 0.45, 0.45, Vector3(0.14, 0.0, 0.0)),
	]
	for leg in p.legs:
		leg.step_trigger = 0.32
		leg.step_lift = 0.17
	p.arms = [
		ArmPlan.new(2, Vector3(-0.24, 0.18, 0.0), 0.3, 0.3),
		ArmPlan.new(2, Vector3(0.24, 0.18, 0.0), 0.3, 0.3),
	]
	p.neck_offset = Vector3(0.0, 0.16, 0.0)
	p.head_offset = Vector3(0.0, 0.13, -0.02)
	p.head_radius = 0.13
	p.ride_height = 0.8
	p.step_time = 0.24
	p.attack_reach = 1.2
	p.body_color = Color(0.62, 0.28, 0.24)
	p.accent_color = Color(0.92, 0.83, 0.65)
	p.collider_radius = 0.34
	p.collider_height = 1.55
	return p


## Small hunched biped with long arms, big head and a lashing tail.
static func make_imp() -> ProcBodyPlan:
	var p := ProcBodyPlan.new()
	p.form_name = &"imp"
	p.segments = [
		SegmentPlan.new(Vector3(0.0, 0.5, 0.0), 0.13),
		SegmentPlan.new(Vector3(0.0, 0.17, -0.06), 0.14, deg_to_rad(24.0)),
	]
	p.legs = [
		LegPlan.new(0, Vector3(-0.1, -0.02, 0.0), 0.3, 0.3, Vector3(-0.13, 0.0, 0.02)),
		LegPlan.new(0, Vector3(0.1, -0.02, 0.0), 0.3, 0.3, Vector3(0.13, 0.0, 0.02)),
	]
	for leg in p.legs:
		leg.step_trigger = 0.24
		leg.step_lift = 0.14
	p.arms = [
		ArmPlan.new(1, Vector3(-0.19, 0.1, -0.02), 0.32, 0.32),
		ArmPlan.new(1, Vector3(0.19, 0.1, -0.02), 0.32, 0.32),
	]
	p.neck_offset = Vector3(0.0, 0.1, -0.05)
	p.head_offset = Vector3(0.0, 0.1, -0.04)
	p.head_radius = 0.15
	p.head_yaw_limit = deg_to_rad(80.0)
	p.tail_offsets = [
		Vector3(0.0, 0.04, 0.16), Vector3(0.0, 0.03, 0.15), Vector3(0.0, 0.02, 0.13),
	]
	p.tail_radius = 0.05
	p.ride_height = 0.48
	p.step_time = 0.17
	p.attack_time = 0.4
	p.attack_reach = 1.0
	p.body_color = Color(0.55, 0.18, 0.5)
	p.accent_color = Color(0.95, 0.8, 0.4)
	p.collider_radius = 0.3
	p.collider_height = 1.05
	return p


## Horse body (4 legs) with an upright humanoid torso, arms and head in front.
static func make_centaur() -> ProcBodyPlan:
	var p := ProcBodyPlan.new()
	p.form_name = &"centaur"
	p.segments = [
		SegmentPlan.new(Vector3(0.0, 0.78, 0.0), 0.2),          # 0: rear hips
		SegmentPlan.new(Vector3(0.0, 0.02, -0.38), 0.21),       # 1: barrel
		SegmentPlan.new(Vector3(0.0, 0.04, -0.38), 0.2),        # 2: front shoulders
		SegmentPlan.new(Vector3(0.0, 0.3, -0.05), 0.15, deg_to_rad(-4.0)),  # 3: humanoid waist
		SegmentPlan.new(Vector3(0.0, 0.26, 0.0), 0.17),         # 4: humanoid chest
	]
	p.legs = [
		LegPlan.new(0, Vector3(-0.17, -0.04, 0.02), 0.42, 0.42, Vector3(-0.2, 0.0, 0.04)),
		LegPlan.new(0, Vector3(0.17, -0.04, 0.02), 0.42, 0.42, Vector3(0.2, 0.0, 0.04)),
		LegPlan.new(2, Vector3(-0.17, -0.04, -0.02), 0.42, 0.42, Vector3(-0.2, 0.0, -0.04)),
		LegPlan.new(2, Vector3(0.17, -0.04, -0.02), 0.42, 0.42, Vector3(0.2, 0.0, -0.04)),
	]
	for i in p.legs.size():
		p.legs[i].step_trigger = 0.38
		p.legs[i].step_lift = 0.2
		p.legs[i].knee_forward = i >= 2     # Rear legs bend backward like hocks.
	p.arms = [
		ArmPlan.new(4, Vector3(-0.24, 0.16, 0.0), 0.3, 0.3),
		ArmPlan.new(4, Vector3(0.24, 0.16, 0.0), 0.3, 0.3),
	]
	p.neck_offset = Vector3(0.0, 0.16, 0.0)
	p.head_offset = Vector3(0.0, 0.13, -0.02)
	p.head_radius = 0.13
	p.ride_height = 0.76
	p.step_time = 0.26
	p.attack_reach = 1.5
	p.body_color = Color(0.45, 0.3, 0.18)
	p.accent_color = Color(0.85, 0.75, 0.55)
	p.collider_radius = 0.55
	p.collider_height = 1.9
	return p


## Wide low body, eight splayed legs, no arms — bites instead.
static func make_spider() -> ProcBodyPlan:
	var p := ProcBodyPlan.new()
	p.form_name = &"spider"
	p.segments = [
		SegmentPlan.new(Vector3(0.0, 0.42, 0.0), 0.24),
	]
	var leg_z := [-0.2, -0.07, 0.07, 0.2]
	var splay := [0.34, 0.4, 0.4, 0.34]
	for row in 4:
		for side in [-1.0, 1.0]:
			var leg := LegPlan.new(
				0,
				Vector3(0.16 * side, 0.05, leg_z[row]),
				0.5, 0.55,
				Vector3(splay[row] * side, 0.0, leg_z[row] * 1.6)
			)
			leg.step_trigger = 0.3
			leg.step_lift = 0.24
			leg.knee_forward = row >= 2
			p.legs.append(leg)
	p.neck_offset = Vector3(0.0, 0.05, -0.2)
	p.head_offset = Vector3(0.0, 0.0, -0.12)
	p.head_radius = 0.14
	p.head_yaw_limit = deg_to_rad(40.0)
	p.head_pitch_limit = deg_to_rad(30.0)
	p.tail_offsets = [Vector3(0.0, 0.06, 0.24)]
	p.tail_radius = 0.2
	p.ride_height = 0.4
	p.step_time = 0.16
	p.stance_pitch_gain = 0.9
	p.stance_roll_gain = 0.8
	p.attack_time = 0.45
	p.attack_reach = 1.1
	p.body_color = Color(0.16, 0.14, 0.18)
	p.accent_color = Color(0.8, 0.2, 0.15)
	p.collider_radius = 0.55
	p.collider_height = 1.1
	return p


## Long segmented body that snakes through turns, a leg pair per segment.
static func make_centipede(body_segments: int = 7) -> ProcBodyPlan:
	var p := ProcBodyPlan.new()
	p.form_name = &"centipede"
	p.segments = [SegmentPlan.new(Vector3(0.0, 0.32, 0.0), 0.15)]
	for i in body_segments - 1:
		p.segments.append(SegmentPlan.new(Vector3(0.0, 0.0, 0.3), 0.15, 0.0, 6.0))
	for seg_i in body_segments:
		for side in [-1.0, 1.0]:
			var leg := LegPlan.new(
				seg_i,
				Vector3(0.1 * side, 0.02, 0.0),
				0.24, 0.28,
				Vector3(0.26 * side, 0.0, 0.0)
			)
			leg.step_trigger = 0.2
			leg.step_lift = 0.12
			p.legs.append(leg)
	p.head_segment = 0
	p.neck_offset = Vector3(0.0, 0.04, -0.16)
	p.head_offset = Vector3(0.0, 0.02, -0.1)
	p.head_radius = 0.14
	p.head_yaw_limit = deg_to_rad(50.0)
	p.head_pitch_limit = deg_to_rad(25.0)
	p.ride_height = 0.3
	p.step_time = 0.14
	p.stance_pitch_gain = 0.4
	p.attack_time = 0.4
	p.attack_reach = 0.9
	p.body_color = Color(0.5, 0.32, 0.1)
	p.accent_color = Color(0.85, 0.6, 0.2)
	p.collider_radius = 0.35
	p.collider_height = 0.8
	return p
