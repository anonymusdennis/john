extends CanvasLayer
## Always-on hotbar + toggleable bag with drag-and-drop onto hotbar.

const InvSlot = preload("res://scripts/inv_slot.gd")

var _hotbar_row: HBoxContainer
var _bag_panel: PanelContainer
var _bag_grid: GridContainer
var _help: Label
var _hotbar_slots: Array = []


func _ready() -> void:
	layer = 20
	_build_ui()
	Inventory.changed.connect(_refresh)
	Inventory.selected_slot_changed.connect(func(_i: int) -> void: _refresh())
	Inventory.inventory_toggled.connect(_on_toggled)
	_refresh()
	_on_toggled(Inventory.is_open)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		Inventory.toggle()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_mouse_capture") and Inventory.is_open:
		Inventory.set_open(false)
		get_viewport().set_input_as_handled()
		return

	if Inventory.is_open:
		return

	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Inventory.select_slot(i)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			Inventory.cycle_slot(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			Inventory.cycle_slot(1)
			get_viewport().set_input_as_handled()


func _on_toggled(open: bool) -> void:
	_bag_panel.visible = open
	_help.visible = not open


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_help = Label.new()
	_help.text = "F5 camera · E inventory · 1-9 / scroll hotbar · LMB use · Esc mouse"
	_help.position = Vector2(16, 16)
	_help.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9, 0.85))
	root.add_child(_help)

	var hotbar_wrap := CenterContainer.new()
	hotbar_wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hotbar_wrap.offset_top = -96
	hotbar_wrap.offset_bottom = -16
	hotbar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hotbar_wrap)

	var hotbar_panel := PanelContainer.new()
	hotbar_wrap.add_child(hotbar_panel)

	_hotbar_row = HBoxContainer.new()
	_hotbar_row.add_theme_constant_override("separation", 4)
	hotbar_panel.add_child(_hotbar_row)

	_hotbar_slots.clear()
	for i in Inventory.HOTBAR_SIZE:
		var slot: Button = InvSlot.new()
		slot.kind = InvSlot.Kind.HOTBAR
		slot.slot_index = i
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		_hotbar_row.add_child(slot)
		_hotbar_slots.append(slot)

	_bag_panel = PanelContainer.new()
	_bag_panel.set_script(preload("res://scripts/bag_drop_target.gd"))
	_bag_panel.visible = false
	_bag_panel.set_anchors_preset(Control.PRESET_CENTER)
	_bag_panel.offset_left = -230
	_bag_panel.offset_top = -280
	_bag_panel.offset_right = 230
	_bag_panel.offset_bottom = 50
	root.add_child(_bag_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	_bag_panel.add_child(margin)

	var bag_vbox := VBoxContainer.new()
	bag_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(bag_vbox)

	var title := Label.new()
	title.text = "Inventory — drag onto hotbar"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 250)
	bag_vbox.add_child(scroll)

	_bag_grid = GridContainer.new()
	_bag_grid.columns = 6
	_bag_grid.add_theme_constant_override("h_separation", 4)
	_bag_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_bag_grid)

	var hint := Label.new()
	hint.text = "Right-click hotbar slot to move back here"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	bag_vbox.add_child(hint)


func _on_slot_clicked(kind: int, index: int) -> void:
	if kind == InvSlot.Kind.HOTBAR:
		Inventory.select_slot(index)


func _on_slot_right_clicked(kind: int, index: int) -> void:
	if kind == InvSlot.Kind.HOTBAR and Inventory.is_open:
		Inventory.move_hotbar_to_bag(index)


func _refresh() -> void:
	for i in _hotbar_slots.size():
		var slot = _hotbar_slots[i]
		slot.slot_index = i
		slot.paint(i == Inventory.selected_slot, i + 1)

	for c in _bag_grid.get_children():
		c.queue_free()

	if Inventory.bag.is_empty():
		var empty := Label.new()
		empty.text = "(empty — pick up potato grenades in the world)"
		empty.modulate = Color(1, 1, 1, 0.55)
		_bag_grid.add_child(empty)
		return

	for i in Inventory.bag.size():
		var slot: Button = InvSlot.new()
		slot.kind = InvSlot.Kind.BAG
		slot.slot_index = i
		slot.paint(false, -1)
		_bag_grid.add_child(slot)
