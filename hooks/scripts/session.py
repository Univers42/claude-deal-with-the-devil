"""session.py: SessionStart hands over the briefing; PreCompact names what must
survive compaction.
"""

import sys

from kit import PLUGIN_ROOT, host_root
from process import run
from respond import context


def session_start(data):
    """Hand over the briefing rather than making the agent re-derive it.

    digest.sh is cached and fingerprinted to git state, so this is a file read
    on every session after the first (rules/memory.md: prefer a tool that cannot
    go stale over a memory that can).
    """
    parts = []
    digest = PLUGIN_ROOT / "tools" / "digest.sh"
    if digest.is_file():
        # The digest describes the host project, so it runs there.
        rc, out = run(["bash", str(digest)], cwd=host_root())
        # Ponytail: the briefing is cut at 4000 characters, so a long digest loses
        # its last sections (untested, duplication) silently; `devil digest`
        # prints the whole of it.
        if rc == 0 and out:
            parts.append(out[:4000])
    if parts:
        context(
            "SessionStart",
            f"Project briefing from `{digest}` (cached, fingerprinted to "
            "git state; no need to re-derive it):\n\n" + "\n\n".join(parts),
        )
    sys.exit(0)


def pre_compact(data):
    """Compaction drops detail. Say what is worth carrying across it."""
    context(
        "PreCompact",
        "Before compacting, preserve: measured numbers and the command that "
        "produced them, any `devil` verdict and its conditions, the current "
        "done-when, and anything still UNKNOWN. Per rules/memory.md, do NOT "
        "preserve what the kit's `tools/digest.sh` re-derives; re-run it after "
        "compaction instead of carrying a copy that will be stale.",
    )
