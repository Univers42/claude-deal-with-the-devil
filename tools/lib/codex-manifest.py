#!/usr/bin/env python3
"""Build the Codex CLI plugin manifest from the kit's Claude Code one.

A transform, not a rewrite: every field a host may already depend on is read from
`.claude-plugin/plugin.json`, so the generated manifest cannot drift from the
version source and a bump is a one-line change in one file.

Usage: codex-manifest.py <source plugin.json> <destination plugin.json>
"""

import json
import sys
from collections import OrderedDict

SCHEMA = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
# The portable manifest is Agent Plugins 1.0 and its schema sets
# additionalProperties false, so a Claude Code field has nowhere to go. The
# marketplace entry already carries the human label.
DROPPED = ("displayName",)


def build(source):
    """The portable manifest: source identity plus the Codex hooks pointer.

    Caveat: line-oriented JSON handling over a small hand-kept manifest. A source
    whose identity fields are absent produces a manifest without them, which Codex
    rejects at install time rather than half-loading.
    """
    with open(source) as fh:
        doc = json.load(fh, object_pairs_hook=OrderedDict)
    for key in DROPPED:
        doc.pop(key, None)
    out = OrderedDict([("$schema", SCHEMA)])
    out.update(doc)
    # An explicit hooks entry, so the file path is a decision on the record rather
    # than a default the harness happens to have.
    out["extensions"] = OrderedDict(
        [("com.openai", OrderedDict([("hooks", "./hooks/hooks.json")]))]
    )
    return out


def main(argv):
    if len(argv) != 3:
        sys.stderr.write(__doc__ + "\n")
        return 2
    with open(argv[2], "w") as fh:
        json.dump(build(argv[1]), fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
