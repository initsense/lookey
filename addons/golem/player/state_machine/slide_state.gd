extends GolemState

class_name GolemSlideState

var state_name: String = "Slide"

var cR: CharacterBody3D


func enter(char_ref: CharacterBody3D):
	cR = char_ref
	cR.godot_plush_skin.set_state("walk")
	cR.floor_snap_length = 1.0
	if not cR.movement_dust.emitting:
		cR.movement_dust.emitting = true


func physics_update(delta: float):
	if cR.vaulting:
		return
	if not cR.is_on_floor():
		cR.store_slide_momentum()
		transitioned.emit(self, "InairState")
		return
	if _hit_wall() or _uphill_too_long(delta):
		_finish_on_floor()
		return

	var slope: float = deg_to_rad(cR.slide_slope_degrees)
	var downhill: bool = cR.get_floor_angle() > slope and cR.get_floor_normal().dot(cR.slide_dir) < -0.05
	if not downhill:
		cR.slide_time_left -= delta
	if cR.slide_time_left <= 0.0:
		_finish_on_floor()
		return

	var duration := maxf(cR.slide_time, 0.001)
	var speed: float = cR.slide_start_speed * clampf(cR.slide_time_left / duration, 0.0, 1.0)
	cR.velocity.x = cR.slide_dir.x * speed
	cR.velocity.z = cR.slide_dir.z * speed

	if Input.is_action_just_pressed(cR.jumpAction):
		cR.store_slide_momentum()
		transitioned.emit(self, "JumpState")


func _finish_on_floor() -> void:
	cR.store_slide_momentum()
	cR.walk_or_run = "WalkState"
	transitioned.emit(self, "WalkState")


func _hit_wall() -> bool:
	for index in cR.get_slide_collision_count():
		var normal := cR.get_slide_collision(index).get_normal()
		if absf(normal.y) < 0.35 and normal.dot(cR.slide_dir) < -0.5:
			return true
	return false


func _uphill_too_long(delta: float) -> bool:
	var slope := deg_to_rad(cR.slide_slope_degrees)
	if cR.get_floor_angle() <= slope or cR.get_floor_normal().dot(cR.slide_dir) <= 0.05:
		cR.slide_uphill_held = 0.0
		return false
	cR.slide_uphill_held += delta
	return cR.slide_uphill_held >= cR.slide_uphill_time
