extends RefCounted

# Stair stepping adapted from mrezai/GodotStairs, MIT License.
# https://github.com/mrezai/GodotStairs

const WALL_MARGIN := 0.001
const STEP_DOWN_MARGIN := 0.01
const STEP_CHECK_COUNT := 2
const UP := Vector3.UP
const EDGE_INSET := 0.08
const TREAD_CLEARANCE := 0.04
const FLOOR_HOLD_SECONDS := 0.4
const SETTLE_DISTANCE := 0.08
const MIN_STEP_RISE := 0.12


static func apply(body, delta: float) -> void:
	if body.vaulting or not bool(body.can_climb_stairs):
		return
	var capsule: CollisionShape3D = body.collision_capsule
	if capsule != null and capsule.disabled:
		return
	var velocity: Vector3 = body.velocity
	if velocity.y > 0.01:
		body.stair_floor_hold = 0.0
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() <= 0.0001:
		return
	var step_height: float = body.step_height
	if step_height <= 0.0:
		return

	var climbed: Dictionary = _step_up(body, horizontal, delta, step_height)
	if bool(climbed["ok"]):
		var climb_diff: Vector3 = climbed["diff"]
		body.global_position += climb_diff
		body.stair_floor_hold = FLOOR_HOLD_SECONDS
		if body.velocity.y < 0.0:
			var stopped: Vector3 = body.velocity
			stopped.y = 0.0
			body.velocity = stopped
		_ease_camera(body, climb_diff.y)
		return

	if body.is_on_floor():
		body.stair_floor_hold = 0.0
		var dropped: Dictionary = _step_down(body, horizontal, delta, step_height)
		if bool(dropped["ok"]):
			var drop_diff: Vector3 = dropped["diff"]
			body.global_position += drop_diff
			_ease_camera(body, drop_diff.y)
		return

	var hold: float = body.stair_floor_hold
	if hold <= 0.0:
		return
	body.stair_floor_hold = hold - delta
	if body.velocity.y < 0.0:
		body.velocity.y = 0.0
	var settled: Dictionary = _settle_onto_tread(body, step_height)
	if bool(settled["ok"]):
		var settle_diff: Vector3 = settled["diff"]
		body.global_position += settle_diff
		body.stair_floor_hold = 0.0
		_ease_camera(body, settle_diff.y)


static func _ease_camera(body, world_delta_y: float) -> void:
	var holder: Node = body.cam_holder
	if holder != null and holder.has_method("note_stair_step"):
		holder.note_stair_step(world_delta_y)


static func _step_up(body, horizontal: Vector3, delta: float, step_height: float) -> Dictionary:
	var max_slope: float = deg_to_rad(float(body.step_max_slope_degrees))
	var increment: float = step_height / float(STEP_CHECK_COUNT)
	var skin: float = maxf(float(body.safe_margin), 0.0)
	var body_rid: RID = body.get_rid()
	for i in STEP_CHECK_COUNT:
		var height: float = step_height - float(i) * increment + skin
		var lift := Vector3(0.0, height, 0.0)
		var params := PhysicsTestMotionParameters3D.new()
		var result := PhysicsTestMotionResult3D.new()
		var here: Transform3D = body.global_transform
		params.from = here
		params.motion = lift
		var blocked: bool = PhysicsServer3D.body_test_motion(body_rid, params, result)
		var ceiling_normal := Vector3.ZERO
		if result.get_collision_count() > 0:
			ceiling_normal = result.get_collision_normal()
		if blocked and ceiling_normal.y < 0.0:
			continue

		var raised: Transform3D = here
		raised.origin += lift
		var forward_motion: Vector3 = horizontal * delta
		params.from = raised
		params.motion = forward_motion
		blocked = PhysicsServer3D.body_test_motion(body_rid, params, result)
		var landed: Dictionary = {"ok": false, "diff": Vector3.ZERO}
		if not blocked:
			landed = _drop_onto_step(raised, forward_motion, lift, max_slope, step_height, body_rid)
		else:
			var wall_normal: Vector3 = result.get_collision_normal()
			if wall_normal.angle_to(UP) <= max_slope:
				landed = _drop_onto_step(raised, Vector3.ZERO, lift, max_slope, step_height, body_rid)
			else:
				var slid_from: Transform3D = raised
				slid_from.origin += wall_normal * WALL_MARGIN
				var slid: Vector3 = forward_motion.slide(wall_normal)
				params.from = slid_from
				params.motion = slid
				blocked = PhysicsServer3D.body_test_motion(body_rid, params, result)
				if not blocked:
					landed = _drop_onto_step(slid_from, slid, lift, max_slope, step_height, body_rid)
		if bool(landed["ok"]):
			return landed
	return {"ok": false, "diff": Vector3.ZERO}


static func _drop_onto_step(from: Transform3D, forward: Vector3, lift: Vector3, max_slope: float, step_height: float, body_rid: RID) -> Dictionary:
	var dropped: Transform3D = from
	dropped.origin += forward
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	params.from = dropped
	params.motion = -lift
	var blocked: bool = PhysicsServer3D.body_test_motion(body_rid, params, result)
	var floor_normal := Vector3.ZERO
	if result.get_collision_count() > 0:
		floor_normal = result.get_collision_normal()
	var remainder: Vector3 = result.get_remainder()
	if blocked and floor_normal.angle_to(UP) <= max_slope:
		return _rise_from_remainder(remainder, step_height)
	if blocked:
		var point: Vector3 = result.get_collision_point()
		var feet_y: float = from.origin.y - lift.y
		var rise: float = point.y - feet_y
		if rise > 0.001 and rise <= step_height + 0.001:
			var toward := Vector3(point.x - dropped.origin.x, 0.0, point.z - dropped.origin.z)
			if toward.length_squared() > 0.0001:
				var probe_from := dropped
				var dir: Vector3 = toward.normalized()
				probe_from.origin = Vector3(point.x, dropped.origin.y, point.z) + dir * EDGE_INSET
				params.from = probe_from
				params.motion = -lift
				var probe_result := PhysicsTestMotionResult3D.new()
				var probe_hit: bool = PhysicsServer3D.body_test_motion(body_rid, params, probe_result)
				var probe_normal: Vector3 = probe_result.get_collision_normal()
				if probe_hit and probe_normal.angle_to(UP) <= max_slope:
					var probe_remainder: Vector3 = probe_result.get_remainder()
					return _rise_from_remainder(probe_remainder, step_height)
	return {"ok": false, "diff": Vector3.ZERO}


static func _rise_from_remainder(remainder: Vector3, step_height: float) -> Dictionary:
	var diff: Vector3 = -remainder
	if diff.y > MIN_STEP_RISE and diff.y <= step_height + 0.001:
		diff.y = minf(diff.y + TREAD_CLEARANCE, step_height)
		return {"ok": true, "diff": diff}
	return {"ok": false, "diff": Vector3.ZERO}


static func _settle_onto_tread(body, step_height: float) -> Dictionary:
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	var here: Transform3D = body.global_transform
	var body_rid: RID = body.get_rid()
	params.from = here
	params.motion = Vector3(0.0, -SETTLE_DISTANCE, 0.0)
	var blocked: bool = PhysicsServer3D.body_test_motion(body_rid, params, result)
	var floor_normal := Vector3.ZERO
	if result.get_collision_count() > 0:
		floor_normal = result.get_collision_normal()
	var max_slope: float = deg_to_rad(float(body.step_max_slope_degrees))
	if blocked and floor_normal.angle_to(UP) <= max_slope:
		var travel: Vector3 = result.get_travel()
		if travel.y < -0.001 and -travel.y <= step_height:
			return {"ok": true, "diff": travel}
	return {"ok": false, "diff": Vector3.ZERO}


static func _step_down(body, horizontal: Vector3, delta: float, step_height: float) -> Dictionary:
	var max_slope: float = deg_to_rad(float(body.step_max_slope_degrees))
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	var forward: Vector3 = horizontal * delta
	var here: Transform3D = body.global_transform
	var body_rid: RID = body.get_rid()
	params.from = here
	params.motion = forward
	params.recovery_as_collision = true
	var blocked: bool = PhysicsServer3D.body_test_motion(body_rid, params, result)
	if not blocked:
		return _drop_down(here, forward, step_height, max_slope, body_rid)
	var wall_normal: Vector3 = result.get_collision_normal()
	if not is_zero_approx(wall_normal.y):
		return {"ok": false, "diff": Vector3.ZERO}
	var slid_from: Transform3D = here
	slid_from.origin += wall_normal * WALL_MARGIN
	var slid: Vector3 = forward.slide(wall_normal)
	params.from = slid_from
	params.motion = slid
	blocked = PhysicsServer3D.body_test_motion(body_rid, params, result)
	if blocked:
		return {"ok": false, "diff": Vector3.ZERO}
	return _drop_down(slid_from, slid, step_height, max_slope, body_rid)


static func _drop_down(from: Transform3D, forward: Vector3, step_height: float, max_slope: float, body_rid: RID) -> Dictionary:
	var dropped: Transform3D = from
	dropped.origin += forward
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	params.from = dropped
	params.motion = Vector3(0.0, -step_height, 0.0)
	var blocked: bool = PhysicsServer3D.body_test_motion(body_rid, params, result)
	var travel: Vector3 = result.get_travel()
	var floor_normal: Vector3 = result.get_collision_normal()
	if blocked and travel.y < -STEP_DOWN_MARGIN and floor_normal.angle_to(UP) <= max_slope:
		return {"ok": true, "diff": travel}
	return {"ok": false, "diff": Vector3.ZERO}
