# Lookey — Project structure

This document explains how the repository is organized and where every file
belongs. These rules are binding; the source of truth for agents and reviews
is `CLAUDE.md` at the project root.

## Global folders

Only these folders exist at the root level (besides the Godot project files):

| Folder     | Contents                                                           |
|------------|--------------------------------------------------------------------|
| `docs/`    | Project documentation, grouped by area: `architecture/`, `development/` (experiments + ADRs, see `docs/development/README.md`), `security/` |
| `entities/`| Game elements with depth and specific gameplay importance           |
| `prefabs/` | Generic scene objects without depth                                 |
| `scripts/` | Global scripts, shared by more than one entity/prefab/folder        |
| `sounds/`  | Audio assets                                                        |
| `tests/`   | Headless tests (`assert()`-based, run from the CLI)                 |
| `ui/`      | UI scenes and scripts                                               |
| `world/`   | Levels and environments (`world/scenes/`, `world/environments/`)    |

## Entity vs Prefab

- **Entity** — a game element with depth and specific importance in the game
  (e.g. `mirror`, `player`). It has complex logic and a dedicated folder:
  `entities/<entity-name>/`.
- **Prefab** — a more generic element without depth (a tree, a rock, the
  terrain). It is a scene object: **no** ad-hoc scripts are written for a
  prefab; if it needs behavior, a global script from `scripts/` is assigned
  to it.

The deciding factor is logic complexity: more complex logic → entity, less
complex logic → prefab.

## Where a script belongs

1. **Specific script → specific folder.** If a script serves one specific
   thing (e.g. `mirror.gd` only serves the mirror), it lives inside that
   entity's folder. Example: `entities/mirror/scripts/mirror.gd`.
2. **Shared script → global `scripts/`.** If a script would need to be placed
   in more than one folder, it goes directly in the global `scripts/` folder.
3. **Entity `scripts/` folder.** If an entity has at least one script, create
   `entities/<entity-name>/scripts/` and keep its scripts there.

The general rule applies to any kind of file, not just scripts: **anything
that would otherwise end up duplicated goes in a global folder** (`docs`,
`entities`, `prefabs`, `scripts`, `sounds`, `tests`, `ui`, `world`);
otherwise it stays in the folder of the single specific object.

## Example: the mirror entity

```
entities/mirror/
├── mirror.tscn              # entity scene
├── mirror.gdshader          # mirror-specific assets
├── mirror_frame.gdshader
├── materials/
└── scripts/
    ├── mirror.gd            # Mirror3D: reflection rendering
    ├── mirror_interaction.gd# REVEAL/DISSOLVE gameplay (occlusion, layers)
    ├── pigment.gd           # colors objects and assigns their layers
    └── pigments.gd          # Pigments: pigment→layer/color tables + bitmask helper
```

`pigments.gd` is the single source of truth for the pigment→layer table and
the bitmask helper: never re-declare them elsewhere. If it were ever needed
outside the mirror, rule 2 says it moves to the global `scripts/` folder.

## Language

Everything inside the project — documentation, rules, scripts, comments,
commit messages, node names — is written in **English**, no exceptions,
regardless of the language spoken with the team or with the agents.

## Previous rules (recap)

All the rules already in `CLAUDE.md` remain valid; a quick recap:

- **Branching**: `main` ← `develop` ← feature branches named
  `<type>/<issue-number>-short-name` (e.g. `add/10-dynamic-mirror-resolution`).
  PRs target `develop`.
- **Naming (official Godot style)**: files `snake_case`, `class_name` and
  nodes `PascalCase`, functions/variables `snake_case`, signals in past tense
  (`door_opened`), constants and enum members `CONSTANT_CASE`, enum names
  `PascalCase`. Leading underscore for private methods/variables. Static
  typing always.
- **Code order inside a script**: `@tool` → `class_name` → `extends` →
  `##` docstring → signals → enums → constants → `@export` → public variables →
  private variables → `@onready` → `_init`/`_ready` → other virtual methods →
  public methods → private methods.
- **Principles**: DRY, YAGNI, no overengineering, small classes (~300 lines
  max or a single responsibility), ask when unsure, implement nothing unasked,
  document with `##`, no `print` in committed code.
- **Testing**: mandatory whenever logic is testable. Pure logic → headless
  tests in `tests/` with `assert()`; script validity →
  `--headless --check-only`; runtime behavior → manual test described in
  the PR.
- **Commits**: run the `/pre-commit-review` skill before every commit (it
  always asks for confirmation before launching the review chain).
