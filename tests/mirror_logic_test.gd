extends GdUnitTestSuite
## Pigment tables, the layer-bit helper, and the mirror reflection transform.


func test_tables() -> void:
	for pigment: Pigments.Pigment in Pigments.Pigment.values():
		assert_bool(Pigments.LAYERS.has(pigment)).is_true()
		# The mirror frame uses this same table as its border color.
		assert_bool(Pigments.COLORS.has(pigment)).is_true()


func test_set_layer_bit() -> void:
	var ray := RayCast3D.new()
	ray.collision_mask = 0
	LayerUtils.set_layer_bit(ray, &"collision_mask", 3, true)
	assert_int(ray.collision_mask).is_equal(0b100)
	LayerUtils.set_layer_bit(ray, &"collision_mask", 1, true)
	assert_int(ray.collision_mask).is_equal(0b101)
	LayerUtils.set_layer_bit(ray, &"collision_mask", 3, false)
	assert_int(ray.collision_mask).is_equal(0b001)
	ray.free()


func test_mirror_transform() -> void:
	# Reflection across the plane z = 5.
	var mirror_transform: Transform3D = Mirror3D.get_mirror_transform(Vector3(0, 0, 1), Vector3(0, 0, 5))
	assert_vector(mirror_transform * Vector3(1, 2, 3)).is_equal(Vector3(1, 2, 7))
	# Reflecting twice is the identity.
	assert_vector(mirror_transform * (mirror_transform * Vector3(1, 2, 3))).is_equal(Vector3(1, 2, 3))
	# Reflection across the plane x = 2.
	mirror_transform = Mirror3D.get_mirror_transform(Vector3(1, 0, 0), Vector3(2, 0, 0))
	assert_vector(mirror_transform * Vector3(5, 1, 1)).is_equal(Vector3(-1, 1, 1))
