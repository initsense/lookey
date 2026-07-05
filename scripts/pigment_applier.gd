@tool
extends Node3D
## Applies the pigment material and the matching render/collision layers to
## the mesh and static body found under this node.

@export var is_invisible: bool = false
@export var pigment: Pigments.Pigment = Pigments.Pigment.WHITE:
	set(value):
		pigment = value
		config_dirty = true

static var pigment_materials: Dictionary[Pigments.Pigment, StandardMaterial3D] = {}

var config_dirty: bool = true

var mesh: MeshInstance3D
var static_body: StaticBody3D

var _current_material: StandardMaterial3D


func _ready() -> void:
	var layer: int = Pigments.LAYERS[pigment]
	# ponytail: white has no invisible variant, it always stays on layer 1
	if is_invisible and pigment != Pigments.Pigment.WHITE:
		layer += Pigments.INVISIBLE_SHIFT

	await get_tree().process_frame

	mesh = find_node_of_type_anywhere(self, "MeshInstance3D") as MeshInstance3D
	if mesh:
		_current_material = get_pigment_material(pigment)
		mesh.set_surface_override_material(0, _current_material)
		mesh.layers = 0
		Pigments.set_layer_bit(mesh, &"layers", layer, true)

	static_body = find_node_of_type_anywhere(self, "StaticBody3D") as StaticBody3D
	if static_body:
		static_body.collision_layer = 0
		Pigments.set_layer_bit(static_body, &"collision_layer", layer, true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and config_dirty and mesh:
		_current_material = get_pigment_material(pigment)
		mesh.set_surface_override_material(0, _current_material)
		config_dirty = false


## Returns the shared material for a pigment, creating it on first use.
func get_pigment_material(p: Pigments.Pigment) -> StandardMaterial3D:
	if pigment_materials.has(p):
		return pigment_materials[p]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Pigments.COLORS[p]
	pigment_materials[p] = mat
	return mat


func find_node_of_type_anywhere(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.is_class(type_name):
			return child
		var found: Node = find_node_of_type_anywhere(child, type_name)
		if found != null:
			return found
	return null
