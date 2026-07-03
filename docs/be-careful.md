# Be careful — running findings log

Living log of findings surfaced by the `/pre-commit-review` chain (and any other
review). **Append** a new dated section after every review chain; never rewrite
history — strike a resolved item through and note when/how it was fixed instead.

## Severity levels

- **HIGH** — dangerous. Act immediately: the project is broken, loses data, or
  will crash/misbehave for a real, reachable configuration. Do not commit on top
  of a HIGH without fixing it.
- **MEDIUM** — matters, but the game still runs. A real defect or risk that is
  contained (rare path, degraded but not broken, or a rule violation with
  gameplay impact). Schedule a fix soon.
- **LOW** — minor. Style, naming, missing docs, cosmetic inconsistencies. The
  game runs fine and nothing is at risk *today*.

## How a LOW becomes dangerous

A LOW is only low **given the current code and scenes**. The danger is that the
condition guarding it is implicit, not enforced — so a future change silently
promotes it to HIGH without anyone re-reviewing it.

Concrete example from the 2026-07-04 chain: the **REVEAL + WHITE** layer gap.
Today `mirror.gd` adds `INVISIBLE_SHIFT` to the affected layer for every REVEAL
mirror, while `pigment.gd` deliberately skips the shift for WHITE. This is
harmless *only because no scene configures a REVEAL mirror with a WHITE pigment*.
The moment a level designer creates one — a completely legal combination in the
editor — the mirror toggles layer 11 while the object stays on layer 1, the
reveal does nothing, and it looks like a "random broken mirror" with no error to
trace. A one-line naming nitpick and a silent cross-file assumption sit in the
same file at the same severity in the raw diff; what separates them is whether an
unenforced precondition can be tripped by ordinary future use. When logging a
LOW, ask: *"what change makes this reachable?"* — if you can name it in one
sentence, write that sentence here.

---

## 2026-07-04 — review chain on `add/10-dynamic-mirror-resolution`

Repository restructure + mirror refactor. Chain verdict: **APPROVED** (no BUG
findings). All open items are LOW; one latent MEDIUM-in-waiting noted.

### MEDIUM (latent — LOW today, escalates on a specific change)
- **REVEAL + WHITE layer mismatch** — `entities/mirror/scripts/mirror.gd`
  (`_apply_pigment`, REVEAL branch) shifts the layer by `INVISIBLE_SHIFT`
  unconditionally, but `entities/mirror/scripts/pigment.gd` skips the shift for
  WHITE. Benign now (no scene uses REVEAL+WHITE, and CLAUDE.md states WHITE has
  no invisible variant). **Escalates to HIGH** the instant a scene sets a REVEAL
  mirror to WHITE pigment: the reveal silently stops working, no error. Fix:
  make `mirror.gd` skip the shift for WHITE too, or reject REVEAL+WHITE with a
  `push_error` at `_ready`.

### LOW
- `entities/mirror/scripts/pigment.gd:14` — `config_dirty` should be
  `_config_dirty` (private flag; sibling `mirror.gd` already uses the underscore).
- `entities/mirror/scripts/pigment.gd:51` — `get_pigment_material` is internal
  only; should be `_get_pigment_material`.
- `entities/mirror/scripts/pigment.gd:61` — `find_node_of_type_anywhere` is
  internal only; should be `_find_node_of_type_anywhere`.
- `entities/mirror/scripts/pigment.gd:16` — `mesh` / `static_body` are used only
  internally; prefix with `_`.
- `entities/mirror/scripts/pigment.gd:6-7` — `is_invisible` and `pigment` exports
  lack the required `##` doc comment (CLAUDE.md principle 7).
- `tests/test_mirror_logic.gd:10` — `print(...)` violates the no-`print` rule
  (principle 8); drop it (assert failures already abort) or mark it a deliberate
  `# ponytail:` test-output shortcut.
