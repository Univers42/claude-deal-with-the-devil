# Prompt contract — facts in, evidence out

*How Claude consumes a request (input) and returns work (output). The best-prompt
contract.*

The best prompt is not a longer prompt — it is a grounded one: facts gathered
before action, results returned as proof. This binds every command, skill,
workflow, and agent here. `AGENTS.md` applies the same discipline to subagents.

## Input — before you act

- **Facts first.** Run `.claude/tools/digest.sh` (or the relevant tool) before
  forming a plan. Decide from the digest, not from a guess about the tree.
- **Read by query.** `rg` / `jq` / the cached `codemap` return the conclusion.
  Never slurp a whole file or tree to answer what a query answers.
- **Restate as a contract.** Echo the task back as inputs → outputs → done-when.
  If the done-when is unstateable, the request is underspecified — sharpen it
  (run `/prompt`) before writing code.
- **Surface unknowns; never paper over them.** A missing fact is named, not assumed.

## Output — what you return

- **Evidence, not adjectives.** Every claim cites proof: a command and its output,
  or `file:line`. "Works" / "fast" / "done" without proof is not a result.
- **Structured for action.** When the caller will act on the result, return a table
  or list it can consume — not prose it must re-parse.
- **No half-states.** Finish to a gate or revert to the last green. Never hand back
  a red test, a partial wiring, or a `TODO` without a linked issue.
- **Minimal.** Say what changed and how to reproduce it. For code comments and docs,
  `minimalism-markers.md` governs — this rule doesn't restate it.

## Why this is the best prompt

A request grounded in tool output and returned as evidence is reproducible: the
next person re-runs the command and sees the same fact. That is the ceiling of
prompt quality — not eloquence, reproducibility.
