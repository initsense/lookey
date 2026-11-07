# Based on Mirror3D (https://github.com/Norodix/Mirror3D)
# Copyright (c) 2025 Joyless, Norodix — MIT License (see entities/mirror/LICENSE.md)
@tool
class_name Mirror3D
extends Node3D
## A flat mirror that reflects the room using two internal cameras:
## one for what the player sees directly (Layer 10), and one for what other
## mirrors see when this mirror is reflected inside them (Layer 11).
## It also sets up the border color and visibility layers for reveal and dissolve effects.

enum MirrorType { REVEAL, DISSOLVE }

## Render layer for the mirror surface seen directly by the player.
const DIRECT_MIRROR_LAYER: int = 10
## Render layer for the mirror surface seen only by other mirrors.
const REFLECTED_MIRROR_LAYER: int = 11
## Frame width on a mirror seen inside another mirror. The player's nested reflection
## sits on the shared edge, so this stays thinner than that strip.
const REFLECTED_BORDER_THICKNESS: float = 0.012
## Minimum perpendicular distance (in meters) from an observer to the mirror plane
## required to build a non-degenerate off-axis frustum.
const MIN_PLANE_DISTANCE: float = 0.05
## How many outer mirrors can show this mirror's reflected glass at once, each from its own viewpoint.
const MAX_REFLECTED_VIEWS: int = 3
## Viewpoint stored for an unused reflected view, so far away that no mirror camera ever matches it.
const UNUSED_REFLECTED_OBSERVER: Vector3 = Vector3(1e9, 1e9, 1e9)

## Optional specific object to track for mirror interactions. All PigmentEntity nodes in the scene are tracked automatically.
@export var object_to_reflect: Node3D
## The player character in the scene. If left empty, the mirror finds the player automatically.
@export var player: CharacterBody3D
## Reference to the player's 3D camera.
@onready var player_cam: Camera3D = (
	player.get_node_or_null("Head/Camera3D") as Camera3D if player != null else null
)

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

@export_category("Settings")
## Width and height of the mirror glass in meters.
@export var size: Vector2 = Vector2.ONE:
	set(value):
		size = value
		_config_dirty = true

## Reflection sharpness: how many texture pixels to render per meter of mirror size.
@export var pixels_per_unit: int = 400:
	set(value):
		pixels_per_unit = value
		_config_dirty = true

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

## Distances (in meters) from the player where the mirror lowers its resolution to save performance. Leave empty to disable.
@export var res_decrease_distances: Array[float] = [30.0, 60.0, 90.0]

## How much to divide the mirror resolution at each distance in res_decrease_distances.
@export var res_decrease_factors: Array[float] = [2.0, 4.0, 8.0]

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
var _reflected_pigments: Array[Pigments.Pigment] = [
	Pigments.Pigment.WHITE, Pigments.Pigment.WHITE, Pigments.Pigment.WHITE
]
var _reflected_slot_outers: Array[Mirror3D] = [null, null, null]
var _current_resolution_scale: float = -1.0
var _target_viewport_size: Vector2i = Vector2i(400, 400)
var _reflected_viewport_size: Vector2i = Vector2i(400, 400)
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
		# Scene instances may override res_decrease_distances with tight debug values (e.g. [3, 6, 9]).
		# Clamp any first threshold below 30 m back to the default [30, 60, 90] so mirrors stay sharp.
		if not res_decrease_distances.is_empty() and res_decrease_distances[0] < 30.0:
			res_decrease_distances = [30.0, 60.0, 90.0]
		_resolve_player_and_camera()
		_make_runtime_resources_unique()
	elif _reflected_quad != null:
		_reflected_quad.visible = false
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

	_configure_mirror_camera(_mirror_camera, active_camera.global_position, cull_mask, true)
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
	if Engine.is_editor_hint():
		if not is_equal_approx(_current_resolution_scale, 1.0):
			_current_resolution_scale = 1.0
			_apply_viewport_size()
	else:
		_update_resolution_scale(distance_from_camera)

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

	if not _configure_mirror_camera(_mirror_camera, active_camera.global_position, cull_mask, true):
		_direct_update_allowed = false
	return true


## Configures one reflected view so another mirror can see this glass.
## The viewpoint comes from that outer mirror (observer_position is the outer mirror's camera),
## and the glass uses the additive pigment mix of both mirrors.
## Each outer mirror gets its own slot (see assign_reflected_slots), so several outer mirrors
## can show this glass at once without sharing the wrong viewpoint or pigment.
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
	if _config_dirty:
		_config_dirty = false
		_apply_mirror_config()

	_apply_reflected_slot_border(slot)
	if _reflected_shader_material != null:
		_reflected_shader_material.set_shader_parameter(_reflected_observer_param(slot), observer_position)

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


## Gives every outer mirror that shows this glass its own reflected view slot.
## An outer mirror keeps its slot for as long as it shows this glass, so views never swap.
## Returns the slot for each outer mirror in the same order, or -1 when all slots are taken.
func assign_reflected_slots(outers: Array[Mirror3D]) -> PackedInt32Array:
	for slot: int in MAX_REFLECTED_VIEWS:
		var current: Mirror3D = _reflected_slot_outers[slot]
		if current != null and (not is_instance_valid(current) or not outers.has(current)):
			_reflected_slot_outers[slot] = null

	var slots := PackedInt32Array()
	slots.resize(outers.size())
	slots.fill(-1)
	for i: int in outers.size():
		slots[i] = _reflected_slot_outers.find(outers[i])
	for i: int in outers.size():
		if slots[i] >= 0:
			continue
		var free_slot: int = _reflected_slot_outers.find(null)
		if free_slot < 0 or free_slot >= _reflected_viewports.size():
			continue
		_reflected_slot_outers[free_slot] = outers[i]
		slots[i] = free_slot
	return slots


## Pauses one reflected view slot that no outer mirror uses anymore.
func release_reflected_slot(slot: int) -> void:
	if slot < 0 or slot >= _reflected_viewports.size():
		return
	_reflected_slot_outers[slot] = null
	if _reflected_shader_material != null:
		_reflected_shader_material.set_shader_parameter(_reflected_observer_param(slot), UNUSED_REFLECTED_OBSERVER)
	var viewport: SubViewport = _reflected_viewports[slot]
	if viewport != null and is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Pauses rendering of every reflected view while optionally keeping their last images visible.
func freeze_reflected_view(keep_quad_visible: bool) -> void:
	for slot: int in _reflected_viewports.size():
		release_reflected_slot(slot)
	if _reflected_quad != null and is_instance_valid(_reflected_quad):
		_reflected_quad.visible = keep_quad_visible and _has_rendered_reflected


## Enables or pauses rendering on the direct player-facing viewport.
## Only resizes the SubViewport when it is actively rendering so a paused viewport is never cleared to black.
func set_direct_viewport_active(active: bool, force_ignore_max_fps: bool = false) -> void:
	if _mirror_viewport == null or not is_instance_valid(_mirror_viewport):
		return
	var should_render: bool = active and (_direct_update_allowed or force_ignore_max_fps or not _has_rendered_direct)
	if should_render:
		if _mirror_viewport.size != _target_viewport_size:
			_mirror_viewport.size = _target_viewport_size
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


func _configure_mirror_camera(
	target_camera: Camera3D,
	observer_position: Vector3,
	mask: int,
	allow_nested_layer: bool
) -> bool:
	if target_camera == null or _mirror_quad == null:
		return false

	target_camera.cull_mask = mask
	target_camera.set_cull_mask_value(REFLECTED_MIRROR_LAYER, allow_nested_layer)
	target_camera.set_cull_mask_value(DIRECT_MIRROR_LAYER, false)

	var quad_pos: Vector3 = _mirror_quad.global_position
	var mirror_normal: Vector3 = _mirror_quad.global_basis.z.normalized()
	var signed_distance: float = (observer_position - quad_pos).dot(mirror_normal)
	if absf(signed_distance) <= MIN_PLANE_DISTANCE:
		return false

	var mirror_transform: Transform3D = get_mirror_transform(mirror_normal, quad_pos)
	var reflected_pos: Vector3 = mirror_transform * observer_position
	var midpoint: Vector3 = (reflected_pos + observer_position) * 0.5
	var up_axis: Vector3 = _mirror_quad.global_basis.y.normalized()

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
	var near: float = maxf(proj_distance + cull_near, 0.05)
	var far: float = camera_to_mirror_offset.length() + cull_far
	if far <= near:
		far = near + 0.1

	var local_camera_offset: Vector3 = target_camera.global_basis.inverse() * camera_to_mirror_offset
	var frustum_scale: float = near / proj_distance
	var frustum_offset: Vector2 = Vector2(local_camera_offset.x, local_camera_offset.y) * frustum_scale
	var world_size: Vector2 = get_world_size()
	# Keep-width frustum: size is the near-plane width. Height follows the viewport aspect.
	target_camera.set_frustum(world_size.x * frustum_scale, frustum_offset, near, far)
	return true


func _resolve_player_and_camera() -> void:
	if player != null and not is_instance_valid(player_cam):
		player_cam = player.get_node_or_null("Head/Camera3D") as Camera3D

	if not is_instance_valid(player_cam) and is_inside_tree():
		var group_cam: Node = get_tree().get_first_node_in_group(&"camera_player")
		if group_cam is Camera3D:
			player_cam = group_cam as Camera3D
		elif get_viewport() != null:
			player_cam = get_viewport().get_camera_3d()

	if player == null and is_instance_valid(player_cam):
		var ancestor: Node = player_cam.get_parent()
		while ancestor != null:
			if ancestor is CharacterBody3D:
				player = ancestor as CharacterBody3D
				break
			ancestor = ancestor.get_parent()


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


func _reflected_observer_param(slot: int) -> StringName:
	return StringName("reflected_observer_%d" % slot)


func _apply_reflected_slot_border(slot: int) -> void:
	if _reflected_shader_material == null:
		return
	var param: StringName = &"border_color" if slot == 0 else StringName("reflected_border_color_%d" % slot)
	_reflected_shader_material.set_shader_parameter(param, Pigments.COLORS[_reflected_pigments[slot]])


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
	for slot: int in MAX_REFLECTED_VIEWS:
		_apply_reflected_slot_border(slot)


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
	var scale_factor: float = _current_resolution_scale if _current_resolution_scale > 0.0 else 1.0
	var world_size: Vector2 = get_world_size()
	_target_viewport_size = Vector2i(
		maxi(2, int(world_size.x * pixels_per_unit * scale_factor)),
		maxi(2, int(world_size.y * pixels_per_unit * scale_factor))
	)
	_reflected_viewport_size = _target_viewport_size


func _apply_mirror_config() -> void:
	if _shader_material == null:
		push_warning("Mirror material is missing or not a ShaderMaterial.")
		return

	if _mirror_camera != null:
		_mirror_camera.cull_mask = cull_mask
		_mirror_camera.set_cull_mask_value(REFLECTED_MIRROR_LAYER, true)
		_mirror_camera.set_cull_mask_value(DIRECT_MIRROR_LAYER, false)

	for camera: Camera3D in _reflected_cameras:
		if camera != null:
			camera.keep_aspect = Camera3D.KEEP_WIDTH
			camera.projection = Camera3D.PROJECTION_FRUSTUM

	if _mirror_quad != null and _mirror_quad.mesh is QuadMesh:
		(_mirror_quad.mesh as QuadMesh).size = size
	if _reflected_quad != null and _reflected_quad.mesh is QuadMesh:
		(_reflected_quad.mesh as QuadMesh).size = size

	if _mirror_notifier != null:
		_mirror_notifier.aabb = AABB(
			Vector3(-size.x * 0.5, -size.y * 0.5, -0.05),
			Vector3(size.x, size.y, 0.1)
		)
	_apply_viewport_size()

	if _mirror_viewport != null and not _has_rendered_direct:
		_mirror_viewport.size = _target_viewport_size
	if not _has_rendered_reflected:
		for viewport: SubViewport in _reflected_viewports:
			if viewport != null:
				viewport.size = _reflected_viewport_size

	if _mirror_viewport != null:
		var direct_tex: ViewportTexture = _mirror_viewport.get_texture()
		_apply_shader_parameters(_shader_material, direct_tex)

	if _reflected_viewport != null and _reflected_shader_material != null:
		var reflected_tex: ViewportTexture = _reflected_viewport.get_texture()
		_apply_shader_parameters(_reflected_shader_material, reflected_tex)
		_reflected_shader_material.set_shader_parameter(&"use_reflected_views", true)
		for slot: int in range(1, _reflected_viewports.size()):
			var viewport: SubViewport = _reflected_viewports[slot]
			var slot_tex: ViewportTexture = viewport.get_texture() if viewport != null else null
			_reflected_shader_material.set_shader_parameter(
				StringName("reflected_texture_linear_%d" % slot), slot_tex if use_linear_filter else null
			)
			_reflected_shader_material.set_shader_parameter(
				StringName("reflected_texture_nearest_%d" % slot), slot_tex if not use_linear_filter else null
			)
		for slot: int in MAX_REFLECTED_VIEWS:
			_apply_reflected_slot_border(slot)
			if _reflected_slot_outers[slot] == null:
				_reflected_shader_material.set_shader_parameter(
					_reflected_observer_param(slot), UNUSED_REFLECTED_OBSERVER
				)
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
