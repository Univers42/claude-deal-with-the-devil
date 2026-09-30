"""process.py: external tools, run inside the hook's time budget."""

import subprocess

# Ponytail: a tool slower than TIMEOUT is killed and returns (124, "timed out").
# The PostToolUse file gate then reports a clean file as not clean (over-reports),
# while the kit selfcheck and the SessionStart briefing are dropped without a word
# (under-reports). Raise it together with the timeouts in hooks/hooks.json.
TIMEOUT = 4  # seconds; hooks/hooks.json gives the harness 5


def run(cmd, cwd=None):
    """Bounded subprocess. Returns (rc, output); rc 124 means it was killed."""
    try:
        p = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=TIMEOUT
        )
        return p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    except Exception as exc:
        return 125, str(exc)


def which(binary):
    from shutil import which as _which

    return _which(binary) is not None
