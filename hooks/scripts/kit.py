"""kit.py: where the kit lives, where the host project lives, and the hook switches.

The switches are hooks/config/hooks-config.json, overridden per user by
hooks-config.local.json.
"""

import json
import os
from pathlib import Path

# Two roots, never confused. The kit's own files (tools/, hooks/config) live
# under the plugin root: the directory above hooks/, wherever the plugin was
# installed or copied. The project being worked on is the host root, which
# Claude Code passes as CLAUDE_PROJECT_DIR; a hook run by hand uses the cwd.
HOOK_DIR = Path(__file__).resolve().parent.parent
PLUGIN_ROOT = HOOK_DIR.parent
CONFIG_DIR = HOOK_DIR / "config"


def host_root():
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


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
