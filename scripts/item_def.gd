class_name ItemDef
extends RefCounted
## Static item catalog.

const GRENADE := &"grenade"

static var _defs: Dictionary = {
	GRENADE: {
		"name": "Potato Grenade",
		"color": Color(0.72, 0.52, 0.28),
		"max_stack": 16,
		"usable": true,
		"throw_force": 14.0,
	},
}


static func has_id(id: StringName) -> bool:
	return _defs.has(id)


static func display_name(id: StringName) -> String:
	return str(_defs.get(id, {}).get("name", id))


static func color(id: StringName) -> Color:
	return _defs.get(id, {}).get("color", Color.WHITE) as Color


static func max_stack(id: StringName) -> int:
	return int(_defs.get(id, {}).get("max_stack", 64))


static func is_usable(id: StringName) -> bool:
	return bool(_defs.get(id, {}).get("usable", false))


static func throw_force(id: StringName) -> float:
	return float(_defs.get(id, {}).get("throw_force", 12.0))
