@tool
class_name Mirror3D
extends Node3D

enum Pigment { WHITE, RED, BLUE, GREEN, YELLOW, VIOLET, ORANGE }
enum Mirror { VANILLA, REVEAL, DISSOLVE }

@onready var ray_cast: RayCast3D = $RayCast
@onready var visible_detector: VisibleOnScreenNotifier3D = $VisibleDetector
@onready var quad: MeshInstance3D = $Quad

@onready var shader_material: ShaderMaterial = quad.get_active_material(0)
@export var player: CharacterBody3D

var player_cam: Camera3D
var space_state: PhysicsDirectSpaceState3D
var collision_mask: int = 0xFFFF
var is_player_visible: bool = true

var facing_mirror: bool = false
var are_layers_enabled: bool = true
var layers_to_affect: Array[int] = []

var current_resolution_scale: float = -1.0

#region BORING VARIABLES
@export_category("Mirror type")
@export var mirror_name: String
@export var pigment: Pigment = Pigment.WHITE
@export var mirror_type: Mirror = Mirror.VANILLA
## Always reflects, even when player is not viewing the mirror.
@export var always_active: bool = true

@export_category("Cull")
## The visibility layers rendered by the mirror.
@export_flags_3d_render var cull_mask: int = 0xFFFFF:
	set(value):
		cull_mask = value
		config_dirty = true

## The minimum distance of objects the mirror will render.
@export var cull_near: float = 0.05
## The maximum distance of objects the mirror will render.
@export var cull_far: float = 50.0
## The maximum distance of the player camera before the mirror is frozen.
@export var freeze_distance: float = 50.0

@export_category("Settings")
## The size of the mirror quad mesh in units.
@export var size: Vector2 = Vector2.ONE:
	set(value):
		size = value
		config_dirty = true

## The number of pixels to render per unit.
@export var pixels_per_unit: int = 400:
	set(value):
		pixels_per_unit = value
		config_dirty = true

## The maximum number of mirror updates per second. If negative, unlimited.
@export var max_fps: float = -1.0

## If true, uses a linear (anti-aliased) filter, otherwise, uses a nearest (aliased) filter.
@export var use_linear_filter: bool = true:
	set(value):
		use_linear_filter = value
		config_dirty = true

## The modulate applied to the mirror.
@export var color: Color = Color(0.9, 0.97, 0.94):
	set(value):
		color = value
		config_dirty = true

## Distance after which the mirror resolution will decrease.
@export_range(0, 1000, 0.1) var res_decrease_distance: float = 1.0

## Distance after which the mirror resolution will decrease.
@export_range(0, 1000, 0.1) var res_decrease_distance_2: float = 2.0

## Distance after which the mirror resolution will decrease.
@export_range(0, 1000, 0.1) var res_decrease_distance_3: float = 3.0

## Factor by which mirror resolution is divided when farther than res_decrease_distance.
@export_range(1.0, 8.0, 0.1) var res_decrease_factor: float = 2.0

## Factor by which mirror resolution is divided when farther than res_decrease_distance.
@export_range(1.0, 8.0, 0.1) var res_decrease_factor_2: float = 4.0

## Factor by which mirror resolution is divided when farther than res_decrease_distance.
@export_range(1.0, 8.0, 0.1) var res_decrease_factor_3: float = 8.0

## Enable or disable distortion
@export var use_distortion: bool = false

## The amount to use the distortion texture.
@export_range(0, 100, 0.01) var distortion: float = 0.0:
	set(value):
		distortion = value
		config_dirty = true

## The noise texture to distort the mirror with.
@export var distortion_texture: Texture2D = null:
	set(value):
		distortion_texture = value
		config_dirty = true

## The viewport used to render the mirror.
@onready var mirror_viewport: SubViewport = $Viewport
## The viewport camera used to sample the mirror.
@onready var mirror_camera: Camera3D = $Viewport/Camera
## The quad mesh instance used to display the mirror.
@onready var mirror_quad: MeshInstance3D = $Quad

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

	if Engine.is_editor_hint():
		return

	_make_runtime_resources_unique()
	config_dirty = true
	time_update_dirty = true
	current_resolution_scale = -1.0

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not player or mirror_type == Mirror.VANILLA:
		return

	var distance_to_player: float = global_position.distance_to(player.global_position)
	if distance_to_player >= cull_far:
		return

	if player.walk_or_run != "WalkState":
		return

	match mirror_type:
		Mirror.DISSOLVE:
			_update_dissolve_logic()
		Mirror.REVEAL:
			_update_reveal_logic()
		Mirror.VANILLA:
			pass

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		set_border_color()
		set_layers()
		handle_mirror(delta)
		return

	if always_active or is_player_visible:
		handle_mirror(delta)

func handle_mirror(delta: float) -> void:
	if not is_visible_in_tree():
		return

	var player_camera: Camera3D = _get_active_camera()
	if not is_instance_valid(player_camera):
		return

	if time_update_dirty:
		time_update_dirty = false
	elif max_fps >= 0.0:
		time_since_update += delta
		if time_since_update < 1.0 / max_fps:
			mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return

	mirror_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	time_since_update = 0.0

	var distance_from_camera: float = global_position.distance_to(player_camera.global_position)

	if distance_from_camera >= freeze_distance:
		mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	mirror_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

	if Engine.is_editor_hint():
		if !is_equal_approx(current_resolution_scale, 1.0):
			current_resolution_scale = 1.0
			_apply_viewport_size()
	else:
		_update_resolution_scale(distance_from_camera)

	if config_dirty:
		config_dirty = false
		_apply_mirror_config()

	var mirror_normal: Vector3 = mirror_quad.global_basis.z
	var mirror_transform: Transform3D = get_mirror_transform(mirror_normal, mirror_quad.global_position)
	mirror_camera.global_transform = mirror_transform * player_camera.global_transform

	mirror_camera.global_transform = mirror_camera.global_transform.looking_at(
		(mirror_camera.global_position / 2.0) + (player_camera.global_position / 2.0),
		mirror_quad.global_basis.y
	)

	var camera_to_mirror_offset: Vector3 = mirror_quad.global_position - mirror_camera.global_position
	var near: float = abs(camera_to_mirror_offset.dot(mirror_normal)) + cull_near
	var far: float = camera_to_mirror_offset.length() + cull_far

	near = max(near, 0.05)
	if far <= near:
		far = near + 0.1

	var local_camera_offset: Vector3 = mirror_camera.global_basis.inverse() * camera_to_mirror_offset
	var frustum_offset: Vector2 = Vector2(local_camera_offset.x, local_camera_offset.y)
	mirror_camera.set_frustum(size.x, frustum_offset, near, far)

func _get_active_camera() -> Camera3D:
	if Engine.is_editor_hint():
		return Engine.get_singleton(&"EditorInterface").get_editor_viewport_3d().get_camera_3d()
	return get_viewport().get_camera_3d()

func _make_runtime_resources_unique() -> void:
	var material: Material = mirror_quad.get_active_material(0)
	if material != null and not material.is_class("ShaderMaterial"):
		push_warning("Mirror material is not a ShaderMaterial.")
	else:
		material = material.duplicate()
		mirror_quad.set_surface_override_material(0, material)
		shader_material = material as ShaderMaterial

	var new_viewport: SubViewport = mirror_viewport.duplicate()
	mirror_viewport.queue_free()
	add_child(new_viewport)
	mirror_viewport = new_viewport
	mirror_camera = mirror_viewport.get_node("Camera") as Camera3D

func _update_dissolve_logic() -> void:
	var occluder: Object = check_occlusion()

	if occluder == null:
		is_player_visible = true

		if facing_mirror and are_layers_enabled:
			_set_layers_enabled(false, true)
			print("layers disabled 👎")
		elif not facing_mirror and not are_layers_enabled:
			_set_layers_enabled(true, true)
			print("layers enabled 👌")
	else:
		is_player_visible = false

		if not are_layers_enabled:
			_set_layers_enabled(true, true)
			print("layers enabled 👌 occlusion: ", occluder)

func _update_reveal_logic() -> void:
	var occluder: Object = check_occlusion()

	if occluder == null:
		is_player_visible = true

		if facing_mirror and not are_layers_enabled:
			_set_layers_enabled(true, false)
			print("layers enabled 👌")
		elif not facing_mirror and are_layers_enabled:
			_set_layers_enabled(false, false)
			print("layers disabled 👎")
	else:
		is_player_visible = false

		if facing_mirror and are_layers_enabled:
			_set_layers_enabled(false, false)
			print("layers enabled 👌 occlusion: ", occluder)
		elif not facing_mirror and are_layers_enabled:
			_set_layers_enabled(false, false)
			print("layers disabled 👎")

func _set_layers_enabled(enabled: bool, affect_raycast: bool) -> void:
	if player:
		set_collision_mask(player, layers_to_affect, enabled)

	if ray_cast and affect_raycast:
		set_collision_mask(ray_cast, layers_to_affect, enabled)

	if player_cam and mirror_type == Mirror.REVEAL:
		set_cull_mask(player_cam, layers_to_affect, enabled)

	are_layers_enabled = enabled

func _update_resolution_scale(distance_from_camera: float) -> void:
	var resolution_scale: float = 1.0
	if res_decrease_distance > 0.0:
		if distance_from_camera >= res_decrease_distance and distance_from_camera < res_decrease_distance_2:
			resolution_scale = 1.0 / res_decrease_factor
		if distance_from_camera >= res_decrease_distance_2 and distance_from_camera < res_decrease_distance_3:
			resolution_scale = 1.0 / res_decrease_factor_2
		if distance_from_camera >= res_decrease_distance_3:
			resolution_scale = 1.0 / res_decrease_factor_3

	if !is_equal_approx(resolution_scale, current_resolution_scale):
		current_resolution_scale = resolution_scale
		_apply_viewport_size()
		time_update_dirty = true

func _apply_viewport_size() -> void:
	var viewport_size: Vector2i = Vector2i(
		max(2, int(size.x * pixels_per_unit * current_resolution_scale)),
		max(2, int(size.y * pixels_per_unit * current_resolution_scale))
	)
	mirror_viewport.size = viewport_size

func _apply_mirror_config() -> void:
	var viewport_texture: ViewportTexture = mirror_viewport.get_texture()
	var quad_material: ShaderMaterial = mirror_quad.get_active_material(0) as ShaderMaterial

	if quad_material == null:
		push_warning("Mirror material is missing or not a ShaderMaterial.")
		return

	mirror_camera.cull_mask = cull_mask
	mirror_quad.mesh.size = size
	_apply_viewport_size()

	quad_material.set_shader_parameter(&"color", color)

	if use_distortion:
		quad_material.set_shader_parameter(&"distortion_texture", distortion_texture)
		quad_material.set_shader_parameter(&"distortion_strength", distortion)
	else:
		quad_material.set_shader_parameter(&"distortion_texture", null)
		quad_material.set_shader_parameter(&"distortion_strength", 0.0)

	quad_material.set_shader_parameter(&"mirror_texture_linear", viewport_texture if use_linear_filter else null)
	quad_material.set_shader_parameter(&"mirror_texture_nearest", viewport_texture if !use_linear_filter else null)
	quad_material.set_shader_parameter(&"use_mirror_texture_linear", use_linear_filter)

static func get_mirror_transform(normal: Vector3, offset: Vector3) -> Transform3D:
	var basis_x: Vector3 = Vector3(1, 0, 0) - (2.0 * Vector3(normal.x * normal.x, normal.x * normal.y, normal.x * normal.z))
	var basis_y: Vector3 = Vector3(0, 1, 0) - (2.0 * Vector3(normal.y * normal.x, normal.y * normal.y, normal.y * normal.z))
	var basis_z: Vector3 = Vector3(0, 0, 1) - (2.0 * Vector3(normal.z * normal.x, normal.z * normal.y, normal.z * normal.z))
	var origin: Vector3 = 2.0 * normal.dot(offset) * normal
	return Transform3D(basis_x, basis_y, basis_z, origin)

#region LAYERS
func set_collision_mask(node: Node3D, layers: Array[int], enabled: bool) -> void:
	for layer in layers:
		var bit: int = 1 << (layer - 1)
		if enabled:
			node.collision_mask |= bit
		else:
			node.collision_mask &= ~bit

func set_cull_mask(camera: Camera3D, layers: Array[int], enabled: bool) -> void:
	for layer in layers:
		var bit: int = 1 << (layer - 1)
		if enabled:
			camera.cull_mask |= bit
		else:
			camera.cull_mask &= ~bit

func set_layers() -> void:
	match pigment:
		Pigment.WHITE:
			layers_to_affect = [1]
		Pigment.RED:
			layers_to_affect = [3]
		Pigment.BLUE:
			layers_to_affect = [4]
		Pigment.GREEN:
			layers_to_affect = [5]
		Pigment.YELLOW:
			layers_to_affect = [6]
		Pigment.VIOLET:
			layers_to_affect = [7]
		Pigment.ORANGE:
			layers_to_affect = [8]

	cull_mask = 0xFFFFF

	match mirror_type:
		Mirror.VANILLA:
			pass
		Mirror.REVEAL:
			for i: int in range(layers_to_affect.size()):
				layers_to_affect[i] += 10
		Mirror.DISSOLVE:
			for layer: int in layers_to_affect:
				cull_mask &= ~(1 << (layer - 1))

func set_border_color() -> void:
	var border_color: Color = Color.WHITE

	match pigment:
		Pigment.WHITE:
			border_color = Color(1, 1, 1, 1)
		Pigment.RED:
			border_color = Color(1, 0, 0, 1)
		Pigment.BLUE:
			border_color = Color(0, 0, 1, 1)
		Pigment.GREEN:
			border_color = Color(0, 1, 0, 1)
		Pigment.YELLOW:
			border_color = Color(1, 1, 0, 1)
		Pigment.VIOLET:
			border_color = Color(1, 0, 1, 1)
		Pigment.ORANGE:
			border_color = Color(1, 0.6, 0, 1)

	if shader_material:
		shader_material.set_shader_parameter("border_color", border_color)
#endregion

func check_occlusion() -> Object:
	if player == null:
		ray_cast.enabled = false
		return null

	ray_cast.enabled = true

	var local_dir: Vector3 = to_local(player.global_transform.origin)
	ray_cast.target_position = local_dir + Vector3(0, 1.7, 0)
	ray_cast.force_raycast_update()

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
