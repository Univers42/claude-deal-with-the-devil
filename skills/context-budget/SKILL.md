---
name: context-budget
description: >
  Measure and cut what this config costs in context every session — always-on rules,
  skill descriptions, unused skills. The token-reduction pass.
  Auto-triggers on: "reduce token usage", "context is full", "what is loading",
  "trim the config", "context budget", "why is my context so big", "compacting too often"
allowed-tools: Read, Edit, Grep, Glob, Bash
---

# Context budget

Configuration is not free. Every always-on rule and every skill description is in the
window before you type anything, on every session, forever. The cost is invisible, which
is why it grows.

This repo shipped 11 rules using Cursor's `globs:`/`alwaysApply:` fields — which Claude
Code does not read — so **22,018 bytes loaded on every session**, including the Go and
REST rules on a Python project. Nothing reported it, because nothing measured it.

## 1. Measure

```sh
.claude/tools/context.sh            # always-on vs lazy, per file
/skill-doctor                       # which loaded skills never actually fire
```

The number that matters is **always-on total**: always-on rules plus every invocable's
`description:`. Everything else loads only when it is needed.

## 2. Know what loads when

| Loads | What |
|---|---|
| **Every session** | `rules/*.md` with **no** `paths:` — full text |
| **Every session** | the `description:` of every skill, command and workflow |
| On a matching file | `rules/*.md` **with** `paths:` |
| On invocation | a skill, command or workflow body |
| In its own context only | an agent definition |

The whole lever is in the first two rows.

## 3. The cuts, in order of return

**1. Give a tech-scoped rule `paths:`.** The biggest single win, and the one most often
missed because the Cursor syntax looks like it works.

```yaml
---
paths:
  - "**/*.go"
---
```

A universal rule keeps **no** frontmatter — that is the signal for always-load, and it
is deliberate. Verify with `.claude/tools/selfcheck.sh`, which fails on `globs:` and
`alwaysApply:`.

**2. Split a long skill.** `SKILL.md` holds the procedure; detail moves to a sibling
`reference.md` the skill reads when it reaches that step. `frontend` does this — the
body stays short, `reference.md` and `a11y.md` load only when relevant.

**3. Tighten descriptions.** Each one is always-on. One sentence plus the trigger
phrases. Trim the prose, keep the triggers — the triggers are what makes it fire.

**4. Delete what never fires.** `/skill-doctor` names skills that load and go unused.
An unused skill is pure always-on cost. Delete it; git has it.

**5. Fork the heavy read-only commands.** `context: fork` with `background: false`
runs the work in an isolated context and returns only the verdict, so the tool chatter
never enters the main window.

## 4. The habits that matter more than the config

Config is the fixed cost; these are the variable one, and usually larger:

- **Tools over re-reading.** `.claude/tools/digest.sh` returns the conclusion from a
  cache fingerprinted to git state. Hand-reading a tree to answer what a tool digested
  is the most expensive habit there is.
- **Read by query.** `rg`, `jq`, `Read` with offset/limit. Never slurp a file to find
  one symbol.
- **Memory over re-derivation.** A measured baseline or a decision belongs in agent
  memory; anything a tool re-derives does not (`rules/memory.md`).
- **Fork the sprawling work.** A wide search in a subagent returns the answer, not the
  file dumps.
- **Compact deliberately** at around half the window, rather than being compacted
  mid-task.

## 5. Re-measure and record

Run `.claude/tools/context.sh` again and state the before and after. A cut you did not
measure is a claim (`rules/prompt-contract.md`).

## Report

| | Before | After |
|---|---:|---:|
| Always-on rules | | |
| Invocable descriptions | | |
| **Always-on total** | | |

- Rules moved to `paths:`, skills split, descriptions tightened, skills deleted.
- Bytes saved per session, and the command that proves it.
- What you deliberately left always-on, and why it earns its place.
