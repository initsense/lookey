extends CanvasLayer

const SKIP := {
	"pan_rotation_val": true,
	"ragdoll_gravity": true,
}

const JUMP_PROPS := {
	"jump_height": true,
	"jump_time_to_peak": true,
	"jump_time_to_descent": true,
}

const REF_PROPS := {
	"jump_cooldown": "jump_cooldown_ref",
	"coyote_jump_cooldown": "coyote_jump_cooldown_ref",
	"nb_jumps_in_air_allowed": "nb_jumps_in_air_allowed_ref",
}

const CAMERA_PROPS := {
	"first_cam_height": true,
	"third_cam_height": true,
	"first_cam_crouch_height": true,
	"aim_cam_pos": true,
	"first_limit_up": true,
	"first_limit_down": true,
	"third_limit_up": true,
	"third_limit_down": true,
	"zoom_val": true,
}

var _player
var _panel: PanelContainer
var _open := false


func _ready() -> void:
	_player = get_parent().find_child("Player", true, false)
	_panel = PanelContainer.new()
	_panel.name = "OptionsPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.anchor_right = 0.34
	_panel.offset_left = 8.0
	_panel.offset_top = 8.0
	_panel.offset_right = -8.0
	_panel.offset_bottom = -8.0
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_add_header(box, "Options")
	if _player:
		_add_object(box, _player)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("options_menu"):
		return
	_set_open(not _open)
	get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_open = open
	_panel.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _add_object(box: VBoxContainer, obj: Object) -> void:
	var category := ""
	var group := ""
	var subgroup := ""
	var shown_category := ""
	var shown_group := ""
	for prop: Dictionary in obj.get_property_list():
		var header := _header_kind(prop)
		if header == "category":
			category = String(prop["name"])
			group = ""
			subgroup = ""
			continue
		if header == "group":
			group = String(prop["name"])
			subgroup = ""
			continue
		if header == "subgroup":
			subgroup = String(prop["name"])
			continue
		if not _include_export(prop):
			continue
		if category != "" and category != shown_category:
			_add_header(box, category)
			shown_category = category
		if group != "" and group != shown_group:
			_add_header(box, group)
			shown_group = group
		if subgroup != "":
			_add_header(box, subgroup)
			subgroup = ""
		_add_control(box, obj, prop)


func _include_export(prop: Dictionary) -> bool:
	var usage := int(prop["usage"])
	if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or usage & PROPERTY_USAGE_EDITOR == 0:
		return false
	var prop_name := String(prop["name"])
	if SKIP.has(prop_name):
		return false
	var prop_type := int(prop["type"])
	return prop_type == TYPE_BOOL or prop_type == TYPE_INT or prop_type == TYPE_FLOAT or prop_type == TYPE_VECTOR2


func _header_kind(prop: Dictionary) -> String:
	if int(prop["type"]) != TYPE_NIL:
		return ""
	var usage := int(prop["usage"])
	if usage & PROPERTY_USAGE_CATEGORY:
		return "category"
	if usage & PROPERTY_USAGE_GROUP:
		return "group"
	if usage & PROPERTY_USAGE_SUBGROUP:
		return "subgroup"
	return ""


func _add_header(box: VBoxContainer, title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 18)
	box.add_child(label)


func _add_control(box: VBoxContainer, obj: Object, prop: Dictionary) -> void:
	var prop_name := String(prop["name"])
	var prop_type := int(prop["type"])
	var hint := int(prop["hint"])
	var hint_string := String(prop["hint_string"])
	if prop_type == TYPE_BOOL:
		_add_bool(box, obj, prop_name)
	elif prop_type == TYPE_VECTOR2:
		_add_vector2(box, obj, prop_name)
	elif hint == PROPERTY_HINT_ENUM:
		_add_enum(box, obj, prop_name, hint_string)
	elif hint == PROPERTY_HINT_RANGE:
		_add_slider(box, obj, prop_name, prop_type, hint_string)
	else:
		_add_spin(box, obj, prop_name, prop_type)


func _add_bool(box: VBoxContainer, obj: Object, prop_name: String) -> void:
	var row := _row(box, _check_label(prop_name))
	var check := CheckBox.new()
	check.name = prop_name
	check.button_pressed = bool(obj.get(prop_name))
	check.toggled.connect(func(on: bool) -> void:
		obj.set(prop_name, on)
		_after_write(obj, prop_name)
	)
	row.add_child(check)


func _add_enum(box: VBoxContainer, obj: Object, prop_name: String, hint_string: String) -> void:
	var row := _row(box, prop_name)
	var button := OptionButton.new()
	button.name = prop_name
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for piece in hint_string.split(","):
		var text := piece
		var id := button.item_count
		if piece.contains(":"):
			var parts := piece.rsplit(":", true, 1)
			text = parts[0]
			id = int(parts[1])
		button.add_item(text, id)
	var current := int(obj.get(prop_name))
	for index in button.item_count:
		if button.get_item_id(index) == current:
			button.select(index)
			break
	button.item_selected.connect(func(index: int) -> void:
		obj.set(prop_name, button.get_item_id(index))
		_after_write(obj, prop_name)
	)
	row.add_child(button)


func _add_slider(box: VBoxContainer, obj: Object, prop_name: String, prop_type: int, hint_string: String) -> void:
	var parsed := _parse_range(hint_string, prop_type)
	var row := _row(box, prop_name)
	var slider := HSlider.new()
	slider.name = prop_name
	slider.min_value = float(parsed["min"])
	slider.max_value = float(parsed["max"])
	slider.step = float(parsed["step"])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(140, 0)
	var current: float = float(obj.get(prop_name))
	if bool(parsed["radians"]):
		current = rad_to_deg(current)
	slider.value = current
	slider.value_changed.connect(func(value: float) -> void:
		var stored: float = deg_to_rad(value) if bool(parsed["radians"]) else value
		if prop_type == TYPE_INT:
			obj.set(prop_name, int(stored))
		else:
			obj.set(prop_name, stored)
		_after_write(obj, prop_name)
	)
	row.add_child(slider)


func _add_spin(box: VBoxContainer, obj: Object, prop_name: String, prop_type: int) -> void:
	var row := _row(box, prop_name)
	var spin := _spin(prop_type)
	spin.name = prop_name
	spin.value = float(obj.get(prop_name))
	spin.value_changed.connect(func(value: float) -> void:
		if prop_type == TYPE_INT:
			obj.set(prop_name, int(value))
		else:
			obj.set(prop_name, value)
		_after_write(obj, prop_name)
	)
	row.add_child(spin)


func _add_vector2(box: VBoxContainer, obj: Object, prop_name: String) -> void:
	var current: Vector2 = obj.get(prop_name)
	for axis in ["x", "y"]:
		var row := _row(box, prop_name + " " + axis)
		var spin := _spin(TYPE_FLOAT)
		spin.name = prop_name + "_" + axis
		spin.value = float(current[axis])
		spin.value_changed.connect(_on_vector_axis.bind(obj, prop_name, axis))
		row.add_child(spin)


func _on_vector_axis(value: float, obj: Object, prop_name: String, axis: String) -> void:
	var vector: Vector2 = obj.get(prop_name)
	vector[axis] = value
	obj.set(prop_name, vector)
	_after_write(obj, prop_name)


func _check_label(prop_name: String) -> String:
	var titled := prop_name.capitalize()
	if titled.begins_with("Can "):
		return titled
	return "Can " + titled


func _row(box: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title.replace("_", " ")
	label.custom_minimum_size = Vector2(180, 0)
	row.add_child(label)
	box.add_child(row)
	return row


func _spin(prop_type: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.allow_greater = true
	spin.allow_lesser = true
	if prop_type == TYPE_INT:
		spin.step = 1.0
		spin.rounded = true
	else:
		spin.step = 0.01
	return spin


func _parse_range(hint_string: String, prop_type: int) -> Dictionary:
	var parts := hint_string.split(",")
	var step := 1.0 if prop_type == TYPE_INT else 0.01
	if parts.size() > 2 and parts[2].is_valid_float():
		step = float(parts[2])
	var radians := false
	for part in parts:
		if part.strip_edges() == "radians_as_degrees":
			radians = true
	return {
		"min": float(parts[0]),
		"max": float(parts[1]),
		"step": step,
		"radians": radians,
	}


func _after_write(_obj: Object, prop_name: String) -> void:
	_refresh_player(prop_name)


func _refresh_player(prop_name: String) -> void:
	if _player == null:
		return
	if JUMP_PROPS.has(prop_name):
		var height: float = _player.jump_height
		var peak: float = _player.jump_time_to_peak
		var descent: float = _player.jump_time_to_descent
		if peak != 0.0:
			_player.jump_gravity = ((-2.0 * height) / (peak * peak)) * -1.0
			_player.jump_velocity = ((2.0 * height) / peak) * -1.0
		if descent != 0.0:
			_player.fall_gravity = ((-2.0 * height) / (descent * descent)) * -1.0
	if REF_PROPS.has(prop_name):
		_player.set(String(REF_PROPS[prop_name]), _player.get(prop_name))
	if CAMERA_PROPS.has(prop_name):
		var holder = _player.cam_holder
		if holder == null:
			return
		if prop_name == "zoom_val":
			var zoom: float = _player.zoom_val
			holder.curr_zoom = zoom
			holder.last_zoom_val = zoom
		holder.set_camera_mode(holder.camera_mode, true)
