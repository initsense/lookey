extends Node
class_name LayerUtils

## Sets or clears the bit of a 1-based layer on any bitmask property
## (collision_mask, collision_layer, cull_mask, layers).
static func set_layer_bit(target: Object, property: StringName, layer: int, enabled: bool) -> void:
	var mask: int = target.get(property)
	var bit: int = 1 << (layer - 1)
	target.set(property, (mask | bit) if enabled else (mask & ~bit))


static func set_visibility_layer_recursive(node: Node, layer: int) -> void:
	var mask := 1 << (layer - 1)

	if node is VisualInstance3D:
		node.layers = mask
		print(node.name, " layers: ", node.layers)

	for child in node.get_children():
		set_visibility_layer_recursive(child, layer)


static func set_collision_layer_recursive(node: Node, layer: int) -> void:
	var mask := 1 << (layer - 1)

	if node is CollisionObject3D:
		node.collision_layer = mask
		node.collision_mask = mask

	for child in node.get_children():
		set_collision_layer_recursive(child, layer)
