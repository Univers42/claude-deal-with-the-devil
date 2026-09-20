# Quality bar — strictest mode, every layer, one command

*The strict, multi-tool quality bar that sits on top of the per-language rules.*

Per-language linters and formatters live in `rules/refactor-<tech>.md` under
"After refactoring". This rule adds the layers that apply to EVERY language and
names the one command that runs them all: `.claude/tools/quality.sh`.

## The bar

- **Strictest flags, always.** `--max-warnings 0`, `-D warnings`,
  `-Wall -Wextra -Werror`, `--check` (a gate never auto-writes). A warning is an
  error. There is no "warning budget".
- **Zero suppressions without a linked issue.** Every `eslint-disable`, `//nolint`,
  `#[allow(...)]`, `# noqa`, norm waiver carries an issue link and a one-line reason.
  An unexplained suppression is a defect.
- **Skipped ≠ passed.** A gate that didn't run is uncovered surface. Install the
  tool or state the gap — never assume green.

## The layers (canonical order — fail early, fix cheap)

1. **Format** — `prettier`, `gofmt`/`gofumpt`, `rustfmt`, `ruff format`, `shfmt`,
   `clang-format`. Check-mode in the gate; the formatter owns style, not humans.
2. **Lint** — `eslint`, `golangci-lint`, `clippy`, `ruff`, `shellcheck`, `cppcheck`.
3. **Types** — `tsc --noEmit`, and the language's strongest type flags.
4. **Static analysis (SAST)** — `semgrep`, **SonarCloud** / `sonar-scanner`, CodeQL.
   These catch what linters miss: taint, cyclomatic complexity, security smells.
5. **Supply-chain audit** — `npm audit`, `cargo audit`, `govulncheck`, `pip-audit`,
   `osv-scanner`, `trivy`. A known-vuln dependency fails the gate.
6. **Accessibility (web)** — `eslint-plugin-jsx-a11y` plus an `axe` / Lighthouse pass
   for any rendered UI. Inaccessible is not done.

## Done means green

- `.claude/tools/quality.sh` exits 0 with every relevant gate run — the static half
  of "done". The dynamic half is tests in the project's framework
  (`rules/test-frameworks.md`, `agents/builder.md`).
- Manual security reasoning (`agents/security.md`) complements SAST — neither
  replaces the other. Run both.
