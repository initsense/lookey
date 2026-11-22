extends GolemState

class_name GolemWallRunState

const LOCKOUT := 0.35

var state_name: String = "WallRun"

var cR: CharacterBody3D


func enter(char_ref: CharacterBody3D):
	cR = char_ref
	cR.wall_run_elapsed = 0.0
	cR.floor_snap_length = 0.0
	cR.godot_plush_skin.set_state("fall")
	if cR.movement_dust.emitting:
		cR.movement_dust.emitting = false


func physics_update(delta: float):
	if cR.vaulting:
		return
	cR.wall_run_elapsed += delta
	if cR.wall_run_elapsed >= cR.wall_run_time or not cR.refresh_wall_run():
		transitioned.emit(self, "InairState")
		return
	if cR.is_on_floor() and cR.wall_run_elapsed > 0.15:
		transitioned.emit(self, "IdleState")
		return
	if Input.is_action_just_pressed(cR.jumpAction):
		cR.velocity = cR.wall_run_normal * cR.wall_jump_speed + Vector3.UP * cR.wall_jump_speed
		cR.wall_run_lockout = LOCKOUT
		transitioned.emit(self, "InairState")
		return

	var along: float = clampf(cR.wall_run_elapsed / maxf(cR.wall_run_time, 0.001), 0.0, 1.0)
	var gravity_scale: float = lerpf(cR.wall_run_gravity_scale, 1.0, along)
	if cR.velocity.y >= 0.0:
		cR.velocity.y -= cR.jump_gravity * delta
	else:
		cR.velocity.y -= cR.fall_gravity * gravity_scale * delta

	var target: Vector3 = cR.wall_run_dir * cR.wall_run_speed - cR.wall_run_normal * 3.0
	var blend := clampf(8.0 * delta, 0.0, 1.0)
	cR.velocity.x = lerpf(cR.velocity.x, target.x, blend)
	cR.velocity.z = lerpf(cR.velocity.z, target.z, blend)
