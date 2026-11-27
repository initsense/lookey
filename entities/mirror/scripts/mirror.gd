# Based on Mirror3D (https://github.com/Norodix/Mirror3D)
# Copyright (c) 2025 Joyless, Norodix — MIT License (see entities/mirror/LICENSE.md)
@tool
class_name Mirror3D
extends Node3D
## A flat mirror that reflects the room using internal cameras:
## one for what the player sees directly (Layer 10), and a few reflected views for what other
## mirrors see when this mirror is reflected inside them (Layer 11), one per viewpoint, as many levels deep as MirrorManager.render_depth allows.
## It also sets up the border color and visibility layers for reveal and dissolve effects.

enum MirrorType { REVEAL, DISSOLVE }

## Render layer for the mirror surface seen directly by the player.
const DIRECT_MIRROR_LAYER: int = 10
## Render layer for the mirror surface seen only by other mirrors.
const REFLECTED_MIRROR_LAYER: int = 11
## Render layer of the MirrorSun. Real-world cameras never include it, so that sun lights mirrors only.
const MIRROR_SUN_LAYER: int = 21
## Frame width on a mirror seen inside another mirror. The player's nested reflection
## sits on the shared edge, so this stays thinner than that strip.
const REFLECTED_BORDER_THICKNESS: float = 0.012
## Minimum perpendicular distance (in meters) from an observer to the mirror plane
## required to build a non-degenerate off-axis frustum.
const MIN_PLANE_DISTANCE: float = 0.05
## How many reflected views this mirror can render at once, each from its own viewpoint:
## one per chain of mirrors it appears in (see MirrorManager.render_depth).
## Must match MAX_REFLECTED_VIEWS in mirror.gdshader and the ReflectedViewport nodes in mirror.tscn.
const MAX_REFLECTED_VIEWS: int = 8
## Viewpoint stored for an unused reflected view, so far away that no mirror camera ever matches it.
const UNUSED_REFLECTED_OBSERVER: Vector3 = Vector3(1e9, 1e9, 1e9)
## Highest width or height (in pixels) any mirror SubViewport will allocate.
const MAX_VIEWPORT_DIMENSION: int = 4096
## Smallest width or height (in UV space, 0..1) a cropped view will shrink to at grazing angles.
const MIN_UV_SPAN: float = 0.05
## Pixel step used to bucket dynamic SubViewport sizes so small camera turns do not reallocate VRAM.
const RESOLUTION_PIXEL_STEP: int = 64
## Pixel margin beyond the current bucket required before resizing the SubViewport.
const RESOLUTION_PIXEL_HYSTERESIS: int = 96
## Extra UV margin added around the visible mirror region so 1-frame headbob or look deltas never clip.
const BASE_UV_CROP_MARGIN: float = 0.03
## Full-quad UV rectangle used when the mirror is uncropped.
const FULL_UV_RECT: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)
## Plane-clipping epsilon when slicing the mirror quad against the player camera frustum.
const FRUSTUM_CLIP_EPSILON: float = 1e-5

## The player character, found in the scene when the mirror starts.
var player: CharacterBody3D
## The player's 3D camera, found with the player.
var player_cam: Camera3D

@export_category("Mirror type")
## The color of this mirror's frame. Determines which colored objects it can reveal or dissolve.
@export var pigment: Pigments.Pigment = Pigments.Pigment.WHITE:
	set(value):
		pigment = value
		_pigment_dirty = true

## Choose REVEAL to make hidden objects appear in the glass, or DISSOLVE to make visible objects disappear in the glass.
@export var mirror_type: MirrorType = MirrorType.REVEAL:
	set(value):
		mirror_type = value
		_pigment_dirty = true

## When enabled, the mirror keeps updating its reflection even when the player is looking away.
@export var always_active: bool = true

@export_category("Cull")
## Which 3D render layers this mirror's camera can see. Updated automatically when you change the pigment or mirror type.
@export_flags_3d_render var cull_mask: int = 0xFFFFF:
	set(value):
		cull_mask = value
		_config_dirty = true

## How close an object can get to the mirror glass before it is clipped out of the reflection.
@export var cull_near: float = 0.05
## How far away (in meters) the mirror can see objects in its reflection.
@export var cull_far: float = 50.0
## If the player is farther than this distance (in meters), the mirror pauses rendering to save performance.
@export var freeze_distance: float = 50.0

@export_category("Resolution")
## Matches the mirror's sharpness to the player's camera resolution up close and lowers it smoothly with distance. Turn off to use a fixed Pixels Per Unit size instead.
@export var dynamic_resolution: bool = true:
	set(value):
		dynamic_resolution = value
		_invalidate_resolution_state()

## How close (in meters) to the mirror glass the player must stand for the reflection to render at full camera sharpness (Max Resolution Scale).
@export_range(0.0, 200.0, 0.1, "or_greater", "suffix:m") var full_resolution_distance: float = 3.0:
	set(value):
		full_resolution_distance = value
		_invalidate_resolution_state()

## Distance (in meters) from the mirror glass where the reflection reaches its lowest sharpness (Min Resolution Scale).
@export_range(0.1, 500.0, 0.1, "or_greater", "suffix:m") var min_resolution_distance: float = 30.0:
	set(value):
		min_resolution_distance = value
		_invalidate_resolution_state()

## Sharpness up close as a fraction of the camera's screen resolution (1.0 matches the camera pixel-for-pixel).
@export_range(0.1, 2.0, 0.05) var max_resolution_scale: float = 1.0:
	set(value):
		max_resolution_scale = value
		_invalidate_resolution_state()

## Lowest sharpness when far away, as a fraction of the camera's screen resolution.
@export_range(0.05, 1.0, 0.05) var min_resolution_scale: float = 0.25:
	set(value):
		min_resolution_scale = value
		_invalidate_resolution_state()

## Number of quality steps between full and minimum sharpness. Stepping keeps the mirror from resizing its texture every single frame while you walk.
@export_range(1, 32, 1) var resolution_steps: int = 8:
	set(value):
		resolution_steps = value
		_invalidate_resolution_state()

## Sharpness multiplier for mirrors seen reflected inside other mirrors, keeping nested reflections fast.
@export_range(0.1, 1.0, 0.05) var reflected_resolution_scale: float = 0.5:
	set(value):
		reflected_resolution_scale = value
		_invalidate_resolution_state()

## Fixed reflection sharpness (pixels per meter of mirror size) used only when Dynamic Resolution is turned off.
@export var pixels_per_unit: int = 400:
	set(value):
		pixels_per_unit = value
		_invalidate_resolution_state()

@export_category("Settings")
## Width and height of the mirror glass in meters.
@export var size: Vector2 = Vector2.ONE:
	set(value):
		size = value
		_invalidate_resolution_state()

## Caps how many times per second the direct reflection updates. Set to -1 for unlimited (every frame).
@export var max_fps: float = -1.0

## Smooths the reflection texture when enabled, or uses pixelated nearest-neighbor filtering when disabled.
@export var use_linear_filter: bool = true:
	set(value):
		use_linear_filter = value
		_config_dirty = true

## Subtle tint color applied to the glass reflection.
@export var color: Color = Color(0.9, 0.97, 0.94):
	set(value):
		color = value
		_config_dirty = true

## Enables wavy glass distortion on the reflection.
@export var use_distortion: bool = false:
	set(value):
		use_distortion = value
		_config_dirty = true

## How strong the wavy glass distortion looks.
@export_range(0, 100, 0.01) var distortion: float = 0.0:
	set(value):
		distortion = value
		_config_dirty = true

## Noise texture used to create the wavy glass distortion effect.
@export var distortion_texture: Texture2D = null:
	set(value):
		distortion_texture = value
		_config_dirty = true

## The single render/collision layer this mirror's pigment targets.
var layer_to_affect: int = 1

var _pigment_dirty: bool = true
var _config_dirty: bool = true
var _reflected_pigments: Array[Pigments.Pigment] = []
var _reflected_slot_keys: PackedStringArray = PackedStringArray()
var _reflected_observers: PackedVector3Array = PackedVector3Array()
var _current_resolution_scale: float = -1.0
var _current_step_index: int = -1
var _last_camera_viewport_size: Vector2i = Vector2i.ZERO
var _target_viewport_size: Vector2i = Vector2i(400, 400)
var _reflected_viewport_size: Vector2i = Vector2i(400, 400)
var _pending_direct_uv_rect: Rect2 = FULL_UV_RECT
var _applied_direct_uv_rect: Rect2 = FULL_UV_RECT
var _time_since_update: float = 0.0
var _time_update_dirty: bool = true
var _direct_update_allowed: bool = true
var _has_rendered_direct: bool = false
var _has_rendered_reflected: bool = false

@onready var _mirror_viewport: SubViewport = get_node_or_null("Viewport") as SubViewport
@onready var _mirror_camera: Camera3D = get_node_or_null("Viewport/Camera") as Camera3D
@onready var _reflected_viewport: SubViewport = get_node_or_null("ReflectedViewport") as SubViewport
@onready var _reflected_camera: Camera3D = get_node_or_null("ReflectedViewport/Camera") as Camera3D
var _reflected_viewports: Array[SubViewport] = []
var _reflected_cameras: Array[Camera3D] = []
@onready var _mirror_quad: MeshInstance3D = get_node_or_null("Quad") as MeshInstance3D
@onready var _reflected_quad: MeshInstance3D = get_node_or_null("ReflectedQuad") as MeshInstance3D
@onready var _mirror_notifier: VisibleOnScreenNotifier3D = get_node_or_null("MirrorNotifier") as VisibleOnScreenNotifier3D
@onready var _shader_material: ShaderMaterial = (
	_mirror_quad.get_active_material(0) as ShaderMaterial if _mirror_quad != null else null
)
var _reflected_shader_material: ShaderMaterial = null


func _ready() -> void:
	if _mirror_quad != null:
		_mirror_quad.layers = 1 << (DIRECT_MIRROR_LAYER - 1)
		_mirror_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _reflected_quad != null:
		_reflected_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if not Engine.is_editor_hint():
		_resolve_player_and_camera()
		_make_runtime_resources_unique()
	elif _reflected_quad != null:
		_reflected_quad.visible = false
	_sync_collider_size()
	_collect_reflected_views()

	if _mirror_viewport != null:
		_mirror_viewport.use_occlusion_culling = true
	for viewport: SubViewport in _reflected_viewports:
		if viewport != null:
			viewport.use_occlusion_culling = true

	_apply_pigment()

	if not Engine.is_editor_hint() and _mirror_viewport != null and _mirror_quad != null:
		MirrorManager.register_mirror(self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		MirrorManager.unregister_mirror(self)


func _process(delta: float) -> void:
	if _pigment_dirty:
		_apply_pigment()

	if Engine.is_editor_hint():
		_handle_mirror(delta)
	else:
		MirrorManager.step_frame(delta)


## Returns the 3D transformation matrix that flips points and directions across a flat mirror plane.
static func get_mirror_transform(normal: Vector3, offset: Vector3) -> Transform3D:
	var n: Vector3 = normal.normalized()
	var basis_x: Vector3 = Vector3(1, 0, 0) - (2.0 * Vector3(n.x * n.x, n.x * n.y, n.x * n.z))
	var basis_y: Vector3 = Vector3(0, 1, 0) - (2.0 * Vector3(n.y * n.x, n.y * n.y, n.y * n.z))
	var basis_z: Vector3 = Vector3(0, 0, 1) - (2.0 * Vector3(n.z * n.x, n.z * n.y, n.z * n.z))
	var origin: Vector3 = 2.0 * n.dot(offset) * n
	return Transform3D(basis_x, basis_y, basis_z, origin)


## Side-effect-free camera preparation used when physics queries need up-to-date mirror transforms
## before the next render frame runs. Does not advance timers or change viewport update modes.
func prepare_camera_only() -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false
	if _mirror_viewport == null or not is_instance_valid(_mirror_viewport):
		return false
	if _mirror_quad == null or not is_instance_valid(_mirror_quad):
		return false

	var active_camera: Camera3D = _get_active_camera()
	if not is_instance_valid(active_camera):
		return false

	if _pigment_dirty:
		_apply_pigment()
	if _config_dirty:
		_config_dirty = false
		_apply_mirror_config()

	var distance_from_camera: float = global_position.distance_to(active_camera.global_position)
	if distance_from_camera >= freeze_distance:
		return false

	_configure_mirror_camera(
		_mirror_camera,
		_reflection_observer_position(active_camera),
		cull_mask,
		true
	)
	return true


## Updates the mirror's direct player-facing reflection camera and settings for the current frame.
## Returns true when the mirror is active and within range of the player camera.
func prepare_frame(delta: float) -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false

	if _mirror_viewport == null or not is_instance_valid(_mirror_viewport):
		return false

	if _mirror_quad == null or not is_instance_valid(_mirror_quad):
		return false

	var active_camera: Camera3D = _get_active_camera()
	if not is_instance_valid(active_camera):
		return false

	# Hidden blocks stay on their own layers. The real-world camera must not draw those layers.
	Pigments.hide_hidden_entities_from_camera(active_camera)
	if not Engine.is_editor_hint():
		active_camera.set_cull_mask_value(DIRECT_MIRROR_LAYER, true)
		active_camera.set_cull_mask_value(REFLECTED_MIRROR_LAYER, false)

	if _pigment_dirty:
		_apply_pigment()

	var distance_from_camera: float = global_position.distance_to(active_camera.global_position)
	if distance_from_camera >= freeze_distance:
		_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		freeze_reflected_view(false)
		_direct_update_allowed = false
		return false

	# Update resolution scale BEFORE evaluating _time_update_dirty so resolution changes
	# immediately mark this frame as needing a fresh render.
	var observer_pos: Vector3 = _reflection_observer_position(active_camera)
	_update_direct_resolution_and_crop(active_camera, observer_pos)

	if _config_dirty:
		_config_dirty = false
		_apply_mirror_config()

	if _time_update_dirty or not _has_rendered_direct:
		_time_update_dirty = false
		_time_since_update = 0.0
		_direct_update_allowed = true
	elif max_fps == 0.0:
		_direct_update_allowed = false
	elif max_fps > 0.0 and max_fps < 60.0:
		_time_since_update += delta
		var interval: float = 1.0 / max_fps
		if _time_since_update < interval:
			_direct_update_allowed = false
		else:
			_time_since_update = fmod(_time_since_update, interval)
			_direct_update_allowed = true
	else:
		_direct_update_allowed = true

	if not _configure_mirror_camera(
		_mirror_camera,
		observer_pos,
		cull_mask,
		true,
		_pending_direct_uv_rect
	):
		_direct_update_allowed = false
	return true


## Returns the slot key for a reflected view of this glass. The path lists the mirrors the glass is seen
## through, outer mirror (the one the player looks at) first: [outer] when this glass sits directly inside
## the outer mirror, [outer, middle] when it sits inside the glass of a middle mirror, and so on.
static func reflected_view_key(path: Array) -> String:
	var ids := PackedStringArray()
	for mirror: Mirror3D in path:
		ids.append(str(mirror.get_instance_id()))
	return ">".join(ids)


## Configures one reflected view so another mirror can see this glass.
## observer_position is the camera that will draw this glass: an outer mirror's camera, or a middle
## mirror's reflected camera for 3-mirror chains. The glass uses the additive pigment mix of the chain.
## Each viewpoint gets its own slot (see assign_reflected_slots), so several mirrors can show this
## glass at once without sharing the wrong viewpoint or pigment.
func configure_reflected_view(
	observer_position: Vector3,
	cull_mask_override: int,
	allow_nested_layer: bool = false,
	reflected_pigment: int = -1,
	slot: int = 0
) -> void:
	if slot < 0 or slot >= _reflected_viewports.size():
		return
	if _pigment_dirty:
		_apply_pigment()
	_reflected_pigments[slot] = (reflected_pigment as Pigments.Pigment) if reflected_pigment >= 0 else pigment
	_reflected_observers[slot] = observer_position
	if _config_dirty:
		_config_dirty = false
		_apply_mirror_config()
	_push_reflected_slot_parameters()

	var viewport: SubViewport = _reflected_viewports[slot]
	var camera: Camera3D = _reflected_cameras[slot]
	if camera == null or viewport == null:
		return

	if viewport.size != _reflected_viewport_size:
		viewport.size = _reflected_viewport_size

	if not _configure_mirror_camera(camera, observer_position, cull_mask_override, allow_nested_layer):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _reflected_quad != null:
		_reflected_quad.visible = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_has_rendered_reflected = true


## Gives every viewpoint that shows this glass its own reflected view slot (keys from reflected_view_key).
## A viewpoint keeps its slot for as long as it shows this glass, so views never swap.
## Keys earlier in the list win when slots run out.
## Returns the slot for each key in the same order, or -1 when all slots are taken.
func assign_reflected_slots(keys: PackedStringArray) -> PackedInt32Array:
	for slot: int in _reflected_slot_keys.size():
		if _reflected_slot_keys[slot] != "" and not keys.has(_reflected_slot_keys[slot]):
			_reflected_slot_keys[slot] = ""

	var slots := PackedInt32Array()
	slots.resize(keys.size())
	slots.fill(-1)
	for i: int in keys.size():
		slots[i] = _reflected_slot_keys.find(keys[i])
	for i: int in keys.size():
		if slots[i] >= 0:
			continue
		var free_slot: int = _reflected_slot_keys.find("")
		if free_slot < 0 or free_slot >= _reflected_viewports.size():
			continue
		_reflected_slot_keys[free_slot] = keys[i]
		slots[i] = free_slot
	return slots


## Returns the slot that renders this glass for a key from reflected_view_key, or -1.
func get_reflected_slot(key: String) -> int:
	return _reflected_slot_keys.find(key)


## Returns the camera of the reflected view for a key while that view is rendering, otherwise null.
## Mirrors seen inside this glass are drawn from this camera's position.
func get_rendering_reflected_camera(key: String) -> Camera3D:
	var slot: int = get_reflected_slot(key)
	if slot < 0 or slot >= _reflected_viewports.size():
		return null
	var viewport: SubViewport = _reflected_viewports[slot]
	if viewport == null or viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		return null
	return _reflected_cameras[slot]


## Pauses one reflected view slot that no viewpoint uses anymore.
func release_reflected_slot(slot: int) -> void:
	if slot < 0 or slot >= _reflected_viewports.size():
		return
	_reflected_slot_keys[slot] = ""
	_reflected_observers[slot] = UNUSED_REFLECTED_OBSERVER
	_push_reflected_slot_parameters()
	var viewport: SubViewport = _reflected_viewports[slot]
	if viewport != null and is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Pauses rendering of every reflected view while optionally keeping the glass visible.
func freeze_reflected_view(keep_quad_visible: bool) -> void:
	for slot: int in _reflected_viewports.size():
		release_reflected_slot(slot)
	if _reflected_quad != null and is_instance_valid(_reflected_quad):
		_reflected_quad.visible = keep_quad_visible and _has_rendered_reflected


## Enables or pauses rendering on the direct player-facing viewport.
## Only resizes the SubViewport and updates direct_uv_rect when actively rendering so a paused viewport is never cleared or stretched.
func set_direct_viewport_active(active: bool, force_ignore_max_fps: bool = false) -> void:
	if _mirror_viewport == null or not is_instance_valid(_mirror_viewport):
		return
	var should_render: bool = active and (_direct_update_allowed or force_ignore_max_fps or not _has_rendered_direct)
	if should_render:
		if _mirror_viewport.size != _target_viewport_size:
			_mirror_viewport.size = _target_viewport_size
		_push_direct_uv_rect(_pending_direct_uv_rect)
		_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_has_rendered_direct = true
	else:
		_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Returns the world-space width and height of the mirror glass, accounting for node scale.
func get_world_size() -> Vector2:
	if _mirror_quad == null:
		return size
	var quad_scale: Vector3 = _mirror_quad.global_basis.get_scale().abs()
	return Vector2(size.x * quad_scale.x, size.y * quad_scale.y)


## Returns the unit normal vector of the mirror glass in world space.
func get_mirror_normal() -> Vector3:
	if _mirror_quad != null:
		return _mirror_quad.global_basis.z.normalized()
	return global_basis.z.normalized()


## Returns the center position of the mirror glass in world space.
func get_mirror_origin() -> Vector3:
	if _mirror_quad != null:
		return _mirror_quad.global_position
	return global_position


## Reflects a 3D world point across this mirror's plane.
func reflect_point(point: Vector3) -> Vector3:
	return get_mirror_transform(get_mirror_normal(), get_mirror_origin()) * point


func _handle_mirror(delta: float) -> void:
	if not prepare_frame(delta):
		return
	if Engine.is_editor_hint():
		if _mirror_viewport.size != _target_viewport_size:
			_mirror_viewport.size = _target_viewport_size
		_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	else:
		set_direct_viewport_active(true)


## Viewpoint for this mirror's own camera. Headbob and shake move only the player
## camera, so the mirror follows the camera holder and stays still while the player moves.
func _reflection_observer_position(camera: Camera3D) -> Vector3:
	if camera == player_cam:
		var holder: Node3D = camera.get_parent() as Node3D
		if holder != null:
			return holder.global_position
	return camera.global_position


func _configure_mirror_camera(
	target_camera: Camera3D,
	observer_position: Vector3,
	mask: int,
	allow_nested_layer: bool,
	uv_rect: Rect2 = FULL_UV_RECT
) -> bool:
	if target_camera == null or _mirror_quad == null:
		return false

	target_camera.cull_mask = mask
	target_camera.set_cull_mask_value(REFLECTED_MIRROR_LAYER, allow_nested_layer)
	target_camera.set_cull_mask_value(DIRECT_MIRROR_LAYER, false)
	# set_cull_mask_value only accepts layers 1-20, so the mirror sun bit is set on the mask itself.
	target_camera.cull_mask |= 1 << (MIRROR_SUN_LAYER - 1)

	var quad_pos: Vector3 = _mirror_quad.global_position
	var quad_right: Vector3 = _mirror_quad.global_basis.x.normalized()
	var up_axis: Vector3 = _mirror_quad.global_basis.y.normalized()
	var mirror_normal: Vector3 = _mirror_quad.global_basis.z.normalized()
	var signed_distance: float = (observer_position - quad_pos).dot(mirror_normal)
	if absf(signed_distance) <= MIN_PLANE_DISTANCE:
		return false

	var mirror_transform: Transform3D = get_mirror_transform(mirror_normal, quad_pos)
	var reflected_pos: Vector3 = mirror_transform * observer_position
	var midpoint: Vector3 = (reflected_pos + observer_position) * 0.5

	target_camera.projection = Camera3D.PROJECTION_FRUSTUM
	target_camera.keep_aspect = Camera3D.KEEP_WIDTH
	target_camera.global_transform = Transform3D(Basis.IDENTITY, reflected_pos).looking_at(
		midpoint,
		up_axis
	)

	var camera_to_mirror_offset: Vector3 = quad_pos - target_camera.global_position
	var proj_distance: float = absf(camera_to_mirror_offset.dot(mirror_normal))
	if proj_distance <= MIN_PLANE_DISTANCE:
		return false

	var world_size: Vector2 = get_world_size()
	var uv_center: Vector2 = uv_rect.position + uv_rect.size * 0.5
	var is_front_facing: bool = _is_observer_front_facing(signed_distance)
	var local_x: float = (0.5 - uv_center.x) * world_size.x if is_front_facing else (uv_center.x - 0.5) * world_size.x
	var local_y: float = (0.5 - uv_center.y) * world_size.y
	var rect_center_world: Vector3 = quad_pos + quad_right * local_x + up_axis * local_y
	var camera_to_rect_offset: Vector3 = rect_center_world - target_camera.global_position

	var near: float = maxf(proj_distance + cull_near, 0.05)
	var far: float = maxf(camera_to_mirror_offset.length(), camera_to_rect_offset.length()) + cull_far
	if far <= near:
		far = near + 0.1

	var local_camera_offset: Vector3 = target_camera.global_basis.inverse() * camera_to_rect_offset
	var frustum_scale: float = near / proj_distance
	var frustum_offset: Vector2 = Vector2(local_camera_offset.x, local_camera_offset.y) * frustum_scale
	# Keep-width frustum: size is the near-plane width. Height follows the viewport aspect.
	var frustum_width: float = maxf(uv_rect.size.x * world_size.x, 1e-4) * frustum_scale
	target_camera.set_frustum(frustum_width, frustum_offset, near, far)
	return true


func _resolve_player_and_camera() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(player_cam):
		player_cam = _find_player_camera()
	if not is_instance_valid(player) and is_instance_valid(player_cam):
		player = _find_player_body(player_cam)
	if not is_instance_valid(player):
		player = _find_named_player()
	if is_instance_valid(player) and not is_instance_valid(player_cam):
		player_cam = player.get_node_or_null("CamHolder/Camera3D") as Camera3D
	# A dissolved body keeps its pigment layer so mirror rays can still see it.
	# The player only blocks on the world and the entity-collider layer, or that pigment layer stays solid.
	if is_instance_valid(player):
		var solid_mask: int = (
			(1 << (Pigments.WORLD_GEOMETRY_LAYER - 1))
			| (1 << (Pigments.ENTITY_COLLIDER_LAYER - 1))
		)
		if player.collision_mask != solid_mask:
			player.collision_mask = solid_mask


## Returns the player camera from the camera_player group, or from a Player body in the scene.
func _find_player_camera() -> Camera3D:
	var group_cam: Node = get_tree().get_first_node_in_group(&"camera_player")
	if group_cam is Camera3D:
		return group_cam as Camera3D
	var named: CharacterBody3D = _find_named_player()
	if named != null:
		return named.get_node_or_null("CamHolder/Camera3D") as Camera3D
	return null


## Returns the CharacterBody3D named Player, if the scene has one.
func _find_named_player() -> CharacterBody3D:
	var named: Node = get_tree().root.find_child("Player", true, false)
	if named is CharacterBody3D:
		return named as CharacterBody3D
	return null


## Walks up from the camera to the character body that carries it.
func _find_player_body(camera: Camera3D) -> CharacterBody3D:
	var ancestor: Node = camera.get_parent()
	while ancestor != null:
		if ancestor is CharacterBody3D:
			return ancestor as CharacterBody3D
		ancestor = ancestor.get_parent()
	return null


func _get_active_camera() -> Camera3D:
	if Engine.is_editor_hint():
		return Engine.get_singleton(&"EditorInterface").get_editor_viewport_3d().get_camera_3d()
	if not is_instance_valid(player_cam):
		_resolve_player_and_camera()
	if is_instance_valid(player_cam):
		return player_cam
	return get_viewport().get_camera_3d() if get_viewport() != null else null


## Creates unique meshes, materials, and viewports at runtime so multiple mirrors
## in the same level do not overwrite each other's reflections or frame colors.
func _make_runtime_resources_unique() -> void:
	if _mirror_quad == null:
		return

	if _mirror_quad.mesh != null:
		_mirror_quad.mesh = _mirror_quad.mesh.duplicate()

	var material: Material = _mirror_quad.get_active_material(0)
	if material is ShaderMaterial:
		_shader_material = (material as ShaderMaterial).duplicate(true)
		_mirror_quad.set_surface_override_material(0, _shader_material)
	else:
		push_warning("Mirror material is missing or not a ShaderMaterial.")

	if _reflected_viewport == null and _mirror_viewport != null:
		_reflected_viewport = _mirror_viewport.duplicate() as SubViewport
		_reflected_viewport.name = "ReflectedViewport"
		add_child(_reflected_viewport)
		_reflected_camera = _reflected_viewport.get_node_or_null("Camera") as Camera3D

	if _reflected_quad == null:
		_reflected_quad = MeshInstance3D.new()
		_reflected_quad.name = "ReflectedQuad"
		add_child(_reflected_quad)

	_reflected_quad.transform = _mirror_quad.transform
	_reflected_quad.layers = 1 << (REFLECTED_MIRROR_LAYER - 1)
	_reflected_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reflected_quad.visible = false
	if _reflected_quad.mesh != null and _reflected_quad.mesh != _mirror_quad.mesh:
		_reflected_quad.mesh = _reflected_quad.mesh.duplicate()
	else:
		_reflected_quad.mesh = _mirror_quad.mesh

	if _shader_material != null:
		_reflected_shader_material = _shader_material.duplicate(true)
		_reflected_quad.set_surface_override_material(0, _reflected_shader_material)

	var collider_shape := get_node_or_null("Collider/Shape") as CollisionShape3D
	if collider_shape != null and collider_shape.shape != null:
		collider_shape.shape = collider_shape.shape.duplicate()


func _collect_reflected_views() -> void:
	_reflected_viewports.clear()
	_reflected_cameras.clear()
	for slot: int in MAX_REFLECTED_VIEWS:
		var node_name: String = "ReflectedViewport" if slot == 0 else "ReflectedViewport%d" % (slot + 1)
		var viewport: SubViewport = get_node_or_null(node_name) as SubViewport
		if viewport == null and not Engine.is_editor_hint() and _reflected_viewport != null:
			viewport = _reflected_viewport.duplicate() as SubViewport
			viewport.name = node_name
			add_child(viewport)
		_reflected_viewports.append(viewport)
		_reflected_cameras.append(viewport.get_node_or_null("Camera") as Camera3D if viewport != null else null)

	_reflected_pigments.resize(MAX_REFLECTED_VIEWS)
	_reflected_pigments.fill(pigment)
	_reflected_slot_keys.resize(MAX_REFLECTED_VIEWS)
	_reflected_slot_keys.fill("")
	_reflected_observers.resize(MAX_REFLECTED_VIEWS)
	_reflected_observers.fill(UNUSED_REFLECTED_OBSERVER)


## Sends every slot's viewpoint and frame color to the reflected glass shader.
func _push_reflected_slot_parameters() -> void:
	if _reflected_shader_material == null:
		return
	var border_colors := PackedColorArray()
	for slot_pigment: Pigments.Pigment in _reflected_pigments:
		border_colors.append(Pigments.COLORS[slot_pigment])
	_reflected_shader_material.set_shader_parameter(&"reflected_observers", _reflected_observers)
	_reflected_shader_material.set_shader_parameter(&"reflected_border_colors", border_colors)


## Updates the mirror's target layer, camera cull mask, and frame color to match its pigment and type.
func _apply_pigment() -> void:
	_pigment_dirty = false
	_reflected_pigments.fill(pigment)
	layer_to_affect = Pigments.get_entity_layer(
		pigment,
		mirror_type == MirrorType.REVEAL
	)
	cull_mask = Pigments.compute_mirror_cull_mask(
		pigment,
		mirror_type == MirrorType.REVEAL
	)
	_config_dirty = true

	if _shader_material != null:
		_shader_material.set_shader_parameter(&"border_color", Pigments.COLORS[pigment])
	_push_reflected_slot_parameters()


func _invalidate_resolution_state() -> void:
	_current_resolution_scale = -1.0
	_current_step_index = -1
	_config_dirty = true
	_time_update_dirty = true


func _push_direct_uv_rect(rect: Rect2) -> void:
	if _shader_material == null:
		return
	if Engine.is_editor_hint():
		return
	var target_rect: Rect2 = rect if dynamic_resolution else FULL_UV_RECT
	if (
		is_equal_approx(_applied_direct_uv_rect.position.x, target_rect.position.x)
		and is_equal_approx(_applied_direct_uv_rect.position.y, target_rect.position.y)
		and is_equal_approx(_applied_direct_uv_rect.size.x, target_rect.size.x)
		and is_equal_approx(_applied_direct_uv_rect.size.y, target_rect.size.y)
	):
		return
	_applied_direct_uv_rect = target_rect
	_shader_material.set_shader_parameter(
		&"direct_uv_rect",
		Vector4(target_rect.position.x, target_rect.position.y, target_rect.size.x, target_rect.size.y)
	)


## Returns true when the observer sees the mirror QuadMesh's front-facing winding.
## A negative-determinant transform flips triangle winding in Godot, inverting FRONT_FACING in the shader.
func _is_observer_front_facing(signed_distance: float) -> bool:
	var det_sign: float = 1.0
	if _mirror_quad != null and _mirror_quad.global_basis.determinant() < 0.0:
		det_sign = -1.0
	return (signed_distance * det_sign) > 0.0


## Shortest world-space distance from point to the bounded rectangular mirror glass surface.
func _distance_to_mirror_surface(point: Vector3) -> float:
	if _mirror_quad == null:
		return global_position.distance_to(point)
	var quad_pos: Vector3 = _mirror_quad.global_position
	var quad_right: Vector3 = _mirror_quad.global_basis.x.normalized()
	var quad_up: Vector3 = _mirror_quad.global_basis.y.normalized()
	var quad_normal: Vector3 = _mirror_quad.global_basis.z.normalized()
	var world_size: Vector2 = get_world_size()
	var half_x: float = maxf(world_size.x * 0.5, 0.0)
	var half_y: float = maxf(world_size.y * 0.5, 0.0)
	var offset: Vector3 = point - quad_pos
	var clamped_x: float = clampf(offset.dot(quad_right), -half_x, half_x)
	var clamped_y: float = clampf(offset.dot(quad_up), -half_y, half_y)
	var plane_dist: float = offset.dot(quad_normal)
	var in_plane_dx: float = offset.dot(quad_right) - clamped_x
	var in_plane_dy: float = offset.dot(quad_up) - clamped_y
	return sqrt(in_plane_dx * in_plane_dx + in_plane_dy * in_plane_dy + plane_dist * plane_dist)


## Effective 3D render target resolution of the active camera's viewport.
## Falls back to the project's configured window size in headless mode or before a viewport is sized.
func _get_camera_viewport_size(camera: Camera3D) -> Vector2i:
	var fallback_w: int = maxi(2, int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)))
	var fallback_h: int = maxi(2, int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))
	if DisplayServer.get_name() == "headless":
		return Vector2i(fallback_w, fallback_h)
	if is_instance_valid(camera):
		var vp: Viewport = camera.get_viewport()
		if vp != null:
			var rect_size: Vector2 = vp.get_visible_rect().size
			var scale_3d: float = vp.scaling_3d_scale if vp.scaling_3d_scale > 0.0 else 1.0
			var w: int = roundi(rect_size.x * scale_3d)
			var h: int = roundi(rect_size.y * scale_3d)
			if w > 64 and h > 64:
				return Vector2i(mini(w, MAX_VIEWPORT_DIMENSION), mini(h, MAX_VIEWPORT_DIMENSION))
	return Vector2i(mini(fallback_w, MAX_VIEWPORT_DIMENSION), mini(fallback_h, MAX_VIEWPORT_DIMENSION))


## Quantizes distance_from_surface into discrete resolution steps with hysteresis so walking near a
## boundary never ping-pongs the SubViewport size on consecutive frames.
func _update_resolution_scale(distance_from_surface: float) -> float:
	if not dynamic_resolution:
		if not is_equal_approx(_current_resolution_scale, 1.0):
			_current_resolution_scale = 1.0
			_current_step_index = 0
			_time_update_dirty = true
		return 1.0

	var max_scale: float = clampf(maxf(max_resolution_scale, min_resolution_scale), 0.05, 4.0)
	var min_scale: float = clampf(minf(min_resolution_scale, max_resolution_scale), 0.05, max_scale)
	var near_dist: float = maxf(full_resolution_distance, 0.0)
	var far_dist: float = maxf(min_resolution_distance, near_dist)
	var steps: int = maxi(resolution_steps, 1)

	var target_scale: float = max_scale
	if steps <= 1 or is_equal_approx(far_dist, near_dist) or is_equal_approx(max_scale, min_scale):
		target_scale = max_scale if distance_from_surface <= near_dist else min_scale
		_current_step_index = 0 if is_equal_approx(target_scale, max_scale) else steps - 1
	else:
		var span: float = far_dist - near_dist
		var raw_t: float = clampf((distance_from_surface - near_dist) / span, 0.0, 1.0)
		var step_count_minus_one: int = steps - 1
		var continuous_step: float = raw_t * float(step_count_minus_one)
		var chosen_step: int
		if _current_step_index < 0 or _current_step_index > step_count_minus_one:
			chosen_step = clampi(roundi(continuous_step), 0, step_count_minus_one)
		else:
			chosen_step = _current_step_index
			# Require crossing 0.65 of a step (0.15 hysteresis deadband around the 0.5 midpoint)
			# before jumping to a neighbor step.
			if continuous_step > float(_current_step_index) + 0.65:
				chosen_step = clampi(roundi(continuous_step), _current_step_index + 1, step_count_minus_one)
			elif continuous_step < float(_current_step_index) - 0.65:
				chosen_step = clampi(roundi(continuous_step), 0, _current_step_index - 1)
		_current_step_index = chosen_step
		var quantized_t: float = float(chosen_step) / float(step_count_minus_one)
		target_scale = lerpf(max_scale, min_scale, quantized_t)

	if not is_equal_approx(target_scale, _current_resolution_scale):
		_current_resolution_scale = target_scale
		_time_update_dirty = true
	return _current_resolution_scale


## Updates distance scale, target/reflected SubViewport sizes, and direct frustum crop UV rect in order.
func _update_direct_resolution_and_crop(active_camera: Camera3D, observer_position: Vector3) -> void:
	var surface_distance: float = _distance_to_mirror_surface(active_camera.global_position)
	_update_resolution_scale(surface_distance)

	var cam_vp_size: Vector2i = _get_camera_viewport_size(active_camera)
	var vp_changed: bool = cam_vp_size != _last_camera_viewport_size
	_last_camera_viewport_size = cam_vp_size

	if not dynamic_resolution:
		_pending_direct_uv_rect = FULL_UV_RECT
		var prev_fixed: Vector2i = _target_viewport_size
		_apply_fixed_viewport_size()
		if _target_viewport_size != prev_fixed:
			_time_update_dirty = true
		return

	if Engine.is_editor_hint():
		_pending_direct_uv_rect = FULL_UV_RECT
		var editor_size: Vector2i = _compute_aspect_matched_size(cam_vp_size, _current_resolution_scale)
		if editor_size != _target_viewport_size or vp_changed:
			_target_viewport_size = editor_size
			_reflected_viewport_size = _compute_reflected_dynamic_size(cam_vp_size)
			_time_update_dirty = true
		return

	var clip_info: Dictionary = _compute_raw_visible_uv_and_footprint(
		active_camera,
		observer_position,
		cam_vp_size
	)
	var raw_uv_rect: Rect2 = clip_info["uv_rect"]
	var footprint_px: Vector2 = clip_info["footprint_px"]
	var covers_full_screen: bool = clip_info["covers_full_screen"]

	var new_direct_size: Vector2i = _compute_quantized_direct_size(
		cam_vp_size,
		footprint_px,
		covers_full_screen,
		vp_changed
	)
	if new_direct_size != _target_viewport_size:
		_target_viewport_size = new_direct_size
		_time_update_dirty = true

	_reflected_viewport_size = _compute_reflected_dynamic_size(cam_vp_size)
	_pending_direct_uv_rect = _expand_uv_rect_to_viewport_aspect(raw_uv_rect, _target_viewport_size)


func _compute_quantized_direct_size(
	cam_vp_size: Vector2i,
	footprint_px: Vector2,
	covers_full_screen: bool,
	force_recompute: bool
) -> Vector2i:
	var scale_factor: float = _current_resolution_scale if _current_resolution_scale > 0.0 else 1.0
	var max_w: float = float(cam_vp_size.x) * scale_factor
	var max_h: float = float(cam_vp_size.y) * scale_factor

	if covers_full_screen:
		return Vector2i(
			clampi(roundi(max_w), 2, MAX_VIEWPORT_DIMENSION),
			clampi(roundi(max_h), 2, MAX_VIEWPORT_DIMENSION)
		)

	var desired_w: float = minf(footprint_px.x * scale_factor, max_w)
	var desired_h: float = minf(footprint_px.y * scale_factor, max_h)

	var snapped_w: int = _quantize_dimension_with_hysteresis(
		desired_w,
		_target_viewport_size.x,
		roundi(max_w),
		force_recompute or not _has_rendered_direct
	)
	var snapped_h: int = _quantize_dimension_with_hysteresis(
		desired_h,
		_target_viewport_size.y,
		roundi(max_h),
		force_recompute or not _has_rendered_direct
	)
	return Vector2i(snapped_w, snapped_h)


func _quantize_dimension_with_hysteresis(
	desired: float,
	current: int,
	cap: int,
	bypass_hysteresis: bool
) -> int:
	var clamped_cap: int = clampi(cap, 2, MAX_VIEWPORT_DIMENSION)
	if desired >= float(clamped_cap) - float(RESOLUTION_PIXEL_STEP) * 0.5:
		return clamped_cap
	var bucket: int = maxi(
		RESOLUTION_PIXEL_STEP,
		int(ceil(desired / float(RESOLUTION_PIXEL_STEP))) * RESOLUTION_PIXEL_STEP
	)
	bucket = clampi(bucket, 2, clamped_cap)
	if bypass_hysteresis or current <= 2:
		return bucket
	if absf(desired - float(current)) < float(RESOLUTION_PIXEL_HYSTERESIS) and current <= clamped_cap:
		return current
	return bucket


func _compute_aspect_matched_size(cam_vp_size: Vector2i, scale_factor: float) -> Vector2i:
	var world_size: Vector2 = get_world_size()
	var w_m: float = maxf(world_size.x, 0.01)
	var h_m: float = maxf(world_size.y, 0.01)
	var aspect: float = w_m / h_m
	var pixel_budget: float = maxf(
		4.0,
		float(cam_vp_size.x) * float(cam_vp_size.y) * scale_factor * scale_factor
	)
	var out_h: int = clampi(roundi(sqrt(pixel_budget / aspect)), 2, MAX_VIEWPORT_DIMENSION)
	var out_w: int = clampi(roundi(float(out_h) * aspect), 2, MAX_VIEWPORT_DIMENSION)
	return Vector2i(out_w, out_h)


func _compute_reflected_dynamic_size(cam_vp_size: Vector2i) -> Vector2i:
	var base_scale: float = _current_resolution_scale if _current_resolution_scale > 0.0 else 1.0
	var refl_scale: float = clampf(reflected_resolution_scale, 0.05, 1.0) * base_scale
	return _compute_aspect_matched_size(cam_vp_size, refl_scale)


## Clips the mirror quad against the active camera's frustum, returning:
## - "uv_rect": visible region in shader uv space (with headbob & distortion margin)
## - "footprint_px": projected width & height on the camera's viewport in pixels
## - "covers_full_screen": true when the mirror fills >= 85% of the screen width or height
func _compute_raw_visible_uv_and_footprint(
	active_camera: Camera3D,
	observer_position: Vector3,
	cam_vp_size: Vector2i
) -> Dictionary:
	var vp_vec := Vector2(float(cam_vp_size.x), float(cam_vp_size.y))
	if _mirror_quad == null or not is_instance_valid(active_camera):
		return {
			"uv_rect": FULL_UV_RECT,
			"footprint_px": vp_vec,
			"covers_full_screen": true,
		}

	var world_size: Vector2 = get_world_size()
	if world_size.x <= 1e-4 or world_size.y <= 1e-4:
		return {
			"uv_rect": FULL_UV_RECT,
			"footprint_px": Vector2(2.0, 2.0),
			"covers_full_screen": false,
		}

	# Throttled mirrors (max_fps >= 0) keep the full quad framed so camera motion between updates
	# never reveals unrendered edges.
	var allow_crop: bool = max_fps < 0.0

	var quad_pos: Vector3 = _mirror_quad.global_position
	var quad_right: Vector3 = _mirror_quad.global_basis.x.normalized()
	var quad_up: Vector3 = _mirror_quad.global_basis.y.normalized()
	var mirror_normal: Vector3 = _mirror_quad.global_basis.z.normalized()
	var half_x: float = world_size.x * 0.5
	var half_y: float = world_size.y * 0.5

	var poly := PackedVector3Array([
		quad_pos - quad_right * half_x - quad_up * half_y,
		quad_pos + quad_right * half_x - quad_up * half_y,
		quad_pos + quad_right * half_x + quad_up * half_y,
		quad_pos - quad_right * half_x + quad_up * half_y,
	])

	var frustum_planes: Array[Plane] = (
		_build_analytic_frustum_planes(active_camera, vp_vec)
		if DisplayServer.get_name() == "headless"
		else active_camera.get_frustum()
	)
	for plane: Plane in frustum_planes:
		poly = _clip_poly_against_frustum_plane(poly, plane)
		if poly.is_empty():
			break

	# Completely outside the camera frustum (e.g. an off-screen always_active mirror):
	# keep the full quad ready at a modest aspect-matched footprint.
	if poly.is_empty():
		var fallback_size: Vector2i = _compute_aspect_matched_size(cam_vp_size, 1.0)
		return {
			"uv_rect": FULL_UV_RECT,
			"footprint_px": Vector2(float(fallback_size.x), float(fallback_size.y)),
			"covers_full_screen": false,
		}

	var signed_distance: float = (observer_position - quad_pos).dot(mirror_normal)
	var is_front_facing: bool = _is_observer_front_facing(signed_distance)

	var uv_min := Vector2(INF, INF)
	var uv_max := Vector2(-INF, -INF)
	var px_min := Vector2(INF, INF)
	var px_max := Vector2(-INF, -INF)
	var cam_basis_z: Vector3 = active_camera.global_basis.z
	var cam_origin: Vector3 = active_camera.global_position
	var vp_rect_size: Vector2 = (
		active_camera.get_viewport().get_visible_rect().size
		if active_camera.get_viewport() != null
		else vp_vec
	)
	var px_scale := Vector2(
		vp_vec.x / maxf(vp_rect_size.x, 1.0),
		vp_vec.y / maxf(vp_rect_size.y, 1.0)
	)
	var use_analytic_projection: bool = (
		DisplayServer.get_name() == "headless"
		or vp_rect_size.x <= 64.0
		or vp_rect_size.y <= 64.0
	)

	for pt: Vector3 in poly:
		var rel: Vector3 = pt - quad_pos
		var lx: float = rel.dot(quad_right)
		var ly: float = rel.dot(quad_up)
		var u: float = (0.5 - lx / world_size.x) if is_front_facing else (0.5 + lx / world_size.x)
		var v: float = 0.5 - ly / world_size.y
		uv_min.x = minf(uv_min.x, u)
		uv_min.y = minf(uv_min.y, v)
		uv_max.x = maxf(uv_max.x, u)
		uv_max.y = maxf(uv_max.y, v)

		# Project clipped point onto screen pixels to measure actual screen coverage.
		var depth_along_look: float = -(pt - cam_origin).dot(cam_basis_z)
		if depth_along_look > 0.01:
			var screen_pt: Vector2
			if use_analytic_projection:
				screen_pt = _project_point_to_screen_analytic(active_camera, pt, vp_vec)
			else:
				screen_pt = active_camera.unproject_position(pt) * px_scale
			px_min.x = minf(px_min.x, clampf(screen_pt.x, 0.0, vp_vec.x))
			px_min.y = minf(px_min.y, clampf(screen_pt.y, 0.0, vp_vec.y))
			px_max.x = maxf(px_max.x, clampf(screen_pt.x, 0.0, vp_vec.x))
			px_max.y = maxf(px_max.y, clampf(screen_pt.y, 0.0, vp_vec.y))

	var footprint_w: float = vp_vec.x
	var footprint_h: float = vp_vec.y
	if px_max.x >= px_min.x and px_max.y >= px_min.y:
		# Include a small padding factor corresponding to the UV safety margin.
		footprint_w = clampf((px_max.x - px_min.x) * 1.08, 2.0, vp_vec.x)
		footprint_h = clampf((px_max.y - px_min.y) * 1.08, 2.0, vp_vec.y)

	var covers_full_screen: bool = (
		footprint_w >= vp_vec.x * 0.85
		and footprint_h >= vp_vec.y * 0.85
	)

	if not allow_crop:
		return {
			"uv_rect": FULL_UV_RECT,
			"footprint_px": Vector2(footprint_w, footprint_h),
			"covers_full_screen": covers_full_screen,
		}

	# Add safety margin for headbob/camera-offset delta and optional glass distortion.
	var headbob_world: float = active_camera.global_position.distance_to(observer_position)
	var margin_u: float = BASE_UV_CROP_MARGIN + (headbob_world / world_size.x)
	var margin_v: float = BASE_UV_CROP_MARGIN + (headbob_world / world_size.y)
	if use_distortion and distortion > 0.0:
		var dist_uv: float = distortion / maxf(minf(vp_vec.x, vp_vec.y), 64.0)
		margin_u += dist_uv
		margin_v += dist_uv

	var min_u: float = clampf(uv_min.x - margin_u, 0.0, 1.0)
	var max_u: float = clampf(uv_max.x + margin_u, 0.0, 1.0)
	var min_v: float = clampf(uv_min.y - margin_v, 0.0, 1.0)
	var max_v: float = clampf(uv_max.y + margin_v, 0.0, 1.0)

	# Enforce MIN_UV_SPAN so grazing-angle slivers never create a near-zero frustum.
	if max_u - min_u < MIN_UV_SPAN:
		var center_u: float = clampf((min_u + max_u) * 0.5, MIN_UV_SPAN * 0.5, 1.0 - MIN_UV_SPAN * 0.5)
		min_u = center_u - MIN_UV_SPAN * 0.5
		max_u = center_u + MIN_UV_SPAN * 0.5
	if max_v - min_v < MIN_UV_SPAN:
		var center_v: float = clampf((min_v + max_v) * 0.5, MIN_UV_SPAN * 0.5, 1.0 - MIN_UV_SPAN * 0.5)
		min_v = center_v - MIN_UV_SPAN * 0.5
		max_v = center_v + MIN_UV_SPAN * 0.5

	return {
		"uv_rect": Rect2(min_u, min_v, max_u - min_u, max_v - min_v),
		"footprint_px": Vector2(footprint_w, footprint_h),
		"covers_full_screen": covers_full_screen,
	}


## Expands raw_rect outward along its narrower world-space axis so that
## (rect.size.x * world_size.x) / (rect.size.y * world_size.y) strictly equals viewport_size.x / viewport_size.y.
## Shifts into [0, 1] first where room exists, and extends past [0, 1] without clamping size when needed.
func _expand_uv_rect_to_viewport_aspect(raw_rect: Rect2, viewport_size: Vector2i) -> Rect2:
	var world_size: Vector2 = get_world_size()
	var w_m: float = maxf(world_size.x, 1e-4)
	var h_m: float = maxf(world_size.y, 1e-4)
	var vp_aspect: float = float(maxi(viewport_size.x, 1)) / float(maxi(viewport_size.y, 1))

	var pos_u: float = raw_rect.position.x
	var pos_v: float = raw_rect.position.y
	var size_u: float = maxf(raw_rect.size.x, MIN_UV_SPAN)
	var size_v: float = maxf(raw_rect.size.y, MIN_UV_SPAN)

	var span_w_m: float = size_u * w_m
	var span_h_m: float = size_v * h_m
	var current_world_aspect: float = span_w_m / span_h_m

	if current_world_aspect < vp_aspect:
		var target_size_u: float = (span_h_m * vp_aspect) / w_m
		var center_u: float = pos_u + size_u * 0.5
		pos_u = center_u - target_size_u * 0.5
		size_u = target_size_u
		if size_u <= 1.0:
			pos_u = clampf(pos_u, 0.0, 1.0 - size_u)
	elif current_world_aspect > vp_aspect:
		var target_size_v: float = (span_w_m / vp_aspect) / h_m
		var center_v: float = pos_v + size_v * 0.5
		pos_v = center_v - target_size_v * 0.5
		size_v = target_size_v
		if size_v <= 1.0:
			pos_v = clampf(pos_v, 0.0, 1.0 - size_v)

	return Rect2(pos_u, pos_v, size_u, size_v)


## Builds outward-facing frustum planes analytically using screen_size's true aspect ratio
## (used in headless mode where Godot's dummy viewport reports a 1:1 aspect to Camera3D.get_frustum()).
static func _build_analytic_frustum_planes(camera: Camera3D, screen_size: Vector2) -> Array[Plane]:
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return camera.get_frustum()
	var aspect: float = screen_size.x / maxf(screen_size.y, 1.0)
	var tan_half_fov: float = tan(deg_to_rad(camera.fov) * 0.5)
	var tan_x: float
	var tan_y: float
	if camera.keep_aspect == Camera3D.KEEP_HEIGHT:
		tan_y = tan_half_fov
		tan_x = tan_y * aspect
	else:
		tan_x = tan_half_fov
		tan_y = tan_x / aspect

	var cam_xf: Transform3D = camera.global_transform
	var origin: Vector3 = cam_xf.origin
	var right: Vector3 = cam_xf.basis.x.normalized()
	var up: Vector3 = cam_xf.basis.y.normalized()
	var back: Vector3 = cam_xf.basis.z.normalized() # Camera looks along -back
	var forward: Vector3 = -back

	var near_pt: Vector3 = origin + forward * maxf(camera.near, 0.01)
	var far_pt: Vector3 = origin + forward * maxf(camera.far, camera.near + 0.1)

	# Outward-pointing normals (distance_to(p) <= 0 is inside).
	var n_near: Vector3 = back
	var n_far: Vector3 = forward
	var n_left: Vector3 = (-right - forward * tan_x).normalized()
	var n_right: Vector3 = (right - forward * tan_x).normalized()
	var n_bottom: Vector3 = (-up - forward * tan_y).normalized()
	var n_top: Vector3 = (up - forward * tan_y).normalized()

	return [
		Plane(n_near, near_pt),
		Plane(n_far, far_pt),
		Plane(n_left, origin),
		Plane(n_top, origin),
		Plane(n_right, origin),
		Plane(n_bottom, origin),
	]


## Analytic perspective/frustum screen projection used in headless mode where the root Viewport rect is tiny.
func _project_point_to_screen_analytic(camera: Camera3D, world_pt: Vector3, screen_size: Vector2) -> Vector2:
	var local: Vector3 = camera.global_transform.affine_inverse() * world_pt
	var z_dist: float = maxf(-local.z, 0.01)
	var aspect: float = screen_size.x / maxf(screen_size.y, 1.0)
	var half_h: float
	var half_w: float
	if camera.keep_aspect == Camera3D.KEEP_HEIGHT:
		half_h = tan(deg_to_rad(camera.fov) * 0.5) * z_dist
		half_w = half_h * aspect
	else:
		half_w = tan(deg_to_rad(camera.fov) * 0.5) * z_dist
		half_h = half_w / aspect
	var ndc_x: float = local.x / maxf(half_w, 1e-5)
	var ndc_y: float = local.y / maxf(half_h, 1e-5)
	return Vector2(
		(ndc_x * 0.5 + 0.5) * screen_size.x,
		(0.5 - ndc_y * 0.5) * screen_size.y
	)


## Clips a 3D polygon against one Camera3D frustum plane (outward normal: inside is plane.distance_to(p) <= 0).
static func _clip_poly_against_frustum_plane(poly: PackedVector3Array, plane: Plane) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count: int = poly.size()
	if count == 0:
		return out
	for i: int in range(count):
		var curr: Vector3 = poly[i]
		var next: Vector3 = poly[(i + 1) % count]
		var d_curr: float = plane.distance_to(curr)
		var d_next: float = plane.distance_to(next)
		var curr_in: bool = d_curr <= FRUSTUM_CLIP_EPSILON
		var next_in: bool = d_next <= FRUSTUM_CLIP_EPSILON
		if curr_in:
			out.append(curr)
		if curr_in != next_in:
			var denom: float = d_curr - d_next
			if not is_zero_approx(denom):
				var t: float = clampf(d_curr / denom, 0.0, 1.0)
				out.append(curr.lerp(next, t))
	return out


func _apply_fixed_viewport_size() -> void:
	var world_size: Vector2 = get_world_size()
	var ppu: int = maxi(1, pixels_per_unit)
	_target_viewport_size = Vector2i(
		clampi(int(world_size.x * ppu), 2, MAX_VIEWPORT_DIMENSION),
		clampi(int(world_size.y * ppu), 2, MAX_VIEWPORT_DIMENSION)
	)
	_reflected_viewport_size = _target_viewport_size


func _apply_viewport_size() -> void:
	if not dynamic_resolution:
		_apply_fixed_viewport_size()
		return
	var active_cam: Camera3D = _get_active_camera()
	var cam_vp_size: Vector2i = _get_camera_viewport_size(active_cam)
	var scale_factor: float = _current_resolution_scale if _current_resolution_scale > 0.0 else clampf(max_resolution_scale, 0.05, 4.0)
	_target_viewport_size = _compute_aspect_matched_size(cam_vp_size, scale_factor)
	_reflected_viewport_size = _compute_reflected_dynamic_size(cam_vp_size)


func _apply_mirror_config() -> void:
	if _shader_material == null:
		push_warning("Mirror material is missing or not a ShaderMaterial.")
		return

	if _mirror_camera != null:
		_mirror_camera.cull_mask = cull_mask
		_mirror_camera.set_cull_mask_value(REFLECTED_MIRROR_LAYER, true)
		_mirror_camera.set_cull_mask_value(DIRECT_MIRROR_LAYER, false)
		_mirror_camera.cull_mask |= 1 << (MIRROR_SUN_LAYER - 1)

	for camera: Camera3D in _reflected_cameras:
		if camera != null:
			camera.keep_aspect = Camera3D.KEEP_WIDTH
			camera.projection = Camera3D.PROJECTION_FRUSTUM
			camera.cull_mask |= 1 << (MIRROR_SUN_LAYER - 1)

	if _mirror_quad != null and _mirror_quad.mesh is QuadMesh:
		(_mirror_quad.mesh as QuadMesh).size = size
	if _reflected_quad != null and _reflected_quad.mesh is QuadMesh:
		(_reflected_quad.mesh as QuadMesh).size = size

	if _mirror_notifier != null:
		_mirror_notifier.aabb = AABB(
			Vector3(-size.x * 0.5, -size.y * 0.5, -0.05),
			Vector3(size.x, size.y, 0.1)
		)
	_sync_collider_size()
	if _current_resolution_scale <= 0.0:
		_apply_viewport_size()

	if _mirror_viewport != null and not _has_rendered_direct:
		_mirror_viewport.size = _target_viewport_size

	if _mirror_viewport != null:
		var direct_tex: ViewportTexture = _mirror_viewport.get_texture()
		_apply_shader_parameters(_shader_material, direct_tex)
		if not dynamic_resolution:
			_push_direct_uv_rect(FULL_UV_RECT)

	if _reflected_viewport != null and _reflected_shader_material != null:
		var reflected_tex: ViewportTexture = _reflected_viewport.get_texture()
		_apply_shader_parameters(_reflected_shader_material, reflected_tex)
		_reflected_shader_material.set_shader_parameter(&"use_reflected_views", true)
		var slot_textures: Array[Texture2D] = []
		for viewport: SubViewport in _reflected_viewports:
			slot_textures.append(viewport.get_texture() if viewport != null else null)
		_reflected_shader_material.set_shader_parameter(&"reflected_textures", slot_textures)
		_push_reflected_slot_parameters()
		_reflected_shader_material.set_shader_parameter(&"border_thickness", REFLECTED_BORDER_THICKNESS)
		_reflected_shader_material.set_shader_parameter(&"smoothness", 0.35)


func _apply_shader_parameters(material: ShaderMaterial, viewport_texture: ViewportTexture) -> void:
	material.set_shader_parameter(&"border_color", Pigments.COLORS[pigment])
	material.set_shader_parameter(&"color", color)
	material.set_shader_parameter(&"distortion_texture", distortion_texture if use_distortion else null)
	material.set_shader_parameter(&"distortion_strength", distortion if use_distortion else 0.0)
	material.set_shader_parameter(&"mirror_texture_linear", viewport_texture if use_linear_filter else null)
	material.set_shader_parameter(&"mirror_texture_nearest", viewport_texture if not use_linear_filter else null)
	material.set_shader_parameter(&"use_mirror_texture_linear", use_linear_filter)


func _sync_collider_size() -> void:
	var collider_shape := get_node_or_null("Collider/Shape") as CollisionShape3D
	if collider_shape == null:
		return
	var box := collider_shape.shape as BoxShape3D
	if box == null:
		return
	var target_size := Vector3(maxf(size.x, 0.05), maxf(size.y, 0.05), 0.1)
	if not box.size.is_equal_approx(target_size):
		box.size = target_size
