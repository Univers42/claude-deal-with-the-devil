2026-09-30 · OpenCode 2.0.18 (free tier) · plugin 0.9.0 · fixture one static notifications page, no framework

## Scenario

> does this notifications page look right? something feels off about it but I can't
> put my finger on what it is.

Three files, no build step: `index.html` (an `h1`, three identical `.cta`
buttons, an empty `ul.feed`), `styles.css` (one blue for everything, 11px to 17px
type), `app.js` (renders six rows, no empty, loading or error branch).

## Baseline

```text
[...the hierarchy, spacing and alignment findings above are elided...]

`app.js:1-2` states the premise outright: *"the empty case is not handled anywhere, because the server never sends an empty list."* That premise doesn't survive contact with a read/unread page — the moment you read everything, the list is empty. You'd get a bare heading, three buttons, and nothing. There are no loading or error states either. Also `innerHTML` with unescaped interpolation at `app.js:13-20` is an injection risk once this hits real server data.
```

## With skill

Skill loaded: yes, `→ Skill "design-review"` on line 4 of the run.

```text
The dominant problem: one blue, four meanings

`#2563eb` is doing the work of *primary action* (all three buttons), *secondary action* (also all three buttons), *tertiary action* (also), and *unread state* (`.unread`). When one colour carries four meanings it stops signalling anything, and the result reads as a wall of competing emphasis with no entry point.

| Issue | Where | Principle | Smallest fix |
|---|---|---|---|
| Blue = primary + secondary + tertiary + unread | `styles.css:13-21, 40-42` | One primary action per view | Keep `.cta` on **Mark all read** only; Export → ghost/text button |
| Unread signalled by hue alone | `.unread` `:40-42` | Emphasis from size/weight/space before colour | Unread → `font-weight: 600` on the row + 2px left rail or dot; drop the blue text |

The states that don't exist (the biggest finding)

I forced `FEED = []` and re-rendered: you get a heading and **three live blue buttons over an empty void** — no message, and "Mark all read" / "Pause all" still active with nothing to act on.
```

## Verdict

Added: the body's five-axis pass turned "feels off" into one named dominant
problem, and step 6 made it render at 375/768/1440 plus a forced-empty run, so the
missing empty state became a screenshot instead of an inference.
Still wrong: it dropped the `innerHTML` injection risk at `app.js:13-20` that the
baseline caught, and it left the dev server on `:8811` running instead of closing
the browser, which step 5 asks for.