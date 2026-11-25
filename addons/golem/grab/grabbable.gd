@tool
class_name Grabbable
extends Node3D
## Lets the player pick up the object this node belongs to. It creates an internal pickup volume on its own physics layer and does not block the body.

## Emitted once the rigid body this node drives is ready at runtime.
signal target_body_ready(body: RigidBody3D)

## Group every pickup volume joins, so the grab ray can find it.
const GROUP_NAME: StringName = &"grabbable"
## Fastest default speed the carry will shove the body toward the hold point, in meters per second.
const MAX_CARRY_SPEED: float = 20.0
## Name used when Grabbable creates a rigid body at runtime.
const GENERATED_BODY_NAME: StringName = &"Collider"
## Name used when Grabbable creates its internal pickup Area3D at runtime.
const GRAB_AREA_NAME: StringName = &"GrabArea"
## Transient collision body created by UniBuilder meshes; skipped so objects are not solid twice.
const UNIBUILDER_COLLISION_NAME: StringName = &"_UBCollision"
## Minimum box thickness (meters) when falling back from a flat mesh such as a quad.
const FLAT_SHAPE_THICKNESS: float = 0.08

## How this object behaves after the player lets go of it.
enum ReleaseMode {
	## Gravity pulls the object down normally.
	FALL,
	## Gravity stays off so the object drifts weightlessly where released.
	FLOAT,
	## The object freezes completely still in place where released.
	FREEZE,
}

@export_category("Grabbable")

@export_group("Pickup")
## Turns pickup on or off for this object without removing the node.
@export var can_be_picked_up: bool = true:
	set(value):
		can_be_picked_up = value
		if not Engine.is_editor_hint() and is_inside_tree():
			_apply_grab_area_layers()
## Maximum distance (in meters) from which the player can grab this object. Leave at 0 to use the player's default reach.
@export_range(0.0, 20.0, 0.1) var reach_override: float = 0.0

@export_group("Carry")
## Lets the player move this object horizontally (left, right, forward, backward) while carrying it.
@export var can_move_horizontally: bool = true:
	set(value):
		can_move_horizontally = value
		_notify_inspector_changed()
## Lets the player lift or lower this object vertically while carrying it.
@export var can_move_vertically: bool = true:
	set(value):
		can_move_vertically = value
		_notify_inspector_changed()
## Lets the player pull this object closer or push it farther with the mouse wheel while holding it.
@export var can_adjust_distance: bool = true
## Fastest speed (in meters per second) the carry pulls this object toward the hold point. Lower values make heavy objects feel slower.
@export_range(0.1, 60.0, 0.5) var max_carry_speed: float = MAX_CARRY_SPEED
## Starting hold distance in front of the camera (in meters) when picked up. Leave at 0 to use the player's default.
@export_range(0.0, 15.0, 0.1) var hold_distance_override: float = 0.0

@export_group("Rotation")
## Lets the player spin this object left and right (yaw) while holding the rotate key.
@export var can_rotate_horizontally: bool = true:
	set(value):
		can_rotate_horizontally = value
		_notify_inspector_changed()
## Lets the player tilt this object up and down (pitch) while holding the rotate key.
@export var can_rotate_vertically: bool = true:
	set(value):
		can_rotate_vertically = value
		_notify_inspector_changed()
## Lets a diagonal mouse movement spin and tilt this object at the same time. Turn off to restrict each mouse move to whichever direction (horizontal or vertical) is stronger.
@export var can_rotate_diagonally: bool = true
## Keeps this object upright (no sideways roll) while rotating it on both axes.
@export var keep_upright: bool = false
## Turns this object horizontally with the player as they look around while carrying it, even without holding the rotate key.
@export var follow_player_yaw: bool = false:
	set(value):
		follow_player_yaw = value
		_notify_inspector_changed()
## Scales how fast this object turns while holding the rotate key.
@export_range(0.05, 5.0, 0.05) var rotate_speed_multiplier: float = 1.0
## Snaps rotation to steps of this many degrees (for example 45 or 90). Leave at 0 for smooth free rotation.
@export_range(0.0, 180.0, 1.0) var rotation_snap_degrees: float = 0.0

@export_group("Release & Physics")
## What happens to this object when you let go: fall with gravity, float weightlessly, or freeze still in place.
@export var release_mode: ReleaseMode = ReleaseMode.FALL:
	set(value):
		release_mode = value
		_notify_inspector_changed()
## Lets the player throw this object with the throw button. Turn off so it can only be set down gently.
@export var can_throw: bool = true:
	set(value):
		can_throw = value
		_notify_inspector_changed()
## Scales how hard the player throws this object.
@export_range(0.1, 5.0, 0.05) var throw_speed_multiplier: float = 1.0
## Keeps this object at its exact angle after you let go, so it can still fall or drift without tumbling or tipping over.
@export var lock_rotation_on_release: bool = false
## Mass of the rigid body in kilograms. Leave at 0 to keep an existing RigidBody3D's own mass (or 1 kg for generated bodies).
@export_range(0.0, 100.0, 0.05) var body_mass: float = 0.0

@export_group("Setup")
## Physics layers this pickup volume occupies. Leave at 0 to use the project's "Grab" layer automatically.
@export_flags_3d_physics var grab_mask: int = 0:
	set(value):
		grab_mask = value
		if not Engine.is_editor_hint() and is_inside_tree():
			_apply_grab_area_layers()
## The rigid body this node carries. Leave empty to discover the parent object's collider automatically.
@export var body_path: NodePath = NodePath()
## Physics layers a converted or generated rigid body collides with while falling. Leave at 0 to detect automatically.
@export_flags_3d_physics var world_collision_mask: int = 0
## Physics layer given to a fallback rigid body generated from meshes. Leave at 0 to detect automatically.
@export_flags_3d_physics var solid_collision_layer: int = 0

var _enabled: bool = true
var _body: RigidBody3D = null
var _target_root: Node3D = null
var _direct_body_parent: bool = false
var _setup_done: bool = false
var _leaving: bool = false
var _parent_leaving: bool = false
var _watched_parent: Node = null
var _grab_area: Area3D = null
var _generated_area: Area3D = null
var _generated_shapes: Array[CollisionShape3D] = []
var _generated_body: RigidBody3D = null
var _suspended_static_parent: StaticBody3D = null
var _saved_static_layer: int = 0
var _saved_static_mask: int = 0
var _saved_self_collision_mode: Dictionary = {}
var _grab_start_position: Vector3 = Vector3.ZERO


## Resolves the Grabbable node that owns a raycast hit collider.
static func from_collider(collider: Object) -> Grabbable:
	if collider == null or not is_instance_valid(collider):
		return null
	if collider is Grabbable:
		return collider as Grabbable
	if collider is Node:
		var node := collider as Node
		if node.has_meta(&"grabbable"):
			var owner_grab := node.get_meta(&"grabbable") as Grabbable
			if owner_grab != null and is_instance_valid(owner_grab):
				return owner_grab
		var parent := node.get_parent()
		if parent is Grabbable:
			return parent as Grabbable
	return null


func _ready() -> void:
	add_to_group(GROUP_NAME)
	if editor_description.is_empty():
		editor_description = "Lets the player pick up the object this node belongs to. It does not block the body."
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	process_physics_priority = -5
	_enabled = true
	_ensure_grab_area()
	_apply_grab_area_layers()
	_watch_parent_exit()

	var immediate_body := _immediate_rigid_body()
	if immediate_body != null:
		_body = immediate_body
		_target_root = _resolve_target_root()
		_direct_body_parent = (get_parent() == _body)
		_body.freeze = true
		_apply_body_mass(_body)
		_sync_pickup_shapes(_body)
		_setup_done = true
		target_body_ready.emit(_body)
	else:
		_setup_target.call_deferred()


func _notification(what: int) -> void:
	if Engine.is_editor_hint() and (what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_CHILD_ORDER_CHANGED):
		update_configuration_warnings()


func _exit_tree() -> void:
	_leaving = true
	if Engine.is_editor_hint():
		return
	set_grab_enabled(false)
	_unwatch_parent_exit()
	if not _parent_leaving:
		_restore_suspended_colliders()
		_clear_generated_shapes()
		if _generated_area != null and is_instance_valid(_generated_area):
			var area_to_free := _generated_area
			_generated_area = null
			_grab_area = null
			area_to_free.collision_layer = 0
			area_to_free.collision_mask = 0
			area_to_free.queue_free()
		if _generated_body != null and is_instance_valid(_generated_body):
			var body_to_free := _generated_body
			_generated_body = null
			body_to_free.collision_layer = 0
			body_to_free.collision_mask = 0
			body_to_free.queue_free()
	else:
		_saved_self_collision_mode.clear()
		_suspended_static_parent = null
		_generated_body = null
		_generated_area = null
		_grab_area = null


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_sync_from_body()


func _sync_from_body() -> void:
	if _body == null or not is_instance_valid(_body) or not _body.is_inside_tree():
		return
	if _direct_body_parent:
		return
	if not _body.freeze:
		if not _body.top_level:
			_body.top_level = true
		if _target_root != null and is_instance_valid(_target_root) and _target_root != _body:
			var kept_scale: Vector3 = _target_root.scale
			_target_root.global_position = _body.global_position
			_target_root.global_rotation = _body.global_rotation
			_target_root.scale = kept_scale
	if _grab_area != null and is_instance_valid(_grab_area):
		_grab_area.global_transform = _body.global_transform
		_grab_area.force_update_transform()


func _validate_property(property: Dictionary) -> void:
	var prop_name: String = property.get("name", "") as String
	var read_only: bool = false
	var can_move_any: bool = can_move_horizontally or can_move_vertically
	var can_rotate_any: bool = can_rotate_horizontally or can_rotate_vertically
	var can_rotate_both: bool = can_rotate_horizontally and can_rotate_vertically
	var freezes_on_release: bool = release_mode == ReleaseMode.FREEZE
	match prop_name:
		"can_adjust_distance":
			read_only = not can_move_horizontally
		"max_carry_speed", "hold_distance_override":
			read_only = not can_move_any
		"can_rotate_diagonally", "keep_upright":
			read_only = not can_rotate_both
		"rotate_speed_multiplier":
			read_only = not can_rotate_any
		"rotation_snap_degrees":
			read_only = not can_rotate_any and not follow_player_yaw
		"can_throw", "lock_rotation_on_release":
			read_only = freezes_on_release
		"throw_speed_multiplier":
			read_only = freezes_on_release or not can_throw
	if read_only:
		property["usage"] = int(property.get("usage", 0)) | PROPERTY_USAGE_READ_ONLY


func _notify_inspector_changed() -> void:
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _apply_body_mass(body: RigidBody3D) -> void:
	if body != null and is_instance_valid(body) and body_mass > 0.0:
		body.mass = maxf(body_mass, 0.05)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not body_path.is_empty():
		var pointed := get_node_or_null(body_path)
		if not (pointed is RigidBody3D):
			warnings.append("Body Path does not point to a RigidBody3D.")
		return warnings
	var target := _resolve_target_root()
	if target == null:
		warnings.append("Place Grabbable as a child of a 3D node so it knows what object to pick up.")
		return warnings
	if _has_manual_shapes():
		return warnings
	if target is PhysicsBody3D or _find_child_body(target) != null or _has_geometry(target):
		return warnings
	warnings.append("No collider or mesh found on the parent object, so there is nothing to pick up.")
	return warnings


## Ensures runtime discovery has run and returns the rigid body this node drives.
func ensure_setup() -> RigidBody3D:
	if Engine.is_editor_hint() or not is_inside_tree():
		return _body
	if not _setup_done or _body == null or not is_instance_valid(_body):
		_setup_target()
	return _body


## Re-copies collision shapes from the current rigid body when no manual shapes are present.
func refresh_shapes() -> void:
	if Engine.is_editor_hint() or _body == null or not is_instance_valid(_body):
		return
	_sync_pickup_shapes(_body)


## The runtime Area3D pickup volume that the grab ray detects, or null in the editor.
func get_grab_area() -> Area3D:
	if _grab_area != null and is_instance_valid(_grab_area):
		return _grab_area
	return null


## The rigid body this volume moves. Empty when no body has been found yet.
func get_body() -> RigidBody3D:
	if _body != null and is_instance_valid(_body):
		return _body
	return _immediate_rigid_body()


## The 3D node whose position and rotation follow this node's rigid body.
func get_target_root() -> Node3D:
	if _target_root != null and is_instance_valid(_target_root):
		return _target_root
	return _resolve_target_root()


## False while this pickup is switched off or has no rigid body to move.
func can_be_grabbed() -> bool:
	return can_be_picked_up and _enabled and get_body() != null


## True when at least one rotation direction is enabled for this object.
func can_rotate() -> bool:
	return (can_rotate_horizontally or can_rotate_vertically) and rotate_speed_multiplier > 0.0


## True when the player can throw this object with the throw button.
func can_be_thrown() -> bool:
	return can_throw and release_mode != ReleaseMode.FREEZE


## Turns the pickup volume on or off. Off removes it from the grab ray.
func set_grab_enabled(enabled: bool) -> void:
	_enabled = enabled
	_apply_grab_area_layers()


## Applies this object's rotation rules (axis locks, diagonal lock, upright lock) to a raw desired basis.
func compute_rotated_basis(current_basis: Basis, relative: Vector2, view_basis: Basis, base_rotate_speed: float) -> Basis:
	if not can_rotate():
		return current_basis
	var dx: float = relative.x if can_rotate_horizontally else 0.0
	var dy: float = relative.y if can_rotate_vertically else 0.0
	if not can_rotate_diagonally and dx != 0.0 and dy != 0.0:
		if absf(dx) >= absf(dy):
			dy = 0.0
		else:
			dx = 0.0
	if dx == 0.0 and dy == 0.0:
		return current_basis

	var speed: float = base_rotate_speed * maxf(rotate_speed_multiplier, 0.0)
	var yaw: float = -dx * speed
	var pitch: float = -dy * speed

	var next_basis: Basis = current_basis
	if keep_upright or not can_rotate_vertically:
		if yaw != 0.0:
			next_basis = Basis(Vector3.UP, yaw) * next_basis
		if pitch != 0.0:
			var horiz_right := Vector3(view_basis.x.x, 0.0, view_basis.x.z)
			if horiz_right.length_squared() < 0.0001:
				horiz_right = Vector3.RIGHT
			else:
				horiz_right = horiz_right.normalized()
			next_basis = Basis(horiz_right, pitch) * next_basis
		if keep_upright:
			var euler := next_basis.get_euler()
			if can_rotate_vertically:
				euler.x = clampf(euler.x, -1.48, 1.48)
			else:
				euler.x = 0.0
			euler.z = 0.0
			next_basis = Basis.from_euler(euler)
	else:
		next_basis = Basis(view_basis.y, yaw) * Basis(view_basis.x, pitch) * next_basis
	return next_basis.orthonormalized()


## Snaps a desired basis to rotation_snap_degrees when snapping is enabled.
func apply_rotation_snap(desired_basis: Basis) -> Basis:
	if rotation_snap_degrees <= 0.0:
		return desired_basis
	var step: float = deg_to_rad(rotation_snap_degrees)
	var euler := desired_basis.get_euler()
	euler.x = snappedf(euler.x, step)
	euler.y = snappedf(euler.y, step)
	euler.z = snappedf(euler.z, step)
	return Basis.from_euler(euler).orthonormalized()


## Wakes the body and takes gravity off so the carry can steer it.
func begin_grab() -> void:
	var body := get_body()
	if body == null:
		return
	_grab_start_position = body.global_position
	if not _direct_body_parent and not body.top_level:
		body.top_level = true
	_apply_body_mass(body)
	body.lock_rotation = false
	body.freeze = false
	body.sleeping = false
	body.gravity_scale = 0.0
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO


## Shoves the body toward the hold point and keeps the facing the carry asked for.
func hold(target_position: Vector3, target_basis: Basis, delta: float) -> void:
	var body := get_body()
	if body == null:
		return
	if not _direct_body_parent and not body.top_level:
		body.top_level = true
	body.freeze = false
	body.sleeping = false
	body.gravity_scale = 0.0

	var clamped_target := target_position
	if not can_move_horizontally:
		clamped_target.x = _grab_start_position.x
		clamped_target.z = _grab_start_position.z
	if not can_move_vertically:
		clamped_target.y = _grab_start_position.y

	var speed_cap: float = maxf(max_carry_speed, 0.0)
	var pinned: bool = not can_move_horizontally and not can_move_vertically
	var velocity := Vector3.ZERO
	if not pinned:
		var offset: Vector3 = clamped_target - body.global_position
		velocity = offset / maxf(delta, 0.001)
		if velocity.length() > speed_cap:
			velocity = velocity.normalized() * speed_cap

	var rid: RID = body.get_rid()
	var current := PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
	if pinned:
		current.origin = _grab_start_position
	current.basis = target_basis
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, current)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	if not _direct_body_parent and _target_root != null and is_instance_valid(_target_root) and _target_root != body:
		var kept_scale: Vector3 = _target_root.scale
		_target_root.global_position = current.origin
		_target_root.global_basis = target_basis
		_target_root.scale = kept_scale
	body.gravity_scale = 0.0


## Releases the body according to its release_mode (fall, float, or freeze), rotation lock, and optional throw velocity.
func release(extra_velocity: Vector3) -> void:
	var body := get_body()
	if body == null:
		return
	var rid: RID = body.get_rid()
	body.lock_rotation = lock_rotation_on_release
	if release_mode == ReleaseMode.FREEZE:
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.gravity_scale = 0.0
		body.freeze = true
		if not _direct_body_parent and _target_root != null and is_instance_valid(_target_root) and _target_root != body:
			var kept_scale: Vector3 = _target_root.scale
			_target_root.global_position = body.global_position
			_target_root.global_rotation = body.global_rotation
			_target_root.scale = kept_scale
		return
	body.freeze = false
	body.sleeping = false
	var current_velocity := PhysicsServer3D.body_get_state(
		rid,
		PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY
	) as Vector3
	var next_velocity := current_velocity + extra_velocity
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, next_velocity)
	body.linear_velocity = next_velocity
	body.gravity_scale = 1.0 if release_mode == ReleaseMode.FALL else 0.0


func _ensure_grab_area() -> Area3D:
	if _grab_area != null and is_instance_valid(_grab_area):
		return _grab_area
	var manual_area := _find_manual_grab_area()
	if manual_area != null:
		_grab_area = manual_area
	else:
		var area := Area3D.new()
		area.name = GRAB_AREA_NAME
		add_child(area)
		_generated_area = area
		_grab_area = area
	_grab_area.monitoring = false
	_grab_area.monitorable = true
	_grab_area.collision_mask = 0
	_grab_area.set_meta(&"grabbable", self)
	_grab_area.add_to_group(GROUP_NAME)
	return _grab_area


func _find_manual_grab_area() -> Area3D:
	for child: Node in get_children():
		if child is Area3D and child != _generated_area:
			return child as Area3D
	return null


func _apply_grab_area_layers() -> void:
	if _grab_area == null or not is_instance_valid(_grab_area):
		return
	_grab_area.collision_mask = 0
	_grab_area.collision_layer = _resolved_grab_mask() if (_enabled and can_be_picked_up) else 0


func _immediate_rigid_body() -> RigidBody3D:
	if not body_path.is_empty():
		return get_node_or_null(body_path) as RigidBody3D
	return get_parent() as RigidBody3D


func _resolve_target_root() -> Node3D:
	if not body_path.is_empty():
		return get_node_or_null(body_path) as Node3D
	var parent := get_parent()
	if parent == null:
		return null
	if parent.has_method(&"_controlled_root_3d"):
		return parent.call(&"_controlled_root_3d") as Node3D
	return parent as Node3D


func _setup_target() -> void:
	if (
		(_setup_done and _body != null and is_instance_valid(_body))
		or Engine.is_editor_hint()
		or not is_inside_tree()
		or _leaving
	):
		return
	_setup_done = true
	_ensure_grab_area()
	var target := _resolve_target_root()
	_target_root = target
	if target == null:
		return

	if not body_path.is_empty():
		_body = get_node_or_null(body_path) as RigidBody3D
		_direct_body_parent = (get_parent() == _body)
	elif target is RigidBody3D:
		_body = target as RigidBody3D
		_direct_body_parent = (get_parent() == _body)
	else:
		_suspend_self_colliding_meshes(target)
		var existing := _find_child_body(target)
		if existing is RigidBody3D:
			_body = existing as RigidBody3D
		elif existing is StaticBody3D:
			_body = _convert_static_to_rigid(existing as StaticBody3D)
		elif target is StaticBody3D:
			_body = _wrap_static_parent(target as StaticBody3D)
		else:
			_body = _build_body_from_meshes(target)

	if _body == null or not is_instance_valid(_body):
		return
	_body.freeze = true
	_body.gravity_scale = 1.0
	_apply_body_mass(_body)
	if not _direct_body_parent and _grab_area != null and is_instance_valid(_grab_area):
		_grab_area.top_level = true
		_grab_area.global_transform = _body.global_transform
		_grab_area.force_update_transform()
	_sync_pickup_shapes(_body)
	_apply_grab_area_layers()
	target_body_ready.emit(_body)


func _find_child_body(root: Node) -> PhysicsBody3D:
	return _find_child_body_under(root, root)


func _find_child_body_under(node: Node, root: Node) -> PhysicsBody3D:
	if not is_instance_valid(node) or node == self:
		return null
	if node != root:
		if node is Grabbable:
			return null
		if _is_separate_owner(node, root):
			return null
		if node is PhysicsBody3D and node.name != UNIBUILDER_COLLISION_NAME and not (node is AnimatableBody3D):
			return node as PhysicsBody3D
	for child: Node in node.get_children():
		var found := _find_child_body_under(child, root)
		if found != null:
			return found
	return null


func _is_separate_owner(node: Node, root: Node) -> bool:
	if node == root:
		return false
	if node.has_method(&"_controlled_root_3d"):
		var controlled: Node = node.call(&"_controlled_root_3d") as Node
		return controlled != root
	if node.get_node_or_null("Interaction") != null and node.get_node_or_null("MirrorNotifier") != null:
		return true
	return false


func _convert_static_to_rigid(static_body: StaticBody3D) -> RigidBody3D:
	var parent: Node = static_body.get_parent()
	var index: int = static_body.get_index()
	var local_xform: Transform3D = static_body.transform
	var rigid := RigidBody3D.new()
	rigid.name = static_body.name
	rigid.freeze = true
	rigid.gravity_scale = 1.0
	rigid.collision_layer = static_body.collision_layer
	rigid.collision_mask = static_body.collision_mask | _resolved_world_mask()
	rigid.editor_description = static_body.editor_description
	var children: Array[Node] = []
	for child: Node in static_body.get_children():
		children.append(child)
	for child: Node in children:
		static_body.remove_child(child)
	parent.remove_child(static_body)
	parent.add_child(rigid)
	parent.move_child(rigid, mini(index, parent.get_child_count() - 1))
	rigid.transform = local_xform
	if static_body.owner != null:
		rigid.owner = static_body.owner
	for child: Node in children:
		rigid.add_child(child)
	static_body.free()
	return rigid


func _wrap_static_parent(static_parent: StaticBody3D) -> RigidBody3D:
	_suspended_static_parent = static_parent
	_saved_static_layer = static_parent.collision_layer
	_saved_static_mask = static_parent.collision_mask
	var rigid := RigidBody3D.new()
	rigid.name = GENERATED_BODY_NAME
	rigid.freeze = true
	rigid.gravity_scale = 1.0
	rigid.collision_layer = _saved_static_layer
	rigid.collision_mask = _saved_static_mask | _resolved_world_mask()
	static_parent.add_child(rigid)
	rigid.transform = Transform3D.IDENTITY
	for child: Node in static_parent.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var copy := CollisionShape3D.new()
		copy.name = shape_node.name
		copy.shape = shape_node.shape
		copy.transform = shape_node.transform
		copy.disabled = shape_node.disabled
		rigid.add_child(copy)
	static_parent.collision_layer = 0
	static_parent.collision_mask = 0
	_generated_body = rigid
	return rigid


func _build_body_from_meshes(target: Node3D) -> RigidBody3D:
	var meshes: Array[GeometryInstance3D] = []
	_gather_geometries(target, target, meshes)
	if meshes.is_empty():
		return null
	var rigid := RigidBody3D.new()
	rigid.name = GENERATED_BODY_NAME
	rigid.freeze = true
	rigid.gravity_scale = 1.0
	rigid.collision_layer = _resolved_solid_layer()
	rigid.collision_mask = _resolved_world_mask()
	rigid.editor_description = "Solid body built from this object's shapes so the player can pick it up."
	target.add_child(rigid)
	rigid.global_transform = Transform3D(target.global_basis.orthonormalized(), target.global_position)
	for geometry: GeometryInstance3D in meshes:
		_add_shape_for_geometry(rigid, geometry)
	if rigid.get_child_count() == 0:
		target.remove_child(rigid)
		rigid.free()
		return null
	_generated_body = rigid
	return rigid


func _add_shape_for_geometry(body: RigidBody3D, geometry: GeometryInstance3D) -> void:
	var geometry_mesh := _geometry_mesh(geometry)
	if geometry_mesh == null:
		return
	var to_body: Transform3D = body.global_transform.affine_inverse() * geometry.global_transform
	var aabb: AABB = geometry_mesh.get_aabb()
	var is_flat: bool = (
		aabb.size.x < 0.01
		or aabb.size.y < 0.01
		or aabb.size.z < 0.01
	)
	var shape_node := CollisionShape3D.new()
	shape_node.name = "%sShape" % geometry.name
	if is_flat:
		var box := BoxShape3D.new()
		var scale_vec := to_body.basis.get_scale()
		box.size = Vector3(
			maxf(aabb.size.x * absf(scale_vec.x), FLAT_SHAPE_THICKNESS),
			maxf(aabb.size.y * absf(scale_vec.y), FLAT_SHAPE_THICKNESS),
			maxf(aabb.size.z * absf(scale_vec.z), FLAT_SHAPE_THICKNESS)
		)
		shape_node.shape = box
		shape_node.transform = Transform3D(to_body.basis.orthonormalized(), to_body * aabb.get_center())
	else:
		var convex: ConvexPolygonShape3D = geometry_mesh.create_convex_shape(true, false)
		if convex == null or convex.points.is_empty():
			return
		var points: PackedVector3Array = convex.points
		for i: int in range(points.size()):
			points[i] = to_body * points[i]
		convex.points = points
		shape_node.shape = convex
	body.add_child(shape_node)


func _geometry_mesh(geometry: GeometryInstance3D) -> Mesh:
	if geometry is MeshInstance3D:
		return (geometry as MeshInstance3D).mesh
	if geometry is CSGShape3D:
		return (geometry as CSGShape3D).bake_static_mesh()
	return null


func _has_geometry(root: Node) -> bool:
	var meshes: Array[GeometryInstance3D] = []
	_gather_geometries(root, root, meshes)
	return not meshes.is_empty()


func _gather_geometries(node: Node, root: Node, into: Array[GeometryInstance3D]) -> void:
	if not is_instance_valid(node) or node == self:
		return
	if node != root:
		if node is Grabbable or _is_separate_owner(node, root):
			return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.visible and mi.mesh != null:
			into.append(mi)
	elif node is CSGShape3D and (node as CSGShape3D).is_root_shape():
		into.append(node as GeometryInstance3D)
	for child: Node in node.get_children():
		_gather_geometries(child, root, into)


func _suspend_self_colliding_meshes(root: Node) -> void:
	_suspend_self_colliding_under(root, root)


func _suspend_self_colliding_under(node: Node, root: Node) -> void:
	if not is_instance_valid(node) or node == self:
		return
	if node != root and (node is Grabbable or _is_separate_owner(node, root)):
		return
	if _is_self_colliding_mesh(node):
		var mode: int = int(node.get(&"collision_mode"))
		if mode != 0:
			if not _saved_self_collision_mode.has(node):
				_saved_self_collision_mode[node] = mode
			node.set(&"collision_mode", 0)
	for child: Node in node.get_children():
		_suspend_self_colliding_under(child, root)


func _is_self_colliding_mesh(node: Node) -> bool:
	return (
		node.has_method(&"refresh_collision")
		and node.get(&"collision_mode") != null
		and node.get(&"collision_layer") != null
		and node.get(&"collision_mask") != null
	)


func _restore_suspended_colliders() -> void:
	if _suspended_static_parent != null and is_instance_valid(_suspended_static_parent):
		if _suspended_static_parent.is_inside_tree():
			_suspended_static_parent.collision_layer = _saved_static_layer
			_suspended_static_parent.collision_mask = _saved_static_mask
	_suspended_static_parent = null
	for node: Variant in _saved_self_collision_mode.keys():
		if is_instance_valid(node) and (node as Node).is_inside_tree():
			(node as Object).set_deferred(&"collision_mode", int(_saved_self_collision_mode[node]))
	_saved_self_collision_mode.clear()


func _has_manual_shapes() -> bool:
	var manual_area := _find_manual_grab_area()
	if manual_area != null:
		for child: Node in manual_area.get_children():
			if child is CollisionShape3D and not _generated_shapes.has(child):
				return true
	for child: Node in get_children():
		if child is CollisionShape3D and not _generated_shapes.has(child):
			return true
	return false


func _clear_generated_shapes() -> void:
	for shape_node: CollisionShape3D in _generated_shapes:
		if is_instance_valid(shape_node):
			var shape_parent := shape_node.get_parent()
			if shape_parent != null:
				shape_parent.remove_child(shape_node)
			shape_node.free()
	_generated_shapes.clear()


func _sync_pickup_shapes(body: RigidBody3D) -> void:
	var area := _ensure_grab_area()
	var manual_area := _find_manual_grab_area()
	if manual_area != null:
		for child: Node in manual_area.get_children():
			if child is CollisionShape3D and not _generated_shapes.has(child):
				return
	var direct_manual_shapes: Array[CollisionShape3D] = []
	for child: Node in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node != null and shape_node.shape != null and not _generated_shapes.has(shape_node):
			direct_manual_shapes.append(shape_node)
	if not direct_manual_shapes.is_empty():
		_clear_generated_shapes()
		for shape_node: CollisionShape3D in direct_manual_shapes:
			var copy := CollisionShape3D.new()
			copy.name = shape_node.name
			copy.shape = shape_node.shape
			copy.transform = shape_node.transform
			copy.disabled = shape_node.disabled
			area.add_child(copy)
			_generated_shapes.append(copy)
		return
	_copy_shapes_from_body(body)


func _copy_shapes_from_body(body: RigidBody3D) -> void:
	var area := _ensure_grab_area()
	_clear_generated_shapes()
	for child: Node in body.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var copy := CollisionShape3D.new()
		copy.name = shape_node.name
		copy.shape = shape_node.shape
		copy.transform = shape_node.transform
		copy.disabled = shape_node.disabled
		area.add_child(copy)
		_generated_shapes.append(copy)


func _watch_parent_exit() -> void:
	var parent := get_parent()
	if parent == _watched_parent:
		return
	_unwatch_parent_exit()
	if parent == null:
		return
	_watched_parent = parent
	if not parent.tree_exiting.is_connected(_on_parent_tree_exiting):
		parent.tree_exiting.connect(_on_parent_tree_exiting)


func _unwatch_parent_exit() -> void:
	var parent := _watched_parent
	_watched_parent = null
	if parent != null and is_instance_valid(parent) and parent.tree_exiting.is_connected(_on_parent_tree_exiting):
		parent.tree_exiting.disconnect(_on_parent_tree_exiting)


func _on_parent_tree_exiting() -> void:
	_parent_leaving = true


func _resolved_grab_mask() -> int:
	if grab_mask != 0:
		return grab_mask
	var named := _find_physics_layers(["grab"])
	return named if named != 0 else 8


func _resolved_world_mask() -> int:
	if world_collision_mask != 0:
		return world_collision_mask
	var named := _find_physics_layers(["environment", "objects", "entity_collider"])
	return named if named != 0 else 2


func _resolved_solid_layer() -> int:
	if solid_collision_layer != 0:
		return solid_collision_layer
	var entity_layer := _find_physics_layers(["entity_collider"])
	if entity_layer != 0:
		return entity_layer
	var env_layer := _find_physics_layers(["environment"])
	return env_layer if env_layer != 0 else 2


static func _find_physics_layers(target_names: Array[String]) -> int:
	var mask: int = 0
	for layer_index: int in range(1, 33):
		var key := "layer_names/3d_physics/layer_%d" % layer_index
		if not ProjectSettings.has_setting(key):
			continue
		var label := String(ProjectSettings.get_setting(key)).strip_edges().to_lower()
		if label.is_empty():
			continue
		if target_names.has(label):
			mask |= 1 << (layer_index - 1)
	return mask
