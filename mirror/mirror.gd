@tool
class_name Mirror3D
extends Node3D

enum Pigment {WHITE, RED, BLUE, GREEN, YELLOW, VIOLET, ORANGE}
enum Mirror {REVEAL, DISSOLVE}

@onready var ray_cast: RayCast3D = $RayCast
@onready var visible_detector: VisibleOnScreenNotifier3D = $VisibleDetector
@onready var quad: MeshInstance3D = $Quad

@onready var shader_material: ShaderMaterial = quad.get_active_material(0)
@export var player: CharacterBody3D

var player_cam: Camera3D
var space_state: PhysicsDirectSpaceState3D
var collision_mask = 0xFFFF
var is_player_visible: bool = true

var facing_mirror: bool = false
var are_layers_enabled: bool = true
var layers_to_affect: Array[int]

#region BORING VARIABLES
@export_category("Mirror type")
@export var mirror_name: String
## Always reflects, even when player is not viewing the mirror.
@export var always_active: bool = true
@export var mirror_type: Mirror = Mirror.DISSOLVE
@export var pigment: Pigment

@export_category("Cull")
## The visibility layers rendered by the mirror.
@export_flags_3d_render var cull_mask: int = 0xFFFFF:
	set(value):
		config_dirty = true
		cull_mask = value
## The minimum distance of objects the mirror will render.
@export var cull_near: float = 0.05
## The maximum distance of objects the mirror will render.
@export var cull_far: float = 50.0
## The maximum distance of the player camera before the mirror is frozen.
@export var freeze_distance: float = 50.0


@export_category("Settings")
## The size of the mirror quad mesh in units.
@export var size: Vector2 = Vector2(1, 1):
	set(value):
		config_dirty = true
		size = value

## The number of pixels to render per unit.
@export var pixels_per_unit: int = 100:
	set(value):
		config_dirty = true
		pixels_per_unit = value

## The maximum number of mirror updates per second. If negative, unlimited.
@export var max_fps: float = -1

## If true, uses a linear (anti-aliased) filter, otherwise, uses a nearest (aliased) filter.
@export var use_linear_filter: bool = true:
	set(value):
		config_dirty = true
		use_linear_filter = value

## The modulate applied to the mirror.
@export var color: Color = Color(0.9, 0.97, 0.94):
	set(value):
		config_dirty = true
		color = value

## The amount to use the distortion texture.
@export_range(0, 100, 0.01) var distortion: float = 0.0:
	set(value):
		config_dirty = true
		distortion = value

## The noise texture to distort the mirror with.
@export var distortion_texture: Texture2D = null:
	set(value):
		config_dirty = true
		distortion_texture = value



## The viewport used to render the mirror.
@onready var mirror_viewport:SubViewport = $Viewport
## The viewport camera used to sample the mirror.
@onready var mirror_camera:Camera3D = $Viewport/Camera
## The quad mesh instance used to display the mirror.
@onready var mirror_quad:MeshInstance3D = $Quad


## If true, the mirror will be reconfigured on the next frame.
var config_dirty: bool = true
## The number of seconds since the mirror was updated.
var time_since_update: float = 0.0
## If true, the mirror will be updated on the next frame regardless of max_fps.
var time_update_dirty: bool = true
#endregion


func _ready() -> void:
	set_layers()
	set_border_color()
	
	if player:
		player_cam = player.get_node_or_null("Head/Camera3D")
		if not player_cam:
			push_error("Player camera not found in 'Head/Camera3D'")
	
	if not Engine.is_editor_hint():
		# Ensure each mirror has its own unique material instance
		var material = mirror_quad.get_active_material(0)
		if material != null and not material.is_class("ShaderMaterial"):
			push_warning("Mirror material is not a ShaderMaterial.")
		else:
			material = material.duplicate()
			mirror_quad.set_surface_override_material(0, material)

		# Force viewport texture refresh so it's not shared
		var new_viewport = mirror_viewport.duplicate()
		mirror_viewport.queue_free()
		add_child(new_viewport)
		mirror_viewport = new_viewport
		mirror_camera = mirror_viewport.get_node("Camera")
		
		# Mark for config
		config_dirty = true


func _physics_process(_delta):
	if Engine.is_editor_hint():
		return
		
	if player:
		var distance = global_position.distance_to(player.global_position)
		if distance < cull_far and player.walk_or_run == "WalkState":
			match mirror_type:
				Mirror.DISSOLVE:
					if check_occlusion() == null:
						is_player_visible = true
						if facing_mirror and are_layers_enabled:
							set_collision_mask(player, layers_to_affect, false)
							set_collision_mask(ray_cast, layers_to_affect, false)
							are_layers_enabled = false
							print("layers disabled 👎")
						elif not facing_mirror and not are_layers_enabled:
							set_collision_mask(player, layers_to_affect, true)
							set_collision_mask(ray_cast, layers_to_affect, true)
							are_layers_enabled = true
							print("layers enabled 👌")
					else:
						is_player_visible = false
						if not are_layers_enabled:
							set_collision_mask(player, layers_to_affect, true)
							set_collision_mask(ray_cast, layers_to_affect, true)
							are_layers_enabled = true
							print("layers enabled 👌 occlusion: ", check_occlusion())
			
				Mirror.REVEAL:
					if check_occlusion() == null:
						is_player_visible = true
						if facing_mirror and not are_layers_enabled:
							set_collision_mask(player, layers_to_affect, true)
							are_layers_enabled = true
							print("layers enabled 👌")
						elif not facing_mirror and are_layers_enabled:
							set_cull_mask(player_cam, layers_to_affect, false)
							set_collision_mask(player, layers_to_affect, false)
							are_layers_enabled = false
							print("layers disabled 👎")
					else:
						is_player_visible = false
						if facing_mirror and are_layers_enabled:
							set_cull_mask(player_cam, layers_to_affect, false)
							set_collision_mask(player, layers_to_affect, false)
							are_layers_enabled = false
							print("layers enabled 👌 occlusion: ", check_occlusion())
						elif not facing_mirror and are_layers_enabled:
							set_cull_mask(player_cam, layers_to_affect, false)
							set_collision_mask(player, layers_to_affect, false)
							are_layers_enabled = false
							print("layers disabled 👎")


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		set_border_color()
		set_layers()
		handle_mirror(delta)
		return
	
	if always_active or is_player_visible:
		handle_mirror(delta)



func handle_mirror(delta: float) -> void:
	# Ensure visible
	if !is_visible_in_tree():
		return
	
	# Get player camera viewing mirror
	var player_camera: Camera3D
	if Engine.is_editor_hint():
		player_camera = Engine.get_singleton(&"EditorInterface").get_editor_viewport_3d().get_camera_3d()
	else:
		player_camera = get_viewport().get_camera_3d()

	# Ensure player camera exists
	if !is_instance_valid(player_camera):
		return
		
	# Ensure enough time passed since last update
	if time_update_dirty:
		time_update_dirty = false
	else:
		if max_fps >= 0:
			time_since_update += delta
			if time_since_update < 1.0 / max_fps:
				mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
				return

	mirror_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	time_since_update = 0
		
	# Freeze mirror if player is far away
	if global_position.distance_to(player_camera.global_position) >= freeze_distance:
		mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	else:
		mirror_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		
	# Configure mirror
	if config_dirty:
		config_dirty = false
		var viewport_texture: ViewportTexture = mirror_viewport.get_texture()
		var quad_material: ShaderMaterial = mirror_quad.get_active_material(0)
		mirror_camera.cull_mask = cull_mask
		mirror_quad.mesh.size = size
		mirror_viewport.size = size * pixels_per_unit
		quad_material.set_shader_parameter(&"color", color)
		quad_material.set_shader_parameter(&"distortion_texture", distortion_texture)
		quad_material.set_shader_parameter(&"distortion_strength", distortion)
		quad_material.set_shader_parameter(&"mirror_texture_linear", viewport_texture if use_linear_filter else null)
		quad_material.set_shader_parameter(&"mirror_texture_nearest", viewport_texture if !use_linear_filter else null)
		quad_material.set_shader_parameter(&"use_mirror_texture_linear", use_linear_filter)
		
	# Transform mirror camera to opposite side of mirror plane
	var mirror_normal: Vector3 = mirror_quad.global_basis.z
	var mirror_transform: Transform3D = get_mirror_transform(mirror_normal, mirror_quad.global_position)
	mirror_camera.global_transform = mirror_transform * player_camera.global_transform
		
	# Look perpendicular into mirror plane for frustum camera
	mirror_camera.global_transform = mirror_camera.global_transform.looking_at(
		(mirror_camera.global_position / 2.0) + (player_camera.global_position / 2.0),
		mirror_quad.global_basis.y
	)
	var camera_to_mirror_offset: Vector3 = mirror_quad.global_position - mirror_camera.global_position
		
	# Get near and far cull distances (safe calculation)
	var near: float = abs(camera_to_mirror_offset.dot(mirror_normal)) + cull_near
	var far: float = camera_to_mirror_offset.length() + cull_far

	# Ensure near isn't too small (prevents clipping bugs)
	near = max(near, 0.05)

	# Ensure far is always greater than near (required by RenderingServer)
	if far <= near:
		far = near + 0.1

	# Apply frustum safely
	var cam_to_mirror_offset_camera_local: Vector3 = mirror_camera.global_basis.inverse() * camera_to_mirror_offset
	var frustum_offset := Vector2(cam_to_mirror_offset_camera_local.x, cam_to_mirror_offset_camera_local.y)
	mirror_camera.set_frustum(size.x, frustum_offset, near, far)


## Calculates the transformation that mirrors through the plane with the normal and offset.
static func get_mirror_transform(normal: Vector3, offset: Vector3) -> Transform3D:
	var basis_x: Vector3 = Vector3(1, 0, 0) - (2 * Vector3(normal.x * normal.x, normal.x * normal.y, normal.x * normal.z))
	var basis_y: Vector3 = Vector3(0, 1, 0) - (2 * Vector3(normal.y * normal.x, normal.y * normal.y, normal.y * normal.z))
	var basis_z: Vector3 = Vector3(0, 0, 1) - (2 * Vector3(normal.z * normal.x, normal.z * normal.y, normal.z * normal.z))
	var origin: Vector3 = 2 * normal.dot(offset) * normal
	return Transform3D(basis_x, basis_y, basis_z, origin)


#region LAYERS
func set_collision_mask(node: Node3D, layers: Array[int], enabled: bool) -> void:
	for layer in layers:
		var bit := 1 << (layer - 1)  # Convert 1-based layer to bit
		
		if enabled: node.collision_mask |= bit    # Add layer (set bit to 1)
		else:       node.collision_mask &= ~bit   # Remove layer (set bit to 0)


func set_cull_mask(camera: Camera3D, layers: Array[int], enabled: bool) -> void:
	for layer in layers:
		var bit := 1 << (layer - 1)  # Convert 1-based layer to bit
		
		if enabled: camera.cull_mask |= bit    # Add layer (set bit to 1)
		else:       camera.cull_mask &= ~bit   # Remove layer (set bit to 0)


# set the number of the layers to affect, based on the pigment name
func set_layers() -> void:	
	match pigment:
		Pigment.WHITE:  layers_to_affect = [1]
		Pigment.RED:    layers_to_affect = [3]
		Pigment.BLUE:   layers_to_affect = [4]
		Pigment.GREEN:  layers_to_affect = [5]
		Pigment.YELLOW: layers_to_affect = [6]
		Pigment.VIOLET: layers_to_affect = [7]
		Pigment.ORANGE: layers_to_affect = [8]
	
	cull_mask = 0xFFFFF
	
	match mirror_type:
		Mirror.REVEAL:
			for i in range(layers_to_affect.size()):
				layers_to_affect[i] += 10
		Mirror.DISSOLVE:
			for layer in layers_to_affect:
				cull_mask &= ~(1 << (layer - 1))


# set the border color based on the pigment name
func set_border_color() -> void:
	var border_color: Color = Color.WHITE
	match pigment:
		Pigment.WHITE:  border_color = Color(1, 1, 1, 1)
		Pigment.RED:    border_color = Color(1, 0, 0, 1)
		Pigment.BLUE:   border_color = Color(0, 0, 1, 1)
		Pigment.GREEN:  border_color = Color(0, 1, 0, 1)
		Pigment.YELLOW: border_color = Color(1, 1, 0, 1)
		Pigment.VIOLET: border_color = Color(1, 0, 1, 1)
		Pigment.ORANGE: border_color = Color(1, 0.6, 0, 1)
	shader_material.set_shader_parameter("border_color", border_color)
#endregion


func check_occlusion() -> Object:
	if player == null:
		ray_cast.enabled = false
		return

	# Enable RayCast3D and update its direction
	ray_cast.enabled = true

	# Calculate direction vector from mirror to player, relative to mirror
	var local_dir = to_local(player.global_transform.origin)
	ray_cast.target_position = local_dir + Vector3(0, 1.7, 0)
	ray_cast.force_raycast_update()

	# Check collision
	return ray_cast.get_collider()


#region SIGNALS
func _on_camera_entered() -> void:
	if mirror_type in [Mirror.REVEAL, Mirror.DISSOLVE]:
		facing_mirror = true
		print("facing mirror: ✅")


func _on_camera_exited() -> void:
	if mirror_type in [Mirror.REVEAL, Mirror.DISSOLVE]:
		facing_mirror = false
		print("facing mirror: ❌")
#endregion
