extends CharacterBody3D


@export_category("Camera")

@export_group("Head bob")
@export var can_headbob: bool = true
@export var headbob_amplitude : float = 0.03
@export var headbob_frequency : float = 2.3
@export var headbob_blend_time: float= 0.5

@export_group("Side tilt")
@export var can_tilt: bool = true
@export_range(0.0, 0.1, 0.005) var tilt_value: float = 0.02
@export_range(0.0, 20.0, 0.1) var tilt_speed: float = 2.0

@export_group("Camera movement")
@export_range(0.0, 0.005, 0.0005) var mouse_sens : float = 0.002
@export_range(0.0, 20.0, 0.01) var pan_rotation_val : float = 2.0
@export_subgroup("First person limits")
@export_range(-90.0, 90.0, 0.1, "radians_as_degrees") var first_limit_up : float = -1.4
@export_range(-90.0, 90.0, 0.1, "radians_as_degrees") var first_limit_down : float = 1.4

@export_group("FOV")
@export var can_change_fov: bool = true
@export var cam_fov: float = 70.0
@export var fov_speed: float = 32.0
@export var min_fov: float = 30.0
@export var max_fov: float = 150.0
@export var walk_fov_increase: float = 4.0
@export var walk_fov_increase_speed: float = 2.0
@export var reset_fov_speed: float = 2.0


@export_category("Movement")

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
var walk_or_run : String = "WalkState" #keep in memory if play char was walking or running before being in the air

@export_group("Walk")
@export var walk_speed : float = 3.0
@export var walk_accel : float = 8.0
@export var walk_deccel : float = 7.5
 
@export_group("In air")
@export var in_air_move_speed : Array[Curve]
@export var in_air_accel : Array[Curve]
@export var hit_wall_cut_velocity : bool = false
@export var fall_gravity: float = 10.0
@export var max_fall_speed: float = 15.0


#region KEYBINDINGS
@export_category("Keybinding")

@export_group("Movement")
@export var moveForwardAction : String = ""
@export var moveBackwardAction : String = ""
@export var moveLeftAction : String = ""
@export var moveRightAction : String = ""
@export var jumpAction : String = ""

@export_group("Camera")
@export var mouse_mode_action : String = "toggle_mouse_mode"
@export var cam_fov_decrease : String = "fov_decrease"
@export var cam_fov_increase : String = "fov_increase"
#endregion


#region REFERENCE VARIABLES
@onready var visual_root = %VisualRoot
@onready var head = %Head
@onready var state_machine = $StateMachine
@onready var collision_capsule = %CollisionCapsule
@onready var floor_check : RayCast3D = %FloorRaycast
#endregion


func _ready():
	#set move variables, and value references
	move_speed = walk_speed
	move_accel = walk_accel
	move_deccel = walk_deccel


func _physics_process(_delta : float):
	modify_physics_properties()
	move_and_slide()
	#print(move_speed)


func modify_physics_properties():
	last_frame_position = position #get play char position every frame
	last_frame_velocity = velocity #get play char velocity every frame
	was_on_floor = not is_on_floor() #get if play char is on floor or not


func apply_gravity(delta : float):
	velocity.y -= fall_gravity * delta
	velocity.y = max(velocity.y, -max_fall_speed)
