extends State

class_name IdleState

var state_name : String = "Idle"

var cR : CharacterBody3D
@onready var head : SpringArm3D = %Head


func enter(char_ref : CharacterBody3D):
	#pass play char reference
	cR = char_ref


func update(_delta : float):
	pass


func physics_update(delta : float):
	check_if_floor()
	#cR.apply_gravity(delta)
	move(delta)


func check_if_floor():
	#manage the appliements and state transitions that needs to be sets/checked/performed
	#every time the play char pass through one of the following : floor-inair-onwall
	if not cR.is_on_floor() and not cR.is_on_wall():
		transitioned.emit(self, "InairState")


func move(delta : float):
	#manage the character movement
	
	#get the move direction depending on the input
	cR.move_dir_relative = Input.get_vector(cR.moveLeftAction, cR.moveRightAction, cR.moveForwardAction, cR.moveBackwardAction)
	cR.move_dir = cR.move_dir_relative.rotated(-cR.head.global_rotation.y)
	
	if cR.move_dir and cR.is_on_floor():
		#transition to corresponding state
		transitioned.emit(self, cR.walk_or_run)
	else:
		#apply smooth stop 
		cR.velocity.x = lerp(cR.velocity.x, 0.0, cR.move_deccel * delta)
		cR.velocity.z = lerp(cR.velocity.z, 0.0, cR.move_deccel * delta)
