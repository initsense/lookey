@tool
class_name PigmentEntity
extends Node3D
## Turns a 3D object into a colored puzzle object (manifest or hidden).
## Sets its material color, puts it on the matching render and physics layers,
## and turns its solid collision on or off when seen through compatible mirrors.

const GROUP_NAME: StringName = &"pigment_entities"

## When enabled, this object starts hidden in the real world and can only be seen and touched through a compatible Reveal mirror.
@export var is_invisible: bool = false
## The color of this object. Determines which mirrors can reveal or dissolve it (White works with every mirror color).
@export var pigment: Pigments.Pigment = Pigments.Pigment.WHITE:
	set(value):
		pigment = value
		_config_dirty = true

static var pigment_materials: Dictionary[Pigments.Pigment, StandardMaterial3D] = {}

var _config_dirty: bool = true
var is_visible_to_mirror: bool = false

var mesh: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D
var _current_material: StandardMaterial3D

var _linked_mirrors: Dictionary[Mirror3D, bool] = {}
var _affected_mirrors: Dictionary[Mirror3D, bool] = {}
var _pending_dissolve_restore: bool = false
var _was_affected: bool = false
var _query_shape: BoxShape3D


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_resolve_nodes()
	_apply_layers_and_material()
	_update_real_world_collider()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _config_dirty and mesh:
		_current_material = _get_pigment_material(pigment)
		mesh.set_surface_override_material(0, _current_material)
		_config_dirty = false


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _pending_dissolve_restore:
		_try_restore_dissolve_collider()


func is_hidden_entity() -> bool:
	return is_invisible


func is_linked() -> bool:
	return not _linked_mirrors.is_empty()


func is_affected() -> bool:
	return not _affected_mirrors.is_empty()


func is_collidable() -> bool:
	if static_body == null:
		return false
	return (static_body.collision_layer & (1 << (Pigments.ENTITY_COLLIDER_LAYER - 1))) != 0


## Updates this entity's link and affect state for one mirror.
func set_mirror_link_state(mirror: Mirror3D, linked: bool, affected: bool) -> void:
	var previously_affected: bool = is_affected()

	if linked:
		_linked_mirrors[mirror] = true
	else:
		_linked_mirrors.erase(mirror)

	if affected:
		_affected_mirrors[mirror] = true
	else:
		_affected_mirrors.erase(mirror)

	var currently_affected: bool = is_affected()
	if currently_affected:
		_pending_dissolve_restore = false

	if not is_hidden_entity():
		if previously_affected and not currently_affected:
			_try_restore_dissolve_collider()
		elif currently_affected:
			_set_entity_collider_enabled(false)
		elif not _pending_dissolve_restore:
			_set_entity_collider_enabled(true)
	else:
		_set_entity_collider_enabled(currently_affected)

	_was_affected = currently_affected


## Clears link/affect state for a mirror that left the tree.
func clear_mirror_link_state(mirror: Mirror3D) -> void:
	set_mirror_link_state(mirror, false, false)


func _resolve_nodes() -> void:
	mesh = _find_node_of_type_anywhere(self, "MeshInstance3D") as MeshInstance3D
	static_body = _find_node_of_type_anywhere(self, "StaticBody3D") as StaticBody3D
	if static_body:
		collision_shape = _find_node_of_type_anywhere(static_body, "CollisionShape3D") as CollisionShape3D


func _apply_layers_and_material() -> void:
	var layer: int = Pigments.get_entity_layer(pigment, is_invisible)

	if mesh:
		_current_material = _get_pigment_material(pigment)
		mesh.set_surface_override_material(0, _current_material)
		mesh.layers = 0
		LayerUtils.set_layer_bit(mesh, &"layers", layer, true)

	if static_body:
		static_body.collision_layer = 0
		LayerUtils.set_layer_bit(static_body, &"collision_layer", layer, true)
		static_body.collision_mask = 1 << (Pigments.PLAYER_LAYER - 1)


func _update_real_world_collider() -> void:
	if is_hidden_entity():
		_set_entity_collider_enabled(is_affected())
	elif is_affected():
		_set_entity_collider_enabled(false)
	elif not _pending_dissolve_restore:
		_set_entity_collider_enabled(true)


func _set_entity_collider_enabled(enabled: bool) -> void:
	if static_body == null:
		return
	LayerUtils.set_layer_bit(
		static_body,
		&"collision_layer",
		Pigments.ENTITY_COLLIDER_LAYER,
		enabled
	)


func _try_restore_dissolve_collider() -> void:
	if is_affected():
		_pending_dissolve_restore = false
		_set_entity_collider_enabled(false)
		return

	if _overlaps_non_player_entity():
		_pending_dissolve_restore = true
		_set_entity_collider_enabled(false)
		return

	_pending_dissolve_restore = false
	_set_entity_collider_enabled(true)

	var player: CharacterBody3D = _find_overlapping_player()
	if player:
		_push_player_out(player)


func _overlaps_non_player_entity() -> bool:
	var results: Array[Dictionary] = _intersect_shape(
		1 << (Pigments.ENTITY_COLLIDER_LAYER - 1)
	)
	return not results.is_empty()


func _find_overlapping_player() -> CharacterBody3D:
	var results: Array[Dictionary] = _intersect_shape(
		1 << (Pigments.PLAYER_LAYER - 1)
	)
	for result: Dictionary in results:
		var collider: Object = result.get("collider")
		if collider is CharacterBody3D:
			return collider as CharacterBody3D
	return null


func _intersect_shape(collision_mask: int) -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	if collision_shape == null or collision_shape.shape == null or static_body == null:
		return empty

	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return empty

	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = collision_mask
	query.exclude = [static_body.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var source_shape: Shape3D = collision_shape.shape
	var global_basis: Basis = collision_shape.global_basis
	var scale: Vector3 = global_basis.get_scale()
	query.transform = Transform3D(global_basis.orthonormalized(), collision_shape.global_position)

	if source_shape is BoxShape3D:
		if _query_shape == null:
			_query_shape = BoxShape3D.new()
		_query_shape.size = (source_shape as BoxShape3D).size * scale.abs()
		query.shape = _query_shape
	else:
		query.shape = source_shape

	return space_state.intersect_shape(query, 8)


func _push_player_out(player: CharacterBody3D) -> void:
	if collision_shape == null or collision_shape.shape == null:
		return
	if not (collision_shape.shape is BoxShape3D):
		return

	var box: BoxShape3D = collision_shape.shape as BoxShape3D
	var scale: Vector3 = collision_shape.global_basis.get_scale().abs()
	var half_extents: Vector3 = box.size * scale * 0.5
	var local_player: Vector3 = (
		collision_shape.global_transform.affine_inverse() * player.global_position
	)

	var capsule_radius: float = 0.3
	var capsule: CollisionShape3D = player.get_node_or_null("%CollisionCapsule") as CollisionShape3D
	if capsule and capsule.shape is CapsuleShape3D:
		capsule_radius = (capsule.shape as CapsuleShape3D).radius

	var dx: float = absf(local_player.x)
	var dz: float = absf(local_player.z)
	var push_x: float = half_extents.x + capsule_radius - dx
	var push_z: float = half_extents.z + capsule_radius - dz
	if push_x <= 0.0 and push_z <= 0.0:
		return

	var local_offset := Vector3.ZERO
	if push_x <= push_z:
		local_offset.x = push_x if local_player.x >= 0.0 else -push_x
	else:
		local_offset.z = push_z if local_player.z >= 0.0 else -push_z

	var world_offset: Vector3 = collision_shape.global_basis.orthonormalized() * local_offset
	world_offset.y = 0.0
	player.global_position += world_offset


## Returns the shared material for a pigment, creating it on first use.
func _get_pigment_material(p: Pigments.Pigment) -> StandardMaterial3D:
	if pigment_materials.has(p):
		return pigment_materials[p]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Pigments.COLORS[p]
	pigment_materials[p] = mat
	return mat


func _find_node_of_type_anywhere(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.is_class(type_name):
			return child
		var found: Node = _find_node_of_type_anywhere(child, type_name)
		if found != null:
			return found
	return null


func _on_visible_on_screen_notifier_3d_screen_entered() -> void:
	is_visible_to_mirror = true


func _on_visible_on_screen_notifier_3d_screen_exited() -> void:
	is_visible_to_mirror = false
