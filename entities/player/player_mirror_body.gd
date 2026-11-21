extends Node
## Shows the player's body in mirrors and keeps it out of the first-person view.


func _ready() -> void:
	_show_body_in_mirrors()


func _process(_delta: float) -> void:
	var visual := _visual_root()
	if visual != null and not visual.visible:
		_show_body_in_mirrors()


## Turns the body on for mirror cameras and leaves it off the player's own camera.
func _show_body_in_mirrors() -> void:
	var visual := _visual_root()
	if visual == null:
		return
	visual.visible = true
	_assign_player_layer(visual)
	var camera := get_parent().get_node_or_null("CamHolder/Camera3D") as Camera3D
	if camera != null:
		camera.set_cull_mask_value(Pigments.PLAYER_LAYER, false)


func _visual_root() -> Node3D:
	return get_parent().get_node_or_null("VisualRoot") as Node3D


func _assign_player_layer(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers = 1 << (Pigments.PLAYER_LAYER - 1)
	for child: Node in node.get_children():
		_assign_player_layer(child)
