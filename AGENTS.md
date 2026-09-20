# Multi-agent work in this repo

How to use subagents and the Workflow tool here without making a mess. This is a **standalone** config with
**no orchestrator kernel** — keep multi-agent work **lean and disposable**: fan out for the task, converge,
throw the scaffolding away. Do **not** build half a kernel.

## 1. Decompose, then pick a shape

- **Fan out (parallel)** only for genuinely *independent* slices — separate files, separate modules,
  separate review dimensions. No shared write target.
- **Sequence** dependency chains (order → invoice; migrate → verify). Parallelizing them corrupts state.
- **Right-size.** A trivial or conversational task needs zero subagents. Reserve fan-out for breadth
  (sweep many files) or confidence (independent perspectives before an irreversible step).
- **Hybrid is normal:** scout inline to discover the work-list, *then* fan out over it.

## 2. Every subagent gets

- **One job, one "done when."** An objective with no verifiable done-condition is not a task.
- **The context it needs + the binding rules.** Assume it shares none of your memory. State the cwd, the
  paths, and the non-negotiables (§5) explicitly.
- **A schema, when you'll act on the result.** Force structured output so you consume data, not prose.
- **Read-by-query discipline.** Subagents `tail`/`rg`/`jq`/`awk` and return the *conclusion*, never the
  dump. The cheapest read returns only what you need. Logs are JSONL — filter, don't slurp. The `tools/`
  layer is this made executable: run `.claude/tools/digest.sh` before hand-reading a tree.

## 3. Verify before you trust — and before you act

- **Cross-check claims. UNKNOWN = FAIL.** A finding without evidence (command + output, file + line) is a
  hypothesis, not a fact.
- **Re-verify state right before any destructive or irreversible step.** Files, branches, and data change
  under you — a human may be editing in parallel. A stale inventory is how you clobber someone's work or
  delete the wrong thing. Confirm the target *now*, not from a scan you ran five steps ago.
- **Adversarial pass for high-stakes findings:** spawn skeptics prompted to *refute*; default to refuted
  when uncertain. Diverse lenses (correctness / security / does-it-reproduce) beat N identical voices. For an
  irreversible or high-blast plan, get the `devil`'s verdict (`rules/risk.md`, `/deal`) before acting.

## 4. Converge on a gate

- Funnel parallel work into **one** quality gate — a tester + a reviewer, or the project's verification gate
  (a `scripts/verify/` check or CI job), and `.claude/tools/quality.sh`. A gate that passes vacuously is not a gate.
- **Measured, not claimed.** Every perf/capacity statement cites an artifact + the command that reproduces
  it. No invented numbers.
- Land behind a gate; sync the docs you touched; then stop.

## 5. Non-negotiables (the binding rules — see [`README.md`](README.md))

Every subagent obeys these, even for a one-off slice:

- **Never co-author** a commit/PR (no `Co-Authored-By` / "Generated with"). `settings.json`
  enforces this by setting `attribution` to empty strings — don't add one by hand.
- **Use the project's toolchain** — detect it with `.claude/tools/facts.sh`; run commands under `.claude/tools/watch.sh`.
- **Backward-compatible by default** — new behavior is additive/opt-in until proven; don't break existing callers.
- **Backend-agnostic** — a fix for one adapter/platform that breaks another is not done.
- **Confirm the irreversible** — pushes, deploys, deletions, publishes, data migrations, security cutovers → explicit human trigger.
- **Stage risky changes** — verify the new path against the old before deleting the old; UNKNOWN = FAIL.
- **Verify before you run** — `preflight` the config, never hang (`run-safely`); the quality gate is green before "done".
- **Report faithfully** — failures stated, skips stated; a clean result claimed only when verified.
- **Say what you get wrong** — a heuristic, sample or estimate ships its limitation
  (`rules/ponytail.md`). A subagent returning a best-effort answer says so, or the caller
  will act on it as a fact.
- **Remember the expensive facts only** — a measured number or a verdict, never what
  `.claude/tools/digest.sh` re-derives (`rules/memory.md`).

## 6. Where things live

- Reusable procedures → a `workflows/<name>.md` playbook (human-readable) — not hard-coded here.
- Auto-firing capabilities → a `skills/<name>/SKILL.md`. One-shot actions → a `commands/<name>.md`.
- Durable constraints → a `rules/*.md`. Orientation + conventions → [`README.md`](README.md).
- Recurring parse or enforceable check → a `tools/<name>.sh` (index in [`tools/README.md`](tools/README.md));
  the `forger` builds and maintains these.
- A constraint that must be impossible to ignore → a hook in `hooks/`
  ([`hooks/HOOKS-README.md`](hooks/HOOKS-README.md)). `PreToolUse` already denies the
  catastrophic and asks on the irreversible, so a subagent cannot route around §5 by
  accident — but it is a seatbelt, not a boundary, and does not replace the judgement.
- An existing external script → check `.claude/tools/scripts.sh list` before writing one
  (`rules/script-library.md`).
- This repo keeps **one source of truth per concept** — reference it, don't re-document it.

## 7. The agent roster

Pick the narrowest agent for the job; compose them at a gate (§4). Each obeys §5.

**Build & extend**

- `builder` — TDD, library-first, fact-driven; turns a contract into shipped code with every gate green.
- `forger` — toolsmith; forges the scripts/commands that make rules self-enforcing, iterates on feedback.
- `innovator` — vision; 10x ideas grounded in facts, each with a cheap experiment and a kill criterion.

**Advise & design**

- `architect` — boundaries, contracts, data flow; produces decisions and interfaces, not code.
- `devil` — risk magistrate; scores risk and pronounces a verdict (BLOCK / PROCEED) before risky code exists.
- `documenter` — docs only; never touches source, examples copied from tests.

**Verify (converge here)**

- `reviewer` — strict merge review: correctness, leaks, contract violations, bloat.
- `security` — white-box attacker; finds the exploit, rates it, names the minimal fix.
- `benchmarker` — performance in numbers against a baseline; no adjectives.
- `compat-tester` — measured behavioral parity against a reference (spec, prior version, or competitor), endpoint by endpoint.
- `norminette` — 42 norm enforcer; lists violations, fixes nothing.

Four carry `memory: project` — `reviewer`, `benchmarker`, `architect`, `devil` — because
they are the ones that otherwise re-derive the most. What belongs there and what does not
is `rules/memory.md`; the three layers and their costs are [`doc/MEMORY.md`](doc/MEMORY.md).

## 8. Converging on the config itself

This repo is a `.claude` payload, so its own integrity is a gate. Before handing back work
that touched it:

```sh
bash tools/selfcheck.sh      # every documented name resolves; frontmatter is one Claude Code reads
bash tools/context.sh        # what the change costs every future session
bash tools/ponytail.sh --strict
for t in tests/test_*.sh; do bash "$t" || echo "FAILED: $t"; done
```

`selfcheck.sh` exists because the README once documented four agents, five rules, a skill,
two workflows and a `settings.json` that were not on disk, and nothing caught it. A config
that lies about itself is the one failure this repo cannot afford.
