# Lookey

First-person puzzle game about mirrors. Godot 4.7, Forward Plus, GDScript only.

Everything in the repository is written in English: docs, rules, scripts, comments, commit messages, and node names.

The game itself is described in `docs/design.md`. When gameplay changes, update that file in the same change.

## Layout

- `docs/` — the design document. Godot ignores this folder.
- `entities/` — gameplay scenes with their own scripts and assets (`mirror`, `player`).
- `prefabs/` — generic scenes without their own scripts.
- `scripts/` — scripts used by more than one scene.
- `tests/` — gdUnit4 suites.
- `world/` — levels and environments.
- `addons/` — third-party code, including gdUnit4.

A script used by one scene stays with that scene. A script used by more than one scene goes in `scripts/`.

## GDScript

Follow the [Godot GDScript style guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html). Files and folders are `snake_case`. Nodes and `class_name` are PascalCase. Functions, variables, and signals are `snake_case`. Signals are past tense (`door_opened`). Constants and enum members are `CONSTANT_CASE`. Use static types. Engine patterns beyond that live in the `godot-master` skill at `.agents/skills/godot-master`.

## Branches

`main` receives `develop`. Work happens on `feature/<issue>-short-name` and merges into `develop` through a pull request.

## Tests

Suites live in `tests/` and extend `GdUnitTestSuite`. They need a Godot 4.7 executable; gdUnit4 6.2 does not load on Godot older than 4.5.

On a fresh clone, import the project once so gdUnit4's classes are registered:

```
godot --headless --path . --import
```

Run the suites before a commit:

```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests -c
```

## Commits

[Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): subject
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`. The subject is imperative, lowercase, and has no trailing period. The scope is optional. One concern per commit.

## Godot MCP

Agents can drive the editor through `@coding-solo/godot-mcp` (`npx -y @coding-solo/godot-mcp`). It launches the editor, runs the project, and edits scenes. No Godot plugin is required. Cursor loads it from `.cursor/mcp.json`. Other agents register the same command themselves. `GODOT_PATH` overrides detection and stays off the committed config, because the path differs per machine.
