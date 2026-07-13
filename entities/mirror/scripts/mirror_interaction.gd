extends Node3D

var is_object_visible_to_player: bool = false
var is_magic_happening: bool = false
var reflection_notifier: VisibleOnScreenNotifier3D
var is_mirror_visible: bool

@onready var _mirror: Mirror3D = get_parent()
@onready var original_notifier: VisibleOnScreenNotifier3D = \
	_mirror.object_to_reflect.get_node("VisibleOnScreenNotifier3D")
@onready var original_mesh: MeshInstance3D = \
	_mirror.object_to_reflect.get_node("MeshInstance3D")
@onready var reflection_mesh: MeshInstance3D = original_mesh


func _ready() -> void:
	_create_reflection()


func _physics_process(_delta: float) -> void:
	if not _mirror.player:
		return

	#if _mirror.mirror_type == Mirror3D.MirrorType.VANILLA:
		#return
	
	if not is_mirror_visible:
		return
	
	_update_reflection_transform(original_mesh, reflection_mesh)
	
	
	if raycast_from_vertices(original_mesh, _mirror._mirror_camera.global_position):
		if raycast_from_vertices(reflection_mesh, _mirror.player_cam.global_position):
			if not is_magic_happening:
				is_magic_happening = true
				print("✅ Visible reflection!!!")
	elif is_magic_happening:
		is_magic_happening = false
		print("❌ Reflection not visible")
		return


func _create_reflection() -> void:
	
	reflection_mesh = MeshInstance3D.new()
	add_child(reflection_mesh)
	reflection_mesh.layers = 1 << 9
	
	reflection_mesh.mesh = original_mesh.mesh
	reflection_mesh.transform = original_mesh.transform
	
	reflection_notifier = VisibleOnScreenNotifier3D.new()
	reflection_mesh.add_child(reflection_notifier)
	# Copy only the data you need
	reflection_notifier.aabb = original_notifier.aabb
	# make it visible only to player (set to layer 10)
	reflection_notifier.layers = 1 << 9

	_update_reflection_transform(original_mesh, reflection_mesh)

	reflection_notifier.screen_entered.connect(
		_on_mirror_notifier_entered)

	reflection_notifier.screen_exited.connect(
		_on_mirror_notifier_exited)


func _update_reflection_transform(original, reflection) -> void:
	reflection.global_transform = _reflect_across_mirror(
		original.global_transform
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


func raycast_from_vertices(mesh_instance: MeshInstance3D, target_point: Vector3) -> bool:
	
	var mesh: Mesh = mesh_instance.mesh
	var global_transform = mesh_instance.global_transform
	var space_state = mesh_instance.get_world_3d().direct_space_state
	
	for s in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		
		for local_vertex in vertices:
			var world_vertex = global_transform * local_vertex
			
			var query = PhysicsRayQueryParameters3D.create(world_vertex, target_point)
			# Optional: exclude the mesh_instance's own body if it has a collider
			# query.exclude = [mesh_instance.get_parent()]  # or whatever the physics body is
			
			var result = space_state.intersect_ray(query)
			
			if result:
				print("Hit: ", result.collider, " at ", result.position)
				#print("WTFFF")
				return false
			#else:
				#print("Clear line of sight from ", world_vertex, " to target")
	print("✅✅")
	return true


#region SIGNALS
func _on_mirror_notifier_entered() -> void:
	#print("✅ REFLECTION PROXY ENTERED")
	is_object_visible_to_player = true

func _on_mirror_notifier_exited() -> void:
	#print("❌ REFLECTION PROXY EXITED")
	is_object_visible_to_player = false


func _on_mirror_notifier_screen_entered() -> void:
	is_mirror_visible = true
	#print("✅ Seen")

func _on_mirror_notifier_screen_exited() -> void:
	is_mirror_visible = false
	#print("❌ Not seen")
#endregion
