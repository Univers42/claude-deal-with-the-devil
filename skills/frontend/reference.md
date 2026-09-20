# Frontend reference — tokens, layout, state

Loaded on demand by the `frontend` skill. Nothing here needs to be in context until you
are actually laying something out.

## Design tokens

One source of truth per axis. A value that appears twice is a token that has not been
named yet.

| Axis | Shape | Why |
|---|---|---|
| Colour | semantic names (`--surface`, `--text-muted`, `--danger`), not literals (`--blue-500`) | a redesign changes the mapping, not 400 call sites |
| Spacing | one scale, 4px or 8px base — `4 8 12 16 24 32 48 64` | arbitrary values are why nothing lines up |
| Type | a scale with paired line-heights, not ad-hoc `font-size` | vertical rhythm survives |
| Radius | 3–4 steps, plus `full` | more than that reads as inconsistency |
| Z-index | a named ladder (`dropdown: 10, sticky: 20, modal: 40, toast: 50`) | `z-index: 99999` is a symptom |
| Motion | 2–3 durations and 2 easings | mixed timings feel broken without looking broken |

Semantic layer on top of the primitive layer: `--danger: var(--red-600)`. Components
reference the semantic name only, so theming is one file.

## Layout

- **Flexbox for one axis, grid for two.** Most "grid" layouts are a wrapping flex row.
- **Let content size itself.** Fixed heights cause overflow the moment the text is
  translated or the font falls back.
- **`gap`, not margins**, for spacing between siblings — no collapse, no last-child
  exception.
- **Intrinsic sizing over breakpoints.** `grid-template-columns:
  repeat(auto-fit, minmax(16rem, 1fr))` adapts continuously; a breakpoint only adapts at
  one width.
- **Container queries** when a component must respond to its container rather than the
  viewport — a card in a sidebar and the same card in a main column.
- **Reserve space for async content** (`aspect-ratio`, skeletons at the real size). Not
  doing this is what causes layout shift.
- **Safe areas** on anything fixed to an edge: `env(safe-area-inset-*)`.

## State

**The four kinds, kept apart:**

1. **Server state** — fetched, cached, refetched, can go stale. Belongs to a data layer
   (React Query, SWR, RTK Query, a loader), never to `useState`.
2. **URL state** — filters, tab, page, sort. Belongs in the URL so it survives reload
   and can be shared. Reaching for `useState` here is the most common mistake.
3. **Local UI state** — is this menu open. Lowest common owner, and usually much lower
   than people put it.
4. **Form state** — the library the project already uses, with schema validation
   (`zod`/`valibot`) shared with the server's own check.

**Rules that follow from that:**

- Colocate state with its consumer; lift only when a second consumer appears.
- Derive, don't duplicate. Two pieces of state that must agree will eventually disagree.
- A context that changes often re-renders every consumer — split by update frequency.
- Keys come from data identity, never the array index.
- Every effect that subscribes, times, or fetches returns its cleanup.
- `useMemo`/`useCallback` after a profiler says so, not before (`minimalism-ladder`).

## Performance, in the order that matters

1. **Ship less.** Route-level code splitting, then component-level. Check the bundle
   before optimising renders — it is almost always the bigger number.
2. **Images.** Correct format (AVIF/WebP), correct dimensions, `loading="lazy"` below
   the fold, explicit `width`/`height` to stop layout shift.
3. **Fonts.** `font-display: swap`, preload the one face above the fold, and give every
   custom face a real fallback stack.
4. **Lists.** Virtualize past a few hundred rows — not before.
5. **Renders.** Now profile. Fix what the profiler names, and cite the number
   (`agents/benchmarker.md`).

Budget it up front with the `perf-budget` skill; LCP, CLS and INP are the ones users
feel.
