# Changesets are out of scope

- Decided: 2026-09-30 · by the maintainer
- Holds while: the release tooling stays bash with no package manager

## The concept

Ship one changeset file per skill, in the style a package-managed repo uses: a
pending entry per change, and a release action that reads the set, bumps the
version and opens the release, so a version number is never typed by a person.

## Why not

The version source is already one file, and the tool that owns it is one bash
script the kit already ships. A changeset adds a second file per change, a second
tool to run it, and a node runtime the kit does not otherwise need, to produce the
number `tools/release.sh bump` can already compute from a `## [Unreleased]` block.

- the version source: `.claude-plugin/plugin.json`
- the check that proves the two agree: `bash tools/release.sh --check`

## Prior requests

- 2026-09-30 (planning pass): adopt the changeset-per-skill model wholesale, because
  the neighbouring repo releases 37 skills without a human typing a version.

## Reopen when

The kit gains a real package manager and a published artifact per skill, so a
version per skill becomes a fact rather than a folder name. Then one version source
with a release tool still wins, and only a per-skill artifact makes that impossible.
