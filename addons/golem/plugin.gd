@tool
extends EditorPlugin

const Defaults := preload("res://addons/golem/input_defaults.gd")
const PresetInspector := preload("res://addons/golem/preset_inspector.gd")

var _preset_inspector: PresetInspector


func _enter_tree() -> void:
	_preset_inspector = PresetInspector.new()
	_preset_inspector.undo_redo = get_undo_redo()
	add_inspector_plugin(_preset_inspector)
	_add_missing_actions()


func _exit_tree() -> void:
	if _preset_inspector:
		remove_inspector_plugin(_preset_inspector)
		_preset_inspector = null


func _add_missing_actions() -> void:
	var existing := PackedStringArray()
	for action: String in Defaults.ACTIONS:
		if ProjectSettings.has_setting("input/%s" % action):
			existing.append(action)
	for action: String in Defaults.POINTER_ACTIONS:
		if ProjectSettings.has_setting("input/%s" % action):
			existing.append(action)
	var missing := Defaults.missing_actions(existing)
	var missing_pointer := Defaults.missing_pointer_actions(existing)
	if missing.is_empty() and missing_pointer.is_empty():
		return
	for action: String in missing:
		var event := InputEventKey.new()
		event.physical_keycode = Defaults.ACTIONS[action]
		ProjectSettings.set_setting("input/%s" % action, {
			"deadzone": 0.2,
			"events": [event],
		})
	for action: String in missing_pointer:
		var button := InputEventMouseButton.new()
		button.button_index = Defaults.POINTER_ACTIONS[action]
		ProjectSettings.set_setting("input/%s" % action, {
			"deadzone": 0.2,
			"events": [button],
		})
	ProjectSettings.save()
