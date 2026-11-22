extends GolemState

class_name GolemRagdollState

var state_name: String = "Ragdoll"

var cR: CharacterBody3D
var _following: bool = false
var _skin_local_transform: Transform3D
var _hips_offset: Vector3 = Vector3.ZERO

func enter(char_ref: CharacterBody3D):
	cR = char_ref
	
	apply_ragdoll()
	
	verifications()
	
func verifications():
	cR.floor_snap_length = 1.0
	if cR.jump_cooldown > 0.0: cR.jump_cooldown = -1.0
	if cR.nb_jumps_in_air_allowed < cR.nb_jumps_in_air_allowed_ref: cR.nb_jumps_in_air_allowed = cR.nb_jumps_in_air_allowed_ref
	if cR.coyote_jump_cooldown < cR.coyote_jump_cooldown_ref: cR.coyote_jump_cooldown = cR.coyote_jump_cooldown_ref
	if cR.movement_dust.emitting: cR.movement_dust.emitting = false
	
func apply_ragdoll():
	var skin: Node3D = cR.godot_plush_skin
	_skin_local_transform = skin.transform
	_hips_offset = cR.global_transform.affine_inverse() * skin.hips_bone.global_position
	skin.top_level = true
	cR.collision_capsule.disabled = true
	cR.velocity = Vector3.ZERO
	skin.ragdoll = true
	_following = true
	cR.cam_holder.begin_ragdoll_view()

func exit():
	_following = false
	var skin: Node3D = cR.godot_plush_skin
	skin.top_level = false
	skin.transform = _skin_local_transform
	cR.collision_capsule.disabled = false
	cR.velocity = Vector3.ZERO
	cR.cam_holder.end_ragdoll_view()
	
func update(_delta: float):
	check_if_ragdoll()
	
func physics_update(_delta: float):
	# Zeroed after move_and_slide has already run this frame, so the next slide cannot launch the camera.
	cR.velocity = Vector3.ZERO
	follow_hips()
	input_management()
	
func check_if_ragdoll():
	if not cR.godot_plush_skin.ragdoll:
		transitioned.emit(self, "IdleState")

func follow_hips() -> void:
	if not _following:
		return
	var hips: Node3D = cR.godot_plush_skin.hips_bone
	cR.global_position = hips.global_position - cR.global_basis * _hips_offset
	
func input_management():
	if Input.is_action_just_pressed("ragdoll"):
		# The standing capsule is disabled, so is_on_floor() cannot see the ground.
		if cR.can_ragdoll_on_floor_only and _hips_near_floor():
			cR.godot_plush_skin.ragdoll = false
		elif not cR.can_ragdoll_on_floor_only:
			cR.godot_plush_skin.ragdoll = false


func _hips_near_floor() -> bool:
	var space := cR.get_world_3d().direct_space_state
	if space == null:
		return false
	var from: Vector3 = cR.godot_plush_skin.hips_bone.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.5, 2)
	return not space.intersect_ray(query).is_empty()
