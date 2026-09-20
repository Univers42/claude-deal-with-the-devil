# Run safely — verify first, never hang

*Verify the environment before building; bound every command so nothing hangs.*

Two failure modes waste the most time: building against an unconfigured environment,
and waiting forever on a stuck process. Both are preventable. Both have a tool.

## Verify before you build

- Run `.claude/tools/preflight.sh` before any compile / build / run. Missing `.env`,
  secrets, or credentials fail fast and clearly — not ten minutes into a build.
- Config is checked, never assumed. A required var that's unset is a blocker, not a warning.
- Never print secret values — names and set/unset only (preflight already redacts).

## Never wait forever

- Wrap every build, test, install, migration, or deploy in `.claude/tools/watch.sh`.
  It enforces a hard timeout AND an idle timeout, so a hang is detected and killed —
  the agent moves on with a clear reason; it does not stall the session.
- A watchdog kill (exit 124) is a fact to act on: the command hung or overran. Diagnose
  it; don't blindly re-run.
- Tune `--idle` for genuinely silent long tasks; never wrap an interactive prompt.

## Order of operations

`preflight` → fix config → build/test under `watch` → `quality.sh` gate. Verifying late
is the same as not verifying.
