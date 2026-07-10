extends Node3D

var is_object_visible_to_player: bool = false
var is_magic_happening: bool = false
var reflection_notifier: VisibleOnScreenNotifier3D

@onready var _mirror: Mirror3D = get_parent()
@onready var original_notifier: VisibleOnScreenNotifier3D = \
	_mirror.object_to_reflect.get_node("VisibleOnScreenNotifier3D")


func _ready() -> void:
	_create_reflection_notifier()


func _physics_process(_delta: float) -> void:
	if not _mirror.player:
		return

	#if _mirror.mirror_type == Mirror3D.MirrorType.VANILLA:
		#return
	
	_update_reflection_notifier_transform()

	if _mirror.object_to_reflect.is_visible_to_mirror \
	and is_object_visible_to_player:

		if not is_magic_happening:
			is_magic_happening = true
			print("✅ Visible reflection!!!")

	elif is_magic_happening:
		is_magic_happening = false
		print("❌ Reflection not visible")


func _create_reflection_notifier() -> void:
	reflection_notifier = VisibleOnScreenNotifier3D.new()
	add_child(reflection_notifier)

	# Copy only the data you need
	reflection_notifier.aabb = original_notifier.aabb

	# make it visible only to player (set to layer 10)
	reflection_notifier.layers = 1 << 9

	_update_reflection_notifier_transform()

	reflection_notifier.screen_entered.connect(
		_on_mirror_notifier_entered)

	reflection_notifier.screen_exited.connect(
		_on_mirror_notifier_exited)


func _update_reflection_notifier_transform() -> void:
	reflection_notifier.global_transform = _reflect_across_mirror(
		original_notifier.global_transform
	)


func _reflect_across_mirror(reflect: Transform3D) -> Transform3D:
	
	var mirror_normal: Vector3 = _mirror.global_basis.z.normalized()
	var mirror_origin: Vector3= _mirror.global_position
	var distance: float = (reflect.origin - mirror_origin).dot(mirror_normal)
	var reflected_position: Vector3 = (reflect.origin - 2.0 * distance * mirror_normal)
	var reflected_basis: Basis = reflect.basis

	reflected_basis.x -= (2.0 * reflected_basis.x.dot(mirror_normal) * mirror_normal)
	reflected_basis.y -= (2.0 * reflected_basis.y.dot(mirror_normal) * mirror_normal)
	reflected_basis.z -= (2.0 * reflected_basis.z.dot(mirror_normal) * mirror_normal)

	return Transform3D(reflected_basis, reflected_position)


func _on_mirror_notifier_entered() -> void:
	#print("✅ REFLECTION PROXY ENTERED")
	is_object_visible_to_player = true


func _on_mirror_notifier_exited() -> void:
	#print("❌ REFLECTION PROXY EXITED")
	is_object_visible_to_player = false
