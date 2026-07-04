# Development workflow — experiments and ADRs

Every branch that experiments with a new feature is bookended by two documents:
an **experiment document** written *before* the code, and an **ADR**
(Architectural Decision Record) written *after* the related PR passes. The first
captures the intent and the options; the second captures what was actually built
and why, turning the branch into a project milestone.

```
idea ──▶ exp000X (before code) ──▶ experiment on branch ──▶ PR passes ──▶ adr000X (after)
```

## 1. Experiment document — before writing code

Location: `docs/development/experiments/`
Filename: `exp000X_experiment_name.md` (zero-padded sequence: `exp0001_…`, `exp0002_…`).

Write it **before** opening the feature branch's first line of code. It defines
what you want to do and the approaches you are considering — so the exploration
is deliberate, not a random walk.

Template:

```markdown
# EXP-000X — <experiment name>

- **Status:** draft | in progress | concluded
- **Author:** <name>
- **Branch:** <type>/<issue>-<short-name>
- **Date:** YYYY-MM-DD

## Goal
What we want to achieve, in one or two sentences.

## Context
Why now — the problem, the constraint, or the opportunity that motivates it.

## Approaches considered
- **A — <name>:** how it would work; pros / cons; open questions.
- **B — <name>:** …
- **C — <name>:** …

## What we will try first
The approach we start with and why.

## Success criteria
How we will know the experiment worked (measurable where possible).
```

## 2. Experiment — on the branch

Build and try things. The experiment document is living during this phase: update
its **Status**, and record surprises or approaches that were abandoned. The branch
still follows all normal rules (structure, naming, testing, pre-commit review).

## 3. ADR — after the related PR passes

Location: `docs/development/adr/`
Filename: `adr000X_adr_name.md` (its own zero-padded sequence, independent of the
experiment numbers).

Write it **once the PR has passed**. Starting from the experiment document, it
records the decision that was actually made and the implementation that shipped —
how we got from the initial idea to the final approach. ADRs are append-only
history: never rewrite a past ADR; if a decision is later reversed, write a new
ADR that supersedes it.

Template:

```markdown
# ADR-000X — <decision title>

- **Status:** accepted | superseded by ADR-000Y
- **Date:** YYYY-MM-DD
- **Experiment:** exp000X_experiment_name.md
- **PR:** #<number>

## Context
The problem and constraints, distilled from the experiment document.

## Decision
The approach we actually adopted, stated plainly.

## How we got here
The path from the initial idea to this decision: which approaches from the
experiment were tried, what we learned, why the others were dropped.

## Consequences
What this enables, what it costs, and any follow-up or risk it introduces
(cross-link `docs/security/be-careful.md` entries if relevant).
```

## Rules

- **No experimental feature branch without its experiment document first.**
- **No merged experiment without its ADR after.**
- Experiment and ADR sequence numbers are independent (`exp0003` need not map to
  `adr0003`); each increments on its own.
- Both are written in English, like everything else in the project.
