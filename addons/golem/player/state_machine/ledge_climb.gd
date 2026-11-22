extends RefCounted

const UP := Vector3.UP
const FORWARD_REACH := 0.75
const MIN_RISE := 0.2
const FACE_PUSH := 3.5
const INTO_DOT := 0.5
const LIP_CLEARANCE := 0.02
const HOP_ABOVE_STEP := 0.08
const HOP_CLEARANCE := 0.2
const HOP_TIME_LIMIT := 0.75


static func apply(body, delta: float) -> void:
	if delta <= 0.0:
		return
	var capsule: CollisionShape3D = body.collision_capsule
	if capsule != null and capsule.disabled:
		body.ledge_pulling = false
		return
	if body.vaulting:
		return

	if not bool(body.wall_climbing):
		body.ledge_block_wall_cut = false
	if body.ledge_pulling:
		if not bool(body.can_climb_ledges):
			body.ledge_pulling = false
			return
		body.ledge_block_wall_cut = true
		if _cancel_jump(body):
			return
		if _cancel_away(body):
			return
		body.ledge_elapsed = float(body.ledge_elapsed) + delta
		if body.ledge_elapsed > HOP_TIME_LIMIT or (body.is_on_floor() and body.ledge_elapsed > 0.05):
			body.ledge_pulling = false
		return

	if not bool(body.can_climb_ledges):
		return
	if body.is_on_floor():
		return
	var velocity: Vector3 = body.velocity
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() <= 0.04:
		return
	var found: Dictionary = _find_ledge(body, horizontal)
	if not bool(found["ok"]):
		return
	if float(body.stair_floor_hold) > 0.0:
		return
	var rise: float = float(found["rise"])
	if rise <= float(body.step_height) + HOP_ABOVE_STEP or (velocity.y <= 0.2 and not body.wall_climbing):
		return
	var gravity: float = maxf(float(body.jump_gravity), 0.1)
	var hop_up: float = sqrt(2.0 * gravity * (rise + HOP_CLEARANCE))
	var target: Vector3 = found["target"]
	var flat := Vector3(target.x - body.global_position.x, 0.0, target.z - body.global_position.z)
	var hop_time: float = hop_up / gravity
	var launch := Vector3.ZERO
	if flat.length_squared() > 0.0001:
		launch = flat.normalized() * (flat.length() / maxf(hop_time, 0.05))
	launch.y = hop_up
	body.velocity = launch
	body.ledge_pulling = true
	body.ledge_block_wall_cut = true
	body.ledge_elapsed = 0.0
	body.ledge_start = body.global_position
	body.ledge_target = target
	body.ledge_face_normal = found["face"]
	var skin: Node = body.godot_plush_skin
	if skin != null and skin.has_method("set_state"):
		skin.set_state("jump")


static func _cancel_jump(body) -> bool:
	var action: String = body.jumpAction
	if action == "" or not Input.is_action_just_pressed(action):
		return false
	body.ledge_pulling = false
	body.ledge_block_wall_cut = true
	body.ledge_jump_launched = true
	body.coyote_jump_on = false
	body.coyote_jump_cooldown = -1.0
	var face: Vector3 = body.ledge_face_normal
	var launch := Vector3(face.x, 0.0, face.z) * FACE_PUSH
	launch.y = -float(body.jump_velocity)
	body.velocity = launch
	return true


static func _cancel_away(body) -> bool:
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
	var into: Vector3 = -body.ledge_face_normal
	if wish.normalized().dot(into) >= INTO_DOT:
		return false
	body.ledge_pulling = false
	body.ledge_block_wall_cut = true
	body.velocity = Vector3.ZERO
	return true


static func _find_ledge(body, horizontal: Vector3) -> Dictionary:
	var none := {"ok": false, "target": Vector3.ZERO, "face": Vector3.FORWARD}
	var shape_node: CollisionShape3D = body.collision_capsule
	if shape_node == null or shape_node.shape == null:
		return none
	var capsule_shape: CapsuleShape3D = shape_node.shape as CapsuleShape3D
	if capsule_shape == null:
		return none
	var capsule_top: float = shape_node.position.y + capsule_shape.height * 0.5
	var reach: float = minf(capsule_top, float(body.ledge_max_height))
	if reach <= MIN_RISE:
		return none
	var max_slope: float = deg_to_rad(float(body.step_max_slope_degrees))
	var body_rid: RID = body.get_rid()
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	var here: Transform3D = body.global_transform
	params.from = here
	params.motion = horizontal.normalized() * FORWARD_REACH
	var blocked: bool = PhysicsServer3D.body_test_motion(body_rid, params, result)
	if not blocked or result.get_collision_count() < 1:
		return none
	var wall_normal: Vector3 = result.get_collision_normal()
	if wall_normal.angle_to(UP) <= max_slope:
		return none
	var face := Vector3(wall_normal.x, 0.0, wall_normal.z)
	if face.length_squared() < 0.0001:
		return none
	face = face.normalized()
	var point: Vector3 = result.get_collision_point()
	var feet_y: float = here.origin.y
	var into: Vector3 = -face
	var probe: Transform3D = here
	var inset: float = capsule_shape.radius + 0.2
	probe.origin = Vector3(point.x, feet_y + reach + 0.05, point.z) + into * inset
	params.from = probe
	params.motion = Vector3(0.0, -(reach + 0.15), 0.0)
	var drop := PhysicsTestMotionResult3D.new()
	var hit: bool = PhysicsServer3D.body_test_motion(body_rid, params, drop)
	if not hit or drop.get_collision_count() < 1:
		return none
	var floor_normal: Vector3 = drop.get_collision_normal()
	if floor_normal.angle_to(UP) > max_slope:
		return none
	var lip_y: float = drop.get_collision_point().y
	var rise: float = lip_y - feet_y
	if rise <= MIN_RISE or rise > reach + 0.001:
		return none
	if lip_y > feet_y + capsule_top + 0.001:
		return none
	var target := Vector3(probe.origin.x, lip_y + LIP_CLEARANCE, probe.origin.z)
	return {"ok": true, "target": target, "face": face, "rise": rise}
