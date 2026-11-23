@tool
class_name GolemPreset
extends Resource

const PLAYER_SCRIPT := preload("res://addons/golem/scripts/player_character.gd")
const CAM_SCRIPT := preload("res://addons/golem/scripts/camera/cam_holder.gd")

const CAMERA_MODE := "camera_mode"
const BODY_LAYER := "body_layer"
const BODY_MASK := "body_mask"
const CAMERA_MASK := "camera_mask"
const PROBE_MASK := "probe_mask"
const RAGDOLL_LAYER := "ragdoll_layer"
const RAGDOLL_MASK := "ragdoll_mask"
const CAM_PATH := "CamHolder"
const FLOOR_RAY_PATH := "Raycasts/FloorRaycast"

const EXTRA_KEYS: PackedStringArray = [
	CAMERA_MODE,
	BODY_LAYER,
	BODY_MASK,
	CAMERA_MASK,
	RAGDOLL_LAYER,
	RAGDOLL_MASK,
]

static var _export_names := PackedStringArray()
static var _player_script_props: Array = []
static var _cam_script_props: Array = []

var _values := {}


static func export_names() -> PackedStringArray:
	if not _export_names.is_empty():
		return _export_names
	var names := PackedStringArray()
	for prop: Dictionary in _player_props():
		if _is_export(prop):
			names.append(String(prop["name"]))
	if not names.is_empty():
		_export_names = names
	return names


static func mirrored_names() -> PackedStringArray:
	var names := export_names().duplicate()
	for key: String in EXTRA_KEYS:
		if not names.has(key):
			names.append(key)
	return names


static func capture(player: Node) -> GolemPreset:
	var preset := GolemPreset.new()
	var stored := {}
	for key: String in export_names():
		stored[key] = player.get(key)
	var cam := player.get_node(CAM_PATH)
	stored[CAMERA_MODE] = cam.camera_mode
	stored[BODY_LAYER] = player.collision_layer
	stored[BODY_MASK] = player.collision_mask
	stored[CAMERA_MASK] = cam.collision_mask
	var bones := _ragdoll_bones(player)
	if bones.is_empty():
		push_error("Golem preset found no ragdoll bones on the player.")
	else:
		stored[RAGDOLL_LAYER] = bones[0].collision_layer
		stored[RAGDOLL_MASK] = bones[0].collision_mask
	preset.values = stored
	return preset


func missing_keys() -> PackedStringArray:
	var missing := PackedStringArray()
	for key: String in mirrored_names():
		if not _values.has(key):
			missing.append(key)
	return missing


func changes_for(player: Node) -> Array:
	var missing := missing_keys()
	if not missing.is_empty():
		push_error("Golem preset is missing %s." % ", ".join(missing))
		return []
	var cam := player.get_node(CAM_PATH)
	var floor_ray := player.get_node(FLOOR_RAY_PATH)
	var bones := _ragdoll_bones(player)
	var changes: Array = []
	for key: String in mirrored_names():
		var value: Variant = _values[key]
		match key:
			BODY_LAYER:
				changes.append(_change(player, "collision_layer", value))
			BODY_MASK:
				changes.append(_change(player, "collision_mask", value))
			CAMERA_MASK:
				changes.append(_change(cam, "collision_mask", value))
			CAMERA_MODE:
				changes.append(_change(cam, "camera_mode", value))
			RAGDOLL_LAYER:
				for bone: Node in bones:
					changes.append(_change(bone, "collision_layer", value))
			RAGDOLL_MASK:
				for bone: Node in bones:
					changes.append(_change(bone, "collision_mask", value))
			PROBE_MASK:
				changes.append(_change(player, PROBE_MASK, value))
				changes.append(_change(floor_ray, "collision_mask", value))
			_:
				changes.append(_change(player, key, value))
	return changes


func apply_to(player: Node) -> void:
	for change: Dictionary in changes_for(player):
		var node: Object = change["node"]
		node.set(String(change["property"]), change["value"])


func _get_property_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = [{
		"name": "values",
		"type": TYPE_DICTIONARY,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"usage": PROPERTY_USAGE_STORAGE,
	}]
	var saw_camera_category := false
	for prop: Dictionary in _script_layout(_player_props()):
		list.append(_editor_prop(prop))
		var is_camera := String(prop["name"]) == "Camera" and int(prop["usage"]) & PROPERTY_USAGE_CATEGORY
		if is_camera and not saw_camera_category:
			saw_camera_category = true
			list.append({
				"name": "Camera mode",
				"type": TYPE_NIL,
				"hint": PROPERTY_HINT_NONE,
				"hint_string": "",
				"usage": PROPERTY_USAGE_GROUP,
			})
			var mode := _camera_mode_property()
			if not mode.is_empty():
				list.append(mode)
	if not saw_camera_category:
		var mode := _camera_mode_property()
		if not mode.is_empty():
			list.append(mode)
	for key: String in [BODY_LAYER, BODY_MASK, CAMERA_MASK, RAGDOLL_LAYER, RAGDOLL_MASK]:
		list.append(_layer_prop(key))
	return list


func _get(property: StringName) -> Variant:
	var key := String(property)
	if key == "values":
		return _values
	if _is_mirrored_key(key):
		if _values.has(key):
			return _values[key]
		return _zero(key)
	return null


func _set(property: StringName, value: Variant) -> bool:
	var key := String(property)
	if key == "values":
		_values = value.duplicate(true) if value is Dictionary else {}
		emit_changed()
		return true
	if not _is_mirrored_key(key):
		return false
	_values[key] = value
	emit_changed()
	return true


static func _ragdoll_bones(player: Node) -> Array[Node]:
	var found: Array[Node] = []
	for node in player.find_children("*", "PhysicalBone3D", true, false):
		found.append(node as Node)
	return found


static func _is_export(prop: Dictionary) -> bool:
	if int(prop["type"]) == TYPE_NIL:
		return false
	var usage := int(prop["usage"])
	return usage & PROPERTY_USAGE_EDITOR != 0 and usage & PROPERTY_USAGE_SCRIPT_VARIABLE != 0


static func _is_header(prop: Dictionary) -> bool:
	if int(prop["type"]) != TYPE_NIL:
		return false
	var usage := int(prop["usage"])
	return usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP) != 0


static func _editor_prop(prop: Dictionary) -> Dictionary:
	var raw := int(prop["usage"])
	var usage := PROPERTY_USAGE_EDITOR
	if raw & PROPERTY_USAGE_CATEGORY:
		usage = PROPERTY_USAGE_CATEGORY
	elif raw & PROPERTY_USAGE_GROUP:
		usage = PROPERTY_USAGE_GROUP
	elif raw & PROPERTY_USAGE_SUBGROUP:
		usage = PROPERTY_USAGE_SUBGROUP
	return {
		"name": prop["name"],
		"type": prop["type"],
		"hint": prop["hint"],
		"hint_string": prop["hint_string"],
		"usage": usage,
	}


static func _script_layout(props: Array) -> Array:
	var first := -1
	var last := -1
	for index in props.size():
		if _is_export(props[index]):
			if first == -1:
				first = index
			last = index
	if first == -1:
		return []
	var start := first
	while start > 0 and _is_header(props[start - 1]):
		start -= 1
	var layout: Array = []
	for index in range(start, last + 1):
		var prop: Dictionary = props[index]
		if _is_header(prop) or _is_export(prop):
			layout.append(prop)
	return layout


static func _player_props() -> Array:
	if not _player_script_props.is_empty():
		return _player_script_props
	var temp: Node = PLAYER_SCRIPT.new()
	_player_script_props = temp.get_property_list().duplicate(true)
	temp.free()
	return _player_script_props


static func _cam_props() -> Array:
	if not _cam_script_props.is_empty():
		return _cam_script_props
	var temp: Node = CAM_SCRIPT.new()
	_cam_script_props = temp.get_property_list().duplicate(true)
	temp.free()
	return _cam_script_props


static func _camera_mode_property() -> Dictionary:
	for prop: Dictionary in _cam_props():
		if String(prop["name"]) == CAMERA_MODE and _is_export(prop):
			return _editor_prop(prop)
	return {}


static func _layer_prop(prop_name: String) -> Dictionary:
	return {
		"name": prop_name,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_LAYERS_3D_PHYSICS,
		"hint_string": "",
		"usage": PROPERTY_USAGE_EDITOR,
	}


static func _change(node: Object, property: String, value: Variant) -> Dictionary:
	return {"node": node, "property": property, "value": value}


func _is_mirrored_key(key: String) -> bool:
	return mirrored_names().has(key)


func _zero(key: String) -> Variant:
	for prop: Dictionary in _get_property_list():
		if String(prop["name"]) != key:
			continue
		match int(prop["type"]):
			TYPE_BOOL:
				return false
			TYPE_INT:
				return 0
			TYPE_FLOAT:
				return 0.0
			TYPE_STRING:
				return ""
			TYPE_VECTOR2:
				return Vector2.ZERO
	return null
