#!/usr/bin/env python3
"""hooks.py — the enforcement and notification handler for this .claude config.

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

Ponytail: the PreToolUse matcher is regex over the command string, not a shell
parser. It misses obfuscation trivially — `rm -r -f`, a path built from a
variable, anything behind `eval` or a script file. It is a seatbelt against the
common accident, NOT a security boundary, and must never be treated as one.
It also over-matches: `rm -rf ./node_modules` trips the same rule as `rm -rf /`,
which is why most patterns ask rather than deny.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOOK_DIR = Path(__file__).resolve().parent.parent
CLAUDE_DIR = HOOK_DIR.parent
CONFIG_DIR = HOOK_DIR / "config"
TIMEOUT = 4  # seconds; settings.json allows 5000ms


# --------------------------------------------------------------------------- config
def load_config():
    """hooks-config.json, overridden by hooks-config.local.json (gitignored)."""
    config = {}
    for name in ("hooks-config.json", "hooks-config.local.json"):
        path = CONFIG_DIR / name
        try:
            if path.is_file():
                config.update(json.loads(path.read_text()))
        except Exception:
            pass  # a malformed config must not break the session
    return config


def disabled(config, event):
    if config.get("disableAllHooks"):
        return True
    return bool(config.get(f"disable{event}Hook", False))


# --------------------------------------------------------------------------- output
def emit(payload):
    """Print a hook response and stop. Anything else on stdout is ignored."""
    sys.stdout.write(json.dumps(payload))
    sys.stdout.flush()
    sys.exit(0)


def deny(event, reason):
    emit({"hookSpecificOutput": {"hookEventName": event,
                                 "permissionDecision": "deny",
                                 "permissionDecisionReason": reason}})


def ask(event, reason):
    emit({"hookSpecificOutput": {"hookEventName": event,
                                 "permissionDecision": "ask",
                                 "permissionDecisionReason": reason}})


def context(event, text):
    emit({"hookSpecificOutput": {"hookEventName": event,
                                 "additionalContext": text}})


def run(cmd, cwd=None):
    """Bounded subprocess. Returns (rc, output); rc 124 means it was killed."""
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                           timeout=TIMEOUT)
        return p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    except Exception as exc:
        return 125, str(exc)


# --------------------------------------------------------------------------- PreToolUse
# DENY: no plausible reason to run this from an agent, and no undo.
DENY_PATTERNS = [
    (r"\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+(/|/\*|~|~/|\$HOME)\s*$",
     "recursive delete of / or $HOME"),
    (r"\bgit\s+push\b.*(--force|-f)\b.*\b(main|master|production)\b",
     "force-push to a protected branch"),
    (r"\bmkfs(\.|\s)", "filesystem creation"),
    (r"\bdd\b.*\bof=/dev/(sd|nvme|hd)", "raw write to a block device"),
    (r":\(\)\s*\{\s*:\|:&\s*\}\s*;\s*:", "fork bomb"),
    (r"\bchmod\s+(-[a-zA-Z]+\s+)*777\s+(/|/etc|/usr)\b", "world-writable system path"),
    (r"\bhistory\s+-c\b|\bshred\b.*\.bash_history", "shell history destruction"),
]

# ASK: legitimate, but irreversible — rules/risk.md says a human decides.
ASK_PATTERNS = [
    (r"\bgit\s+push\b.*(--force|-f)\b", "force-push"),
    (r"\bgit\s+(reset\s+--hard|clean\s+-[a-zA-Z]*f)", "discards uncommitted work"),
    (r"\bgit\s+push\b", "publishes to a remote"),
    (r"\b(npm|yarn|pnpm)\s+publish\b|\bcargo\s+publish\b|\btwine\s+upload\b",
     "publishes a package — irreversible"),
    (r"\b(kubectl|helm)\s+(delete|uninstall)\b", "deletes live infrastructure"),
    (r"\bterraform\s+(apply|destroy)\b", "changes live infrastructure"),
    (r"\bdocker\s+(system\s+)?prune\b.*(-a|--all)", "removes all unused images"),
    (r"\bDROP\s+(TABLE|DATABASE|SCHEMA)\b", "destructive schema change"),
    (r"\b(DELETE\s+FROM|UPDATE)\b(?!.*\bWHERE\b)", "unqualified DELETE/UPDATE"),
    (r"\bgh\s+repo\s+delete\b|\bgh\s+release\s+delete\b", "deletes a GitHub resource"),
]

# Writing one of these is almost always an accident.
SECRET_PATHS = re.compile(r"(^|/)(\.env|\.env\.[a-z]+|id_rsa|id_ed25519|"
                          r"\.npmrc|\.pypirc|credentials|\.aws/config)$")


def pre_tool_use(data):
    tool = data.get("tool_name", "")
    inp = data.get("tool_input", {}) or {}

    if tool == "Bash":
        cmd = inp.get("command", "") or ""
        flat = " ".join(cmd.split())
        for pattern, why in DENY_PATTERNS:
            if re.search(pattern, flat, re.IGNORECASE):
                deny("PreToolUse",
                     f"Refused: {why}. rules/risk.md treats this as a one-way door with "
                     f"no bounded blast radius. If it is genuinely intended, run it "
                     f"yourself — an agent should not be the one to do it.")
        for pattern, why in ASK_PATTERNS:
            if re.search(pattern, flat, re.IGNORECASE):
                ask("PreToolUse",
                    f"This {why}. rules/risk.md: the irreversible needs an explicit "
                    f"human go-ahead. Confirm the target is what you think it is — "
                    f"state can change under a plan made several steps ago.")

    if tool in ("Write", "Edit", "NotebookEdit"):
        path = inp.get("file_path", "") or ""
        if SECRET_PATHS.search(path):
            ask("PreToolUse",
                f"`{os.path.basename(path)}` normally holds credentials. Confirm this "
                f"is intended — and remember no secret belongs in git or in any memory "
                f"layer (rules/memory.md).")

    sys.exit(0)


# --------------------------------------------------------------------------- PostToolUse
# Fast, single-file gates only. A hook has ~4s; a project-wide lint does not fit,
# and a slow hook is one people disable.
FILE_GATES = {
    ".sh": [["shellcheck", "-e", "SC1091"]],
    ".bash": [["shellcheck", "-e", "SC1091"]],
    ".py": [["ruff", "check"], ["python3", "-m", "pyflakes"]],
    ".go": [["gofmt", "-l"]],
    ".rs": [["rustfmt", "--check", "--edition", "2021"]],
    ".json": [["python3", "-c",
               "import json,sys; json.load(open(sys.argv[1]))"]],
}


def which(binary):
    from shutil import which as _which
    return _which(binary) is not None


def post_tool_use(data):
    if data.get("tool_name") not in ("Write", "Edit", "NotebookEdit"):
        sys.exit(0)
    path = (data.get("tool_input", {}) or {}).get("file_path", "")
    if not path or not os.path.isfile(path):
        sys.exit(0)

    ext = os.path.splitext(path)[1]
    for gate in FILE_GATES.get(ext, []):
        if not which(gate[0]):
            continue
        rc, out = run(gate + [path])
        if rc == 0 or not out:
            break
        context("PostToolUse",
                f"`{' '.join(gate)}` on the file you just edited is not clean:\n\n"
                f"```\n{out[:1500]}\n```\n\n"
                f"rules/quality-bar.md: a warning is an error, there is no warning "
                f"budget. Fix it now — it is cheaper here than at the gate.")
        break

    # This config edits itself; keep it honest as it goes.
    try:
        if Path(path).resolve().is_relative_to(CLAUDE_DIR) and ext == ".md":
            rc, out = run(["bash", str(CLAUDE_DIR / "tools" / "selfcheck.sh"),
                           "--summary"], cwd=str(CLAUDE_DIR))
            if rc == 1:
                context("PostToolUse",
                        f"`selfcheck.sh` now fails — this edit named something that is "
                        f"not on disk:\n\n{out[-1200:]}")
    except Exception:
        pass
    sys.exit(0)


# --------------------------------------------------------------------------- SessionStart
def session_start(data):
    """Hand over the briefing rather than making the agent re-derive it.

    digest.sh is cached and fingerprinted to git state, so this is a file read
    on every session after the first (rules/memory.md: prefer a tool that cannot
    go stale over a memory that can).
    """
    parts = []
    digest = CLAUDE_DIR / "tools" / "digest.sh"
    if digest.is_file():
        rc, out = run(["bash", str(digest)], cwd=os.getcwd())
        if rc == 0 and out:
            parts.append(out[:4000])
    if parts:
        context("SessionStart",
                "Project briefing from `.claude/tools/digest.sh` (cached, "
                "fingerprinted to git state — no need to re-derive it):\n\n"
                + "\n\n".join(parts))
    sys.exit(0)


# --------------------------------------------------------------------------- PreCompact
def pre_compact(data):
    """Compaction drops detail. Say what is worth carrying across it."""
    context("PreCompact",
            "Before compacting, preserve: measured numbers and the command that "
            "produced them, any `devil` verdict and its conditions, the current "
            "done-when, and anything still UNKNOWN. Per rules/memory.md, do NOT "
            "preserve what `.claude/tools/digest.sh` re-derives — re-run it after "
            "compaction instead of carrying a copy that will be stale.")


# --------------------------------------------------------------------------- sounds
def play_sound(event, data):
    """Best effort. No sounds ship with this repo — see hooks/sounds/README.md."""
    try:
        sounds = HOOK_DIR / "sounds" / event.lower()
        if not sounds.is_dir():
            return
        for ext in (".wav", ".mp3"):
            for f in sorted(sounds.glob(f"*{ext}")):
                for player in ("paplay", "aplay", "afplay", "ffplay"):
                    if which(player):
                        args = [player, str(f)]
                        if player == "ffplay":
                            args = ["ffplay", "-nodisp", "-autoexit", "-loglevel",
                                    "quiet", str(f)]
                        subprocess.Popen(args, stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL)
                        return
    except Exception:
        return


# --------------------------------------------------------------------------- main
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
