extends Node
## Coordinates all mirrors in the current scene.
## Figures out which mirrors can see each other, sets up nested reflection cameras
## with additive RYB pigment mixing, and schedules viewport updates so reflections
## never flicker.

## Maximum number of mirror bounces supported for rendering and interaction chains.
const MAX_REFLECTION_BOUNCES: int = 3
const PLANE_EPSILON: float = 0.001
## Extra visibility margin (in meters) applied to shadow casters so off-axis mirror cameras
## never cull shadow casters whose shadows fall onto the mirror glass.
const OFF_AXIS_SHADOW_CASTER_MARGIN: float = 25.0

var _mirrors: Array[Mirror3D] = []
var _chains_by_outer: Dictionary[Mirror3D, Array] = {}
var _last_process_frame: int = -1
var _last_graph_physics_frame: int = -1
var _tree_connected: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var tree := get_tree()
	if tree != null and not _tree_connected:
		tree.node_added.connect(_on_scene_node_added)
		_tree_connected = true
	call_deferred("_configure_scene_shadow_casters")


func _on_scene_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		_apply_shadow_caster_margin(node as GeometryInstance3D)


func _configure_scene_shadow_casters() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	for node: Node in tree.root.find_children("*", "GeometryInstance3D", true, false):
		_apply_shadow_caster_margin(node as GeometryInstance3D)


func _apply_shadow_caster_margin(geom: GeometryInstance3D) -> void:
	if geom == null or not is_instance_valid(geom):
		return
	if geom.name == &"Quad" or geom.name == &"ReflectedQuad":
		return
	if geom.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		return
	if geom.extra_cull_margin < OFF_AXIS_SHADOW_CASTER_MARGIN:
		geom.extra_cull_margin = OFF_AXIS_SHADOW_CASTER_MARGIN


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	step_frame(delta)


## Registers a mirror when it enters the scene so the manager can update it each frame.
func register_mirror(mirror: Mirror3D) -> void:
	if mirror == null or _mirrors.has(mirror):
		return
	_mirrors.append(mirror)
	_invalidate_frame_cache()


## Removes a mirror when it leaves the scene and clears any cached chains referencing it.
func unregister_mirror(mirror: Mirror3D) -> void:
	_mirrors.erase(mirror)
	_chains_by_outer.erase(mirror)
	for outer: Mirror3D in _chains_by_outer.keys():
		var filtered: Array = []
		for chain: Array in _chains_by_outer[outer]:
			if not chain.has(mirror):
				filtered.append(chain)
		_chains_by_outer[outer] = filtered
	_invalidate_frame_cache()


## Runs the per-frame mirror update and nested reflection scheduler once per process frame.
func step_frame(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var frame: int = Engine.get_process_frames()
	if frame == _last_process_frame:
		return
	_last_process_frame = frame
	_update_all_mirrors(delta)


## Forces an immediate rebuild of mirror cameras, reflection chains, and viewport states.
## Useful in tests or when mirrors move or change pigment mid-frame.
func refresh_now() -> void:
	_last_process_frame = -1
	_last_graph_physics_frame = -1
	_update_all_mirrors(0.0)


## Returns all valid reflection chains ending at outer_mirror (from 1-bounce up to MAX_REFLECTION_BOUNCES).
## Each chain is ordered from innermost mirror to outer_mirror: [M_1, ..., outer_mirror].
func get_chains_for_outer_mirror(outer_mirror: Mirror3D) -> Array:
	if outer_mirror == null or not is_instance_valid(outer_mirror):
		return []

	var phys_frame: int = Engine.get_physics_frames()
	# Only rebuild chains from physics if _process has not already updated chains recently,
	# and NEVER run _schedule_viewports or mutate timers from physics.
	if not _chains_by_outer.has(outer_mirror) or (_last_process_frame < 0 and phys_frame != _last_graph_physics_frame):
		_rebuild_chains_for_physics()
		_last_graph_physics_frame = phys_frame

	return _chains_by_outer.get(outer_mirror, [[outer_mirror]])


func _invalidate_frame_cache() -> void:
	_last_process_frame = -1
	_last_graph_physics_frame = -1


func _rebuild_chains_for_physics() -> void:
	_prune_invalid_mirrors()
	var active_mirrors: Array[Mirror3D] = []
	for mirror: Mirror3D in _mirrors:
		if mirror.prepare_camera_only():
			active_mirrors.append(mirror)
	_rebuild_reflection_chains(active_mirrors)


func _update_all_mirrors(delta: float) -> void:
	_prune_invalid_mirrors()

	var active_mirrors: Array[Mirror3D] = []
	for mirror: Mirror3D in _mirrors:
		if mirror.prepare_frame(delta):
			active_mirrors.append(mirror)

	_rebuild_reflection_chains(active_mirrors)
	_schedule_viewports(active_mirrors)


func _prune_invalid_mirrors() -> void:
	var idx: int = _mirrors.size() - 1
	while idx >= 0:
		var m: Mirror3D = _mirrors[idx]
		if m == null or not is_instance_valid(m) or not m.is_inside_tree():
			_mirrors.remove_at(idx)
		idx -= 1


func _rebuild_reflection_chains(active_mirrors: Array[Mirror3D]) -> void:
	_chains_by_outer.clear()

	for outer: Mirror3D in active_mirrors:
		var chains: Array = []
		var single_chain: Array[Mirror3D] = [outer]
		chains.append(single_chain)

		var cam: Camera3D = outer._get_active_camera()
		if not is_instance_valid(cam):
			_chains_by_outer[outer] = chains
			continue

		var cam_pos: Vector3 = cam.global_position

		# 2-mirror chains: [inner, outer]
		if MAX_REFLECTION_BOUNCES >= 2:
			for inner: Mirror3D in active_mirrors:
				if inner == outer:
					continue
				var chain_2: Array[Mirror3D] = [inner, outer]
				if _is_chain_geometrically_valid(chain_2, cam_pos):
					chains.append(chain_2)

		# 3-mirror chains: [innermost, middle, outer]
		if MAX_REFLECTION_BOUNCES >= 3:
			var two_bounce_chains: Array = chains.duplicate()
			for existing: Array in two_bounce_chains:
				if existing.size() != 2:
					continue
				var middle: Mirror3D = existing[0]
				for innermost: Mirror3D in active_mirrors:
					if innermost == middle:
						continue
					var chain_3: Array[Mirror3D] = [innermost, middle, outer]
					if _is_chain_geometrically_valid(chain_3, cam_pos):
						chains.append(chain_3)

		_chains_by_outer[outer] = chains


func _schedule_viewports(active_mirrors: Array[Mirror3D]) -> void:
	var outer_mirrors_with_nesting: Array[Mirror3D] = []
	var outers_by_inner: Dictionary[Mirror3D, Array] = {}

	# Most centered outer mirrors first, so they keep a reflected view when an inner mirror runs out of slots.
	var visible_outers: Array[Mirror3D] = []
	for outer: Mirror3D in active_mirrors:
		if _is_mirror_visible_to_player(outer):
			visible_outers.append(outer)
	visible_outers.sort_custom(func(a: Mirror3D, b: Mirror3D) -> bool:
		return _get_outer_mirror_view_alignment(a) > _get_outer_mirror_view_alignment(b)
	)

	for outer: Mirror3D in visible_outers:
		var chains: Array = _chains_by_outer.get(outer, [])
		var outer_has_nested: bool = false
		for chain: Array in chains:
			if chain.size() != 2:
				continue
			var inner_m: Mirror3D = chain[0]
			outer_has_nested = true
			if not outers_by_inner.has(inner_m):
				outers_by_inner[inner_m] = [] as Array[Mirror3D]
			outers_by_inner[inner_m].append(outer)
		if outer_has_nested:
			outer_mirrors_with_nesting.append(outer)

	# Fast path 0: No visible outer mirror reflects another mirror right now.
	if outer_mirrors_with_nesting.is_empty():
		for m: Mirror3D in active_mirrors:
			m.freeze_reflected_view(true)
			m.set_direct_viewport_active(_is_mirror_visible_to_player(m))
		return

	# Every outer mirror that shows this mirror gets its own reflected view. Each view uses that
	# outer mirror's viewpoint so the perspective stays correct, and combines both pigments
	# (RYB additive mixing) while keeping this mirror's own reveal/dissolve type.
	for m: Mirror3D in active_mirrors:
		if outers_by_inner.has(m):
			var outers: Array[Mirror3D] = []
			outers.assign(outers_by_inner[m])
			var slots: PackedInt32Array = m.assign_reflected_slots(outers)
			var used_slots: Array[bool] = []
			used_slots.resize(Mirror3D.MAX_REFLECTED_VIEWS)
			used_slots.fill(false)
			for i: int in outers.size():
				var slot: int = slots[i]
				if slot < 0:
					continue
				var outer: Mirror3D = outers[i]
				var observer_pos: Vector3 = _get_reflected_observer_for_outer(outer)
				var mixed_pigment: Pigments.Pigment = Pigments.mix_pigments(m.pigment, outer.pigment)
				var mixed_mask: int = Pigments.compute_mirror_cull_mask(
					mixed_pigment,
					m.mirror_type == Mirror3D.MirrorType.REVEAL
				)
				m.configure_reflected_view(observer_pos, mixed_mask, false, mixed_pigment, slot)
				used_slots[slot] = true
			for slot: int in Mirror3D.MAX_REFLECTED_VIEWS:
				if not used_slots[slot]:
					m.release_reflected_slot(slot)
		else:
			m.freeze_reflected_view(true)
		m.set_direct_viewport_active(_is_mirror_visible_to_player(m))



func _is_mirror_visible_to_player(mirror: Mirror3D) -> bool:
	if mirror == null or mirror._mirror_quad == null:
		return false
	if mirror.always_active:
		return true
	var cam: Camera3D = mirror._get_active_camera()
	if not is_instance_valid(cam):
		return true
	var half := Vector3(mirror.size.x * 0.5, mirror.size.y * 0.5, 0.05)
	var world_aabb: AABB = mirror._mirror_quad.global_transform * AABB(-half, half * 2.0)
	if not _is_aabb_in_frustum(world_aabb, cam.get_frustum()):
		return false
	return _is_point_pair_unoccluded(mirror.get_world_3d(), cam.global_position, mirror.get_mirror_origin())


func _is_nested_mirror_in_player_frustum(inner_mirror: Mirror3D, outer_mirror: Mirror3D) -> bool:
	if inner_mirror == null or outer_mirror == null:
		return false
	if outer_mirror.always_active:
		return true
	var cam: Camera3D = outer_mirror._get_active_camera()
	if not is_instance_valid(cam):
		return true
	var corners: PackedVector3Array = _get_mirror_quad_corners(inner_mirror)
	if corners.is_empty():
		return false
	var reflected_aabb := AABB()
	var first: bool = true
	for pt: Vector3 in corners:
		var r_pt: Vector3 = outer_mirror.reflect_point(pt)
		if first:
			reflected_aabb = AABB(r_pt, Vector3.ZERO)
			first = false
		else:
			reflected_aabb = reflected_aabb.expand(r_pt)
	return _is_aabb_in_frustum(reflected_aabb, cam.get_frustum())


func _is_aabb_in_frustum(world_aabb: AABB, planes: Array[Plane]) -> bool:
	for plane: Plane in planes:
		var negative := Vector3(
			world_aabb.position.x if plane.normal.x >= 0.0 else world_aabb.end.x,
			world_aabb.position.y if plane.normal.y >= 0.0 else world_aabb.end.y,
			world_aabb.position.z if plane.normal.z >= 0.0 else world_aabb.end.z
		)
		if plane.distance_to(negative) > 0.0:
			return false
	return true


func _get_outer_mirror_view_alignment(outer: Mirror3D) -> float:
	if outer == null:
		return -1.0
	var cam: Camera3D = outer._get_active_camera()
	if not is_instance_valid(cam):
		return 0.0
	var to_mirror: Vector3 = (outer.get_mirror_origin() - cam.global_position).normalized()
	return (-cam.global_basis.z).dot(to_mirror)


func _get_reflected_observer_for_outer(outer: Mirror3D) -> Vector3:
	if outer._mirror_camera != null:
		return outer._mirror_camera.global_position
	var cam: Camera3D = outer._get_active_camera()
	if is_instance_valid(cam):
		return outer.reflect_point(cam.global_position)
	return outer.get_mirror_origin()


## Checks whether light from chain[0] can bounce sequentially through chain[1..k-1]
## and reach player_cam_pos without being blocked by solid world walls.
func _is_chain_geometrically_valid(chain: Array[Mirror3D], player_cam_pos: Vector3) -> bool:
	var count: int = chain.size()
	if count < 2:
		return true

	# Check that consecutive mirrors are not separated by solid world walls (Layer 1).
	for i: int in range(count - 1):
		if not _is_mirror_pair_unoccluded(chain[i], chain[i + 1]):
			return false

	# 1. Compute unfolded observer positions from outermost mirror down to innermost mirror.
	var observers: Array[Vector3] = []
	observers.resize(count)
	observers[count - 1] = player_cam_pos

	var idx: int = count - 1
	while idx >= 1:
		var m: Mirror3D = chain[idx]
		var dist_to_plane: float = (observers[idx] - m.get_mirror_origin()).dot(m.get_mirror_normal())
		if absf(dist_to_plane) <= PLANE_EPSILON:
			return false
		observers[idx - 1] = m.reflect_point(observers[idx])
		idx -= 1

	var innermost: Mirror3D = chain[0]
	var innermost_dist: float = (
		(observers[0] - innermost.get_mirror_origin()).dot(innermost.get_mirror_normal())
	)
	if absf(innermost_dist) <= PLANE_EPSILON:
		return false

	# 2. Unfold chain[0]'s quad corners across each subsequent mirror in the chain,
	# clipping to each mirror's reflecting half-space and checking 2D projection overlap.
	var poly: PackedVector3Array = _get_mirror_quad_corners(innermost)
	if poly.is_empty():
		return false

	for j: int in range(1, count):
		var receiving: Mirror3D = chain[j]
		var obs_pos: Vector3 = observers[j]
		var plane_origin: Vector3 = receiving.get_mirror_origin()
		var plane_normal: Vector3 = receiving.get_mirror_normal()
		var obs_signed_dist: float = (obs_pos - plane_origin).dot(plane_normal)
		if absf(obs_signed_dist) <= PLANE_EPSILON:
			return false

		var side_sign: float = signf(obs_signed_dist)
		var min_dist: float = maxf(receiving.cull_near, 0.01)

		poly = _clip_polygon_to_plane(poly, plane_origin, plane_normal * side_sign, min_dist)
		if poly.is_empty():
			return false

		if not _any_point_within_distance(poly, plane_origin, receiving.cull_far):
			return false

		var reflected_obs: Vector3 = observers[j - 1]
		if not _projected_polygon_overlaps_quad(poly, reflected_obs, receiving):
			return false

		if j < count - 1:
			for p_idx: int in range(poly.size()):
				poly[p_idx] = receiving.reflect_point(poly[p_idx])

	return true


func _is_mirror_pair_unoccluded(mirror_a: Mirror3D, mirror_b: Mirror3D) -> bool:
	if mirror_a == null or mirror_b == null:
		return false
	return _is_point_pair_unoccluded(
		mirror_a.get_world_3d(),
		mirror_a.get_mirror_origin(),
		mirror_b.get_mirror_origin()
	)


func _is_point_pair_unoccluded(world: World3D, from: Vector3, to: Vector3) -> bool:
	if world == null or world.direct_space_state == null:
		return true
	var offset: Vector3 = to - from
	var length: float = offset.length()
	if length <= 0.1:
		return true
	var dir: Vector3 = offset / length
	var query := PhysicsRayQueryParameters3D.create(from + dir * 0.05, to - dir * 0.05)
	query.collision_mask = 1 << (Pigments.WORLD_GEOMETRY_LAYER - 1)
	query.collide_with_areas = false
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _get_mirror_quad_corners(mirror: Mirror3D) -> PackedVector3Array:
	if mirror == null or mirror._mirror_quad == null:
		return PackedVector3Array()
	var half: Vector2 = mirror.get_world_size() * 0.5
	var quad_basis: Basis = mirror._mirror_quad.global_basis.orthonormalized()
	var quad_origin: Vector3 = mirror._mirror_quad.global_position
	return PackedVector3Array([
		quad_origin + quad_basis * Vector3(-half.x, -half.y, 0.0),
		quad_origin + quad_basis * Vector3(half.x, -half.y, 0.0),
		quad_origin + quad_basis * Vector3(half.x, half.y, 0.0),
		quad_origin + quad_basis * Vector3(-half.x, half.y, 0.0),
	])


func _clip_polygon_to_plane(
	poly: PackedVector3Array,
	plane_origin: Vector3,
	outward_normal: Vector3,
	min_dist: float
) -> PackedVector3Array:
	var result := PackedVector3Array()
	var count: int = poly.size()
	if count == 0:
		return result

	for i: int in range(count):
		var current: Vector3 = poly[i]
		var next: Vector3 = poly[(i + 1) % count]
		var d_curr: float = (current - plane_origin).dot(outward_normal) - min_dist
		var d_next: float = (next - plane_origin).dot(outward_normal) - min_dist

		var curr_inside: bool = d_curr >= 0.0
		var next_inside: bool = d_next >= 0.0

		if curr_inside:
			result.append(current)
		if curr_inside != next_inside:
			var t: float = d_curr / (d_curr - d_next)
			result.append(current.lerp(next, clampf(t, 0.0, 1.0)))

	return result


func _any_point_within_distance(
	poly: PackedVector3Array,
	origin: Vector3,
	max_distance: float
) -> bool:
	var max_sq: float = max_distance * max_distance
	var count: int = poly.size()
	for i: int in range(count):
		if poly[i].distance_squared_to(origin) <= max_sq:
			return true
		var next: Vector3 = poly[(i + 1) % count]
		var closest: Vector3 = Geometry3D.get_closest_point_to_segment(origin, poly[i], next)
		if closest.distance_squared_to(origin) <= max_sq:
			return true
	return false


func _projected_polygon_overlaps_quad(
	poly: PackedVector3Array,
	reflected_observer: Vector3,
	receiving: Mirror3D
) -> bool:
	if receiving._mirror_quad == null:
		return false

	var quad_basis: Basis = receiving._mirror_quad.global_basis.orthonormalized()
	var quad_origin: Vector3 = receiving._mirror_quad.global_position
	var inv_plane := Transform3D(quad_basis, quad_origin).affine_inverse()

	var local_obs: Vector3 = inv_plane * reflected_observer
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	var valid_points: int = 0

	for world_pt: Vector3 in poly:
		var local_pt: Vector3 = inv_plane * world_pt
		var dz: float = local_pt.z - local_obs.z
		if absf(dz) <= PLANE_EPSILON:
			continue
		var t: float = -local_obs.z / dz
		if t <= 0.0 or t >= 1.0:
			continue
		var proj_x: float = local_obs.x + t * (local_pt.x - local_obs.x)
		var proj_y: float = local_obs.y + t * (local_pt.y - local_obs.y)
		min_x = minf(min_x, proj_x)
		max_x = maxf(max_x, proj_x)
		min_y = minf(min_y, proj_y)
		max_y = maxf(max_y, proj_y)
		valid_points += 1

	if valid_points == 0:
		return false

	var half: Vector2 = receiving.get_world_size() * 0.5
	return (
		max_x >= -half.x
		and min_x <= half.x
		and max_y >= -half.y
		and min_y <= half.y
	)

