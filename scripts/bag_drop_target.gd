extends PanelContainer
## Accepts hotbar → bag drops on empty inventory background.


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("from") == "hotbar"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		Inventory.move_hotbar_to_bag(int(data["index"]))
