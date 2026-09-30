"""respond.py: the hook's answer to Claude Code.

One JSON object on stdout, then exit 0. `hookSpecificOutput` with a
`permissionDecision` influences a tool call; `additionalContext` injects text.
"""

import json
import os
import sys

# The opt-in knob for sessions the user runs unattended. A PreToolUse ask is a prompt
# even in bypass mode, so it stops every session the user meant to leave alone; with the
# knob on, ask() emits no decision and the session's own permission mode decides.
#
# Caveat: only the exact string "1" turns it on. Unset, "0", "true", "yes" and every typo
# keep the prompts, which is the safe direction to fail in. What it costs is the
# confirm-the-target half of rules/risk.md: an irreversible aimed at the wrong branch,
# the wrong registry or the wrong database runs with nobody in the loop. deny() is
# unreachable from this switch and keeps refusing under it.


def autonomous():
    """True when the operator gave the go-ahead once for the whole session."""
    return os.environ.get("DEVIL_AUTONOMY") == "1"


def emit(payload):
    """Print a hook response and stop. Anything else on stdout is ignored."""
    sys.stdout.write(json.dumps(payload))
    sys.stdout.flush()
    sys.exit(0)


def deny(event, reason):
    emit(
        {
            "hookSpecificOutput": {
                "hookEventName": event,
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }
    )


def ask(event, reason):
    # No decision at all is the shape the harness reads as "no opinion": the caller
    # keeps going and the hook exits 0 having said nothing.
    if autonomous():
        return
    emit(
        {
            "hookSpecificOutput": {
                "hookEventName": event,
                "permissionDecision": "ask",
                "permissionDecisionReason": reason,
            }
        }
    )


def context(event, text):
    emit({"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}})
