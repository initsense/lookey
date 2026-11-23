@tool
class_name PigmentEntity
extends Node3D
## Turns any 3D object into a colored puzzle object (a manifest-entity or a hidden-entity).
## Put this on the object, or add an empty one as a child of the object you want to color,
## including a mesh that already has its own script, such as a UniBuilder mesh. Every visible
## shape on that object gets the pigment's render layer, so reveal and dissolve mirrors can
## hide or show it. Colliders turn solid or not with those mirrors. You can leave the color
## as the shared pigment material, or assign your own. Adding this node in the editor paints
## that color immediately. A hidden object keeps its hidden layer, and the editor view still
## shows it because the editor camera draws every layer.
## No collider yet? Press "Generate collider" in the Inspector, or one is generated when the game starts.

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
		if Engine.is_editor_hint() and is_inside_tree():
			_refresh_config()
## The color of this object. Determines which mirrors can reveal or dissolve it (White works with every mirror color).
@export var pigment: Pigments.Pigment = Pigments.Pigment.WHITE:
	set(value):
		pigment = value
		_config_dirty = true
		if Engine.is_editor_hint() and is_inside_tree():
			_refresh_config()
## Material painted on this object's shapes. Leave empty to use the shared color of the pigment above.
## Assigning one does not change which mirrors can reveal or dissolve the object.
@export var surface_material: Material:
	set(value):
		surface_material = value
		_config_dirty = true
		if Engine.is_editor_hint() and is_inside_tree():
			_refresh_config()

@export_category("Collider")
## Builds a "Collider" body from this object's shapes and saves it in the scene.
## Press it again after reshaping the object to rebuild the collider.
@export_tool_button("Generate collider", "CollisionShape3D")
var generate_collider_button: Callable = generate_collider

var is_visible_to_mirror: bool = false

## Every shape that mirrors can reflect and paint: meshes, root CSG, multimeshes, sprites, labels, and particles.
var geometries: Array[GeometryInstance3D] = []
## Every collider on this object, including areas. Areas are not the solid body the player bumps into.
var bodies: Array[CollisionObject3D] = []
## The first MeshInstance3D of this entity (null for a CSG-only entity).
## Not called "mesh", because that would hide MeshInstance3D.mesh when this script sits on a mesh node.
var mesh_instance: MeshInstance3D
## The first static collider of this entity, including animatable bodies. Null when the only collider is a rigid body or a character body.
var static_body: StaticBody3D

var _visuals: Array[VisualInstance3D] = []
var _config_dirty: bool = true
var _refreshing: bool = false
var _local_sample_points: Dictionary[GeometryInstance3D, PackedVector3Array] = {}
var _watched_nodes: Array[Node] = []

var _linked_mirrors: Dictionary[Mirror3D, bool] = {}
var _affected_mirrors: Dictionary[Mirror3D, bool] = {}
var _pending_dissolve_restore: bool = false
var _was_affected: bool = false
## Look each painted shape had before this entity first changed it.
var _painted_look: Dictionary = {}
## True while this node is leaving the tree, so a refresh cannot paint over a restore.
var _leaving: bool = false
## True when the parent is leaving too. Closing the scene must not put the old look back.
var _parent_leaving: bool = false
var _parent_exit_watched: Node = null


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_refresh_config()
	if not Engine.is_editor_hint():
		_disable_csg_collision()
		if (
			not _has_blocking_body()
			and not _external_collider_provides_body()
			and not geometries.is_empty()
		):
			# A child component's _ready runs while its parent is still entering the tree.
			if _controlled_root() == self:
				_generate_collider_when_ready()
			else:
				_generate_collider_when_ready.call_deferred()


func _exit_tree() -> void:
	_leaving = true
	_release_painted_parent()
	_unwatch_parent_exit()
	_unwatch_tree()


func _process(_delta: float) -> void:
	# In the editor, show the same material and layers the game uses, so the Inspector tells the truth.
	if not Engine.is_editor_hint():
		return
	if _config_dirty or _material_was_overwritten():
		_refresh_config()
		update_configuration_warnings()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _pending_dissolve_restore:
		_try_restore_dissolve_collider()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		# Dragging this node onto another object does not run _ready again.
		_leaving = false
		_parent_leaving = false
		_watch_parent_exit()
		_refresh_config()
	elif what == NOTIFICATION_CHILD_ORDER_CHANGED and Engine.is_editor_hint():
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
	var parent := get_parent()
	if parent != null and _earlier_sibling_adopts_parent(parent):
		warnings.append("Another pigment entity already colors this object.")
		return warnings
	_resolve_nodes()
	if geometries.is_empty():
		warnings.append(
			"No visible shape found on this object, so there is nothing for mirrors to show."
		)
	elif not _has_blocking_body() and not _external_collider_provides_body():
		warnings.append(
			"No collider yet. Press \"Generate collider\" in the Inspector, or one is generated when the game starts."
		)
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


## Returns true when a solid collider on this object is currently blocking other entities.
func is_collidable() -> bool:
	var bit: int = 1 << (Pigments.ENTITY_COLLIDER_LAYER - 1)
	for body: CollisionObject3D in _blocking_bodies():
		if (body.collision_layer & bit) != 0:
			return true
	return false


## Returns true when at least one shape of this entity has geometry mirrors can reflect.
func has_geometry() -> bool:
	for geometry: GeometryInstance3D in geometries:
		if is_instance_valid(geometry) and not _get_local_sample_points(geometry).is_empty():
			return true
	return false


## Returns the world-space box that encloses every shape of this entity.
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
		return _controlled_root_3d().global_position
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
		# Hull corners of a large shape can all miss a mirror while the middle of a face is in the glass.
		var bounds: AABB = geometry.get_aabb()
		if not bounds.size.is_zero_approx():
			points.append(geometry_transform * bounds.get_center())
	return points


## Returns the physics RIDs of every collider of this entity.
func get_collision_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for body: CollisionObject3D in bodies:
		if is_instance_valid(body):
			rids.append(body.get_rid())
	return rids


## Builds a "Collider" StaticBody3D with one convex collision shape per mesh or CSG shape,
## replacing a previously generated one. In the editor, the new nodes are saved in the scene.
## The body is parented to the object this entity controls, which may be the parent node.
func generate_collider() -> void:
	_resolve_nodes()
	if _external_collider_provides_body():
		push_warning(
			"This object already builds its own collider, so a second one was not generated."
		)
		_apply_layers_and_material()
		_update_real_world_collider()
		return

	_refreshing = true
	var root: Node3D = _controlled_root_3d()
	for host: Node in [root, self]:
		var previous: Node = host.get_node_or_null(NodePath(String(GENERATED_COLLIDER_NAME)))
		if previous is StaticBody3D:
			host.remove_child(previous)
			previous.free()

	var scene_owner: Node = _get_edited_scene_owner()
	var body := StaticBody3D.new()
	body.name = GENERATED_COLLIDER_NAME
	body.editor_description = (
		"Solid collider generated from this object's shapes. It blocks the player while the "
		+ "object is solid, and switches off while the object is dissolved or hidden."
	)
	root.add_child(body, true)
	body.owner = scene_owner
	# Keep the body unscaled in world space so its convex shapes never inherit scale.
	body.global_transform = Transform3D(root.global_basis.orthonormalized(), root.global_position)

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

	_refreshing = false
	_refresh_config()
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


## The material drawn on this object's shapes: the assigned one, or the shared pigment color.
func get_resolved_material() -> Material:
	if surface_material != null:
		return surface_material
	return PIGMENT_MATERIALS[pigment]


func _refresh_config() -> void:
	if _refreshing or _leaving or not is_inside_tree():
		return
	_refreshing = true
	_resolve_nodes()
	_remember_painted_nodes()
	_apply_layers_and_material()
	_update_real_world_collider()
	_watch_tree()
	_config_dirty = false
	_refreshing = false


func _resolve_nodes() -> void:
	geometries.clear()
	bodies.clear()
	_visuals.clear()
	mesh_instance = null
	static_body = null
	_collect_nodes(_controlled_root())
	for body: CollisionObject3D in bodies:
		if body is StaticBody3D:
			static_body = body as StaticBody3D
			break
	for geometry: GeometryInstance3D in geometries:
		if geometry is MeshInstance3D:
			mesh_instance = geometry as MeshInstance3D
			break
	_local_sample_points.clear()


## The node whose shapes this entity colors. An empty pigment node uses its parent.
## The earlier empty sibling owns that parent; a later one leaves it alone.
func _controlled_root() -> Node:
	if _subtree_has_content(self):
		return self
	var parent: Node = get_parent()
	if parent == null or _earlier_sibling_adopts_parent(parent):
		return self
	return parent


## True when an earlier pigment sibling has no shapes of its own and therefore colors this parent.
## Sibling order only: asking the other entity for its controlled root would recurse.
func _earlier_sibling_adopts_parent(parent: Node) -> bool:
	for child: Node in parent.get_children():
		if child == self:
			return false
		if child is PigmentEntity and not (child as PigmentEntity)._subtree_has_content(child):
			return true
	return false


func _controlled_root_3d() -> Node3D:
	var root: Node = _controlled_root()
	return root as Node3D if root is Node3D else self


func _subtree_has_content(node: Node) -> bool:
	if _node_is_content(node):
		return true
	for child: Node in node.get_children():
		if child is PigmentEntity:
			continue
		if _subtree_has_content(child):
			return true
	return false


func _node_is_content(node: Node) -> bool:
	if node is VisibleOnScreenNotifier3D or node is Mirror3D:
		return false
	if node is CSGShape3D and not (node as CSGShape3D).is_root_shape():
		return false
	return node is VisualInstance3D or node is CollisionObject3D


func _is_adopted_by_other(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is PigmentEntity and child != self:
			if (child as PigmentEntity)._controlled_root() == node:
				return true
	return false


func _collect_nodes(node: Node) -> void:
	if node is Mirror3D:
		return
	if node is PigmentEntity and node != self:
		return
	if node != _controlled_root() and _is_adopted_by_other(node):
		return

	_collect_one(node)
	for child: Node in node.get_children():
		if child is PigmentEntity:
			continue
		_collect_nodes(child)


func _collect_one(node: Node) -> void:
	if node is VisibleOnScreenNotifier3D:
		return
	if node is CSGShape3D and not (node as CSGShape3D).is_root_shape():
		return
	if node is VisualInstance3D:
		_visuals.append(node as VisualInstance3D)
	if _uses_material_override(node):
		geometries.append(node as GeometryInstance3D)
	if node is CollisionObject3D:
		bodies.append(node as CollisionObject3D)


func _uses_material_override(node: Node) -> bool:
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		return true
	if node is SpriteBase3D or node is Label3D:
		return true
	if node is GPUParticles3D or node is CPUParticles3D:
		return true
	return node is CSGShape3D and (node as CSGShape3D).is_root_shape()


## Stores the look of each shape the first time this entity paints it, including shapes that appear later.
func _remember_painted_nodes() -> void:
	for visual: VisualInstance3D in _visuals:
		_remember_painted_node(visual)
	for geometry: GeometryInstance3D in geometries:
		_remember_painted_node(geometry)
	for body: CollisionObject3D in bodies:
		_remember_painted_node(body)


func _remember_painted_node(node: Node) -> void:
	if not is_instance_valid(node) or _painted_look.has(node):
		return
	var look := {}
	if node is VisualInstance3D:
		look["layers"] = (node as VisualInstance3D).layers
	if node is GeometryInstance3D:
		look["material_override"] = (node as GeometryInstance3D).material_override
	if node is CSGShape3D:
		look["csg_material"] = (node as CSGShape3D).material
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		look["collision_layer"] = body.collision_layer
		look["collision_mask"] = body.collision_mask
	if _is_self_colliding_mesh(node):
		look["ub_collision_layer"] = int(node.get(&"collision_layer"))
		look["ub_collision_mask"] = int(node.get(&"collision_mask"))
	_painted_look[node] = look


## Puts back the look saved before the first paint. The generated collider node stays.
func _restore_painted_look() -> void:
	for node: Variant in _painted_look.keys():
		if not is_instance_valid(node):
			continue
		var look: Dictionary = _painted_look[node]
		if node is VisualInstance3D and look.has("layers"):
			(node as VisualInstance3D).layers = int(look["layers"])
		if node is GeometryInstance3D and look.has("material_override"):
			(node as GeometryInstance3D).material_override = look["material_override"] as Material
		if node is CSGShape3D and look.has("csg_material"):
			(node as CSGShape3D).material = look["csg_material"] as Material
		if node is CollisionObject3D and look.has("collision_layer"):
			var body := node as CollisionObject3D
			body.collision_layer = int(look["collision_layer"])
			body.collision_mask = int(look["collision_mask"])
		if look.has("ub_collision_layer"):
			var painted := node as Object
			painted.set(&"collision_layer", int(look["ub_collision_layer"]))
			painted.set(&"collision_mask", int(look["ub_collision_mask"]))
	_painted_look.clear()


## Restores the painted shapes only when the parent stays in the tree.
func _release_painted_parent() -> void:
	var parent := get_parent()
	if parent != null and is_instance_valid(parent) and parent.is_inside_tree() and not _parent_leaving:
		_restore_painted_look()
	else:
		_painted_look.clear()


func _watch_parent_exit() -> void:
	var parent := get_parent()
	if parent == _parent_exit_watched:
		return
	_unwatch_parent_exit()
	if parent == null:
		return
	_parent_exit_watched = parent
	if not parent.tree_exiting.is_connected(_on_parent_tree_exiting):
		parent.tree_exiting.connect(_on_parent_tree_exiting)


func _unwatch_parent_exit() -> void:
	var parent := _parent_exit_watched
	_parent_exit_watched = null
	if parent != null and is_instance_valid(parent) and parent.tree_exiting.is_connected(_on_parent_tree_exiting):
		parent.tree_exiting.disconnect(_on_parent_tree_exiting)


func _on_parent_tree_exiting() -> void:
	_parent_leaving = true


func _apply_layers_and_material() -> void:
	var layer: int = Pigments.get_entity_layer(pigment, hidden_entity)
	var material: Material = get_resolved_material()

	for visual: VisualInstance3D in _visuals:
		if not is_instance_valid(visual):
			continue
		visual.layers = 0
		LayerUtils.set_layer_bit(visual, &"layers", layer, true)

	for geometry: GeometryInstance3D in geometries:
		if not is_instance_valid(geometry):
			continue
		geometry.material_override = material
		# CSG brushes tint from their own material slot; material_override alone often stays gray in the editor.
		if geometry is CSGShape3D:
			(geometry as CSGShape3D).material = material

	var player_mask: int = 1 << (Pigments.PLAYER_LAYER - 1)
	for body: CollisionObject3D in bodies:
		if not is_instance_valid(body):
			continue
		body.collision_layer = 0
		LayerUtils.set_layer_bit(body, &"collision_layer", layer, true)
		# Static and animatable bodies only need to be detected by the player.
		# Moving bodies keep their mask so they still land on the floor.
		if body is StaticBody3D:
			body.collision_mask = player_mask


func _material_was_overwritten() -> bool:
	var material: Material = get_resolved_material()
	for geometry: GeometryInstance3D in geometries:
		if is_instance_valid(geometry) and geometry.material_override != material:
			return true
	return false


func _sync_unibuilder_collision(solid: bool) -> void:
	var pigment_layer: int = Pigments.get_entity_layer(pigment, hidden_entity)
	var layer_mask: int = 1 << (pigment_layer - 1)
	if solid:
		layer_mask |= 1 << (Pigments.ENTITY_COLLIDER_LAYER - 1)
	var player_mask: int = 1 << (Pigments.PLAYER_LAYER - 1)
	for geometry: GeometryInstance3D in geometries:
		if not _is_self_colliding_mesh(geometry):
			continue
		if int(geometry.get(&"collision_layer")) != layer_mask:
			geometry.set(&"collision_layer", layer_mask)
		if int(geometry.get(&"collision_mask")) != player_mask:
			geometry.set(&"collision_mask", player_mask)


func _is_self_colliding_mesh(node: Node) -> bool:
	return (
		node.has_method(&"refresh_collision")
		and node.get(&"collision_mode") != null
		and node.get(&"collision_layer") != null
		and node.get(&"collision_mask") != null
	)


func _external_collider_provides_body() -> bool:
	for geometry: GeometryInstance3D in geometries:
		if _is_self_colliding_mesh(geometry) and int(geometry.get(&"collision_mode")) != 0:
			return true
	return false


func _has_blocking_body() -> bool:
	return not _blocking_bodies().is_empty()


func _blocking_bodies() -> Array[CollisionObject3D]:
	var blocking: Array[CollisionObject3D] = []
	for body: CollisionObject3D in bodies:
		if is_instance_valid(body) and body is PhysicsBody3D:
			blocking.append(body)
	return blocking


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
	if _has_blocking_body() or _external_collider_provides_body():
		return
	if not geometries.is_empty():
		generate_collider()


func _all_geometry_meshes_ready() -> bool:
	for geometry: GeometryInstance3D in geometries:
		if geometry is MeshInstance3D or geometry is CSGShape3D or geometry is MultiMeshInstance3D:
			if _get_geometry_mesh(geometry) == null:
				return false
	return true


func _get_geometry_mesh(geometry: GeometryInstance3D) -> Mesh:
	if geometry is MeshInstance3D:
		var instance_mesh: Mesh = (geometry as MeshInstance3D).mesh
		if instance_mesh != null and instance_mesh.get_surface_count() > 0:
			return instance_mesh
		return null
	if geometry is MultiMeshInstance3D:
		var multi_mesh: MultiMesh = (geometry as MultiMeshInstance3D).multimesh
		if multi_mesh != null and multi_mesh.mesh != null and multi_mesh.mesh.get_surface_count() > 0:
			return multi_mesh.mesh
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
	if geometry is MultiMeshInstance3D:
		return _multi_mesh_sample_points(geometry as MultiMeshInstance3D)
	var geometry_mesh: Mesh = _get_geometry_mesh(geometry)
	if geometry_mesh != null:
		return _points_from_mesh(geometry_mesh)
	if geometry is MeshInstance3D or geometry is CSGShape3D:
		return PackedVector3Array()
	return _aabb_corner_points(geometry)


func _multi_mesh_sample_points(instance: MultiMeshInstance3D) -> PackedVector3Array:
	var geometry_mesh: Mesh = _get_geometry_mesh(instance)
	var local: PackedVector3Array = (
		_points_from_mesh(geometry_mesh) if geometry_mesh != null else _aabb_corner_points(instance)
	)
	var multi_mesh: MultiMesh = instance.multimesh
	if multi_mesh == null or multi_mesh.instance_count <= 0 or local.is_empty():
		return local
	var points := PackedVector3Array()
	var instance_count: int = mini(multi_mesh.instance_count, MAX_LINK_SAMPLE_POINTS)
	for index: int in instance_count:
		points.append(multi_mesh.get_instance_transform(index) * local[0])
	return points


func _points_from_mesh(geometry_mesh: Mesh) -> PackedVector3Array:
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


func _aabb_corner_points(geometry: GeometryInstance3D) -> PackedVector3Array:
	var bounds: AABB = geometry.get_aabb()
	if bounds.size.is_zero_approx():
		return PackedVector3Array()
	var origin: Vector3 = bounds.position
	var size: Vector3 = bounds.size
	return PackedVector3Array([
		origin,
		origin + Vector3(size.x, 0.0, 0.0),
		origin + Vector3(0.0, size.y, 0.0),
		origin + Vector3(0.0, 0.0, size.z),
		origin + Vector3(size.x, size.y, 0.0),
		origin + Vector3(size.x, 0.0, size.z),
		origin + Vector3(0.0, size.y, size.z),
		origin + size,
	])


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
	for body: CollisionObject3D in bodies:
		if not is_instance_valid(body):
			continue
		LayerUtils.set_layer_bit(
			body,
			&"collision_layer",
			Pigments.ENTITY_COLLIDER_LAYER,
			enabled
		)
	_sync_unibuilder_collision(enabled)


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
	for body: CollisionObject3D in _blocking_bodies():
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


func _watch_tree() -> void:
	var needed: Array[Node] = []
	_gather_watch_nodes(_controlled_root(), needed)
	var still: Array[Node] = []
	for node: Node in _watched_nodes:
		if not is_instance_valid(node) or not needed.has(node):
			_disconnect_watch(node)
		else:
			still.append(node)
	_watched_nodes = still
	for node: Node in needed:
		if _watched_nodes.has(node):
			continue
		_connect_watch(node)
		_watched_nodes.append(node)


func _gather_watch_nodes(node: Node, into: Array[Node]) -> void:
	if not is_instance_valid(node):
		return
	if node is Mirror3D:
		return
	if node is PigmentEntity and node != self:
		return
	if node != _controlled_root() and _is_adopted_by_other(node):
		return
	into.append(node)
	for child: Node in node.get_children():
		if child is PigmentEntity:
			continue
		_gather_watch_nodes(child, into)


func _connect_watch(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if not node.child_entered_tree.is_connected(_on_child_entered_tree):
		node.child_entered_tree.connect(_on_child_entered_tree)
	if not node.child_exiting_tree.is_connected(_on_child_exiting_tree):
		node.child_exiting_tree.connect(_on_child_exiting_tree)


func _disconnect_watch(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.child_entered_tree.is_connected(_on_child_entered_tree):
		node.child_entered_tree.disconnect(_on_child_entered_tree)
	if node.child_exiting_tree.is_connected(_on_child_exiting_tree):
		node.child_exiting_tree.disconnect(_on_child_exiting_tree)


func _unwatch_tree() -> void:
	for node: Node in _watched_nodes:
		_disconnect_watch(node)
	_watched_nodes.clear()


func _on_child_entered_tree(_node: Node) -> void:
	_config_dirty = true
	_refresh_config()


func _on_child_exiting_tree(node: Node) -> void:
	if node == self:
		_leaving = true
		return
	_config_dirty = true
	if is_inside_tree() and not is_queued_for_deletion() and not _leaving:
		_refresh_config.call_deferred()


func _on_visible_on_screen_notifier_3d_screen_entered() -> void:
	is_visible_to_mirror = true


func _on_visible_on_screen_notifier_3d_screen_exited() -> void:
	is_visible_to_mirror = false
