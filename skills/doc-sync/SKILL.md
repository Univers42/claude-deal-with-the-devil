---
name: doc-sync
description: >
  Find the documentation a change just made false, and fix it — examples copied from
  passing tests, never composed. Auto-triggers on: "update the docs", "are the docs
  current", "the README is out of date", "document this change", "sync the documentation"
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Doc sync

Documentation does not rot gradually. It becomes false at a specific commit, and then
stays false until someone notices — usually a new person, who trusts it, and loses an
afternoon.

This is the pass that runs *after* a change: find what the change falsified, and fix
exactly that. The `documenter` agent writes docs from scratch; this keeps existing ones
true.

## 1. Find what the change falsified

Start from the diff, not from the docs.

```sh
git diff --name-only <base>..HEAD
```

For every renamed, removed or signature-changed thing, grep the docs for it:

```sh
rg -n '<old-name>|<old-flag>|<old-path>' --glob '*.md' --glob '*.rst'
.claude/tools/selfcheck.sh        # in a .claude config: names docs claim but that are gone
```

The five that go stale first, in order of how often:

1. **Command examples** — a renamed flag, a changed default, a moved path.
2. **Output samples** — pasted once, never re-run, now showing columns that no longer
   exist.
3. **Config keys** — documented after being renamed.
4. **Cross-references** — a link to a file that moved or a section that was retitled.
5. **Counts and lists** — "the six tools", now seven. This one is invisible and
   constant.

## 2. Verify before you rewrite

Do not fix a doc from what you assume the new behaviour is. Run it.

```sh
.claude/tools/watch.sh --idle 60 -- <the documented command>
```

Paste the **real** output, unglamorous parts included. Output trimmed to look cleaner
than reality is a small lie that costs someone an hour.

## 3. Examples come from tests

Every example is copied from a passing test or is a command you just ran. Never
composed from memory — a plausible-looking snippet that does not run is worse than no
example, because it is trusted.

**No test for what you are documenting?** That is the finding. Say it and route it to
the `write-test` skill. Do not invent an example to fill the hole.

## 4. Keep one source of truth

- A concept is explained in exactly **one** place and linked from everywhere else. Two
  explanations drift, and the reader finds the stale one.
- Found a second explanation? Delete it and link. That is the fix, not "update both".
- Cut filler: "simply", "just", "easily", "powerful", "seamless", "robust".
- Keep file headers true — this repo's convention is a block comment stating the why,
  the trick, or the bug that motivated the code. When the behaviour changes, the header
  changes in the same commit (`rules/minimalism-markers.md`).
- New limitation? It gets a `Ponytail:` line (`rules/ponytail.md`).

## 5. Do not overreach

You are syncing, not rewriting. A doc that is merely *imperfect* is out of scope —
changing it buries the change that matters in a diff nobody reads. Fix what is now
**false**, and note the rest separately.

Never change source to make a doc easier to write. If the code is wrong, say so and hand
it to the `builder`.

## Report

- Docs updated, with the specific claim that had become false in each.
- The commands run to verify each example, and their output.
- Duplicate explanations collapsed into a link.
- **Anything you could not document** because the behaviour is untested or unclear —
  named, not silently skipped.
- Docs you deliberately left alone, and why.
