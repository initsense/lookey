---
name: pre-commit-review
description: Two-stage agent review chain (Software Reviewer → Reviewer Reviewer) to run before every commit. Always asks the user for confirmation before launching. Use when the user is about to commit, asks for a pre-commit review, or invokes /pre-commit-review.
---

# Pre-commit review chain

Run this before **every commit** in this repo. The chain is: **Software Reviewer** (finds bugs and rule violations in the diff, emits a report) → **Reviewer Reviewer** (senior, intransigent auditor of that report, emits the final verdict).

## Steps

1. **Ask first — mandatory.** Show the user a one-line summary of the staged diff (`git diff --staged --stat`; if nothing is staged, `git diff HEAD --stat`) and ask for confirmation to launch the review chain (AskUserQuestion: "Run the pre-commit review chain on this diff?"). If the user declines, stop — do not commit on their behalf either.
2. **Stage 1 — Software Reviewer.** Launch the `software-reviewer` agent (Agent tool, subagent_type `software-reviewer`) with the prompt: "Review the staged diff (fall back to `git diff HEAD` if empty) against CLAUDE.md and emit your report." Its final message is the Review Report.
3. **Stage 2 — Reviewer Reviewer.** Launch the `reviewer-reviewer` agent and paste the FULL Review Report from stage 1 into its prompt, asking it to audit the review of the same diff. Its final message is the Review Audit with the final verdict.
4. **Act on the verdict:**
   - **APPROVED** → report both verdicts to the user; the commit may proceed.
   - **REJECTED** → show the user what must be fixed in the code. Do not commit. Re-run the chain (from step 1) after fixes.
   - **REDO REVIEW** → re-run stage 1 addressing the audit's complaints, then stage 2 again. Max one redo; if it still fails, surface everything to the user and ask.
5. **Log the findings.** After the verdict, append a new dated section to `docs/security/be-careful.md` with every confirmed finding, each marked **HIGH** / **MEDIUM** / **LOW** (see that file's legend). For any LOW that hides an unenforced precondition, add the one-sentence "what change makes this reachable?" note. Append only — never rewrite past entries.
6. **Always show the user** the final verdict and any confirmed findings — never silently swallow a report.

## Rules

- Never launch the chain without the user's explicit confirmation (step 1).
- Never commit while the latest verdict is not APPROVED.
- The agents only read and report; all code fixes happen in the main session, by you, with the user's approval.
