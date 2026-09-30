---
name: write-test
description: >
  Generate tests for code that already exists. Use when a module has no tests,
  coverage is thin, a fix needs a regression test, or a change should land with
  proof it still works. Auto-triggers on: "write tests for", "add test coverage",
  "this needs tests"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
metadata:
  stage: beta
  since: "1.0.0"
---

# Write Tests

## 0. Detect the framework

- Run `devil facts` — it reports the detected test framework. Write in
  THAT framework, in its idiom (see `rules/test-frameworks.md`). Don't introduce a
  second framework; don't hand-roll asserts/mocks it already ships.
- None configured? Pick the canonical default for the stack and say why in one line.

## 1. Read the source

- Understand every public function's contract
- Identify edge cases from the implementation (not just happy path)

## 2. Design test cases (before writing any code)

For each function, list:

- Happy path (normal input → expected output)
- Boundary (empty, zero, max, nil/null)
- Error path (invalid input, resource failure)
- Concurrency (if the function touches shared state)

Present the test plan. Wait for approval.

## 3. Write

- Table-driven / parameterized tests in the detected framework's idiom (Go subtests, `rstest`, `it.each`, `pytest.mark.parametrize`)
- Property-based tests for anything parsing external input (Hypothesis, proptest, fast-check, `testing/quick`)
- One test function per behavior, not per source function
- Test names describe the scenario: `test_login_rejects_expired_token`
- No test depends on another test's state
- No sleep() — use channels, signals, or mocks

## 4. Verify

- All new tests pass
- All existing tests still pass
- No flaky tests (run 3 times)
- Report coverage delta

## Report

| Metric | Value |
|---|---|
| Framework detected | |
| Tests added (passing) | |
| Existing tests still green | |
| Coverage delta | |
| Behaviors still untested | |

Plus: the test command you ran and its output, any case you deliberately did not
cover and why, and anything the source does that you could not pin down from the
outside.
