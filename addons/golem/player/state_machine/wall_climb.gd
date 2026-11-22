extends RefCounted

const INTO_DOT := 0.5
const JUST_NEGATIVE := -1.5


static func apply(body, delta: float) -> void:
	if delta <= 0.0:
		return
	var capsule: CollisionShape3D = body.collision_capsule
	if capsule != null and capsule.disabled:
		body.wall_climbing = false
		return
	if body.vaulting or not bool(body.can_climb_walls) or body.ledge_pulling:
		body.wall_climbing = false
		return
	if body.is_on_floor():
		body.wall_climbing = false
		body.wall_climb_armed = false
		body.wall_climb_spent = false
		body.wall_climb_elapsed = 0.0
		return

	var vy: float = body.velocity.y
	if not body.wall_climb_spent and not body.wall_climbing and vy > 0.0:
		body.wall_climb_armed = true

	if body.wall_climbing:
		_keep_climbing(body, delta)
		return

	if body.wall_climb_armed and body.is_on_wall():
		body.wall_climb_armed = false
		body.wall_climb_spent = true
		if vy > JUST_NEGATIVE and _pushing_into_wall(body):
			body.wall_climbing = true
			body.wall_climb_elapsed = 0.0
			_keep_climbing(body, delta)


static func _keep_climbing(body, delta: float) -> void:
	if not body.is_on_wall() or not _pushing_into_wall(body):
		body.wall_climbing = false
		return
	var duration: float = maxf(float(body.wall_climb_time), 0.05)
	body.wall_climb_elapsed = float(body.wall_climb_elapsed) + delta
	var t: float = float(body.wall_climb_elapsed) / duration
	if t >= 1.0:
		body.wall_climbing = false
		return
	var start_speed: float = 2.0 * float(body.wall_climb_height) / duration
	var climb_vy: float = start_speed * (1.0 - t)
	if body.velocity.y < climb_vy:
		body.velocity.y = climb_vy
	body.ledge_block_wall_cut = true


static func _pushing_into_wall(body) -> bool:
	if not body.is_on_wall():
		return false
	var normal: Vector3 = body.get_wall_normal()
	var face := Vector3(normal.x, 0.0, normal.z)
	if face.length_squared() < 0.0001:
		return false
	face = face.normalized()
	var relative: Vector2 = Input.get_vector(body.moveLeftAction, body.moveRightAction, body.moveForwardAction, body.moveBackwardAction)
	if relative.length_squared() < 0.01:
		return false
	var holder: Node3D = body.cam_holder
	var yaw: float = 0.0
	if holder != null:
		yaw = holder.global_rotation.y
	var world: Vector2 = relative.rotated(-yaw)
	var wish := Vector3(world.x, 0.0, world.y)
	if wish.length_squared() < 0.01:
		return false
	return wish.normalized().dot(-face) >= INTO_DOT
