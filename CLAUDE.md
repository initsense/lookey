# Lookey — Project Rules

First-person puzzle game about mirrors, built with **Godot 4.7** (Forward Plus). GDScript only.

**English only, no exceptions**: everything inside the project — documentation, project rules, scripts, comments, commit messages, node names — is written in English, regardless of the language used in conversation.

## Repository map

Global folders (top level): `docs`, `entities`, `prefabs`, `scripts`, `sounds`, `tests`, `ui`, `world`.

- `docs/` — project documentation; `docs/project_structure.md` explains the structure rules in full
- `entities/` — game elements with depth and gameplay importance (mirror, player). One folder per entity
- `prefabs/` — generic scene objects without depth (terrain, object)
- `scripts/` — global scripts shared by more than one entity/prefab/folder
- `sounds/` — audio assets
- `tests/` — headless test scripts
- `ui/` — UI scenes and scripts
- `world/` — levels and environments (`world/scenes/`, `world/environments/`)

Core mechanic: each mirror (`entities/mirror/`) has a `Pigment` (color) and a `MirrorType` (`VANILLA`, `REVEAL`, `DISSOLVE`). Pigments map to fixed render/collision layers (1, 3–8; +10 for the "invisible"/reveal variants). Mirrors render via a `SubViewport` camera mirrored across the quad plane, with distance-based resolution scaling. The pigment→layer/color tables and the layer-bitmask helper live **only** in `entities/mirror/scripts/pigments.gd` (`Pigments`) — never re-declare them. `mirror.gd` does the rendering, `mirror_interaction.gd` the REVEAL/DISSOLVE gameplay, `pigment.gd` colors objects and assigns their layers.

## Structure rules

1. **Specific script → specific folder.** A script needed by one specific thing lives inside that thing's folder (e.g. `entities/mirror/scripts/mirror.gd`). A script that would be needed in more than one folder goes directly in the global `scripts/` folder.
2. **Shared → global.** In general, anything that would otherwise end up duplicated goes in the global folders (`docs`, `entities`, `prefabs`, `scripts`, `sounds`, `tests`, `ui`, `world`); otherwise it stays in the folder of the single specific object.
3. **Entity vs prefab.** Entities are game elements with depth and specific importance in the game (mirror, player). Prefabs are more generic scene objects without depth (a tree, a rock). More complex logic → entity; less complex → prefab. A prefab is a scene object and gets no ad-hoc script, but a global script from `scripts/` may be assigned to it.
4. **Entity scripts folder.** If an entity has at least one script, create `entities/<entity-name>/scripts/` and put its scripts there.

## Branching

`main` ← `develop` ← feature branches named `<type>/<issue-number>-short-name` (e.g. `add/10-dynamic-mirror-resolution`, `feature/5-vanilla-mirror`). PRs target `develop`; `develop` merges to `main`.

## Naming conventions (Godot official style)

| Type         | Convention    | Example / note                        |
|--------------|---------------|---------------------------------------|
| File names   | snake_case    | `yaml_parsed.gd`                       |
| class_name   | PascalCase    | `YAMLParser`                           |
| Node names   | PascalCase    |                                        |
| Functions    | snake_case    |                                        |
| Variables    | snake_case    |                                        |
| Signals      | snake_case    | always past tense: `door_opened`       |
| Constants    | CONSTANT_CASE |                                        |
| enum names   | PascalCase    |                                        |
| enum members | CONSTANT_CASE |                                        |

Prepend a single underscore (`_`) to virtual methods the user must override, private functions, and private variables.

Always use static typing: `var speed: float = 3.0`, `func foo(delta: float) -> void:`.

## Code order inside a script

1. `@tool`
2. `class_name`
3. `extends`
4. `## docstring`
5. signals
6. enums
7. constants
8. `@export` variables
9. public variables
10. private variables
11. `@onready` variables
12. `_init`
13. `_ready`
14. remaining built-in virtual methods (`_process`, `_physics_process`, …)
15. public methods
16. private methods

## Principles

1. **DRY** — before writing anything new, reuse what exists (e.g. the layer-bitmask helpers, the `Pigment` enum, the state machine). If two scripts need the same logic, extract it, don't copy it.
2. **YAGNI** — implement only what is needed *now*. No options, parameters, or systems "for later".
3. **No overengineering** — practical, effective solutions. No abstraction with a single implementation, no config for a value that never changes.
4. **Small classes** — each script does few things well. If a script grows past ~300 lines or a second responsibility, split it.
5. **Ask when unsure** — if a decision isn't covered by these rules or the existing code, stop and ask instead of guessing.
6. **Implement nothing unasked** — no unsolicited features, refactors, or files.
7. **Document the code** — every script gets a `##` docstring; every exported variable and every non-obvious public function gets a `##` comment. Comments explain *why*, not *what*.
8. **No `print` in committed code** — use `push_warning`/`push_error`, or guard debug output behind the debug HUD.
9. **Offer alternatives** — for the discussions and implementations we bring you, look beyond the proposed approach: suggest alternative angles grounded in established best practices, and research current sources (as of July 2026 — Godot 4.x patterns, GDScript idioms, rendering/performance techniques) to propose better or newer methods. Present them as options with trade-offs, not as mandates; the final call stays with us.

## Ponytail — how code gets written

The laziest solution that works is the right one. Before writing code, stop at the first rung that holds:

1. Does this need to exist at all? Speculative need = skip it, say so in one line.
2. Godot built-in covers it? (node, signal, `@export` hint, CSS-equivalent: theme/shader param) Use it.
3. Existing project code covers it? (layer-bitmask helpers, `Pigment` table, state machine) Reuse it.
4. Can it be one line? One line.
5. Only then: the minimum code that works.

Deletion over addition, boring over clever, fewest files, shortest working diff. Mark deliberate shortcuts with a `# ponytail:` comment naming the ceiling and the upgrade path (e.g. `# ponytail: linear scan, spatial hash if >100 mirrors`). Never simplify away: input validation, error handling that prevents data loss, anything explicitly requested.

## Testing

Testing is mandatory when logic can be tested. Real tests only — no fake mocks, and tests must actually pass.

- Godot CLI on this machine: `/Applications/Godot.app/Contents/MacOS/Godot` (not on PATH).
- Pure logic (math, layer masks, state transitions) → test headless:
  `<godot> --headless --script res://tests/<name>.gd` with `assert()` checks, or GUT if/when the team adds it.
- Script validity for the whole project: `<godot> --headless --check-only --quit --path .`.
- Behavior that needs the running game (rendering, physics feel) → describe the manual test in the PR.

## Commits and review

Before **every commit**, run the `/pre-commit-review` skill (see `.claude/skills/pre-commit-review/`). It always asks for confirmation before launching the review chain — never run the chain without asking first. After each chain, its findings are appended to `docs/be-careful.md`, marked HIGH / MEDIUM / LOW.
