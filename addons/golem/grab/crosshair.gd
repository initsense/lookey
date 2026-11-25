class_name GrabCrosshair
extends Control
## The pickup mark in the middle of the view. The mouse ignores it.

## Hollow circle, the same circle filled, or that filled circle plus an outer ring.
enum Mark { HOLLOW, FILLED, HELD }

## Radius shared by the hollow circle and the filled circle, in pixels.
@export var inner_radius: float = 6.0
## Radius of the ring drawn outside the filled circle while something is held, in pixels.
@export var outer_radius: float = 12.0
## Thickness of the hollow circle and the outer ring, in pixels.
@export var line_width: float = 1.5

var mark: Mark = Mark.HOLLOW


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if editor_description.is_empty():
		editor_description = (
			"A hollow circle. It fills when you look at something you can pick up, "
			+ "and a ring appears outside it while you are holding something."
		)


## Switches the mark. The filled circle stays the same size as the hollow one.
func set_mark(next: Mark) -> void:
	if mark == next:
		return
	mark = next
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var color := Color.WHITE
	if mark == Mark.HOLLOW:
		draw_arc(center, inner_radius, 0.0, TAU, 48, color, line_width, true)
		return
	draw_circle(center, inner_radius, color)
	if mark == Mark.HELD:
		draw_arc(center, outer_radius, 0.0, TAU, 48, color, line_width, true)
