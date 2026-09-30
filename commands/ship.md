---
description: >
  Full release pipeline. Usage: /devil:ship <major|minor|patch>
metadata:
  kind: workflow
---

# Ship

Bump type: $ARGUMENTS

## 1. Pre-flight

- All tests pass
- Zero linter warnings
- No uncommitted changes
- Branch is up to date with main

## 2. Benchmark gate

- Run full benchmark suite
- Compare against last release tag
- If any regression > 5%: ABORT and report what regressed

## 3. Parity gate

- Run the behavioral parity tests against the reference spec
- If any new failure vs last release: ABORT and report

## 4. Version bump

- Bump version in all manifests
- Update CHANGELOG.md

## 5. Final commit

- `chore(release): vX.Y.Z`
- Tag: `vX.Y.Z`

## 6. Present for approval

- Version number
- Changelog summary
- Benchmark comparison
- Parity comparison
- **Wait for explicit "ship it" before pushing tag**
