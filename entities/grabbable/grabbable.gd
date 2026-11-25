@tool
class_name GrabbableEntity
extends Grabbable
## Lets the player pick up the object this node belongs to, and optionally carry it even while a mirror makes it non-solid.

@export_category("Mirrors")
## The player can also pick this object up while a mirror has made it non-solid. That covers a dissolved manifest object and a hidden object that no reveal-mirror is showing. The object stays non-solid: the player finds it with the crosshair and walks through it.
@export var overrides_mirrors: bool = false:
	set(value):
		if overrides_mirrors == value:
			return
		overrides_mirrors = value
		_notify_owner()


func _ready() -> void:
	if editor_description.is_empty():
		editor_description = "Lets the player pick up the object this node belongs to, even across mirror states when Overrides Mirrors is on."
	super._ready()
	_notify_owner.call_deferred()


func _notify_owner() -> void:
	var entity := _owning_entity()
	if entity != null:
		entity.notify_grabbable_changed()


## The pigment entity that colors the object this node belongs to.
func _owning_entity() -> PigmentEntity:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor is PigmentEntity:
			return cursor as PigmentEntity
		for child: Node in cursor.get_children():
			if child is PigmentEntity and (child as PigmentEntity)._controlled_root() == cursor:
				return child as PigmentEntity
		cursor = cursor.get_parent()
	return null
