extends State

class_name WalkState

var state_name : String = "Walk"

var cR : CharacterBody3D
@onready var head : SpringArm3D = %Head


func enter(char_ref : CharacterBody3D):
	cR = char_ref

	verifications()


func verifications():
	cR.move_speed = cR.walk_speed
	
	cR.move_accel = cR.walk_accel
	cR.move_deccel = cR.walk_deccel
	
	cR.floor_snap_length = 1.0


func update(_delta : float):
	pass


func physics_update(delta : float):
	check_if_floor()
	cR.apply_gravity(delta)
	move(delta)


func check_if_floor():
	if !cR.is_on_floor() and !cR.is_on_wall():
		if cR.velocity.y < 0.0:
			transitioned.emit(self, "InairState")


func move(delta : float):
	cR.move_dir_relative = Input.get_vector(cR.moveLeftAction, cR.moveRightAction, cR.moveForwardAction, cR.moveBackwardAction)
	cR.move_dir = cR.move_dir_relative.rotated(-cR.head.global_rotation.y)
	
	if cR.move_dir and cR.is_on_floor():
		#apply smooth move
		cR.velocity.x = lerp(cR.velocity.x, cR.move_dir.x * cR.move_speed, cR.move_accel * delta)
		cR.velocity.z = lerp(cR.velocity.z, cR.move_dir.y * cR.move_speed, cR.move_accel * delta)
	else:
		transitioned.emit(self, "IdleState")
