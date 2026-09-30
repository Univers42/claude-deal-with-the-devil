#!/usr/bin/env python3
"""Translate the kit's hooks/hooks.json into the Codex CLI dialect.

Codex runs one command string where Claude Code has `command` plus `args`, fires
twelve of the kit's twenty-nine events, expands `PLUGIN_ROOT` itself, and caps
`SessionEnd` and `Interrupt` at three seconds while always running them
synchronously whatever `async` says. Those four differences are the whole of it;
everything else in the source passes through.

Usage: codex-hooks.py <source hooks.json> <destination hooks.json> <notice>
"""

import json
import sys
from collections import OrderedDict

# The events Codex 0.159.2 fires, per https://developers.openai.com/codex/hooks
# (fetched 2026-09-30). An event here that the source does not declare produces
# no handler: inventing a handler for an event with nothing to run it on would be
# inventing behaviour.
EVENTS = [
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PreCompact",
    "PostCompact",
    "UserPromptSubmit",
    "SubagentStop",
    "Stop",
    "Interrupt",
    "SessionStart",
    "SubagentStart",
    "SessionEnd",
]
CAPPED = {"SessionEnd": 3, "Interrupt": 3}
FORCED_SYNC = {"SessionEnd", "Interrupt"}
CARRIED = ("timeout", "async", "statusMessage")


def merge_handler(handler, event):
    """One Codex handler: a single command string plus the fields it honours."""
    # `command` + `args` is Claude's spelling. Codex also sets CLAUDE_PLUGIN_ROOT
    # for compatibility, but PLUGIN_ROOT is the variable its own documentation
    # names, so the generated file says the Codex one and reads on its own.
    parts = [handler.get("command", "")] + list(handler.get("args", []))
    command = " ".join(str(p) for p in parts if str(p))
    merged = OrderedDict([("type", "command")])
    merged["command"] = command.replace("${CLAUDE_PLUGIN_ROOT}", "${PLUGIN_ROOT}")
    for key in CARRIED:
        if key in handler:
            merged[key] = handler[key]
    if event in CAPPED:
        merged["timeout"] = min(
            int(merged.get("timeout", CAPPED[event])), CAPPED[event]
        )
    if event in FORCED_SYNC:
        merged["async"] = False
    return merged


def translate_group(group, event):
    handlers = [
        merge_handler(h, event)
        for h in group.get("hooks", [])
        if h.get("type") == "command"
    ]
    if not handlers:
        return None
    out = OrderedDict()
    if "matcher" in group:
        out["matcher"] = group["matcher"]
    out["hooks"] = handlers
    return out


def translate(source, notice):
    """The Codex hooks object: every declared event Codex fires, translated.

    Caveat: the event list is the documented one for Codex 0.159.2. A release that
    fires more of the kit's twenty-nine events needs it widened here, and
    `--check` cannot notice that, only a re-measure can.
    """
    with open(source) as fh:
        doc = json.load(fh, object_pairs_hook=OrderedDict)
    hooks = OrderedDict()
    for event in EVENTS:
        groups = [
            translate_group(g, event) for g in doc.get("hooks", {}).get(event, [])
        ]
        groups = [g for g in groups if g is not None]
        if groups:
            hooks[event] = groups
    return OrderedDict([("description", notice), ("hooks", hooks)])


def main(argv):
    if len(argv) != 4:
        sys.stderr.write(__doc__ + "\n")
        return 2
    source, dest, notice = argv[1], argv[2], argv[3]
    with open(dest, "w") as fh:
        json.dump(translate(source, notice), fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
