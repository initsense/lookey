class_name Pigments
extends RefCounted
## Single source of truth for the pigment system: the pigment→layer and
## pigment→color tables shared by Mirror3D and pigment.gd, plus the bitmask
## helper for layer properties.

enum Pigment { WHITE, RED, BLUE, GREEN, YELLOW, VIOLET, ORANGE }

## Layer shift for the "invisible"/reveal variant of a pigment.
const INVISIBLE_SHIFT: int = 10


## Base render/collision layer of each pigment (without INVISIBLE_SHIFT).
const LAYERS: Dictionary[Pigment, int] = {
	Pigment.WHITE: 1,
	Pigment.RED: 3,
	Pigment.BLUE: 4,
	Pigment.GREEN: 5,
	Pigment.YELLOW: 6,
	Pigment.VIOLET: 7,
	Pigment.ORANGE: 8,
}


## Albedo color of each pigment material.
const COLORS: Dictionary[Pigment, Color] = {
	Pigment.WHITE: Color(1, 1, 1),
	Pigment.RED: Color(1, 0, 0),
	Pigment.BLUE: Color(0, 0, 1),
	Pigment.GREEN: Color(0, 1, 0),
	Pigment.YELLOW: Color(1, 1, 0),
	Pigment.VIOLET: Color(1, 0, 1),
	Pigment.ORANGE: Color(1, 0.5, 0),
}
