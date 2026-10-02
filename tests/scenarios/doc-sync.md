2026-09-30 · OpenCode v2.0.18 (free tier) · plugin 0.9.0 · fixture `storefacts`, a `release.sh` that gained two positional arguments and a `__pycache__` exclusion

## Scenario

> release.sh used to hardcode dist/ and now takes an output directory and a gzip level, and it excludes __pycache__ from the tarball. The README still documents the old behaviour. Can you check whether the README is out of date and fix what it says about releasing? Do not change release.sh.

Fixture: `release.sh` reading `$1`/`$2` positionally, a `VERSION` file, and a README whose
Options section still advertises `--out-dir` and `--gzip-level` as flags. The exclusion is
undocumented. The fixture has no `src/`, so the script cannot run in place.

## Baseline

Excerpt from `base.out` (no skill loaded):

```text
1. **Flags that don't exist.** The old Options section documented `--out-dir` and
   `--gzip-level`, but `release.sh:6-7` reads them as positional `$1`/`$2`.
2. **Undocumented exclusion.** `release.sh:11` passes `--exclude='__pycache__'`; the README
   said nothing about the tarball's contents at all.
**One thing I found but did not paper over**
`GZIP_LEVEL` is assigned at `release.sh:7` and then never referenced — `tar czf` uses gzip's
own default. The second argument is accepted and silently ignored.
```

It found the same three defects. Every claim is read off the source; no command was run to
confirm the tarball contents or the flag behaviour.

## With skill

Skill loaded: `Skill "doc-sync"`. Excerpt from `with.out`:

```text
--- Positional, not flags ---
$ bash release.sh out/9 9
wrote out/9/storefacts-1.4.0.tar.gz
$ bash release.sh --out-dir build
mkdir: unrecognized option '--out-dir'
- **Exclusion, any depth** — added `src/deep/__pycache__/a.pyc`; both are dropped, not just
  the top level.
```

The claims are now outputs of commands run against a scratch copy, and the one thing that
could not be run in place is named rather than asserted.

## Verdict

Added: every documented claim is verified by running the command, in a scratch copy because
the fixture lacks `src/`, and the unverifiable parts are declared instead of asserted.
Still wrong: it added a `Caveat:` line inside a user-facing README about a source defect it
correctly declined to fix, so the doc now describes a no-op knob in prose rather than a bug.
