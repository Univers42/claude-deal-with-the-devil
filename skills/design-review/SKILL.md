---
name: design-review
description: >
  Judge an interface the way a design engineer does — hierarchy, rhythm, type, states,
  and the empty/loading/error cases nobody built. Names what is wrong and why, not "make
  it pop". Auto-triggers on: "review this design", "does this look right", "improve the
  UI", "critique this", "the design feels off", "make this look better"
allowed-tools: Read, Edit, Grep, Glob, Bash
---

# Design review

"It looks off" is a real observation with a findable cause. The cause is almost always
one of five things, and none of them is taste. Find which, name it, and give the
smallest change that fixes it.

Pairs with `frontend` (how to build it) and `browser-testing` (see it running before
judging it).

## 1. Hierarchy — can you find the one thing?

Squint at it, or blur it. The most important element should still be the most
prominent. If three things compete, the user reads none of them.

- **One primary action per view.** Two primary buttons means neither is.
- Emphasis comes from **size, weight and space** before colour. Colour is the weakest
  signal and the one people reach for first.
- De-emphasise the secondary rather than shouting the primary. Most "make it pop" is
  really "quiet everything else".
- Reading order should match importance. In a form, the label is not the hero.

## 2. Rhythm — is the spacing saying anything?

Spacing communicates grouping. Wrong spacing is the most common cause of "off".

- **Related things are closer than unrelated things.** A label 16px from its input and
  8px from the *next* input is actively lying about the structure.
- One spacing scale, used consistently. Values off the scale (13px, 27px) read as
  sloppy even when nobody can say why.
- **Alignment: pick an edge and hold it.** Mixed left/centre within a block is the
  single most visible amateur tell.
- Consistent gutters; consistent vertical rhythm between sections.

## 3. Type — is it readable before it is pretty?

- **45–75 characters** per line for body text. Full-width paragraphs on a desktop are
  unreadable and extremely common.
- Line height ~1.5 for body, tighter for headings. Long lines need more.
- **Two or three sizes, not seven.** A scale, from tokens.
- Two weights are usually enough. Weight carries hierarchy better than size does.
- Body text at full contrast; muted is for genuinely secondary content. Grey body text
  is a contrast failure wearing a style.

## 4. States — the half that does not exist yet

This is where most reviews find the real work. For every view:

**empty** (first-run — and it is an onboarding opportunity, not an apology) ·
**loading** (skeleton at the real size, so nothing jumps) · **error** (what failed and
what they can do — not "Something went wrong") · **partial** · **too much** (200 rows,
a 60-character unbroken string, a name in a language you did not test)

For every control: default · hover · **focus-visible** · active · disabled · selected.
A disabled button with no explanation is a dead end; say why it is disabled.

## 5. Consistency — is this component already in here?

- Same concept, same appearance, everywhere. Two card styles means a decision was never
  made.
- Is this a new component, or a variant of an existing one? Almost always the latter
  (`rules/library-first.md`, `.claude/tools/dupes.sh`).
- Tokens, not literals. A hardcoded colour is a redesign that will cost a month
  (`skills/frontend/reference.md`).
- Voice: sentence case or title case, "Delete" or "Remove" — pick one and hold it.

## 6. Check it running, at real sizes

Do not review a design from the source. Use `browser-testing`: render it at ~375, ~768
and ~1440, in both themes, with real-length content. Most problems appear only at a
width you did not design at, or with a name longer than "Jane".

Accessibility is part of the review, not a later pass (`skills/frontend/a11y.md`).

## Report

| Issue | Where | Principle | Smallest fix |
|---|---|---|---|

- Lead with the one change that improves it most — there is usually a single dominant
  problem, and fixing it resolves several symptoms.
- Cite the principle, never taste. "Label is closer to the next field than to its own
  input" is actionable; "feels cramped" is not.
- Say what is **working**. A review that only subtracts gets discounted.
- Name the states that do not exist yet — that is the largest finding in most reviews.
