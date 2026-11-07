class_name Pigments
extends RefCounted
## Single source of truth for the pigment system: the pigment→layer and
## pigment→color tables shared by Mirror3D and PigmentEntity, plus
## compatibility and mirror cull-mask helpers.


enum Pigment { WHITE, RED, BLUE, GREEN, YELLOW, VIOLET, ORANGE }

## Layer shift for the hidden-entity variant of a pigment.
const INVISIBLE_SHIFT: int = 10

const WORLD_GEOMETRY_LAYER: int = 1
const PLAYER_LAYER: int = 2
const ENTITY_COLLIDER_LAYER: int = 12

## Manifest pigment layers 3..9 (red..white).
const MANIFEST_PIGMENT_MASK: int = (
	(1 << 2) | (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6) | (1 << 7) | (1 << 8)
)

## Hidden pigment layers 13..19.
const HIDDEN_PIGMENT_MASK: int = (
	(1 << 12) | (1 << 13) | (1 << 14) | (1 << 15) | (1 << 16) | (1 << 17) | (1 << 18)
)

## Real-world occlusion: world geometry + manifest pigment layers.
const REAL_WORLD_OCCLUSION_MASK: int = (1 << (WORLD_GEOMETRY_LAYER - 1)) | MANIFEST_PIGMENT_MASK

## Reflected-world occlusion candidate bits (intersected with mirror.cull_mask).
const REFLECTED_OCCLUSION_MASK: int = (
	(1 << (WORLD_GEOMETRY_LAYER - 1)) | MANIFEST_PIGMENT_MASK | HIDDEN_PIGMENT_MASK
)


## Base render/collision layer of each pigment (without INVISIBLE_SHIFT).
const LAYERS: Dictionary[Pigment, int] = {
	Pigment.WHITE: 9,
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


## 3-bit RYB primary color mask for each pigment (Red = 1, Yellow = 2, Blue = 4).
const PRIMARY_BITS: Dictionary[Pigment, int] = {
	Pigment.RED: 0b001,
	Pigment.YELLOW: 0b010,
	Pigment.BLUE: 0b100,
	Pigment.ORANGE: 0b011,
	Pigment.GREEN: 0b110,
	Pigment.VIOLET: 0b101,
	Pigment.WHITE: 0b111,
}


## Maps a 3-bit RYB primary color mask back to its matching Pigment.
const BITS_TO_PIGMENT: Dictionary[int, Pigment] = {
	0b001: Pigment.RED,
	0b010: Pigment.YELLOW,
	0b100: Pigment.BLUE,
	0b011: Pigment.ORANGE,
	0b110: Pigment.GREEN,
	0b101: Pigment.VIOLET,
	0b111: Pigment.WHITE,
}


## Combines two pigments using RYB additive color mixing (for example, Yellow + Blue = Green).
static func mix_pigments(a: Pigment, b: Pigment) -> Pigment:
	var combined_bits: int = PRIMARY_BITS.get(a, 0b111) | PRIMARY_BITS.get(b, 0b111)
	return BITS_TO_PIGMENT.get(combined_bits, Pigment.WHITE)


## Combines the pigments of all mirrors along a reflection chain [innermost, ..., outer].
static func mix_mirror_chain_pigment(chain: Array) -> Pigment:
	if chain.is_empty():
		return Pigment.WHITE
	var first_mirror: Object = chain[0]
	var mixed: Pigment = first_mirror.get(&"pigment") as Pigment if first_mirror != null else Pigment.WHITE
	for i: int in range(1, chain.size()):
		var next_mirror: Object = chain[i]
		if next_mirror != null:
			mixed = mix_pigments(mixed, next_mirror.get(&"pigment") as Pigment)
	return mixed


## Returns true when the mirror pigment can affect the entity pigment.
static func is_compatible(mirror_pigment: Pigment, entity_pigment: Pigment) -> bool:
	return (
		mirror_pigment == Pigment.WHITE
		or entity_pigment == Pigment.WHITE
		or mirror_pigment == entity_pigment
	)


## Returns the 1-based render/collision layer for a pigment entity state.
static func get_entity_layer(pigment: Pigment, is_hidden: bool) -> int:
	var layer: int = LAYERS[pigment]
	if is_hidden:
		layer += INVISIBLE_SHIFT
	return layer


## Returns true when a linked entity is eligible for the mirror's effect.
static func is_entity_eligible(
	mirror_pigment: Pigment,
	is_reveal_mirror: bool,
	entity_pigment: Pigment,
	is_entity_hidden: bool
) -> bool:
	if is_reveal_mirror != is_entity_hidden:
		return false
	return is_compatible(mirror_pigment, entity_pigment)


## Builds the SubViewport camera cull mask for a reveal-mirror or dissolve-mirror.
static func compute_mirror_cull_mask(mirror_pigment: Pigment, is_reveal_mirror: bool) -> int:
	var mask: int = (
		(1 << (WORLD_GEOMETRY_LAYER - 1))
		| (1 << (PLAYER_LAYER - 1))
		| MANIFEST_PIGMENT_MASK
	)

	if is_reveal_mirror:
		for pigment: Pigment in Pigment.values():
			if is_compatible(mirror_pigment, pigment):
				mask |= 1 << (get_entity_layer(pigment, true) - 1)
	else:
		for pigment: Pigment in Pigment.values():
			if is_compatible(mirror_pigment, pigment):
				mask &= ~(1 << (get_entity_layer(pigment, false) - 1))

	return mask
