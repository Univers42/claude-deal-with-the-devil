---
name: browser-testing
description: >
  Verify a change in a real browser and come back with evidence — navigate, interact,
  snapshot, read the console. Turns "should work" into an artifact.
  Auto-triggers on: "test in the browser", "does the page work", "check the console",
  "screenshot", "click through", "playwright", "verify the UI", "e2e test"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Browser testing

A passing unit test says a function returns the right value. It does not say the page
renders, the button is reachable, or the console is clean. This closes that gap with
the only evidence that counts for a UI: the thing running.

Uses the Playwright MCP when it is available (`mcp__playwright__*`), and falls back to
Playwright in the repo otherwise.

## 1. Get it running

- `.claude/tools/preflight.sh` — a missing `.env` fails here, not after a browser is
  open (`rules/run-safely.md`).
- Start the dev server **as a background task** so its log stays readable, and wait for
  the port to actually answer. A fixed `sleep` is a flake generator.
- Never point a destructive flow at a real environment. Local or a disposable fixture,
  always.

## 2. Drive it

```
browser_navigate  → browser_snapshot  → browser_click / browser_type / browser_fill_form
                  → browser_wait_for  → browser_snapshot
```

- **`browser_snapshot` before `browser_click`.** The snapshot is the accessibility tree
  with the refs you click by; guessing a selector is how this gets flaky.
- **Prefer role and accessible name** over CSS paths. `getByRole('button', {name:
  'Save'})` survives a restyle; `.btn-primary > span:nth-child(2)` does not. A selector
  that needs the DOM shape is testing the DOM shape.
- **Wait for a condition, never a duration.** `browser_wait_for` on the text or state
  you expect. Every `sleep` is a race you decided to lose later.
- **Read the console and the network** — `browser_console_messages`,
  `browser_network_requests`. An uncaught error or a 404 on a chunk is a failure even
  when the page looks right. This is the single highest-value thing here and the one
  people skip.

## 3. Check what a unit test cannot

- **Responsive** — `browser_resize` to ~375, ~768 and ~1440. Does it wrap, or clip? Does
  the page ever scroll sideways?
- **Theme** — `browser_emulate_media` for dark, and re-check contrast.
- **Keyboard** — `browser_press_key` Tab through the flow. Focus visible? Escape closes
  the dialog? (`frontend/a11y.md`)
- **The states that get skipped** — empty, loading, error. Force them by intercepting
  the request, not by hoping.
- **Accessibility** — run axe against the live DOM. This is what catches contrast and
  computed-role failures that static lint cannot.

## 4. Make the finding permanent

A bug you drove by hand will come back. Turn the reproduction into a Playwright spec in
the project's suite (`rules/test-frameworks.md`), watch it fail, then fix — the RED step
of `agents/builder.md`.

Keep specs independent: no shared mutable state, no ordering assumption, each one sets
up and tears down its own data.

## 5. Close the browser

`browser_close` when done. A session left open holds a port and confuses the next run.

## Report

- What you drove: URL, the steps, the viewport(s) and theme(s).
- **Console and network**: clean, or the exact errors.
- Screenshots or snapshots as the artifact — the evidence
  (`rules/prompt-contract.md`: evidence, not adjectives).
- The a11y result, with the tool named.
- The spec added, and its pass output.
- Anything you could **not** check, and why — never silently narrowed.
