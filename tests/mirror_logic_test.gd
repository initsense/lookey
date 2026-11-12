extends GdUnitTestSuite
## Pigment tables, mirror cull masks, link/affect state, occlusion, and
## dissolve-exit transitions for reveal-mirror and dissolve-mirror mechanics.


const OBJECT_SCENE := preload("res://prefabs/object.tscn")
const MIRROR_SCENE := preload("res://entities/mirror/mirror.tscn")
const PLAYER_SCENE := preload("res://entities/player/player.tscn")
const PIGMENT_ENTITY_SCRIPT := preload("res://scripts/pigment_entity.gd")


func after_test() -> void:
	# Tests change the render depth on the MirrorManager autoload, so put it back.
	MirrorManager.render_depth = MirrorManager.DEFAULT_RENDER_DEPTH


func test_tables() -> void:
	for pigment: Pigments.Pigment in Pigments.Pigment.values():
		assert_bool(Pigments.LAYERS.has(pigment)).is_true()
		assert_bool(Pigments.COLORS.has(pigment)).is_true()


func test_pigment_material_files_match_pigment_colors() -> void:
	for pigment: Pigments.Pigment in Pigments.Pigment.values():
		assert_bool(PigmentEntity.PIGMENT_MATERIALS.has(pigment)).is_true()
		var material: StandardMaterial3D = PigmentEntity.PIGMENT_MATERIALS[pigment]
		assert_that(material.albedo_color).is_equal(Pigments.COLORS[pigment])


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
	assert_int(Pigments.mix_pigments(Pigments.Pigment.GREEN, Pigments.Pigment.VIOLET)).is_equal(Pigments.Pigment.WHITE)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.ORANGE, Pigments.Pigment.VIOLET)).is_equal(Pigments.Pigment.WHITE)
	assert_int(Pigments.mix_pigments(Pigments.Pigment.WHITE, Pigments.Pigment.YELLOW)).is_equal(Pigments.Pigment.WHITE)


func test_mirror_chain_pigment_mixing() -> void:
	var red := Mirror3D.new()
	var yellow := Mirror3D.new()
	var blue := Mirror3D.new()
	red.pigment = Pigments.Pigment.RED
	yellow.pigment = Pigments.Pigment.YELLOW
	blue.pigment = Pigments.Pigment.BLUE

	assert_int(Pigments.mix_mirror_chain_pigment([])).is_equal(Pigments.Pigment.WHITE)
	# A directly viewed mirror keeps its own pigment.
	assert_int(Pigments.mix_mirror_chain_pigment([yellow])).is_equal(Pigments.Pigment.YELLOW)
	assert_int(Pigments.mix_mirror_chain_pigment([yellow, blue])).is_equal(Pigments.Pigment.GREEN)
	assert_int(Pigments.mix_mirror_chain_pigment([red, yellow])).is_equal(Pigments.Pigment.ORANGE)
	assert_int(Pigments.mix_mirror_chain_pigment([yellow, yellow])).is_equal(Pigments.Pigment.YELLOW)
	# All three primaries along a 3-bounce chain mix to white.
	assert_int(Pigments.mix_mirror_chain_pigment([red, yellow, blue])).is_equal(Pigments.Pigment.WHITE)
	# Two distinct secondary hues along a chain also cover all three primaries.
	var green := Mirror3D.new()
	var violet := Mirror3D.new()
	var orange := Mirror3D.new()
	green.pigment = Pigments.Pigment.GREEN
	violet.pigment = Pigments.Pigment.VIOLET
	orange.pigment = Pigments.Pigment.ORANGE
	assert_int(Pigments.mix_mirror_chain_pigment([green, violet])).is_equal(Pigments.Pigment.WHITE)
	assert_int(Pigments.mix_mirror_chain_pigment([orange, violet])).is_equal(Pigments.Pigment.WHITE)
	assert_int(Pigments.mix_mirror_chain_pigment([blue, yellow, blue])).is_equal(Pigments.Pigment.GREEN)

	for mirror: Mirror3D in [red, yellow, blue, green, violet, orange]:
		mirror.free()


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
	assert_int(entity.mesh_instance.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.YELLOW, true) - 1))

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
	assert_int(entity.mesh_instance.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.YELLOW, true) - 1))

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
	assert_int(entity.mesh_instance.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.BLUE, false) - 1))

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
	assert_int(entity.mesh_instance.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.BLUE, false) - 1))
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
	assert_int(entity.mesh_instance.layers).is_equal(1 << 18)
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
	front.hidden_entity = false
	hidden.pigment = Pigments.Pigment.BLUE
	hidden.hidden_entity = true
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
	hidden.hidden_entity = true
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


func test_mirror_glass_never_casts_shadows() -> void:
	# A shadow-casting ReflectedQuad drops a huge rectangular shadow onto the floor
	# inside the outer mirror's reflected-world whenever nested reflection is active.
	var packed_mirror: Mirror3D = MIRROR_SCENE.instantiate()
	var packed_quad: MeshInstance3D = packed_mirror.get_node("Quad")
	var packed_reflected_quad: MeshInstance3D = packed_mirror.get_node("ReflectedQuad")
	assert_int(packed_quad.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(packed_reflected_quad.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	packed_mirror.free()

	var root := await _build_nested_mirror_scene(
		Pigments.Pigment.YELLOW,
		Mirror3D.MirrorType.REVEAL,
		Pigments.Pigment.BLUE,
		Mirror3D.MirrorType.REVEAL
	)
	for mirror_name: String in ["InnerMirror", "OuterMirror"]:
		var mirror: Mirror3D = root.get_node(mirror_name)
		assert_int(mirror._mirror_quad.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_int(mirror._reflected_quad.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	root.queue_free()


func test_shadow_casters_survive_off_axis_mirror_culling() -> void:
	# Godot culls directional shadow casters with a centered frustum that ignores the mirror
	# camera's frustum offset, so casters need an extra cull margin to keep their shadows in the glass.
	assert_bool(
		ProjectSettings.get_setting("rendering/lights_and_shadows/tighter_shadow_caster_culling", true)
	).is_false()

	var root := await _build_link_scene()
	var front: PigmentEntity = root.get_node("Front")
	var casters: Array[Node] = front.find_children("*", "GeometryInstance3D", true, false)
	var checked: int = 0
	for node: Node in casters:
		var geom: GeometryInstance3D = node as GeometryInstance3D
		if geom.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		assert_float(geom.extra_cull_margin).is_greater_equal(MirrorManager.OFF_AXIS_SHADOW_CASTER_MARGIN)
		checked += 1
	assert_int(checked).is_greater(0)

	root.queue_free()


func test_mirror_keeps_full_resolution_up_close() -> void:
	# Tight resolution thresholds make the mirror shrink its viewport (blurry glass) and
	# resize it on every threshold crossing (black-frame flicker) while the player walks around.
	var mirror: Mirror3D = MIRROR_SCENE.instantiate()
	mirror.res_decrease_distances = [3.0, 6.0, 9.0]
	add_child(mirror)

	assert_float(mirror.res_decrease_distances[0]).is_greater_equal(30.0)
	mirror._update_resolution_scale(10.0)
	assert_float(mirror._current_resolution_scale).is_equal(1.0)
	mirror._update_resolution_scale(29.0)
	assert_float(mirror._current_resolution_scale).is_equal(1.0)

	mirror.queue_free()


func test_observer_on_mirror_plane_pauses_reflection() -> void:
	# An observer a couple of centimeters from the mirror plane makes the off-axis frustum degenerate,
	# which triggers create_frustum_points errors in Godot's light culler.
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var origin: Vector3 = mirror.get_mirror_origin()
	var normal: Vector3 = mirror.get_mirror_normal()
	var on_plane: Vector3 = origin + normal * 0.02
	var in_front: Vector3 = origin + normal * 2.0

	assert_bool(mirror._configure_mirror_camera(mirror._mirror_camera, on_plane, mirror.cull_mask, true)).is_false()
	assert_bool(mirror._configure_mirror_camera(mirror._mirror_camera, in_front, mirror.cull_mask, true)).is_true()

	mirror.configure_reflected_view(on_plane, mirror.cull_mask)
	assert_int(mirror._reflected_viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)
	mirror.configure_reflected_view(in_front, mirror.cull_mask)
	assert_int(mirror._reflected_viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)

	root.queue_free()


func test_inactive_direct_viewport_stays_paused() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")

	# Even before its first render, a mirror the player cannot see must not render.
	mirror._has_rendered_direct = false
	mirror.set_direct_viewport_active(false)
	assert_int(mirror._mirror_viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)

	mirror.set_direct_viewport_active(true)
	assert_int(mirror._mirror_viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)

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
		_reflected_border_color(inner_mirror, 0)
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
		_reflected_border_color(inner_mirror, 0)
	).is_equal(Pigments.COLORS[Pigments.Pigment.ORANGE])

	root.queue_free()


func test_inner_mirror_seen_by_two_outer_mirrors_gets_one_reflected_view_each() -> void:
	# A blue mirror shown inside a yellow and a red mirror at the same time must render one view per
	# outer mirror (green from the yellow one, violet from the red one), each from that outer mirror's
	# viewpoint. A single shared view shows the wrong pigment and a distorted image in one of them.
	var root := await _build_nested_mirror_scene(
		Pigments.Pigment.BLUE,
		Mirror3D.MirrorType.REVEAL,
		Pigments.Pigment.YELLOW,
		Mirror3D.MirrorType.REVEAL
	)
	var inner_mirror: Mirror3D = root.get_node("InnerMirror")
	var yellow_outer: Mirror3D = root.get_node("OuterMirror")
	# Two narrow outer mirrors side by side, each showing part of the inner mirror.
	yellow_outer.size = Vector2(1.0, 3.0)
	yellow_outer.global_position = Vector3(0.4, 1.5, 3.0)
	var red_outer: Mirror3D = _add_mirror(
		root, "RedOuterMirror", Pigments.Pigment.RED, Mirror3D.MirrorType.REVEAL, Vector3(1.6, 1.5, 3.0)
	)
	await get_tree().physics_frame
	MirrorManager.refresh_now()

	var yellow_slot: int = inner_mirror.get_reflected_slot(Mirror3D.reflected_view_key([yellow_outer]))
	var red_slot: int = inner_mirror.get_reflected_slot(Mirror3D.reflected_view_key([red_outer]))
	assert_int(yellow_slot).is_greater_equal(0)
	assert_int(red_slot).is_greater_equal(0)
	assert_int(red_slot).is_not_equal(yellow_slot)
	if yellow_slot < 0 or red_slot < 0 or yellow_slot == red_slot:
		root.free()
		return

	var expected := {
		yellow_slot: [yellow_outer, Pigments.Pigment.GREEN],
		red_slot: [red_outer, Pigments.Pigment.VIOLET],
	}
	for slot: int in expected:
		var outer: Mirror3D = expected[slot][0]
		var mixed: Pigments.Pigment = expected[slot][1]
		var camera: Camera3D = inner_mirror._reflected_cameras[slot]
		assert_bool(_has_layer(camera.cull_mask, Pigments.get_entity_layer(mixed, true))).is_true()
		assert_bool(_has_layer(camera.cull_mask, Pigments.get_entity_layer(Pigments.Pigment.BLUE, true))).is_false()
		var expected_pos: Vector3 = inner_mirror.reflect_point(outer._mirror_camera.global_position)
		assert_bool(camera.global_position.distance_to(expected_pos) < 0.01).is_true()
		assert_int(inner_mirror._reflected_viewports[slot].render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)

		# The glass shader picks the view whose stored viewpoint matches the outer mirror camera drawing it.
		var observer: Vector3 = _reflected_observer(inner_mirror, slot)
		assert_bool(observer.distance_to(outer._mirror_camera.global_position) < 0.001).is_true()
		assert_that(_reflected_border_color(inner_mirror, slot)).is_equal(Pigments.COLORS[mixed])

	# Slots stay put across frames so the views never swap between outer mirrors.
	MirrorManager.refresh_now()
	assert_int(inner_mirror.get_reflected_slot(Mirror3D.reflected_view_key([yellow_outer]))).is_equal(yellow_slot)
	assert_int(inner_mirror.get_reflected_slot(Mirror3D.reflected_view_key([red_outer]))).is_equal(red_slot)

	root.queue_free()


func test_mirror_inside_nested_glass_gets_three_mirror_view() -> void:
	# A red dissolve-mirror seen inside a blue mirror, itself seen inside a yellow mirror, must be drawn
	# inside the blue mirror's (green) glass. Its view is rendered from the blue mirror's reflected camera,
	# with the three-way mix (red + blue + yellow = white) and the red mirror's own DISSOLVE type.
	var root := await _build_nested_mirror_scene(
		Pigments.Pigment.BLUE,
		Mirror3D.MirrorType.REVEAL,
		Pigments.Pigment.YELLOW,
		Mirror3D.MirrorType.REVEAL
	)
	var middle: Mirror3D = root.get_node("InnerMirror")
	var outer: Mirror3D = root.get_node("OuterMirror")
	var innermost: Mirror3D = _add_mirror(
		root, "InnermostMirror", Pigments.Pigment.RED, Mirror3D.MirrorType.DISSOLVE, Vector3(2.5, 1.5, 1.0)
	)
	await get_tree().physics_frame
	MirrorManager.refresh_now()

	var has_chain: bool = false
	for chain: Array in MirrorManager.get_chains_for_outer_mirror(outer):
		if chain.size() == 3 and chain[0] == innermost and chain[1] == middle:
			has_chain = true
	assert_bool(has_chain).is_true()
	var middle_slot: int = middle.get_reflected_slot(Mirror3D.reflected_view_key([outer]))
	var slot: int = innermost.get_reflected_slot(Mirror3D.reflected_view_key([outer, middle]))
	assert_int(middle_slot).is_greater_equal(0)
	assert_int(slot).is_greater_equal(0)
	if not has_chain or middle_slot < 0 or slot < 0:
		root.free()
		return

	# The blue mirror's view for the yellow mirror draws other mirrors' glass, so the red mirror shows up in it.
	var middle_camera: Camera3D = middle._reflected_cameras[middle_slot]
	assert_bool(_has_layer(middle_camera.cull_mask, Mirror3D.REFLECTED_MIRROR_LAYER)).is_true()

	var camera: Camera3D = innermost._reflected_cameras[slot]
	assert_bool(_reflected_observer(innermost, slot).distance_to(middle_camera.global_position) < 0.001).is_true()
	var expected_pos: Vector3 = innermost.reflect_point(middle_camera.global_position)
	assert_bool(camera.global_position.distance_to(expected_pos) < 0.01).is_true()
	assert_int(innermost._reflected_viewports[slot].render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)
	assert_that(_reflected_border_color(innermost, slot)).is_equal(Pigments.COLORS[Pigments.Pigment.WHITE])
	# A white dissolve-mirror hides every manifest hue entity. Reflections stop at three mirrors deep.
	for hue: Pigments.Pigment in Pigments.Pigment.values():
		assert_bool(_has_layer(camera.cull_mask, Pigments.get_entity_layer(hue, false))).is_false()
	assert_bool(_has_layer(camera.cull_mask, Mirror3D.REFLECTED_MIRROR_LAYER)).is_false()

	# Slots stay put across frames.
	MirrorManager.refresh_now()
	assert_int(innermost.get_reflected_slot(Mirror3D.reflected_view_key([outer, middle]))).is_equal(slot)
	assert_int(middle.get_reflected_slot(Mirror3D.reflected_view_key([outer]))).is_equal(middle_slot)

	# Once the red mirror leaves the blue mirror's glass, its view stops and the blue mirror's view
	# no longer draws other mirrors' glass.
	innermost.global_position = Vector3(40.0, 1.5, 1.0)
	await get_tree().physics_frame
	MirrorManager.refresh_now()
	assert_int(innermost.get_reflected_slot(Mirror3D.reflected_view_key([outer, middle]))).is_equal(-1)
	assert_bool(_has_layer(middle_camera.cull_mask, Mirror3D.REFLECTED_MIRROR_LAYER)).is_false()

	root.queue_free()


func test_render_depth_setting_is_clamped_and_registered() -> void:
	assert_bool(ProjectSettings.has_setting(MirrorManager.RENDER_DEPTH_SETTING)).is_true()
	assert_int(int(ProjectSettings.get_setting(MirrorManager.RENDER_DEPTH_SETTING))).is_equal(
		MirrorManager.DEFAULT_RENDER_DEPTH
	)
	MirrorManager.render_depth = 0
	assert_int(MirrorManager.render_depth).is_equal(1)
	MirrorManager.render_depth = 99
	assert_int(MirrorManager.render_depth).is_equal(MirrorManager.MAX_RENDER_DEPTH)


func test_render_depth_limits_how_deep_mirrors_are_drawn() -> void:
	# Blue mirror seen in a yellow one, and a red mirror seen in the blue glass. The two parallel mirrors
	# (blue and red) also reflect each other, which gives a 4-mirror chain [blue, red, blue, yellow].
	var root := await _build_nested_mirror_scene(
		Pigments.Pigment.BLUE,
		Mirror3D.MirrorType.REVEAL,
		Pigments.Pigment.YELLOW,
		Mirror3D.MirrorType.REVEAL
	)
	var blue: Mirror3D = root.get_node("InnerMirror")
	var yellow: Mirror3D = root.get_node("OuterMirror")
	var red: Mirror3D = _add_mirror(
		root, "RedMirror", Pigments.Pigment.RED, Mirror3D.MirrorType.DISSOLVE, Vector3(2.5, 1.5, 1.0)
	)
	await get_tree().physics_frame

	var two_deep: String = Mirror3D.reflected_view_key([yellow])
	var three_deep: String = Mirror3D.reflected_view_key([yellow, blue])
	var four_deep: String = Mirror3D.reflected_view_key([yellow, blue, red])

	# Depth 1: only the mirror the player looks at is drawn, no mirror shows up inside another.
	MirrorManager.render_depth = 1
	MirrorManager.refresh_now()
	assert_int(blue.get_reflected_slot(two_deep)).is_equal(-1)
	assert_int(red.get_reflected_slot(three_deep)).is_equal(-1)

	# Depth 2: a mirror inside a mirror. Linking still builds 3-mirror chains, independent of what is drawn.
	MirrorManager.render_depth = 2
	MirrorManager.refresh_now()
	assert_int(blue.get_reflected_slot(two_deep)).is_greater_equal(0)
	assert_int(red.get_reflected_slot(three_deep)).is_equal(-1)
	assert_bool(_has_chain(yellow, [red, blue, yellow])).is_true()
	assert_bool(_has_layer(blue._reflected_cameras[blue.get_reflected_slot(two_deep)].cull_mask, Mirror3D.REFLECTED_MIRROR_LAYER)).is_false()

	# Depth 3: one more level, and the blue view now draws the red mirror's glass.
	MirrorManager.render_depth = 3
	MirrorManager.refresh_now()
	assert_int(red.get_reflected_slot(three_deep)).is_greater_equal(0)
	assert_int(blue.get_reflected_slot(Mirror3D.reflected_view_key([yellow, blue, red]))).is_equal(-1)
	assert_bool(_has_chain(yellow, [blue, red, blue, yellow])).is_false()
	assert_bool(_has_layer(blue._reflected_cameras[blue.get_reflected_slot(two_deep)].cull_mask, Mirror3D.REFLECTED_MIRROR_LAYER)).is_true()

	# Depth 4: the blue mirror appears again inside the red glass, drawn from the red mirror's view.
	MirrorManager.render_depth = 4
	MirrorManager.refresh_now()
	assert_bool(_has_chain(yellow, [blue, red, blue, yellow])).is_true()
	var slot: int = blue.get_reflected_slot(four_deep)
	var red_slot: int = red.get_reflected_slot(three_deep)
	assert_int(slot).is_greater_equal(0)
	assert_int(red_slot).is_greater_equal(0)
	if slot >= 0 and red_slot >= 0:
		var red_camera: Camera3D = red._reflected_cameras[red_slot]
		assert_bool(_has_layer(red_camera.cull_mask, Mirror3D.REFLECTED_MIRROR_LAYER)).is_true()
		assert_bool(_reflected_observer(blue, slot).distance_to(red_camera.global_position) < 0.001).is_true()
		assert_that(_reflected_border_color(blue, slot)).is_equal(Pigments.COLORS[Pigments.Pigment.WHITE])
		assert_int(blue._reflected_viewports[slot].render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)

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
		_reflected_border_color(inner_mirror, 0)
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


func test_legacy_is_invisible_property_sets_hidden_entity() -> void:
	var entity: PigmentEntity = OBJECT_SCENE.instantiate()
	entity.set(&"is_invisible", true)
	assert_bool(entity.hidden_entity).is_true()
	assert_bool(entity.is_hidden_entity()).is_true()
	entity.free()


func test_mesh_only_hidden_entity_generates_collider() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var interaction: Node = mirror.get_node("Interaction")
	(root.get_node("Front") as Node3D).global_position = Vector3(40, 1, 0)
	(root.get_node("Hidden") as Node3D).global_position = Vector3(-40, 1, 0)

	var crate := _make_mesh_instance("Crate", BoxMesh.new(), Vector3.ZERO)
	var entity := _attach_pigment_entity(crate, Pigments.Pigment.BLUE, true)
	root.add_child(crate)
	crate.global_position = Vector3(0, 1, 0.5)

	var collider: StaticBody3D = crate.get_node_or_null("Collider") as StaticBody3D
	assert_that(collider).is_not_null()
	assert_bool(collider.get_node("CrateShape").shape is ConvexPolygonShape3D).is_true()
	var hidden_layer: int = Pigments.get_entity_layer(Pigments.Pigment.BLUE, true)
	assert_int(crate.layers).is_equal(1 << (hidden_layer - 1))
	assert_bool(_has_layer(collider.collision_layer, hidden_layer)).is_true()
	assert_bool(entity.is_collidable()).is_false()

	# Linked through the white reveal-mirror: still invisible in the real-world, but solid there.
	interaction._refresh_tracked_entities()
	await get_tree().physics_frame
	await _wait_for_link_eval(interaction)
	assert_bool(entity.is_linked()).is_true()
	assert_bool(entity.is_affected()).is_true()
	assert_bool(entity.is_collidable()).is_true()
	assert_int(crate.layers).is_equal(1 << (hidden_layer - 1))

	# Out of the mirror's reflected-world: no longer linked, no longer solid.
	crate.global_position = Vector3(30, 1, 0.5)
	await _wait_for_link_eval(interaction)
	assert_bool(entity.is_linked()).is_false()
	assert_bool(entity.is_collidable()).is_false()

	root.queue_free()


func test_grouped_manifest_entity_applies_pigment_to_all_geometry() -> void:
	var root := Node3D.new()
	add_child(root)

	var shelf := Node3D.new()
	shelf.name = "Shelf"
	shelf.add_child(_make_mesh_instance("Left", BoxMesh.new(), Vector3(-1, 0, 0)))
	shelf.add_child(_make_mesh_instance("Right", SphereMesh.new(), Vector3(1, 0, 0)))
	var top := CSGBox3D.new()
	top.name = "Top"
	top.size = Vector3(3, 0.2, 1)
	top.position = Vector3(0, 0.6, 0)
	shelf.add_child(top)
	var entity := _attach_pigment_entity(shelf, Pigments.Pigment.YELLOW, false)
	shelf.scale = Vector3(2, 1, 1)
	root.add_child(shelf)
	shelf.global_position = Vector3(0, 1, 0)
	await _wait_frames(PigmentEntity.MAX_CSG_BAKE_FRAMES)

	assert_int(entity.geometries.size()).is_equal(3)
	var manifest_layer: int = Pigments.get_entity_layer(Pigments.Pigment.YELLOW, false)
	for geometry: GeometryInstance3D in entity.geometries:
		assert_int(geometry.layers).is_equal(1 << (manifest_layer - 1))
		assert_object(geometry.material_override).is_same(PigmentEntity.PIGMENT_MATERIALS[Pigments.Pigment.YELLOW])

	var collider: StaticBody3D = shelf.get_node_or_null("Collider") as StaticBody3D
	assert_that(collider).is_not_null()
	assert_int(collider.get_child_count()).is_equal(3)
	for shape_name: String in ["LeftShape", "RightShape", "TopShape"]:
		assert_that(collider.get_node_or_null(shape_name)).is_not_null()
	# Collision shapes never inherit the entity's non-uniform scale.
	assert_bool(collider.global_basis.get_scale().is_equal_approx(Vector3.ONE)).is_true()

	# Link sampling covers all geometry, including the detailed sphere through its convex hull.
	var points: PackedVector3Array = entity.get_link_sample_points()
	assert_int(points.size()).is_greater(0)
	var bounds: AABB = entity.get_world_aabb().grow(0.01)
	for point: Vector3 in points:
		assert_bool(bounds.has_point(point)).is_true()

	assert_bool(entity.is_collidable()).is_true()
	var dissolve := Mirror3D.new()
	entity.set_mirror_link_state(dissolve, true, true)
	for body: StaticBody3D in entity.bodies:
		assert_bool(_has_layer(body.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_false()

	root.queue_free()
	dissolve.free()


func test_existing_static_body_is_reused() -> void:
	var root := Node3D.new()
	add_child(root)

	var pillars := Node3D.new()
	pillars.name = "Pillars"
	for pillar_name: String in ["West", "East"]:
		var pillar := _make_mesh_instance(pillar_name, BoxMesh.new(), Vector3(-1 if pillar_name == "West" else 1, 0, 0))
		var body := StaticBody3D.new()
		var shape_node := CollisionShape3D.new()
		shape_node.shape = BoxShape3D.new()
		body.add_child(shape_node)
		pillar.add_child(body)
		pillars.add_child(pillar)
	var entity := _attach_pigment_entity(pillars, Pigments.Pigment.RED, false)
	root.add_child(pillars)
	await get_tree().physics_frame

	assert_that(pillars.get_node_or_null("Collider")).is_null()
	assert_int(entity.geometries.size()).is_equal(2)
	assert_int(entity.bodies.size()).is_equal(2)
	var manifest_layer: int = Pigments.get_entity_layer(Pigments.Pigment.RED, false)
	for body: StaticBody3D in entity.bodies:
		assert_bool(_has_layer(body.collision_layer, manifest_layer)).is_true()
		assert_bool(_has_layer(body.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_true()

	# A dissolve-mirror disables every collider body of the entity.
	var dissolve := Mirror3D.new()
	entity.set_mirror_link_state(dissolve, true, true)
	for body: StaticBody3D in entity.bodies:
		assert_bool(_has_layer(body.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_false()

	root.queue_free()
	dissolve.free()


func test_nested_pigment_entity_stays_separate() -> void:
	var root := Node3D.new()
	add_child(root)

	var cabinet := Node3D.new()
	cabinet.name = "Cabinet"
	var cabinet_body := _make_mesh_instance("Body", BoxMesh.new(), Vector3.ZERO)
	cabinet.add_child(cabinet_body)
	var handle := _make_mesh_instance("Handle", BoxMesh.new(), Vector3(0, 0, 0.7))
	handle.scale = Vector3(0.3, 0.3, 0.3)
	cabinet.add_child(handle)
	var handle_entity := _attach_pigment_entity(handle, Pigments.Pigment.BLUE, false)
	var cabinet_entity := _attach_pigment_entity(cabinet, Pigments.Pigment.RED, false)
	root.add_child(cabinet)
	await get_tree().physics_frame

	assert_int(cabinet_entity.geometries.size()).is_equal(1)
	assert_object(cabinet_entity.geometries[0]).is_same(cabinet_body)
	assert_int(handle_entity.geometries.size()).is_equal(1)
	assert_int(cabinet_body.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.RED, false) - 1))
	assert_int(handle.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.BLUE, false) - 1))

	assert_int(cabinet.get_node("Collider").get_child_count()).is_equal(1)
	assert_int(handle_entity.bodies.size()).is_equal(1)
	assert_bool(cabinet_entity.bodies.has(handle_entity.bodies[0])).is_false()

	root.queue_free()


func test_csg_hidden_entity_links_through_reveal_mirror() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var interaction: Node = mirror.get_node("Interaction")
	(root.get_node("Front") as Node3D).global_position = Vector3(40, 1, 0)
	(root.get_node("Hidden") as Node3D).global_position = Vector3(-40, 1, 0)

	var block := CSGBox3D.new()
	block.name = "Block"
	block.use_collision = true
	var entity := _attach_pigment_entity(block, Pigments.Pigment.BLUE, true)
	root.add_child(block)
	# Start outside the mirror's reflected-world: the collider is generated a frame later, once the CSG mesh exists.
	block.global_position = Vector3(30, 1, 0.5)
	await _wait_frames(PigmentEntity.MAX_CSG_BAKE_FRAMES)
	await _wait_for_link_eval(interaction)

	assert_bool(block.use_collision).is_false()
	var collider: StaticBody3D = block.get_node_or_null("Collider") as StaticBody3D
	assert_that(collider).is_not_null()
	assert_bool((interaction._exclude_rids[entity] as Array).has(collider.get_rid())).is_true()
	assert_bool(entity.is_linked()).is_false()
	assert_bool(entity.is_collidable()).is_false()

	# The late collider must not occlude its own entity's link.
	block.global_position = Vector3(0, 1, 0.5)
	await _wait_for_link_eval(interaction)
	assert_bool(entity.is_linked()).is_true()
	assert_bool(entity.is_affected()).is_true()
	assert_bool(entity.is_collidable()).is_true()

	root.queue_free()


func test_dissolve_exit_pushes_player_out_of_convex_collider() -> void:
	var root := Node3D.new()
	add_child(root)
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 0, 0)

	var cylinder := CylinderMesh.new()
	cylinder.height = 1.0
	var barrel := _make_mesh_instance("Barrel", cylinder, Vector3.ZERO)
	var entity := _attach_pigment_entity(barrel, Pigments.Pigment.BLUE, false)
	root.add_child(barrel)
	barrel.global_position = Vector3(0, 1, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool((entity.static_body.get_child(0) as CollisionShape3D).shape is ConvexPolygonShape3D).is_true()

	var dissolve := Mirror3D.new()
	entity.set_mirror_link_state(dissolve, true, true)
	player.global_position = Vector3(0, 0.5, 0)

	entity.set_mirror_link_state(dissolve, false, false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_bool(entity.is_collidable()).is_true()
	assert_vector(barrel.global_position).is_equal(Vector3(0, 1, 0))
	assert_bool(player.global_position.distance_to(Vector3(0, 0.5, 0)) > 0.01).is_true()

	root.queue_free()
	dissolve.free()


func _make_mesh_instance(node_name: String, primitive: Mesh, position: Vector3) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = primitive
	mesh_instance.position = position
	return mesh_instance


func _attach_pigment_entity(node: Node3D, pigment: Pigments.Pigment, is_hidden: bool) -> PigmentEntity:
	node.set_script(PIGMENT_ENTITY_SCRIPT)
	var entity := node as PigmentEntity
	entity.pigment = pigment
	entity.hidden_entity = is_hidden
	return entity


func _wait_frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().process_frame


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
	entity.hidden_entity = is_hidden
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
	mirror.player_cam = player.get_node("CamHolder/Camera3D") as Camera3D
	# CamHolder is pre-rotated 180 deg, so the camera looks toward +Z / the mirror.
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

	var player_cam: Camera3D = player.get_node("CamHolder/Camera3D") as Camera3D
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


## Adds a mirror facing -z (toward the scene's inner mirror) that the scene's player can see.
func _add_mirror(
	root: Node3D,
	mirror_name: String,
	pigment: Pigments.Pigment,
	type: Mirror3D.MirrorType,
	position: Vector3
) -> Mirror3D:
	var player: CharacterBody3D = root.get_node("Player")
	var mirror: Mirror3D = MIRROR_SCENE.instantiate()
	mirror.name = mirror_name
	mirror.player = player
	mirror.pigment = pigment
	mirror.mirror_type = type
	mirror.always_active = true
	mirror.size = Vector2(1.0, 3.0)
	root.add_child(mirror)
	mirror.global_position = position
	mirror.rotation = Vector3(0.0, PI, 0.0)
	mirror.player_cam = player.get_node("CamHolder/Camera3D") as Camera3D
	mirror._apply_pigment()
	return mirror


## Returns true when the outer mirror has a reflection chain made of exactly these mirrors (innermost first).
func _has_chain(outer: Mirror3D, expected: Array) -> bool:
	for chain: Array in MirrorManager.get_chains_for_outer_mirror(outer):
		if chain == expected:
			return true
	return false


func _reflected_border_color(mirror: Mirror3D, slot: int) -> Color:
	var colors: PackedColorArray = mirror._reflected_shader_material.get_shader_parameter(&"reflected_border_colors")
	return colors[slot]


func _reflected_observer(mirror: Mirror3D, slot: int) -> Vector3:
	var observers: PackedVector3Array = mirror._reflected_shader_material.get_shader_parameter(&"reflected_observers")
	return observers[slot]


func _wait_for_link_eval(interaction: Node) -> void:
	interaction.is_mirror_visible = true
	for _i: int in range(STAGGER_WAIT_FRAMES):
		await get_tree().physics_frame


const STAGGER_WAIT_FRAMES: int = 8
