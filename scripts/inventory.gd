extends Node
## Minecraft-style bag + 9-slot hotbar.
## Pickups stack into matching hotbar slots first (1-9), then the bag.
## Empty hotbar slots are never auto-filled.

signal changed
signal selected_slot_changed(index: int)
signal inventory_toggled(open: bool)

const HOTBAR_SIZE := 9

## Each entry: {"id": StringName, "count": int} or null/empty dict for empty.
var bag: Array[Dictionary] = []
var hotbar: Array[Dictionary] = []
var selected_slot: int = 0
var is_open: bool = false


func _ready() -> void:
	hotbar.resize(HOTBAR_SIZE)
	for i in HOTBAR_SIZE:
		hotbar[i] = {}


func toggle() -> void:
	set_open(not is_open)


func set_open(open: bool) -> void:
	if is_open == open:
		return
	is_open = open
	if is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	inventory_toggled.emit(is_open)
	changed.emit()


func select_slot(index: int) -> void:
	selected_slot = clampi(index, 0, HOTBAR_SIZE - 1)
	selected_slot_changed.emit(selected_slot)
	changed.emit()


func cycle_slot(delta: int) -> void:
	select_slot(posmod(selected_slot + delta, HOTBAR_SIZE))


func add_item(id: StringName, amount: int = 1) -> int:
	if not ItemDef.has_id(id) or amount <= 0:
		return amount
	var remaining := amount
	remaining = _stack_into_hotbar(id, remaining)
	remaining = _stack_into_bag(id, remaining)
	while remaining > 0:
		var take := mini(ItemDef.max_stack(id), remaining)
		bag.append({"id": id, "count": take})
		remaining -= take
	changed.emit()
	return remaining


func _stack_into_hotbar(id: StringName, amount: int) -> int:
	var remaining := amount
	for i in HOTBAR_SIZE:
		if remaining <= 0:
			break
		var stack := hotbar[i]
		if stack.get("id") != id:
			continue
		var room := ItemDef.max_stack(id) - int(stack.get("count", 0))
		if room <= 0:
			continue
		var take := mini(room, remaining)
		stack["count"] = int(stack["count"]) + take
		hotbar[i] = stack
		remaining -= take
	return remaining


func _stack_into_bag(id: StringName, amount: int) -> int:
	var remaining := amount
	for i in bag.size():
		if remaining <= 0:
			break
		var stack := bag[i]
		if stack.get("id") != id:
			continue
		var room := ItemDef.max_stack(id) - int(stack.get("count", 0))
		if room <= 0:
			continue
		var take := mini(room, remaining)
		stack["count"] = int(stack["count"]) + take
		bag[i] = stack
		remaining -= take
	return remaining


func _add_to_bag_only(id: StringName, amount: int) -> void:
	var remaining := _stack_into_bag(id, amount)
	while remaining > 0:
		var take := mini(ItemDef.max_stack(id), remaining)
		bag.append({"id": id, "count": take})
		remaining -= take
	changed.emit()


func get_hotbar_stack(index: int) -> Dictionary:
	if index < 0 or index >= HOTBAR_SIZE:
		return {}
	return hotbar[index]


func get_selected_stack() -> Dictionary:
	return get_hotbar_stack(selected_slot)


func consume_selected(amount: int = 1) -> bool:
	var stack := get_selected_stack()
	if stack.is_empty():
		return false
	var count := int(stack.get("count", 0))
	if count < amount:
		return false
	count -= amount
	if count <= 0:
		hotbar[selected_slot] = {}
	else:
		stack["count"] = count
		hotbar[selected_slot] = stack
	changed.emit()
	return true


func move_bag_to_hotbar(bag_index: int, hotbar_index: int) -> void:
	if bag_index < 0 or bag_index >= bag.size():
		return
	if hotbar_index < 0 or hotbar_index >= HOTBAR_SIZE:
		return
	var from := bag[bag_index]
	var dest := hotbar[hotbar_index]
	if dest.is_empty():
		hotbar[hotbar_index] = from.duplicate()
		bag.remove_at(bag_index)
	elif dest.get("id") == from.get("id"):
		var max_s := ItemDef.max_stack(from["id"])
		var space := max_s - int(dest.get("count", 0))
		var take := mini(space, int(from.get("count", 0)))
		dest["count"] = int(dest["count"]) + take
		from["count"] = int(from["count"]) - take
		hotbar[hotbar_index] = dest
		if int(from["count"]) <= 0:
			bag.remove_at(bag_index)
		else:
			bag[bag_index] = from
	else:
		# Swap
		hotbar[hotbar_index] = from.duplicate()
		bag[bag_index] = dest.duplicate()
	changed.emit()


func move_hotbar_to_bag(hotbar_index: int) -> void:
	if hotbar_index < 0 or hotbar_index >= HOTBAR_SIZE:
		return
	var stack := hotbar[hotbar_index]
	if stack.is_empty():
		return
	hotbar[hotbar_index] = {}
	_add_to_bag_only(stack["id"], int(stack["count"]))


func swap_hotbar(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= HOTBAR_SIZE or b >= HOTBAR_SIZE or a == b:
		return
	var tmp := hotbar[a]
	hotbar[a] = hotbar[b]
	hotbar[b] = tmp
	changed.emit()


func is_slot_empty(stack: Dictionary) -> bool:
	return stack.is_empty() or int(stack.get("count", 0)) <= 0
