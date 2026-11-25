extends GdUnitTestSuite
## Pickup volumes on pigment entities, and how mirrors keep the solid collider.


const PLAYER_SCENE := preload("res://entities/player/player.tscn")
const MIRROR_SCENE := preload("res://entities/mirror/mirror.tscn")
const PIGMENT_ENTITY_SCRIPT := preload("res://scripts/pigment_entity.gd")

var _root: Node3D


func after_test() -> void:
	for action_name: String in ["interact", "throw", "rotate_held", "hold_nearer", "hold_farther"]:
		if InputMap.has_action(action_name) and Input.is_action_pressed(action_name):
			Input.action_release(action_name)
	if is_instance_valid(_root):
		_root.free()
	_root = null


func test_without_a_grabbable_child() -> void:
	var rig := await _make_rig(false, false, false)
	var entity: PigmentEntity = rig["entity"]
	var grab: PlayerGrab = rig["grab"]
	assert_object(_grab_area(entity)).is_null()
	assert_object(grab.target_under_crosshair()).is_null()
	assert_int((rig["player"] as CharacterBody3D).collision_layer).is_equal(2)
	assert_int((rig["player"] as CharacterBody3D).collision_mask).is_equal(2049)


func test_solid_grabbable_carries_turns_and_drops() -> void:
	var rig := await _make_rig(true, false, false)
	var grab: PlayerGrab = rig["grab"]
	var body: RigidBody3D = rig["body"]
	var camera: Camera3D = rig["view"]
	var cam_holder: SpringArm3D = rig["camera"]
	var entity: PigmentEntity = rig["entity"]
	var forward := -camera.global_basis.z
	var area := _grab_area(entity) as Grabbable
	assert_object(area).is_not_null()
	assert_bool(area.is_class("CollisionObject3D")).is_false()
	assert_int(area._get_configuration_warnings().size()).is_equal(0)
	assert_int(entity._get_configuration_warnings().size()).is_equal(0)
	assert_int(grab.grab_mask).is_equal(524288)
	assert_int(area.get_grab_area().collision_layer).is_equal(524288)
	assert_object(grab.target_under_crosshair()).is_not_null()
	var start_distance := body.global_position.distance_to(camera.global_position)
	assert_bool(_has_layer(body.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_true()
	assert_bool(_has_layer(body.collision_layer, Pigments.WORLD_GEOMETRY_LAYER)).is_false()
	assert_bool(_has_layer(body.collision_mask, Pigments.WORLD_GEOMETRY_LAYER)).is_true()
	assert_bool(_has_layer(body.collision_mask, Pigments.ENTITY_COLLIDER_LAYER)).is_true()
	assert_bool(_walker_hits(body.global_position)).is_true()

	await _press_action("interact")
	assert_bool(grab.is_holding()).is_true()
	var moved := false
	for _step: int in 8:
		await get_tree().physics_frame
		if body.global_position.distance_to(camera.global_position) < start_distance - 0.2:
			moved = true
			break
	assert_bool(moved).is_true()

	var held_basis := body.global_transform.basis
	for _step: int in 5:
		await get_tree().physics_frame
	assert_float(_basis_angle(held_basis, body.global_transform.basis)).is_less(0.02)

	Input.action_press("rotate_held")
	var yaw_before := cam_holder.rotation.y
	cam_holder.apply_look_motion(Vector2(90, 0))
	assert_float(absf(wrapf(cam_holder.rotation.y - yaw_before, -PI, PI))).is_less(0.001)
	grab.apply_mouse_look(Vector2(80, 0))
	await get_tree().physics_frame
	var yawed := body.global_transform.basis
	assert_float(_basis_angle(held_basis, yawed)).is_greater(0.05)
	grab.apply_mouse_look(Vector2(0, 80))
	await get_tree().physics_frame
	assert_float(_basis_angle(yawed, body.global_transform.basis)).is_greater(0.05)
	Input.action_release("rotate_held")
	var look_before := cam_holder.rotation.y
	cam_holder.apply_look_motion(Vector2(90, 0))
	assert_float(absf(wrapf(cam_holder.rotation.y - look_before, -PI, PI))).is_greater(0.05)

	var carried_forward := body.global_position.dot(forward)
	await _release_action("interact")
	await get_tree().physics_frame
	await _press_action("interact")
	assert_bool(grab.is_holding()).is_false()
	assert_float(body.gravity_scale).is_equal(1.0)
	assert_bool(body.freeze).is_false()
	await _release_action("interact")
	var fell := false
	var rested := false
	for _step: int in 180:
		await get_tree().physics_frame
		if body.global_position.dot(forward) > carried_forward - 0.5 and body.global_position.y < 0.85:
			fell = true
		if fell and absf(body.linear_velocity.y) < 0.2 and body.global_position.y < 0.85:
			rested = true
			break
	assert_bool(fell).is_true()
	assert_bool(rested).is_true()
	assert_bool(body.freeze).is_false()


func test_dissolve_without_override_drops_a_held_object() -> void:
	var rig := await _make_rig(true, false, false)
	var entity: PigmentEntity = rig["entity"]
	var grab: PlayerGrab = rig["grab"]
	var body: RigidBody3D = rig["body"]
	var mirror := Mirror3D.new()
	await _press_action("interact")
	assert_bool(grab.is_holding()).is_true()
	entity.set_mirror_link_state(mirror, true, true)
	await get_tree().physics_frame
	assert_bool(grab.is_holding()).is_false()
	assert_float(body.gravity_scale).is_equal(1.0)
	assert_bool(entity.is_collidable()).is_false()
	assert_bool(_has_layer(body.collision_mask, Pigments.WORLD_GEOMETRY_LAYER)).is_true()
	assert_bool(_has_layer(body.collision_mask, Pigments.ENTITY_COLLIDER_LAYER)).is_false()
	assert_bool(_has_layer(body.collision_layer, Pigments.WORLD_GEOMETRY_LAYER)).is_false()
	assert_bool(_walker_hits(body.global_position)).is_false()
	var held_y := body.global_position.y
	var fell := false
	for _step: int in 60:
		await get_tree().physics_frame
		if body.global_position.y < held_y - 0.15:
			fell = true
			break
	assert_bool(fell).is_true()
	await _release_action("interact")
	mirror.free()


func test_unrevealed_hidden_without_override_cannot_be_grabbed() -> void:
	var rig := await _make_rig(true, false, true)
	var entity: PigmentEntity = rig["entity"]
	var grab: PlayerGrab = rig["grab"]
	assert_bool(entity.is_collidable()).is_false()
	assert_object(_grab_area(entity)).is_not_null()
	assert_object(grab.target_under_crosshair()).is_null()


func test_override_carries_a_non_solid_object_and_keeps_it_non_solid() -> void:
	var rig := await _make_rig(true, true, true)
	var entity: PigmentEntity = rig["entity"]
	var grab: PlayerGrab = rig["grab"]
	var body: RigidBody3D = rig["body"]
	var mirror := Mirror3D.new()
	assert_bool(entity.is_collidable()).is_false()
	assert_object(grab.target_under_crosshair()).is_not_null()
	assert_bool(_walker_hits(body.global_position)).is_false()

	await _press_action("interact")
	assert_bool(grab.is_holding()).is_true()
	assert_bool(entity.is_collidable()).is_false()
	assert_bool(_walker_hits(body.global_position)).is_false()

	entity.set_mirror_link_state(mirror, true, true)
	await get_tree().physics_frame
	assert_bool(grab.is_holding()).is_true()
	assert_bool(entity.is_collidable()).is_true()

	entity.set_mirror_link_state(mirror, false, false)
	await get_tree().physics_frame
	assert_bool(grab.is_holding()).is_true()
	assert_bool(entity.is_collidable()).is_false()
	assert_bool(_walker_hits(body.global_position)).is_false()

	await _release_action("interact")
	await get_tree().physics_frame
	await _press_action("interact")
	assert_bool(grab.is_holding()).is_false()
	assert_bool(entity.is_collidable()).is_false()
	assert_float(body.gravity_scale).is_equal(1.0)
	var held_y := body.global_position.y
	var fell := false
	for _step: int in 60:
		await get_tree().physics_frame
		if body.global_position.y < held_y - 0.15:
			fell = true
			break
	assert_bool(fell).is_true()
	assert_bool(entity.is_collidable()).is_false()
	assert_bool(_walker_hits(body.global_position)).is_false()
	await _release_action("interact")
	mirror.free()


func test_turning_the_solid_collider_back_on_does_not_unfreeze_a_resting_body() -> void:
	var rig := await _make_rig(true, false, false)
	var entity: PigmentEntity = rig["entity"]
	var body: RigidBody3D = rig["body"]
	var mirror := Mirror3D.new()
	assert_bool(body.freeze).is_true()
	entity.set_mirror_link_state(mirror, true, true)
	entity.set_mirror_link_state(mirror, false, false)
	await get_tree().physics_frame
	assert_bool(body.freeze).is_true()
	assert_bool(entity.is_collidable()).is_true()
	mirror.free()


func test_unibuilder_collision_turns_off_while_grabbable() -> void:
	_root = Node3D.new()
	add_child(_root)
	var carved := UBMeshInstance3D.new()
	carved.name = "Carved"
	carved.mesh_data = UBPrimitives.make_cube()
	carved.collision_mode = UBMeshInstance3D.CollisionMode.CONVEX
	var entity := Node3D.new()
	entity.set_script(PIGMENT_ENTITY_SCRIPT)
	carved.add_child(entity)
	var grab := GrabbableEntity.new()
	grab.name = "Grabbable"
	carved.add_child(grab)
	_root.add_child(carved)
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_int(carved.collision_mode).is_equal(UBMeshInstance3D.CollisionMode.NONE)
	assert_object(carved.get_node_or_null("_UBCollision")).is_null()
	var body := carved.get_node_or_null("Collider") as RigidBody3D
	assert_object(body).is_not_null()
	assert_object(grab.get_body()).is_same(body)
	carved.remove_child(grab)
	grab.free()
	await get_tree().process_frame
	await get_tree().physics_frame
	assert_int(carved.collision_mode).is_equal(UBMeshInstance3D.CollisionMode.CONVEX)
	assert_object(carved.get_node_or_null("_UBCollision")).is_not_null()
	assert_object(carved.get_node_or_null("Collider")).is_null()


func test_mirror_with_grabbable_moves_rotates_drops_and_keeps_linking() -> void:
	_root = Node3D.new()
	add_child(_root)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1 << (Pigments.WORLD_GEOMETRY_LAYER - 1)
	floor_body.collision_mask = floor_body.collision_layer
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40, 1, 40)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(floor_shape)
	_root.add_child(floor_body)

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	_root.add_child(player)
	player.global_position = Vector3.ZERO
	await get_tree().physics_frame
	var camera := player.get_node("CamHolder/Camera3D") as Camera3D
	var grab := player.get_node("Grab") as PlayerGrab
	var forward := -camera.global_basis.z

	var mirror: Mirror3D = MIRROR_SCENE.instantiate()
	mirror.pigment = Pigments.Pigment.YELLOW
	mirror.mirror_type = Mirror3D.MirrorType.REVEAL
	mirror.size = Vector2(2.0, 2.0)
	var grabbable := Grabbable.new()
	grabbable.name = "Grabbable"
	mirror.add_child(grabbable)
	_root.add_child(mirror)
	mirror.global_position = camera.global_position + forward * 3.0
	# Face the mirror's reflective +Z side back toward the player camera.
	mirror.look_at(mirror.global_position + forward * 5.0, Vector3.UP)

	var hidden_block := _make_entity()
	hidden_block.pigment = Pigments.Pigment.YELLOW
	hidden_block.hidden_entity = true
	_root.add_child(hidden_block)
	hidden_block.global_position = camera.global_position + forward * 1.5 + Vector3(0.5, 0.0, 0.0)

	for _step: int in 8:
		await get_tree().physics_frame

	var mirror_body := grabbable.get_body()
	assert_object(mirror_body).is_not_null()
	assert_int(grabbable._get_configuration_warnings().size()).is_equal(0)
	assert_int(grabbable.get_grab_area().collision_layer).is_equal(524288)
	var shape_node := mirror_body.get_node_or_null("Shape") as CollisionShape3D
	assert_object(shape_node).is_not_null()
	assert_vector((shape_node.shape as BoxShape3D).size).is_equal_approx(Vector3(2.0, 2.0, 0.1), Vector3(0.01, 0.01, 0.01))
	assert_bool(_has_layer(mirror_body.collision_layer, Pigments.WORLD_GEOMETRY_LAYER)).is_false()
	assert_bool(_has_layer(mirror_body.collision_layer, Pigments.ENTITY_COLLIDER_LAYER)).is_true()

	# Mirror's own Collider on layer 12 must not occlude reflections through its glass.
	assert_bool(hidden_block.is_linked()).is_true()
	assert_bool(hidden_block.is_affected()).is_true()

	# Move hidden block out of the way and grab the mirror.
	hidden_block.global_position = Vector3(20, 0, 20)
	await get_tree().physics_frame
	assert_object(grab.target_under_crosshair()).is_same(grabbable)
	var start_distance := mirror.global_position.distance_to(camera.global_position)
	await _press_action("interact")
	assert_bool(grab.is_holding()).is_true()
	var moved := false
	for _step: int in 10:
		await get_tree().physics_frame
		if mirror.global_position.distance_to(camera.global_position) < start_distance - 0.15:
			moved = true
			break
	assert_bool(moved).is_true()

	var basis_before := mirror.global_transform.basis
	Input.action_press("rotate_held")
	grab.apply_mouse_look(Vector2(80, 0))
	await get_tree().physics_frame
	assert_float(_basis_angle(basis_before, mirror.global_transform.basis)).is_greater(0.05)
	Input.action_release("rotate_held")

	await _release_action("interact")
	await get_tree().physics_frame
	await _press_action("interact")
	assert_bool(grab.is_holding()).is_false()
	await _release_action("interact")
	var drop_y := mirror.global_position.y
	var fell := false
	for _step: int in 90:
		await get_tree().physics_frame
		if mirror.global_position.y < drop_y - 0.15:
			fell = true
			break
	assert_bool(fell).is_true()


func test_plain_non_pigment_mesh_with_grabbable_is_grabbable() -> void:
	_root = Node3D.new()
	add_child(_root)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1 << (Pigments.WORLD_GEOMETRY_LAYER - 1)
	floor_body.collision_mask = floor_body.collision_layer
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40, 1, 40)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(floor_shape)
	_root.add_child(floor_body)

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	_root.add_child(player)
	player.global_position = Vector3.ZERO
	await get_tree().physics_frame
	var camera := player.get_node("CamHolder/Camera3D") as Camera3D
	var grab := player.get_node("Grab") as PlayerGrab
	var forward := -camera.global_basis.z

	var crate := MeshInstance3D.new()
	crate.mesh = BoxMesh.new()
	var grabbable := Grabbable.new()
	crate.add_child(grabbable)
	_root.add_child(crate)
	crate.global_position = camera.global_position + forward * 2.5
	for _step: int in 3:
		await get_tree().physics_frame

	assert_int(grabbable._get_configuration_warnings().size()).is_equal(0)
	assert_int(grabbable.get_grab_area().collision_layer).is_equal(524288)
	assert_object(grabbable.get_body()).is_not_null()
	assert_object(grab.target_under_crosshair()).is_same(grabbable)

	var start_distance := crate.global_position.distance_to(camera.global_position)
	await _press_action("interact")
	assert_bool(grab.is_holding()).is_true()
	var moved := false
	for _step: int in 10:
		await get_tree().physics_frame
		if crate.global_position.distance_to(camera.global_position) < start_distance - 0.1:
			moved = true
			break
	assert_bool(moved).is_true()
	await _release_action("interact")
	await get_tree().physics_frame
	await _press_action("interact")
	assert_bool(grab.is_holding()).is_false()
	await _release_action("interact")
	var drop_y := crate.global_position.y
	var fell := false
	for _step: int in 60:
		await get_tree().physics_frame
		if crate.global_position.y < drop_y - 0.15:
			fell = true
			break
	assert_bool(fell).is_true()


func test_csg_with_pigment_and_grabbable_entity_has_no_warnings() -> void:
	_root = Node3D.new()
	add_child(_root)
	var box := CSGBox3D.new()
	box.use_collision = true
	var pigment := Node3D.new()
	pigment.set_script(PIGMENT_ENTITY_SCRIPT)
	var grabbable := GrabbableEntity.new()
	box.add_child(pigment)
	box.add_child(grabbable)
	_root.add_child(box)
	await get_tree().process_frame
	await get_tree().physics_frame

	assert_bool(grabbable.is_class("CollisionObject3D")).is_false()
	assert_int((pigment as PigmentEntity)._get_configuration_warnings().size()).is_equal(0)
	assert_int(grabbable._get_configuration_warnings().size()).is_equal(0)


func test_grabbable_editor_action_toggles() -> void:
	var rig := await _make_rig(true, false, false)
	var grab: PlayerGrab = rig["grab"]
	var body: RigidBody3D = rig["body"]
	var entity: PigmentEntity = rig["entity"]
	var area := _grab_area(entity) as Grabbable

	# Reach override shorter than current distance blocks pickup until restored.
	area.reach_override = 1.0
	assert_object(grab.target_under_crosshair()).is_null()
	area.reach_override = 0.0
	assert_object(grab.target_under_crosshair()).is_same(area)

	# Disable pickup directly via toggle.
	area.can_be_picked_up = false
	assert_object(grab.target_under_crosshair()).is_null()
	area.can_be_picked_up = true
	assert_object(grab.target_under_crosshair()).is_same(area)

	# Pin horizontally and vertically (rotate-in-place), horizontal rotation only, freeze on release.
	area.can_move_horizontally = false
	area.can_move_vertically = false
	area.can_rotate_horizontally = true
	area.can_rotate_vertically = false
	area.can_throw = false
	area.release_mode = Grabbable.ReleaseMode.FREEZE

	var start_pos := body.global_position
	var start_basis := body.global_basis
	await _press_action("interact")
	await _release_action("interact")
	for _step: int in 5:
		await get_tree().physics_frame
	assert_float(body.global_position.distance_to(start_pos)).is_less(0.05)

	# Vertical mouse movement is ignored; horizontal spins cleanly.
	grab.apply_mouse_look(Vector2(0, 90))
	await get_tree().physics_frame
	assert_float(_basis_angle(start_basis, body.global_basis)).is_less(0.01)

	grab.apply_mouse_look(Vector2(90, 0))
	await get_tree().physics_frame
	assert_float(_basis_angle(start_basis, body.global_basis)).is_greater(0.05)

	# Throw is disabled so throw button keeps holding.
	await _press_action("throw")
	await _release_action("throw")
	assert_bool(grab.is_holding()).is_true()

	# Drop freezes in place.
	await _press_action("interact")
	await _release_action("interact")
	assert_bool(grab.is_holding()).is_false()
	assert_bool(body.freeze).is_true()


func _make_rig(grabbable: bool, overrides: bool, hidden: bool) -> Dictionary:
	_root = Node3D.new()
	add_child(_root)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1 << (Pigments.WORLD_GEOMETRY_LAYER - 1)
	floor_body.collision_mask = floor_body.collision_layer
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40, 1, 40)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(floor_shape)
	_root.add_child(floor_body)

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	_root.add_child(player)
	player.global_position = Vector3.ZERO

	var entity := _make_entity()
	entity.hidden_entity = hidden
	if grabbable:
		var grab := GrabbableEntity.new()
		grab.name = "Grabbable"
		grab.overrides_mirrors = overrides
		entity.add_child(grab)
	_root.add_child(entity)
	await get_tree().physics_frame
	var camera := player.get_node("CamHolder/Camera3D") as Camera3D
	var forward := -camera.global_basis.z
	entity.global_position = camera.global_position + forward * 3.0
	for _step: int in 3:
		await get_tree().physics_frame
	var body := _find_rigid_body(entity)
	return {
		"player": player,
		"grab": player.get_node("Grab") as PlayerGrab,
		"camera": player.get_node("CamHolder") as SpringArm3D,
		"view": camera,
		"entity": entity,
		"body": body,
	}


func _make_entity() -> PigmentEntity:
	var entity := Node3D.new()
	entity.set_script(PIGMENT_ENTITY_SCRIPT)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = BoxMesh.new()
	entity.add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "Collider"
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	entity.add_child(body)
	return entity as PigmentEntity


func _find_rigid_body(entity: PigmentEntity) -> RigidBody3D:
	var area := _grab_area(entity) as Grabbable
	if area != null:
		return area.get_body()
	return _find_rigid_under(entity)


func _find_rigid_under(node: Node) -> RigidBody3D:
	if node is RigidBody3D:
		return node as RigidBody3D
	for child: Node in node.get_children():
		var found := _find_rigid_under(child)
		if found != null:
			return found
	return null


func _grab_area(entity: PigmentEntity) -> Node:
	return _find_grabbable_under(entity)


func _find_grabbable_under(node: Node) -> Grabbable:
	if node is Grabbable:
		return node as Grabbable
	for child: Node in node.get_children():
		var found := _find_grabbable_under(child)
		if found != null:
			return found
	return null


func _walker_hits(where: Vector3) -> bool:
	var walker := CharacterBody3D.new()
	walker.collision_layer = 1 << (Pigments.PLAYER_LAYER - 1)
	walker.collision_mask = 2049
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	shape.shape = box
	walker.add_child(shape)
	_root.add_child(walker)
	walker.global_position = where + Vector3(-1.2, 0, 0)
	var hit := walker.move_and_collide(Vector3(2.0, 0, 0))
	walker.queue_free()
	return hit != null


func _has_layer(mask: int, layer: int) -> bool:
	return (mask & (1 << (layer - 1))) != 0


func _basis_angle(from: Basis, to: Basis) -> float:
	return from.get_rotation_quaternion().angle_to(to.get_rotation_quaternion())


func _press_action(action_name: String) -> void:
	Input.action_press(action_name)
	await get_tree().physics_frame


func _release_action(action_name: String) -> void:
	Input.action_release(action_name)
	await get_tree().physics_frame
