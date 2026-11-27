@tool
class_name MirrorSun
extends DirectionalLight3D
## A copy of the level sun used only by mirror cameras.
## Godot builds directional-light shadows from a centered view, which clips shadows in a mirror
## seen from far away or from the side. This light uses one cascade over the whole shadow map
## so the glass keeps those shadows. Its sun is at least a couple of degrees wide, which is what
## pulls an off-center reflection inside that map. Place it as a child of the real sun, and set
## that sun to render layer 10 so mirror cameras do not draw both.

## How far (in meters) this light bothers to cast shadows. Mirror cameras never look this far;
## the high value just lets each camera use its own far distance.
const SHADOW_MAX_DISTANCE: float = 16000.0
## Keeps the shadow at full strength until the mirror camera's far plane, instead of fading early.
const SHADOW_FADE_START: float = 1.0
## Smallest sun width, in degrees. Godot grows the shadow map by this angle, which is what keeps
## an off-center reflection inside the map. A wider parent sun is kept as-is.
const MIN_ANGULAR_DISTANCE: float = 2.0
## How far past the shadow receivers Godot looks for casters. Matches DirectionalLight3D's default.
const SHADOW_PANCAKE_SIZE: float = 20.0

var _last_warning_state: int = -1


func _ready() -> void:
	_sync_from_parent()
	_refresh_warnings()


func _process(_delta: float) -> void:
	_sync_from_parent()
	_refresh_warnings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		_sync_from_parent()
		_refresh_warnings()


## Warns when this node is not under a sun, or when that sun still shines on layers the mirrors draw.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var sun := get_parent() as DirectionalLight3D
	if sun == null:
		warnings.append("Put MirrorSun as a child of the level's DirectionalLight3D so it can copy that sun.")
		return warnings
	if _parent_overlaps_mirror_cameras(sun):
		warnings.append(
			"The parent sun still shines on a layer mirror cameras draw, so the reflection is lit twice. Leave the parent sun on layer 10 only."
		)
	return warnings


func _sync_from_parent() -> void:
	var sun := get_parent() as DirectionalLight3D
	if sun == null:
		_keep_mirror_shadow_settings()
		return
	if not light_color.is_equal_approx(sun.light_color):
		light_color = sun.light_color
	if not is_equal_approx(light_energy, sun.light_energy):
		light_energy = sun.light_energy
	if not is_equal_approx(light_indirect_energy, sun.light_indirect_energy):
		light_indirect_energy = sun.light_indirect_energy
	if not is_equal_approx(light_volumetric_fog_energy, sun.light_volumetric_fog_energy):
		light_volumetric_fog_energy = sun.light_volumetric_fog_energy
	if not is_equal_approx(light_specular, sun.light_specular):
		light_specular = sun.light_specular
	var angular_distance: float = maxf(sun.light_angular_distance, MIN_ANGULAR_DISTANCE)
	if not is_equal_approx(light_angular_distance, angular_distance):
		light_angular_distance = angular_distance
	if light_negative != sun.light_negative:
		light_negative = sun.light_negative
	if light_cull_mask != sun.light_cull_mask:
		light_cull_mask = sun.light_cull_mask
	if shadow_caster_mask != sun.shadow_caster_mask:
		shadow_caster_mask = sun.shadow_caster_mask
	if shadow_enabled != sun.shadow_enabled:
		shadow_enabled = sun.shadow_enabled
	if not is_equal_approx(shadow_bias, sun.shadow_bias):
		shadow_bias = sun.shadow_bias
	if not is_equal_approx(shadow_normal_bias, sun.shadow_normal_bias):
		shadow_normal_bias = sun.shadow_normal_bias
	if not is_equal_approx(shadow_transmittance_bias, sun.shadow_transmittance_bias):
		shadow_transmittance_bias = sun.shadow_transmittance_bias
	if not is_equal_approx(shadow_blur, sun.shadow_blur):
		shadow_blur = sun.shadow_blur
	if not is_equal_approx(shadow_opacity, sun.shadow_opacity):
		shadow_opacity = sun.shadow_opacity
	if shadow_reverse_cull_face != sun.shadow_reverse_cull_face:
		shadow_reverse_cull_face = sun.shadow_reverse_cull_face
	if sky_mode != sun.sky_mode:
		sky_mode = sun.sky_mode
	_keep_mirror_shadow_settings()


func _keep_mirror_shadow_settings() -> void:
	var mirror_layers: int = 1 << (Mirror3D.MIRROR_SUN_LAYER - 1)
	if layers != mirror_layers:
		layers = mirror_layers
	if directional_shadow_mode != SHADOW_ORTHOGONAL:
		directional_shadow_mode = SHADOW_ORTHOGONAL
	if not is_equal_approx(directional_shadow_max_distance, SHADOW_MAX_DISTANCE):
		directional_shadow_max_distance = SHADOW_MAX_DISTANCE
	if not is_equal_approx(directional_shadow_fade_start, SHADOW_FADE_START):
		directional_shadow_fade_start = SHADOW_FADE_START
	if not is_equal_approx(directional_shadow_pancake_size, SHADOW_PANCAKE_SIZE):
		directional_shadow_pancake_size = SHADOW_PANCAKE_SIZE


## Returns true when the parent sun shines on a layer that mirror cameras also draw.
func _parent_overlaps_mirror_cameras(sun: DirectionalLight3D) -> bool:
	var mirror_layers: int = (
		(1 << (Pigments.WORLD_GEOMETRY_LAYER - 1))
		| (1 << (Pigments.PLAYER_LAYER - 1))
		| Pigments.MANIFEST_PIGMENT_MASK
		| Pigments.HIDDEN_PIGMENT_MASK
		| (1 << (Mirror3D.REFLECTED_MIRROR_LAYER - 1))
		| (1 << (Mirror3D.MIRROR_SUN_LAYER - 1))
	)
	return (sun.layers & mirror_layers) != 0


func _refresh_warnings() -> void:
	if not is_inside_tree():
		return
	var state := _warning_state()
	if state == _last_warning_state:
		return
	_last_warning_state = state
	update_configuration_warnings()


func _warning_state() -> int:
	var sun := get_parent() as DirectionalLight3D
	if sun == null:
		return 1
	if _parent_overlaps_mirror_cameras(sun):
		return 2
	return 0

