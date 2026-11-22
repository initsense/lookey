extends GolemState

class_name GolemInairState

var state_name: String = "Inair"

var cR: CharacterBody3D
@onready var cam_holder: SpringArm3D = %CamHolder


func enter(char_ref: CharacterBody3D):
	cR = char_ref
	verifications()


func verifications():
	cR.godot_plush_skin.set_state("fall")
	if cR.floor_snap_length != 0.0: cR.floor_snap_length = 0.0
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
		if cR.jump_cooldown > 0.0:
			cR.jump_cooldown -= delta
		if cR.coyote_jump_cooldown > 0.0:
			cR.coyote_jump_cooldown -= delta


func input_management():
	if Input.is_action_just_pressed(cR.jumpAction):
		#check if can jump buffer
		if cR.floor_check.is_colliding() and cR.last_frame_position.y > cR.position.y and cR.nb_jumps_in_air_allowed <= 0: cR.jump_buff_on = true
		#check if can coyote jump
		if cR.was_on_floor and cR.coyote_jump_cooldown > 0.0 and cR.last_frame_position.y > cR.position.y:
			cR.coyote_jump_on = true
			transitioned.emit(self, "JumpState")
		transitioned.emit(self, "JumpState")
	
	if Input.is_action_just_pressed("ragdoll"):
		if not cR.godot_plush_skin.ragdoll and not cR.can_ragdoll_on_floor_only:
			transitioned.emit(self, "RagdollState")
	
	if Input.is_action_just_pressed("crouch"):
		cR.toggle_crouch(cR.move_speed)


func check_if_floor():
	if cR.ledge_pulling:
		return
	if cR.is_on_floor():
		cR.release_crouch_on_land()
		if cR.jump_buff_on:
			cR.buffered_jump = true
			cR.jump_buff_on = false
			transitioned.emit(self, "JumpState")
		
		if cam_holder.camera_mode != cam_holder.Camera.FIRST:
			cR.squash_and_strech(0.8, 0.08)
			cR.particles_manager.display_particles(cR.land_particles, cR)
		
		impact_audio_playing()
		
		if cR.can_landing_shake:
			cam_holder.trigger_camera_shake()
		
		if cR.move_dir:
			transitioned.emit(self, cR.walk_or_run)
		else:
			transitioned.emit(self, "IdleState")
	
	if cR.is_on_wall():
		if cR.can_hit_wall_cut_velocity and not cR.ledge_block_wall_cut and cR.wall_run_lockout <= 0.0:
			cR.velocity.x = 0.0
			cR.velocity.z = 0.0


func move(delta: float):
	cR.move_dir_relative = Input.get_vector(cR.moveLeftAction, cR.moveRightAction, cR.moveForwardAction, cR.moveBackwardAction)
	cR.move_dir = cR.move_dir_relative.rotated(-cR.cam_holder.global_rotation.y)
	
	cR.apply_air_move(delta)


func impact_audio_playing():
	#audio played when play char touch the ground after being in air
	#the volume is calculated based on the velocity pre ground hit, plus the fall gravity
	var floor_impact_percent: float = clamp(abs(cR.velocity.y), 0.0, cR.fall_gravity) / cR.fall_gravity
	cR.impact_audio.volume_db = linear_to_db(remap(floor_impact_percent, 0.0, 1.0, 0.5, 2.0))
	cR.impact_audio.play()
