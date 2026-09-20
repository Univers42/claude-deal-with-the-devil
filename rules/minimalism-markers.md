# Minimalism in comments, names and docs

*The ladder, applied to words. A comment that restates the code is not free.*

It is one more thing that goes stale and one more thing to read.

## Comments explain WHY, never WHAT

The code already says what it does. A comment earns its place by carrying the **reason**
this approach and not the obvious one, the **trick**, or — best of all — **the bug that
motivated it, with the measurement that proved it**.

```go
// BAD  — restates the line below it
// increment the counter
count++

// GOOD — carries what the code cannot
// Bounded at 4: above that the kernel silently drops our netlink
// messages (measured on 5.15, 6/6 runs).
const maxWorkers = 4
```

Block comments go **before** a function or logic block, not trailing. A file header
states what the file is for and the constraint that shaped it — and changes in the same
commit as the behaviour. A header that is no longer true is worse than none.

## Delete on sight

Commented-out code (git has it) · a `TODO` with no linked issue · a comment repeating
the function name · a docstring re-listing what the signature declares · section banners
in a file small enough not to need them · changelog comments (`git blame` exists).

## Names carry the weight comments would

A good name deletes a comment — prefer renaming to explaining. Names describe
**behaviour**, not implementation: `pending_writes`, not `int_list`. No abbreviation the
reader must decode. One vocabulary per codebase — pick `fetch` or `get` and never mix
them. A boolean reads as an assertion: `is_expired`, `has_quorum`.

## Docs

One source of truth per concept; link rather than restate. No filler — "simply", "just",
"easily", "powerful", "seamless", "robust". Examples are copied from passing tests or
pasted output, never composed (`agents/documenter.md`, the `doc-sync` skill). Say what
it does **not** do; a page with only a happy path is marketing.

## The one mandatory comment

Any heuristic, sampler, estimate, timeout or cache carries a `Ponytail:` line naming
what it gets wrong (`rules/ponytail.md`). That one is required rather than earned.
