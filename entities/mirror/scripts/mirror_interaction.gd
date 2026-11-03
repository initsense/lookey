extends Node3D
## Evaluates which PigmentEntity instances are linked through this mirror and
## which of those are affected, using frustum gates and reflection raycasts.


const SURFACE_EPSILON: float = 0.01
const STAGGER_GROUP_SIZE: int = 4

static var _next_stagger_index: int = 0

var is_mirror_visible: bool = false

@onready var _mirror: Mirror3D = get_parent()
@onready var _mirror_quad: MeshInstance3D = _mirror.get_node("Quad")

var _tracked_entities: Array[PigmentEntity] = []
var _linked_cache: Dictionary[PigmentEntity, bool] = {}
var _stagger_index: Dictionary[PigmentEntity, int] = {}
var _exclude_rids: Dictionary[PigmentEntity, Array] = {}
var _tree_connected: bool = false


func _ready() -> void:
	_refresh_tracked_entities()
	var tree := get_tree()
	if tree and not _tree_connected:
		tree.node_added.connect(_on_tree_node_added)
		tree.node_removed.connect(_on_tree_node_removed)
		_tree_connected = true


func _exit_tree() -> void:
	for entity: PigmentEntity in _tracked_entities:
		if is_instance_valid(entity):
			entity.clear_mirror_link_state(_mirror)
	_tracked_entities.clear()
	_linked_cache.clear()
	_stagger_index.clear()
	_exclude_rids.clear()

	var tree := get_tree()
	if tree and _tree_connected:
		if tree.node_added.is_connected(_on_tree_node_added):
			tree.node_added.disconnect(_on_tree_node_added)
		if tree.node_removed.is_connected(_on_tree_node_removed):
			tree.node_removed.disconnect(_on_tree_node_removed)
		_tree_connected = false


func _physics_process(_delta: float) -> void:
	if not _mirror.player:
		return
	if not is_instance_valid(_mirror.player_cam):
		return

	# Entities may join the pigment group only after their own _ready(), which
	# runs after node_added. Refresh when tracking is empty or stale.
	if _tracked_entities.is_empty():
		_refresh_tracked_entities()

	for entity: PigmentEntity in _tracked_entities:
		if not is_instance_valid(entity):
			continue
		_evaluate_entity(entity)


func _evaluate_entity(entity: PigmentEntity) -> void:
	if not _passes_cheap_gates(entity):
		_report_link_state(entity, false)
		return

	var previously_linked: bool = _linked_cache.get(entity, false)
	var physics_frame: int = Engine.get_physics_frames()
	var stagger: int = _stagger_index.get(entity, 0)
	var should_raycast: bool = (
		not previously_linked
		or physics_frame % STAGGER_GROUP_SIZE == stagger
	)

	var is_linked: bool = previously_linked
	if should_raycast:
		is_linked = _any_vertex_reflection_visible(entity)

	_report_link_state(entity, is_linked)


func _report_link_state(entity: PigmentEntity, is_linked: bool) -> void:
	_linked_cache[entity] = is_linked
	var is_affected: bool = false
	if is_linked:
		is_affected = Pigments.is_entity_eligible(
			_mirror.pigment,
			_mirror.mirror_type == Mirror3D.MirrorType.REVEAL,
			entity.pigment,
			entity.is_hidden_entity()
		)
	entity.set_mirror_link_state(_mirror, is_linked, is_affected)


func _passes_cheap_gates(entity: PigmentEntity) -> bool:
	if not is_mirror_visible and not _is_aabb_in_camera_frustum(_mirror_quad_aabb()):
		return false

	if not is_instance_valid(_mirror.player_cam):
		return false

	var camera_to_mirror: float = _mirror.global_position.distance_to(
		_mirror.player_cam.global_position
	)
	if camera_to_mirror >= _mirror.freeze_distance:
		return false

	if entity.mesh == null:
		return false

	var object_to_mirror: float = entity.mesh.global_position.distance_to(
		_mirror_quad.global_position
	)
	if object_to_mirror > _mirror.cull_far:
		return false

	var reflected_aabb: AABB = _reflected_entity_aabb(entity)
	if not _is_aabb_in_camera_frustum(reflected_aabb):
		return false

	return true


func _any_vertex_reflection_visible(entity: PigmentEntity) -> bool:
	if entity.mesh == null or entity.mesh.mesh == null:
		return false

	var mirror_plane_normal: Vector3 = _mirror_quad.global_basis.z.normalized()
	var mirror_plane_origin: Vector3 = _mirror_quad.global_position
	var target_point: Vector3 = _mirror.player_cam.global_position
	var mesh: Mesh = entity.mesh.mesh
	var mesh_transform: Transform3D = entity.mesh.global_transform
	var exclude: Array = _exclude_rids.get(entity, [])

	for s: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for local_vertex: Vector3 in vertices:
			var world_vertex: Vector3 = mesh_transform * local_vertex
			if _is_vertex_reflection_visible(
				world_vertex,
				mirror_plane_normal,
				mirror_plane_origin,
				target_point,
				exclude
			):
				return true
	return false


func _is_vertex_reflection_visible(
	world_vertex: Vector3,
	mirror_normal: Vector3,
	mirror_origin: Vector3,
	target_point: Vector3,
	exclude: Array
) -> bool:
	var reflected_vertex: Vector3 = _reflect_point(world_vertex, mirror_normal, mirror_origin)
	var direction: Vector3 = target_point - reflected_vertex
	var denom: float = direction.dot(mirror_normal)
	if is_zero_approx(denom):
		return false

	var t: float = (mirror_origin - reflected_vertex).dot(mirror_normal) / denom
	if t < 0.0 or t > 1.0:
		return false

	var q: Vector3 = reflected_vertex + t * direction
	if not _is_point_within_mirror_bounds(q):
		return false

	var reflected_mask: int = _mirror.cull_mask & Pigments.REFLECTED_OCCLUSION_MASK
	if _raycast_blocked(world_vertex, q, reflected_mask, exclude):
		return false

	if _raycast_blocked(q, target_point, Pigments.REAL_WORLD_OCCLUSION_MASK, exclude):
		return false

	return true


func _is_point_within_mirror_bounds(world_point: Vector3) -> bool:
	var local_point: Vector3 = _mirror_quad.global_transform.affine_inverse() * world_point
	return (
		absf(local_point.x) <= _mirror.size.x * 0.5
		and absf(local_point.y) <= _mirror.size.y * 0.5
	)


func _raycast_blocked(
	from: Vector3,
	to: Vector3,
	collision_mask: int,
	exclude: Array
) -> bool:
	var space_state := get_world_3d().direct_space_state
	var offset: Vector3 = to - from
	var length: float = offset.length()
	if length <= SURFACE_EPSILON * 2.0:
		return false

	var direction: Vector3 = offset / length
	var adjusted_from: Vector3 = from + direction * SURFACE_EPSILON
	var adjusted_to: Vector3 = to - direction * SURFACE_EPSILON
	var query := PhysicsRayQueryParameters3D.create(adjusted_from, adjusted_to)
	query.exclude = exclude
	query.collision_mask = collision_mask
	query.collide_with_areas = false

	var result: Dictionary = space_state.intersect_ray(query)
	return not result.is_empty()


func _reflect_point(point: Vector3, normal: Vector3, plane_origin: Vector3) -> Vector3:
	var distance: float = (point - plane_origin).dot(normal)
	return point - 2.0 * distance * normal


func _mirror_quad_aabb() -> AABB:
	var half := Vector3(_mirror.size.x * 0.5, _mirror.size.y * 0.5, 0.05)
	var local_aabb := AABB(-half, half * 2.0)
	return _mirror_quad.global_transform * local_aabb


func _reflected_entity_aabb(entity: PigmentEntity) -> AABB:
	var mesh_aabb: AABB = entity.mesh.get_aabb()
	var world_aabb: AABB = entity.mesh.global_transform * mesh_aabb
	var corners: Array[Vector3] = [
		world_aabb.position,
		world_aabb.position + Vector3(world_aabb.size.x, 0.0, 0.0),
		world_aabb.position + Vector3(0.0, world_aabb.size.y, 0.0),
		world_aabb.position + Vector3(0.0, 0.0, world_aabb.size.z),
		world_aabb.position + Vector3(world_aabb.size.x, world_aabb.size.y, 0.0),
		world_aabb.position + Vector3(world_aabb.size.x, 0.0, world_aabb.size.z),
		world_aabb.position + Vector3(0.0, world_aabb.size.y, world_aabb.size.z),
		world_aabb.position + world_aabb.size,
	]

	var mirror_normal: Vector3 = _mirror_quad.global_basis.z.normalized()
	var mirror_origin: Vector3 = _mirror_quad.global_position
	var reflected_aabb := AABB()
	var first: bool = true
	for corner: Vector3 in corners:
		var reflected: Vector3 = _reflect_point(corner, mirror_normal, mirror_origin)
		if first:
			reflected_aabb = AABB(reflected, Vector3.ZERO)
			first = false
		else:
			reflected_aabb = reflected_aabb.expand(reflected)
	return reflected_aabb


func _is_aabb_in_camera_frustum(aabb: AABB) -> bool:
	if not is_instance_valid(_mirror.player_cam):
		return false
	# Camera3D.get_frustum() normals point outward; a point is inside when
	# distance_to(point) <= 0 for every plane.
	var planes: Array[Plane] = _mirror.player_cam.get_frustum()
	for plane: Plane in planes:
		# n-vertex: AABB corner with the minimum signed distance (against the
		# outward normal). If that corner is still outside, the AABB is out.
		var negative := Vector3(
			aabb.position.x if plane.normal.x >= 0.0 else aabb.end.x,
			aabb.position.y if plane.normal.y >= 0.0 else aabb.end.y,
			aabb.position.z if plane.normal.z >= 0.0 else aabb.end.z
		)
		if plane.distance_to(negative) > 0.0:
			return false
	return true


func _refresh_tracked_entities() -> void:
	_tracked_entities.clear()
	var seen: Dictionary = {}

	for node: Node in get_tree().get_nodes_in_group(PigmentEntity.GROUP_NAME):
		if node is PigmentEntity:
			_track_entity(node as PigmentEntity, seen)

	if _mirror.object_to_reflect is PigmentEntity:
		_track_entity(_mirror.object_to_reflect as PigmentEntity, seen)
	elif _mirror.object_to_reflect != null:
		var nested: PigmentEntity = _find_pigment_entity(_mirror.object_to_reflect)
		if nested:
			_track_entity(nested, seen)


func _track_entity(entity: PigmentEntity, seen: Dictionary) -> void:
	if seen.has(entity):
		return
	seen[entity] = true
	_tracked_entities.append(entity)
	if not _stagger_index.has(entity):
		_stagger_index[entity] = _next_stagger_index
		_next_stagger_index = (_next_stagger_index + 1) % STAGGER_GROUP_SIZE
	_exclude_rids[entity] = _build_exclude_rids(entity)
	_linked_cache[entity] = false


func _build_exclude_rids(entity: PigmentEntity) -> Array:
	var rids: Array = []
	if entity.static_body:
		rids.append(entity.static_body.get_rid())
	if _mirror.player:
		rids.append(_mirror.player.get_rid())
	var mirror_body: CollisionObject3D = _find_collision_object(_mirror_quad)
	if mirror_body:
		rids.append(mirror_body.get_rid())
	return rids


func _find_pigment_entity(from_node: Node) -> PigmentEntity:
	if from_node is PigmentEntity:
		return from_node as PigmentEntity
	for child in from_node.get_children():
		var found: PigmentEntity = _find_pigment_entity(child)
		if found:
			return found
	return null


func _find_collision_object(from_node: Node) -> CollisionObject3D:
	var node: Node = from_node
	while node:
		if node is CollisionObject3D:
			return node as CollisionObject3D
		node = node.get_parent()
	return null


func _on_tree_node_added(node: Node) -> void:
	if node is PigmentEntity:
		# Defer until after PigmentEntity._ready() adds the node to the group
		# and resolves mesh / static_body references.
		call_deferred("_refresh_tracked_entities")


func _on_tree_node_removed(node: Node) -> void:
	if node is PigmentEntity:
		var entity := node as PigmentEntity
		_tracked_entities.erase(entity)
		_linked_cache.erase(entity)
		_stagger_index.erase(entity)
		_exclude_rids.erase(entity)


#region SIGNALS
func _on_mirror_notifier_screen_entered() -> void:
	is_mirror_visible = true


func _on_mirror_notifier_screen_exited() -> void:
	is_mirror_visible = false
#endregion
