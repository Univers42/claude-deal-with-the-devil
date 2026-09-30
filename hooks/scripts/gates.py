"""gates.py: PostToolUse. Run the matching fast gate on the file just edited
(rules/quality-bar.md), and re-run selfcheck when a doc inside the kit changes.
"""

import os
import sys
from pathlib import Path

from kit import PLUGIN_ROOT, host_root
from process import run, which
from respond import context

# Fast, single-file gates only. A hook has ~4s; a project-wide lint does not fit,
# and a slow hook is one people disable.
FILE_GATES = {
    ".sh": [["shellcheck", "-e", "SC1091"]],
    ".bash": [["shellcheck", "-e", "SC1091"]],
    ".py": [["ruff", "check"], ["python3", "-m", "pyflakes"]],
    ".go": [["gofmt", "-l"]],
    ".rs": [["rustfmt", "--check", "--edition", "2021"]],
    ".json": [["python3", "-c", "import json,sys; json.load(open(sys.argv[1]))"]],
}


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
        rc, out = run(gate + [path], cwd=host_root())
        if rc == 0 or not out:
            break
        context(
            "PostToolUse",
            f"`{' '.join(gate)}` on the file you just edited is not clean:\n\n"
            f"```\n{out[:1500]}\n```\n\n"
            f"rules/quality-bar.md: a warning is an error, there is no warning "
            f"budget. Fix it now — it is cheaper here than at the gate.",
        )
        break

    # A doc edited inside the kit may name a file that is not there; keep the
    # kit honest as it goes. The host's own docs are not selfcheck's business.
    try:
        if ext == ".md" and Path(path).resolve().is_relative_to(PLUGIN_ROOT):
            rc, out = run(
                ["bash", str(PLUGIN_ROOT / "tools" / "selfcheck.sh"), "--summary"],
                cwd=str(PLUGIN_ROOT),
            )
            if rc == 1:
                context(
                    "PostToolUse",
                    f"`selfcheck.sh` now fails — this edit named something that is "
                    f"not on disk:\n\n{out[-1200:]}",
                )
    except Exception:
        pass
    sys.exit(0)
