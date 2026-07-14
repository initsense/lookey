class_name Utils
extends Node3D


func shoot_raycast(from: Vector3, to: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result:
		print("Hit: ", result.collider.name)
	else:
		print("Nothing hit")
