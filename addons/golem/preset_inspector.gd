@tool
extends EditorInspectorPlugin

const Preset := preload("res://addons/golem/scripts/golem_preset.gd")
const PlayerScript := preload("res://addons/golem/scripts/player_character.gd")

var undo_redo: EditorUndoRedoManager


func _can_handle(object: Object) -> bool:
	return object is Node and object.get_script() == PlayerScript


func _parse_begin(object: Object) -> void:
	var row := PresetRow.new()
	row.player = object
	row.undo_redo = undo_redo
	add_custom_control(row)


class PresetRow:
	extends VBoxContainer

	const Preset := preload("res://addons/golem/scripts/golem_preset.gd")

	var player: Node
	var undo_redo: EditorUndoRedoManager
	var _picker: EditorResourcePicker
	var _busy := false


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 56)
		var title := Label.new()
		title.text = "Golem preset"
		add_child(title)
		_picker = EditorResourcePicker.new()
		_picker.base_type = "GolemPreset"
		_picker.resource_changed.connect(_on_resource)
		add_child(_picker)


	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return _preset_from(data) != null


	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		var preset: Resource = _preset_from(data)
		if preset:
			_apply(preset)


	func _on_resource(resource: Resource) -> void:
		if _busy or not _is_preset(resource):
			return
		_busy = true
		_apply(resource)
		_picker.edited_resource = null
		_busy = false


	func _apply(preset: Resource) -> void:
		if player == null:
			return
		var changes: Array = preset.changes_for(player)
		if changes.is_empty() or undo_redo == null:
			return
		undo_redo.create_action("Apply Golem preset")
		for change: Dictionary in changes:
			var node: Object = change["node"]
			var property := String(change["property"])
			undo_redo.add_do_property(node, property, change["value"])
			undo_redo.add_undo_property(node, property, node.get(property))
		undo_redo.commit_action()


	func _preset_from(data: Variant) -> Resource:
		if _is_preset(data):
			return data
		if data is Dictionary and _is_preset(data.get("resource")):
			return data["resource"]
		if data is Dictionary and data.get("type") == "files":
			var files: PackedStringArray = data["files"]
			if files.size() == 1 and String(files[0]).ends_with(".tres"):
				var loaded: Resource = load(String(files[0]))
				if _is_preset(loaded):
					return loaded
		return null


	func _is_preset(resource: Variant) -> bool:
		return resource is Resource and resource.get_script() == Preset
