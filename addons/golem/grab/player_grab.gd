class_name PlayerGrab
extends Node
## Picks up the grabbable object under the crosshair, carries it, and throws or drops it.

## How far the crosshair looks for something to pick up, in meters.
@export var reach: float = 4.0
## Distance in front of the camera where a newly picked-up object is held, in meters.
@export var hold_distance: float = 2.0
## Closest the mouse wheel can bring a held object, in meters.
@export var min_hold_distance: float = 1.0
## Farthest the mouse wheel can push a held object, in meters.
@export var max_hold_distance: float = 3.5
## How far one mouse-wheel notch moves a held object, in meters.
@export var distance_step: float = 0.25
## Extra speed added along the view when a held object is thrown, in meters per second.
@export var throw_speed: float = 8.0
## How fast the mouse turns a held object, in radians per pixel.
@export var rotate_speed: float = 0.01
## Physics layers the crosshair searches. The body does not use these layers.
@export_flags_3d_physics var grab_mask: int = 8

var _held: Grabbable = null
var _wanted_basis: Basis = Basis.IDENTITY
var _last_camera_yaw: float = 0.0
var _has_saved_hold_distance: bool = false
var _saved_hold_distance: float = 2.0
var _throw_latched: bool = false
var _queued_interact: bool = false
var _queued_throw: bool = false
var _queued_nearer: bool = false
var _queued_farther: bool = false
var _interact_was_down: bool = false
var _throw_was_down: bool = false
var _nearer_was_down: bool = false
var _farther_was_down: bool = false
var _interact_used: bool = false
var _throw_used: bool = false
var _nearer_used: bool = false
var _farther_used: bool = false


func _ready() -> void:
	# After the object's own physics, so a game can switch the volume off in the same frame.
	process_physics_priority = 10
	if editor_description.is_empty():
		editor_description = (
			"Picks up the object under the crosshair. E or the left mouse button lifts it, "
			+ "the wheel sets how far away it sits, T and the mouse turn it, and a left click throws it."
		)


## True while an object is being carried.
func is_holding() -> bool:
	return _held != null and is_instance_valid(_held)


## True while an object is held and allows at least one rotation direction.
func can_rotate_held() -> bool:
	return is_holding() and _held.can_rotate()


## The body currently carried, or null.
func held_body() -> RigidBody3D:
	if not is_holding():
		return null
	return _held.get_body()


## The grabbable volume the crosshair is pointing at, or null.
func target_under_crosshair() -> Grabbable:
	var camera := _camera()
	if camera == null or grab_mask == 0:
		return null
	var space := camera.get_world_3d().direct_space_state
	if space == null:
		return null
	var from: Vector3 = camera.global_position
	var ray_length: float = maxf(reach, _max_reach_override())
	var to: Vector3 = from + (-camera.global_basis.z) * ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = grab_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return null
	var grabbable := Grabbable.from_collider(hit.get("collider"))
	if grabbable == null or not grabbable.can_be_grabbed():
		return null
	var allowed_reach: float = grabbable.reach_override if grabbable.reach_override > 0.0 else reach
	var hit_position: Vector3 = hit.get("position", to) as Vector3
	if from.distance_to(hit_position) > allowed_reach + 0.001:
		return null
	return grabbable


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_queued_interact = true
	if event.is_action_pressed("throw"):
		_queued_throw = true
	if event.is_action_pressed("hold_nearer"):
		_queued_nearer = true
	if event.is_action_pressed("hold_farther"):
		_queued_farther = true
	if not can_rotate_held():
		return
	if not (event is InputEventMouseMotion):
		return
	if not _action_down("rotate_held"):
		return
	apply_mouse_look((event as InputEventMouseMotion).relative)
	get_viewport().set_input_as_handled()


## Turns the held object according to its rotation settings.
func apply_mouse_look(relative: Vector2) -> void:
	if not can_rotate_held():
		return
	var camera := _camera()
	if camera == null:
		return
	_wanted_basis = _held.compute_rotated_basis(_wanted_basis, relative, camera.global_basis, rotate_speed)


func _physics_process(delta: float) -> void:
	var throw_press := _rising("throw", _queued_throw, _throw_was_down, _throw_used)
	_queued_throw = false
	_throw_was_down = throw_press.down
	_throw_used = throw_press.used
	var interact_press := _rising("interact", _queued_interact, _interact_was_down, _interact_used)
	_queued_interact = false
	_interact_was_down = interact_press.down
	_interact_used = interact_press.used
	var nearer_press := _rising("hold_nearer", _queued_nearer, _nearer_was_down, _nearer_used)
	_queued_nearer = false
	_nearer_was_down = nearer_press.down
	_nearer_used = nearer_press.used
	var farther_press := _rising("hold_farther", _queued_farther, _farther_was_down, _farther_used)
	_queued_farther = false
	_farther_was_down = farther_press.down
	_farther_used = farther_press.used

	var released_this_frame := false
	if is_holding():
		if not _held.can_be_grabbed():
			_drop(Vector3.ZERO)
			released_this_frame = true
		elif throw_press.fired:
			if _held.can_be_thrown():
				var extra := Vector3.ZERO
				var camera := _camera()
				if camera:
					extra = -camera.global_basis.z * (throw_speed * maxf(_held.throw_speed_multiplier, 0.0))
				_drop(extra)
				released_this_frame = true
			_throw_latched = true
		elif interact_press.fired:
			_drop(Vector3.ZERO)
			released_this_frame = true
		else:
			_apply_wheel(nearer_press.fired, farther_press.fired)
			_apply_player_yaw_follow()
			var final_basis := _wanted_basis
			if _held.can_rotate() or _held.follow_player_yaw:
				final_basis = _held.apply_rotation_snap(_wanted_basis)
			_held.hold(_hold_point(), final_basis, delta)
	if _throw_latched and not _action_down("throw"):
		_throw_latched = false
	if not is_holding() and not released_this_frame and not _throw_latched:
		if interact_press.fired or throw_press.fired:
			_try_pickup()
	_update_crosshair()


func _try_pickup() -> void:
	var target := target_under_crosshair()
	if target == null:
		return
	var body := target.get_body()
	if body == null:
		return
	_held = target
	_wanted_basis = body.global_basis
	var camera := _camera()
	if camera != null:
		_last_camera_yaw = _camera_yaw(camera)
	_has_saved_hold_distance = false
	if target.hold_distance_override > 0.0:
		_saved_hold_distance = hold_distance
		_has_saved_hold_distance = true
		hold_distance = target.hold_distance_override
	target.begin_grab()


func _drop(extra_velocity: Vector3) -> void:
	var held := _held
	_held = null
	if _has_saved_hold_distance:
		hold_distance = _saved_hold_distance
		_has_saved_hold_distance = false
	if held != null and is_instance_valid(held):
		held.release(extra_velocity)


func _apply_wheel(nearer_pressed: bool, farther_pressed: bool) -> void:
	if not is_holding() or not _held.can_adjust_distance or not _held.can_move_horizontally:
		return
	var min_d := _effective_min_hold_distance()
	var max_d := _effective_max_hold_distance()
	if nearer_pressed:
		hold_distance = maxf(min_d, hold_distance - distance_step)
	if farther_pressed:
		hold_distance = minf(max_d, hold_distance + distance_step)


func _apply_player_yaw_follow() -> void:
	var camera := _camera()
	if camera == null:
		return
	var current_yaw := _camera_yaw(camera)
	var delta_yaw := wrapf(current_yaw - _last_camera_yaw, -PI, PI)
	_last_camera_yaw = current_yaw
	if is_holding() and _held.follow_player_yaw and absf(delta_yaw) > 0.00001:
		_wanted_basis = (Basis(Vector3.UP, delta_yaw) * _wanted_basis).orthonormalized()


func _effective_min_hold_distance() -> float:
	if is_holding() and _held.hold_distance_override > 0.0:
		return minf(min_hold_distance, _held.hold_distance_override)
	return min_hold_distance


func _effective_max_hold_distance() -> float:
	var min_d := _effective_min_hold_distance()
	var max_d := max_hold_distance
	if is_holding() and _held.hold_distance_override > 0.0:
		max_d = maxf(max_d, _held.hold_distance_override)
	return maxf(min_d, max_d)


func _max_reach_override() -> float:
	var tree := get_tree()
	if tree == null:
		return 0.0
	var max_reach: float = 0.0
	for node: Node in tree.get_nodes_in_group(Grabbable.GROUP_NAME):
		if node is Grabbable:
			var r: float = (node as Grabbable).reach_override
			if r > max_reach:
				max_reach = r
	return max_reach


func _camera_yaw(camera: Camera3D) -> float:
	var forward := -camera.global_basis.z
	return atan2(-forward.x, -forward.z)


func _rising(action: StringName, queued: bool, was_down: bool, used: bool) -> Dictionary:
	var down := _action_down(action)
	var just := _just_pressed(action)
	var fired := (queued or just or (down and not was_down)) and not used
	if fired:
		used = true
	if not down and not just:
		used = false
	return {"fired": fired, "used": used, "down": down}


func _hold_point() -> Vector3:
	var camera := _camera()
	if camera == null:
		return Vector3.ZERO
	return camera.global_position + (-camera.global_basis.z) * hold_distance


func _update_crosshair() -> void:
	var mark_node := get_node_or_null("../Crosshair/Mark") as GrabCrosshair
	if mark_node == null:
		return
	if is_holding():
		mark_node.set_mark(GrabCrosshair.Mark.HELD)
		return
	if target_under_crosshair() != null:
		mark_node.set_mark(GrabCrosshair.Mark.FILLED)
		return
	mark_node.set_mark(GrabCrosshair.Mark.HOLLOW)


func _camera() -> Camera3D:
	var named := get_node_or_null("%Camera3D") as Camera3D
	if named:
		return named
	var parent := get_parent()
	if parent == null:
		return null
	return parent.find_child("Camera3D", true, false) as Camera3D


func _just_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _action_down(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)
