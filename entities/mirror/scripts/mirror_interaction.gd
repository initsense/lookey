extends Node3D

var is_object_visible_to_player: bool = false
var is_magic_happening: bool = false
var reflection_notifier: VisibleOnScreenNotifier3D
var is_mirror_visible: bool

@onready var _mirror: Mirror3D = get_parent()
# Fetched directly via get_node rather than _mirror_quad: this
# script's _ready() runs BEFORE Mirror3D's _ready() (children ready before
# parents in Godot), so Mirror3D's own @onready var _mirror_quad is still
# null at that point. get_node only needs the node to exist in the tree,
# which it does.
@onready var _mirror_quad: MeshInstance3D = _mirror.get_node("Quad")
@onready var original_notifier: VisibleOnScreenNotifier3D = \
	_mirror.object_to_reflect.get_node("VisibleOnScreenNotifier3D")
@onready var original_mesh: MeshInstance3D = \
	_mirror.object_to_reflect.get_node("MeshInstance3D")
@onready var reflection_mesh: MeshInstance3D = original_mesh

# RIDs to exclude from every raycast: the object's own body, the player's
# own body, and the mirror's own collider. Populated in _ready().
var _exclude_rids: Array[RID] = []

# Small margin the raycast segments are shrunk by from both ends, so a
# ray doesn't start or end exactly touching a collider surface.
const SURFACE_EPSILON: float = 0.01

# --- Frame staggering ---
# With many objects reflected by the same mirror, running every object's
# full per-vertex raycast loop every physics frame is wasteful. Instead,
# each instance only runs the expensive loop once every STAGGER_GROUP_SIZE
# frames, and different instances are offset so they don't all land on the
# same frame. Cheap checks (mirror visibility, notifier, distance culls)
# still run every frame, so state still reacts promptly to gross changes;
# only the fine-grained raycast result is a frame or two "stale" at worst.
const STAGGER_GROUP_SIZE: int = 4
static var _next_stagger_index: int = 0
var _stagger_index: int = 0


func _ready() -> void:
	_create_reflection()
	_collect_exclude_rids()

	_stagger_index = _next_stagger_index
	_next_stagger_index = (_next_stagger_index + 1) % STAGGER_GROUP_SIZE


func _physics_process(_delta: float) -> void:
	if not _mirror.player:
		return

	if not _passes_cheap_gates():
		_set_visibility_state(false)
		return

	# Expensive part: only run the full per-vertex raycast loop on this
	# instance's assigned frame slot. On other frames, keep the last known
	# state instead of recomputing it.
	if Engine.get_physics_frames() % STAGGER_GROUP_SIZE != _stagger_index:
		return

	_update_reflection_transform(original_mesh, reflection_mesh)
	_set_visibility_state(_any_vertex_reflection_visible())


## Cheap, frame-safe checks that rule out reflection visibility before the
## expensive per-vertex raycast loop is even considered. All are checked
## every physics frame regardless of staggering, so state reacts instantly
## to gross changes (mirror off-screen, object out of range, etc).
func _passes_cheap_gates() -> bool:
	if not is_mirror_visible:
		return false  # mirror itself isn't on screen at all

	var camera_to_mirror: float = _mirror.global_position.distance_to(
		_mirror.player_cam.global_position
	)
	if camera_to_mirror >= _mirror.freeze_distance:
		return false  # mirror is frozen, same threshold Mirror3D uses

	if not is_object_visible_to_player:
		return false  # reflected proxy isn't roughly on-screen (notifier)

	var object_to_mirror: float = original_mesh.global_position.distance_to(
		_mirror_quad.global_position
	)
	if object_to_mirror > _mirror.cull_far:
		return false  # farther than the mirror ever renders

	return true


## Returns true as soon as any vertex's reflection has an unobstructed path
## to the player camera. Full precision: every vertex of every surface is
## checked (only skipped via frame staggering upstream, never sampled).
func _any_vertex_reflection_visible() -> bool:
	var mirror_plane_normal: Vector3 = _mirror_quad.global_basis.z.normalized()
	var mirror_plane_origin: Vector3 = _mirror_quad.global_position
	var target_point: Vector3 = _mirror.player_cam.global_position

	var mesh: Mesh = original_mesh.mesh
	var mesh_transform: Transform3D = original_mesh.global_transform

	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

		for local_vertex in vertices:
			var world_vertex: Vector3 = mesh_transform * local_vertex

			if _is_vertex_reflection_visible(
				world_vertex, mirror_plane_normal, mirror_plane_origin, target_point
			):
				return true

	return false


## Centralizes the is_magic_happening transition + logging so every early
## exit and the full raycast result all update state the same way.
func _set_visibility_state(is_visible: bool) -> void:
	if is_visible and not is_magic_happening:
		is_magic_happening = true
		print("✅ Visible reflection!!!")
	elif not is_visible and is_magic_happening:
		is_magic_happening = false
		print("❌ Reflection not visible")


func _create_reflection() -> void:

	reflection_mesh = MeshInstance3D.new()
	add_child(reflection_mesh)
	reflection_mesh.layers = 1 << 9

	reflection_mesh.mesh = original_mesh.mesh
	reflection_mesh.transform = original_mesh.transform

	reflection_notifier = VisibleOnScreenNotifier3D.new()
	reflection_mesh.add_child(reflection_notifier)
	reflection_notifier.aabb = original_notifier.aabb
	reflection_notifier.layers = 1 << 9

	_update_reflection_transform(original_mesh, reflection_mesh)

	reflection_notifier.screen_entered.connect(
		_on_mirror_notifier_entered)

	reflection_notifier.screen_exited.connect(
		_on_mirror_notifier_exited)


func _update_reflection_transform(original, reflection) -> void:
	reflection.global_transform = _reflect_across_mirror(
		original.global_transform
	)


func _reflect_across_mirror(reflect: Transform3D) -> Transform3D:

	var mirror_normal: Vector3 = _mirror_quad.global_basis.z.normalized()
	var mirror_origin: Vector3 = _mirror_quad.global_position
	var reflected_position: Vector3 = _reflect_point(reflect.origin, mirror_normal, mirror_origin)
	var reflected_basis: Basis = reflect.basis

	reflected_basis.x -= (2.0 * reflected_basis.x.dot(mirror_normal) * mirror_normal)
	reflected_basis.y -= (2.0 * reflected_basis.y.dot(mirror_normal) * mirror_normal)
	reflected_basis.z -= (2.0 * reflected_basis.z.dot(mirror_normal) * mirror_normal)

	return Transform3D(reflected_basis, reflected_position)


func _reflect_point(point: Vector3, normal: Vector3, plane_origin: Vector3) -> Vector3:
	var distance: float = (point - plane_origin).dot(normal)
	return point - 2.0 * distance * normal


## Returns true if a light path from world_vertex, bouncing off the mirror's
## physical surface, can reach target_point (the player camera) unobstructed.
func _is_vertex_reflection_visible(
	world_vertex: Vector3,
	mirror_normal: Vector3,
	mirror_origin: Vector3,
	target_point: Vector3
) -> bool:

	var reflected_vertex: Vector3 = _reflect_point(world_vertex, mirror_normal, mirror_origin)

	# Where does the segment (reflected_vertex -> target_point) cross the
	# mirror's plane? That crossing point IS the real point on the mirror
	# surface where the light physically bounces.
	var direction: Vector3 = target_point - reflected_vertex
	var denom: float = direction.dot(mirror_normal)
	if is_zero_approx(denom):
		return false  # parallel to the mirror plane, no crossing

	var t: float = (mirror_origin - reflected_vertex).dot(mirror_normal) / denom
	if t < 0.0 or t > 1.0:
		return false  # the plane crossing isn't between the two points

	var q: Vector3 = reflected_vertex + t * direction  # point on mirror surface

	# Reject if outside the mirror's actual physical bounds (not the
	# infinite plane).
	if not _is_point_within_mirror_bounds(q):
		return false

	# Real segment 1: object vertex -> mirror surface point.
	if _raycast_blocked(world_vertex, q):
		return false

	# Real segment 2: mirror surface point -> camera.
	if _raycast_blocked(q, target_point):
		return false

	return true


func _is_point_within_mirror_bounds(world_point: Vector3) -> bool:
	var local_point: Vector3 = _mirror_quad.global_transform.affine_inverse() * world_point
	return absf(local_point.x) <= _mirror.size.x * 0.5 \
		and absf(local_point.y) <= _mirror.size.y * 0.5


## Casts a ray between two points, shrunk slightly inward from both ends so
## it doesn't immediately re-hit whatever surface it starts or ends on.
## (The known offenders — the object's own body, the mirror's own body,
## the player's own body — are already excluded via _exclude_rids; this is
## just a generic safety margin for anything else touching either point.)
func _raycast_blocked(from: Vector3, to: Vector3) -> bool:
	var space_state := get_world_3d().direct_space_state

	var offset: Vector3 = to - from
	var length: float = offset.length()
	if length <= SURFACE_EPSILON * 2.0:
		return false  # points are effectively coincident, nothing to block

	var direction: Vector3 = offset / length
	var adjusted_from: Vector3 = from + direction * SURFACE_EPSILON
	var adjusted_to: Vector3 = to - direction * SURFACE_EPSILON

	var query := PhysicsRayQueryParameters3D.create(adjusted_from, adjusted_to)
	query.exclude = _exclude_rids
	query.collide_with_areas = false

	var result: Dictionary = space_state.intersect_ray(query)
	return not result.is_empty()


## Gathers physics body RIDs that should never count as an "obstruction":
## the reflected object's own body, the player's own body, and the mirror's
## own collider (the ray legitimately touches it at Q).
func _collect_exclude_rids() -> void:
	_exclude_rids.clear()

	var object_body: CollisionObject3D = _find_collision_object(_mirror.object_to_reflect)
	if object_body:
		_exclude_rids.append(object_body.get_rid())

	if _mirror.player:
		_exclude_rids.append(_mirror.player.get_rid())

	var mirror_body: CollisionObject3D = _find_collision_object(_mirror_quad)
	if mirror_body:
		_exclude_rids.append(mirror_body.get_rid())


func _find_collision_object(from_node: Node) -> CollisionObject3D:
	var node: Node = from_node
	while node:
		if node is CollisionObject3D:
			return node
		node = node.get_parent()
	return null


#region SIGNALS
func _on_mirror_notifier_entered() -> void:
	is_object_visible_to_player = true

func _on_mirror_notifier_exited() -> void:
	is_object_visible_to_player = false


func _on_mirror_notifier_screen_entered() -> void:
	is_mirror_visible = true

func _on_mirror_notifier_screen_exited() -> void:
	is_mirror_visible = false
#endregion
