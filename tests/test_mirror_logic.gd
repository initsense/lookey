extends SceneTree
## Headless assertions for the pure mirror logic (Pigments tables, bitmask
## helper, reflection transform). Run with:
## <godot> --headless --path . --script res://tests/test_mirror_logic.gd

func _init() -> void:
	_test_tables()
	_test_set_layer_bit()
	_test_mirror_transform()
	print("test_mirror_logic: all assertions passed")
	quit()


func _test_tables() -> void:
	for p: Pigments.Pigment in Pigments.Pigment.values():
		assert(Pigments.LAYERS.has(p), "missing layer for pigment %d" % p)
		assert(Pigments.COLORS.has(p), "missing color for pigment %d" % p)
		assert(Mirror3D.BORDER_COLORS.has(p), "missing border color for pigment %d" % p)


func _test_set_layer_bit() -> void:
	var ray := RayCast3D.new()
	ray.collision_mask = 0
	Pigments.set_layer_bit(ray, &"collision_mask", 3, true)
	assert(ray.collision_mask == 0b100)
	Pigments.set_layer_bit(ray, &"collision_mask", 1, true)
	assert(ray.collision_mask == 0b101)
	Pigments.set_layer_bit(ray, &"collision_mask", 3, false)
	assert(ray.collision_mask == 0b001)
	ray.free()


func _test_mirror_transform() -> void:
	# Reflection across the plane z = 5.
	var t: Transform3D = Mirror3D.get_mirror_transform(Vector3(0, 0, 1), Vector3(0, 0, 5))
	assert((t * Vector3(1, 2, 3)).is_equal_approx(Vector3(1, 2, 7)))
	# Reflecting twice is the identity.
	assert((t * (t * Vector3(1, 2, 3))).is_equal_approx(Vector3(1, 2, 3)))
	# Reflection across the plane x = 2.
	t = Mirror3D.get_mirror_transform(Vector3(1, 0, 0), Vector3(2, 0, 0))
	assert((t * Vector3(5, 1, 1)).is_equal_approx(Vector3(-1, 1, 1)))
