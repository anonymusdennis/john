class_name EnemyBoneMap
extends RefCounted
## Named joint map for the exported enemyrig skeleton.

const TORSO := &"torsobone"
const HEAD := &"neckandhead"

const LEFT_LEG: Array[StringName] = [&"lefthip", &"leftupperleg", &"leftlowerleg"]
const RIGHT_LEG: Array[StringName] = [&"righthip", &"rightupperleg", &"rightlowerleg"]
const LEFT_ARM: Array[StringName] = [&"left_shoulder", &"left_upperarm", &"leftlowerarmandhand"]
const RIGHT_ARM: Array[StringName] = [&"right_shoulder", &"right_upperarm", &"rightlowerarmandhand"]

const ALL: Array[StringName] = [
	TORSO, HEAD,
	&"lefthip", &"leftupperleg", &"leftlowerleg",
	&"righthip", &"rightupperleg", &"rightlowerleg",
	&"left_shoulder", &"left_upperarm", &"leftlowerarmandhand",
	&"right_shoulder", &"right_upperarm", &"rightlowerarmandhand",
]


static func resolve(skeleton: Skeleton3D) -> Dictionary:
	var out := {
		"torso": -1,
		"head": -1,
		"left_leg": [] as Array[int],
		"right_leg": [] as Array[int],
		"left_arm": [] as Array[int],
		"right_arm": [] as Array[int],
		"missing": [] as Array[StringName],
	}
	out["torso"] = skeleton.find_bone(String(TORSO))
	out["head"] = skeleton.find_bone(String(HEAD))
	for n in LEFT_LEG:
		var idx := skeleton.find_bone(String(n))
		out["left_leg"].append(idx)
		if idx < 0:
			out["missing"].append(n)
	for n in RIGHT_LEG:
		var idx := skeleton.find_bone(String(n))
		out["right_leg"].append(idx)
		if idx < 0:
			out["missing"].append(n)
	for n in LEFT_ARM:
		var idx := skeleton.find_bone(String(n))
		out["left_arm"].append(idx)
		if idx < 0:
			out["missing"].append(n)
	for n in RIGHT_ARM:
		var idx := skeleton.find_bone(String(n))
		out["right_arm"].append(idx)
		if idx < 0:
			out["missing"].append(n)
	return out


static func find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var found := find_skeleton(child)
		if found:
			return found
	return null
