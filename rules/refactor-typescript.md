---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# TypeScript Refactoring

## Types are the point — don't opt out of them

- **No `any`.** Use `unknown` and narrow. An `any` that must stay carries an issue link
  and a one-line reason, like any suppression (`rules/quality-bar.md`).
- No `as` to silence the compiler. A cast is a claim you are right and the checker is
  wrong; prove it with a type guard instead. `as const` and `satisfies` are fine.
- No non-null `!`. If it cannot be null, the type should say so; if it can, handle it.
- `strict: true`, plus `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`,
  `noImplicitOverride`, `noFallthroughCasesInSwitch`. `arr[i]` is `T | undefined` and
  that is correct.
- Model the domain so illegal states are unrepresentable: a discriminated union beats
  four optional fields and a comment explaining which combinations are valid.
- Validate anything crossing the boundary at runtime — `zod`/`valibot` on API input,
  env vars and parsed JSON. A TypeScript type is erased at runtime; it is documentation
  the compiler checks, not a guard.

## Structure

- Max 40 lines per function; max 4 parameters, then an options object.
- Named exports only. A default export renames itself at every import site.
- No barrel `index.ts` re-exporting a whole tree — it breaks tree-shaking and creates
  import cycles. Import from the module.
- One concern per file; a file over 300 lines is at least two modules.
- `readonly` on anything that is not mutated, arrays included (`readonly T[]`).

## Async

- Every promise is awaited or explicitly `void`-ed. A floating promise swallows its
  rejection — `@typescript-eslint/no-floating-promises` catches it, keep it on.
- `Promise.all` for independent work; sequential `await` in a loop is a serial
  bottleneck unless order matters. `Promise.allSettled` when one failure must not
  cancel the rest.
- No `async` on a function that never awaits.
- Errors in `catch` are `unknown`. Narrow before reading `.message`.

## React and the DOM (`.tsx`)

- The dependency array is complete. Disabling `react-hooks/exhaustive-deps` is a bug
  report, not a fix.
- Derive during render instead of syncing with an effect. Most `useEffect` that sets
  state is a computed value in disguise.
- Every effect that subscribes, times or fetches returns its cleanup.
- Stable keys from data identity, never the array index.
- Accessibility is part of correctness, not polish: semantic elements before
  `role`, a label on every input, focus managed on route and dialog changes, and
  contrast that passes (`rules/quality-bar.md` layer 6, and the `frontend` skill).

## Dependencies

- Check `package.json` before adding anything — the project probably already has a
  date library, a fetch wrapper and a validator (`rules/minimalism-ladder.md` rung 4).
- `date-fns`/`Temporal` over moment; native `fetch` over axios in a modern runtime;
  `structuredClone` over a deep-clone dependency.
- A dependency used for one function gets inlined.

## After refactoring

- `tsc --noEmit` — zero errors.
- `eslint . --max-warnings 0` with `@typescript-eslint` strict-type-checked, plus
  `jsx-a11y` for anything rendered.
- `prettier --check .`
- The detected test runner green (`rules/test-frameworks.md` — Vitest for new projects,
  Jest where it already is).
- `npm audit --audit-level=high` / `osv-scanner` — no known-vuln dependency.
