extends GolemState

class_name GolemWalkState

var state_name : String = "Walk"

var cR : CharacterBody3D
@onready var cam_holder : SpringArm3D = %CamHolder


func enter(char_ref : CharacterBody3D):
	cR = char_ref

	verifications()


func verifications():
	cR.godot_plush_skin.set_state("walk")
	
	if cR.pose == cR.Pose.STANDING:
		cR.move_speed = cR.walk_speed
	elif cR.pose == cR.Pose.CROUCHED:
		cR.move_speed = cR.crouch_speed
	
	cR.move_accel = cR.walk_accel
	cR.move_deccel = cR.walk_deccel
	
	cR.floor_snap_length = 1.0
	if cR.jump_cooldown > 0.0: cR.jump_cooldown = -1.0
	if cR.nb_jumps_in_air_allowed < cR.nb_jumps_in_air_allowed_ref: cR.nb_jumps_in_air_allowed = cR.nb_jumps_in_air_allowed_ref
	if cR.coyote_jump_cooldown < cR.coyote_jump_cooldown_ref: cR.coyote_jump_cooldown = cR.coyote_jump_cooldown_ref
	if cR.movement_dust.emitting: cR.movement_dust.emitting = false


func update(_delta : float):
	pass


func physics_update(delta : float):
	check_if_floor()
	cR.apply_gravity(delta)
	input_management()
	move(delta)


func check_if_floor():
	if !cR.is_on_floor() and !cR.is_on_wall():
		if cR.velocity.y < 0.0:
			transitioned.emit(self, "InairState")
			
	if cR.is_on_floor():
		if cR.jump_buff_on:
			#apply jump buffering
			cR.buffered_jump = true
			cR.jump_buff_on = false
			transitioned.emit(self, "JumpState")


func input_management():
	if Input.is_action_pressed(cR.jumpAction) if cR.can_auto_jump else Input.is_action_just_pressed(cR.jumpAction) :
		transitioned.emit(self, "JumpState")
	
	if Input.is_action_just_pressed(cR.runAction) and cR.pose != cR.Pose.CROUCHED:
		cR.walk_or_run = "RunState"
		transitioned.emit(self, "RunState")
	
	if Input.is_action_just_pressed("ragdoll"):
		if !cR.godot_plush_skin.ragdoll:
			transitioned.emit(self, "RagdollState")
	
	if Input.is_action_just_pressed("crouch"):
		cR.toggle_crouch(cR.walk_speed)


func move(delta : float):
	cR.move_dir_relative = Input.get_vector(cR.moveLeftAction, cR.moveRightAction, cR.moveForwardAction, cR.moveBackwardAction)
	cR.move_dir = cR.move_dir_relative.rotated(-cR.cam_holder.global_rotation.y)
	
	if cR.move_dir and (cR.is_on_floor() or cR.stair_floor_hold > 0.0):
		#apply smooth move
		cR.velocity.x = lerp(cR.velocity.x, cR.move_dir.x * cR.move_speed, cR.move_accel * delta)
		cR.velocity.z = lerp(cR.velocity.z, cR.move_dir.y * cR.move_speed, cR.move_accel * delta)
	else:
		transitioned.emit(self, "IdleState")
