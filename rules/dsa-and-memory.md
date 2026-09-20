# Data structures, algorithms, memory

*Pick the optimal data structure and algorithm; pool allocations. Rust manages its own.*

Correctness first, then the right structure, then the right algorithm. The data
structure is a design decision made before the code, not discovered after.
`minimalism-ladder.md` decides WHEN speed beats simplicity; this rule decides WHAT
to reach for.

## Pick the structure for the access pattern

- **Sequential / index** → array / slice / `Vec`. Contiguous, cache-friendly. The default.
- **Key lookup** → hash map — O(1) average. But for small N (< ~20) a flat slice scan
  is faster and allocates less.
- **Membership** → set. Not a map-to-bool, not a list with `contains`.
- **Work at the ends** → queue / deque / ring buffer. Not shifting an array.
- **Always need the extreme** → heap / priority queue. Not re-sorting each time.
- **Ordered range scan** → balanced tree, or sorted slice + binary search.
- **Prefix / autocomplete** → trie. **Relations** → graph + the right traversal.
- Name the access pattern first; the structure follows from it.

## Pick the algorithm by complexity

- State the Big-O before coding. If a lower rung of the ladder is worse asymptotically
  on data that grows, take the better algorithm.
- No O(n²) on unbounded input. No linear scan where the data is already indexed.
- Sort once and reuse the order; don't re-sort in a loop.
- Measure before micro-optimizing (`agents/benchmarker.md`) — but never ship a
  known-worse complexity class on growing data.

## Memory — pool the high-churn allocations

- **Pool what churns.** Per-request buffers, parse scratch, short-lived high-turnover
  objects → a pool, not a fresh allocation each time.
  - Go: `sync.Pool` (see `rules/refactor-go.md`). C: arena / freelist / slab.
    TS/JS: reuse buffers and `TypedArray`s; reuse objects on hot paths.
- **Size up front.** Known capacity → pre-allocate (`make([]T, 0, n)`,
  `Vec::with_capacity`, geometric `realloc`). Growing by one in a hot loop is a bug.
- **Every allocation has an owner and a free path** (already in `refactor-common.md`).
- **Rust is the exception.** Ownership, borrowing, and RAII manage lifetimes — do not
  hand-roll pools to fight the borrow checker. Restructure lifetimes first; reach for
  an arena (`bumpalo`) only when a profiler proves allocation is the bottleneck.
