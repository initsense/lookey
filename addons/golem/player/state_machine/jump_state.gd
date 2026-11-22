extends GolemState

class_name GolemJumpState

var state_name: String = "Jump"

var cR: CharacterBody3D

@onready var cam_holder: SpringArm3D = %CamHolder


func enter(char_ref: CharacterBody3D):
	cR = char_ref
	
	verifications()
	jump()


func verifications():
	if cR.pose == cR.Pose.CROUCHED:
		cR.pose = cR.Pose.STANDING
		cR.uncrouch_on_land = true
		cR.emit_signal("pose_changed")
	
	cR.godot_plush_skin.set_state("jump")
	if cR.floor_snap_length != 0.0: cR.floor_snap_length = 0.0
	if cR.jump_cooldown < cR.jump_cooldown_ref: cR.jump_cooldown = cR.jump_cooldown_ref
	if cR.movement_dust.emitting: cR.movement_dust.emitting = false


func update(_delta: float):
	pass


func physics_update(delta: float):
	if cR.vaulting:
		return
	if cR.try_wall_run():
		transitioned.emit(self, "WallRunState")
		return
	applies(delta)
	cR.apply_gravity(delta)
	input_management()
	check_if_floor()
	move(delta)


func applies(delta: float):
	if not cR.is_on_floor():
		if cR.jump_cooldown > 0.0: cR.jump_cooldown -= delta
		if cR.coyote_jump_cooldown > 0.0: cR.coyote_jump_cooldown -= delta


func input_management():
	if Input.is_action_just_pressed(cR.jumpAction):
		jump()
	
	if Input.is_action_just_pressed("ragdoll"):
		if not cR.godot_plush_skin.ragdoll and not cR.can_ragdoll_on_floor_only:
			transitioned.emit(self, "RagdollState")


func check_if_floor():
	if cR.ledge_pulling:
		return
	if not cR.is_on_floor() and cR.velocity.y < 0.0:
		transitioned.emit(self, "InairState")
	
	if cR.is_on_floor():
		cR.release_crouch_on_land()
		if cR.move_dir: transitioned.emit(self, cR.walk_or_run)
		else: transitioned.emit(self, "IdleState")
	
	if cR.is_on_wall():
		#if enabled, cut velocity when the play char hit a wall
		if cR.can_hit_wall_cut_velocity and not cR.ledge_block_wall_cut and cR.wall_run_lockout <= 0.0:
			cR.velocity.x = 0.0
			cR.velocity.z = 0.0


func move(delta: float):
	cR.move_dir_relative = Input.get_vector(cR.moveLeftAction, cR.moveRightAction, cR.moveForwardAction, cR.moveBackwardAction)
	cR.move_dir = cR.move_dir_relative.rotated(-cR.cam_holder.global_rotation.y)
	
	cR.apply_air_move(delta)


func jump():
	if cR.ledge_jump_launched:
		cR.ledge_jump_launched = false
		return
	# jump condition
	var can_jump: bool = false
	
	# in air jump
	if not cR.is_on_floor():
		if cR.coyote_jump_on:
			cR.jump_cooldown = cR.jump_cooldown_ref
			cR.coyote_jump_cooldown = -1.0 # so that the character cannot immediately make another coyote jump
			cR.coyote_jump_on = false
			can_jump = true
		elif cR.nb_jumps_in_air_allowed > 0:
			cR.nb_jumps_in_air_allowed -= 1
			cR.jump_cooldown = cR.jump_cooldown_ref
			can_jump = true
	
	# on floor jump
	if cR.is_on_floor():
		cR.jump_cooldown = cR.jump_cooldown_ref
		can_jump = true
		
	# jump buffering
	if cR.buffered_jump:
		cR.buffered_jump = false
		cR.nb_jumps_in_air_allowed = cR.nb_jumps_in_air_allowed_ref
	
	# apply jump
	if can_jump:
		cR.velocity.y = - cR.jump_velocity
		can_jump = false
	
		# play squash and strech effect, and display jump particles
		if cR.is_on_floor() and cam_holder.camera_mode != cam_holder.Camera.FIRST:
			cR.squash_and_strech(1.12, 0.1)
			cR.particles_manager.display_particles(cR.jump_particles, cR)
