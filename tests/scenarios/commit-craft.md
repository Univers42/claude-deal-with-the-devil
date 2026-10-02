2026-09-30 · OpenCode v2.0.18 (free tier) · plugin 0.9.0 · fixture a real git repo whose working tree mixes four changes

## Scenario

> I have been editing ptool all morning and the working tree is a mess. Turn it into a history I can bisect.

Fixture: `ptool`, 5 files, one initial commit. The dirty tree holds four separable concerns: a
`to_csv` helper, a `--csv` CLI flag, a README rewrite, a 0.3.0 to 0.4.0 bump, plus a `.gitignore`
and an untracked test file. Both arms run with HOME and the XDG config roots redirected (no
user-level skills, no kit), outside the kit tree, `question` tool denied.

## Baseline

```text
| Commit | Change |
|---|---|
| `f83e489` | chore: ignore `.venv/` and `dist/` |
| `3d0faa8` | test: cover `money()` and `label()` |
| `883451e` | feat(format): add `to_csv()` helper |
| `552c573` | feat(cli): add `--csv` output mode |
| `8b38ece` | docs: show both usage forms |
| `812294f` | chore: bump version to 0.4.0 |

**Two judgement calls worth flagging**

I ordered commits so each one builds and passes tests on its own — verified by running the suite across all 7 commits, all `OK`. That's what makes the history actually bisectable.

I also combined `to_csv()` with its test rather than separating them. Splitting a function from the test that covers it produces a commit that's only meaningful alongside the next one, and leaves you with a window where new code ships untested. The `money`/`label` tests I did keep as an earlier commit, since those lock in behaviour that already existed before you started.
```

## With skill

Skill loaded: yes, `→ Skill "commit-craft"` on line 4 of `with.out`. It committed 4 plus the import,
not the baseline's 6, and proved the result.

```text
The obvious split was file-by-file, which would have given you a commit that adds `to_csv` to `format.py` and *another* that wires up the CLI — a history where no single commit is a working `--csv`. I kept those together, along with the README and the `to_csv` test, because the fix and its proof belong in one place.

The subtler seam was the untracked test file. It looked like one atomic change — but `test_money` and `test_label` cover code that shipped in the original import, while `test_to_csv` covers the new feature. Splitting it as `d400ce6` gives you a commit that pins current behaviour *before* the feature lands, so when `to_csv` moves next to it you can see exactly what the new code did or didn't disturb.

`.gitignore` is a standalone chore, and the 0.3.0 → 0.4.0 bump went last as its own commit — so `git revert d5c653b` drops the feature without dragging the version back with it.

**Verification**

I checked every commit in a throwaway worktree. Each one that has a `tests/` directory passes (`a8b84e0` shows a discovery error simply because the directory doesn't exist yet). I also ran a real `git bisect run` for the `--csv` feature, and it identifies `d5c653b` as the first commit introducing it.

Worth flagging: my first two bisect attempts gave wrong answers — once because I marked `9ae0cc3` good when `--csv` doesn't work there either, and again because I had the polarity inverted. Bisect needs "good" to be an *ancestor* of "bad", and here the fix is a descendant of the pre-feature commits. The test has to pass when the feature is *absent*. The history was fine both times; my labelling was not.
```

## Verdict

Added: it ran a real `git bisect run` and named the first bad commit instead of asserting
bisectability from per-commit test runs, and it reported the skill's own gate
(`devil quality --with-tests`) as unverified rather than quietly claiming green.
Still wrong: the skill's step 5 gate is unrunnable in a host without the kit installed, and the
skill prescribes interactive `git add -p` staging that an unattended run cannot use, so the run
staged by explicit path and had to be told which seams mattered.
