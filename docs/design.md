# Lookey

First-person puzzle game about mirrors. This is the living design document. When gameplay changes, update this file in the same change.

## Player

You inhabit a body and look through its eyes. Movement is on foot: idle, walk, and in the air, with gravity while falling. The mouse aims the view. Captured mouse can be released. Field of view can be narrowed or widened, and it opens slightly while walking. The head bobs and tilts with movement.

The current space is the tutorial.

## Pigments

Objects and mirrors carry a pigment. The pigments are white, red, blue, green, yellow, violet, and orange. A pigment is both a color and a place in the world: each one owns a render layer and a collision layer, so the game can show or hide a color without hiding the rest of the scene.

An object may be invisible. An invisible object leaves its pigment's ordinary layer and moves to that pigment's hidden layer, ten layers higher. It is still there. A normal view does not show it.

White has no hidden form. A white object always stays on the white layer, even when marked invisible.

## Mirrors

A mirror is a flat surface. It shows the world reflected across its plane, through a camera that copies the player's view. The frame is colored with the mirror's pigment. Farther mirrors draw at a lower resolution. Past a freeze distance, the reflection stops updating.

The player's own view never shows hidden layers. Every mirror does: invisible objects of any color appear in any mirror's glass.

Each mirror is one of three types.

- **Vanilla.** A reflection that includes hidden objects. The pigment only colors the frame.
- **Reveal.** Currently behaves like Vanilla.
- **Dissolve.** The reflection omits the mirror's pigment. Objects of that color are cut out of the reflected view.

Whether a reflected object actually reaches the player's eye is a question of the glass itself: the mirror must be on screen, the object must sit within the mirror's range, and some part of the object must have a clear path to the camera that bounces off the physical mirror, not the infinite plane.

## Open

The tutorial is the only space. Puzzle goals, beyond looking and moving, are not designed yet.

Intended but not implemented: only a reveal mirror should show hidden objects, and only those of its own pigment. Vanilla mirrors would then show the world as the player sees it. A white reveal mirror would reveal nothing, since white has no hidden form.
