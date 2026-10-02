2026-09-30 · OpenCode 2.0.18 (free tier) · plugin 0.9.0 · fixture one static orders page, no framework

## Scenario

> the orders page is broken on my phone: the header and the table run off the side
> of the screen, and the text is unreadable when my OS is in dark mode. Can you fix
> the CSS?

Three files, no build step: `index.html` (header, nav, three `.primary` buttons,
a 4-row table), `styles.css` (`min-width: 1180px` on both header and table,
light-only custom properties), `app.js` (renders the rows).

## Baseline

```text
Two things to flag honestly:

- **The row divider doesn't reach 3:1** (1.47:1 light, 2.35:1 dark) — I improved it from the original 1.26:1 but stopped short deliberately; 3:1 hairlines are visually heavy and the table stays fully readable without them. Worth a second opinion if rows need to read as grouped.
- **I could not take screenshots** to eyeball the result — snap-confined Chrome can't write to any path in this environment. I verified numerically instead, which I'd argue is stronger evidence for these two symptoms, but it does mean nobody has actually *looked* at it. Worth a glance on your phone.

Three pre-existing issues I found but did **not** change, since they're outside what you asked for:

- `app.js` never updates `.hint`, so the page says "Showing 0 orders" while rendering 4 orders.
- `Export CSV`, `New order` and `Refund` are all `.primary` — three competing primary buttons, which is likely not what you want in a phone-sized header.
- Order status is signalled by colour alone (`td.status`), so `paid`/`refunded`/`pending`/`failed` are indistinguishable to anyone who can't separate those hues.
```

## With skill

Skill loaded: yes, `→ Skill "frontend"` on line 4 of the run.

```text
Stress data at 320px — empty, 200 rows, and a 70-char unbroken token: **0 overflow** in each. The table doesn't even need to scroll for normal data.

Screenshots in `/tmp/opencode/shots/`: `after-375-light/dark.png`, `after-900-light/dark.png`. Before/after at 375px dark went from "2 columns, no buttons visible" to everything on screen.

**Caveat:** no axe/Lighthouse pass — the browser MCP tool wasn't connected this session and there's no `node` on the box for `eslint-plugin-jsx-a11y`. Contrast is computed and every state is rendered, but the automated audit itself did not run.

Left alone (out of scope — say the word)

- **`Showing 0 orders` is a bug.** It's hardcoded in `index.html`; there are 4 rows. Needs an `app.js` change.
- **Status is colour-only.** I kept the colour but it still fails for colour-blind users; needs a text or shape cue.
- **All three buttons are `.primary`** — no visual hierarchy between Export / New / Refund. That's a design call, not a bug fix.
- **No empty/loading/error states** for the table.
```

## Verdict

Added: the skill's skipped-states and per-control lists turned into checks the
baseline never ran, so the run measured overflow and AA contrast at six widths in
both themes against empty data, 200 rows and a 70-character unbroken token, and
delivered screenshots as the artifact instead of "should be fine".
Still wrong: the skill's own accessibility gate never ran (no axe, no
`eslint-plugin-jsx-a11y`), and it filed "no empty/loading/error states" under out
of scope, which is the one thing step 4 of the body requires.
