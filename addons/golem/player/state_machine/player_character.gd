extends CharacterBody3D

const Defaults := preload("res://addons/golem/input_defaults.gd")
const StairStep := preload("res://addons/golem/player/state_machine/stair_step.gd")
const WallClimb := preload("res://addons/golem/player/state_machine/wall_climb.gd")
const LedgeClimb := preload("res://addons/golem/player/state_machine/ledge_climb.gd")
const Vault := preload("res://addons/golem/player/state_machine/vault.gd")


@export_category("Camera")

@export_group("Position")
## Eye height of the first-person camera, in meters.
@export var first_cam_height : float = 1.5
## Eye height of the third-person camera, in meters.
@export var third_cam_height : float = 1.5
## Aim-camera offset from the player: x is sideways meters, y is height in meters.
@export var aim_cam_pos : Vector2 = Vector2(1.6, 0.8)
## Seconds to blend holder position, distance, and pitch when the camera mode changes.
@export_range(0.0, 2.0, 0.01, "suffix:s") var camera_mode_blend_time : float = 0.25

@export_group("Crouch")
enum Pose {
	STANDING,
	CROUCHED
	}
## First-person eye height while crouched, in meters.
@export var first_cam_crouch_height: float = 0.4
## Seconds to blend the camera up to standing height.
@export_range(0.05, 2.0, 0.01, "suffix:s") var standing_speed: float = 0.2
## Seconds to blend the camera down to crouch height.
@export_range(0.05, 2.0, 0.01, "suffix:s") var crouching_speed: float = 0.2

@onready var pose: Pose = Pose.STANDING
## Movement speed while crouched, in meters per second.
@export var crouch_speed: float = 1.6
const CROUCH_TRANSLATE: float = 0.7
const CROUCH_JUMP_ADD: float = CROUCH_TRANSLATE * 0.9
@onready var original_capsule_height = %CollisionCapsule.shape.height

@export_group("Head bob")
## Enables the first-person head bob while walking or running.
@export var can_headbob: bool = true
## Scales every head-bob distance. 1 is full size. 0 keeps the view still.
@export var headbob_strength: float = 1.0
@export_subgroup("Walk")
## Walk step speed, in radians per second.
@export var headbob_walk_rate: float = 14.0
## Walk sideways distance, in meters.
@export var headbob_walk_side: float = 0.1
## Walk up-and-down distance, in meters.
@export var headbob_walk_up: float = 0.05
@export_subgroup("Run")
## Run step speed, in radians per second.
@export var headbob_run_rate: float = 22.0
## Run sideways distance, in meters.
@export var headbob_run_side: float = 0.2
## Run up-and-down distance, in meters.
@export var headbob_run_up: float = 0.1
@export_subgroup("Crouch")
## Crouch step speed, in radians per second.
@export var headbob_crouch_rate: float = 10.0
## Crouch sideways distance, in meters.
@export var headbob_crouch_side: float = 0.05
## Crouch up-and-down distance, in meters.
@export var headbob_crouch_up: float = 0.025
@export_subgroup("Shape")
## Sideways cycles for each up-and-down cycle. 0.5 is one sway every two steps.
@export var headbob_side_rate_ratio: float = 0.5
## Added to the sideways wave before scaling. 0 crosses the middle.
@export var headbob_side_bias: float = 0.0
## How quickly the view chases the step. Higher values catch up sooner.
@export var headbob_lerp_speed: float = 10.0

@export_group("Side tilt")
## Enables first-person camera roll while strafing.
@export var can_tilt: bool = true
## Maximum camera roll, in radians, at full strafe input.
@export_range(0.0, 0.1, 0.005) var tilt_value: float = 0.02
## How quickly the roll follows the strafe input.
@export_range(0.0, 20.0, 0.1) var tilt_speed: float = 4.0
## Adds roll while the mouse turns and the body is moving in first person.
@export var can_turn_lean: bool = true
## Largest turn roll, in radians.
@export_range(0.0, 15.0, 0.1, "radians_as_degrees") var turn_lean_max: float = 0.087266
## How quickly that roll returns to level.
@export_range(0.0, 20.0, 0.1) var turn_lean_return: float = 6.0

@export_group("Camera movement")
## Mouse look multiplier. Higher values turn the camera faster.
@export_range(0.0, 0.005, 0.0005) var mouse_sens : float = 0.002
## Not applied. Reserved look-speed value with no current effect.
@export_range(0.0, 20.0, 0.01) var pan_rotation_val : float = 2.0
@export_subgroup("First person limits")
## Lowest first-person look angle. Negative looks up.
@export_range(-90.0, 90.0, 0.1, "radians_as_degrees") var first_limit_up : float = -1.4
## Highest first-person look angle. Positive looks down.
@export_range(-90.0, 90.0, 0.1, "radians_as_degrees") var first_limit_down : float = 1.4
@export_subgroup("Third person limits")
## Lowest third-person look angle. Negative looks up.
@export_range(-90.0, 90.0, 0.1, "radians_as_degrees") var third_limit_up : float = -1.4
## Highest third-person look angle. Positive looks down.
@export_range(-90.0, 90.0, 0.1, "radians_as_degrees") var third_limit_down : float = 0.8

@export_group("FOV")
## Enables manual FOV keys and the walk/run FOV widen.
@export var can_change_fov: bool = true
## Resting camera field of view, in degrees.
@export var cam_fov: float = 90.0
## Degrees per second while an FOV key is held.
@export var fov_speed: float = 32.0
## Lowest field of view the keys can reach, in degrees.
@export var min_fov: float = 30.0
## Highest field of view the keys can reach, in degrees.
@export var max_fov: float = 150.0
## Extra degrees added to the field of view while walking.
@export var walk_fov_increase: float = 4.0
## Extra degrees added to the field of view while running.
@export var run_fov_increase: float = 10.0
## How quickly the field of view widens while walking.
@export var walk_fov_increase_speed: float = 2.0
## How quickly the field of view widens while running.
@export var run_fov_increase_speed: float = 2.0
## How quickly the field of view returns to rest.
@export var reset_fov_speed: float = 2.0
## Field of view follows horizontal speed. Off restores the walk and run bonuses.
@export var can_speed_fov: bool = true
## Extra degrees at run speed. A slower speed widens less.
@export var speed_fov_add: float = 10.0
## Higher values keep a slow walk closer to the resting field of view.
@export var speed_fov_exponent: float = 2.0

@export_group("Shake")
## Shakes the camera once when landing from a fall.
@export var can_landing_shake: bool = true
## Landing-shake distance, in meters.
@export var shake_strength : float = 0.06
## Landing-shake length, in seconds. Amplitude fades across this time.
@export var shake_duration : float = 0.1
## Landing-shake cycles per second. Zero disables the oscillation.
@export var shake_frequency: int = 3

@export_group("View noise")
## Adds a small speed-scaled pitch and roll. The landing shake stays separate.
@export var can_view_noise: bool = true
## Pitch and roll at run speed, in radians. Larger in the air.
@export var view_noise_amount: float = 0.006
## How fast the noise pattern moves.
@export var view_noise_speed: float = 1.4
## Multiplier while off the floor.
@export var view_noise_air: float = 2.0

@export_group("Zoom")
## Enables the third-person zoom keys.
@export var can_change_zoom: bool = true
## Starting third-person camera distance, in meters.
@export var zoom_val : float = 3.0
## Meters per second while a zoom key is held.
@export var zoom_speed : float = 4.0
## Farthest third-person camera distance, in meters.
@export var max_zoom_val : float = 10.0
## Nearest third-person camera distance, in meters.
@export var min_zoom_val : float = 2.0


@export_category("Movement")

#movement variables
var move_speed : float
var move_accel : float
var move_deccel : float
var move_dir_relative: Vector2
var move_dir : Vector2
var target_angle : float
var last_input_dir : Vector2
var last_frame_position : Vector3
var last_frame_velocity : Vector3
var was_on_floor : bool = false
var stair_floor_hold: float = 0.0
var walk_or_run : String = "WalkState" #keep in memory if play char was walking or running before being in the air
## A jump that started crouched stands at takeoff. Landing stands again if crouch was pressed in the air.
var uncrouch_on_land: bool = false

@export_group("Walk")
## Ground walk speed, in meters per second.
@export var walk_speed : float = 5.0
## How quickly walking reaches walk speed.
@export var walk_accel : float = 8.0
## How quickly walking slows to a stop.
@export var walk_deccel : float = 7.5

@export_group("Run")
## Ground run speed, in meters per second. A directed jump in the run gait aims for this speed.
@export var run_speed : float = 10.0
## How quickly running reaches run speed.
@export var run_accel : float = 3.5
## How quickly running slows to a stop.
@export var run_deccel : float = 6.5
## When enabled, one press toggles running. Otherwise the run key must be held.
@export var can_continuous_run : bool = false

@export_group("Slide")
## Crouch during a fast run slides. Off keeps that crouch canceling the run.
@export var can_slide: bool = true
## Slowest horizontal speed, in meters per second, that a run crouch will slide.
@export var slide_min_speed: float = 6.0
## Starting slide speed, in meters per second, when the current speed is lower.
@export var slide_speed: float = 10.0
## Seconds the slide lasts on flat ground.
@export var slide_time: float = 1.0
## Seconds of uphill travel that end the slide.
@export var slide_uphill_time: float = 0.3
## Floors steeper than this, in degrees, count as a slope. Downhill holds the timer.
@export var slide_slope_degrees: float = 8.0
## How quickly speed left above run speed fades after the slide, in meters per second squared.
@export var slide_momentum_decay: float = 5.0
## Camera roll during the slide, in radians.
@export_range(0.0, 20.0, 0.1, "radians_as_degrees") var slide_roll: float = 0.122173
var slide_dir: Vector3 = Vector3.FORWARD
var slide_start_speed: float = 0.0
var slide_time_left: float = 0.0
var slide_uphill_held: float = 0.0
var slide_momentum: float = 0.0

@export_group("Jump")
@onready var jump_gravity : float = ((-2.0 * jump_height) / (jump_time_to_peak * jump_time_to_peak)) * -1.0
## Jump apex height, in meters.
@export var jump_height : float = 5.0
## Seconds to rise from the ground to the jump apex.
@export var jump_time_to_peak : float = 0.7
## Seconds to fall from the jump apex back to the ground.
@export var jump_time_to_descent : float = 0.4
@onready var jump_velocity : float = ((2.0 * jump_height) / jump_time_to_peak) * -1.0
## Seconds after a jump before another jump is allowed.
@export var jump_cooldown : float = 0.2
var jump_cooldown_ref : float
## Extra jumps allowed before landing. Zero means ground jumps only.
@export var nb_jumps_in_air_allowed : int = 0
var nb_jumps_in_air_allowed_ref : int
var jump_buff_on : bool = false
var buffered_jump : bool = false
## Seconds after walking off a ledge during which a jump is still allowed.
@export var coyote_jump_cooldown : float = 0.2
var coyote_jump_cooldown_ref : float = 0.2
var coyote_jump_on : bool = false
## Keeps jumping if you keep the key pressed.
@export var can_auto_jump : bool = false
 
@export_group("In air")
@onready var fall_gravity : float = ((-2.0 * jump_height) / (jump_time_to_descent * jump_time_to_descent)) * -1.0
## Zeroes horizontal speed on a wall hit while in the air.
@export var can_hit_wall_cut_velocity : bool = false

@export_group("Stairs")
## Steps up and down low ledges instead of stopping on the riser.
@export var can_climb_stairs: bool = true
## Tallest ledge, in meters, that still counts as a step.
@export var step_height: float = 0.5
## Steepest floor angle, in degrees, that a step can land on.
@export_range(0.0, 89.0, 1.0) var step_max_slope_degrees: float = 40.0
## How quickly the camera catches the body after a stair snap.
@export_range(0.0, 30.0, 0.1) var stair_camera_catchup: float = 8.0

@export_group("Ledges")
## Hops onto a ledge when a jump reaches it. Walking into the face does not.
@export var can_climb_ledges: bool = true
## Highest lip above the feet, in meters, that a jump can still hop onto.
@export var ledge_max_height: float = 1.5
var ledge_pulling: bool = false
var ledge_block_wall_cut: bool = false
var ledge_jump_launched: bool = false
var ledge_elapsed: float = 0.0
var ledge_start: Vector3 = Vector3.ZERO
var ledge_target: Vector3 = Vector3.ZERO
var ledge_face_normal: Vector3 = Vector3.FORWARD

@export_group("Walls")
## A jump into a wall climbs briefly, then the lift fades.
@export var can_climb_walls: bool = true
## Extra rise, in meters, if you stay on the face for the whole climb.
@export var wall_climb_height: float = 1.2
## Seconds before the wall lift is gone.
@export var wall_climb_time: float = 0.4
var wall_climbing: bool = false
var wall_climb_armed: bool = false
var wall_climb_spent: bool = false
var wall_climb_elapsed: float = 0.0

@export_group("Wall run")
## Run along a side wall and jump off it. A jump straight into a wall still climbs.
@export var can_wall_run: bool = true
## Speed along the wall, in meters per second.
@export var wall_run_speed: float = 15.0
## Longest wall run, in seconds.
@export var wall_run_time: float = 3.0
## Push off the wall and upward, in meters per second.
@export var wall_jump_speed: float = 4.5
## How far a side check looks for a wall, in meters.
@export var wall_run_reach: float = 1.15
## Nearest angle, in degrees off your facing, that still counts as a side wall.
@export var wall_run_min_angle: float = 25.0
## Farthest angle, in degrees off your facing, that still counts as a side wall.
@export var wall_run_max_angle: float = 105.0
## Fall gravity multiplier at the start of the wall run. It returns to 1 as the timer ends.
@export var wall_run_gravity_scale: float = 0.25
## Camera roll toward the wall, in radians.
@export_range(0.0, 20.0, 0.1, "radians_as_degrees") var wall_run_roll: float = 0.10472
var wall_run_normal: Vector3 = Vector3.RIGHT
var wall_run_dir: Vector3 = Vector3.FORWARD
var wall_run_roll_sign: float = 1.0
var wall_run_elapsed: float = 0.0
var wall_run_lockout: float = 0.0

@export_group("Vault")
## Run or slide over a block taller than a step. Off means that run stops at the block.
@export var can_vault: bool = true
## Tallest block, in meters, a run can vault.
@export var vault_max_height: float = 1.2
## Slowest horizontal speed, in meters per second, that still vaults.
@export var vault_min_speed: float = 6.0
## Upward speed, in meters per second, when the far side is not a floor.
@export var vault_pop: float = 2.0
var vaulting: bool = false
var vault_elapsed: float = 0.0
var vault_duration: float = 0.3
var vault_from: Vector3 = Vector3.ZERO
var vault_control: Vector3 = Vector3.ZERO
var vault_to: Vector3 = Vector3.ZERO
var vault_pop_on_end: bool = false


@export_category("Model")

@export_group("Rotation")
## How quickly the model turns toward its facing direction, in radians per second.
@export var model_rot_speed : float
## When enabled, the model faces the camera while aiming left or right.
@export var can_follow_cam_pos_when_aimed : bool = false

@export_group("Ragdoll")
## Not applied. The body follows the ragdoll hips instead of this gravity.
@export var ragdoll_gravity : float
## When enabled, ragdoll can only start and stop while standing on the floor.
@export var can_ragdoll_on_floor_only : bool = false


#region KEYBINDINGS
@export_category("Keybinding")

@export_group("Movement")
## Input action name for moving forward.
@export var moveForwardAction : String = ""
## Input action name for moving backward.
@export var moveBackwardAction : String = ""
## Input action name for moving left.
@export var moveLeftAction : String = ""
## Input action name for moving right.
@export var moveRightAction : String = ""
## Input action name for running.
@export var runAction : String = ""
## Input action name for jumping.
@export var jumpAction : String = ""

@export_group("Camera")
## Input action name that toggles captured mouse look.
@export var mouse_mode_action : String = "toggle_mouse_mode"
## Input action name that moves the third-person camera closer.
@export var cam_zoom_in_action : String = "zoom_in"
## Input action name that moves the third-person camera farther.
@export var cam_zoom_out_action : String = "zoom_out"
## Input action name that narrows the field of view.
@export var cam_fov_decrease : String = "fov_decrease"
## Input action name that widens the field of view.
@export var cam_fov_increase : String = "fov_increase"
#endregion


#region REFERENCE VARIABLES
@onready var visual_root = %VisualRoot
@onready var godot_plush_skin = %GodotPlushSkin
@onready var particles_manager = %ParticlesManager
@onready var cam_holder = %CamHolder
@onready var state_machine = $StateMachine
@onready var debug_hud = %DebugHUD
@onready var foot_step_audio = %FootStepAudio
@onready var impact_audio = %ImpactAudio
@onready var wave_audio = %WaveAudio
@onready var collision_capsule = %CollisionCapsule
@onready var floor_check : RayCast3D = %FloorRaycast

# particles variables
@onready var movement_dust = %MovementDust
@onready var jump_particles = preload("res://addons/golem/player/vfx/jump_particles.tscn")
@onready var land_particles = preload("res://addons/golem/player/vfx/land_particles.tscn")
#endregion


signal pose_changed


func _ready():
	_add_missing_input_actions()
	#set move variables, and value references
	move_speed = walk_speed
	move_accel = walk_accel
	move_deccel = walk_deccel
	
	jump_cooldown_ref = jump_cooldown
	nb_jumps_in_air_allowed_ref = nb_jumps_in_air_allowed
	coyote_jump_cooldown_ref = coyote_jump_cooldown
	
	#set char model audios effects
	godot_plush_skin.footstep.connect(func(intensity : float = 1.0):
		foot_step_audio.volume_db = linear_to_db(intensity)
		foot_step_audio.play()
		)


func _add_missing_input_actions() -> void:
	var existing := PackedStringArray()
	for action: StringName in InputMap.get_actions():
		existing.append(String(action))
	for action: String in Defaults.missing_actions(existing):
		var event := InputEventKey.new()
		event.physical_keycode = Defaults.ACTIONS[action]
		InputMap.add_action(action, 0.2)
		InputMap.action_add_event(action, event)


func _process(delta: float):
	modify_model_orientation(delta)
	display_properties()


func _physics_process(delta: float) -> void:
	modify_physics_properties()
	if wall_run_lockout > 0.0:
		wall_run_lockout = maxf(0.0, wall_run_lockout - delta)
	if not can_slide:
		slide_momentum = 0.0
	elif state_machine.curr_state_name != "Slide":
		slide_momentum = move_toward(slide_momentum, 0.0, slide_momentum_decay * delta)
	Vault.apply(self, delta)
	if not vaulting:
		StairStep.apply(self, delta)
		WallClimb.apply(self, delta)
		LedgeClimb.apply(self, delta)
	move_and_slide()


func display_properties():
	#display play char properties
	debug_hud.display_curr_state(state_machine.curr_state_name)
	debug_hud.display_velocity(velocity.length())
	debug_hud.display_nb_jumps_in_air_allowed(nb_jumps_in_air_allowed)
	debug_hud.display_jump_buffer(jump_buff_on)
	debug_hud.display_coyote_time(coyote_jump_cooldown)


func modify_model_orientation(delta : float):
	#manage the model rotation depending on the camera mode + char parameters
	
	var dir_target_angle : float

	# First person always faces the camera, including while moving backward.
	# The extra half turn matches aiming: the camera yaw alone is the backward-step facing.
	if cam_holder.camera_mode == cam_holder.Camera.FIRST and not godot_plush_skin.ragdoll:
		visual_root.rotation.y = cam_holder.cam.global_rotation.y + PI
		return
	
	#follow mode (model must follow the camera rotation)
	#if the cam is in angled/aim mode
	if ( cam_holder.camera_mode in [cam_holder.Camera.THIRD_L, cam_holder.Camera.THIRD_R]
	and can_follow_cam_pos_when_aimed and not godot_plush_skin.ragdoll ):
		#get cam rotation on the y axis (+ PI to invert half circle, and be sure that the model is correctly oriented)
		dir_target_angle = (cam_holder.cam.global_rotation.y) + PI
		#rotate the model on the y axis
		visual_root.rotation.y = rotate_toward(visual_root.rotation.y, dir_target_angle, model_rot_speed * delta)
	
	#free mode (the model orientation is independant to the camera one)
	if (cam_holder.camera_mode in [cam_holder.Camera.THIRD, cam_holder.Camera.FIRST] or not can_follow_cam_pos_when_aimed) and move_dir != Vector2.ZERO:
		#get char move direction
		dir_target_angle = -move_dir.orthogonal().angle()
		#rotate the model on the y axis
		visual_root.rotation.y = rotate_toward(visual_root.rotation.y, dir_target_angle, model_rot_speed * delta)


func modify_physics_properties():
	last_frame_position = position #get play char position every frame
	last_frame_velocity = velocity #get play char velocity every frame
	was_on_floor = not is_on_floor() #get if play char is on floor or not


func apply_air_move(delta: float) -> void:
	if not move_dir or is_on_floor():
		return
	var target_speed := walk_speed
	var accel := walk_accel
	if walk_or_run == "RunState":
		target_speed = run_speed
		accel = run_accel
	var target := Vector3(move_dir.x, 0.0, move_dir.y) * target_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var steered := horizontal.lerp(target, clampf(accel * delta, 0.0, 1.0))
	velocity.x = steered.x
	velocity.z = steered.z


func apply_gravity(delta : float):
	if velocity.y >= 0.0:
		velocity.y -= jump_gravity * delta
	else:
		velocity.y -= fall_gravity * delta


func squash_and_strech(value : float, timing : float):
	#create a tween that simulate a compression of the model (squash and strech ones)
	#maily used to accentuate game feel/juice
	#call the squash_and_strech function of the model (it's this function that actually squash and strech the model)
	var sasTween : Tween = create_tween()
	sasTween.set_ease(Tween.EASE_OUT)
	sasTween.tween_property(godot_plush_skin, "squash_and_stretch", value, timing)
	sasTween.tween_property(godot_plush_skin, "squash_and_stretch", 1.0, timing * 1.8)


func toggle_crouch(state_speed: float) -> void:
	if pose == Pose.STANDING:
		pose = Pose.CROUCHED
		move_speed = crouch_speed
		walk_or_run = "WalkState"
		print("crouched")
	elif pose == Pose.CROUCHED:
		pose = Pose.STANDING
		move_speed = state_speed
		print("standing")
	emit_signal("pose_changed")


func begin_slide() -> void:
	if pose != Pose.CROUCHED:
		pose = Pose.CROUCHED
		pose_changed.emit()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if speed > 0.1:
		slide_dir = horizontal / speed
	else:
		var wish := Vector3(move_dir.x, 0.0, move_dir.y)
		slide_dir = wish.normalized() if wish.length_squared() > 0.0001 else Vector3.FORWARD
	slide_start_speed = maxf(speed, slide_speed)
	velocity.x = slide_dir.x * slide_start_speed
	velocity.z = slide_dir.z * slide_start_speed
	slide_time_left = slide_time
	slide_uphill_held = 0.0


func store_slide_momentum() -> void:
	if not can_slide:
		slide_momentum = 0.0
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	slide_momentum = maxf(0.0, speed - run_speed)


func try_wall_run() -> bool:
	if not can_wall_run or vaulting or wall_climbing or ledge_pulling or wall_run_lockout > 0.0:
		return false
	if is_on_floor() or state_machine.curr_state_name == "WallRun":
		return false
	var forward := flat_camera_forward()
	if forward == Vector3.ZERO:
		return false
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < 2.0:
		return false
	if horizontal.normalized().dot(forward) < 0.35:
		return false
	var right := flat_camera_right()
	if right == Vector3.ZERO:
		return false
	var origin := global_position + Vector3.UP
	for side in [right, -right]:
		var hit := cast_ray(origin, origin + side * wall_run_reach)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.normal
		if absf(normal.y) > 0.3:
			continue
		var flat_n := Vector3(normal.x, 0.0, normal.z).normalized()
		var angle := rad_to_deg(forward.angle_to(-flat_n))
		if angle < wall_run_min_angle or angle > wall_run_max_angle:
			continue
		var along := horizontal - flat_n * horizontal.dot(flat_n)
		if along.length_squared() < 0.04:
			along = forward - flat_n * forward.dot(flat_n)
		if along.length_squared() < 0.0001:
			continue
		wall_run_normal = flat_n
		wall_run_dir = along.normalized()
		wall_run_roll_sign = -signf(flat_n.dot(right))
		return true
	return false


func refresh_wall_run() -> bool:
	var origin := global_position + Vector3.UP
	var hit := cast_ray(origin, origin - wall_run_normal * wall_run_reach)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit.normal
	if absf(normal.y) > 0.35:
		return false
	var flat_n := Vector3(normal.x, 0.0, normal.z).normalized()
	wall_run_normal = flat_n
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var along := horizontal - flat_n * horizontal.dot(flat_n)
	if along.length_squared() > 0.04:
		wall_run_dir = along.normalized()
	return true


func cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	var world := get_world_3d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, 2, [get_rid()])
	return world.direct_space_state.intersect_ray(query)


func flat_camera_forward() -> Vector3:
	var forward: Vector3 = -cam_holder.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.ZERO
	return forward.normalized()


func flat_camera_right() -> Vector3:
	var right: Vector3 = cam_holder.global_basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return Vector3.ZERO
	return right.normalized()


func release_crouch_on_land() -> void:
	if not uncrouch_on_land:
		return
	uncrouch_on_land = false
	if pose != Pose.CROUCHED:
		return
	pose = Pose.STANDING
	emit_signal("pose_changed")
