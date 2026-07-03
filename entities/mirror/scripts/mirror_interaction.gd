class_name MirrorInteraction
extends Node
## Gameplay logic for REVEAL and DISSOLVE mirrors: tracks whether the player
## is facing the mirror, checks line-of-sight occlusion with a raycast and
## toggles the pigment layers on the player, the raycast and the camera.
## Sits as a child of Mirror3D and reacts to the VisibleDetector signals.

var _facing_mirror: bool = false
var _are_layers_enabled: bool = true

@onready var _mirror: Mirror3D = get_parent()
@onready var _ray_cast: RayCast3D = _mirror.get_node("RayCast")


func _physics_process(_delta: float) -> void:
	if not _mirror.player or _mirror.mirror_type == Mirror3D.MirrorType.VANILLA:
		return

	if _mirror.global_position.distance_to(_mirror.player.global_position) >= _mirror.cull_far:
		return

	# ponytail: stringly-typed state check, replace with a player API if states grow
	if _mirror.player.walk_or_run != "WalkState":
		return

	match _mirror.mirror_type:
		Mirror3D.MirrorType.DISSOLVE:
			_update_dissolve_logic()
		Mirror3D.MirrorType.REVEAL:
			_update_reveal_logic()


func _update_dissolve_logic() -> void:
	if _check_occlusion() == null:
		_mirror.is_player_visible = true

		if _facing_mirror and _are_layers_enabled:
			_set_layers_enabled(false, true)
		elif not _facing_mirror and not _are_layers_enabled:
			_set_layers_enabled(true, true)
	else:
		_mirror.is_player_visible = false

		if not _are_layers_enabled:
			_set_layers_enabled(true, true)


func _update_reveal_logic() -> void:
	if _check_occlusion() == null:
		_mirror.is_player_visible = true

		if _facing_mirror and not _are_layers_enabled:
			_set_layers_enabled(true, false)
		elif not _facing_mirror and _are_layers_enabled:
			_set_layers_enabled(false, false)
	else:
		_mirror.is_player_visible = false

		if _are_layers_enabled:
			_set_layers_enabled(false, false)


func _set_layers_enabled(enabled: bool, affect_raycast: bool) -> void:
	if _mirror.player:
		Pigments.set_layer_bit(_mirror.player, &"collision_mask", _mirror.layer_to_affect, enabled)

	if _ray_cast and affect_raycast:
		Pigments.set_layer_bit(_ray_cast, &"collision_mask", _mirror.layer_to_affect, enabled)

	if _mirror.mirror_type == Mirror3D.MirrorType.REVEAL:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if is_instance_valid(camera):
			Pigments.set_layer_bit(camera, &"cull_mask", _mirror.layer_to_affect, enabled)

	_are_layers_enabled = enabled


## Returns the collider between the mirror and the player camera, or null if
## the line of sight is clear.
func _check_occlusion() -> Object:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return null

	_ray_cast.target_position = _ray_cast.to_local(camera.global_position)
	_ray_cast.force_raycast_update()
	return _ray_cast.get_collider()


func _on_camera_entered() -> void:
	if _mirror.mirror_type != Mirror3D.MirrorType.VANILLA:
		_facing_mirror = true


func _on_camera_exited() -> void:
	if _mirror.mirror_type != Mirror3D.MirrorType.VANILLA:
		_facing_mirror = false
