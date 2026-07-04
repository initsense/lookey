extends State

class_name InairState

var state_name : String = "Inair"

var cR : CharacterBody3D
@onready var head: SpringArm3D = %Head


func enter(char_ref : CharacterBody3D):
	cR = char_ref
	verifications()


func verifications():
	if cR.floor_snap_length != 0.0:  cR.floor_snap_length = 0.0


func update(_delta : float):
	pass


func physics_update(delta : float):
	
	if cR.velocity.y > 0.0 and cR.has_cut_jump:
		apply_gravity(delta)
	else:
		cR.apply_gravity(delta)
	
	check_if_floor()
	move(delta)


func apply_gravity(delta : float):
	if cR.velocity.y >= 0.0:
		cR.velocity.y -= cR.jump_gravity / cR.jump_cut_multiplier * delta


func check_if_floor():
	if cR.is_on_floor():
		
		if cR.move_dir:
			transitioned.emit(self, cR.walk_or_run)
		else:
			transitioned.emit(self, "IdleState")
	
	if cR.is_on_wall():
		if cR.hit_wall_cut_velocity:
			cR.velocity.x = 0.0
			cR.velocity.z = 0.0


func move(delta : float):
	cR.move_dir_relative = Input.get_vector(cR.moveLeftAction, cR.moveRightAction, cR.moveForwardAction, cR.moveBackwardAction)
	cR.move_dir = cR.move_dir_relative.rotated(-cR.head.global_rotation.y)
	
	if cR.move_dir and not cR.is_on_floor():
		var in_air_move_speed_val : float
		var in_air_accel_val : float
		if cR.walk_or_run == "WalkState":
			in_air_move_speed_val = cR.in_air_move_speed[0].sample(cR.velocity.length())
			in_air_accel_val = cR.in_air_accel[0].sample(cR.velocity.length())
		
		cR.velocity.x = lerp(cR.velocity.x, cR.move_dir.x * in_air_move_speed_val, in_air_accel_val * delta)
		cR.velocity.z = lerp(cR.velocity.z, cR.move_dir.y * in_air_move_speed_val, in_air_accel_val * delta)
