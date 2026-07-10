@tool
class_name Mirror3D
extends Node3D
## Planar mirror: renders the reflection through a SubViewport camera mirrored
## across the quad plane, scales the viewport resolution with distance and
## drives the pigment layer logic for the REVEAL and DISSOLVE mirror types.

enum MirrorType { VANILLA, REVEAL, DISSOLVE }

@export var player: CharacterBody3D
@export var object_to_reflect: Node3D

@export_category("Mirror type")
@export var pigment: Pigments.Pigment = Pigments.Pigment.WHITE:
	set(value):
		pigment = value
		_pigment_dirty = true

@export var mirror_type: MirrorType = MirrorType.VANILLA:
	set(value):
		mirror_type = value
		_pigment_dirty = true


## Always reflects, even when player is not viewing the mirror.
@export var always_active: bool = true


@export_category("Cull")
## The visibility layers rendered by the mirror.
@export_flags_3d_render var cull_mask: int = 0xFFFFF:
	set(value):
		cull_mask = value
		_config_dirty = true

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
		_config_dirty = true

## The number of pixels to render per unit.
@export var pixels_per_unit: int = 400:
	set(value):
		pixels_per_unit = value
		_config_dirty = true

## The maximum number of mirror updates per second. If negative, unlimited.
@export var max_fps: float = -1.0

## If true, uses a linear (anti-aliased) filter, otherwise a nearest (aliased) filter.
@export var use_linear_filter: bool = true:
	set(value):
		use_linear_filter = value
		_config_dirty = true

## The modulate applied to the mirror.
@export var color: Color = Color(0.9, 0.97, 0.94):
	set(value):
		color = value
		_config_dirty = true

## Distances beyond which the resolution is divided by the matching
## res_decrease_factors entry. Sorted ascending; empty disables the scaling.
@export var res_decrease_distances: Array[float] = [1.0, 2.0, 3.0]

## Resolution divisors paired with res_decrease_distances.
@export var res_decrease_factors: Array[float] = [2.0, 4.0, 8.0]

## Enable or disable distortion.
@export var use_distortion: bool = false:
	set(value):
		use_distortion = value
		_config_dirty = true

## The amount to use the distortion texture.
@export_range(0, 100, 0.01) var distortion: float = 0.0:
	set(value):
		distortion = value
		_config_dirty = true

## The noise texture to distort the mirror with.
@export var distortion_texture: Texture2D = null:
	set(value):
		distortion_texture = value
		_config_dirty = true

## The single render/collision layer this mirror's pigment affects.
## Read by MirrorInteraction to toggle collision/cull bits.
var layer_to_affect: int = 1


## If true, the layer setup and border color are reapplied on the next frame.
var _pigment_dirty: bool = true
## If true, the mirror is reconfigured on the next handled frame.
var _config_dirty: bool = true
var _current_resolution_scale: float = -1.0
## Seconds since the mirror was last rendered (used by max_fps).
var _time_since_update: float = 0.0
## If true, the mirror updates on the next frame regardless of max_fps.
var _time_update_dirty: bool = true

@onready var _mirror_viewport: SubViewport = $Viewport
@onready var _mirror_camera: Camera3D = $Viewport/Camera
@onready var _mirror_quad: MeshInstance3D = $Quad
@onready var _shader_material: ShaderMaterial = _mirror_quad.get_active_material(0)


func _ready() -> void:
	if !Engine.is_editor_hint():
		_make_runtime_resources_unique()
	
	print("_mirror_viewport =", _mirror_viewport)
	print("valid =", is_instance_valid(_mirror_viewport))

	_mirror_viewport.use_occlusion_culling = true
	_apply_pigment()


func _process(delta: float) -> void:
	if _pigment_dirty:
		_apply_pigment()

	_handle_mirror(delta)


## Returns the transform that reflects across the plane with the given normal
## passing through offset.
static func get_mirror_transform(normal: Vector3, offset: Vector3) -> Transform3D:
	var basis_x: Vector3 = Vector3(1, 0, 0) - (2.0 * Vector3(normal.x * normal.x, normal.x * normal.y, normal.x * normal.z))
	var basis_y: Vector3 = Vector3(0, 1, 0) - (2.0 * Vector3(normal.y * normal.x, normal.y * normal.y, normal.y * normal.z))
	var basis_z: Vector3 = Vector3(0, 0, 1) - (2.0 * Vector3(normal.z * normal.x, normal.z * normal.y, normal.z * normal.z))
	var origin: Vector3 = 2.0 * normal.dot(offset) * normal
	return Transform3D(basis_x, basis_y, basis_z, origin)


func _handle_mirror(delta: float) -> void:
	
	if not is_inside_tree():
		return

	if _mirror_viewport == null:
		return

	if not is_instance_valid(_mirror_viewport):
		return
	
	if not is_visible_in_tree():
		return

	var player_camera: Camera3D = _get_active_camera()
	if not is_instance_valid(player_camera):
		return

	if _time_update_dirty:
		_time_update_dirty = false
	elif max_fps >= 0.0:
		_time_since_update += delta
		if _time_since_update < 1.0 / max_fps:
			_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return
	_time_since_update = 0.0

	var distance_from_camera: float = global_position.distance_to(player_camera.global_position)
	if distance_from_camera >= freeze_distance:
		_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

	if Engine.is_editor_hint():
		if not is_equal_approx(_current_resolution_scale, 1.0):
			_current_resolution_scale = 1.0
			_apply_viewport_size()
	else:
		_update_resolution_scale(distance_from_camera)

	if _config_dirty:
		_config_dirty = false
		_apply_mirror_config()

	var mirror_normal: Vector3 = _mirror_quad.global_basis.z
	var mirror_transform: Transform3D = get_mirror_transform(mirror_normal, _mirror_quad.global_position)
	_mirror_camera.global_transform = mirror_transform * player_camera.global_transform

	_mirror_camera.global_transform = _mirror_camera.global_transform.looking_at(
		(_mirror_camera.global_position + player_camera.global_position) / 2.0,
		_mirror_quad.global_basis.y
	)

	var camera_to_mirror_offset: Vector3 = _mirror_quad.global_position - _mirror_camera.global_position
	var near: float = maxf(absf(camera_to_mirror_offset.dot(mirror_normal)) + cull_near, 0.05)
	var far: float = camera_to_mirror_offset.length() + cull_far
	if far <= near:
		far = near + 0.1

	var local_camera_offset: Vector3 = _mirror_camera.global_basis.inverse() * camera_to_mirror_offset
	var frustum_offset: Vector2 = Vector2(local_camera_offset.x, local_camera_offset.y)
	_mirror_camera.set_frustum(size.x, frustum_offset, near, far)


func _get_active_camera() -> Camera3D:
	if Engine.is_editor_hint():
		return Engine.get_singleton(&"EditorInterface").get_editor_viewport_3d().get_camera_3d()
	return get_viewport().get_camera_3d()


## Duplicates the quad material and the viewport so mirror instances don't
## share render targets.
func _make_runtime_resources_unique() -> void:
	var material := _mirror_quad.get_active_material(0)

	if material is ShaderMaterial:
		_shader_material = material.duplicate(true)
		_mirror_quad.set_surface_override_material(0, _shader_material)
	else:
		push_warning("Mirror material is missing or not a ShaderMaterial.")


## Recomputes the affected layer, the mirror cull mask and the border color
## from the current pigment and mirror type.
func _apply_pigment() -> void:
	_pigment_dirty = false
	layer_to_affect = Pigments.LAYERS[pigment]
	cull_mask = 0xFFFFF

	match mirror_type:
		MirrorType.REVEAL:
			layer_to_affect += Pigments.INVISIBLE_SHIFT
		MirrorType.DISSOLVE:
			cull_mask &= ~(1 << (layer_to_affect - 1))
	
	

	if _shader_material:
		_shader_material.set_shader_parameter(&"border_color", Pigments.COLORS[pigment])


func _update_resolution_scale(distance_from_camera: float) -> void:
	var resolution_scale: float = 1.0
	for i: int in mini(res_decrease_distances.size(), res_decrease_factors.size()):
		if distance_from_camera >= res_decrease_distances[i]:
			resolution_scale = 1.0 / res_decrease_factors[i]

	if not is_equal_approx(resolution_scale, _current_resolution_scale):
		_current_resolution_scale = resolution_scale
		_apply_viewport_size()
		_time_update_dirty = true


func _apply_viewport_size() -> void:
	_mirror_viewport.size = Vector2i(
		maxi(2, int(size.x * pixels_per_unit * _current_resolution_scale)),
		maxi(2, int(size.y * pixels_per_unit * _current_resolution_scale))
	)


func _apply_mirror_config() -> void:
	if _shader_material == null:
		push_warning("Mirror material is missing or not a ShaderMaterial.")
		return

	_mirror_camera.cull_mask = cull_mask
	_mirror_camera.set_cull_mask_value(11, true)
	_mirror_camera.set_cull_mask_value(10, false)
	_mirror_quad.mesh.size = size
	_apply_viewport_size()

	var viewport_texture: ViewportTexture = _mirror_viewport.get_texture()
	_shader_material.set_shader_parameter(&"color", color)
	_shader_material.set_shader_parameter(&"distortion_texture", distortion_texture if use_distortion else null)
	_shader_material.set_shader_parameter(&"distortion_strength", distortion if use_distortion else 0.0)
	_shader_material.set_shader_parameter(&"mirror_texture_linear", viewport_texture if use_linear_filter else null)
	_shader_material.set_shader_parameter(&"mirror_texture_nearest", viewport_texture if not use_linear_filter else null)
	_shader_material.set_shader_parameter(&"use_mirror_texture_linear", use_linear_filter)
