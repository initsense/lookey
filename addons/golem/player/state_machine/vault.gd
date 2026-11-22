extends RefCounted

const FACE_REACH := 1.25
const CLEARANCE := 1.7
const MIN_TIME := 0.2
const MAX_TIME := 0.5
const LIP_LIFT := 0.4


static func apply(body, delta: float) -> void:
	if delta <= 0.0:
		return
	if body.vaulting:
		_advance(body, delta)
		return
	if _begin(body):
		_advance(body, delta)


static func _begin(body) -> bool:
	if not bool(body.can_vault) or body.wall_climbing or body.ledge_pulling:
		return false
	var state_name := str(body.state_machine.curr_state_name)
	if state_name != "Run" and state_name != "Slide":
		return false
	if not body.is_on_floor() and body.stair_floor_hold <= 0.0:
		return false
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed := horizontal.length()
	if speed < body.vault_min_speed:
		return false
	var direction := horizontal / speed
	var feet: Vector3 = body.global_position
	var face_height: float = float(body.step_height) + 0.08
	var face: Dictionary = body.cast_ray(
		feet + Vector3.UP * face_height,
		feet + Vector3.UP * face_height + direction * FACE_REACH
	)
	if face.is_empty():
		return false
	var normal: Vector3 = face.normal
	if absf(normal.y) > 0.35:
		return false
	var flat_n := Vector3(normal.x, 0.0, normal.z).normalized()
	if flat_n.dot(direction) > -0.5:
		return false
	var clearance_height: float = float(body.vault_max_height) + 0.08
	var blocked_high: Dictionary = body.cast_ray(
		feet + Vector3.UP * clearance_height,
		feet + Vector3.UP * clearance_height + direction * FACE_REACH
	)
	if not blocked_high.is_empty():
		return false

	var inward := -flat_n
	var above_y: float = feet.y + float(body.vault_max_height) + 0.5
	var down_from := Vector3(face.position.x, above_y, face.position.z) + inward * 0.25
	var top: Dictionary = body.cast_ray(down_from, down_from + Vector3.DOWN * (float(body.vault_max_height) + 0.9))
	if top.is_empty():
		return false
	var rise: float = top.position.y - feet.y
	if rise <= body.step_height or rise > body.vault_max_height:
		return false

	var last: Vector3 = top.position
	for step in 8:
		var sample: Vector3 = top.position + inward * (0.2 * float(step + 1))
		var origin := Vector3(sample.x, above_y, sample.z)
		var hit: Dictionary = body.cast_ray(origin, origin + Vector3.DOWN * (float(body.vault_max_height) + 0.9))
		if hit.is_empty() or absf(hit.position.y - top.position.y) > 0.3:
			break
		last = hit.position

	var landing := last - inward * 0.12
	landing.y = last.y
	var blocked: Dictionary = body.cast_ray(landing + Vector3.UP * 0.15, landing + Vector3.UP * CLEARANCE)
	if not blocked.is_empty():
		return false
	var floor_hit: Dictionary = body.cast_ray(landing + Vector3.UP * 0.2, landing + Vector3.DOWN * 0.35)

	body.vault_from = feet
	body.vault_to = landing
	var control := (feet + landing) * 0.5
	control.y = landing.y + LIP_LIFT
	body.vault_control = control
	body.vault_duration = clampf(feet.distance_to(landing) / speed, MIN_TIME, MAX_TIME)
	body.vault_elapsed = 0.0
	body.vault_pop_on_end = floor_hit.is_empty()
	body.vaulting = true
	body.velocity = Vector3.ZERO
	body.floor_snap_length = 0.0
	return true


static func _advance(body, delta: float) -> void:
	body.vault_elapsed += delta
	var duration := maxf(float(body.vault_duration), 0.0001)
	var curve := clampf(body.vault_elapsed / duration, 0.0, 1.0)
	var from_control: Vector3 = body.vault_from.lerp(body.vault_control, curve)
	var control_to: Vector3 = body.vault_control.lerp(body.vault_to, curve)
	body.global_position = from_control.lerp(control_to, curve)
	body.velocity = Vector3.ZERO
	body.floor_snap_length = 0.0
	if curve < 1.0:
		return
	body.global_position = body.vault_to
	body.vaulting = false
	body.floor_snap_length = 1.0
	if body.vault_pop_on_end:
		body.velocity.y = body.vault_pop
