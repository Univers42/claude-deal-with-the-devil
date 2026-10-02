2026-09-30 · OpenCode v2.0.18 (free tier) · plugin 0.9.0 · fixture `debtcalc`, a Python project whose `.claude/` holds four rules and three skills

## Scenario

> Every session in this repo seems to start with a lot of my context already used before I type anything, and we keep compacting mid-task. I want to cut that. Measure what is actually being loaded on every session and tell me what to cut, with the numbers before and after.

Fixture: `.claude/rules/` with three rules carrying Cursor `globs:`/`alwaysApply:` and one
with no frontmatter, plus `chart`, `slides` and `spreadsheet` skills. One file,
`debtcalc/payoff.py`, so two of the three rules can never match.

## Baseline

Excerpt from `base.out` (no skill loaded):

```text
| Bucket | Bytes | ~tokens | Loads |
| Always-on rules | 26,328 | 6,582 | every session |
| **Always-on total** | **33,635** | **8,408** | **the target** |
**But `context.sh` is measuring the wrong directory.** ... the `M4c` config repo, not the
`debtcalc` project you're actually working in.
2. **Go and SQL rules in a Python project (618 B of pure waste).** ...
Both carry `globs:` + `alwaysApply: true` — **Cursor syntax that OpenCode does not read.**
The one number I won't give you is a confident "after" for cut #1
```

It found the Cursor-field bug and the Go/SQL waste, and refused to invent an "after". It
edited nothing and produced no before/after pair.

## With skill

Skill loaded: `Skill "context-budget"` on attempt 1. Excerpt from `with.attempt1.out`:

```text
-globs: "**/*.py"
-alwaysApply: true
+paths:
+  - "**/*.py"
| Always-on rules | 275 | 68 | every session, no exceptions |
| **Always-on total** | **1275** | **318** |
Measured saving: **1079 bytes** per session.
```

The rules were rewritten to a real `paths:` gate and re-measured after. The run then ended
on an interactive question: `Error: The user dismissed this question` / `Session
interrupted: shutdown` (rc=1).

Retry (`with.attempt2.out`) loaded the skill again and timed out at the 900 s cap after
wandering into the parent kit repository (rc=124).

## Verdict

Added: not established, because no with-skill run completed. Attempt 1 shows the intended
behaviour (paths: conversion plus a re-measured after) but dies before its report.
Still wrong: the skill sent the model into the enclosing kit repo instead of the fixture, so
both arms measured a 33 KB config rather than the 2 KB one under test.
