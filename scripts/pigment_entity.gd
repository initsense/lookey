@tool
class_name PigmentEntity
extends Node3D
## Turns any 3D object into a colored puzzle object (a manifest-entity or a hidden-entity).
## Attach it to a mesh, a CSG shape, an imported model, or a Node3D that groups several of them:
## every mesh and CSG shape on or under this node gets the pigment's color and render layer, and
## every StaticBody3D under it becomes the entity's collider. This also happens in the editor,
## so the Inspector shows the same material and layers the game uses. No collider yet? Press
## "Generate collider" in the Inspector, or one is generated when the game starts.

## Emitted after generate_collider() replaces this entity's collider bodies.
signal colliders_rebuilt

const GROUP_NAME: StringName = &"pigment_entities"
## Name of the StaticBody3D that generate_collider() creates.
const GENERATED_COLLIDER_NAME: StringName = &"Collider"
## Meshes with more unique vertices than this are sampled through their simplified convex hull
## when mirrors check whether the entity is linked, so detailed models stay cheap.
const MAX_LINK_SAMPLE_POINTS: int = 64
## How many frames to wait for CSG shapes to build their mesh before generating a collider.
const MAX_CSG_BAKE_FRAMES: int = 10
const VERTEX_SNAP: float = 0.0001
## The shared material of each pigment. Edit the files in res://materials/pigments/ to restyle every object of that pigment.
const PIGMENT_MATERIALS: Dictionary[Pigments.Pigment, StandardMaterial3D] = {
	Pigments.Pigment.WHITE: preload("res://materials/pigments/white.tres"),
	Pigments.Pigment.RED: preload("res://materials/pigments/red.tres"),
	Pigments.Pigment.BLUE: preload("res://materials/pigments/blue.tres"),
	Pigments.Pigment.GREEN: preload("res://materials/pigments/green.tres"),
	Pigments.Pigment.YELLOW: preload("res://materials/pigments/yellow.tres"),
	Pigments.Pigment.VIOLET: preload("res://materials/pigments/violet.tres"),
	Pigments.Pigment.ORANGE: preload("res://materials/pigments/orange.tres"),
}

@export_category("Pigment")
## When enabled, this object is a hidden-entity: invisible in the real-world, seen only in the
## reflected-world of a compatible reveal-mirror, and solid only while linked through one.
@export var hidden_entity: bool = false:
	set(value):
		hidden_entity = value
		_config_dirty = true
## The color of this object. Determines which mirrors can reveal or dissolve it (White works with every mirror color).
@export var pigment: Pigments.Pigment = Pigments.Pigment.WHITE:
	set(value):
		pigment = value
		_config_dirty = true

@export_category("Collider")
## Builds a "Collider" body from this object's meshes and CSG shapes and saves it in the scene.
## Press it again after reshaping the object to rebuild the collider.
@export_tool_button("Generate collider", "CollisionShape3D")
var generate_collider_button: Callable = generate_collider

var is_visible_to_mirror: bool = false

## Every mesh and root CSG shape that belongs to this entity.
var geometries: Array[GeometryInstance3D] = []
## Every StaticBody3D that acts as this entity's collider.
var bodies: Array[StaticBody3D] = []
## The first MeshInstance3D of this entity (null for a CSG-only entity).
## Not called "mesh", because that would hide MeshInstance3D.mesh when this script sits on a mesh node.
var mesh_instance: MeshInstance3D
## The first collider body of this entity.
var static_body: StaticBody3D

var _config_dirty: bool = true
var _local_sample_points: Dictionary[GeometryInstance3D, PackedVector3Array] = {}

var _linked_mirrors: Dictionary[Mirror3D, bool] = {}
var _affected_mirrors: Dictionary[Mirror3D, bool] = {}
var _pending_dissolve_restore: bool = false
var _was_affected: bool = false


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_resolve_nodes()
	if not Engine.is_editor_hint():
		_disable_csg_collision()
	_apply_layers_and_material()
	_update_real_world_collider()
	_config_dirty = false
	if not Engine.is_editor_hint() and bodies.is_empty() and not geometries.is_empty():
		_generate_collider_when_ready()


func _process(_delta: float) -> void:
	# In the editor, show the same material and layers the game uses, so the Inspector tells the truth.
	if Engine.is_editor_hint() and _config_dirty:
		_config_dirty = false
		_resolve_nodes()
		_apply_layers_and_material()
		_update_real_world_collider()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _pending_dissolve_restore:
		_try_restore_dissolve_collider()


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED and Engine.is_editor_hint():
		_config_dirty = true
		update_configuration_warnings()


func _set(property: StringName, value: Variant) -> bool:
	# Scenes saved before the rename store "is_invisible"; without this the flag is silently dropped.
	if property == &"is_invisible":
		hidden_entity = value as bool
		return true
	return false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	_resolve_nodes()
	if geometries.is_empty():
		warnings.append("No mesh or CSG shape found on or under this node, so there is nothing for mirrors to show.")
	elif bodies.is_empty():
		warnings.append("No collider yet. Press \"Generate collider\" in the Inspector, or one is generated when the game starts.")
	for geometry: GeometryInstance3D in geometries:
		if geometry is CSGShape3D and (geometry as CSGShape3D).use_collision:
			warnings.append(
				"CSG shape \"%s\" has Use Collision on. It is turned off when the game starts, because this entity's collider decides when the object is solid."
				% geometry.name
			)
	return warnings


func is_hidden_entity() -> bool:
	return hidden_entity


func is_linked() -> bool:
	return not _linked_mirrors.is_empty()


func is_affected() -> bool:
	return not _affected_mirrors.is_empty()


func is_collidable() -> bool:
	if static_body == null:
		return false
	return (static_body.collision_layer & (1 << (Pigments.ENTITY_COLLIDER_LAYER - 1))) != 0


## Returns true when at least one mesh or CSG shape of this entity has geometry mirrors can reflect.
func has_geometry() -> bool:
	for geometry: GeometryInstance3D in geometries:
		if is_instance_valid(geometry) and not _get_local_sample_points(geometry).is_empty():
			return true
	return false


## Returns the world-space box that encloses every mesh and CSG shape of this entity.
func get_world_aabb() -> AABB:
	var merged := AABB()
	var first: bool = true
	for geometry: GeometryInstance3D in geometries:
		if not is_instance_valid(geometry) or _get_local_sample_points(geometry).is_empty():
			continue
		var world_aabb: AABB = geometry.global_transform * geometry.get_aabb()
		if first:
			merged = world_aabb
			first = false
		else:
			merged = merged.merge(world_aabb)
	return merged


## Returns the world-space center of this entity's geometry.
func get_world_center() -> Vector3:
	if not has_geometry():
		return global_position
	return get_world_aabb().get_center()


## Returns the world-space points that mirrors test when checking whether this entity is linked.
func get_link_sample_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for geometry: GeometryInstance3D in geometries:
		if not is_instance_valid(geometry):
			continue
		var geometry_transform: Transform3D = geometry.global_transform
		for local_point: Vector3 in _get_local_sample_points(geometry):
			points.append(geometry_transform * local_point)
	return points


## Returns the physics RIDs of every collider body of this entity.
func get_collision_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for body: StaticBody3D in bodies:
		if is_instance_valid(body):
			rids.append(body.get_rid())
	return rids


## Builds a "Collider" StaticBody3D with one convex collision shape per mesh or CSG shape,
## replacing a previously generated one. In the editor, the new nodes are saved in the scene.
func generate_collider() -> void:
	_resolve_nodes()
	var previous: Node = get_node_or_null(NodePath(String(GENERATED_COLLIDER_NAME)))
	if previous is StaticBody3D:
		remove_child(previous)
		previous.free()

	var scene_owner: Node = _get_edited_scene_owner()
	var body := StaticBody3D.new()
	body.name = GENERATED_COLLIDER_NAME
	body.editor_description = (
		"Solid collider generated from this object's shapes. It blocks the player while the "
		+ "object is solid, and switches off while the object is dissolved or hidden."
	)
	add_child(body, true)
	body.owner = scene_owner
	# Keep the body unscaled in world space so its convex shapes never inherit scale.
	body.global_transform = Transform3D(global_basis.orthonormalized(), global_position)

	for geometry: GeometryInstance3D in geometries:
		var geometry_mesh: Mesh = _get_geometry_mesh(geometry)
		if geometry_mesh == null:
			continue
		var convex: ConvexPolygonShape3D = geometry_mesh.create_convex_shape(true, false)
		if convex == null or convex.points.is_empty():
			continue
		var to_body: Transform3D = body.global_transform.affine_inverse() * geometry.global_transform
		var points: PackedVector3Array = convex.points
		for i: int in range(points.size()):
			points[i] = to_body * points[i]
		convex.points = points

		var shape_node := CollisionShape3D.new()
		shape_node.name = "%sShape" % geometry.name
		shape_node.editor_description = "Collision shape generated from \"%s\"." % geometry.name
		shape_node.shape = convex
		body.add_child(shape_node, true)
		shape_node.owner = scene_owner

	_resolve_nodes()
	_apply_layers_and_material()
	_update_real_world_collider()
	if Engine.is_editor_hint():
		update_configuration_warnings()
	colliders_rebuilt.emit()


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
	geometries.clear()
	bodies.clear()
	mesh_instance = null
	_collect_nodes(self)
	static_body = bodies[0] if not bodies.is_empty() else null
	for geometry: GeometryInstance3D in geometries:
		if geometry is MeshInstance3D:
			mesh_instance = geometry as MeshInstance3D
			break
	_local_sample_points.clear()


func _collect_nodes(node: Node) -> void:
	if node is MeshInstance3D:
		geometries.append(node as MeshInstance3D)
	elif node is CSGShape3D and (node as CSGShape3D).is_root_shape():
		geometries.append(node as CSGShape3D)
	elif node is StaticBody3D:
		bodies.append(node as StaticBody3D)

	for child: Node in node.get_children():
		if child is PigmentEntity:
			continue
		_collect_nodes(child)


func _apply_layers_and_material() -> void:
	var layer: int = Pigments.get_entity_layer(pigment, hidden_entity)
	var material: StandardMaterial3D = PIGMENT_MATERIALS[pigment]

	for geometry: GeometryInstance3D in geometries:
		geometry.material_override = material
		geometry.layers = 0
		LayerUtils.set_layer_bit(geometry, &"layers", layer, true)

	for body: StaticBody3D in bodies:
		body.collision_layer = 0
		LayerUtils.set_layer_bit(body, &"collision_layer", layer, true)
		body.collision_mask = 1 << (Pigments.PLAYER_LAYER - 1)


func _disable_csg_collision() -> void:
	for geometry: GeometryInstance3D in geometries:
		if geometry is CSGShape3D:
			(geometry as CSGShape3D).use_collision = false


func _generate_collider_when_ready() -> void:
	for _frame: int in range(MAX_CSG_BAKE_FRAMES):
		if _all_geometry_meshes_ready():
			break
		await get_tree().process_frame
		if not is_inside_tree():
			return
	if bodies.is_empty():
		generate_collider()


func _all_geometry_meshes_ready() -> bool:
	for geometry: GeometryInstance3D in geometries:
		if _get_geometry_mesh(geometry) == null:
			return false
	return true


func _get_geometry_mesh(geometry: GeometryInstance3D) -> Mesh:
	if geometry is MeshInstance3D:
		var instance_mesh: Mesh = (geometry as MeshInstance3D).mesh
		if instance_mesh != null and instance_mesh.get_surface_count() > 0:
			return instance_mesh
		return null
	if geometry is CSGShape3D:
		var baked: ArrayMesh = (geometry as CSGShape3D).bake_static_mesh()
		if baked != null and baked.get_surface_count() > 0:
			return baked
	return null


func _get_local_sample_points(geometry: GeometryInstance3D) -> PackedVector3Array:
	if _local_sample_points.has(geometry):
		return _local_sample_points[geometry]
	var points: PackedVector3Array = _compute_local_sample_points(geometry)
	# CSG shapes build their mesh a frame late; only cache once there is something to cache.
	if not points.is_empty():
		_local_sample_points[geometry] = points
	return points


func _compute_local_sample_points(geometry: GeometryInstance3D) -> PackedVector3Array:
	var geometry_mesh: Mesh = _get_geometry_mesh(geometry)
	if geometry_mesh == null:
		return PackedVector3Array()

	var unique: Dictionary[Vector3, bool] = {}
	var too_many: bool = false
	for surface: int in range(geometry_mesh.get_surface_count()):
		var arrays: Array = geometry_mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			unique[vertex.snappedf(VERTEX_SNAP)] = true
			if unique.size() > MAX_LINK_SAMPLE_POINTS:
				too_many = true
				break
		if too_many:
			break

	if not too_many:
		return PackedVector3Array(unique.keys())
	var hull: ConvexPolygonShape3D = geometry_mesh.create_convex_shape(true, true)
	return hull.points if hull != null else PackedVector3Array()


func _get_edited_scene_owner() -> Node:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return null
	var scene_root: Node = get_tree().edited_scene_root
	if scene_root != null and (scene_root == self or scene_root.is_ancestor_of(self)):
		return scene_root
	return null


func _update_real_world_collider() -> void:
	if is_hidden_entity():
		_set_entity_collider_enabled(is_affected())
	elif is_affected():
		_set_entity_collider_enabled(false)
	elif not _pending_dissolve_restore:
		_set_entity_collider_enabled(true)


func _set_entity_collider_enabled(enabled: bool) -> void:
	for body: StaticBody3D in bodies:
		LayerUtils.set_layer_bit(
			body,
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

	for shape_node: CollisionShape3D in _get_collision_shapes():
		var player: CharacterBody3D = _find_overlapping_player(shape_node)
		if player:
			_push_player_out(player, shape_node)
			return


func _get_collision_shapes() -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	for body: StaticBody3D in bodies:
		if not is_instance_valid(body):
			continue
		for child: Node in body.get_children():
			var shape_node: CollisionShape3D = child as CollisionShape3D
			if shape_node != null and shape_node.shape != null and not shape_node.disabled:
				shapes.append(shape_node)
	return shapes


func _overlaps_non_player_entity() -> bool:
	for shape_node: CollisionShape3D in _get_collision_shapes():
		var results: Array[Dictionary] = _intersect_shape(
			shape_node,
			1 << (Pigments.ENTITY_COLLIDER_LAYER - 1)
		)
		if not results.is_empty():
			return true
	return false


func _find_overlapping_player(shape_node: CollisionShape3D) -> CharacterBody3D:
	var results: Array[Dictionary] = _intersect_shape(
		shape_node,
		1 << (Pigments.PLAYER_LAYER - 1)
	)
	for result: Dictionary in results:
		var collider: Object = result.get("collider")
		if collider is CharacterBody3D:
			return collider as CharacterBody3D
	return null


func _intersect_shape(shape_node: CollisionShape3D, collision_mask: int) -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	if shape_node == null or shape_node.shape == null or not is_inside_tree():
		return empty

	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return empty

	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = collision_mask
	query.exclude = get_collision_rids()
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var frame := Transform3D(shape_node.global_basis.orthonormalized(), shape_node.global_position)
	var shape_scale: Vector3 = shape_node.global_basis.get_scale().abs()
	var source_shape: Shape3D = shape_node.shape
	query.transform = frame

	if source_shape is BoxShape3D:
		var box := BoxShape3D.new()
		box.size = (source_shape as BoxShape3D).size * shape_scale
		query.shape = box
	elif source_shape is ConvexPolygonShape3D:
		var convex := ConvexPolygonShape3D.new()
		var points: PackedVector3Array = (source_shape as ConvexPolygonShape3D).points
		for i: int in range(points.size()):
			points[i] *= shape_scale
		convex.points = points
		query.shape = convex
	else:
		# Concave and other shapes are queried through their bounding box.
		var bounds: AABB = _get_shape_local_aabb(source_shape)
		var proxy := BoxShape3D.new()
		proxy.size = bounds.size * shape_scale
		query.shape = proxy
		query.transform = frame * Transform3D(Basis.IDENTITY, bounds.get_center() * shape_scale)

	return space_state.intersect_shape(query, 8)


func _get_shape_local_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if points.is_empty():
			return AABB()
		var bounds := AABB(points[0], Vector3.ZERO)
		for point: Vector3 in points:
			bounds = bounds.expand(point)
		return bounds
	var debug_mesh: ArrayMesh = shape.get_debug_mesh()
	return debug_mesh.get_aabb() if debug_mesh != null else AABB()


func _push_player_out(player: CharacterBody3D, shape_node: CollisionShape3D) -> void:
	if shape_node == null or shape_node.shape == null:
		return

	var frame := Transform3D(shape_node.global_basis.orthonormalized(), shape_node.global_position)
	var shape_scale: Vector3 = shape_node.global_basis.get_scale().abs()
	var bounds: AABB = _get_shape_local_aabb(shape_node.shape)
	var center: Vector3 = bounds.get_center() * shape_scale
	var half_extents: Vector3 = bounds.size * shape_scale * 0.5
	var local_player: Vector3 = frame.affine_inverse() * player.global_position - center

	var capsule_radius: float = 0.3
	var capsule: CollisionShape3D = player.get_node_or_null("%CollisionCapsule") as CollisionShape3D
	if capsule and capsule.shape is CapsuleShape3D:
		capsule_radius = (capsule.shape as CapsuleShape3D).radius

	var push_x: float = half_extents.x + capsule_radius - absf(local_player.x)
	var push_z: float = half_extents.z + capsule_radius - absf(local_player.z)
	if push_x <= 0.0 and push_z <= 0.0:
		return

	var local_offset := Vector3.ZERO
	if push_x <= push_z:
		local_offset.x = push_x if local_player.x >= 0.0 else -push_x
	else:
		local_offset.z = push_z if local_player.z >= 0.0 else -push_z

	var world_offset: Vector3 = frame.basis * local_offset
	world_offset.y = 0.0
	player.global_position += world_offset


func _on_visible_on_screen_notifier_3d_screen_entered() -> void:
	is_visible_to_mirror = true


func _on_visible_on_screen_notifier_3d_screen_exited() -> void:
	is_visible_to_mirror = false
