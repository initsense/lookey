lookey design document

# Entities

An entity is a game element that can interact with other entities.

There are different kinds of entities:

- Player
- Object

Every entity is either a manifest-entity or a hidden-entity.

## Manifest-entity

A manifest-entity is visible to the player in the real-world and can normally interact with other manifest entities.

The `player` is initially a manifest-entity, but during the gameplay it can become a hidden-entity.

> **Note.** Since the game is in first person, the player cannot directly see himself in the real-world. The player can only see a reflection of himself in a mirror.

## Hidden-entity

A hidden-entity is invisible in the real-world and does not normally interact with other entities.

# Pigments

Pigments are color properties possessed by entities and mirrors.

There are two types of pigments:

- Hue pigment
- White pigment

## Hue pigment

There are different hue pigments:

- Red
- Orange
- Yellow
- Green
- Blue
- Violet

## White pigment

White pigment is agnostic.

A white entity is compatible with every mirror pigment.

# Interactions

There are different types of interactions.

## Collision

A collision is a physical interaction between entities.

An entity with an enabled collider can block the movement of other entities and be blocked by them.

# World

There are two visible worlds:

- Real-world
- Reflected-world

## Real-world

The normal game world as it is.

## Reflected-world

The reflection of the real-world inside any mirror.

# Mirrors

A mirror is a special surface that can influence entities in the real-world, including objects and the player.

In order to be influenced by a mirror, an entity must first be `linked` to the player.

## Linking

An entity is `linked` to the player when some portion of its reflected geometry reaches the player through one or more visible mirrors.

This condition is evaluated independently of whether any mirror renders that entity.

An entity can be linked through nested reflections. The number of mirrors between the entity and the player does not affect the validity of the link.

> **Example.** Mirror A reflects Mirror B. Mirror B reflects an object. If the player sees Mirror A, and the object’s reflected geometry reaches the player through Mirror B and Mirror A, then the object is linked to the player.

An entity is linked only if its reflected geometry is not occluded, at any point along the reflection path, by an entity that is visible in the reflected-world of the mirror currently being evaluated.

An entity that is not rendered in a mirror cannot occlude other entities in that mirror’s reflected-world.

> **Example.** There is a manifest object in front of a hidden object, and a dissolve-mirror. From a certain angle, the player sees only the hidden object. Then, that hidden object is linked to the player, even if the manifest object would have occluded it if it were visible in the mirror.

There can be one or multiple entities linked to the player through the same mirror.

## Affected entity

A linked entity becomes an `affected-entity` when it is eligible for the effect of at least one mirror reflection chain through which it is linked.

When the player looks directly at a mirror (a 1-bounce reflection), that mirror reveals or dissolves entities compatible with its own pigment and mirror type.

When a mirror is seen reflected inside another mirror (a nested reflection chain `[InnerMirror, ..., OuterMirror]`), the nested mirror's effective pigment becomes the **RYB additive mix** of all mirrors along that reflection chain, while keeping the **innermost mirror's type** (`Reveal-mirror` or `Dissolve-mirror`):

- `Red + Yellow = Orange`
- `Yellow + Blue = Green`
- `Red + Blue = Violet`
- Mixing identical pigments preserves that pigment (`Yellow + Yellow = Yellow`).
- Mixing pigments that span all three primaries (`Red`, `Yellow`, and `Blue` — such as `Red + Green`, `Yellow + Violet`, `Blue + Orange`, two different secondary hues, or any pigment mixed with `White`) produces `White`.

> **Example.** When a yellow reveal-mirror is seen reflected inside a blue reveal-mirror, the nested mirror inside the blue mirror becomes a **green reveal-mirror** (with a green frame). Its glass reveals green (and white) hidden objects instead of yellow or blue ones, and any green hidden object linked through that nested reflection becomes collidable and interactable in the real-world.

Nested mirrors are drawn up to a configurable **render depth** (Project Settings, `lookey/mirrors/max_render_depth`, from 1 to 5, default 3). Depth 1 draws no mirror inside another mirror, depth 2 draws a mirror inside a mirror, and every extra level draws a mirror inside the glass of a mirror that is itself reflected inside the mirror the player looks at. Each extra level adds more views to render, so a higher depth costs more GPU time. The render depth only changes what is drawn: linking always follows reflection chains at least three mirrors deep, so a graphics setting never changes which entities are linked.

Glass drawn deeper mixes the pigments of every mirror in its chain with the same rule, so a chain covering `Red`, `Yellow` and `Blue` (or two different secondary hues) shows a **white** frame and behaves as a white mirror of the innermost mirror's type. Each mirror shows its own correct view in every mirror it appears in, even when several mirrors show it at the same time.

> **Example.** A red dissolve-mirror is seen inside a blue mirror, which is seen inside a yellow mirror. Inside the yellow mirror, the blue mirror's glass is green, and inside that green glass the red mirror's glass is a **white dissolve-mirror**: it dissolves every manifest hue object.

All affected entities are linked entities, but not all linked entities are affected entities.

Eligibility along a reflection chain depends on:

- The pigment of the entity.
- The mixed pigment of the mirrors along the reflection chain through which the reflected geometry reaches the player.
- The type of the innermost mirror in that reflection chain.

## Pigment compatibility

A hue mirror affects only entities with the same hue pigment or with white pigment.

A white mirror affects every hue entity and every white entity.

> **Example.** A blue-hidden-object linked through a yellow-reveal-mirror is not affected by that mirror, because their pigments do not match.

> **Example.** A manifest-object linked through a reveal-mirror is not affected by that mirror, because reveal-mirrors affect hidden entities.

## Mirror types

There are two types of mirrors:

- Reveal-mirror
- Dissolve-mirror

## Reveal-mirror

A reveal-mirror affects linked hidden entities.

Hidden entities can only be visible as reflections in the reflected-world of reveal-mirrors.

As long as a hidden entity stays linked through a reveal-mirror, that entity becomes interactable in the real-world.

The player can see the entity only in the mirror, but can interact with it in the real-world.

> **Example.** In an empty room, there is only a yellow-reveal-mirror. The player sees a yellow hidden-object reflected in the yellow-reveal-mirror. The player now understands that there is a hidden yellow object in the room. As long as the player continues seeing that reflection, the hidden yellow object stays invisible in the real-world, but acts like it was physically there: the player can interact and collide with it.

## Dissolve-mirror

A dissolve-mirror affects linked manifest entities.

A dissolve-mirror can make a manifest entity disappear in its reflected-world.

As long as a manifest entity stays linked through a dissolve-mirror, that entity cannot be interacted with in the real-world.

Any hue-manifest-entity can be affected by a white-dissolve-mirror.

Dissolve-mirrors disable interactions between affected entities and other entities.

Affected entities lose their colliders and cannot be lifted, pushed, carried, or activated.

> **Example.** In a room, there is only a blue manifest-object and a blue-dissolve-mirror. As long as the player keeps seeing the reflection of the object in the reflected-world of the blue-dissolve-mirror, the blue manifest-object loses its collider: the player cannot interact with it. When the reflection leaves the player view, the object returns to being collidable and interactable, unless its collider overlaps another entity.

# Interaction transitions

When an entity regains interaction after being affected by a dissolve-mirror, its collider is re-enabled.

If the re-enabled collider overlaps the player, the player is pushed away.

# Glossary

- **Entity**: A game element that can interact with other entities.
- **Player**: The entity controlled by the player.
- **Object**: An entity that can interact with other entities. An object can be either a manifest-entity or a hidden-entity.
- **Manifest-entity**: An entity that is visible and can normally interact in the real-world.
- **Hidden-entity**: An entity that is invisible and does not normally interact in the real-world.
- **Pigment**: A color property of an entity or mirror. Pigments can be hue pigments or white.
- **Hue pigment**: A specific color pigment, such as red, orange, yellow, green, blue, or violet.
- **White pigment**: An agnostic pigment that is compatible with every mirror pigment.
- **Real-world**: The normal game world as it is.
- **Reflected-world**: The reflection of the real-world inside any mirror.
- **Link**: The relationship between an entity and the player through one or more mirrors.
- **Linked entity**: An entity whose reflected geometry reaches the player through one or more mirrors.
- **Affected entity**: A linked entity that is eligible to receive the effect of at least one mirror through which it is linked.
- **Reveal-mirror**: A mirror that affects linked hidden entities by making them interactable in the real-world while keeping them invisible there.
- **Dissolve-mirror**: A mirror that affects linked manifest entities by making them non-interactive in the real-world while keeping them visible there.
- **Collider**: A physical boundary that allows an entity to block or be blocked by other entities.
