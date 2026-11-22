extends GolemState

class_name GolemRunState

var state_name : String = "Run"

var cR : CharacterBody3D


func enter(char_ref : CharacterBody3D):
	cR = char_ref
	
	verifications()


func verifications():
	if cR.pose == cR.Pose.CROUCHED:
		cR.pose = cR.Pose.STANDING
		cR.emit_signal("pose_changed")
		print("standing")
	
	cR.godot_plush_skin.set_state("run")
	cR.move_speed = cR.run_speed
	cR.move_accel = cR.run_accel
	cR.move_deccel = cR.run_deccel
	
	cR.floor_snap_length = 1.0
	if cR.jump_cooldown > 0.0:
		cR.jump_cooldown = -1.0
	if cR.nb_jumps_in_air_allowed < cR.nb_jumps_in_air_allowed_ref:
		cR.nb_jumps_in_air_allowed = cR.nb_jumps_in_air_allowed_ref
	if cR.coyote_jump_cooldown < cR.coyote_jump_cooldown_ref:
		cR.coyote_jump_cooldown = cR.coyote_jump_cooldown_ref
	if not cR.movement_dust.emitting:
		cR.movement_dust.emitting = true


func update(_delta : float):
	pass


func physics_update(delta : float):
	if cR.vaulting:
		return
	if cR.try_wall_run():
		transitioned.emit(self, "WallRunState")
		return
	check_if_floor()
	
	cR.apply_gravity(delta)
	
	input_management()
	if cR.state_machine.curr_state != self:
		return
	move(delta)


func check_if_floor():
	if not cR.is_on_floor():
		if cR.velocity.y < 0.0:
			transitioned.emit(self, "InairState")
	
	if cR.is_on_floor():
		if cR.jump_buff_on:
			cR.buffered_jump = true
			cR.jump_buff_on = false
			transitioned.emit(self, "JumpState")


func input_management():
	if Input.is_action_pressed(cR.jumpAction) if cR.can_auto_jump else Input.is_action_just_pressed(cR.jumpAction) :
		transitioned.emit(self, "JumpState")
	
	if cR.can_continuous_run:
		#has to press run button once to run
		if Input.is_action_just_pressed(cR.runAction):
			cR.walk_or_run = "WalkState"
			transitioned.emit(self, "WalkState")
	else:
		#has to continuously press run button to run
		if not Input.is_action_pressed(cR.runAction):
			cR.walk_or_run = "WalkState"
			transitioned.emit(self, "WalkState")
	
	if Input.is_action_just_pressed("ragdoll"):
		if not cR.godot_plush_skin.ragdoll:
			transitioned.emit(self, "RagdollState")
	
	if Input.is_action_just_pressed("crouch"):
		var horiz := Vector2(cR.velocity.x, cR.velocity.z).length()
		if cR.can_slide and cR.is_on_floor() and horiz >= cR.slide_min_speed:
			cR.begin_slide()
			transitioned.emit(self, "SlideState")
			return
		cR.toggle_crouch(cR.run_speed)
		cR.walk_or_run = "WalkState"
		transitioned.emit(self, "WalkState")
		return


func move(delta : float):
	cR.move_dir_relative = Input.get_vector(cR.moveLeftAction, cR.moveRightAction, cR.moveForwardAction, cR.moveBackwardAction)
	cR.move_dir = cR.move_dir_relative.rotated(-cR.cam_holder.global_rotation.y)
	
	cR.move_speed = cR.run_speed + cR.slide_momentum
	if cR.move_dir and (cR.is_on_floor() or cR.stair_floor_hold > 0.0):
		cR.velocity.x = lerp(cR.velocity.x, cR.move_dir.x * cR.move_speed, cR.move_accel * delta)
		cR.velocity.z = lerp(cR.velocity.z, cR.move_dir.y * cR.move_speed, cR.move_accel * delta)
	else:
		transitioned.emit(self, "IdleState")
