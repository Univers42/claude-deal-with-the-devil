#!/usr/bin/env python3
"""hooks.py: the enforcement and notification handler for the devil kit.

Why this exists: every rule in rules/ was a reminder, and reminders drift. A rule
that can be checked mechanically should be a check (agents/forger.md: "a rule
without a tool is a hope"). This turns four of them into something the harness
actually runs.

Two jobs, in this order:

  ENFORCEMENT (synchronous — the decision is only honoured if we block)
    PreToolUse   refuse the catastrophic, ask on the irreversible (rules/risk.md)
    PostToolUse  run the matching fast gate on the file just edited
    SessionStart hand the agent its briefing instead of making it re-derive one
    PreCompact   flush session facts so compaction does not lose them

  NOTIFICATION (asynchronous — best effort, never blocks)
    a sound per event, if sounds are installed. None ship with this repo.

Contract with Claude Code: event JSON arrives on stdin with `hook_event_name`.
To influence a tool call, print a JSON object with `hookSpecificOutput` and exit
0. To inject context, print `additionalContext`.

FAIL OPEN, ALWAYS. A hook that crashes must not stop the user working, so every
path is wrapped and every unexpected error exits 0 silently. The one thing worse
than an unenforced rule is a harness nobody can use.

This file is the entry point hooks/hooks.json runs. Each job lives in a sibling
module named for its concern:

  risk.py     PreToolUse, and the limits of its regex matcher
  gates.py    PostToolUse
  session.py  SessionStart and PreCompact
  notify.py   the sounds
  kit.py      plugin root, host root, hooks/config
  respond.py  the JSON answer to the harness
  process.py  bounded subprocesses
"""

import json
import sys
from pathlib import Path

# Importing a sibling would otherwise write .pyc files into the plugin root,
# which the single-file handler never did.
sys.dont_write_bytecode = True
# The harness runs this file by absolute path from any cwd, and under -P or
# PYTHONSAFEPATH Python does not put the script's directory on sys.path.
sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from gates import post_tool_use
    from kit import disabled, load_config
    from notify import play_sound
    from risk import pre_tool_use
    from session import pre_compact, session_start
except Exception:
    sys.exit(0)  # fail open: a broken module must not stop the user either

ENFORCERS = {
    "PreToolUse": pre_tool_use,
    "PostToolUse": post_tool_use,
    "SessionStart": session_start,
    "PreCompact": pre_compact,
}


def main():
    try:
        raw = sys.stdin.read().strip()
        if not raw:
            sys.exit(0)
        data = json.loads(raw)
        event = data.get("hook_event_name", "")
        if not event:
            sys.exit(0)

        config = load_config()
        if disabled(config, event):
            sys.exit(0)

        if config.get("sounds", False):
            play_sound(event, data)

        handler = ENFORCERS.get(event)
        if handler and not config.get("disableEnforcement", False):
            handler(data)
    except SystemExit:
        raise
    except Exception:
        pass  # fail open: never stop the user because a hook broke
    sys.exit(0)


if __name__ == "__main__":
    main()
