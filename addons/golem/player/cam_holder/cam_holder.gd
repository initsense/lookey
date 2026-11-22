extends SpringArm3D

var active: bool = true: set = set_active

@onready var cam: Camera3D = %Camera3D
@onready var godot_plush_skin: Node3D = %GodotPlushSkin
@onready var visual_root: Node3D = %VisualRoot
@onready var cR: CharacterBody3D = $".."
@onready var state_machine: Node = $"../StateMachine"

@export_group("Camera mode")
enum Camera {
	FIRST,
	THIRD,
	THIRD_L,
	THIRD_R
}
## Starting view: first person, third person, or an over-the-shoulder aim.
@export var camera_mode: Camera = Camera.FIRST

# HEADBOB
const HEADBOB_SNAP: float = 0.0005
var headbob_index: float = 0.0
var headbob_offset: Vector2 = Vector2.ZERO
# CAMERA LIMITS
var cam_limit_up: float
var cam_limit_down: float
# ZOOM
@onready var last_zoom_val: float = cR.zoom_val
@onready var curr_zoom: float = cR.zoom_val
# FOV
@onready var curr_fov: float = cR.cam_fov
# SHAKE
var cam_shake_offset: Vector3 = Vector3.ZERO
var _strafe_roll: float = 0.0
var _turn_lean: float = 0.0
var _slide_roll: float = 0.0
var _wall_roll: float = 0.0
var view_noise_pitch: float = 0.0
var view_noise_roll: float = 0.0
var _noise_time: float = 0.0
var _view_noise := FastNoiseLite.new()
var stair_offset_y: float = 0.0
var _stair_spring_z: float = 0.0
var _stair_wrote_position: Vector3 = Vector3.ZERO
var _stair_wrote: bool = false
var shake_timer: float = 0.0
var shake_time: float = 0.0
# MODE BLEND
var mode_tween: Tween
var ragdoll_view: bool = false


func _ready() -> void:
	_view_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_view_noise.fractal_octaves = 1
	_view_noise.seed = 1
	cR.connect("pose_changed", Callable(self, "_on_pose_changed"))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.set_use_accumulated_input(false)
	set_active(active)
	
	set_camera_mode(camera_mode, true)


func set_active(state: bool):
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
	
	# switches between camera modes
	if event.is_action_pressed("first_person") and camera_mode != Camera.FIRST:
		set_camera_mode(Camera.FIRST)
	
	if event.is_action_pressed("third_person") and camera_mode != Camera.THIRD:
		set_camera_mode(Camera.THIRD)
	
	if event.is_action_pressed("third_aim_left") and camera_mode != Camera.THIRD_L:
		set_camera_mode(Camera.THIRD_L)
	
	if event.is_action_pressed("third_aim_right") and camera_mode != Camera.THIRD_R:
		set_camera_mode(Camera.THIRD_R)
	
	# rotate cam according to the mouse
	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x * cR.mouse_sens
		rotation.y = wrapf(rotation.y, 0.0, TAU)
		rotation.x -= event.relative.y * cR.mouse_sens
		rotation.x = clamp(rotation.x, cam_limit_up, cam_limit_down)
		add_turn_lean(event.relative.x)


func add_turn_lean(yaw_pixels: float) -> void:
	if not cR.can_turn_lean or camera_mode != Camera.FIRST or ragdoll_view:
		return
	if Vector2(cR.velocity.x, cR.velocity.z).length() <= 0.25:
		return
	_turn_lean = clampf(_turn_lean - yaw_pixels * cR.mouse_sens, -cR.turn_lean_max, cR.turn_lean_max)


func _process(delta: float) -> void:
	if cR.can_change_zoom and camera_mode != Camera.FIRST and not ragdoll_view:
		zoom_handling(delta)
		
	if cR.can_change_fov:
		fov_handling(delta)

	headbob_handling(delta)
	update_camera_shake(delta)
	var catchup: float = cR.stair_camera_catchup
	if catchup > 0.0:
		stair_offset_y = lerpf(stair_offset_y, 0.0, 1.0 - exp(-catchup * delta))
	else:
		stair_offset_y = 0.0
	apply_camera_offsets()
	apply_view_roll(delta)


func set_camera_mode(new_mode: Camera, snap: bool = false) -> void:
	if camera_mode != Camera.FIRST and new_mode == Camera.FIRST:
		last_zoom_val = curr_zoom
	
	camera_mode = new_mode
	if camera_mode != Camera.FIRST:
		reset_headbob()
	
	var holder_position := Vector3.ZERO
	var spring := 0.0
	if camera_mode == Camera.FIRST:
		holder_position = first_person_holder_position()
		cam_limit_down = cR.first_limit_down
		cam_limit_up = cR.first_limit_up
		visual_root.visible = ragdoll_view
	else:
		holder_position = third_person_holder_position()
		spring = curr_zoom
		cam_limit_down = cR.third_limit_down
		cam_limit_up = cR.third_limit_up
		visual_root.visible = true
	
	var pitch := clampf(rotation.x, cam_limit_up, cam_limit_down)
	var duration: float = 0.0 if snap else cR.camera_mode_blend_time
	blend_camera(holder_position, spring, pitch, duration, camera_mode != Camera.FIRST)


func begin_ragdoll_view() -> void:
	ragdoll_view = true
	if camera_mode != Camera.FIRST:
		return
	visual_root.visible = true
	blend_camera(position, cR.zoom_val, rotation.x, cR.camera_mode_blend_time, false)


func end_ragdoll_view() -> void:
	ragdoll_view = false
	set_camera_mode(camera_mode)


func first_person_holder_position() -> Vector3:
	var height: float = cR.first_cam_crouch_height if cR.pose == cR.Pose.CROUCHED else cR.first_cam_height
	return Vector3(0.0, height, 0.0)


func third_person_holder_position() -> Vector3:
	if camera_mode == Camera.THIRD_L:
		return Vector3(-cR.aim_cam_pos.x, cR.aim_cam_pos.y, 0.0)
	if camera_mode == Camera.THIRD_R:
		return Vector3(cR.aim_cam_pos.x, cR.aim_cam_pos.y, 0.0)
	return Vector3(0.0, cR.third_cam_height, 0.0)


func blend_camera(holder_position: Vector3, spring: float, pitch: float, duration: float, clear_roll: bool) -> void:
	if mode_tween != null and mode_tween.is_valid():
		mode_tween.kill()
	mode_tween = null
	
	if duration <= 0.0:
		position = holder_position
		spring_length = spring
		rotation.x = pitch
		if clear_roll:
			cam.rotation.z = 0.0
		return
	
	mode_tween = create_tween()
	mode_tween.set_parallel(true)
	mode_tween.tween_property(self, "position", holder_position, duration)
	mode_tween.tween_property(self, "spring_length", spring, duration)
	mode_tween.tween_property(self, "rotation:x", pitch, duration)
	if clear_roll:
		mode_tween.tween_property(cam, "rotation:z", 0.0, duration)


#region HANDLINGS
func zoom_handling(delta: float) -> void:
	var zoom_input: float = Input.get_axis(cR.cam_zoom_in_action, cR.cam_zoom_out_action)
	
	if zoom_input != 0.0:
		curr_zoom += zoom_input * cR.zoom_speed * delta
		curr_zoom = clamp(curr_zoom, cR.min_zoom_val, cR.max_zoom_val)
	
	if not is_equal_approx(curr_zoom, last_zoom_val):
		last_zoom_val = curr_zoom
		spring_length = curr_zoom


func fov_handling(delta: float) -> void:
	var fov_input := Input.get_axis(cR.cam_fov_decrease, cR.cam_fov_increase)

	if fov_input != 0.0:
		cR.cam_fov += fov_input * cR.fov_speed * delta
		cR.cam_fov = clamp(cR.cam_fov, cR.min_fov, cR.max_fov)
		curr_fov = cR.cam_fov
	else:
		var target_fov: float = cR.cam_fov
		var speed: float = cR.reset_fov_speed

		var horiz := Vector2(cR.velocity.x, cR.velocity.z).length()
		if cR.can_speed_fov:
			var reference := maxf(cR.run_speed, 0.001)
			var ratio := clampf(horiz / reference, 0.0, 1.5)
			target_fov += cR.speed_fov_add * pow(ratio, cR.speed_fov_exponent)
			if horiz >= cR.walk_speed:
				speed = cR.run_fov_increase_speed
			elif horiz > 0.5:
				speed = cR.walk_fov_increase_speed
		else:
			match state_machine.curr_state_name:
				"Walk":
					target_fov += cR.walk_fov_increase
					speed = cR.walk_fov_increase_speed
				"Run":
					target_fov += cR.run_fov_increase
					speed = cR.run_fov_increase_speed

		curr_fov = lerp(curr_fov, target_fov, 1.0 - exp(-speed * delta))

	cam.fov = curr_fov


func headbob_handling(delta: float) -> void:
	# The view eases toward a step while walking or running on the floor with a move key held.
	# Releasing the key, leaving the floor, or leaving those states freezes the step and eases home.
	var bobbing: bool = (
		cR.can_headbob
		and camera_mode == Camera.FIRST
		and (cR.is_on_floor() or cR.stair_floor_hold > 0.0)
		and cR.move_dir != Vector2.ZERO
		and state_machine.curr_state_name in ["Walk", "Run"]
	)
	if bobbing:
		var rate: float = cR.headbob_walk_rate
		var side: float = cR.headbob_walk_side
		var up: float = cR.headbob_walk_up
		if state_machine.curr_state_name == "Run":
			rate = cR.headbob_run_rate
			side = cR.headbob_run_side
			up = cR.headbob_run_up
		elif cR.pose == cR.Pose.CROUCHED:
			rate = cR.headbob_crouch_rate
			side = cR.headbob_crouch_side
			up = cR.headbob_crouch_up
		headbob_index += rate * delta
		var target: Vector2 = headbob_target(headbob_index, side, up)
		headbob_offset = headbob_offset.lerp(target, _headbob_ease(delta))
	elif headbob_offset != Vector2.ZERO:
		headbob_offset = headbob_offset.lerp(Vector2.ZERO, _headbob_ease(delta))
		if headbob_offset.length() < HEADBOB_SNAP:
			headbob_offset = Vector2.ZERO


func headbob_target(index: float, side_distance: float, up_distance: float) -> Vector2:
	var strength: float = cR.headbob_strength
	return Vector2(
		strength * side_distance * (sin(index * cR.headbob_side_rate_ratio) + cR.headbob_side_bias),
		strength * up_distance * sin(index)
	)


func _headbob_ease(delta: float) -> float:
	return 1.0 - pow(0.5, delta * cR.headbob_lerp_speed)


func reset_headbob() -> void:
	headbob_index = 0.0
	headbob_offset = Vector2.ZERO
	cam.position.x = 0.0
	cam.position.y = 0.0


func trigger_camera_shake() -> void:
	if cR.shake_frequency <= 0:
		return
	shake_timer = cR.shake_duration
	shake_time = 0.0


func update_camera_shake(delta: float) -> void:
	if shake_timer <= 0.0 or cR.shake_frequency <= 0:
		cam_shake_offset = Vector3.ZERO
		if shake_timer <= 0.0:
			shake_time = 0.0
		return
	
	shake_timer -= delta
	shake_time += delta
	var amplitude: float = cR.shake_strength * clampf(shake_timer / cR.shake_duration, 0.0, 1.0)
	cam_shake_offset.y = amplitude * sin(shake_time * TAU * cR.shake_frequency)


func note_stair_step(world_delta_y: float) -> void:
	stair_offset_y -= world_delta_y


func apply_view_roll(delta: float) -> void:
	# Strafe, turn lean, slide, wall run, and noise share one roll. One write keeps them all.
	var strafe_target := 0.0
	if cR.can_tilt and camera_mode == Camera.FIRST and not ragdoll_view:
		strafe_target = cR.move_dir_relative.x * cR.tilt_value
	_strafe_roll = lerp(_strafe_roll, strafe_target, clampf(delta * cR.tilt_speed, 0.0, 1.0))
	_turn_lean = lerpf(_turn_lean, 0.0, 1.0 - exp(-cR.turn_lean_return * delta))

	var slide_target: float = cR.slide_roll if state_machine.curr_state_name == "Slide" else 0.0
	_slide_roll = lerpf(_slide_roll, slide_target, 1.0 - exp(-8.0 * delta))
	var wall_target := 0.0
	if state_machine.curr_state_name == "WallRun":
		wall_target = cR.wall_run_roll * cR.wall_run_roll_sign
	_wall_roll = lerpf(_wall_roll, wall_target, 1.0 - exp(-8.0 * delta))
	_update_view_noise(delta)

	if camera_mode != Camera.FIRST or ragdoll_view:
		cam.rotation.x = 0.0
		return
	cam.rotation.z = _strafe_roll + _turn_lean + _slide_roll + _wall_roll + view_noise_roll
	cam.rotation.x = view_noise_pitch


func _update_view_noise(delta: float) -> void:
	if not cR.can_view_noise or camera_mode != Camera.FIRST or ragdoll_view:
		view_noise_pitch = 0.0
		view_noise_roll = 0.0
		return
	_noise_time += delta * cR.view_noise_speed
	var horiz := Vector2(cR.velocity.x, cR.velocity.z).length()
	var scale := clampf(horiz / maxf(cR.run_speed, 0.001), 0.0, 1.0)
	if not cR.is_on_floor():
		scale *= cR.view_noise_air
	var amount: float = cR.view_noise_amount * scale
	view_noise_pitch = _view_noise.get_noise_2d(_noise_time, 0.0) * amount
	view_noise_roll = _view_noise.get_noise_2d(0.0, _noise_time) * amount


func apply_camera_offsets() -> void:
	# Reapplied every frame: the spring arm clears the camera between physics ticks.
	# The holder pitches, so the stair catch-up is world up expressed in local space.
	var local_stair: Vector3 = global_basis.inverse() * Vector3(0.0, stair_offset_y, 0.0)
	var spring_z: float = cam.position.z
	if _stair_wrote and cam.position.is_equal_approx(_stair_wrote_position):
		spring_z = _stair_spring_z
	_stair_spring_z = spring_z
	cam.position = Vector3(
		headbob_offset.x + cam_shake_offset.x + local_stair.x,
		headbob_offset.y + cam_shake_offset.y + local_stair.y,
		spring_z + local_stair.z
	)
	_stair_wrote_position = cam.position
	_stair_wrote = true
#endregion


func _on_pose_changed() -> void:
	if camera_mode != Camera.FIRST or ragdoll_view:
		return
	var duration: float = cR.crouching_speed if cR.pose == cR.Pose.CROUCHED else cR.standing_speed
	blend_camera(first_person_holder_position(), spring_length, rotation.x, duration, false)
