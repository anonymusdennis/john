extends Button
## Draggable inventory / hotbar slot.

enum Kind { BAG, HOTBAR }

@export var kind: Kind = Kind.HOTBAR
@export var slot_index: int = 0

signal slot_clicked(kind: Kind, index: int)
signal slot_right_clicked(kind: Kind, index: int)


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(52, 52)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(kind, slot_index)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(kind, slot_index)
			accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	var stack := _stack()
	if Inventory.is_slot_empty(stack):
		return null
	var data := {
		"from": "bag" if kind == Kind.BAG else "hotbar",
		"index": slot_index,
		"id": stack["id"],
		"count": stack["count"],
	}
	var preview := ColorRect.new()
	preview.size = Vector2(40, 40)
	preview.color = ItemDef.color(stack["id"])
	var label := Label.new()
	label.text = ItemDef.display_name(stack["id"])
	label.position = Vector2(4, 10)
	preview.add_child(label)
	set_drag_preview(preview)
	return data


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("from") and data.has("id")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(Vector2.ZERO, data):
		return
	var from: String = data["from"]
	var from_index: int = int(data["index"])

	if kind == Kind.HOTBAR:
		if from == "bag":
			Inventory.move_bag_to_hotbar(from_index, slot_index)
		elif from == "hotbar":
			Inventory.swap_hotbar(from_index, slot_index)
	elif kind == Kind.BAG:
		if from == "hotbar":
			# Drop onto bag area: stash that hotbar slot.
			Inventory.move_hotbar_to_bag(from_index)


func _stack() -> Dictionary:
	if kind == Kind.HOTBAR:
		return Inventory.get_hotbar_stack(slot_index)
	if slot_index >= 0 and slot_index < Inventory.bag.size():
		return Inventory.bag[slot_index]
	return {}


func paint(selected: bool = false, hotkey: int = -1) -> void:
	var stack := _stack()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.12, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.95, 0.85, 0.25) if selected else Color(0.35, 0.4, 0.35)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)

	if Inventory.is_slot_empty(stack):
		text = str(hotkey) if hotkey > 0 else ""
		modulate = Color.WHITE
		tooltip_text = "Empty"
		return

	var id: StringName = stack["id"]
	var count := int(stack["count"])
	var prefix := ("%d\n" % hotkey) if hotkey > 0 else ""
	text = "%s%s\nx%d" % [prefix, ItemDef.display_name(id).substr(0, 3).to_upper(), count]
	modulate = ItemDef.color(id).lerp(Color.WHITE, 0.2)
	tooltip_text = "%s x%d" % [ItemDef.display_name(id), count]
