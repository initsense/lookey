extends GdUnitTestSuite
## Pigment tables, mirror cull masks, link/affect state, occlusion, and
## dissolve-exit transitions for reveal-mirror and dissolve-mirror mechanics.


const OBJECT_SCENE := preload("res://prefabs/object.tscn")
const MIRROR_SCENE := preload("res://entities/mirror/mirror.tscn")
const PLAYER_SCENE := preload("res://entities/player/player.tscn")


func test_tables() -> void:
	for pigment: Pigments.Pigment in Pigments.Pigment.values():
		assert_bool(Pigments.LAYERS.has(pigment)).is_true()
		assert_bool(Pigments.COLORS.has(pigment)).is_true()


func test_entity_layers() -> void:
	assert_int(Pigments.LAYERS[Pigments.Pigment.WHITE]).is_equal(9)
	for pigment: Pigments.Pigment in Pigments.Pigment.values():
		var manifest: int = Pigments.get_entity_layer(pigment, false)
		var hidden: int = Pigments.get_entity_layer(pigment, true)
		assert_int(manifest).is_greater_equal(3)
		assert_int(manifest).is_less_equal(9)
		assert_int(hidden).is_equal(manifest + Pigments.INVISIBLE_SHIFT)
		assert_int(hidden).is_greater_equal(13)
		assert_int(hidden).is_less_equal(19)
		assert_int(manifest).is_not_equal(Pigments.WORLD_GEOMETRY_LAYER)
		assert_int(manifest).is_not_equal(Pigments.PLAYER_LAYER)
		assert_int(manifest).is_not_equal(Pigments.ENTITY_COLLIDER_LAYER)
		assert_int(hidden).is_not_equal(Pigments.WORLD_GEOMETRY_LAYER)
		assert_int(hidden).is_not_equal(Pigments.PLAYER_LAYER)
		assert_int(hidden).is_not_equal(Pigments.ENTITY_COLLIDER_LAYER)


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
	var mirror_transform: Transform3D = Mirror3D.get_mirror_transform(Vector3(0, 0, 1), Vector3(0, 0, 5))
	assert_vector(mirror_transform * Vector3(1, 2, 3)).is_equal(Vector3(1, 2, 7))
	assert_vector(mirror_transform * (mirror_transform * Vector3(1, 2, 3))).is_equal(Vector3(1, 2, 3))
	mirror_transform = Mirror3D.get_mirror_transform(Vector3(1, 0, 0), Vector3(2, 0, 0))
	assert_vector(mirror_transform * Vector3(5, 1, 1)).is_equal(Vector3(-1, 1, 1))


func test_pigment_compatibility() -> void:
	assert_bool(Pigments.is_compatible(Pigments.Pigment.YELLOW, Pigments.Pigment.YELLOW)).is_true()
	assert_bool(Pigments.is_compatible(Pigments.Pigment.YELLOW, Pigments.Pigment.WHITE)).is_true()
	assert_bool(Pigments.is_compatible(Pigments.Pigment.YELLOW, Pigments.Pigment.BLUE)).is_false()
	assert_bool(Pigments.is_compatible(Pigments.Pigment.WHITE, Pigments.Pigment.RED)).is_true()
	assert_bool(Pigments.is_compatible(Pigments.Pigment.WHITE, Pigments.Pigment.WHITE)).is_true()
	assert_bool(Pigments.is_compatible(Pigments.Pigment.BLUE, Pigments.Pigment.WHITE)).is_true()
	for pigment: Pigments.Pigment in Pigments.Pigment.values():
		assert_bool(Pigments.is_compatible(Pigments.Pigment.WHITE, pigment)).is_true()
		assert_bool(Pigments.is_compatible(pigment, Pigments.Pigment.WHITE)).is_true()


func test_pigment_mixing() -> void:
	# Primary + Primary -> Secondary (commutative)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.RED, Pigments.Pigment.YELLOW)).is_equal(Pigments.Pigment.ORANGE)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.YELLOW, Pigments.Pigment.RED)).is_equal(Pigments.Pigment.ORANGE)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.YELLOW, Pigments.Pigment.BLUE)).is_equal(Pigments.Pigment.GREEN)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.BLUE, Pigments.Pigment.YELLOW)).is_equal(Pigments.Pigment.GREEN)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.RED, Pigments.Pigment.BLUE)).is_equal(Pigments.Pigment.VIOLET)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.BLUE, Pigments.Pigment.RED)).is_equal(Pigments.Pigment.VIOLET)

	# Same + Same -> Same
	for pigment: Pigments.Pigment in Pigments.Pigment.values():
		assert_int(Pigments.mix_pigments(pigment, pigment)).is_equal(pigment)

	# Secondary + constituent Primary -> same Secondary
	assert_int(Pigments.mix_pigments(Pigments.Pigment.GREEN, Pigments.Pigment.YELLOW)).is_equal(Pigments.Pigment.GREEN)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.GREEN, Pigments.Pigment.BLUE)).is_equal(Pigments.Pigment.GREEN)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.ORANGE, Pigments.Pigment.RED)).is_equal(Pigments.Pigment.ORANGE)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.VIOLET, Pigments.Pigment.BLUE)).is_equal(Pigments.Pigment.VIOLET)

	# Complementary / 3-primary combinations -> WHITE
	assert_int(Pigments.mix_pigments(Pigments.Pigment.RED, Pigments.Pigment.GREEN)).is_equal(Pigments.Pigment.WHITE)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.YELLOW, Pigments.Pigment.VIOLET)).is_equal(Pigments.Pigment.WHITE)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.BLUE, Pigments.Pigment.ORANGE)).is_equal(Pigments.Pigment.WHITE)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.ORANGE, Pigments.Pigment.GREEN)).is_equal(Pigments.Pigment.WHITE)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.WHITE, Pigments.Pigment.YELLOW)).is_equal(Pigments.Pigment.WHITE)


func test_reveal_mirror_cull_mask() -> void:
	var yellow_reveal: int = Pigments.compute_mirror_cull_mask(Pigments.Pigment.YELLOW, true)
	assert_bool(_has_layer(yellow_reveal, 1)).is_true()
	assert_bool(_has_layer(yellow_reveal, 2)).is_true()
	for layer: int in range(3, 10):
		assert_bool(_has_layer(yellow_reveal, layer)).is_true()
	assert_bool(_has_layer(yellow_reveal, 16)).is_true()
	assert_bool(_has_layer(yellow_reveal, 19)).is_true()
	for layer: int in [13, 14, 15, 17, 18]:
		assert_bool(_has_layer(yellow_reveal, layer)).is_false()

	var white_reveal: int = Pigments.compute_mirror_cull_mask(Pigments.Pigment.WHITE, true)
	for layer: int in range(13, 20):
		assert_bool(_has_layer(white_reveal, layer)).is_true()


func test_dissolve_mirror_cull_mask() -> void:
	var blue_dissolve: int = Pigments.compute_mirror_cull_mask(Pigments.Pigment.BLUE, false)
	assert_bool(_has_layer(blue_dissolve, 1)).is_true()
	assert_bool(_has_layer(blue_dissolve, 2)).is_true()
	assert_bool(_has_layer(blue_dissolve, 4)).is_false()
	assert_bool(_has_layer(blue_dissolve, 9)).is_false()
	for layer: int in [3, 5, 6, 7, 8]:
		assert_bool(_has_layer(blue_dissolve, layer)).is_true()
	for layer: int in range(13, 20):
		assert_bool(_has_layer(blue_dissolve, layer)).is_false()

	var white_dissolve: int = Pigments.compute_mirror_cull_mask(Pigments.Pigment.WHITE, false)
	assert_bool(_has_layer(white_dissolve, 1)).is_true()
	assert_bool(_has_layer(white_dissolve, 2)).is_true()
	for layer: int in range(3, 10):
		assert_bool(_has_layer(white_dissolve, layer)).is_false()


func test_eligibility_rules() -> void:
	assert_bool(
		Pigments.is_entity_eligible(
			Pigments.Pigment.YELLOW, true, Pigments.Pigment.YELLOW, true
		)
	).is_true()
	assert_bool(
		Pigments.is_entity_eligible(
			Pigments.Pigment.YELLOW, true, Pigments.Pigment.YELLOW, false
		)
	).is_false()
	assert_bool(
		Pigments.is_entity_eligible(
			Pigments.Pigment.YELLOW, false, Pigments.Pigment.YELLOW, false
		)
	).is_true()
	assert_bool(
		Pigments.is_entity_eligible(
			Pigments.Pigment.YELLOW, false, Pigments.Pigment.YELLOW, true
		)
	).is_false()
	assert_bool(
		Pigments.is_entity_eligible(
			Pigments.Pigment.YELLOW, true, Pigments.Pigment.BLUE, true
		)
	).is_false()


func test_hidden_entity_reveal_link_and_collider() -> void:
	var root := Node3D.new()
	add_child(root)
	var entity: PigmentEntity = _spawn_object(root, Pigments.Pigment.YELLOW, true, Vector3.ZERO)
	var mirror_a := Mirror3D.new()
	mirror_a.pigment = Pigments.Pigment.YELLOW
	mirror_a.mirror_type = Mirror3D.MirrorType.REVEAL
	var mirror_b := Mirror3D.new()
	mirror_b.pigment = Pigments.Pigment.BLUE
	mirror_b.mirror_type = Mirror3D.MirrorType.REVEAL
	var dissolve := Mirror3D.new()
	dissolve.pigment = Pigments.Pigment.YELLOW
	dissolve.mirror_type = Mirror3D.MirrorType.DISSOLVE

	await get_tree().physics_frame

	assert_bool(entity.is_hidden_entity()).is_true()
	assert_bool(entity.is_linked()).is_false()
	assert_bool(entity.is_affected()).is_false()
	assert_bool(entity.is_collidable()).is_false()
	assert_int(entity.mesh.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.YELLOW, true) - 1))

	entity.set_mirror_link_state(mirror_b, true, false)
	assert_bool(entity.is_linked()).is_true()
	assert_bool(entity.is_affected()).is_false()
	assert_bool(entity.is_collidable()).is_false()

	entity.set_mirror_link_state(mirror_b, false, false)
	entity.set_mirror_link_state(dissolve, true, false)
	assert_bool(entity.is_linked()).is_true()
	assert_bool(entity.is_affected()).is_false()
	assert_bool(entity.is_collidable()).is_false()

	entity.set_mirror_link_state(dissolve, false, false)
	entity.set_mirror_link_state(mirror_a, true, true)
	assert_bool(entity.is_linked()).is_true()
	assert_bool(entity.is_affected()).is_true()
	assert_bool(entity.is_collidable()).is_true()
	assert_int(entity.mesh.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.YELLOW, true) - 1))

	entity.set_mirror_link_state(mirror_a, false, false)
	assert_bool(entity.is_collidable()).is_false()

	root.queue_free()
	mirror_a.free()
	mirror_b.free()
	dissolve.free()


func test_manifest_entity_dissolve_link_and_collider() -> void:
	var root := Node3D.new()
	add_child(root)
	var entity: PigmentEntity = _spawn_object(root, Pigments.Pigment.BLUE, false, Vector3.ZERO)
	var dissolve := Mirror3D.new()
	dissolve.pigment = Pigments.Pigment.BLUE
	dissolve.mirror_type = Mirror3D.MirrorType.DISSOLVE
	var wrong_dissolve := Mirror3D.new()
	wrong_dissolve.pigment = Pigments.Pigment.RED
	wrong_dissolve.mirror_type = Mirror3D.MirrorType.DISSOLVE
	var reveal := Mirror3D.new()
	reveal.pigment = Pigments.Pigment.BLUE
	reveal.mirror_type = Mirror3D.MirrorType.REVEAL

	await get_tree().physics_frame

	assert_bool(entity.is_hidden_entity()).is_false()
	assert_bool(entity.is_collidable()).is_true()
	assert_int(entity.mesh.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.BLUE, false) - 1))

	entity.set_mirror_link_state(wrong_dissolve, true, false)
	assert_bool(entity.is_linked()).is_true()
	assert_bool(entity.is_affected()).is_false()
	assert_bool(entity.is_collidable()).is_true()

	entity.set_mirror_link_state(wrong_dissolve, false, false)
	entity.set_mirror_link_state(reveal, true, false)
	assert_bool(entity.is_collidable()).is_true()

	entity.set_mirror_link_state(reveal, false, false)
	entity.set_mirror_link_state(dissolve, true, true)
	assert_bool(entity.is_affected()).is_true()
	assert_bool(entity.is_collidable()).is_false()
	assert_int(entity.mesh.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.BLUE, false) - 1))
	assert_bool(
		(entity.static_body.collision_layer & (1 << (Pigments.get_entity_layer(Pigments.Pigment.BLUE, false) - 1))) != 0
	).is_true()

	root.queue_free()
	dissolve.free()
	wrong_dissolve.free()
	reveal.free()


func test_multi_mirror_aggregation() -> void:
	var root := Node3D.new()
	add_child(root)
	var entity: PigmentEntity = _spawn_object(root, Pigments.Pigment.YELLOW, true, Vector3.ZERO)
	var mirror_a := Mirror3D.new()
	var mirror_b := Mirror3D.new()
	await get_tree().physics_frame

	entity.set_mirror_link_state(mirror_a, true, true)
	entity.set_mirror_link_state(mirror_b, true, true)
	assert_bool(entity.is_affected()).is_true()
	assert_bool(entity.is_linked()).is_true()

	entity.set_mirror_link_state(mirror_a, true, false)
	assert_bool(entity.is_affected()).is_true()
	assert_bool(entity.is_linked()).is_true()

	entity.set_mirror_link_state(mirror_b, false, false)
	assert_bool(entity.is_affected()).is_false()
	assert_bool(entity.is_linked()).is_true()

	entity.set_mirror_link_state(mirror_a, false, false)
	assert_bool(entity.is_linked()).is_false()

	root.queue_free()
	mirror_a.free()
	mirror_b.free()


func test_white_hidden_entity_layers() -> void:
	var root := Node3D.new()
	add_child(root)
	var entity: PigmentEntity = _spawn_object(root, Pigments.Pigment.WHITE, true, Vector3.ZERO)
	await get_tree().physics_frame
	assert_int(entity.mesh.layers).is_equal(1 << 18)
	assert_bool(
		(entity.static_body.collision_layer & (1 << 18)) != 0
	).is_true()
	root.queue_free()


func test_dissolve_exit_holds_while_overlapping_non_player_entity() -> void:
	var root := Node3D.new()
	add_child(root)
	var entity_a: PigmentEntity = _spawn_object(root, Pigments.Pigment.BLUE, false, Vector3(0, 1, 0))
	var entity_b: PigmentEntity = _spawn_object(root, Pigments.Pigment.RED, false, Vector3(0, 1, 0))
	var dissolve := Mirror3D.new()
	await get_tree().physics_frame
	await get_tree().physics_frame

	entity_a.set_mirror_link_state(dissolve, true, true)
	assert_bool(entity_a.is_collidable()).is_false()

	entity_a.set_mirror_link_state(dissolve, false, false)
	await get_tree().physics_frame
	assert_bool(entity_a.is_collidable()).is_false()

	entity_b.global_position = Vector3(5, 1, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(entity_a.is_collidable()).is_true()

	root.queue_free()
	dissolve.free()


func test_dissolve_exit_pushes_overlapping_player() -> void:
	var root := Node3D.new()
	add_child(root)
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 0, 0)

	var entity: PigmentEntity = _spawn_object(root, Pigments.Pigment.BLUE, false, Vector3(0, 1, 0))
	var dissolve := Mirror3D.new()
	await get_tree().physics_frame
	await get_tree().physics_frame

	entity.set_mirror_link_state(dissolve, true, true)
	player.global_position = Vector3(0, 0.5, 0)
	var entity_origin: Vector3 = entity.global_position

	entity.set_mirror_link_state(dissolve, false, false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_bool(entity.is_collidable()).is_true()
	assert_vector(entity.global_position).is_equal(entity_origin)
	assert_bool(player.global_position.distance_to(Vector3(0, 0.5, 0)) > 0.01).is_true()

	root.queue_free()
	dissolve.free()


func test_render_dependent_occlusion_in_dissolve_mirror() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var hidden: PigmentEntity = root.get_node("Hidden")
	var front: PigmentEntity = root.get_node("Front")
	var interaction: Node = mirror.get_node("Interaction")

	# Offset entities off the camera->mirror axis so the occluder sits on
	# Segment 1 (reflected-world) without also blocking Segment 2 (real-world).
	hidden.global_position = Vector3(1.2, 1.2, 0.4)
	front.global_position = Vector3(1.2, 1.2, 1.8)
	front.scale = Vector3(1.5, 1.5, 0.6)

	mirror.pigment = Pigments.Pigment.BLUE
	mirror.mirror_type = Mirror3D.MirrorType.DISSOLVE
	mirror.size = Vector2(5, 4)
	mirror._apply_pigment()
	front.pigment = Pigments.Pigment.BLUE
	front.is_invisible = false
	hidden.pigment = Pigments.Pigment.BLUE
	hidden.is_invisible = true
	front._apply_layers_and_material()
	hidden._apply_layers_and_material()
	front._update_real_world_collider()
	hidden._update_real_world_collider()
	interaction._refresh_tracked_entities()
	interaction.is_mirror_visible = true

	await _wait_for_link_eval(interaction)

	# Blue front object is dissolved in the blue dissolve-mirror, so it must not
	# occlude the blue hidden object behind it.
	assert_bool(hidden.is_linked()).is_true()

	front.pigment = Pigments.Pigment.RED
	front._apply_layers_and_material()
	front._update_real_world_collider()
	await _wait_for_link_eval(interaction)
	assert_bool(hidden.is_linked()).is_false()

	root.queue_free()


func test_hidden_entity_does_not_occlude_real_world_segment() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var hidden: PigmentEntity = root.get_node("Hidden")
	var front: PigmentEntity = root.get_node("Front")
	var interaction: Node = mirror.get_node("Interaction")

	mirror.pigment = Pigments.Pigment.YELLOW
	mirror.mirror_type = Mirror3D.MirrorType.REVEAL
	mirror._apply_pigment()
	hidden.pigment = Pigments.Pigment.YELLOW
	hidden.is_invisible = true
	hidden.global_position = Vector3(0, 1.2, 0.5)
	front.static_body.collision_layer = 0
	front.visible = false
	hidden._apply_layers_and_material()
	hidden._update_real_world_collider()

	# Place a second hidden entity between the camera and the mirror on the
	# real-world segment. It must not block linking of the target hidden entity.
	var blocker: PigmentEntity = _spawn_object(
		root,
		Pigments.Pigment.YELLOW,
		true,
		Vector3(0, 1.2, 1.0)
	)
	blocker.scale = Vector3(2.0, 2.0, 0.5)
	interaction._refresh_tracked_entities()
	interaction.is_mirror_visible = true

	await get_tree().physics_frame
	await _wait_for_link_eval(interaction)
	assert_bool(hidden.is_linked()).is_true()
	assert_that(blocker).is_not_null()

	root.queue_free()


func test_mirror_dual_viewport_and_layer_isolation() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	MirrorManager.refresh_now()

	assert_int(mirror._mirror_quad.layers).is_equal(1 << (Mirror3D.DIRECT_MIRROR_LAYER - 1))
	assert_that(mirror._reflected_quad).is_not_null()
	assert_int(mirror._reflected_quad.layers).is_equal(1 << (Mirror3D.REFLECTED_MIRROR_LAYER - 1))
	assert_that(mirror._reflected_camera).is_not_null()
	assert_int(mirror._reflected_camera.keep_aspect).is_equal(Camera3D.KEEP_WIDTH)
	assert_bool(_has_layer(mirror._mirror_camera.cull_mask, Mirror3D.REFLECTED_MIRROR_LAYER)).is_true()
	assert_bool(_has_layer(mirror._mirror_camera.cull_mask, Mirror3D.DIRECT_MIRROR_LAYER)).is_false()

	root.queue_free()


func test_nested_reveal_mirror_cull_mask_and_camera() -> void:
	var root := await _build_nested_mirror_scene(
		Pigments.Pigment.YELLOW,
		Mirror3D.MirrorType.REVEAL,
		Pigments.Pigment.BLUE,
		Mirror3D.MirrorType.REVEAL
	)
	var inner_mirror: Mirror3D = root.get_node("InnerMirror")
	var outer_mirror: Mirror3D = root.get_node("OuterMirror")
	MirrorManager.refresh_now()

	var yellow_hidden_layer: int = Pigments.get_entity_layer(Pigments.Pigment.YELLOW, true)
	var blue_hidden_layer: int = Pigments.get_entity_layer(Pigments.Pigment.BLUE, true)
	var green_hidden_layer: int = Pigments.get_entity_layer(Pigments.Pigment.GREEN, true)

	# Directly, the yellow inner mirror reveals yellow hidden entities.
	# Reflected inside the blue outer mirror, Yellow + Blue mixes to Green:
	# its reflected glass reveals green hidden entities (not yellow or blue) and has a green border.
	assert_bool(_has_layer(inner_mirror._mirror_camera.cull_mask, yellow_hidden_layer)).is_true()
	assert_bool(_has_layer(inner_mirror._reflected_camera.cull_mask, yellow_hidden_layer)).is_false()
	assert_bool(_has_layer(inner_mirror._reflected_camera.cull_mask, blue_hidden_layer)).is_false()
	assert_bool(_has_layer(inner_mirror._reflected_camera.cull_mask, green_hidden_layer)).is_true()
	assert_that(
		inner_mirror._reflected_shader_material.get_shader_parameter(&"border_color")
	).is_equal(Pigments.COLORS[Pigments.Pigment.GREEN])

	var expected_pos: Vector3 = inner_mirror.reflect_point(outer_mirror._mirror_camera.global_position)
	assert_bool(inner_mirror._reflected_camera.global_position.distance_to(expected_pos) < 0.01).is_true()

	# Red + Yellow mixes to Orange.
	inner_mirror.pigment = Pigments.Pigment.RED
	outer_mirror.pigment = Pigments.Pigment.YELLOW
	inner_mirror._apply_pigment()
	outer_mirror._apply_pigment()
	MirrorManager.refresh_now()

	var orange_hidden_layer: int = Pigments.get_entity_layer(Pigments.Pigment.ORANGE, true)
	assert_bool(_has_layer(inner_mirror._reflected_camera.cull_mask, orange_hidden_layer)).is_true()
	assert_bool(_has_layer(inner_mirror._reflected_camera.cull_mask, yellow_hidden_layer)).is_false()
	assert_that(
		inner_mirror._reflected_shader_material.get_shader_parameter(&"border_color")
	).is_equal(Pigments.COLORS[Pigments.Pigment.ORANGE])

	root.queue_free()


func test_nested_dissolve_mirror_cull_mask_and_camera() -> void:
	var root := await _build_nested_mirror_scene(
		Pigments.Pigment.RED,
		Mirror3D.MirrorType.DISSOLVE,
		Pigments.Pigment.BLUE,
		Mirror3D.MirrorType.REVEAL
	)
	var inner_mirror: Mirror3D = root.get_node("InnerMirror")
	var outer_mirror: Mirror3D = root.get_node("OuterMirror")
	MirrorManager.refresh_now()

	var red_manifest_layer: int = Pigments.get_entity_layer(Pigments.Pigment.RED, false)
	var violet_manifest_layer: int = Pigments.get_entity_layer(Pigments.Pigment.VIOLET, false)

	# Directly, the red dissolve mirror hides red manifest entities.
	# Reflected inside the blue reveal mirror, Red + Blue mixes to Violet while keeping the inner mirror's DISSOLVE type.
	assert_bool(_has_layer(inner_mirror._mirror_camera.cull_mask, red_manifest_layer)).is_false()
	assert_bool(_has_layer(inner_mirror._reflected_camera.cull_mask, red_manifest_layer)).is_true()
	assert_bool(_has_layer(inner_mirror._reflected_camera.cull_mask, violet_manifest_layer)).is_false()
	assert_that(
		inner_mirror._reflected_shader_material.get_shader_parameter(&"border_color")
	).is_equal(Pigments.COLORS[Pigments.Pigment.VIOLET])

	# When the inner mirror is a Blue Reveal mirror reflected inside a Red Dissolve mirror,
	# the nested mirror keeps the inner mirror's REVEAL type (Violet Reveal) so manifest entities stay visible.
	inner_mirror.pigment = Pigments.Pigment.BLUE
	inner_mirror.mirror_type = Mirror3D.MirrorType.REVEAL
	outer_mirror.pigment = Pigments.Pigment.RED
	outer_mirror.mirror_type = Mirror3D.MirrorType.DISSOLVE
	inner_mirror._apply_pigment()
	outer_mirror._apply_pigment()
	MirrorManager.refresh_now()

	var violet_hidden_layer: int = Pigments.get_entity_layer(Pigments.Pigment.VIOLET, true)
	assert_bool(_has_layer(inner_mirror._reflected_camera.cull_mask, violet_manifest_layer)).is_true()
	assert_bool(_has_layer(inner_mirror._reflected_camera.cull_mask, violet_hidden_layer)).is_true()

	root.queue_free()


func test_nested_reveal_linking_and_collider_across_two_mirrors() -> void:
	var root := await _build_nested_mirror_scene(
		Pigments.Pigment.YELLOW,
		Mirror3D.MirrorType.REVEAL,
		Pigments.Pigment.BLUE,
		Mirror3D.MirrorType.REVEAL
	)
	var inner_mirror: Mirror3D = root.get_node("InnerMirror")
	var outer_mirror: Mirror3D = root.get_node("OuterMirror")
	var inner_interaction: Node = inner_mirror.get_node("Interaction")
	var outer_interaction: Node = outer_mirror.get_node("Interaction")

	# Position the hidden object so 1-bounce misses OuterMirror,
	# and only the 2-bounce path (Object -> InnerMirror -> OuterMirror -> Player) reaches the camera.
	var hidden_obj: PigmentEntity = _spawn_object(
		root,
		Pigments.Pigment.YELLOW,
		true,
		Vector3(3.0, 1.5, 2.0)
	)
	inner_interaction._refresh_tracked_entities()
	outer_interaction._refresh_tracked_entities()
	inner_interaction.is_mirror_visible = false
	outer_interaction.is_mirror_visible = true
	MirrorManager.refresh_now()

	await _wait_for_link_eval(outer_interaction)

	# Yellow InnerMirror + Blue OuterMirror mixes to Green Reveal:
	# A yellow hidden object on the 2-bounce path is linked, but NOT affected.
	assert_bool(hidden_obj.is_linked()).is_true()
	assert_bool(hidden_obj.is_affected()).is_false()
	assert_bool(hidden_obj.is_collidable()).is_false()

	# Change the hidden object to Green: now it matches the mixed Green pigment of the 2-bounce chain
	# and becomes affected and collidable in the real-world.
	hidden_obj.pigment = Pigments.Pigment.GREEN
	hidden_obj._apply_layers_and_material()
	hidden_obj._update_real_world_collider()
	MirrorManager.refresh_now()

	await _wait_for_link_eval(outer_interaction)

	assert_bool(hidden_obj.is_linked()).is_true()
	assert_bool(hidden_obj.is_affected()).is_true()
	assert_bool(hidden_obj.is_collidable()).is_true()

	root.queue_free()


func test_nested_dissolve_linking_and_collider_across_two_mirrors() -> void:
	var root := await _build_nested_mirror_scene(
		Pigments.Pigment.RED,
		Mirror3D.MirrorType.DISSOLVE,
		Pigments.Pigment.BLUE,
		Mirror3D.MirrorType.REVEAL
	)
	var inner_mirror: Mirror3D = root.get_node("InnerMirror")
	var outer_mirror: Mirror3D = root.get_node("OuterMirror")
	var inner_interaction: Node = inner_mirror.get_node("Interaction")
	var outer_interaction: Node = outer_mirror.get_node("Interaction")

	var manifest_obj: PigmentEntity = _spawn_object(
		root,
		Pigments.Pigment.RED,
		false,
		Vector3(3.0, 1.5, 2.0)
	)
	inner_interaction._refresh_tracked_entities()
	outer_interaction._refresh_tracked_entities()
	inner_interaction.is_mirror_visible = false
	outer_interaction.is_mirror_visible = true
	MirrorManager.refresh_now()

	await _wait_for_link_eval(outer_interaction)

	# Red Dissolve InnerMirror + Blue Reveal OuterMirror mixes to Violet Dissolve:
	# A red manifest object on the 2-bounce path is linked, but remains solid because the mixed pigment is Violet.
	assert_bool(manifest_obj.is_linked()).is_true()
	assert_bool(manifest_obj.is_affected()).is_false()
	assert_bool(manifest_obj.is_collidable()).is_true()

	# Change the manifest object to Violet: now the mixed Violet Dissolve chain dissolves it and disables its collider.
	manifest_obj.pigment = Pigments.Pigment.VIOLET
	manifest_obj._apply_layers_and_material()
	manifest_obj._update_real_world_collider()
	MirrorManager.refresh_now()

	await _wait_for_link_eval(outer_interaction)

	assert_bool(manifest_obj.is_linked()).is_true()
	assert_bool(manifest_obj.is_affected()).is_true()
	assert_bool(manifest_obj.is_collidable()).is_false()

	root.queue_free()


func _has_layer(mask: int, layer: int) -> bool:
	return (mask & (1 << (layer - 1))) != 0


func _spawn_object(
	parent: Node,
	pigment: Pigments.Pigment,
	is_hidden: bool,
	position: Vector3
) -> PigmentEntity:
	var entity: PigmentEntity = OBJECT_SCENE.instantiate()
	entity.pigment = pigment
	entity.is_invisible = is_hidden
	parent.add_child(entity)
	entity.global_position = position
	return entity


func _build_link_scene() -> Node3D:
	var root := Node3D.new()
	add_child(root)

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.name = "Player"
	player.global_position = Vector3(0, 0, -2)
	player.rotation = Vector3.ZERO

	var front: PigmentEntity = _spawn_object(root, Pigments.Pigment.BLUE, false, Vector3(0, 1, 1.5))
	front.name = "Front"
	var hidden: PigmentEntity = _spawn_object(root, Pigments.Pigment.BLUE, true, Vector3(0, 1, 0.5))
	hidden.name = "Hidden"

	var mirror: Mirror3D = MIRROR_SCENE.instantiate()
	mirror.player = player
	mirror.object_to_reflect = hidden
	root.add_child(mirror)
	mirror.name = "Mirror"
	mirror.always_active = true
	mirror.size = Vector2(4, 3)
	mirror.global_position = Vector3(0, 1.5, 3)
	# Face the player (QuadMesh normal is +Z in local space).
	mirror.rotation = Vector3(0.0, PI, 0.0)
	mirror.player_cam = player.get_node("Head/Camera3D") as Camera3D
	# Player Head is pre-rotated 180 deg, so the camera looks toward +Z / the mirror.
	mirror.player_cam.make_current()
	mirror._apply_pigment()

	var interaction: Node = mirror.get_node("Interaction")
	interaction._refresh_tracked_entities()
	interaction.is_mirror_visible = true

	await get_tree().physics_frame
	await get_tree().physics_frame
	return root


func _build_nested_mirror_scene(
	inner_pigment: Pigments.Pigment,
	inner_type: Mirror3D.MirrorType,
	outer_pigment: Pigments.Pigment,
	outer_type: Mirror3D.MirrorType
) -> Node3D:
	var root := Node3D.new()
	add_child(root)

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.name = "Player"
	player.global_position = Vector3(0, 0, -2)
	player.rotation = Vector3.ZERO

	var player_cam: Camera3D = player.get_node("Head/Camera3D") as Camera3D
	player_cam.make_current()

	var inner_mirror: Mirror3D = MIRROR_SCENE.instantiate()
	inner_mirror.name = "InnerMirror"
	inner_mirror.player = player
	inner_mirror.pigment = inner_pigment
	inner_mirror.mirror_type = inner_type
	inner_mirror.always_active = true
	inner_mirror.size = Vector2(1.5, 3.0)
	root.add_child(inner_mirror)
	inner_mirror.global_position = Vector3(2.0, 1.5, -1.0)
	inner_mirror.rotation = Vector3.ZERO
	inner_mirror.player_cam = player_cam
	inner_mirror._apply_pigment()

	var outer_mirror: Mirror3D = MIRROR_SCENE.instantiate()
	outer_mirror.name = "OuterMirror"
	outer_mirror.player = player
	outer_mirror.pigment = outer_pigment
	outer_mirror.mirror_type = outer_type
	outer_mirror.always_active = true
	outer_mirror.size = Vector2(1.5, 3.0)
	root.add_child(outer_mirror)
	outer_mirror.global_position = Vector3(1.0, 1.5, 3.0)
	outer_mirror.rotation = Vector3(0.0, PI, 0.0)
	outer_mirror.player_cam = player_cam
	outer_mirror._apply_pigment()

	await get_tree().physics_frame
	await get_tree().physics_frame
	MirrorManager.refresh_now()
	return root


func _wait_for_link_eval(interaction: Node) -> void:
	interaction.is_mirror_visible = true
	for _i: int in range(STAGGER_WAIT_FRAMES):
		await get_tree().physics_frame


const STAGGER_WAIT_FRAMES: int = 8
