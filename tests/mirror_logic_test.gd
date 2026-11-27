extends GdUnitTestSuite
## Pigment tables, mirror cull masks, link/affect state, occlusion, and
## dissolve-exit transitions for reveal-mirror and dissolve-mirror mechanics.


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


func test_mirror_sun_copies_its_parent_and_uses_one_cascade() -> void:
	var root := Node3D.new()
	add_child(root)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.light_energy = 1.4
	sun.light_indirect_energy = 0.7
	sun.light_volumetric_fog_energy = 0.3
	sun.light_specular = 0.4
	sun.light_angular_distance = 0.5
	sun.light_negative = false
	sun.light_cull_mask = 512
	sun.shadow_caster_mask = 7
	sun.shadow_enabled = true
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.5
	sun.shadow_transmittance_bias = 0.04
	sun.shadow_blur = 1.2
	sun.shadow_opacity = 0.9
	sun.shadow_reverse_cull_face = true
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.layers = 512
	sun.rotation = Vector3(-0.6, 0.4, 0.0)
	root.add_child(sun)

	var mirror_sun: MirrorSun = preload("res://entities/mirror/mirror_sun.tscn").instantiate()
	sun.add_child(mirror_sun)
	await get_tree().process_frame

	assert_int(mirror_sun.layers).is_equal(1 << (Mirror3D.MIRROR_SUN_LAYER - 1))
	assert_int(mirror_sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_float(mirror_sun.directional_shadow_max_distance).is_equal_approx(MirrorSun.SHADOW_MAX_DISTANCE, 0.01)
	assert_float(mirror_sun.directional_shadow_fade_start).is_equal_approx(MirrorSun.SHADOW_FADE_START, 0.001)
	assert_int(sun.directional_shadow_mode).is_not_equal(DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_that(mirror_sun.light_color).is_equal(sun.light_color)
	assert_float(mirror_sun.light_energy).is_equal_approx(sun.light_energy, 0.001)
	assert_float(mirror_sun.light_indirect_energy).is_equal_approx(sun.light_indirect_energy, 0.001)
	assert_float(mirror_sun.light_volumetric_fog_energy).is_equal_approx(sun.light_volumetric_fog_energy, 0.001)
	assert_float(mirror_sun.light_specular).is_equal_approx(sun.light_specular, 0.001)
	assert_float(mirror_sun.light_angular_distance).is_equal_approx(
		maxf(sun.light_angular_distance, MirrorSun.MIN_ANGULAR_DISTANCE),
		0.001
	)
	assert_bool(mirror_sun.light_negative).is_equal(sun.light_negative)
	assert_int(mirror_sun.light_cull_mask).is_equal(sun.light_cull_mask)
	assert_int(mirror_sun.shadow_caster_mask).is_equal(sun.shadow_caster_mask)
	assert_bool(mirror_sun.shadow_enabled).is_true()
	assert_float(mirror_sun.shadow_bias).is_equal_approx(sun.shadow_bias, 0.001)
	assert_float(mirror_sun.shadow_normal_bias).is_equal_approx(sun.shadow_normal_bias, 0.001)
	assert_float(mirror_sun.shadow_transmittance_bias).is_equal_approx(sun.shadow_transmittance_bias, 0.001)
	assert_float(mirror_sun.shadow_blur).is_equal_approx(sun.shadow_blur, 0.001)
	assert_float(mirror_sun.shadow_opacity).is_equal_approx(sun.shadow_opacity, 0.001)
	assert_bool(mirror_sun.shadow_reverse_cull_face).is_true()
	assert_int(mirror_sun.sky_mode).is_equal(DirectionalLight3D.SKY_MODE_LIGHT_ONLY)
	assert_bool(mirror_sun.global_basis.is_equal_approx(sun.global_basis)).is_true()
	var near_sun: DirectionalLight3D = mirror_sun.get_node("MirrorSunNear")
	assert_int(near_sun.layers).is_equal(1 << (Mirror3D.MIRROR_SUN_NEAR_LAYER - 1))
	assert_int(near_sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_float(near_sun.directional_shadow_split_1).is_equal_approx(MirrorSun.NEAR_SPLIT_1, 0.001)
	assert_float(near_sun.light_angular_distance).is_equal_approx(sun.light_angular_distance, 0.001)
	assert_bool(near_sun.directional_shadow_blend_splits).is_false()

	sun.light_energy = 0.35
	sun.light_angular_distance = 0.2
	sun.shadow_enabled = false
	sun.rotation = Vector3(-0.2, 1.1, 0.0)
	await get_tree().process_frame
	assert_float(mirror_sun.light_energy).is_equal_approx(0.35, 0.001)
	assert_float(mirror_sun.light_angular_distance).is_equal_approx(MirrorSun.MIN_ANGULAR_DISTANCE, 0.001)
	assert_float(near_sun.light_angular_distance).is_equal_approx(0.2, 0.001)
	assert_bool(mirror_sun.shadow_enabled).is_false()
	assert_int(mirror_sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_bool(mirror_sun.global_basis.is_equal_approx(sun.global_basis)).is_true()

	sun.visible = false
	await get_tree().process_frame
	assert_bool(mirror_sun.visible).is_true()
	assert_bool(mirror_sun.is_visible_in_tree()).is_false()
	sun.visible = true
	await get_tree().process_frame
	assert_bool(mirror_sun.is_visible_in_tree()).is_true()

	var orphan := MirrorSun.new()
	root.add_child(orphan)
	var orphan_warnings := orphan._get_configuration_warnings()
	assert_int(orphan_warnings.size()).is_equal(1)
	assert_bool(orphan_warnings[0].contains("child of the level")).is_true()

	sun.layers = 1
	mirror_sun._last_warning_state = -1
	mirror_sun._refresh_warnings()
	var overlap_warnings := mirror_sun._get_configuration_warnings()
	assert_int(overlap_warnings.size()).is_equal(1)
	assert_bool(overlap_warnings[0].contains("lit twice")).is_true()
	sun.layers = 512
	var clear_warnings := mirror_sun._get_configuration_warnings()
	assert_int(clear_warnings.size()).is_equal(0)

	root.queue_free()


func test_tutorial_sun_lights_the_room_and_mirror_sun_lights_mirrors() -> void:
	var packed: PackedScene = load("res://world/scenes/tutorial/tutorial.tscn")
	var root: Node = packed.instantiate()
	add_child(root)
	var sun: DirectionalLight3D = root.get_node("DirectionalLight3D")
	var mirror_sun: MirrorSun = sun.get_node("MirrorSun")
	await get_tree().process_frame

	assert_int(sun.layers).is_equal(1 << (Mirror3D.DIRECT_MIRROR_LAYER - 1))
	assert_int(mirror_sun.layers).is_equal(1 << (Mirror3D.MIRROR_SUN_LAYER - 1))
	assert_int(mirror_sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_bool(mirror_sun.shadow_enabled).is_equal(sun.shadow_enabled)
	assert_bool(mirror_sun.global_basis.is_equal_approx(sun.global_basis)).is_true()
	var player_cam: Camera3D = root.get_node("Player/CamHolder/Camera3D")
	assert_bool(_has_layer(player_cam.cull_mask, Mirror3D.DIRECT_MIRROR_LAYER)).is_true()
	assert_bool(_has_layer(player_cam.cull_mask, Mirror3D.MIRROR_SUN_LAYER)).is_false()
	assert_bool(_has_layer(player_cam.cull_mask, Mirror3D.MIRROR_SUN_NEAR_LAYER)).is_false()
	var near_sun: DirectionalLight3D = mirror_sun.get_node("MirrorSunNear")
	assert_int(near_sun.layers).is_equal(1 << (Mirror3D.MIRROR_SUN_NEAR_LAYER - 1))
	assert_int(near_sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)

	root.queue_free()


func test_mirror_cameras_see_the_mirror_sun_without_changing_far() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var player_cam: Camera3D = root.get_node("Player/CamHolder/Camera3D")
	mirror.size = Vector2(5.0, 4.0)
	mirror.global_position = Vector3(0.0, 2.0, 0.0)
	mirror.rotation = Vector3(0.0, PI, 0.0)
	var observer := Vector3(0.0, 2.0, -2.0)
	assert_bool(mirror._configure_mirror_camera(mirror._mirror_camera, observer, mirror.cull_mask, true)).is_true()
	# 2 m in front of a 5 m mirror is already a wide view, so the close-up sun keeps the shadow sharp.
	assert_float(mirror._mirror_camera.far).is_equal_approx(2.0 + mirror.cull_far, 0.02)
	assert_bool(_has_layer(mirror._mirror_camera.cull_mask, Mirror3D.MIRROR_SUN_NEAR_LAYER)).is_true()
	assert_bool(_has_layer(mirror._mirror_camera.cull_mask, Mirror3D.MIRROR_SUN_LAYER)).is_false()
	assert_bool(_has_layer(mirror._mirror_camera.cull_mask, Mirror3D.DIRECT_MIRROR_LAYER)).is_false()
	assert_bool(_has_layer(player_cam.cull_mask, Mirror3D.MIRROR_SUN_LAYER)).is_false()

	mirror._apply_mirror_config()
	assert_bool(_has_layer(mirror._mirror_camera.cull_mask, Mirror3D.MIRROR_SUN_LAYER)).is_true()
	assert_float(mirror._mirror_camera.far).is_equal_approx(2.0 + mirror.cull_far, 0.02)

	mirror.configure_reflected_view(observer, mirror.cull_mask)
	var reflected: Camera3D = mirror._reflected_cameras[0]
	assert_bool(_has_layer(reflected.cull_mask, Mirror3D.MIRROR_SUN_NEAR_LAYER)).is_true()
	assert_bool(_has_layer(reflected.cull_mask, Mirror3D.MIRROR_SUN_LAYER)).is_false()
	assert_float(reflected.far).is_equal_approx(2.0 + mirror.cull_far, 0.02)

	var close := Vector3(0.0, 2.0, -0.35)
	assert_bool(mirror._configure_mirror_camera(mirror._mirror_camera, close, mirror.cull_mask, true)).is_true()
	assert_float(mirror._mirror_camera.far).is_equal_approx(0.35 + mirror.cull_far, 0.02)
	assert_bool(_has_layer(mirror._mirror_camera.cull_mask, Mirror3D.MIRROR_SUN_NEAR_LAYER)).is_true()
	assert_bool(_has_layer(mirror._mirror_camera.cull_mask, Mirror3D.MIRROR_SUN_LAYER)).is_false()

	var distant := Vector3(0.0, 2.0, -12.0)
	assert_bool(mirror._configure_mirror_camera(mirror._mirror_camera, distant, mirror.cull_mask, true)).is_true()
	assert_bool(_has_layer(mirror._mirror_camera.cull_mask, Mirror3D.MIRROR_SUN_LAYER)).is_true()
	assert_bool(_has_layer(mirror._mirror_camera.cull_mask, Mirror3D.MIRROR_SUN_NEAR_LAYER)).is_false()
	assert_float(mirror._mirror_camera.far).is_equal_approx(12.0 + mirror.cull_far, 0.02)

	root.queue_free()


func test_single_cascade_covers_off_axis_mirror_views() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	mirror.size = Vector2(5.0, 4.0)
	mirror.global_position = Vector3(0.0, 2.0, 0.0)
	mirror.rotation = Vector3(0.0, PI, 0.0)
	var viewport_size := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 2560)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 1440))
	)
	mirror._mirror_viewport.size = viewport_size
	# Views like the reported screenshots: straight on from 12 m, and 6 m to the side.
	var observers: Array[Vector3] = [
		Vector3(0.0, 2.0, -12.0),
		Vector3(6.0, 2.0, -12.0),
		Vector3(6.0, 2.5, -8.0),
	]
	for observer: Vector3 in observers:
		assert_bool(
			mirror._configure_mirror_camera(mirror._mirror_camera, observer, mirror.cull_mask, true)
		).is_true()
		_assert_shadow_corners_inside_cascade(mirror, mirror._mirror_camera, viewport_size, observer)
		mirror.configure_reflected_view(observer, mirror.cull_mask)
		var reflected_viewport: SubViewport = mirror._reflected_viewports[0]
		reflected_viewport.size = viewport_size
		_assert_shadow_corners_inside_cascade(
			mirror,
			mirror._reflected_cameras[0],
			viewport_size,
			observer
		)

	root.queue_free()


func test_mirror_matches_camera_resolution_up_close_and_caps_distant_small_footprint() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var player: CharacterBody3D = root.get_node("Player")
	mirror.size = Vector2(5.0, 4.0)
	mirror.full_resolution_distance = 3.0
	mirror.min_resolution_distance = 30.0
	mirror.max_resolution_scale = 1.0
	mirror.min_resolution_scale = 0.25

	var expected_cam_vp: Vector2i = mirror._get_camera_viewport_size(mirror.player_cam)

	# Standing 1.0 m in front of a 5x4 m mirror (including laterally off-center):
	# closest surface distance <= 3.0 m and the mirror fills the screen -> exact 1:1 camera resolution.
	player.global_position = Vector3(1.1, 0.5, 2.0)
	await get_tree().process_frame
	MirrorManager.refresh_now()
	assert_float(mirror._distance_to_mirror_surface(mirror.player_cam.global_position)).is_less(2.0)
	assert_float(mirror._current_resolution_scale).is_equal_approx(1.0, 1e-4)
	assert_that(mirror._target_viewport_size).is_equal(expected_cam_vp)
	assert_that(mirror._mirror_viewport.size).is_equal(expected_cam_vp)

	# Even when standing right near the outer edge (x = 2.3 on a 5m-wide mirror) so half the screen shows the
	# room beside the mirror, the mirror's surface distance is still <= 3.0 m (full_resolution_scale = 1.0).
	player.global_position = Vector3(2.3, 0.5, 2.0)
	await get_tree().process_frame
	MirrorManager.refresh_now()
	assert_float(mirror._distance_to_mirror_surface(mirror.player_cam.global_position)).is_less(2.0)
	assert_float(mirror._current_resolution_scale).is_equal_approx(1.0, 1e-4)

	# A small 1x1 m mirror 2.8 m away is still within full_resolution_distance,
	# yet covers a fraction of the screen, so its SubViewport is capped to its screen footprint.
	mirror.size = Vector2(1.0, 1.0)
	player.global_position = Vector3(0.0, 0.5, 0.2)
	await get_tree().process_frame
	MirrorManager.refresh_now()
	assert_float(mirror._current_resolution_scale).is_equal_approx(1.0, 1e-4)
	assert_int(mirror._target_viewport_size.x).is_less(expected_cam_vp.x)
	assert_int(mirror._target_viewport_size.y).is_less(expected_cam_vp.y)

	root.queue_free()


func test_dynamic_resolution_steps_hysteresis_and_inspector_overrides() -> void:
	var mirror: Mirror3D = MIRROR_SCENE.instantiate()
	# Custom tight Inspector settings must NOT be overwritten in _ready().
	mirror.full_resolution_distance = 1.5
	mirror.min_resolution_distance = 11.5
	mirror.max_resolution_scale = 1.0
	mirror.min_resolution_scale = 0.2
	mirror.resolution_steps = 5
	add_child(mirror)

	assert_float(mirror.full_resolution_distance).is_equal_approx(1.5, 1e-4)
	assert_float(mirror.min_resolution_distance).is_equal_approx(11.5, 1e-4)
	assert_int(mirror.resolution_steps).is_equal(5)

	# 5 steps between 1.0 and 0.2 -> scales [1.0, 0.8, 0.6, 0.4, 0.2] at t = [0, 0.25, 0.5, 0.75, 1.0].
	assert_float(mirror._update_resolution_scale(1.0)).is_equal_approx(1.0, 1e-4)
	assert_int(mirror._current_step_index).is_equal(0)

	# t = (2.9 - 1.5) / 10 = 0.14 -> continuous_step = 0.56 (< 0.65 hysteresis threshold): stays on step 0.
	assert_float(mirror._update_resolution_scale(2.9)).is_equal_approx(1.0, 1e-4)
	assert_int(mirror._current_step_index).is_equal(0)

	# t = (3.3 - 1.5) / 10 = 0.18 -> continuous_step = 0.72 (> 0.65): transitions to step 1 (0.8).
	assert_float(mirror._update_resolution_scale(3.3)).is_equal_approx(0.8, 1e-4)
	assert_int(mirror._current_step_index).is_equal(1)

	# Walking slightly back toward the mirror (continuous_step = 0.44, which is >= 1 - 0.65 = 0.35):
	# hysteresis prevents ping-ponging back to step 0.
	assert_float(mirror._update_resolution_scale(2.6)).is_equal_approx(0.8, 1e-4)
	assert_int(mirror._current_step_index).is_equal(1)

	# Beyond min_resolution_distance -> clamps to min_resolution_scale (0.2).
	assert_float(mirror._update_resolution_scale(25.0)).is_equal_approx(0.2, 1e-4)
	assert_int(mirror._current_step_index).is_equal(4)

	# Inverted / extreme Inspector settings are guarded safely and capped at MAX_VIEWPORT_DIMENSION.
	mirror.min_resolution_distance = 0.5
	mirror.full_resolution_distance = 5.0
	mirror.min_resolution_scale = 0.9
	mirror.max_resolution_scale = 10.0
	mirror.resolution_steps = 0
	assert_float(mirror._update_resolution_scale(2.0)).is_equal_approx(4.0, 1e-4)
	var huge: Vector2i = mirror._compute_quantized_direct_size(Vector2i(2560, 1440), Vector2(2560, 1440), true, true)
	assert_int(huge.x).is_less_equal(Mirror3D.MAX_VIEWPORT_DIMENSION)
	assert_int(huge.y).is_less_equal(Mirror3D.MAX_VIEWPORT_DIMENSION)

	mirror.queue_free()


func test_fixed_resolution_fallback_uses_pixels_per_unit_and_full_uv() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	mirror.size = Vector2(3.0, 2.0)
	mirror.pixels_per_unit = 300
	mirror.dynamic_resolution = false
	MirrorManager.refresh_now()

	assert_that(mirror._target_viewport_size).is_equal(Vector2i(900, 600))
	assert_that(mirror._reflected_viewport_size).is_equal(Vector2i(900, 600))
	assert_that(mirror._pending_direct_uv_rect).is_equal(Mirror3D.FULL_UV_RECT)
	var shader_rect: Vector4 = mirror._shader_material.get_shader_parameter(&"direct_uv_rect")
	assert_that(shader_rect).is_equal(Vector4(0.0, 0.0, 1.0, 1.0))

	root.queue_free()


func test_cropped_frustum_matches_uncropped_world_projection_on_standard_and_mirrored_transforms() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var player: CharacterBody3D = root.get_node("Player")
	mirror.size = Vector2(5.0, 4.0)

	# Test 1: Front-facing off-center close-up on a non-square 5x4 m mirror.
	player.global_position = Vector3(1.1, 0.2, 1.6)
	player.rotation = Vector3(0.0, -0.22, 0.0)
	await get_tree().process_frame
	MirrorManager.refresh_now()
	_assert_cropped_and_uncropped_sample_same_point(mirror, Vector3(0.6, 1.8, -1.5))

	# Test 2: Back-facing off-center close-up (camera on the opposite side of the mirror plane).
	mirror.rotation = Vector3.ZERO
	await get_tree().process_frame
	MirrorManager.refresh_now()
	_assert_cropped_and_uncropped_sample_same_point(mirror, Vector3(0.6, 1.8, -1.5))

	# Test 3: Negative-determinant mirror transform (mirrored X scale = -1, flipping winding/FRONT_FACING).
	mirror.global_transform = Transform3D(
		Basis(
			Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0),
			Vector3(0.0, 0.0, -1.0)
		),
		Vector3(0.0, 1.5, 3.0)
	)
	assert_float(mirror._mirror_quad.global_basis.determinant()).is_less(0.0)
	player.global_position = Vector3(0.9, 0.3, 1.6)
	player.rotation = Vector3(0.0, -0.18, 0.0)
	await get_tree().process_frame
	MirrorManager.refresh_now()
	_assert_cropped_and_uncropped_sample_same_point(mirror, Vector3(0.5, 1.7, -1.5))

	root.queue_free()


func test_small_camera_rotation_keeps_viewport_size_stable_and_paused_frame_keeps_uv_rect() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var player: CharacterBody3D = root.get_node("Player")
	mirror.size = Vector2(2.0, 2.0)
	player.global_position = Vector3(0.0, 0.5, -1.0)
	await get_tree().process_frame
	MirrorManager.refresh_now()

	var initial_vp_size: Vector2i = mirror._mirror_viewport.size
	# Small 1.5-degree yaw rotation: footprint shifts by a few pixels, which pixel-bucket hysteresis absorbs.
	player.rotation.y = deg_to_rad(1.5)
	await get_tree().process_frame
	MirrorManager.refresh_now()
	assert_that(mirror._mirror_viewport.size).is_equal(initial_vp_size)

	# Off-screen always_active mirror falls back to uncropped FULL_UV_RECT (aspect-expanded) without collapsing.
	player.rotation.y = PI
	await get_tree().process_frame
	MirrorManager.refresh_now()
	assert_float(mirror._pending_direct_uv_rect.size.x).is_greater_equal(1.0 - 1e-4)
	assert_float(mirror._pending_direct_uv_rect.size.y).is_greater_equal(1.0 - 1e-4)

	# When set_direct_viewport_active(false) skips rendering, direct_uv_rect on the shader stays untouched.
	var applied_before: Rect2 = mirror._applied_direct_uv_rect
	mirror._pending_direct_uv_rect = Rect2(0.2, 0.2, 0.4, 0.4)
	mirror.set_direct_viewport_active(false)
	assert_that(mirror._applied_direct_uv_rect).is_equal(applied_before)

	root.queue_free()


func test_reflected_viewport_preserves_mirror_aspect_and_resizes_lazily() -> void:
	var root := await _build_nested_mirror_scene(
		Pigments.Pigment.YELLOW,
		Mirror3D.MirrorType.REVEAL,
		Pigments.Pigment.BLUE,
		Mirror3D.MirrorType.REVEAL
	)
	var inner_mirror: Mirror3D = root.get_node("InnerMirror")
	var outer_mirror: Mirror3D = root.get_node("OuterMirror")
	inner_mirror.size = Vector2(1.5, 3.0)
	inner_mirror.reflected_resolution_scale = 0.5
	MirrorManager.refresh_now()

	# InnerMirror is 1.5x3.0 (aspect 0.5): its reflected viewport size must match aspect ~0.5.
	var refl_aspect: float = float(inner_mirror._reflected_viewport_size.x) / float(inner_mirror._reflected_viewport_size.y)
	assert_float(refl_aspect).is_equal_approx(0.5, 0.02)

	var active_slot: int = inner_mirror.get_reflected_slot(Mirror3D.reflected_view_key([outer_mirror]))
	assert_int(active_slot).is_greater_equal(0)
	assert_that(inner_mirror._reflected_viewports[active_slot].size).is_equal(inner_mirror._reflected_viewport_size)

	# Unused reflected slots remain at their initial 400x400 size instead of wasting VRAM.
	var unused_slot: int = 7
	assert_int(unused_slot).is_not_equal(active_slot)
	assert_that(inner_mirror._reflected_viewports[unused_slot].size).is_equal(Vector2i(400, 400))

	# Cropping on outer_mirror must never alter outer_mirror._mirror_camera.global_position or basis.
	var expected_obs: Vector3 = outer_mirror.reflect_point(outer_mirror._reflection_observer_position(outer_mirror.player_cam))
	assert_vector(outer_mirror._mirror_camera.global_position).is_equal_approx(expected_obs, Vector3(1e-4, 1e-4, 1e-4))

	root.queue_free()


func _assert_cropped_and_uncropped_sample_same_point(mirror: Mirror3D, world_target: Vector3) -> void:
	var obs_pos: Vector3 = mirror._reflection_observer_position(mirror.player_cam)
	var quad_pos: Vector3 = mirror._mirror_quad.global_position
	var quad_right: Vector3 = mirror._mirror_quad.global_basis.x.normalized()
	var quad_up: Vector3 = mirror._mirror_quad.global_basis.y.normalized()
	var mirror_normal: Vector3 = mirror._mirror_quad.global_basis.z.normalized()
	var world_size: Vector2 = mirror.get_world_size()

	# Ray from reflected observer (mirror camera) to world_target intersects the mirror plane at bounce_pt.
	var cam_pos: Vector3 = mirror.reflect_point(obs_pos)
	var ray_dir: Vector3 = world_target - cam_pos
	var denom: float = ray_dir.dot(mirror_normal)
	assert_bool(absf(denom) > 1e-4).is_true()
	var t_hit: float = (quad_pos - cam_pos).dot(mirror_normal) / denom
	var bounce_pt: Vector3 = cam_pos + ray_dir * t_hit
	var rel_bounce: Vector3 = bounce_pt - quad_pos
	var lx: float = rel_bounce.dot(quad_right)
	var ly: float = rel_bounce.dot(quad_up)

	var signed_dist: float = (obs_pos - quad_pos).dot(mirror_normal)
	var front: bool = mirror._is_observer_front_facing(signed_dist)
	# Shader uv at bounce_pt on the mirror quad:
	var shader_uv := Vector2(
		(0.5 - lx / world_size.x) if front else (0.5 + lx / world_size.x),
		0.5 - ly / world_size.y
	)

	# Configure mirror camera with the cropped rect and verify world_size aspect match.
	var crop_rect: Rect2 = mirror._pending_direct_uv_rect
	var expected_vp_aspect: float = float(mirror._target_viewport_size.x) / float(mirror._target_viewport_size.y)
	var actual_world_aspect: float = (crop_rect.size.x * world_size.x) / (crop_rect.size.y * world_size.y)
	assert_float(actual_world_aspect).is_equal_approx(expected_vp_aspect, 1e-3)

	assert_bool(mirror._configure_mirror_camera(mirror._mirror_camera, obs_pos, mirror.cull_mask, true, crop_rect)).is_true()
	var cropped_cam_pos: Vector3 = mirror._mirror_camera.global_position
	var cropped_cam_basis: Basis = mirror._mirror_camera.global_basis

	# Compare against uncropped FULL_UV_RECT camera transform & projection:
	var cam_uv_cropped: Vector2 = _project_through_frustum_camera(
		mirror._mirror_camera,
		expected_vp_aspect,
		world_target
	)
	var shader_sample_uv := Vector2(
		(shader_uv.x - crop_rect.position.x) / crop_rect.size.x,
		(shader_uv.y - crop_rect.position.y) / crop_rect.size.y
	)
	assert_vector(Vector3(cam_uv_cropped.x, cam_uv_cropped.y, 0.0)).is_equal_approx(
		Vector3(shader_sample_uv.x, shader_sample_uv.y, 0.0),
		Vector3(1e-3, 1e-3, 1e-3)
	)

	# Verify camera position and perpendicular basis never change between cropped and uncropped.
	assert_bool(mirror._configure_mirror_camera(mirror._mirror_camera, obs_pos, mirror.cull_mask, true, Mirror3D.FULL_UV_RECT)).is_true()
	assert_vector(cropped_cam_pos).is_equal_approx(mirror._mirror_camera.global_position, Vector3(1e-5, 1e-5, 1e-5))
	assert_vector(cropped_cam_basis.z).is_equal_approx(mirror._mirror_camera.global_basis.z, Vector3(1e-5, 1e-5, 1e-5))


func _project_through_frustum_camera(cam: Camera3D, vp_aspect: float, world_pt: Vector3) -> Vector2:
	var local: Vector3 = cam.global_transform.affine_inverse() * world_pt
	var depth: float = -local.z
	var scale_to_near: float = cam.near / depth
	var near_x: float = local.x * scale_to_near
	var near_y: float = local.y * scale_to_near
	var near_w: float = cam.size
	var near_h: float = near_w / vp_aspect
	var u: float = (near_x - cam.frustum_offset.x) / near_w + 0.5
	var v: float = 0.5 - (near_y - cam.frustum_offset.y) / near_h
	return Vector2(u, v)


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
	var entity: PigmentEntity = _make_object()
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
	for body: CollisionObject3D in entity.bodies:
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
	for body: CollisionObject3D in entity.bodies:
		assert_bool(_has_layer(body.collision_layer, manifest_layer)).is_true()
		assert_bool(_has_layer(body.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_true()

	# A dissolve-mirror disables every collider body of the entity.
	var dissolve := Mirror3D.new()
	entity.set_mirror_link_state(dissolve, true, true)
	for body: CollisionObject3D in entity.bodies:
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


func test_child_pigment_entity_paints_parent_mesh() -> void:
	var root := Node3D.new()
	add_child(root)

	var crate := _make_mesh_instance("Crate", BoxMesh.new(), Vector3.ZERO)
	var entity := _add_pigment_child(crate, Pigments.Pigment.RED, false)
	root.add_child(crate)
	await get_tree().process_frame
	await get_tree().physics_frame

	assert_that(crate.get_script()).is_null()
	assert_object(entity.get_parent()).is_same(crate)
	var manifest_layer: int = Pigments.get_entity_layer(Pigments.Pigment.RED, false)
	assert_object(crate.material_override).is_same(PigmentEntity.PIGMENT_MATERIALS[Pigments.Pigment.RED])
	assert_int(crate.layers).is_equal(1 << (manifest_layer - 1))
	var collider: StaticBody3D = crate.get_node_or_null("Collider") as StaticBody3D
	assert_that(collider).is_not_null()
	assert_bool(_has_layer(collider.collision_layer, manifest_layer)).is_true()
	assert_bool(_has_layer(collider.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_true()
	assert_bool(entity.is_collidable()).is_true()

	root.queue_free()


func test_surface_material_overrides_shared_pigment_material() -> void:
	var root := Node3D.new()
	add_child(root)

	var block := _make_mesh_instance("Block", BoxMesh.new(), Vector3.ZERO)
	var entity := _attach_pigment_entity(block, Pigments.Pigment.BLUE, true)
	root.add_child(block)
	await get_tree().physics_frame

	var custom := StandardMaterial3D.new()
	custom.albedo_color = Color(0.4, 0.2, 0.1)
	entity.surface_material = custom
	entity._apply_layers_and_material()
	var hidden_layer: int = Pigments.get_entity_layer(Pigments.Pigment.BLUE, true)
	assert_object(block.material_override).is_same(custom)
	assert_int(block.layers).is_equal(1 << (hidden_layer - 1))

	# A custom look does not change which mirrors can affect the entity.
	var reveal := Mirror3D.new()
	reveal.pigment = Pigments.Pigment.BLUE
	reveal.mirror_type = Mirror3D.MirrorType.REVEAL
	entity.set_mirror_link_state(reveal, true, true)
	assert_bool(entity.is_affected()).is_true()
	assert_object(block.material_override).is_same(custom)

	entity.pigment = Pigments.Pigment.RED
	entity._apply_layers_and_material()
	assert_object(block.material_override).is_same(custom)
	assert_int(block.layers).is_equal(1 << (Pigments.get_entity_layer(Pigments.Pigment.RED, true) - 1))

	entity.surface_material = null
	entity._apply_layers_and_material()
	assert_object(block.material_override).is_same(PigmentEntity.PIGMENT_MATERIALS[Pigments.Pigment.RED])

	root.queue_free()
	reveal.free()


func test_plain_parent_pigment_child_paints_links_and_restores() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var interaction: Node = mirror.get_node("Interaction")
	(root.get_node("Front") as Node3D).global_position = Vector3(40, 1, 0)
	(root.get_node("Hidden") as Node3D).global_position = Vector3(-40, 1, 0)

	var host := Node3D.new()
	host.name = "Prop"
	root.add_child(host)
	host.global_position = Vector3(0, 1, 0.5)
	var mesh := _make_mesh_instance("Crate", BoxMesh.new(), Vector3.ZERO)
	var original_layers: int = mesh.layers
	var original_material: Material = mesh.material_override
	host.add_child(mesh)
	var entity := _add_pigment_child(host, Pigments.Pigment.BLUE, true)
	await get_tree().process_frame
	await get_tree().physics_frame
	interaction._refresh_tracked_entities()

	assert_object(entity.get_parent()).is_same(host)
	var hidden_layer: int = Pigments.get_entity_layer(Pigments.Pigment.BLUE, true)
	assert_object(mesh.material_override).is_same(PigmentEntity.PIGMENT_MATERIALS[Pigments.Pigment.BLUE])
	assert_int(mesh.layers).is_equal(1 << (hidden_layer - 1))
	var collider: StaticBody3D = host.get_node_or_null("Collider") as StaticBody3D
	assert_that(collider).is_not_null()
	assert_bool(entity.is_collidable()).is_false()

	await _wait_for_link_eval(interaction)
	assert_bool(entity.is_linked()).is_true()
	assert_bool(entity.is_affected()).is_true()
	assert_bool(entity.is_collidable()).is_true()
	assert_bool(_has_layer(collider.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_true()

	host.remove_child(entity)
	entity.free()
	assert_object(mesh.material_override).is_same(original_material)
	assert_int(mesh.layers).is_equal(original_layers)
	assert_that(host.get_node_or_null("Collider")).is_same(collider)
	assert_int(collider.collision_layer).is_equal(1)
	assert_int(collider.collision_mask).is_equal(1)

	root.queue_free()


func test_later_pigment_sibling_does_not_repaint() -> void:
	var root := Node3D.new()
	add_child(root)
	var mesh := _make_mesh_instance("Crate", BoxMesh.new(), Vector3.ZERO)
	root.add_child(mesh)
	var first := _add_pigment_child(root, Pigments.Pigment.RED, false)
	var second := _add_pigment_child(root, Pigments.Pigment.BLUE, false)
	await get_tree().process_frame
	await get_tree().physics_frame

	assert_object(mesh.material_override).is_same(PigmentEntity.PIGMENT_MATERIALS[Pigments.Pigment.RED])
	var warnings := second._get_configuration_warnings()
	assert_int(warnings.size()).is_equal(1)
	assert_bool(warnings[0].contains("already colors")).is_true()

	root.queue_free()


func test_unibuilder_mesh_uses_pigment_layers_and_links() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var interaction: Node = mirror.get_node("Interaction")
	(root.get_node("Front") as Node3D).global_position = Vector3(40, 1, 0)
	(root.get_node("Hidden") as Node3D).global_position = Vector3(-40, 1, 0)

	var carved := UBMeshInstance3D.new()
	carved.name = "Carved"
	carved.mesh_data = UBPrimitives.make_cube()
	carved.collision_mode = UBMeshInstance3D.CollisionMode.CONVEX
	var entity := _add_pigment_child(carved, Pigments.Pigment.BLUE, true)
	root.add_child(carved)
	carved.global_position = Vector3(0, 1, 0.5)
	await get_tree().physics_frame
	interaction._refresh_tracked_entities()

	assert_bool(carved.get_script() != PIGMENT_ENTITY_SCRIPT).is_true()
	assert_object(entity.get_parent()).is_same(carved)
	assert_object(carved.material_override).is_same(PigmentEntity.PIGMENT_MATERIALS[Pigments.Pigment.BLUE])
	var hidden_layer: int = Pigments.get_entity_layer(Pigments.Pigment.BLUE, true)
	assert_bool(_has_layer(carved.layers, hidden_layer)).is_true()
	assert_bool(_has_layer(carved.collision_layer, hidden_layer)).is_true()
	assert_bool(_has_layer(carved.collision_layer, 1)).is_false()
	assert_bool(_has_layer(carved.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_false()

	var body: StaticBody3D = carved.get_node_or_null("_UBCollision") as StaticBody3D
	assert_that(body).is_not_null()
	assert_bool(_has_layer(body.collision_layer, hidden_layer)).is_true()
	assert_bool(_has_layer(body.collision_layer, 1)).is_false()
	assert_that(carved.get_node_or_null("Collider")).is_null()
	assert_bool(entity.is_collidable()).is_false()

	await _wait_for_link_eval(interaction)
	assert_bool(entity.is_linked()).is_true()
	assert_bool(entity.is_affected()).is_true()
	assert_bool(entity.is_collidable()).is_true()
	assert_bool(_has_layer(carved.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_true()
	assert_bool(_has_layer(body.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_true()
	assert_bool(_has_layer(carved.collision_layer, 1)).is_false()
	assert_bool(_has_layer(body.collision_layer, 1)).is_false()

	root.queue_free()


func test_mirror_finds_player_without_exports() -> void:
	var root := await _build_link_scene()
	var mirror: Mirror3D = root.get_node("Mirror")
	var player: CharacterBody3D = root.get_node("Player")
	var hidden: PigmentEntity = root.get_node("Hidden")
	var interaction: Node = mirror.get_node("Interaction")
	(root.get_node("Front") as Node3D).global_position = Vector3(40, 1, 0)

	mirror.player = null
	mirror.player_cam = null
	mirror._resolve_player_and_camera()
	assert_object(mirror.player).is_same(player)
	assert_object(mirror.player_cam).is_same(player.get_node("CamHolder/Camera3D"))

	interaction._refresh_tracked_entities()
	await _wait_for_link_eval(interaction)
	assert_bool(hidden.is_linked()).is_true()

	root.queue_free()


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


func _add_pigment_child(host: Node3D, pigment: Pigments.Pigment, is_hidden: bool) -> PigmentEntity:
	var child := Node3D.new()
	child.name = "Pigment"
	child.set_script(PIGMENT_ENTITY_SCRIPT)
	var entity := child as PigmentEntity
	entity.pigment = pigment
	entity.hidden_entity = is_hidden
	host.add_child(child)
	return entity


func _wait_frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().process_frame


func _has_layer(mask: int, layer: int) -> bool:
	return (mask & (1 << (layer - 1))) != 0


## The old object prefab: a pigment entity, a box mesh, a static collider, and an on-screen notifier.
func _make_object() -> PigmentEntity:
	var entity := Node3D.new()
	entity.set_script(PIGMENT_ENTITY_SCRIPT)
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	mesh.mesh = BoxMesh.new()
	entity.add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	body.collision_mask = 2
	mesh.add_child(body)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.name = "VisibleOnScreenNotifier3D"
	notifier.layers = 1024
	notifier.aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	entity.add_child(notifier)
	var pigment_entity := entity as PigmentEntity
	notifier.screen_entered.connect(pigment_entity._on_visible_on_screen_notifier_3d_screen_entered)
	notifier.screen_exited.connect(pigment_entity._on_visible_on_screen_notifier_3d_screen_exited)
	return pigment_entity


func _spawn_object(
	parent: Node,
	pigment: Pigments.Pigment,
	is_hidden: bool,
	position: Vector3
) -> PigmentEntity:
	var entity: PigmentEntity = _make_object()
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


## Godot builds one directional shadow cascade from a centered frustum (Projection.get_fov), ignoring
## the mirror camera's frustum offset. These helpers rebuild that cascade the way
## RendererSceneCull::_light_instance_setup_directional_shadow does for MirrorSun's single cascade,
## including the extra map width from MirrorSun's minimum sun angle.
func _assert_shadow_corners_inside_cascade(
	mirror: Mirror3D,
	camera: Camera3D,
	viewport_size: Vector2i,
	observer: Vector3
) -> void:
	var sphere: Dictionary = _orthogonal_cascade_sphere(camera, viewport_size)
	var center: Vector3 = sphere["center"]
	var radius: float = sphere["radius"]
	var proj_distance: float = absf((observer - mirror.get_mirror_origin()).dot(mirror.get_mirror_normal()))
	var behind_glass: float = minf(camera.far - 0.05, proj_distance + 20.0)
	var depths: Array[float] = [camera.near, behind_glass]
	for depth: float in depths:
		for corner: Vector3 in _off_axis_frustum_corners(camera, viewport_size, depth):
			assert_float(corner.distance_to(center)).is_less_equal(radius + 0.05)


func _orthogonal_cascade_sphere(camera: Camera3D, viewport_size: Vector2i) -> Dictionary:
	var aspect: float = float(viewport_size.x) / maxf(float(viewport_size.y), 1.0)
	var keep_width: bool = camera.keep_aspect == Camera3D.KEEP_WIDTH
	var proj := Projection.create_frustum_aspect(
		camera.size,
		aspect,
		camera.frustum_offset,
		camera.near,
		camera.far,
		keep_width
	)
	# The shadow split uses the full camera range because MirrorSun's max distance is farther than far.
	var cascade := Projection.create_perspective(proj.get_fov(), proj.get_aspect(), proj.get_z_near(), proj.get_z_far(), true)
	var z_near: float = cascade.get_z_near()
	var z_far: float = cascade.get_z_far()
	var near_half: Vector2 = cascade.get_viewport_half_extents()
	var far_half: Vector2 = near_half * (z_far / z_near)
	var forward: Vector3 = -camera.global_basis.z
	var right_axis: Vector3 = camera.global_basis.x
	var up_axis: Vector3 = camera.global_basis.y
	var mid_depth: float = (z_near + z_far) * 0.5
	var center: Vector3 = camera.global_position + forward * mid_depth
	var far_corner: Vector3 = (
		camera.global_position
		+ forward * z_far
		+ right_axis * far_half.x
		+ up_axis * far_half.y
	)
	var radius: float = center.distance_to(far_corner)
	var texture_size: float = float(ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/size",
		8192
	))
	radius *= texture_size / (texture_size - 2.0)
	# Godot widens the shadow map by the sun's angular size so the off-axis mirror still lands inside it.
	var z_range: float = radius * 2.0 + MirrorSun.SHADOW_PANCAKE_SIZE
	var expand: float = tan(deg_to_rad(MirrorSun.MIN_ANGULAR_DISTANCE)) * z_range
	return {"center": center, "radius": radius + expand}


func _off_axis_frustum_corners(camera: Camera3D, viewport_size: Vector2i, depth: float) -> PackedVector3Array:
	var aspect: float = float(viewport_size.x) / maxf(float(viewport_size.y), 1.0)
	var half_w: float
	var half_h: float
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		half_w = camera.size * 0.5
		half_h = camera.size / aspect * 0.5
	else:
		half_h = camera.size * 0.5
		half_w = camera.size * aspect * 0.5
	var left: float = -half_w + camera.frustum_offset.x
	var right: float = half_w + camera.frustum_offset.x
	var bottom: float = -half_h + camera.frustum_offset.y
	var top: float = half_h + camera.frustum_offset.y
	var scale: float = depth / camera.near
	var forward: Vector3 = -camera.global_basis.z
	var corners := PackedVector3Array()
	var xs := PackedFloat32Array([left, right])
	var ys := PackedFloat32Array([bottom, top])
	for x: float in xs:
		for y: float in ys:
			corners.append(
				camera.global_position
				+ forward * depth
				+ camera.global_basis.x * (x * scale)
				+ camera.global_basis.y * (y * scale)
			)
	return corners
