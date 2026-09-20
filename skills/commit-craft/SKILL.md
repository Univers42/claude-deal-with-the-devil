---
name: commit-craft
description: >
  Turn a working tree into a history someone can read, revert and bisect — atomic
  commits, Conventional Commits, never co-authored. Auto-triggers on: "commit this",
  "write a commit message", "split these changes", "prepare a PR", "clean up the history"
allowed-tools: Read, Bash, Grep, Glob
---

# Commit craft

A commit is a message to whoever is bisecting at 3am, and that is usually you. The two
properties that matter: each commit does **one** thing, and each commit **builds and
passes**. Everything else follows from those.

## 1. Look at what you actually have

```sh
git status
git diff            # unstaged
git diff --staged   # staged
```

Read the whole diff before writing anything. Two things you are looking for:

- **Accidents** — a debug print, a commented-out block, a `.env`, a large binary, a
  hardcoded token, a stray formatter sweep across files you never touched.
- **Seams** — where this tree is really two or three changes wearing one hat.

## 2. Split it

One logical change per commit. If the message needs "and", it is two commits.

- **Never mix a refactor with a feature** (`rules/refactor-common.md`). A rename across
  40 files plus one behaviour change is a diff nobody can review — and reviewers approve
  what they cannot read.
- A fix and its regression test go **together**. The test is what proves the fix.
- Formatting-only sweeps get their own commit, so the real change stays legible.

```sh
git add -p                 # stage by hunk
git stash push -- <path>   # set aside what belongs in the next commit
```

**Each commit compiles and passes on its own.** That is what makes `git bisect` and
`git revert` work, and it is the whole reason for this discipline.

## 3. Write the message

```
<type>(<scope>): <what changed, imperative, lower case, no period>

<why — the problem, the constraint, the measurement. Not the what: the diff has that.>

<footer: Fixes #123, BREAKING CHANGE: ...>
```

Types: `feat` · `fix` · `refactor` · `perf` · `test` · `docs` · `build` · `ci` ·
`chore`. Scope is optional and is the module, not the file.

- **Subject: what. Body: why.** "fix(auth): reject expired tokens" then, in the body,
  *why it was accepted before* and what that allowed. The why is the part that cannot
  be recovered from the code.
- Cite the evidence: the measurement, the failing input, the issue. `perf(parse):
  pre-size the buffer — p95 18ms → 4ms on the 10k fixture` is a message that pays for
  itself.
- `BREAKING CHANGE:` in the footer whenever a shipped contract changes
  (`rules/api-convention.md`).
- Imperative mood: "add", not "added" or "adds".

## 4. Never co-author

**No `Co-Authored-By` and no "Generated with" trailer.** Binding rule #1 of this config,
and `settings.json` enforces it by setting `attribution` to empty strings. Do not add
one by hand.

## 5. Before it leaves your machine

- `.claude/tools/quality.sh --with-tests` green.
- No secret, no large binary, nothing that should be gitignored.
- Rebase on the target branch; resolve conflicts here, not in a merge commit nobody
  reviews.
- **Pushing is irreversible enough to confirm** — and a force-push always is
  (`rules/risk.md`). Ask before you push; never force-push a shared branch without an
  explicit go-ahead.

## Report

- The commits created, in order, each with its subject line.
- What you split and why — the seam you found.
- Anything you refused to commit (a secret, a debug artifact, a stray file).
- The gate status, and whether it was pushed or is waiting for a go-ahead.
