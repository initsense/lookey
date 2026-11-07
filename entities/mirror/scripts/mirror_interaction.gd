extends Node3D
## Checks which colored objects (PigmentEntity) are visible to the player through
## this mirror — both directly and bounced through other mirrors — and tells those
## objects when to enable or disable their physical collision.

const SURFACE_EPSILON: float = 0.01
const STAGGER_GROUP_SIZE: int = 4

static var _next_stagger_index: int = 0

## True while this mirror's bounding box is on the player's screen.
var is_mirror_visible: bool = false

@onready var _mirror: Mirror3D = get_parent() as Mirror3D
@onready var _mirror_quad: MeshInstance3D = _mirror.get_node_or_null("Quad") as MeshInstance3D

var _tracked_entities: Array[PigmentEntity] = []
var _linked_cache: Dictionary[PigmentEntity, bool] = {}
var _linked_chains_cache: Dictionary[PigmentEntity, Array] = {}
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
	_linked_chains_cache.clear()
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
		_mirror._resolve_player_and_camera()
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
	if not _passes_outer_mirror_gates(entity):
		_report_link_state(entity, false, [])
		return

	var candidate_chains: Array = MirrorManager.get_chains_for_outer_mirror(_mirror)
	if candidate_chains.is_empty():
		candidate_chains = [[_mirror]]

	var valid_chains: Array = []
	for chain: Array in candidate_chains:
		if _passes_chain_gates(entity, chain):
			valid_chains.append(chain)

	if valid_chains.is_empty():
		_report_link_state(entity, false, [])
		return

	var previously_linked: bool = _linked_cache.get(entity, false)
	var physics_frame: int = Engine.get_physics_frames()
	var stagger: int = _stagger_index.get(entity, 0)
	var should_raycast: bool = (
		not previously_linked
		or physics_frame % STAGGER_GROUP_SIZE == stagger
	)

	var is_linked: bool = previously_linked
	var linked_chains: Array = _linked_chains_cache.get(entity, [])
	if should_raycast:
		is_linked = false
		linked_chains = []
		for chain: Array in valid_chains:
			var chain_eligible: bool = _is_entity_eligible_for_chain(entity, chain)
			if is_linked and not chain_eligible:
				continue
			var chain_exclude: Array = _build_chain_exclude_rids(entity, chain)
			if _any_vertex_reflection_visible_along_chain(entity, chain, chain_exclude):
				is_linked = true
				linked_chains.append(chain)
				if chain_eligible:
					break

	_report_link_state(entity, is_linked, linked_chains)


func _report_link_state(entity: PigmentEntity, is_linked: bool, linked_chains: Array) -> void:
	_linked_cache[entity] = is_linked
	_linked_chains_cache[entity] = linked_chains if is_linked else []
	var is_affected: bool = false
	if is_linked:
		for chain: Array in linked_chains:
			if _is_entity_eligible_for_chain(entity, chain):
				is_affected = true
				break
	entity.set_mirror_link_state(_mirror, is_linked, is_affected)


func _is_entity_eligible_for_chain(entity: PigmentEntity, chain: Array) -> bool:
	if chain.is_empty():
		return false
	var innermost: Mirror3D = chain[0] as Mirror3D
	if innermost == null or not is_instance_valid(innermost):
		return false
	var chain_pigment: Pigments.Pigment = Pigments.mix_mirror_chain_pigment(chain)
	var is_reveal: bool = innermost.mirror_type == Mirror3D.MirrorType.REVEAL
	return Pigments.is_entity_eligible(
		chain_pigment,
		is_reveal,
		entity.pigment,
		entity.is_hidden_entity()
	)


func _passes_outer_mirror_gates(entity: PigmentEntity) -> bool:
	if not is_mirror_visible and not _is_aabb_in_camera_frustum(_mirror_quad_aabb()):
		return false

	if not is_instance_valid(_mirror.player_cam):
		return false

	var camera_to_mirror: float = _mirror.global_position.distance_to(
		_mirror.player_cam.global_position
	)
	if camera_to_mirror >= _mirror.freeze_distance:
		return false

	if entity.mesh == null or entity.mesh.mesh == null:
		return false

	return true


func _passes_chain_gates(entity: PigmentEntity, chain: Array) -> bool:
	if chain.is_empty():
		return false

	var innermost: Mirror3D = chain[0]
	if innermost == null or not is_instance_valid(innermost):
		return false

	var object_to_inner: float = entity.mesh.global_position.distance_to(
		innermost.get_mirror_origin()
	)
	if object_to_inner > innermost.cull_far:
		return false

	var reflected_aabb: AABB = _reflected_entity_aabb_for_chain(entity, chain)
	if not _is_aabb_in_camera_frustum(reflected_aabb):
		return false

	return true


func _any_vertex_reflection_visible_along_chain(
	entity: PigmentEntity,
	chain: Array,
	exclude: Array
) -> bool:
	if entity.mesh == null or entity.mesh.mesh == null:
		return false

	var target_point: Vector3 = _mirror.player_cam.global_position
	var mesh: Mesh = entity.mesh.mesh
	var mesh_transform: Transform3D = entity.mesh.global_transform

	for s: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for local_vertex: Vector3 in vertices:
			var world_vertex: Vector3 = mesh_transform * local_vertex
			if _is_vertex_reflection_visible_along_chain(
				world_vertex,
				chain,
				target_point,
				exclude
			):
				return true
	return false


func _is_vertex_reflection_visible_along_chain(
	world_vertex: Vector3,
	chain: Array,
	target_point: Vector3,
	exclude: Array
) -> bool:
	var count: int = chain.size()
	if count == 0:
		return false

	# 1. Unfold the vertex sequentially across each mirror in the chain (innermost to outermost).
	var unfolded: Array[Vector3] = []
	unfolded.resize(count + 1)
	unfolded[0] = world_vertex
	for i: int in range(count):
		var m: Mirror3D = chain[i]
		unfolded[i + 1] = _reflect_point(
			unfolded[i],
			m.get_mirror_normal(),
			m.get_mirror_origin()
		)

	# 2. Back-project from the player camera down to the object to find the bounce point on each mirror.
	var bounce_points: Array[Vector3] = []
	bounce_points.resize(count)
	var receiver_point: Vector3 = target_point

	var idx: int = count - 1
	while idx >= 0:
		var m: Mirror3D = chain[idx]
		var m_normal: Vector3 = m.get_mirror_normal()
		var m_origin: Vector3 = m.get_mirror_origin()
		var virtual_source: Vector3 = unfolded[idx + 1]
		var direction: Vector3 = receiver_point - virtual_source
		var denom: float = direction.dot(m_normal)
		if is_zero_approx(denom):
			return false

		var t: float = (m_origin - virtual_source).dot(m_normal) / denom
		if t <= 0.0 or t >= 1.0:
			return false

		var q: Vector3 = virtual_source + t * direction
		if not _is_point_within_mirror_bounds(q, m):
			return false

		bounce_points[idx] = q
		receiver_point = q
		idx -= 1

	# 3. Check occlusion along each reflected segment using that sub-chain's mixed pigment
	# and innermost mirror type, and along the final mirror-to-player segment using the real-world mask.
	var first_segment_mask: int = _compute_segment_occlusion_mask(chain, 0)
	if _raycast_blocked(world_vertex, bounce_points[0], first_segment_mask, exclude):
		return false

	for i: int in range(count - 1):
		var segment_mask: int = _compute_segment_occlusion_mask(chain, i + 1)
		if _raycast_blocked(bounce_points[i], bounce_points[i + 1], segment_mask, exclude):
			return false

	if _raycast_blocked(bounce_points[count - 1], target_point, Pigments.REAL_WORLD_OCCLUSION_MASK, exclude):
		return false

	return true


func _compute_segment_occlusion_mask(chain: Array, start_index: int) -> int:
	var sub_chain: Array = chain.slice(start_index)
	if sub_chain.is_empty():
		return _mirror.cull_mask & Pigments.REFLECTED_OCCLUSION_MASK
	var segment_mirror: Mirror3D = sub_chain[0] as Mirror3D
	if segment_mirror == null or not is_instance_valid(segment_mirror):
		return _mirror.cull_mask & Pigments.REFLECTED_OCCLUSION_MASK
	var mixed_pigment: Pigments.Pigment = Pigments.mix_mirror_chain_pigment(sub_chain)
	var is_reveal: bool = segment_mirror.mirror_type == Mirror3D.MirrorType.REVEAL
	var mask: int = Pigments.compute_mirror_cull_mask(mixed_pigment, is_reveal)
	return mask & Pigments.REFLECTED_OCCLUSION_MASK


func _is_point_within_mirror_bounds(world_point: Vector3, mirror: Mirror3D) -> bool:
	if mirror._mirror_quad == null:
		return false
	var local_point: Vector3 = mirror._mirror_quad.global_transform.affine_inverse() * world_point
	return (
		absf(local_point.x) <= mirror.size.x * 0.5
		and absf(local_point.y) <= mirror.size.y * 0.5
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


func _reflected_entity_aabb_for_chain(entity: PigmentEntity, chain: Array) -> AABB:
	var mesh_aabb: AABB = entity.mesh.get_aabb()
	var current_aabb: AABB = entity.mesh.global_transform * mesh_aabb

	for m: Mirror3D in chain:
		var corners: Array[Vector3] = [
			current_aabb.position,
			current_aabb.position + Vector3(current_aabb.size.x, 0.0, 0.0),
			current_aabb.position + Vector3(0.0, current_aabb.size.y, 0.0),
			current_aabb.position + Vector3(0.0, 0.0, current_aabb.size.z),
			current_aabb.position + Vector3(current_aabb.size.x, current_aabb.size.y, 0.0),
			current_aabb.position + Vector3(current_aabb.size.x, 0.0, current_aabb.size.z),
			current_aabb.position + Vector3(0.0, current_aabb.size.y, current_aabb.size.z),
			current_aabb.position + current_aabb.size,
		]
		var mirror_normal: Vector3 = m.get_mirror_normal()
		var mirror_origin: Vector3 = m.get_mirror_origin()
		var next_aabb := AABB()
		var first: bool = true
		for corner: Vector3 in corners:
			var reflected: Vector3 = _reflect_point(corner, mirror_normal, mirror_origin)
			if first:
				next_aabb = AABB(reflected, Vector3.ZERO)
				first = false
			else:
				next_aabb = next_aabb.expand(reflected)
		current_aabb = next_aabb

	return current_aabb


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
	_linked_chains_cache[entity] = []


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


func _build_chain_exclude_rids(entity: PigmentEntity, chain: Array) -> Array:
	var rids: Array = _exclude_rids.get(entity, []).duplicate()
	for m: Mirror3D in chain:
		if m == null or m == _mirror or m._mirror_quad == null:
			continue
		var body: CollisionObject3D = _find_collision_object(m._mirror_quad)
		if body != null:
			var rid: RID = body.get_rid()
			if not rids.has(rid):
				rids.append(rid)
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
		_linked_chains_cache.erase(entity)
		_stagger_index.erase(entity)
		_exclude_rids.erase(entity)


#region SIGNALS
func _on_mirror_notifier_screen_entered() -> void:
	is_mirror_visible = true


func _on_mirror_notifier_screen_exited() -> void:
	is_mirror_visible = false
#endregion
