extends SpringArm3D

var active : bool = true : set = set_active

@onready var cam : Camera3D = %Camera3D
@onready var visual_root : Node3D = %VisualRoot
@onready var cR: CharacterBody3D = $".."
@onready var state_machine: Node = $"../StateMachine"

# HEADBOB



# CAMERA LIMITS
var cam_limit_up : float
var cam_limit_down : float
# FOV
@onready var curr_fov: float = cR.cam_fov


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.set_use_accumulated_input(false)
	set_active(active)

	cam_limit_down = cR.first_limit_down
	cam_limit_up = cR.first_limit_up
	spring_length = 0.0


func set_active(state : bool):
	# enable/disable play char camera
	active = state
	set_process_input(active)
	set_process(active)


func _input(event) -> void:
	#free/capture mouse cursor
	if event.is_action_pressed(cR.mouse_mode_action):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	#if mouse cursor is free, can't rotate cam
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	
	# rotate cam according to the mouse
	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x * cR.mouse_sens
		rotation.y = wrapf(rotation.y, 0.0, TAU)
		rotation.x -= event.relative.y * cR.mouse_sens
		rotation.x = clamp(rotation.x, cam_limit_up, cam_limit_down)


func _process(delta: float) -> void:
	
	if cR.can_change_fov:
		fov_handling(delta)

	if cR.can_headbob and state_machine.curr_state_name in ["Walk"]:
		pass

	if cR.can_tilt:
		cam.rotation.z = lerp(cam.rotation.z, cR.move_dir_relative.x * cR.tilt_value, delta * cR.tilt_speed)


func fov_handling(delta: float) -> void:
	var fov_input := Input.get_axis(cR.cam_fov_decrease, cR.cam_fov_increase)

	if fov_input != 0.0:
		cR.cam_fov += fov_input * cR.fov_speed * delta
		cR.cam_fov = clamp(cR.cam_fov, cR.min_fov, cR.max_fov)
		curr_fov = cR.cam_fov
	else:
		var target_fov: float = cR.cam_fov
		var speed: float = cR.reset_fov_speed

		match state_machine.curr_state_name:
			"Walk":
				target_fov += cR.walk_fov_increase
				speed = cR.walk_fov_increase_speed

		curr_fov = lerp(curr_fov, target_fov, 1.0 - exp(-speed * delta))

	cam.fov = curr_fov
