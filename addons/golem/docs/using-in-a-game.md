# Using Golem in a game

Instance `res://addons/golem/scenes/player.tscn`. The body starts on physics layer 1. The camera spring arm, the floor ray, the movement checks, and the ragdoll bones use physics layer 2 until a preset or the instance sets them. In this project that layer is named Environment. A floor on another layer is a floor the character will fall through. Can Climb Ledges, Can Climb Walls, Can Wall Run, Can Vault, Can Slide, Can Speed Fov, Can Turn Lean, and Can View Noise can be turned off on the player.

## Presets

A preset is the whole player configuration, saved as a `.tres` file. `res://addons/golem/presets/default.tres` matches the character as it ships. `res://addons/golem/presets/grounded.tres` is that same set with slide, wall climb, wall run, vault, and ledge hop turned off.

Select the Player node. At the top of the inspector, drop a preset onto the Golem preset row. Godot writes every value onto that instance: the mechanic exports, the exported keybinding strings, the camera mode, and the collision layers. The numbers are copied. Editing the preset file later leaves the instance as it was. `probe_mask` is the mask for the stair, ledge, vault, wall, and ragdoll floor checks, and for the floor ray. The layer checkboxes use the names from the game's Project Settings.

The jump's launch speed and its single gravity, the head bob, the speed-based view, the slide, the side wall run, and the vault are adapted from the [NOSHOT first-person controller](https://github.com/theRealUnd3rdog/Godot_Noshot_Controller) by [theRealUnd3rdog](https://github.com/theRealUnd3rdog). That project is MIT, Copyright (c) 2023 theRealUnd3rdog.

The debug HUD is part of the scene and starts hidden.

The camera captures the mouse in its `_ready`.

## Actions

The player needs input actions with these names. The keys can be whatever the game wants. The names cannot, unless you change the player too.

When the Golem plugin is enabled, the editor adds any of these names that the project does not already have, using the key listed here. A name that already exists keeps its binding.

Set on the player scene:

- `move_forward` (W), `move_backward` (S), `move_left` (A), `move_right` (D)
- `jump` (Space)
- `run` (Shift)

Written as those exact strings in the state scripts:

- `crouch` (X)
- `ragdoll` (E)

Written as those exact strings in the camera script:

- `first_person` (V), `third_person` (N), `third_aim_left` (M), `third_aim_right` (B)

Defaults on the player script, used when the scene does not override them:

- `zoom_in` (O), `zoom_out` (L)
- `fov_decrease` (I), `fov_increase` (K)
- `toggle_mouse_mode` (Y)

This project's map does define `toggle_mouse_mode` (Y). It also defines a different action named `mouse_mode` (left bracket). The player reads `toggle_mouse_mode`, not `mouse_mode`.

The map also has `pan_up`, `pan_down`, `pan_left`, `pan_right`, `aim_cam`, and `aim_cam_side`. No current player script reads those names. The plugin does not add them.

The Escape menu reads `options_menu` (Escape).

## The level

Keep the node name `Player` when the level uses `res://addons/golem/scripts/menu/golem_world.gd`. That script searches the level for that name, adds the options menu, and Escape toggles it. The menu edits the exports on that Player node. The game is not paused while the menu is open.

The character expects Godot 4.7 with the Forward Plus renderer.

A jump with a direction held speeds up to the current gait, walk or run, using that gait's ground acceleration. A jump with no direction keeps the horizontal speed you already had. Letting go of jump does not change the rise. Jump Velocity defaults to 4.5 meters per second. The body uses the project gravity, 9.8, on the way up and on the way down, and only while it is off the floor. A tap reaches the same height as holding the key. Coyote time, jump buffering, and extra air jumps stay on the player.

Crouching during a walk ignores the run key. Crouching during a sprint that is already at slide speed starts a slide. Letting go of `run` does not stop that slide. It ends crouched, in the walk. Can Slide turns this off, and a crouch during a run then cancels the run. A jump straight into a wall still does the short climb. Running along a side wall starts a wall run, and `jump` pushes off that wall. Can Wall Run turns the side run off. Running into a block taller than a step and no taller than the vault height carries the body onto the far top. Walking into that block stops. Can Vault turns the vault off. Can Speed Fov, Can Turn Lean, and Can View Noise turn off the speed widen, the mouse-turn roll, and the small speed noise. The I and K field-of-view keys stay either way.
