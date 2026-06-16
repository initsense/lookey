@tool
extends Node3D

var config_dirty: bool = true

enum Pigment {WHITE, RED, BLUE, GREEN, YELLOW, VIOLET, ORANGE}

@export var is_invisible: bool = false
@export var pigment: Pigment = Pigment.WHITE:
	set(value):
		config_dirty = true
		pigment = value

var _current_material: StandardMaterial3D
static var pigment_materials: Dictionary = {}

var mesh: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D


func _ready() -> void:
	var shift: int = 10 * int(is_invisible)
	var object_layers: Array[int]

	match pigment:
		Pigment.WHITE:  object_layers = [1]
		Pigment.RED:    object_layers = [3 + shift]
		Pigment.BLUE:   object_layers = [4 + shift]
		Pigment.GREEN:  object_layers = [5 + shift]
		Pigment.YELLOW: object_layers = [6 + shift]
		Pigment.VIOLET: object_layers = [7 + shift]
		Pigment.ORANGE: object_layers = [8 + shift]

	await get_tree().process_frame

	mesh = find_node_of_type_anywhere(self, "MeshInstance3D") as MeshInstance3D
	if mesh:
		_current_material = get_pigment_material(pigment)
		mesh.set_surface_override_material(0, _current_material)
		mesh.layers = 0
		set_visual_layers(mesh, object_layers, true)

	static_body = find_node_of_type_anywhere(self, "StaticBody3D") as StaticBody3D
	if static_body:
		static_body.collision_layer = 0
		set_collision_layer(static_body, object_layers, true)

	collision_shape = find_node_of_type_anywhere(self, "CollisionShape3D") as CollisionShape3D


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and config_dirty:
		_current_material = get_pigment_material(pigment)
		mesh.set_surface_override_material(0, _current_material)
		config_dirty = false


func get_pigment_material(p: Pigment) -> StandardMaterial3D:
	if pigment_materials.has(p):
		return pigment_materials[p]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = get_color_for_pigment(p)
	pigment_materials[p] = mat
	return mat


func get_color_for_pigment(p: Pigment) -> Color:
	match p:
		Pigment.WHITE:  return Color(1,1,1)
		Pigment.RED:    return Color(1,0,0)
		Pigment.BLUE:   return Color(0,0,1)
		Pigment.GREEN:  return Color(0,1,0)
		Pigment.YELLOW: return Color(1,1,0)
		Pigment.VIOLET: return Color(0.5,0,0.5)
		Pigment.ORANGE: return Color(1,0.5,0)
	return Color(1,1,1)


func find_node_of_type_anywhere(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.is_class(type_name):
			return child
		var found = find_node_of_type_anywhere(child, type_name)
		if found != null:
			return found
	return null


func set_collision_layer(node: Node3D, layers: Array[int], enabled: bool) -> void:
	for layer in layers:
		var bit := 1 << (layer - 1)
		if enabled: node.collision_layer |= bit
		else:       node.collision_layer &= ~bit


func set_visual_layers(node: VisualInstance3D, layers: Array[int], enabled: bool) -> void:
	for layer in layers:
		var bit := 1 << (layer - 1)
		if enabled: node.layers |= bit
		else:       node.layers &= ~bit
