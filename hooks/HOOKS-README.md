# `hooks/` — where the rules stop being reminders

A rule that can be checked mechanically should be a check. `agents/forger.md` puts it
plainly: *a rule without a tool is a hope*. Every event in `settings.json` runs
`scripts/hooks.py`, which does two jobs.

## 1. Enforcement — the part that matters

| Event | What it does | Rule it enforces |
|---|---|---|
| `PreToolUse` | **Denies** the catastrophic (`rm -rf /`, force-push to `main`, `mkfs`, a fork bomb). **Asks** on the irreversible (any push, `publish`, `terraform apply`, `kubectl delete`, an unqualified `DELETE`/`UPDATE`, writing a `.env` or a private key). | `rules/risk.md` — confirm the irreversible |
| `PostToolUse` | Runs the matching fast gate on the single file just edited — `shellcheck`, `ruff`, `gofmt`, `rustfmt --check`, JSON parse. Re-runs `selfcheck.sh` when a doc in this config changes. | `rules/quality-bar.md` — a warning is an error |
| `SessionStart` | Injects `tools/digest.sh` so the agent starts briefed instead of re-deriving the tree. Cached and fingerprinted to git state. | `rules/prompt-contract.md` — facts first |
| `PreCompact` | Names what must survive compaction (measured numbers, verdicts, the done-when, open UNKNOWNs) and what must not (anything `digest.sh` re-derives). | `rules/memory.md` |

`PreToolUse` is the only **synchronous** hook — a decision is only honoured if the
harness waits for it. Everything else is `async: true` and cannot block you.

### What it is not

**`PreToolUse` is a seatbelt, not a security boundary.** It is regex over the command
string, not a shell parser, so it misses obfuscation trivially: `rm -r -f`, a path built
from a variable, anything behind `eval` or inside a script file. It catches the common
accident. Do not build a trust model on it (`rules/ponytail.md`).

It also over-matches — `rm -rf ./node_modules` trips the same rule as `rm -rf /` — which
is why most patterns **ask** rather than deny.

## 2. Notification

A sound per event, if sounds are installed. **None ship with this repo** and the feature
is off by default; see `sounds/README.md`.

## Configuration

`config/hooks-config.json` is team-shared. `config/hooks-config.local.json` is yours and
gitignored; it is merged over the shared file.

```jsonc
// config/hooks-config.local.json
{
  "sounds": true,              // you added sounds
  "disablePostToolUseHook": true,  // you run the gates yourself
  "disableEnforcement": false      // leave this alone unless you mean it
}
```

Three levels of off, narrowest first:

1. `disable<Event>Hook: true` — silence one event.
2. `disableEnforcement: true` — keep sounds, drop the checks. Every rule is a reminder
   again.
3. `disableAllHooks: true`, here or in `settings.local.json` — everything off.

## Fail open, always

Any unexpected error exits 0 silently. A hook that crashes must never stop you working,
and a handler that throws on a malformed payload would block every tool call in the
session. Subprocesses are bounded at 4s against the 5s harness timeout.

**If a hook seems to be misbehaving**, test it directly — it reads JSON on stdin:

```sh
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash",
       "tool_input":{"command":"git push --force origin main"}}' \
  | python3 hooks/scripts/hooks.py
```

Expect a JSON object with `permissionDecision`. Silence plus exit 0 means "no opinion",
which is the correct response to most events.

## Adding an event

1. Add the block to `settings.json` (copy an existing one; keep `async: true` unless it
   must block).
2. Add `disable<Event>Hook` to `config/hooks-config.json`.
3. For enforcement, add a handler and register it in the `ENFORCERS` map in
   `scripts/hooks.py`.
4. Prove it: the pass path, the fail path, and the malformed-input path. An unproven
   hook is not done (`agents/forger.md`).
