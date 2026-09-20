# Test frameworks — detect, then use the right one

*Detect and use the project's test framework; don't reinvent it. Reference per
language.*

A test proves something only when it runs in the project's real framework and runner.
Don't hand-roll what `gtest`, `pytest`, or `vitest` already do. Build and verify WITH
the framework — "passing" means its runner reports pass.

## Discipline

- **Detect first.** Run `.claude/tools/facts.sh` (it reports the detected framework)
  or read the manifest. Match the framework AND the existing test style.
- **One framework per language per repo.** If one is configured, use it. A second one
  fragments the suite — don't add it.
- **Don't reinvent.** Never hand-roll an assertion, mock, or runner the framework ships.
  Use its fixtures, matchers, and parameterization.
- **None yet?** Pick the canonical default for the stack (first column below) — the
  lowest-friction standard one — and say why in one line.
- **It must run in CI** via the project's test command (`facts.sh`), not only locally.

## Reference (canonical default first)

| Lang | Unit / runner | Property-based | Mock | E2E / integration | Bench |
|---|---|---|---|---|---|
| **C** | Unity, Criterion, CMocka, Check | theft | CMocka, FFF | — | custom + `clock_gettime` |
| **C++** | GoogleTest (+GoogleMock), Catch2, doctest | rapidcheck | GoogleMock, trompeloeil | — | Google Benchmark, nanobench |
| **Go** | `testing` (stdlib, table-driven) + testify | `testing/quick`, rapid, gopter | gomock (`go.uber.org/mock`), testify/mock | `httptest`, testcontainers-go | `testing.B` + benchstat |
| **Rust** | built-in `cargo test` (+ rstest fixtures) | proptest, quickcheck | mockall | `tests/` integration, doctests | criterion, divan |
| **TS / JS** | Vitest (new projects) / Jest (existing); `node:test` zero-dep | fast-check | `vi.mock`/`jest.mock`, msw | Playwright (preferred) / Cypress | Vitest bench, tinybench |
| **Python** | pytest (default), unittest (stdlib) | Hypothesis | `unittest.mock`, pytest-mock | Playwright-python, Selenium | pytest-benchmark |
| **Shell** | Bats-core (bash), shUnit2 (POSIX), ShellSpec (BDD) | — | shellmock | Bats + the real CLI | `hyperfine` |

Also: Java → JUnit 5 + Mockito + AssertJ · C#/.NET → xUnit/NUnit + Moq · Ruby →
RSpec/Minitest · PHP → PHPUnit/Pest · Swift → Swift Testing/XCTest · Elixir → ExUnit.

## Pair with the matching agent

- `agents/builder.md` writes tests in the detected framework as the RED step of TDD.
- The `write-test` skill generates coverage in that framework, in its idiom.
- Property-based tests count toward "done" (`quality-bar.md`) for anything that parses
  external input — generate inputs, don't only hand-pick examples.
