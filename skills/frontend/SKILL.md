---
name: frontend
description: >
  Build UI that holds up — component and state boundaries, design tokens, responsive and
  theme behaviour, and the accessibility gate. Auto-triggers on: "build a component",
  "add a page", "style this", "make it responsive", "dark mode", "the layout breaks",
  "frontend", "this UI"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Frontend

UI is where "it works on my machine" hides best: it renders on your screen, in your
theme, with your data, at your width. Correctness here means it holds at every width, in
both themes, with no data and with too much, and for someone not using a mouse.

Depth lives in `reference.md` (tokens, layout, state) and `a11y.md` (the gate). Read
them when you reach that step, not before.

## 1. Look before you add

- `.claude/tools/facts.sh` for the framework, the test runner and the lint setup. Do
  not introduce a second styling approach, state library or component kit — that is a
  fork in the codebase (`rules/minimalism-ladder.md` rung 4).
- Find the nearest existing component and mirror its structure, naming and file layout.
  The codebase's convention beats your preference.
- `.claude/tools/dupes.sh` — a third copy of the same button is an extraction
  (`rules/library-first.md`).

## 2. Draw the boundaries first

- **State lives at the lowest common owner** of everything that reads it. Lifting
  everything to the top is how a page re-renders on every keystroke.
- **Server state is not UI state.** Cache, loading and error belong to a data layer, not
  to twelve `useState` calls.
- **Derive during render; do not sync with an effect.** Most `useEffect` that sets state
  is a computed value in disguise (`rules/refactor-typescript.md`).
- **Presentational components take data and callbacks**, and fetch nothing. They are the
  ones that stay testable.

## 3. Tokens, never magic values

Colour, spacing, radius, type scale, z-index and motion come from the design system's
tokens. A hardcoded `#3b82f6` or `margin-top: 13px` is the bug that makes a redesign
cost a month. Details in `reference.md`.

## 4. Build every state, not just the happy one

Each of these is real and each gets skipped:

**empty** · **loading** (skeleton, not a spinner that jumps the layout) · **error**
(what failed, what they can do) · **partial** · **too much** (200 rows, a 60-character
unbroken word) · **offline / slow**

Plus per-element: default · hover · focus-visible · active · disabled · selected.
A control with no visible focus state is broken for keyboard users, and that is most
custom controls.

## 5. Responsive and theme are correctness

- Works from ~320px up. Layout wraps or stacks; nothing has a `min-width` wider than a
  phone. Tables, code and diagrams scroll inside their own container so the page body
  never scrolls sideways.
- Both themes. Define the full palette on a light `:root`, then override only the
  tokens that change — never let a colour exist *only* inside a dark-mode block, and
  always set an explicit background on `body`.
- Respect `prefers-reduced-motion`.

## 6. Prove it

- **Accessibility is part of the gate, not polish.** `a11y.md` has the checklist and
  the tools; `eslint-plugin-jsx-a11y` plus an axe pass is the floor
  (`rules/quality-bar.md` layer 6).
- **See it running.** The `browser-testing` skill drives a real browser: render it,
  resize it, tab through it, read the console. A screenshot is evidence; "should work"
  is not.
- `.claude/tools/quality.sh --with-tests` green.

## Report

- Components added or changed, and where state ended up living.
- Every state implemented (empty / loading / error / too-much) — and any you skipped,
  named.
- Widths and themes actually checked, with the artifact.
- The a11y result: tool, version, findings, what is left.
