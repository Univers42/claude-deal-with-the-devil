---
name: write-test
description: >
  Generate tests for existing code. Auto-triggers on:
  "write tests for", "add test coverage", "this needs tests"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Write Tests

## 0. Detect the framework

- Run `.claude/tools/facts.sh` — it reports the detected test framework. Write in
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
